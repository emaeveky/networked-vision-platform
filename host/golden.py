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


def motion_box(
    previous: bytes, current: bytes, width: int, height: int, thresh: int = 16
) -> tuple[bool, int, int, int, int, int]:
    """Inclusive box of pixels whose absolute difference exceeds thresh.

    Matches motion_box RTL. Returns motion, min_x, min_y, max_x, max_y, count.
    count saturates at 65535. An empty result is all zeros.
    """
    min_x = min_y = None
    max_x = max_y = 0
    count = 0
    for y in range(height):
        row = y * width
        for x in range(width):
            if abs(current[row + x] - previous[row + x]) > thresh:
                count += 1
                if min_x is None:
                    min_x = max_x = x
                    min_y = max_y = y
                else:
                    min_x = min(min_x, x)
                    max_x = max(max_x, x)
                    min_y = min(min_y, y)
                    max_y = max(max_y, y)
    if min_x is None:
        return False, 0, 0, 0, 0, 0
    return True, min_x, min_y, max_x, max_y, min(count, 65535)


def xor_checksum(image: bytes) -> int:
    acc = 0
    for pixel in image:
        acc ^= pixel
    return acc
