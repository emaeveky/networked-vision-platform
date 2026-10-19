module arty_s7_uart_top #(
    // Hardware sends a short beacon while idle so a silent status reply can be
    // told apart from a dead clock, a stuck reset, or a deaf receiver.
    // Simulation turns this off; the beacon bytes are not part of the protocol.
    parameter bit ENABLE_BEACON = 1'b1,
    parameter int READBACK_BYTES = 76_800,
    parameter int FRAME_W = 320,
    parameter int FRAME_H = 240
) (
    input  logic       CLK12MHZ,
    input  logic       clk100 = 1'b0,
    input  logic [3:0] btn,
    input  logic       uart_txd_in,
    output logic       uart_rxd_out,
    output logic [3:0] led,
    inout  wire [15:0] ddr3_dq,
    inout  wire [1:0]  ddr3_dqs_n,
    inout  wire [1:0]  ddr3_dqs_p,
    output wire [13:0] ddr3_addr,
    output wire [2:0]  ddr3_ba,
    output wire        ddr3_ras_n,
    output wire        ddr3_cas_n,
    output wire        ddr3_we_n,
    output wire        ddr3_reset_n,
    output wire [0:0]  ddr3_ck_p,
    output wire [0:0]  ddr3_ck_n,
    output wire [0:0]  ddr3_cke,
    output wire [0:0]  ddr3_cs_n,
    output wire [1:0]  ddr3_dm,
    output wire [0:0]  ddr3_odt
);

    localparam int CLOCK_HZ = 12_000_000;
    localparam int BAUD     = 1_000_000;
    localparam logic [7:0] READBACK_CMD  = 8'h52;
    localparam logic [7:0] THRESHOLD_CMD = 8'h54;
    localparam logic [7:0] SOBEL_CMD     = 8'h45;
    localparam logic [7:0] SESSION_RESET_CMD = 8'h53;
    localparam logic [7:0] MOTION_CMD = 8'h4D;
    localparam logic [7:0] BG_CMD = 8'h42;
    localparam logic [7:0] DDR_CMD = 8'h44;
    localparam logic [7:0] DDR_FRAME_CMD = 8'h46;
    localparam logic [7:0] READBACK_SYNC = 8'hD3;
    localparam logic [7:0] MOTION_SYNC = 8'hD4;
    localparam logic [7:0] BG_SYNC = 8'hD5;
    localparam logic [7:0] DDR_SYNC = 8'hD6;
    localparam int SOBEL_BYTES = (FRAME_W - 2) * (FRAME_H - 2);
    // After a bad CRC, wait until the host has stopped sending before reporting
    // the final packet count. One millisecond is far longer than the gap
    // between back-to-back UART bytes and far shorter than the host timeout.
    localparam int CRC_IDLE_CYCLES = CLOCK_HZ / 1000;

    logic rx_valid;
    logic [7:0] rx_data;
    logic framing_error;

    logic hdr_valid;
    logic [15:0] frame_id;
    logic [5:0] packet_id;
    logic [10:0] payload_len;
    logic data_valid;
    logic [7:0] data;
    logic data_last;
    logic parse_error;
    logic crc_ok;
    logic crc_error;
    logic parser_idle;
    logic crc_fail_seen;
    logic [13:0] crc_idle;
    wire crc_status_fire = crc_fail_seen && parser_idle && !rx_valid
        && (crc_idle == CRC_IDLE_CYCLES[13:0]);

    logic pkt_accept;
    logic duplicate_packet;
    logic late_packet;
    logic incomplete_frame;
    logic dropped_frame;
    logic payload_error;
    logic frame_complete;
    logic wr_allowed;
    logic swap_pulse;
    logic pending_display;
    logic rd_bank;
    logic wr_bank;
    logic [15:0] current_frame_id;
    logic [6:0] unique_packet_count;
    logic [16:0] write_count;
    logic mem_we;
    logic [16:0] mem_addr;
    logic [7:0] mem_wdata;
    logic rd_en;
    logic [16:0] rd_addr;
    logic [7:0] rd_data;

    logic [22:0] activity_count;
    logic [6:0] error_latch;
    logic [6:0] status_errors;

    logic [7:0] tx_data;
    logic tx_ready;
    logic status_active;
    logic status_pending;
    logic [2:0] status_index;

    logic beacon_active;
    logic [1:0] beacon_index;
    logic [19:0] beacon_div;
    logic [6:0] rx_count_mod;
    logic saw_rx;
    logic saw_framing;
    logic saw_parse;
    logic [7:0] beacon_flags;
    logic [7:0] beacon_count;
    logic readback_active;
    logic readback_pending;
    logic motion_active;
    logic motion_pending;
    logic [4:0] motion_index;
    logic [15:0] motion_frame;
    logic motion_flag;
    logic [8:0] motion_min_x;
    logic [8:0] motion_max_x;
    logic [7:0] motion_min_y;
    logic [7:0] motion_max_y;
    logic [15:0] motion_count;
    logic [8:0] motion_cen_x;
    logic [7:0] motion_cen_y;
    logic bg_start;
    logic bg_ack_active;
    logic bg_ack_pending;
    logic bg_ack_index;
    logic ddr_reply_active;
    logic ddr_reply_pending;
    logic ddr_reply_index;
    logic [7:0] ddr_reply_byte;
    logic ddr_stream;
    logic copy_start;
    logic copy_busy;
    logic copy_rd_en;
    logic [16:0] copy_rd_addr;
    logic [7:0] copy_byte;
    logic copy_valid;
    logic copy_last;
    logic copy_take;
    logic ddr_hold_valid;
    logic ddr_hold_last;
    logic ddr_calib;
    logic ddr_done;
    logic ddr_pass;
    logic bg_busy;
    logic bg_armed;
    logic bg_done;
    logic bg_rd_en;
    logic [16:0] bg_rd_addr;
    logic [7:0] bg_sample;
    logic readback_payload;
    logic [2:0] readback_header_index;
    logic [16:0] readback_addr;
    logic [1:0] readback_prefetch;
    logic [15:0] readback_frame_id;
    logic [1:0] readback_mode;
    logic [23:0] readback_length;
    logic command_error_suppress;
    logic session_reset;
    logic filter_clear;
    logic filter_pop;
    logic feed_capture;
    logic feed_hold;
    logic feed_last;
    logic feed_done;
    logic [16:0] feed_addr;
    logic [7:0] feed_data;
    logic hold_valid;
    logic hold_last;
    logic thresh_ready;
    logic thresh_valid;
    logic thresh_last;
    logic [7:0] thresh_data;
    logic sobel_ready;
    logic sobel_valid;
    logic sobel_last;
    logic [7:0] sobel_data;
    // One stable Sobel byte. It is filled from the filter and emptied only
    // when that byte is copied into the UART holding register.
    logic skid_valid;
    logic skid_last;
    logic [7:0] skid_data;

    wire [16:0] filter_pixels = (readback_mode == 2'd2)
        ? 17'(FRAME_W * FRAME_H) : 17'(READBACK_BYTES);
    wire filter_mode = (readback_mode != 2'd0);
    wire filter_ready = (readback_mode == 2'd2) ? sobel_ready : thresh_ready;
    wire filter_valid = (readback_mode == 2'd2) ? skid_valid : thresh_valid;
    wire filter_last  = (readback_mode == 2'd2) ? skid_last : thresh_last;
    wire [7:0] filter_data = (readback_mode == 2'd2) ? skid_data : thresh_data;
    wire sobel_room = (readback_mode == 2'd2) && readback_active && !skid_valid;
    logic [22:0] alive_count;
    logic [7:0] por_count = 8'd0;
    logic por;

    // Releases about 21 us after configuration. The button can still reset the
    // frame path, but it must not be able to hold the UART itself in reset:
    // a floating BTN0 would otherwise look exactly like a dead board.
    always_ff @(posedge CLK12MHZ)
        if (por_count != 8'hFF)
            por_count <= por_count + 8'd1;

    assign por = (por_count != 8'hFF);
    // Button resets the frame path only. The UART beacon keeps running so a
    // stuck or floating BTN0 cannot look like a dead board.
    wire core_rst = por | btn[0] | session_reset;

    always_ff @(posedge CLK12MHZ)
        alive_count <= alive_count + 23'd1;

    uart_rx #(.CLOCK_HZ(CLOCK_HZ), .BAUD(BAUD)) u_rx (
        .clk           (CLK12MHZ),
        .rst           (por),
        .serial_in     (uart_txd_in),
        .data_valid    (rx_valid),
        .data          (rx_data),
        .framing_error (framing_error)
    );

    proto_parser u_parser (
        .clk         (CLK12MHZ),
        .rst         (core_rst),
        .rx_valid    (rx_valid),
        .rx_data     (rx_data),
        .rx_ready    (),
        .hdr_valid   (hdr_valid),
        .frame_id    (frame_id),
        .packet_id   (packet_id),
        .payload_len (payload_len),
        .data_valid  (data_valid),
        .data        (data),
        .data_last   (data_last),
        .parse_error (parse_error),
        .crc_ok      (crc_ok),
        .crc_error   (crc_error),
        .idle        (parser_idle)
    );

    // Keep the whole portable core while this bring-up top only observes it
    // through status. Later the read port feeds VGA or UART frame readback.
    (* DONT_TOUCH = "true" *) vision_core u_core (
        .clk                 (CLK12MHZ),
        .rst                 (core_rst),
        .swap_ready          (1'b1),
        .hdr_valid           (hdr_valid),
        .frame_id            (frame_id),
        .packet_id           (packet_id),
        .payload_len         (payload_len),
        .data_valid          (data_valid),
        .data                (data),
        .data_last           (data_last),
        .crc_ok              (crc_ok),
        .crc_error           (crc_error),
        .rd_en               (rd_en),
        .rd_addr             (rd_addr),
        .rd_data             (rd_data),
        .rd_bank             (rd_bank),
        .wr_bank             (wr_bank),
        .pkt_accept          (pkt_accept),
        .duplicate_packet    (duplicate_packet),
        .late_packet         (late_packet),
        .incomplete_frame    (incomplete_frame),
        .dropped_frame       (dropped_frame),
        .payload_error       (payload_error),
        .frame_complete      (frame_complete),
        .wr_allowed          (wr_allowed),
        .swap_pulse          (swap_pulse),
        .pending_display     (pending_display),
        .current_frame_id    (current_frame_id),
        .unique_packet_count (unique_packet_count),
        .write_count         (write_count),
        .mem_we              (mem_we),
        .mem_addr            (mem_addr),
        .mem_wdata           (mem_wdata)
    );

    wire beacon_tick = ENABLE_BEACON && (beacon_div == 20'd599_999);
    // The read enable is combinational so the captured word is the address
    // issued on this clock, not the stale word from the previous read.
    // feed_hold keeps a fetched pixel until the filter is actually ready.
    // Checking readiness before the memory latency and pulsing for one cycle
    // dropped pixels whenever Sobel backpressure arrived during that latency.
    wire feed_valid = feed_hold && filter_ready;
    wire issue_read = filter_mode && readback_active && !filter_clear &&
        !feed_done && !feed_capture && !feed_hold;
    // While a new frame is arriving, borrow the display-bank read port to
    // fetch the previous pixel at the address being written. Readback keeps
    // the port once it starts.
    wire motion_issue = mem_we && !readback_active && !bg_busy;
    wire bg_owns_read = bg_busy;
    wire ddr_owns_read = copy_busy;
    assign rd_en   = bg_owns_read ? bg_rd_en
        : ddr_owns_read ? copy_rd_en
        : (motion_issue ? 1'b1 : (filter_mode ? issue_read : (readback_active && !ddr_stream)));
    assign rd_addr = bg_owns_read ? bg_rd_addr
        : ddr_owns_read ? copy_rd_addr
        : (motion_issue ? mem_addr : (filter_mode ? feed_addr : readback_addr));

    bg_frame #(.FRAME_BYTES(READBACK_BYTES)) u_bg (
        .clk         (CLK12MHZ),
        .rst         (core_rst),
        .start       (bg_start),
        .abort       (bg_busy && !parser_idle),
        .rd_data     (rd_data),
        .rd_en       (bg_rd_en),
        .rd_addr     (bg_rd_addr),
        .busy        (bg_busy),
        .armed       (bg_armed),
        .done        (bg_done),
        .sample_en   (motion_issue && bg_armed),
        .sample_addr (mem_addr),
        .sample_data (bg_sample)
    );

    motion_watch #(.WIDTH(FRAME_W), .HEIGHT(FRAME_H), .THRESH(16)) u_motion (
        .clk       (CLK12MHZ),
        .rst       (core_rst),
        .clear     (swap_pulse || incomplete_frame),
        .latch     (swap_pulse),
        .issue     (motion_issue),
        .curr_pix  (mem_wdata),
        .addr      (mem_addr),
        .prev_pix  (bg_armed ? bg_sample : rd_data),
        .motion    (motion_flag),
        .min_x     (motion_min_x),
        .max_x     (motion_max_x),
        .min_y     (motion_min_y),
        .max_y     (motion_max_y),
        .pix_count (motion_count),
        .cen_x     (motion_cen_x),
        .cen_y     (motion_cen_y)
    );

    // Hold a processed pixel until the UART actually accepts it. Keeping
    // tx_valid low while the filter catches up prevents a repeated byte.
    ddr3_board u_ddr (
        .clk12       (CLK12MHZ),
        .clk100      (clk100),
        .rst12       (por),
        .copy_go     (copy_start),
        .copy_busy   (copy_busy),
        .copy_rd_en  (copy_rd_en),
        .copy_rd_addr(copy_rd_addr),
        .copy_rd_data(rd_data),
        .copy_byte   (copy_byte),
        .copy_valid  (copy_valid),
        .copy_last   (copy_last),
        .copy_ready  (copy_take || (!ddr_stream && copy_valid)),
        .calib       (ddr_calib),
        .test_done   (ddr_done),
        .test_pass   (ddr_pass),
        .ddr3_dq     (ddr3_dq),
        .ddr3_dqs_n  (ddr3_dqs_n),
        .ddr3_dqs_p  (ddr3_dqs_p),
        .ddr3_addr   (ddr3_addr),
        .ddr3_ba     (ddr3_ba),
        .ddr3_ras_n  (ddr3_ras_n),
        .ddr3_cas_n  (ddr3_cas_n),
        .ddr3_we_n   (ddr3_we_n),
        .ddr3_reset_n(ddr3_reset_n),
        .ddr3_ck_p   (ddr3_ck_p),
        .ddr3_ck_n   (ddr3_ck_n),
        .ddr3_cke    (ddr3_cke),
        .ddr3_cs_n   (ddr3_cs_n),
        .ddr3_dm     (ddr3_dm),
        .ddr3_odt    (ddr3_odt)
    );

    wire tx_valid = status_active || beacon_active || motion_active || bg_ack_active ||
        ddr_reply_active ||
        (readback_active && !ddr_stream && (!filter_mode || !readback_payload || hold_valid)) ||
        (readback_active && ddr_stream && (!readback_payload || ddr_hold_valid));

    img_threshold u_threshold (
        .clk       (CLK12MHZ),
        .rst       (core_rst || filter_clear),
        .threshold (8'd128),
        .s_valid   (feed_valid && readback_mode == 2'd1),
        .s_data    (feed_data),
        .s_last    (feed_last),
        .s_ready   (thresh_ready),
        .m_valid   (thresh_valid),
        .m_data    (thresh_data),
        .m_last    (thresh_last),
        .m_ready   (filter_pop && readback_mode == 2'd1)
    );

    img_sobel #(.WIDTH(FRAME_W), .HEIGHT(FRAME_H)) u_sobel (
        .clk     (CLK12MHZ),
        .rst     (core_rst || filter_clear),
        .s_valid (feed_valid && readback_mode == 2'd2),
        .s_data  (feed_data),
        .s_last  (feed_last),
        .s_ready (sobel_ready),
        .m_valid (sobel_valid),
        .m_data  (sobel_data),
        .m_last  (sobel_last),
        .m_ready (sobel_room)
    );

    uart_tx #(.CLOCK_HZ(CLOCK_HZ), .BAUD(BAUD)) u_tx (
        .clk        (CLK12MHZ),
        .rst        (por),
        .data_valid (tx_valid),
        .data       (tx_data),
        .ready      (tx_ready),
        .serial_out (uart_rxd_out)
    );

    always_ff @(posedge CLK12MHZ) begin
        if (por) begin
            activity_count   <= 23'd0;
            error_latch      <= 7'd0;
            status_errors    <= 7'd0;
            tx_data          <= 8'h5A;
            status_active    <= 1'b0;
            status_pending   <= 1'b0;
            status_index     <= 3'd0;
            beacon_active    <= 1'b0;
            beacon_index     <= 2'd0;
            beacon_div       <= 20'd0;
            rx_count_mod     <= 7'd0;
            saw_rx           <= 1'b0;
            saw_framing      <= 1'b0;
            saw_parse        <= 1'b0;
            beacon_flags     <= 8'hC0;
            beacon_count     <= 8'h80;
            readback_active       <= 1'b0;
            readback_pending      <= 1'b0;
            readback_payload      <= 1'b0;
            readback_header_index <= 3'd0;
            readback_addr         <= 17'd0;
            readback_prefetch     <= 2'd0;
            readback_frame_id     <= 16'd0;
            readback_mode          <= 2'd0;
            readback_length        <= 24'(READBACK_BYTES);
            command_error_suppress <= 1'b0;
            session_reset          <= 1'b0;
            filter_clear           <= 1'b0;
            filter_pop             <= 1'b0;
            feed_capture           <= 1'b0;
            feed_hold              <= 1'b0;
            feed_last              <= 1'b0;
            feed_done              <= 1'b0;
            feed_addr              <= 17'd0;
            feed_data              <= 8'd0;
            hold_valid             <= 1'b0;
            hold_last              <= 1'b0;
            skid_valid             <= 1'b0;
            skid_last              <= 1'b0;
            skid_data              <= 8'd0;
            crc_fail_seen          <= 1'b0;
            crc_idle               <= 14'd0;
            motion_active          <= 1'b0;
            motion_pending         <= 1'b0;
            motion_index           <= 5'd0;
            motion_frame           <= 16'd0;
            bg_start               <= 1'b0;
            bg_ack_active          <= 1'b0;
            bg_ack_pending         <= 1'b0;
            bg_ack_index           <= 1'b0;
            ddr_reply_active       <= 1'b0;
            ddr_reply_pending      <= 1'b0;
            ddr_reply_index        <= 1'b0;
            ddr_reply_byte         <= 8'd0;
            ddr_stream             <= 1'b0;
            copy_start             <= 1'b0;
            copy_take              <= 1'b0;
            ddr_hold_valid         <= 1'b0;
            ddr_hold_last          <= 1'b0;
        end
        else begin
            command_error_suppress <= 1'b0;
            bg_start               <= 1'b0;
            copy_start             <= 1'b0;
            copy_take              <= 1'b0;
            session_reset          <= 1'b0;
            filter_clear           <= 1'b0;
            filter_pop             <= 1'b0;
            if (filter_clear) begin
                skid_valid <= 1'b0;
            end
            else if (sobel_room && sobel_valid) begin
                skid_valid <= 1'b1;
                skid_last  <= sobel_last;
                skid_data  <= sobel_data;
            end
            else if (filter_pop && readback_mode == 2'd2)
                skid_valid <= 1'b0;

            if (feed_valid)
                feed_hold <= 1'b0;

            if (rx_valid) begin
                activity_count <= 23'h7F_FFFF;
                rx_count_mod   <= rx_count_mod + 7'd1;
                saw_rx         <= 1'b1;

                // A read request is accepted only between camera packets and
                // after a frame has completed. The parser also sees this byte
                // as bad magic; suppress that intentional parse error below.
                if (parser_idle && frame_complete &&
                    (rx_data == READBACK_CMD || rx_data == THRESHOLD_CMD ||
                     rx_data == SOBEL_CMD || rx_data == MOTION_CMD)) begin
                    command_error_suppress <= 1'b1;
                    if (rx_data == MOTION_CMD)
                        motion_pending <= 1'b1;
                    else begin
                        readback_pending <= 1'b1;
                        if (rx_data == THRESHOLD_CMD)
                            readback_mode <= 2'd1;
                        else if (rx_data == SOBEL_CMD)
                            readback_mode <= 2'd2;
                        else
                            readback_mode <= 2'd0;
                    end
                end
                else if (parser_idle && rx_data == SESSION_RESET_CMD) begin
                    // Start a fresh host session without resetting the UART or
                    // stopping the diagnostic beacon.
                    session_reset          <= 1'b1;
                    command_error_suppress <= 1'b1;
                    status_pending         <= 1'b0;
                    readback_pending       <= 1'b0;
                    motion_pending         <= 1'b0;
                    bg_ack_pending         <= 1'b0;
                    ddr_reply_pending      <= 1'b0;
                    ddr_stream             <= 1'b0;
                    ddr_hold_valid         <= 1'b0;
                    error_latch            <= 7'd0;
                end
                else if (parser_idle && frame_complete && !bg_busy &&
                         !readback_active && !readback_pending &&
                         !motion_active && !motion_pending &&
                         rx_data == BG_CMD) begin
                    command_error_suppress <= 1'b1;
                    bg_start               <= 1'b1;
                end
                else if (parser_idle && !bg_busy &&
                         !readback_active && !readback_pending &&
                         !motion_active && !motion_pending &&
                         rx_data == DDR_CMD) begin
                    command_error_suppress <= 1'b1;
                    ddr_reply_pending      <= 1'b1;
                    ddr_reply_byte         <= {5'd0, ddr_pass, ddr_done, ddr_calib};
                end
                else if (parser_idle && frame_complete && !bg_busy &&
                         !readback_active && !readback_pending &&
                         !motion_active && !motion_pending &&
                         !copy_busy && !ddr_stream &&
                         rx_data == DDR_FRAME_CMD) begin
                    command_error_suppress <= 1'b1;
                    readback_pending       <= 1'b1;
                    readback_mode          <= 2'd0;
                    ddr_stream             <= 1'b1;
                    copy_start             <= 1'b1;
                end
            end
            else if (activity_count != 0)
                activity_count <= activity_count - 1'b1;

            if (framing_error)
                saw_framing <= 1'b1;
            if (parse_error && !command_error_suppress)
                saw_parse <= 1'b1;

            if (beacon_tick)
                beacon_div <= 20'd0;
            else
                beacon_div <= beacon_div + 20'd1;

            if (rx_valid && parser_idle && rx_data == SESSION_RESET_CMD)
                error_latch <= 7'd0;
            else
                error_latch <= error_latch |
                    {framing_error, (parse_error && !command_error_suppress),
                     payload_error, dropped_frame,
                     incomplete_frame, late_packet, duplicate_packet};

            if (rx_valid || !parser_idle)
                crc_idle <= 14'd0;
            else if (crc_idle != CRC_IDLE_CYCLES[13:0])
                crc_idle <= crc_idle + 14'd1;

            // A good frame reports on the display swap. A frame with a bad
            // CRC never swaps, so report once the host has gone idle and the
            // unique-packet count has stopped changing.
            if (swap_pulse)
                motion_frame <= current_frame_id;
            if (swap_pulse || crc_status_fire)
                status_pending <= 1'b1;
            if ((rx_valid && parser_idle && rx_data == SESSION_RESET_CMD) ||
                swap_pulse || crc_status_fire)
                crc_fail_seen <= 1'b0;
            else if (crc_error)
                crc_fail_seen <= 1'b1;

            if (!status_active && !beacon_active && !readback_active &&
                !motion_active && !bg_ack_active && !ddr_reply_active &&
                status_pending) begin
                status_active  <= 1'b1;
                status_pending <= 1'b0;
                status_index   <= 3'd0;
                tx_data        <= 8'h5A;
                status_errors  <= error_latch;
                error_latch    <= 7'd0;
            end
            else if (!status_active && !beacon_active && !readback_active &&
                     !motion_active && !bg_ack_active && !ddr_reply_active &&
                     !status_pending && readback_pending) begin
                readback_active       <= 1'b1;
                readback_pending      <= 1'b0;
                readback_payload      <= 1'b0;
                readback_header_index <= 3'd0;
                readback_addr         <= 17'd0;
                readback_prefetch     <= 2'd0;
                readback_frame_id     <= current_frame_id;
                readback_length       <= (readback_mode == 2'd2)
                    ? 24'(SOBEL_BYTES) : 24'(READBACK_BYTES);
                filter_clear          <= (readback_mode != 2'd0);
                feed_capture          <= 1'b0;
                feed_hold             <= 1'b0;
                feed_done             <= 1'b0;
                feed_addr             <= 17'd0;
                hold_valid            <= 1'b0;
                hold_last             <= 1'b0;
                tx_data               <= READBACK_SYNC;
            end
            else if (!status_active && !beacon_active && !readback_active &&
                     !motion_active && !bg_ack_active && !ddr_reply_active &&
                     !status_pending && !readback_pending &&
                     motion_pending) begin
                motion_active  <= 1'b1;
                motion_pending <= 1'b0;
                motion_index   <= 5'd0;
                tx_data        <= MOTION_SYNC;
            end
            else if (!status_active && !beacon_active && !readback_active &&
                     !motion_active && !status_pending && !readback_pending &&
                     !motion_pending && bg_ack_pending) begin
                bg_ack_active  <= 1'b1;
                bg_ack_pending <= 1'b0;
                bg_ack_index   <= 1'b0;
                tx_data        <= BG_SYNC;
            end
            else if (!status_active && !beacon_active && !readback_active &&
                     !motion_active && !bg_ack_active &&
                     !status_pending && !readback_pending &&
                     !motion_pending && !bg_ack_pending && ddr_reply_pending) begin
                ddr_reply_active  <= 1'b1;
                ddr_reply_pending <= 1'b0;
                ddr_reply_index   <= 1'b0;
                tx_data           <= DDR_SYNC;
            end
            else if (!status_active && !beacon_active && !readback_active &&
                     !motion_active && !bg_ack_active && !ddr_reply_active &&
                     !bg_busy && !copy_busy && !ddr_stream &&
                     !status_pending && !readback_pending &&
                     !motion_pending && !bg_ack_pending && !ddr_reply_pending &&
                     beacon_tick) begin
                beacon_active <= 1'b1;
                beacon_index  <= 2'd0;
                tx_data       <= 8'hE7;
                // 0xC0-0xCF and 0x80-0xFF, so a beacon can never look like a
                // status sync of 0x5A.
                beacon_flags  <= {4'hC, frame_complete, saw_rx, saw_framing, saw_parse};
                beacon_count  <= {1'b1, rx_count_mod};
                saw_rx        <= 1'b0;
                saw_framing   <= 1'b0;
                saw_parse     <= 1'b0;
            end
            else if (status_active && tx_ready) begin
                // This edge consumes tx_data; queue the next byte.
                if (status_index == 3'd4) begin
                    status_active <= 1'b0;
                end
                else begin
                    status_index <= status_index + 3'd1;
                    unique case (status_index)
                        3'd0: tx_data <= current_frame_id[7:0];
                        3'd1: tx_data <= current_frame_id[15:8];
                        3'd2: tx_data <= {1'b0, unique_packet_count};
                        default: tx_data <= {1'b0, status_errors};
                    endcase
                end
            end
            else if (motion_active && tx_ready) begin
                if (motion_index == 5'd17)
                    motion_active <= 1'b0;
                else begin
                    motion_index <= motion_index + 5'd1;
                    case (motion_index)
                        4'd0:  tx_data <= motion_frame[7:0];
                        4'd1:  tx_data <= motion_frame[15:8];
                        4'd2:  tx_data <= {7'd0, motion_flag};
                        4'd3:  tx_data <= motion_min_x[7:0];
                        4'd4:  tx_data <= {7'd0, motion_min_x[8]};
                        4'd5:  tx_data <= motion_min_y;
                        4'd6:  tx_data <= 8'd0;
                        4'd7:  tx_data <= motion_max_x[7:0];
                        4'd8:  tx_data <= {7'd0, motion_max_x[8]};
                        4'd9:  tx_data <= motion_max_y;
                        4'd10: tx_data <= 8'd0;
                        4'd11: tx_data <= motion_count[7:0];
                        4'd12: tx_data <= motion_count[15:8];
                        4'd13: tx_data <= motion_cen_x[7:0];
                        4'd14: tx_data <= {7'd0, motion_cen_x[8]};
                        4'd15: tx_data <= motion_cen_y;
                        default: tx_data <= 8'd0;
                    endcase
                end
            end
            else if (bg_ack_active && tx_ready) begin
                if (bg_ack_index) begin
                    bg_ack_active <= 1'b0;
                end
                else begin
                    bg_ack_index <= 1'b1;
                    tx_data      <= 8'h01;
                end
            end
            else if (ddr_reply_active && tx_ready) begin
                if (ddr_reply_index) begin
                    ddr_reply_active <= 1'b0;
                end
                else begin
                    ddr_reply_index <= 1'b1;
                    tx_data         <= ddr_reply_byte;
                end
            end
            else if (beacon_active && tx_ready) begin
                if (beacon_index == 2'd2) begin
                    beacon_active <= 1'b0;
                end
                else begin
                    beacon_index <= beacon_index + 2'd1;
                    tx_data <= (beacon_index == 2'd0) ? beacon_flags : beacon_count;
                end
            end
            else if (readback_active && tx_ready && !readback_payload) begin
                if (readback_header_index == 3'd5) begin
                    readback_payload <= 1'b1;
                    if (ddr_stream) begin
                        // The DDR byte is loaded once readback_payload is set.
                    end
                    else if (!filter_mode)
                        tx_data <= rd_data;
                    else if (filter_valid) begin
                        hold_valid <= 1'b1;
                        hold_last  <= filter_last;
                        tx_data    <= filter_data;
                        filter_pop <= 1'b1;
                    end
                end
                else begin
                    readback_header_index <= readback_header_index + 3'd1;
                    unique case (readback_header_index)
                        3'd0: tx_data <= readback_frame_id[7:0];
                        3'd1: tx_data <= readback_frame_id[15:8];
                        3'd2: tx_data <= readback_length[7:0];
                        3'd3: tx_data <= readback_length[15:8];
                        default: tx_data <= readback_length[23:16];
                    endcase
                end
            end
            else if (readback_active && readback_payload && ddr_stream) begin
                if (tx_ready && ddr_hold_valid) begin
                    ddr_hold_valid <= 1'b0;
                    if (ddr_hold_last) begin
                        readback_active <= 1'b0;
                        ddr_stream      <= 1'b0;
                    end
                end
                else if (!ddr_hold_valid && copy_valid) begin
                    ddr_hold_valid <= 1'b1;
                    ddr_hold_last  <= copy_last;
                    tx_data        <= copy_byte;
                    copy_take      <= 1'b1;
                end
            end
            else if (readback_active && tx_ready && readback_payload && !filter_mode) begin
                if (readback_addr == 17'(READBACK_BYTES - 1))
                    readback_active <= 1'b0;
                else begin
                    readback_addr     <= readback_addr + 17'd1;
                    readback_prefetch <= 2'd2;
                end
            end
            else if (readback_active && readback_payload && filter_mode) begin
                // Accept and refill are separate cycles. Refilling on the
                // accept cycle repeated the byte just taken, because the
                // filter still held that same byte.
                if (tx_ready && hold_valid) begin
                    hold_valid <= 1'b0;
                    if (hold_last)
                        readback_active <= 1'b0;
                end
                else if (!hold_valid && filter_valid) begin
                    hold_valid <= 1'b1;
                    hold_last  <= filter_last;
                    tx_data    <= filter_data;
                    filter_pop <= 1'b1;
                end
            end

            // frame_mem is synchronous. Two clocks after changing rd_addr,
            // rd_data contains the next pixel; copy it while UART is busy.
            if (!filter_mode && !ddr_stream && readback_prefetch != 0) begin
                readback_prefetch <= readback_prefetch - 2'd1;
                if (readback_prefetch == 2'd1)
                    tx_data <= rd_data;
            end

            // One-cycle memory read, then one cycle into the selected filter.
            // Issue only when the filter can accept, so a stalled Sobel window
            // cannot drop a source pixel.
            if (feed_capture) begin
                feed_capture <= 1'b0;
                feed_hold    <= 1'b1;
                feed_data    <= rd_data;
                feed_last    <= (feed_addr == filter_pixels - 17'd1);
                feed_done    <= (feed_addr == filter_pixels - 17'd1);
                feed_addr    <= feed_addr + 17'd1;
            end
            else if (issue_read)
                feed_capture <= 1'b1;

            if (bg_done)
                bg_ack_pending <= 1'b1;
        end
    end

    // Blinks when the clock is alive and no UART bytes are arriving, so a dark
    // LED0 means the design is not clocked. Solid means bytes are arriving.
    assign led[0] = (activity_count != 0) | alive_count[22];
    assign led[1] = frame_complete;
    assign led[2] = pending_display;
    assign led[3] = (error_latch != 0);

endmodule
