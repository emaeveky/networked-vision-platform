"""Prototype camera packet codec used before a real GigE Vision stack."""

from __future__ import annotations

import struct
import zlib
from collections.abc import Iterable

MAGIC = 0xA5
FRAME_WIDTH = 320
FRAME_HEIGHT = 240
FRAME_BYTES = FRAME_WIDTH * FRAME_HEIGHT
PACKETS_PER_FRAME = 64
PACKET_BYTES = FRAME_BYTES // PACKETS_PER_FRAME
HEADER = struct.Struct("<BHBH")  # magic, frame_id, packet_id, payload_len


def crc32(payload: bytes) -> int:
    return zlib.crc32(payload) & 0xFFFFFFFF


def pack_packet(frame_id: int, packet_id: int, payload: bytes, *, limit: int = PACKETS_PER_FRAME) -> bytes:
    if not 0 <= packet_id < limit:
        raise ValueError(f"packet_id {packet_id} is out of range")
    if len(payload) != PACKET_BYTES:
        raise ValueError(f"payload must be {PACKET_BYTES} bytes")
    header = HEADER.pack(MAGIC, frame_id, packet_id, len(payload))
    return header + payload + struct.pack("<I", crc32(payload))


def unpack_packet(blob: bytes) -> tuple[int, int, bytes]:
    magic, frame_id, packet_id, payload_len = HEADER.unpack(blob[: HEADER.size])
    if magic != MAGIC:
        raise ValueError("bad magic")
    payload = blob[HEADER.size : HEADER.size + payload_len]
    (got_crc,) = struct.unpack("<I", blob[HEADER.size + payload_len :])
    if len(payload) != payload_len:
        raise ValueError("truncated payload")
    if crc32(payload) != got_crc:
        raise ValueError("crc mismatch")
    return frame_id, packet_id, payload


def split_image(frame_id: int, image: bytes) -> list[bytes]:
    """Split an image whose length is a multiple of 1,200 bytes, up to 256 packets."""
    if len(image) % PACKET_BYTES:
        raise ValueError(f"image length {len(image)} is not a multiple of {PACKET_BYTES}")
    count = len(image) // PACKET_BYTES
    if not 1 <= count <= 256:
        raise ValueError(f"{count} packets is outside 1..256")
    packets = []
    for packet_id in range(count):
        start = packet_id * PACKET_BYTES
        packets.append(
            pack_packet(frame_id, packet_id, image[start : start + PACKET_BYTES], limit=256)
        )
    return packets


def split_frame(frame_id: int, image: bytes) -> list[bytes]:
    if len(image) != FRAME_BYTES:
        raise ValueError(f"image must be {FRAME_BYTES} bytes")
    packets = []
    for packet_id in range(PACKETS_PER_FRAME):
        start = packet_id * PACKET_BYTES
        packets.append(pack_packet(frame_id, packet_id, image[start : start + PACKET_BYTES]))
    return packets


def assemble_frame(packets: Iterable[bytes]) -> bytes:
    image = bytearray(FRAME_BYTES)
    seen = set()
    for blob in packets:
        _frame_id, packet_id, payload = unpack_packet(blob)
        if packet_id in seen:
            continue
        start = packet_id * PACKET_BYTES
        image[start : start + PACKET_BYTES] = payload
        seen.add(packet_id)
    if len(seen) != PACKETS_PER_FRAME:
        raise ValueError("incomplete frame")
    return bytes(image)
