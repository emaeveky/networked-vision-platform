"""Build a 320x240 Mono8 test frame and fragment it into prototype packets."""

from __future__ import annotations

import argparse
from pathlib import Path

from golden import threshold, xor_checksum
from packet_codec import FRAME_HEIGHT, FRAME_WIDTH, assemble_frame, split_frame


def gradient_frame() -> bytes:
    pixels = bytearray(FRAME_WIDTH * FRAME_HEIGHT)
    for y in range(FRAME_HEIGHT):
        for x in range(FRAME_WIDTH):
            pixels[y * FRAME_WIDTH + x] = (x + y) & 0xFF
    return bytes(pixels)


def write_pgm(path: Path, image: bytes) -> None:
    path.write_bytes(f"P5\n{FRAME_WIDTH} {FRAME_HEIGHT}\n255\n".encode("ascii") + image)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("sim/vectors"))
    parser.add_argument("--frame-id", type=int, default=1)
    args = parser.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    image = gradient_frame()
    packets = split_frame(args.frame_id, image)
    rebuilt = assemble_frame(packets)
    if rebuilt != image:
        raise SystemExit("host assembler failed to reconstruct the generated frame")

    raw_path = args.out / "frame_320x240.raw"
    pgm_path = args.out / "frame_320x240.pgm"
    pkt_path = args.out / "frame_320x240.packets"
    bin_path = args.out / "frame_320x240_thresh.raw"

    raw_path.write_bytes(image)
    write_pgm(pgm_path, image)
    pkt_path.write_bytes(b"".join(packets))
    bin_path.write_bytes(threshold(image, 128))

    print(f"wrote {len(packets)} packets, checksum=0x{xor_checksum(image):02x}")
    print(f"raw={raw_path}")
    print(f"packets={pkt_path}")


if __name__ == "__main__":
    main()
