"""Listen for the FPGA idle beacon, then see whether it notices our bytes.

Beacon layout, every 50 ms while the status reply is idle:
  E7, flags, count
  flags: 0xC0 | {frame_complete, saw_rx, framing_error, parse_error}
  count: 0x80 | rx_byte_count[6:0]
None of those bytes is 0x5A, so this cannot be mistaken for a frame status.
"""

from __future__ import annotations

import sys
import time

from serial_link import BAUD


def beacons(blob: bytes) -> list[dict]:
    found = []
    i = 0
    while i + 2 < len(blob):
        flags = blob[i + 1]
        count = blob[i + 2]
        if blob[i] == 0xE7 and 0xC0 <= flags <= 0xCF and count & 0x80:
            found.append(
                {
                    "frame_complete": bool(flags & 0x08),
                    "saw_rx": bool(flags & 0x04),
                    "framing": bool(flags & 0x02),
                    "parse": bool(flags & 0x01),
                    "count_mod": count & 0x7F,
                }
            )
            i += 3
        else:
            i += 1
    return found


def listen(link, seconds: float) -> bytes:
    deadline = time.monotonic() + seconds
    got = bytearray()
    while time.monotonic() < deadline:
        chunk = link.read(256)
        if chunk:
            got += chunk
    return bytes(got)


def report(label: str, blob: bytes) -> None:
    parsed = beacons(blob)
    print(f"{label}: {len(blob)} bytes, {len(parsed)} beacons", flush=True)
    if blob and not parsed:
        print(f"  raw {blob[:32].hex(' ')}", flush=True)
    if parsed:
        last = parsed[-1]
        rx = sum(1 for b in parsed if b["saw_rx"])
        framing = sum(1 for b in parsed if b["framing"])
        parse = sum(1 for b in parsed if b["parse"])
        print(
            f"  last count_mod={last['count_mod']} "
            f"beacons_with_rx={rx} framing={framing} parse={parse} "
            f"frame_complete={last['frame_complete']}",
            flush=True,
        )


def main() -> None:
    port = sys.argv[1] if len(sys.argv) > 1 else "COM9"
    import serial

    link = serial.Serial(port, BAUD, timeout=0.05, write_timeout=5.0)
    print(f"opened {port} at {link.baudrate}", flush=True)
    time.sleep(0.05)
    link.reset_input_buffer()

    idle = listen(link, 0.4)
    report("before sending", idle)

    payload = bytes([0x55]) * 400
    link.write(payload)
    link.flush()
    print(f"sent {len(payload)} bytes of 0x55", flush=True)

    after = listen(link, 0.4)
    report("after sending", after)
    link.close()

    idle_beacons = beacons(idle)
    after_beacons = beacons(after)
    if not idle_beacons and not after_beacons:
        print(
            "VERDICT: no beacon. Clock is stopped, or the FPGA TX pin is not reaching COM9.",
            flush=True,
        )
    elif not any(b["saw_rx"] for b in after_beacons):
        print(
            "VERDICT: beacon is alive but the FPGA did not see our bytes. RX pin or baud.",
            flush=True,
        )
    elif any(b["framing"] for b in after_beacons):
        print(
            "VERDICT: bytes arrived with framing errors. Baud mismatch.",
            flush=True,
        )
    else:
        print("VERDICT: FPGA saw the bytes with no framing errors.", flush=True)


if __name__ == "__main__":
    main()
