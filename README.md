# FPGA Networked Vision Platform

An FPGA learning project that builds toward a real-time networked camera-to-display pipeline with image processing and on-screen overlays.

## Target hardware

- Digilent Arty S7-50 (`XC7S50-CSGA324`)
- HDMI monitor
- Network camera or laptop-generated packet source during development

The design keeps portable SystemVerilog logic separate from board-specific clock, pin, network, and video interfaces so the laptop simulations can later transfer to the FPGA.

## Current milestone

The first verified block is a 64-packet frame tracker. It:

- records each packet ID received for a frame;
- counts only unique packet IDs;
- reports duplicate packets without counting them twice; and
- marks the frame complete after all 64 unique packets arrive.

The self-checking testbench covers reset, duplicate rejection, and frame completion.

## Repository layout

```text
docs/   Design decisions and frame policy
rtl/    Synthesizable SystemVerilog modules
sim/    SystemVerilog testbenches
```

## Run the current simulation

With Icarus Verilog installed:

```powershell
iverilog -g2012 -o sim/packet_tracker_tb.vvp rtl/packet_tracker.sv sim/packet_tracker_tb.sv
vvp sim/packet_tracker_tb.vvp
```

Expected result:

```text
PASS: packet_tracker accepted 64 unique packets and rejected a duplicate
```

## Long-term direction

The planned platform grows incrementally from packet reception and frame reconstruction into buffering, video timing, HDMI output, and useful real-time image-processing features. Each hardware block will be simulated before it is integrated on the Arty S7-50.
