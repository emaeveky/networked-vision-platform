`timescale 1ns/1ps

// Previous frame sits in display bank 1. New pixels are compared through the
// same one-cycle memory read the UART top uses.
module motion_pipe_tb;
    logic        clk = 1'b0;
    logic        rst;
    logic        issue;
    logic        latch;
    logic [7:0]  curr_pix;
    logic [16:0] addr;
    logic [7:0]  prev_pix;
    logic        motion;
    logic [8:0]  min_x;
    logic [8:0]  max_x;
    logic [7:0]  min_y;
    logic [7:0]  max_y;
    logic [15:0] pix_count;

    localparam int WIDTH = 320;

    frame_mem mem (
        .clk     (clk),
        .wr_en   (1'b0),
        .wr_bank (1'b0),
        .wr_addr (17'd0),
        .wr_data (8'd0),
        .rd_en   (issue),
        .rd_bank (1'b1),
        .rd_addr (addr),
        .rd_data (prev_pix)
    );

    motion_watch #(.WIDTH(WIDTH), .HEIGHT(240), .THRESH(16)) dut (
        .clk       (clk),
        .rst       (rst),
        .clear     (latch),
        .latch     (latch),
        .issue     (issue),
        .curr_pix  (curr_pix),
        .addr      (addr),
        .prev_pix  (prev_pix),
        .motion    (motion),
        .min_x     (min_x),
        .max_x     (max_x),
        .min_y     (min_y),
        .max_y     (max_y),
        .pix_count (pix_count)
    );

    always #5 clk = ~clk;

    task automatic pixel(input int x, input int y, input logic [7:0] value);
        begin
            issue    = 1'b1;
            curr_pix = value;
            addr     = 17'(y * WIDTH + x);
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        int i;
        rst      = 1'b1;
        issue    = 1'b0;
        latch    = 1'b0;
        curr_pix = 8'd0;
        addr     = 17'd0;
        for (i = 0; i < 76800; i++)
            mem.bank1[i] = 8'd0;
        mem.bank1[20 * WIDTH + 12] = 8'd100;
        repeat (2) @(posedge clk);
        #1;
        rst = 1'b0;

        // 255 and 17 differ from 0 by more than 16. 16 does not. 100 -> 110
        // differs by 10, so it is not motion either.
        pixel(10, 20, 8'd255);
        pixel(11, 20, 8'd17);
        pixel(12, 20, 8'd110);
        pixel(0, 0, 8'd16);
        issue = 1'b0;
        repeat (3) @(posedge clk);
        #1;

        latch = 1'b1;
        @(posedge clk);
        #1;
        latch = 1'b0;

        if (!motion || min_x !== 9'd10 || max_x !== 9'd11 ||
            min_y !== 8'd20 || max_y !== 8'd20 || pix_count !== 16'd2)
            $fatal(1, "box motion=%0b x=%0d..%0d y=%0d..%0d count=%0d",
                   motion, min_x, max_x, min_y, max_y, pix_count);

        $display("PASS: motion box matched the two pixels above threshold");
        $finish;
    end
endmodule
