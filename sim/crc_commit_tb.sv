`timescale 1ns/1ps

// Clock-cycle packet feed: a good CRC commits the packet, a bad CRC does not,
// and a later good copy of that packet can still complete the frame.
module crc_commit_tb;
    logic        clk = 1'b0;
    logic        rst;
    logic        rx_valid;
    logic [7:0]  rx_data;
    logic        hdr_valid;
    logic [15:0] frame_id;
    logic [5:0]  packet_id;
    logic [10:0] payload_len;
    logic        data_valid;
    logic [7:0]  data;
    logic        data_last;
    logic        parse_error;
    logic        crc_ok;
    logic        crc_error;
    logic        pkt_accept;
    logic        duplicate_packet;
    logic        late_packet;
    logic        incomplete_frame;
    logic        dropped_frame;
    logic        payload_error;
    logic        frame_complete;
    logic [6:0]  unique_packet_count;
    logic        saw_dup;
    logic        saw_crc_err;

    localparam int PACKET_BYTES = 1200;

    proto_parser parser (
        .clk         (clk),
        .rst         (rst),
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
        .idle        ()
    );

    vision_core core (
        .clk                 (clk),
        .rst                 (rst),
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
        .rd_en               (1'b0),
        .rd_addr             (17'd0),
        .rd_data             (),
        .rd_bank             (),
        .wr_bank             (),
        .pkt_accept          (pkt_accept),
        .duplicate_packet    (duplicate_packet),
        .late_packet         (late_packet),
        .incomplete_frame    (incomplete_frame),
        .dropped_frame       (dropped_frame),
        .payload_error       (payload_error),
        .frame_complete      (frame_complete),
        .wr_allowed          (),
        .swap_pulse          (),
        .pending_display     (),
        .current_frame_id    (),
        .unique_packet_count (unique_packet_count),
        .write_count         ()
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (rst) begin
            saw_dup     <= 1'b0;
            saw_crc_err <= 1'b0;
        end
        else begin
            if (duplicate_packet)
                saw_dup <= 1'b1;
            if (payload_error)
                saw_crc_err <= 1'b1;
        end
    end

    function automatic logic [31:0] crc32_byte(input logic [31:0] crc, input logic [7:0] byte_in);
        logic [31:0] c;
        int n;
        begin
            c = crc ^ {24'd0, byte_in};
            for (n = 0; n < 8; n++) begin
                if (c[0])
                    c = (c >> 1) ^ 32'hEDB88320;
                else
                    c = c >> 1;
            end
            crc32_byte = c;
        end
    endfunction

    task automatic send_byte(input logic [7:0] value);
        begin
            rx_valid = 1'b1;
            rx_data  = value;
            @(posedge clk);
            #1;
            rx_valid = 1'b0;
        end
    endtask

    task automatic send_packet(input logic [5:0] pid, input logic bad_crc);
        logic [31:0] crc;
        logic [7:0]  pixel;
        int i;
        begin
            crc = 32'hFFFFFFFF;
            send_byte(8'hA5);
            send_byte(8'h01);
            send_byte(8'h00);
            send_byte({2'b00, pid});
            send_byte(8'd176);
            send_byte(8'd4);
            for (i = 0; i < PACKET_BYTES; i++) begin
                pixel = pid ^ i[7:0];
                send_byte(pixel);
                crc = crc32_byte(crc, pixel);
            end
            crc = crc ^ 32'hFFFFFFFF;
            send_byte(crc[7:0]);
            send_byte(crc[15:8]);
            send_byte(crc[23:16]);
            send_byte(bad_crc ? (crc[31:24] ^ 8'hFF) : crc[31:24]);
            // crc_ok/crc_error is visible after the last byte's clock.
            // The received-map updates on the following clock.
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        int id;
        rst      = 1'b1;
        rx_valid = 1'b0;
        rx_data  = 8'd0;
        repeat (3) @(posedge clk);
        #1;
        rst = 1'b0;

        send_packet(6'd0, 1'b0);
        if (unique_packet_count !== 7'd1 || frame_complete)
            $fatal(1, "good packet count=%0d complete=%0b", unique_packet_count, frame_complete);

        send_packet(6'd0, 1'b0);
        if (unique_packet_count !== 7'd1 || !saw_dup)
            $fatal(1, "duplicate was counted or not flagged (count=%0d dup=%0b)",
                   unique_packet_count, saw_dup);

        for (id = 1; id < 64; id++)
            send_packet(id[5:0], 1'b0);
        repeat (3) @(posedge clk);
        if (!frame_complete || unique_packet_count !== 7'd64)
            $fatal(1, "64 good CRCs did not complete (count=%0d)", unique_packet_count);

        rst = 1'b1;
        repeat (3) @(posedge clk);
        #1;
        rst = 1'b0;

        for (id = 0; id < 64; id++)
            send_packet(id[5:0], id == 7);
        if (saw_crc_err !== 1'b1 || unique_packet_count !== 7'd63 || frame_complete)
            $fatal(1, "bad CRC count=%0d err=%0b complete=%0b",
                   unique_packet_count, saw_crc_err, frame_complete);

        send_packet(6'd7, 1'b0);
        repeat (3) @(posedge clk);
        if (!frame_complete || unique_packet_count !== 7'd64)
            $fatal(1, "retried packet did not complete the frame (count=%0d)",
                   unique_packet_count);

        $display("PASS: CRC commit keeps good packets, rejects a bad CRC, and accepts the retry");
        $finish;
    end
endmodule
