"""Software golden models for the FPGA image-processing blocks."""

from __future__ import annotations


def threshold(image: bytes, value: int) -> bytes:
    return bytes(255 if pixel > value else 0 for pixel in image)


def sobel_interior(image: bytes, width: int, height: int) -> bytes:
    """|Gx|+|Gy| for interior pixels; matches img_sobel RTL."""

    def pix(x: int, y: int) -> int:
        return image[y * width + x]

    out = bytearray()
    for y in range(1, height - 1):
        for x in range(1, width - 1):
            gx = (
                -pix(x - 1, y - 1)
                + pix(x + 1, y - 1)
                - 2 * pix(x - 1, y)
                + 2 * pix(x + 1, y)
                - pix(x - 1, y + 1)
                + pix(x + 1, y + 1)
            )
            gy = (
                -pix(x - 1, y - 1)
                - 2 * pix(x, y - 1)
                - pix(x + 1, y - 1)
                + pix(x - 1, y + 1)
                + 2 * pix(x, y + 1)
                + pix(x + 1, y + 1)
            )
            mag = abs(gx) + abs(gy)
            out.append(255 if mag > 255 else mag)
    return bytes(out)


def xor_checksum(image: bytes) -> int:
    acc = 0
    for pixel in image:
        acc ^= pixel
    return acc
