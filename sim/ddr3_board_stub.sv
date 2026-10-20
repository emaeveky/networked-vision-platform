// Stand-in for the MIG wrapper. Icarus cannot elaborate the Xilinx memory IP.
module ddr3_board (
    input  logic        clk12,
    input  logic        clk100,
    input  logic        rst12,
    input  logic        copy_go,
    output logic        copy_busy,
    output logic        copy_rd_en,
    output logic [16:0] copy_rd_addr,
    input  logic [7:0]  copy_rd_data,
    output logic [7:0]  copy_byte,
    output logic        copy_valid,
    output logic        copy_last,
    input  logic        copy_ready,

    input  logic        sink_byte_valid,
    input  logic [7:0]  sink_byte,
    input  logic [18:0] sink_byte_addr,
    output logic        sink_write_idle,
    input  logic        sink_read_go,
    output logic [7:0]  sink_out_byte,
    output logic        sink_out_valid,
    output logic        sink_out_last,
    input  logic        sink_out_ready,
    output logic        sink_busy,

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
    assign copy_busy = 1'b0;
    assign copy_rd_en = 1'b0;
    assign copy_rd_addr = 17'd0;
    assign copy_byte = 8'd0;
    assign copy_valid = 1'b0;
    assign copy_last = 1'b0;
    assign sink_write_idle = 1'b1;
    assign sink_out_byte = 8'd0;
    assign sink_out_valid = 1'b0;
    assign sink_out_last = 1'b0;
    assign sink_busy = 1'b0;
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

    wire unused = clk12 ^ clk100 ^ rst12 ^ copy_go ^ copy_ready ^ (|copy_rd_data) ^
        sink_byte_valid ^ (|sink_byte) ^ (|sink_byte_addr) ^ sink_read_go ^ sink_out_ready ^
        (|ddr3_dq) ^ (|ddr3_dqs_n) ^ (|ddr3_dqs_p);

endmodule
