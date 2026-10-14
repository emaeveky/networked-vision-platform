`timescale 1ns/1ps

module vision_core_tb;
    logic        clk = 1'b0;
    logic        rst;
    logic        swap_ready;
    logic        hdr_valid;
    logic [15:0] frame_id;
    logic [5:0]  packet_id;
    logic [10:0] payload_len;
    logic        data_valid;
    logic [7:0]  data;
    logic        data_last;
    logic        crc_ok;
    logic        crc_error;
    logic        rd_en;
    logic [16:0] rd_addr;
    logic [7:0]  rd_data;
    logic        rd_bank;
    logic        wr_bank;
    logic        pkt_accept;
    logic        duplicate_packet;
    logic        late_packet;
    logic        incomplete_frame;
    logic        dropped_frame;
    logic        payload_error;
    logic        frame_complete;
    logic        wr_allowed;
    logic        swap_pulse;
    logic        pending_display;
    logic [15:0] current_frame_id;
    logic [6:0]  unique_packet_count;
    logic [16:0] write_count;

    localparam int PACKET_BYTES = 1200;
    localparam int FRAME_BYTES  = 76800;

    vision_core dut (
        .clk                 (clk),
        .rst                 (rst),
        .swap_ready          (swap_ready),
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
        .mem_we              (),
        .mem_addr            (),
        .mem_wdata           ()
    );

    always #5 clk = ~clk;

    function automatic logic [7:0] pixel_at(input int addr);
        int pkt;
        int off;
        begin
            pkt  = addr / PACKET_BYTES;
            off  = addr % PACKET_BYTES;
            pixel_at = pkt[7:0] ^ off[7:0];
        end
    endfunction

    task automatic send_packet(
        input logic [15:0] fid,
        input logic [5:0]  pid,
        input logic        expect_accept
    );
        int i;
        begin
            frame_id    = fid;
            packet_id   = pid;
            payload_len = 11'(PACKET_BYTES);
            hdr_valid   = 1'b1;
            data_valid  = 1'b0;
            data_last   = 1'b0;
            @(posedge clk);
            if (pkt_accept !== expect_accept)
                $fatal(1, "Packet %0d accept=%0b expected %0b", pid, pkt_accept, expect_accept);
            #1;
            if (!expect_accept && !duplicate_packet)
                $fatal(1, "Packet %0d should have been a duplicate", pid);
            hdr_valid = 1'b0;
            @(posedge clk);
            #1;

            for (i = 0; i < PACKET_BYTES; i++) begin
                data_valid = 1'b1;
                data      = pid[7:0] ^ i[7:0];
                data_last = (i == PACKET_BYTES - 1);
                @(posedge clk);
                #1;
            end
            data_valid = 1'b0;
            data_last  = 1'b0;
            crc_ok = 1'b1;
            @(posedge clk);
            #1;
            crc_ok = 1'b0;
        end
    endtask

    initial begin
        rst         = 1'b1;
        swap_ready  = 1'b0;
        hdr_valid   = 1'b0;
        data_valid  = 1'b0;
        data_last   = 1'b0;
        crc_ok      = 1'b0;
        crc_error   = 1'b0;
        rd_en       = 1'b0;
        rd_addr     = 17'd0;
        frame_id    = 16'd0;
        packet_id   = 6'd0;
        payload_len = 11'd0;
        data        = 8'd0;
        repeat (3) @(posedge clk);
        #1;
        rst = 1'b0;

        send_packet(16'd1, 6'd5, 1'b1);
        send_packet(16'd1, 6'd5, 1'b0);

        for (int id = 0; id < 64; id++) begin
            if (id != 5)
                send_packet(16'd1, id[5:0], 1'b1);
        end

        repeat (3) @(posedge clk);

        if (!frame_complete || unique_packet_count !== 7'd64)
            $fatal(1, "vision_core did not complete frame 1");
        if (write_count !== 17'(FRAME_BYTES))
            $fatal(1, "pixel writer stored %0d bytes, expected %0d", write_count, FRAME_BYTES);

        $display("pre-swap wr_allowed=%0b pending=%0b complete=%0b",
                 wr_allowed, pending_display, frame_complete);
        swap_ready = 1'b1;
        @(posedge clk);
        #1;
        if (pending_display || !wr_allowed || rd_bank !== 1'b0)
            $fatal(1, "Display swap did not occur (wr_allowed=%0b pending=%0b rd_bank=%0b pulse=%0b)",
                   wr_allowed, pending_display, rd_bank, swap_pulse);
        $display("post-swap wr_bank=%0b rd_bank=%0b", wr_bank, rd_bank);
        $display("PASS: vision_core accepted 64 packets, wrote %0d bytes, and swapped banks", FRAME_BYTES);
        $finish;
    end
endmodule
