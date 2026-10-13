# Frame Packet Policy

## Prototype image

The first prototype uses 320 × 240 Mono8 images.

- Each pixel is 1 byte.
- Each frame contains 76,800 bytes.
- Each frame is divided into 64 packets.
- Each packet contains 1,200 image bytes.
- Packet IDs range from 0 through 63.

## Packet metadata

Every packet must eventually contain:

- `frame_id`: identifies which image frame the packet belongs to
- `packet_id`: identifies the packet position within that frame
- `payload_length`: number of valid pixel bytes
- `payload`: image bytes

## Packet acceptance rules

A packet is accepted only when:

1. Its frame ID matches the frame currently being assembled.
2. Its packet ID is within the valid range 0–63.
3. Its payload length is valid.
4. Its packet ID has not already been received.
5. The little-endian CRC32 after the payload matches `zlib.crc32` of those
   1200 bytes. The header is not covered.

A CRC mismatch raises `payload_error` and does not count the packet, so the
frame is not displayed. Pixel bytes may already have been written into the
write bank; a later good copy of that same packet overwrites them. The host
gets one status reply after the link goes idle, with the number of packets
that did check out.

## Duplicate packets

If a packet arrives with a packet ID that was already received:

- Do not increase the unique packet count.
- Do not mark another received-map bit.
- Raise the duplicate-packet status for one clock cycle.
- Record the duplicate in a future duplicate counter.

## Out-of-order packets

Packets do not need to arrive in numerical order.

The FPGA uses the packet ID to calculate the packet's destination:

    byte_address = packet_id × 1,200

For example:

- Packet 0 starts at byte 0.
- Packet 1 starts at byte 1,200.
- Packet 17 starts at byte 20,400.
- Packet 63 starts at byte 75,600.

## Missing packets

A frame is complete only when all 64 unique packet IDs have been received.

If any packet is missing:

- The frame is incomplete.
- The frame must not be displayed.
- The monitor continues displaying the previous complete frame.
- The incomplete-frame counter should increase.

## Late packets

If a packet arrives for an older frame after a newer frame has started:

- Reject the old packet.
- Do not write its pixels into the newer frame.
- Do not update the newer frame's received map.

## Newer frame arrival

The first prototype assembles only one frame at a time.

When a newer frame ID arrives before the current frame is complete:

- Abandon the incomplete current frame.
- Record an incomplete-frame event.
- Clear the received map.
- Start assembling the newer frame.

## Display behavior

The monitor must never wait for the network.

While a new frame is incomplete:

- Continue displaying the previous complete frame.
- Do not display an incomplete frame.
- If no complete frame has ever been received, display a defined blank or error image.

## Frame completion

When the 64th unique packet arrives:

- Set `frame_complete`.
- Mark the frame as ready for later display.
- Do not overwrite the frame while it is being displayed.

## Buffering policy

The eventual system will use separate read and write buffers:

- The read buffer contains the frame currently being displayed.
- The write buffer receives the next frame.
- Buffers swap only at a safe video-frame boundary.
- If no buffer is available, drop the incoming frame rather than corrupting an existing frame.

## Current module limitation

`packet_tracker` still tracks only one received-map. `frame_engine` now owns `frame_id` policy:

- The first accepted packet starts a frame.
- Older `frame_id` values are late and rejected. "Older" is a modular 16-bit
  comparison: up to 32767 frames ahead counts as newer, so the host's
  `0xFFFF -> 0x0000` wrap is a new frame, not a late one.
- A newer `frame_id` abandons an incomplete frame.
- If the write bank is locked after a complete frame, a newer frame is dropped until `double_buffer_ctrl` swaps.

`pixel_writer` currently expects payload bytes on the cycles after the accepted header. Swap must wait until that payload has been written; `vision_core` does not yet stall swap on `busy`.