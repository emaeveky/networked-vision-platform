import unittest

from golden import motion_box, sobel_interior, threshold, xor_checksum
from packet_codec import FRAME_BYTES, PACKET_BYTES, PACKETS_PER_FRAME, assemble_frame, pack_packet, split_frame, unpack_packet
from serial_link import (
    MOTION_CMD,
    MOTION_SYNC,
    READBACK_CMD,
    READBACK_SYNC,
    STATUS_SYNC,
    decode_status,
    encode_frame,
    read_frame,
    read_motion,
)


class FakeSerial:
    def __init__(self, incoming: bytes) -> None:
        self.incoming = bytearray(incoming)
        self.written = bytearray()

    def reset_input_buffer(self) -> None:
        pass

    def write(self, blob: bytes) -> int:
        self.written.extend(blob)
        return len(blob)

    def flush(self) -> None:
        pass

    def read(self, size: int) -> bytes:
        blob = bytes(self.incoming[:size])
        del self.incoming[:size]
        return blob


class PacketCodecTests(unittest.TestCase):
    def test_round_trip_one_packet(self) -> None:
        payload = bytes((i + 3) & 0xFF for i in range(PACKET_BYTES))
        blob = pack_packet(4, 9, payload)
        frame_id, packet_id, got = unpack_packet(blob)
        self.assertEqual((frame_id, packet_id, got), (4, 9, payload))

    def test_split_and_assemble_shuffled(self) -> None:
        image = bytes((x * 17) & 0xFF for x in range(320 * 240))
        packets = split_frame(2, image)
        self.assertEqual(len(packets), PACKETS_PER_FRAME)
        shuffled = packets[::-1]
        self.assertEqual(assemble_frame(shuffled), image)

    def test_threshold_matches_rtl_rule(self) -> None:
        image = bytes([0, 128, 129, 255])
        self.assertEqual(threshold(image, 128), bytes([0, 0, 255, 255]))
        self.assertEqual(xor_checksum(image), 0 ^ 128 ^ 129 ^ 255)

    def test_sobel_interior_has_no_border(self) -> None:
        image = bytes((i * 3) & 0xFF for i in range(8 * 8))
        out = sobel_interior(image, 8, 8)
        self.assertEqual(len(out), 6 * 6)
        self.assertNotEqual(out, bytes(len(out)))

    def test_uart_frame_and_status_formats(self) -> None:
        image = bytes((i * 5) & 0xFF for i in range(320 * 240))
        stream = encode_frame(0x1234, image)
        # Header is magic(1) + frame_id(2) + packet_id(1) + length(2).
        self.assertEqual(len(stream), 64 * (6 + 1200 + 4))

        status = decode_status(bytes([STATUS_SYNC, 0x34, 0x12, 64, 0]))
        self.assertEqual(status.frame_id, 0x1234)
        self.assertTrue(status.ok)
        self.assertEqual(status.errors, "none")

        # 0x24 is what the FPGA reports after a dropped byte: the parser
        # scanned through garbage (bit 5) and the previous frame never
        # completed (bit 2).
        damaged = decode_status(bytes([STATUS_SYNC, 0x01, 0x00, 64, 0x24]))
        self.assertFalse(damaged.ok)
        self.assertEqual(damaged.errors, "incomplete_frame,parse_error")

    def test_uart_frame_readback(self) -> None:
        image = bytes((i * 11 + 7) & 0xFF for i in range(FRAME_BYTES))
        header = bytes(
            [
                READBACK_SYNC,
                0x34,
                0x12,
                FRAME_BYTES & 0xFF,
                (FRAME_BYTES >> 8) & 0xFF,
                (FRAME_BYTES >> 16) & 0xFF,
            ]
        )
        link = FakeSerial(bytes([0xE7, 0xC0, 0x80]) + header + image)
        result = read_frame(link)
        self.assertEqual(link.written, bytes([READBACK_CMD]))
        self.assertEqual(result, (0x1234, image))

    def test_motion_box_ignores_small_changes(self) -> None:
        previous = bytes(8 * 8)
        current = bytearray(previous)
        current[2 * 8 + 3] = 16
        current[4 * 8 + 5] = 17
        current[4 * 8 + 6] = 40
        self.assertEqual(
            motion_box(previous, bytes(current), 8, 8, 16),
            (True, 5, 4, 6, 4, 2, 5, 4),
        )
        self.assertEqual(
            motion_box(previous, previous, 8, 8, 16),
            (False, 0, 0, 0, 0, 0, 0, 0),
        )

    def test_motion_reply_decode(self) -> None:
        payload = bytes(
            [
                MOTION_SYNC,
                0x02,
                0x00,
                1,
                10,
                0,
                20,
                0,
                11,
                0,
                20,
                0,
                2,
                0,
                4,
                0,
                5,
                0,
            ]
        )
        link = FakeSerial(payload)
        got = read_motion(link)
        self.assertEqual(link.written, bytes([MOTION_CMD]))
        self.assertEqual(got.frame_id, 2)
        self.assertEqual(
            (got.motion, got.min_x, got.min_y, got.max_x, got.max_y, got.count, got.cen_x, got.cen_y),
            (True, 10, 20, 11, 20, 2, 4, 5),
        )

    def test_paint_motion_draws_border_without_changing_source(self) -> None:
        import numpy as np
        from camera_uart import paint_motion
        from serial_link import MotionBox

        frame = np.zeros((8, 8), np.uint8)
        original = frame.copy()
        painted = paint_motion(frame, MotionBox(1, True, 2, 3, 5, 6, 4, 4, 4))
        self.assertTrue(np.array_equal(frame, original))
        self.assertEqual(int(painted[3, 2]), 255)
        self.assertEqual(int(painted[3, 5]), 255)
        self.assertEqual(int(painted[6, 5]), 255)
        self.assertEqual(int(painted[4, 4]), 255)
        self.assertEqual(int(painted[5, 3]), 0)
        self.assertEqual(int(painted[3, 1]), 0)
        still = paint_motion(frame, MotionBox(1, False, 0, 0, 0, 0, 0, 0, 0))
        self.assertTrue(np.array_equal(still, frame))


if __name__ == "__main__":
    unittest.main()
