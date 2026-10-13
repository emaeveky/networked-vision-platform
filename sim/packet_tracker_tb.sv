`timescale 1ns/1ps

module packet_tracker_tb;
    logic        clk = 1'b0;
    logic        rst;
    logic        packet_valid;
    logic [5:0]  packet_id;
    logic [63:0] received_map;
    logic [6:0]  unique_packet_count;
    logic        duplicate_packet;
    logic        frame_complete;

    packet_tracker dut (
        .clk                 (clk),
        .rst                 (rst),
        .clear               (1'b0),
        .packet_valid        (packet_valid),
        .packet_id           (packet_id),
        .received_map        (received_map),
        .unique_packet_count (unique_packet_count),
        .duplicate_packet    (duplicate_packet),
        .frame_complete      (frame_complete)
    );

    always #5 clk = ~clk;

    task automatic send_packet(input logic [5:0] id);
        begin
            packet_id    = id;
            packet_valid = 1'b1;
            @(posedge clk);
            #1;
            packet_valid = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("packet_tracker.vcd");
        $dumpvars(0, packet_tracker_tb);

        rst          = 1'b1;
        packet_valid = 1'b0;
        packet_id    = 6'd0;
        @(posedge clk);
        #1;
        rst = 1'b0;

        if (received_map !== 64'b0 || unique_packet_count !== 7'd0 ||
            duplicate_packet !== 1'b0 || frame_complete !== 1'b0)
            $fatal(1, "Reset test failed");

        send_packet(6'd5);
        if (!received_map[5] || unique_packet_count !== 7'd1 || duplicate_packet)
            $fatal(1, "First packet test failed");

        send_packet(6'd5);
        if (unique_packet_count !== 7'd1 || !duplicate_packet)
            $fatal(1, "Duplicate packet test failed");

        for (int id = 0; id < 64; id++) begin
            if (id != 5)
                send_packet(id[5:0]);
        end

        if (received_map !== 64'hFFFF_FFFF_FFFF_FFFF ||
            unique_packet_count !== 7'd64 || !frame_complete)
            $fatal(1, "Frame completion test failed");

        $display("PASS: packet_tracker accepted 64 unique packets and rejected a duplicate");
        $finish;
    end
endmodule
