`timescale 1ns/1ps

module img_threshold_tb;
    logic       clk = 1'b0;
    logic       rst;
    logic [7:0] threshold;
    logic       s_valid;
    logic [7:0] s_data;
    logic       s_last;
    logic       s_ready;
    logic       m_valid;
    logic [7:0] m_data;
    logic       m_last;
    logic       m_ready;

    img_threshold dut (
        .clk       (clk),
        .rst       (rst),
        .threshold (threshold),
        .s_valid   (s_valid),
        .s_data    (s_data),
        .s_last    (s_last),
        .s_ready   (s_ready),
        .m_valid   (m_valid),
        .m_data    (m_data),
        .m_last    (m_last),
        .m_ready   (m_ready)
    );

    always #5 clk = ~clk;

    initial begin
        rst       = 1'b1;
        threshold = 8'd128;
        s_valid   = 1'b0;
        s_data    = 8'd0;
        s_last    = 1'b0;
        m_ready   = 1'b1;
        @(posedge clk);
        #1;
        rst = 1'b0;

        s_valid = 1'b1;
        s_data  = 8'd10;
        s_last  = 1'b0;
        @(posedge clk);
        #1;
        if (!m_valid || m_data !== 8'h00 || m_last)
            $fatal(1, "First pixel should threshold to 0");

        s_data = 8'd200;
        s_last  = 1'b1;
        @(posedge clk);
        #1;
        if (!m_valid || m_data !== 8'hFF || !m_last)
            $fatal(1, "Second pixel should threshold to 255");

        s_valid = 1'b0;
        s_last  = 1'b0;
        @(posedge clk);
        #1;

        m_ready = 1'b0;
        s_valid = 1'b1;
        s_data  = 8'd40;
        s_last  = 1'b0;
        @(posedge clk);
        #1;
        if (!m_valid || s_ready)
            $fatal(1, "Backpressure did not stall the input");

        m_ready = 1'b1;
        @(posedge clk);
        #1;
        if (!s_ready)
            $fatal(1, "Ready did not return after the output fired");

        $display("PASS: img_threshold matched the software 0/255 rule and honored backpressure");
        $finish;
    end
endmodule
