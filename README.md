# FPGA Networked Vision Platform

FPGA-based camera receiver and image-processing pipeline. The first hardware target is the Digilent Arty S7-50. A laptop generates prototype image packets so the RTL can be verified before Ethernet or HDMI exist on the board.

## Why the Arty S7-50, not a Basys board

Stay on the Arty S7-50. A Basys 3 is the wrong board for this project.

| Need | Arty S7-50 | Basys 3 |
| --- | --- | --- |
| FPGA | XC7S50 | XC7A35T |
| On-board memory | 256 MB DDR3L | none |
| BRAM | enough for one 320x240 Mono8 pair in a pinch | too tight for double-buffered frames plus processing |
| Ethernet | none; add later via Pmod or a later board | none |
| Video | none; Pmod VGA/HDMI later | native VGA, still no frame DRAM |

The architecture needs a write frame and a display frame. DDR3 on the S7-50 is the reason this stays a real pipeline instead of a BRAM toy. Basys VGA does not compensate for that.

The S7-50 also has no Ethernet PHY and no HDMI PHY. That is acceptable for the current milestone: inject packets from simulation (and later UART), reconstruct frames, process pixels, then add PHYs. If a later milestone needs native Gigabit Ethernet plus HDMI, consider Nexys Video or Genesys 2. Do not buy a Basys 3 for this.

## Prototype image

- 320 x 240 Mono8
- 76,800 bytes per frame
- 64 packets per frame
- 1,200 bytes per packet

## Current milestone

Implemented, simulated, and exercised on the Arty S7-50:

- packet ID tracker with duplicate rejection
- frame-ID policy: late reject, newer-frame abandon, write-bank drop
- pixel writer that places packets at `packet_id * 1200`
- double-buffer swap on a display-ready strobe
- prototype byte-stream parser (`0xA5`, little-endian header, 1200-byte payload)
- streaming threshold with backpressure
- 8x8 Sobel `|Gx|+|Gy|` matching the Python golden model
- full 320x240 reconstruction into a two-bank frame memory
- UART readback of the completed display bank with a byte-for-byte host check
- explicit host-session reset and diagnostic idle beacon
- DDR3 self-test, then a copy of the received 320x240 frame into DDR3 (command `0x46`; 76,800 pixels matched the host)
- 640x480 frames written straight into DDR3 (256 packets; 307,200 pixels matched the host)

Python host tools generate the same 64-packet frames, assemble them, and provide threshold/Sobel golden models.

The regression checks packet tracking, parsing, memory writes, bank swaps, UART
baud tolerance, parser recovery, and ordered UART readback. On hardware, four
successive frames were returned from alternating BRAM banks and all 76,800
pixels in every frame matched the transmitted image.

## Your current hardware path

No VGA or HDMI port is required. The Acer monitor remains connected to the
laptop. The same USB cable used by Vivado exposes the Arty's FTDI serial port:

```text
USB webcam -> Python -> USB-UART -> Arty S7 -> status/readback -> USB-UART -> Python
                  \-> original / threshold / Sobel preview on the laptop
```

The board receives and reconstructs frames, reports completion, and can return
the raw display buffer, the hardware threshold image, or the hardware Sobel
interior. All three matched the host byte for byte on a full 320x240 frame:
76,800 raw or threshold pixels, and 75,684 Sobel pixels. Each packet's payload
CRC32 is checked. A bad CRC is reported as `payload_error`, that packet is not
counted, and the previous complete frame stays on the display path. The board
also compares each new frame with the previous one and can return the
bounding box and center of pixels that changed by more than 16. The host can
freeze that comparison against one captured frame, so a still object stays
inside the box. The preview panes remain
software golden models.

At 1 Mbaud, one 320x240 frame takes about 0.78 seconds on the wire. Start at one
frame per second. This is a bring-up link, not the eventual Gigabit transport.

### LED meanings

- LED 0: heartbeat while idle; solid during UART traffic
- LED 1: all 64 packets accepted (payload CRC included)
- LED 2: completed frame waiting for a safe bank swap
- LED 3: UART, parser, payload, frame, or packet error

## Repository layout

```text
docs/     Frame and buffer policy
rtl/      Synthesizable SystemVerilog
sim/      Self-checking testbenches
host/     Packet codec, golden models, test-frame generator
scripts/  Simulation entry points
```

## Run simulations

```powershell
powershell -File scripts/sim_all.ps1
```

Or run one bench:

```powershell
iverilog -g2012 -o sim/packet_tracker_tb.vvp rtl/packet_tracker.sv sim/packet_tracker_tb.sv
vvp sim/packet_tracker_tb.vvp
```

Host-only:

```powershell
cd host
py -3 -m unittest test_host_models.py
py -3 generate_test_frame.py --out ..\sim\vectors
```

Webcam preview without an FPGA:

```powershell
py -3 -m pip install -r host/requirements.txt
py -3 host/camera_uart.py
```

With the programmed Arty on `COM9`:

```powershell
py -3 host/camera_uart.py --port COM9 --source gradient --fps 1 --readback --process raw
py -3 host/camera_uart.py --port COM9 --source gradient --fps 1 --readback --process threshold
py -3 host/camera_uart.py --port COM9 --source gradient --fps 1 --readback --process sobel
py -3 host/camera_uart.py --port COM9 --source gradient --fps 1 --no-preview --frames 2 --process motion
```

Press `q` or Escape in the preview to stop. Use `--source gradient` when a
webcam is unavailable. `--readback` compares every returned FPGA pixel with
the host result. `--process` selects `raw`, `threshold`, `sobel`, or `motion`.
In motion mode the left preview pane draws the box returned by the FPGA.

## Create the Arty S7-50 Vivado project

From a Vivado Tcl shell, or a terminal where `vivado` is on `PATH`:

```powershell
vivado -mode batch -source scripts/create_vivado_project.tcl
```

Then open `build/vivado/vision_uart.xpr`, run synthesis and implementation, and
generate the bitstream. Hold button 0 to reset. The constraints use the
official Digilent pins: 12 MHz clock F14, FTDI RX/TX V12/R12, buttons, and LEDs.

## Bring-up path

1. Simulation packet source and frame reconstruction (complete)
2. USB-UART receiver, webcam sender, status response, and Arty project (complete)
3. Program and smoke-test the physical board (complete)
4. Read raw frame-buffer pixels back and verify them (complete)
5. Route threshold and Sobel into hardware readback (raw, threshold, and Sobel verified on the board)
6. Check payload CRC32 before a packet counts (verified: bad CRC reports `payload_error` and keeps the previous frame)
7. DDR3 frame buffers and higher-resolution frames (320x240 copy and a 640x480 frame both read back from DDR3 and matched the host)
8. Real Ethernet / GigE Vision on PHY-equipped hardware
9. Optional direct display hardware

A soft CPU is intentionally outside the near-term plan.

Each block stays behind a narrow streaming interface so board-specific clock, pin, and PHY work does not leak into the packet and pixel logic.
