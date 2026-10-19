`timescale 1ns/1ps

module ddr3_pattern_tb;
    localparam int BEATS = 4;
    localparam int BURSTS = 2;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic calib = 1'b0;
    logic done;
    logic pass;

    logic [27:0] awaddr;
    logic [7:0]  awlen;
    logic [2:0]  awsize;
    logic [1:0]  awburst;
    logic        awvalid;
    logic        awready;
    logic [127:0] wdata;
    logic [15:0] wstrb;
    logic        wlast;
    logic        wvalid;
    logic        wready;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;
    logic [27:0] araddr;
    logic [7:0]  arlen;
    logic [2:0]  arsize;
    logic [1:0]  arburst;
    logic        arvalid;
    logic        arready;
    logic [127:0] rdata;
    logic [1:0]  rresp;
    logic        rlast;
    logic        rvalid;
    logic        rready;

    ddr3_pattern #(.BEATS(BEATS), .BURSTS(BURSTS)) dut (
        .clk     (clk),
        .rst     (rst),
        .calib   (calib),
        .awaddr  (awaddr),
        .awlen   (awlen),
        .awsize  (awsize),
        .awburst (awburst),
        .awvalid (awvalid),
        .awready (awready),
        .wdata   (wdata),
        .wstrb   (wstrb),
        .wlast   (wlast),
        .wvalid  (wvalid),
        .wready  (wready),
        .bresp   (bresp),
        .bvalid  (bvalid),
        .bready  (bready),
        .araddr  (araddr),
        .arlen   (arlen),
        .arsize  (arsize),
        .arburst (arburst),
        .arvalid (arvalid),
        .arready (arready),
        .rdata   (rdata),
        .rresp   (rresp),
        .rlast   (rlast),
        .rvalid  (rvalid),
        .rready  (rready),
        .done    (done),
        .pass    (pass)
    );

    ddr3_axi_ram #(.BYTES(BEATS * BURSTS * 16)) ram (
        .clk     (clk),
        .rst     (rst),
        .awaddr  (awaddr),
        .awlen   (awlen),
        .awvalid (awvalid),
        .awready (awready),
        .wdata   (wdata),
        .wlast   (wlast),
        .wvalid  (wvalid),
        .wready  (wready),
        .bresp   (bresp),
        .bvalid  (bvalid),
        .bready  (bready),
        .araddr  (araddr),
        .arlen   (arlen),
        .arvalid (arvalid),
        .arready (arready),
        .rdata   (rdata),
        .rresp   (rresp),
        .rlast   (rlast),
        .rvalid  (rvalid),
        .rready  (rready)
    );

    always #5 clk = ~clk;

    initial begin
        repeat (4) @(posedge clk);
        rst   = 1'b0;
        calib = 1'b1;
        wait (done);
        @(posedge clk);
        if (!pass)
            $fatal(1, "DDR pattern readback did not match");
        $display("PASS: DDR pattern matched %0d bytes", BEATS * BURSTS * 16);
        $finish;
    end
endmodule
