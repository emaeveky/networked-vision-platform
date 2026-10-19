// Stand-in for the MIG wrapper. Icarus cannot elaborate the Xilinx memory IP.
module ddr3_board (
    input  logic        clk12,
    input  logic        clk100,

    output logic        calib,
    output logic        test_done,
    output logic        test_pass,

    inout  wire [15:0]  ddr3_dq,
    inout  wire [1:0]   ddr3_dqs_n,
    inout  wire [1:0]   ddr3_dqs_p,
    output logic [13:0] ddr3_addr,
    output logic [2:0]  ddr3_ba,
    output logic        ddr3_ras_n,
    output logic        ddr3_cas_n,
    output logic        ddr3_we_n,
    output logic        ddr3_reset_n,
    output logic [0:0]  ddr3_ck_p,
    output logic [0:0]  ddr3_ck_n,
    output logic [0:0]  ddr3_cke,
    output logic [0:0]  ddr3_cs_n,
    output logic [1:0]  ddr3_dm,
    output logic [0:0]  ddr3_odt
);

    assign calib     = 1'b0;
    assign test_done = 1'b0;
    assign test_pass = 1'b0;
    assign ddr3_addr = 14'd0;
    assign ddr3_ba   = 3'd0;
    assign ddr3_ras_n = 1'b1;
    assign ddr3_cas_n = 1'b1;
    assign ddr3_we_n = 1'b1;
    assign ddr3_reset_n = 1'b1;
    assign ddr3_ck_p = 1'b0;
    assign ddr3_ck_n = 1'b1;
    assign ddr3_cke  = 1'b0;
    assign ddr3_cs_n = 1'b1;
    assign ddr3_dm   = 2'd0;
    assign ddr3_odt  = 1'b0;

    wire unused = clk12 ^ clk100 ^ (|ddr3_dq) ^ (|ddr3_dqs_n) ^ (|ddr3_dqs_p);

endmodule
