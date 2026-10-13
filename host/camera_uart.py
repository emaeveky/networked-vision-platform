"""Preview a webcam and optionally stream 320x240 Mono8 frames to the Arty."""

from __future__ import annotations

import argparse
import time

from golden import sobel_interior, threshold
from packet_codec import FRAME_HEIGHT, FRAME_WIDTH
from serial_link import encode_frame, open_serial, read_frame, read_status


def gradient_frame(frame_id: int) -> bytes:
    return bytes(
        (x + y + frame_id) & 0xFF
        for y in range(FRAME_HEIGHT)
        for x in range(FRAME_WIDTH)
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Webcam/test-pattern viewer and Arty S7 UART sender"
    )
    parser.add_argument("--port", help="Windows COM port, for example COM5")
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument(
        "--source", choices=("webcam", "gradient"), default="webcam"
    )
    parser.add_argument("--fps", type=float, default=1.0)
    parser.add_argument(
        "--frames", type=int, default=0, help="stop after this many frames (0 = run until quit)"
    )
    parser.add_argument("--threshold", type=int, default=128)
    parser.add_argument(
        "--no-preview", action="store_true", help="run without an OpenCV window"
    )
    parser.add_argument(
        "--readback",
        action="store_true",
        help="read the FPGA result back and compare every pixel",
    )
    parser.add_argument(
        "--process",
        choices=("raw", "threshold", "sobel"),
        default="raw",
        help="FPGA image returned by --readback",
    )
    args = parser.parse_args()

    if args.fps <= 0:
        parser.error("--fps must be positive")

    try:
        import cv2
        import numpy as np
    except ImportError as exc:
        raise SystemExit(
            "OpenCV and NumPy are required: "
            "py -3 -m pip install -r host/requirements.txt"
        ) from exc

    link = open_serial(args.port) if args.port else None
    camera = None
    if args.source == "webcam":
        camera = cv2.VideoCapture(args.camera)
        if not camera.isOpened():
            raise SystemExit(f"could not open webcam index {args.camera}")

    frame_id = 0
    period = 1.0 / args.fps

    try:
        while True:
            started = time.monotonic()
            if camera is not None:
                ok, color = camera.read()
                if not ok:
                    raise SystemExit("webcam stopped returning frames")
                gray = cv2.cvtColor(color, cv2.COLOR_BGR2GRAY)
                gray = cv2.resize(gray, (FRAME_WIDTH, FRAME_HEIGHT))
                image = gray.tobytes()
            else:
                image = gradient_frame(frame_id)
                gray = np.frombuffer(image, dtype=np.uint8).reshape(
                    FRAME_HEIGHT, FRAME_WIDTH
                )

            binary = np.frombuffer(
                threshold(image, args.threshold), dtype=np.uint8
            ).reshape(FRAME_HEIGHT, FRAME_WIDTH)

            # The RTL emits only valid 3x3 centers. Pad for an equally sized preview.
            edges = np.zeros((FRAME_HEIGHT, FRAME_WIDTH), dtype=np.uint8)
            edges[1:-1, 1:-1] = np.frombuffer(
                sobel_interior(image, FRAME_WIDTH, FRAME_HEIGHT), dtype=np.uint8
            ).reshape(FRAME_HEIGHT - 2, FRAME_WIDTH - 2)

            if link is not None:
                payload = encode_frame(frame_id, image)
                # Drop anything left over so a status reply is never mistaken
                # for the previous frame's.
                link.reset_input_buffer()
                # FTDI likes modest chunks more than one 77 KB write.
                for offset in range(0, len(payload), 1024):
                    link.write(payload[offset : offset + 1024])
                link.flush()
                print(
                    f"frame {frame_id}: sent {len(payload)} bytes, waiting for status",
                    flush=True,
                )
                status = read_status(link)
                if status is None:
                    print(f"frame {frame_id}: no FPGA status response", flush=True)
                else:
                    print(
                        f"frame {status.frame_id}: packets={status.packet_count} "
                        f"errors=0x{status.error_flags:02x} ({status.errors})",
                        flush=True,
                    )
                    if args.readback and status.packet_count == 64:
                        if args.process == "threshold":
                            expected = threshold(image, args.threshold)
                        elif args.process == "sobel":
                            expected = sobel_interior(
                                image, FRAME_WIDTH, FRAME_HEIGHT
                            )
                        else:
                            expected = image
                        result = read_frame(link, args.process)
                        if result is None:
                            print(
                                f"frame {frame_id}: no FPGA readback response",
                                flush=True,
                            )
                        else:
                            readback_id, readback = result
                            mismatch = next(
                                (
                                    index
                                    for index, (want, got) in enumerate(
                                        zip(expected, readback)
                                    )
                                    if want != got
                                ),
                                None,
                            )
                            if (
                                mismatch is None
                                and len(readback) == len(expected)
                            ):
                                print(
                                    f"frame {readback_id}: {args.process} "
                                    f"readback verified {len(readback)} pixels",
                                    flush=True,
                                )
                            else:
                                shown = mismatch if mismatch is not None else 0
                                got = (
                                    readback[shown]
                                    if shown < len(readback)
                                    else None
                                )
                                print(
                                    f"frame {readback_id}: {args.process} "
                                    f"readback mismatch at pixel {shown}: "
                                    f"expected=0x{expected[shown]:02x} got={got} "
                                    f"lengths={len(expected)}/{len(readback)}",
                                    flush=True,
                                )

            if not args.no_preview:
                preview = np.hstack((gray, binary, edges))
                cv2.imshow("original | threshold | Sobel golden", preview)
                if cv2.waitKey(1) & 0xFF in (27, ord("q")):
                    break

            frame_id = (frame_id + 1) & 0xFFFF
            if args.frames and frame_id >= args.frames:
                break
            time.sleep(max(0.0, period - (time.monotonic() - started)))
    finally:
        if camera is not None:
            camera.release()
        if link is not None:
            link.close()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
