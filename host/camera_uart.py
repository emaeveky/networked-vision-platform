"""Preview a webcam and optionally stream 320x240 Mono8 frames to the Arty."""

from __future__ import annotations

import argparse
import time

from golden import motion_box, sobel_interior, threshold
from packet_codec import FRAME_HEIGHT, FRAME_WIDTH, split_image
from serial_link import (
    MotionBox,
    arm_wide,
    capture_background,
    encode_frame,
    open_serial,
    read_ddr_status,
    read_frame,
    read_motion,
    read_status,
    read_wide_done,
)


def wide_gradient(frame_id: int) -> bytes:
    width, height = 640, 480
    return bytes(
        (x + y + frame_id) & 0xFF
        for y in range(height)
        for x in range(width)
    )


def run_wide(args, link, camera) -> None:
    """Send one or more 640x480 frames straight into DDR and check them."""
    import cv2

    frames = args.frames or 1
    deadline = time.monotonic() + 8
    ready = None
    while time.monotonic() < deadline:
        ready = read_ddr_status(link)
        if ready is not None and ready[1]:
            break
        time.sleep(0.05)
    if not ready or not ready[0] or not ready[1]:
        print(f"DDR controller was not ready ({ready})", flush=True)
        return
    for frame_id in range(frames):
        if camera is not None:
            ok, color = camera.read()
            if not ok:
                raise SystemExit("webcam stopped returning frames")
            gray = cv2.cvtColor(color, cv2.COLOR_BGR2GRAY)
            image = cv2.resize(gray, (640, 480)).tobytes()
        else:
            image = wide_gradient(frame_id)
        if not arm_wide(link):
            print(f"frame {frame_id}: DDR wide mode was not armed", flush=True)
            return
        payload = b"".join(split_image(frame_id, image))
        link.reset_input_buffer()
        for offset in range(0, len(payload), 1024):
            link.write(payload[offset : offset + 1024])
        link.flush()
        print(f"frame {frame_id}: sent {len(payload)} bytes, waiting for DDR", flush=True)
        done = read_wide_done(link)
        if done is None or done[1] != 256 or done[2] != 0:
            print(f"frame {frame_id}: wide commit failed ({done})", flush=True)
            return
        print(
            f"frame {done[0]}: DDR accepted {done[1]} packets",
            flush=True,
        )
        if args.readback:
            result = read_frame(link, "wide")
            if result is None:
                print(f"frame {frame_id}: no wide readback", flush=True)
                return
            got_id, got = result
            mismatch = next(
                (i for i, (want, have) in enumerate(zip(image, got)) if want != have),
                None,
            )
            if mismatch is None and len(got) == len(image):
                print(
                    f"frame {got_id}: wide readback verified {len(got)} pixels",
                    flush=True,
                )
            else:
                shown = mismatch if mismatch is not None else 0
                print(
                    f"frame {got_id}: wide readback mismatch at pixel {shown}",
                    flush=True,
                )
                return


def gradient_frame(frame_id: int) -> bytes:
    return bytes(
        (x + y + frame_id) & 0xFF
        for y in range(FRAME_HEIGHT)
        for x in range(FRAME_WIDTH)
    )


def paint_motion(frame, box):
    """Return a copy of a grayscale frame with the motion rectangle in white.

    The source frame is left unchanged, because those bytes may still be the
    image stored for the next comparison.
    """
    import numpy as np

    view = np.array(frame, dtype=np.uint8, copy=True)
    if box is None or not box.motion:
        return view
    height, width = view.shape[:2]
    x0 = min(max(int(box.min_x), 0), width - 1)
    x1 = min(max(int(box.max_x), 0), width - 1)
    y0 = min(max(int(box.min_y), 0), height - 1)
    y1 = min(max(int(box.max_y), 0), height - 1)
    if x1 < x0:
        x0, x1 = x1, x0
    if y1 < y0:
        y0, y1 = y1, y0
    view[y0, x0 : x1 + 1] = 255
    view[y1, x0 : x1 + 1] = 255
    view[y0 : y1 + 1, x0] = 255
    view[y0 : y1 + 1, x1] = 255
    cx = min(max(int(box.cen_x), 0), width - 1)
    cy = min(max(int(box.cen_y), 0), height - 1)
    view[cy, cx] = 255
    if cx > 0:
        view[cy, cx - 1] = 255
    if cx + 1 < width:
        view[cy, cx + 1] = 255
    if cy > 0:
        view[cy - 1, cx] = 255
    if cy + 1 < height:
        view[cy + 1, cx] = 255
    return view


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
        choices=("raw", "threshold", "sobel", "motion", "ddr", "wide"),
        default="raw",
        help="FPGA result: raw, threshold, sobel, the DDR copy, a 640x480 DDR frame, or a motion box",
    )
    parser.add_argument(
        "--lock-background",
        action="store_true",
        help="after the first complete frame, compare later motion to that frame",
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
    previous = bytes(FRAME_WIDTH * FRAME_HEIGHT)
    background = previous
    background_locked = False

    try:
        if args.process == "wide":
            if link is None:
                raise SystemExit("--process wide needs --port")
            run_wide(args, link, camera)
            return
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

            overlay = None
            overlay_name = "software motion"
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
                    if status.packet_count == 64 and args.process == "motion":
                        expected = motion_box(
                            background if background_locked else previous,
                            image,
                            FRAME_WIDTH,
                            FRAME_HEIGHT,
                            16,
                        )
                        got = read_motion(link)
                        if got is None:
                            print(
                                f"frame {frame_id}: no FPGA motion response",
                                flush=True,
                            )
                        elif (
                            got.motion,
                            got.min_x,
                            got.min_y,
                            got.max_x,
                            got.max_y,
                            got.count,
                            got.cen_x,
                            got.cen_y,
                        ) == expected:
                            print(
                                f"frame {got.frame_id}: motion verified "
                                f"x={got.min_x}..{got.max_x} "
                                f"y={got.min_y}..{got.max_y} "
                                f"center=({got.cen_x},{got.cen_y}) "
                                f"count={got.count}",
                                flush=True,
                            )
                        else:
                            print(
                                f"frame {got.frame_id}: motion mismatch "
                                f"got=({got.motion},{got.min_x},{got.min_y},"
                                f"{got.max_x},{got.max_y},{got.count},"
                                f"{got.cen_x},{got.cen_y}) "
                                f"expected={expected}",
                                flush=True,
                            )
                        if got is not None:
                            overlay = got
                            overlay_name = "FPGA motion"
                    elif args.readback and status.packet_count == 64:
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
                    if (
                        args.lock_background
                        and not background_locked
                        and status.packet_count == 64
                    ):
                        if capture_background(link):
                            background = image
                            background_locked = True
                            print(
                                f"frame {frame_id}: background locked",
                                flush=True,
                            )
                        else:
                            print(
                                f"frame {frame_id}: background capture failed",
                                flush=True,
                            )
                    if status.packet_count == 64 and not background_locked:
                        previous = image

            if not args.no_preview:
                shown = gray
                title = "original | threshold | Sobel golden"
                if args.process == "motion":
                    if overlay is None and link is None:
                        found = motion_box(
                            previous, image, FRAME_WIDTH, FRAME_HEIGHT, 16
                        )
                        overlay = MotionBox(frame_id, *found)
                    shown = paint_motion(gray, overlay)
                    title = f"{overlay_name} | threshold | Sobel"
                preview = np.hstack((shown, binary, edges))
                cv2.imshow(title, preview)
                if cv2.waitKey(1) & 0xFF in (27, ord("q")):
                    break

            if link is None and args.process == "motion":
                previous = image

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
