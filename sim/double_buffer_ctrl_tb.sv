`timescale 1ns/1ps

module double_buffer_ctrl_tb;
    logic clk = 1'b0;
    logic rst;
    logic frame_complete;
    logic swap_ready;
    logic wr_bank;
    logic rd_bank;
    logic wr_allowed;
    logic swap_pulse;
    logic pending_display;

    double_buffer_ctrl dut (
        .clk             (clk),
        .rst             (rst),
        .frame_complete  (frame_complete),
        .swap_ready      (swap_ready),
        .wr_bank         (wr_bank),
        .rd_bank         (rd_bank),
        .wr_allowed      (wr_allowed),
        .swap_pulse      (swap_pulse),
        .pending_display (pending_display)
    );

    always #5 clk = ~clk;

    initial begin
        rst            = 1'b1;
        frame_complete = 1'b0;
        swap_ready     = 1'b0;
        @(posedge clk);
        #1;
        rst = 1'b0;

        if (!wr_allowed || wr_bank !== 1'b0 || rd_bank !== 1'b1)
            $fatal(1, "Reset bank selection failed");

        frame_complete = 1'b1;
        @(posedge clk);
        #1;
        if (wr_allowed || !pending_display)
            $fatal(1, "Completed frame did not lock the write bank");

        @(posedge clk);
        #1;
        if (!pending_display)
            $fatal(1, "Level-held frame_complete re-latched after the rising edge");

        swap_ready = 1'b1;
        @(posedge clk);
        #1;
        if (!swap_pulse || wr_bank !== 1'b1 || rd_bank !== 1'b0 || !wr_allowed)
            $fatal(1, "Swap at the display boundary failed");

        $display("PASS: double_buffer_ctrl swaps once per completed frame");
        $finish;
    end
endmodule
