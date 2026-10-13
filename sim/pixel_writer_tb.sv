`timescale 1ns/1ps

module pixel_writer_tb;
    logic        clk = 1'b0;
    logic        rst;
    logic        pkt_accept;
    logic [5:0]  packet_id;
    logic [10:0] payload_len;
    logic        data_valid;
    logic [7:0]  data;
    logic        data_last;
    logic        mem_we;
    logic [16:0] mem_addr;
    logic [7:0]  mem_wdata;
    logic        payload_error;
    logic        busy;
    logic [7:0]  rd_data;

    localparam int N = 1200;

    pixel_writer dut (
        .clk          (clk),
        .rst          (rst),
        .pkt_accept    (pkt_accept),
        .packet_id    (packet_id),
        .payload_len  (payload_len),
        .data_valid   (data_valid),
        .data         (data),
        .data_last    (data_last),
        .mem_we       (mem_we),
        .mem_addr     (mem_addr),
        .mem_wdata    (mem_wdata),
        .payload_error(payload_error),
        .busy         (busy)
    );

    frame_mem mem (
        .clk     (clk),
        .wr_en   (mem_we),
        .wr_bank (1'b0),
        .wr_addr (mem_addr),
        .wr_data (mem_wdata),
        .rd_en   (1'b1),
        .rd_bank (1'b0),
        .rd_addr (17'd0),
        .rd_data (rd_data)
    );

    always #5 clk = ~clk;

    int writes;

    always_ff @(posedge clk) begin
        if (rst)
            writes <= 0;
        else if (mem_we)
            writes <= writes + 1;
    end

    initial begin
        rst         = 1'b1;
        pkt_accept  = 1'b0;
        packet_id   = 6'd0;
        payload_len = 11'(N);
        data_valid  = 1'b0;
        data_last   = 1'b0;
        data        = 8'd0;
        @(posedge clk);
        #1;
        rst = 1'b0;

        packet_id  = 6'd0;
        pkt_accept = 1'b1;
        @(posedge clk);
        #1;
        pkt_accept = 1'b0;
        @(posedge clk);
        #1;

        for (int i = 0; i < N; i++) begin
            data_valid = 1'b1;
            data      = 8'(i);
            data_last = (i == N - 1);
            @(posedge clk);
            #1;
        end
        data_valid = 1'b0;
        data_last  = 1'b0;
        repeat (3) @(posedge clk);

        if (writes !== N)
            $fatal(1, "pixel_writer issued %0d writes, expected %0d", writes, N);
        if (rd_data !== 8'd0)
            $fatal(1, "Address 0 should be 0, got %0h", rd_data);

        $display("PASS: pixel_writer stored 1200 bytes");
        $finish;
    end
endmodule
