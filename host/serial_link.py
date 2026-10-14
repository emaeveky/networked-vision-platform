"""PC side of the Arty S7 USB-UART prototype link."""

from __future__ import annotations

from dataclasses import dataclass
import time

from packet_codec import split_frame

BAUD = 1_000_000
STATUS_SYNC = 0x5A
STATUS_BYTES = 5
READBACK_CMD = 0x52
THRESHOLD_CMD = 0x54
SOBEL_CMD = 0x45
SESSION_RESET_CMD = 0x53
MOTION_CMD = 0x4D
BG_CMD = 0x42
BG_SYNC = 0xD5
READBACK_COMMANDS = {
    "raw": READBACK_CMD,
    "threshold": THRESHOLD_CMD,
    "sobel": SOBEL_CMD,
}
READBACK_SYNC = 0xD3
MOTION_SYNC = 0xD4
MOTION_BYTES = 18
READBACK_HEADER_BYTES = 6

# Bit order matches error_latch in rtl/arty_s7_uart_top.sv. Flags accumulate
# between status replies, so a flag on frame N may describe damage during
# frame N-1 (for example a frame that never completed and so sent no status).
ERROR_FLAG_NAMES = (
    "duplicate_packet",   # bit 0
    "late_packet",        # bit 1
    "incomplete_frame",   # bit 2
    "dropped_frame",      # bit 3
    "payload_error",      # bit 4
    "parse_error",        # bit 5
    "framing_error",      # bit 6
)


def describe_errors(flags: int) -> str:
    names = [name for bit, name in enumerate(ERROR_FLAG_NAMES) if flags & (1 << bit)]
    return ",".join(names) if names else "none"


@dataclass(frozen=True)
class MotionBox:
    frame_id: int
    motion: bool
    min_x: int
    min_y: int
    max_x: int
    max_y: int
    count: int
    cen_x: int
    cen_y: int


@dataclass(frozen=True)
class FrameStatus:
    frame_id: int
    packet_count: int
    error_flags: int

    @property
    def ok(self) -> bool:
        return self.packet_count == 64 and self.error_flags == 0

    @property
    def errors(self) -> str:
        return describe_errors(self.error_flags)


def encode_frame(frame_id: int, image: bytes) -> bytes:
    """Return exactly the bytes sent over UART for one prototype frame."""
    return b"".join(split_frame(frame_id, image))


def decode_status(blob: bytes) -> FrameStatus:
    if len(blob) != STATUS_BYTES:
        raise ValueError(f"status must be {STATUS_BYTES} bytes")
    if blob[0] != STATUS_SYNC:
        raise ValueError("bad status sync")
    frame_id = blob[1] | (blob[2] << 8)
    return FrameStatus(frame_id, blob[3], blob[4] & 0x7F)


def open_serial(port: str):
    try:
        import serial
    except ImportError as exc:
        raise SystemExit(
            "pyserial is required: py -3 -m pip install -r host/requirements.txt"
        ) from exc
    link = serial.Serial(
        port=port,
        baudrate=BAUD,
        timeout=8.0,
        write_timeout=15.0,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        xonxoff=False,
        rtscts=False,
        dsrdtr=False,
    )
    link.reset_input_buffer()
    link.reset_output_buffer()
    # A new host process starts frame IDs at zero. Explicitly reset only the
    # frame/parser session; the FPGA UART and diagnostic beacon stay alive.
    # Drain any packet left half-received by a crashed previous host. With a
    # fixed 1200-byte payload, 1210 non-magic bytes always return the parser to
    # its magic-search state before the reset command arrives.
    link.write(bytes(1210) + bytes([SESSION_RESET_CMD]))
    link.flush()
    time.sleep(0.03)
    link.reset_input_buffer()
    return link


def read_status(link) -> FrameStatus | None:
    """Scan through noise until a five-byte status response is found."""
    deadline = time.monotonic() + float(getattr(link, "timeout", 8.0) or 8.0)
    while time.monotonic() < deadline:
        first = link.read(1)
        if not first:
            return None
        if first[0] == STATUS_SYNC:
            rest = link.read(STATUS_BYTES - 1)
            if len(rest) != STATUS_BYTES - 1:
                return None
            return decode_status(first + rest)
    return None


def _read_exact(link, size: int) -> bytes | None:
    blob = bytearray()
    while len(blob) < size:
        chunk = link.read(size - len(blob))
        if not chunk:
            return None
        blob.extend(chunk)
    return bytes(blob)


def read_frame(link, kind: str = "raw") -> tuple[int, bytes] | None:
    """Request and receive one FPGA result image.

    kind is "raw", "threshold", or "sobel". Sobel returns only the interior
    pixels produced by the RTL, in the same order as golden.sobel_interior.
    """
    try:
        command = READBACK_COMMANDS[kind]
    except KeyError as exc:
        raise ValueError(f"unknown readback kind {kind}") from exc
    link.reset_input_buffer()
    link.write(bytes([command]))
    link.flush()

    deadline = time.monotonic() + float(getattr(link, "timeout", 8.0) or 8.0)
    while time.monotonic() < deadline:
        first = link.read(1)
        if not first:
            return None
        if first[0] == READBACK_SYNC:
            rest = _read_exact(link, READBACK_HEADER_BYTES - 1)
            if rest is None:
                return None
            frame_id = rest[0] | (rest[1] << 8)
            length = rest[2] | (rest[3] << 8) | (rest[4] << 16)
            payload = _read_exact(link, length)
            if payload is None:
                return None
            return frame_id, payload
    return None


def capture_background(link) -> bool:
    """Freeze the frame on display and use it for later motion comparisons.

    The copy takes a few milliseconds. Returns True when the FPGA reports that
    the frozen frame is armed. A later session reset disarms it.
    """
    link.reset_input_buffer()
    link.write(bytes([BG_CMD]))
    link.flush()

    deadline = time.monotonic() + float(getattr(link, "timeout", 8.0) or 8.0)
    while time.monotonic() < deadline:
        first = link.read(1)
        if not first:
            return False
        if first[0] == BG_SYNC:
            rest = link.read(1)
            if rest == bytes([0x01]):
                return True
            if not rest:
                return False
    return False


def read_motion(link) -> MotionBox | None:
    """Ask for the bounding box of the frame that just became visible."""
    link.reset_input_buffer()
    link.write(bytes([MOTION_CMD]))
    link.flush()

    deadline = time.monotonic() + float(getattr(link, "timeout", 8.0) or 8.0)
    while time.monotonic() < deadline:
        first = link.read(1)
        if not first:
            return None
        if first[0] == MOTION_SYNC:
            rest = _read_exact(link, MOTION_BYTES - 1)
            if rest is None:
                return None
            return MotionBox(
                frame_id=rest[0] | (rest[1] << 8),
                motion=bool(rest[2] & 1),
                min_x=rest[3] | (rest[4] << 8),
                min_y=rest[5] | (rest[6] << 8),
                max_x=rest[7] | (rest[8] << 8),
                max_y=rest[9] | (rest[10] << 8),
                count=rest[11] | (rest[12] << 8),
                cen_x=rest[13] | (rest[14] << 8),
                cen_y=rest[15] | (rest[16] << 8),
            )
    return None
