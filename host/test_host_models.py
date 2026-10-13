import unittest

from golden import sobel_interior, threshold, xor_checksum
from packet_codec import FRAME_BYTES, PACKET_BYTES, PACKETS_PER_FRAME, assemble_frame, pack_packet, split_frame, unpack_packet
from serial_link import READBACK_CMD, READBACK_SYNC, STATUS_SYNC, decode_status, encode_frame, read_frame


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


if __name__ == "__main__":
    unittest.main()
