`timescale 1ns/1ps

module frame_engine_tb;
    logic        clk = 1'b0;
    logic        rst;
    logic        wr_allowed;
    logic        hdr_valid;
    logic [15:0] frame_id;
    logic [5:0]  packet_id;
    logic        crc_ok;
    logic        crc_error;
    logic        pkt_accept;
    logic        duplicate_packet;
    logic        late_packet;
    logic        incomplete_frame;
    logic        dropped_frame;
    logic        frame_complete;
    logic [15:0] current_frame_id;
    logic [6:0]  unique_packet_count;
    logic [63:0] received_map;
    logic        have_frame;

    frame_engine dut (
        .clk                 (clk),
        .rst                 (rst),
        .wr_allowed          (wr_allowed),
        .hdr_valid           (hdr_valid),
        .frame_id            (frame_id),
        .packet_id           (packet_id),
        .crc_ok              (crc_ok),
        .crc_error           (crc_error),
        .pkt_accept          (pkt_accept),
        .duplicate_packet    (duplicate_packet),
        .late_packet         (late_packet),
        .incomplete_frame    (incomplete_frame),
        .dropped_frame       (dropped_frame),
        .frame_complete      (frame_complete),
        .current_frame_id    (current_frame_id),
        .unique_packet_count (unique_packet_count),
        .received_map        (received_map),
        .have_frame          (have_frame)
    );

    always #5 clk = ~clk;

    task automatic send_hdr(input logic [15:0] fid, input logic [5:0] pid);
        begin
            frame_id  = fid;
            packet_id = pid;
            hdr_valid = 1'b1;
            @(posedge clk);
        end
    endtask

    task automatic drop_hdr;
        begin
            #1;
            hdr_valid = 1'b0;
        end
    endtask

    task automatic crc_good;
        begin
            crc_ok = 1'b1;
            @(posedge clk);
            #1;
            crc_ok = 1'b0;
        end
    endtask

    initial begin
        wr_allowed = 1'b1;
        hdr_valid  = 1'b0;
        crc_ok     = 1'b0;
        crc_error  = 1'b0;
        frame_id   = 16'd0;
        packet_id  = 6'd0;
        rst        = 1'b1;
        @(posedge clk);
        #1;
        rst = 1'b0;

        send_hdr(16'd7, 6'd3);
        if (!pkt_accept)
            $fatal(1, "First packet was not accepted");
        drop_hdr();
        crc_good();
        if (!have_frame || current_frame_id !== 16'd7 || unique_packet_count !== 7'd1)
            $fatal(1, "First packet did not start a frame");

        send_hdr(16'd6, 6'd0);
        if (!late_packet || pkt_accept)
            $fatal(1, "Late packet was not rejected");
        drop_hdr();
        if (unique_packet_count !== 7'd1)
            $fatal(1, "Late packet changed the unique count");

        send_hdr(16'd7, 6'd3);
        if (pkt_accept)
            $fatal(1, "Duplicate packet was accepted");
        drop_hdr();
        if (!duplicate_packet || unique_packet_count !== 7'd1)
            $fatal(1, "Duplicate packet was not flagged");

        send_hdr(16'd8, 6'd1);
        if (!incomplete_frame || !pkt_accept)
            $fatal(1, "Newer frame did not abandon the incomplete frame");
        drop_hdr();
        crc_good();
        if (current_frame_id !== 16'd8 || unique_packet_count !== 7'd1)
            $fatal(1, "Newer frame did not become current");

        for (int id = 0; id < 64; id++) begin
            if (id != 1)
                send_hdr(16'd8, id[5:0]);
            drop_hdr();
            if (id != 1)
                crc_good();
        end

        if (!frame_complete || unique_packet_count !== 7'd64)
            $fatal(1, "Frame 8 did not complete");

        wr_allowed = 1'b0;
        send_hdr(16'd9, 6'd0);
        if (!dropped_frame || pkt_accept)
            $fatal(1, "Frame 9 should drop while the write bank is locked");
        drop_hdr();
        wr_allowed = 1'b1;

        // 16-bit frame_id wrap: the host goes 0xFFFF -> 0x0000. Frame 0 must
        // be treated as newer, not as a late packet from 65535 frames ago.
        // Walk forward in modular steps (< 32768 each) the way a real host does.
        send_hdr(16'h7FFF, 6'd0);
        if (!pkt_accept) $fatal(1, "Frame 0x7FFF was not accepted");
        drop_hdr();
        send_hdr(16'hFFFE, 6'd0);
        if (!pkt_accept) $fatal(1, "Frame 0xFFFE was not accepted");
        drop_hdr();
        send_hdr(16'hFFFF, 6'd0);
        if (!pkt_accept)
            $fatal(1, "Frame 0xFFFF was not accepted");
        drop_hdr();
        if (current_frame_id !== 16'hFFFF)
            $fatal(1, "Frame 0xFFFF did not become current");

        send_hdr(16'h0000, 6'd0);
        if (late_packet || !pkt_accept)
            $fatal(1, "Frame 0 after 0xFFFF was rejected as late (wrap bug)");
        drop_hdr();
        if (current_frame_id !== 16'h0000)
            $fatal(1, "Frame 0 did not become current after wrap");

        // ...and a genuinely late packet across the wrap is still rejected.
        send_hdr(16'hFFFE, 6'd5);
        if (!late_packet || pkt_accept)
            $fatal(1, "Frame 0xFFFE after wrap should be late");
        drop_hdr();

        $display("PASS: frame_engine frame-id, late, duplicate, abandon, drop, and wrap policy");
        $finish;
    end
endmodule
