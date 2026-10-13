package vision_pkg;
    localparam int FRAME_WIDTH       = 320;
    localparam int FRAME_HEIGHT      = 240;
    localparam int FRAME_BYTES        = FRAME_WIDTH * FRAME_HEIGHT;
    localparam int PACKETS_PER_FRAME = 64;
    localparam int PACKET_BYTES      = FRAME_BYTES / PACKETS_PER_FRAME;
    localparam int PACKET_ID_W       = 6;
    localparam int FRAME_ID_W        = 16;
    localparam int ADDR_W            = 17;
    localparam int BANK_W             = 1;

    localparam logic [7:0] PROTO_MAGIC = 8'hA5;
endpackage
