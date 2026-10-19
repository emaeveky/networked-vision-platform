`timescale 1ns/1ps

module ddr3_link_tb;
    localparam int FRAME_BYTES = 64;

    logic clk_byte = 1'b0;
    logic clk_ddr  = 1'b0;
    logic rst_byte = 1'b1;
    logic rst_ddr  = 1'b1;
    logic go = 1'b0;

    logic        rd_en;
    logic [16:0] rd_addr;
    logic [7:0]  rd_data;
    logic [7:0]  out_byte;
    logic        out_valid;
    logic        out_last;
    logic        out_ready;
    logic        take;
    logic        busy;

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

    reg [7:0] mem [0:FRAME_BYTES-1];
    int got_count;
    int mismatches;
    int cycles;

    always #20 clk_byte = ~clk_byte;
    always #5  clk_ddr  = ~clk_ddr;

    ddr3_link #(.FRAME_BYTES(FRAME_BYTES)) dut (
        .clk_byte  (clk_byte),
        .rst_byte  (rst_byte),
        .clk_ddr   (clk_ddr),
        .rst_ddr   (rst_ddr),
        .gate      (1'b1),
        .go        (go),
        .rd_en     (rd_en),
        .rd_addr   (rd_addr),
        .rd_data   (rd_data),
        .out_byte  (out_byte),
        .out_valid (out_valid),
        .out_last  (out_last),
        .out_ready (out_ready),
        .busy      (busy),
        .awaddr    (awaddr),
        .awlen     (awlen),
        .awsize    (awsize),
        .awburst   (awburst),
        .awvalid   (awvalid),
        .awready   (awready),
        .wdata     (wdata),
        .wstrb     (wstrb),
        .wlast     (wlast),
        .wvalid    (wvalid),
        .wready    (wready),
        .bresp     (bresp),
        .bvalid    (bvalid),
        .bready    (bready),
        .araddr    (araddr),
        .arlen     (arlen),
        .arsize    (arsize),
        .arburst   (arburst),
        .arvalid   (arvalid),
        .arready   (arready),
        .rdata     (rdata),
        .rresp     (rresp),
        .rlast     (rlast),
        .rvalid    (rvalid),
        .rready    (rready)
    );

    ddr3_axi_ram #(.BYTES(FRAME_BYTES)) ram (
        .clk     (clk_ddr),
        .rst     (rst_ddr),
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

    always_ff @(posedge clk_byte) begin
        if (rd_en)
            rd_data <= mem[rd_addr];
    end

    assign out_ready = take;

    always_ff @(posedge clk_byte) begin
        if (rst_byte) begin
            take <= 1'b0;
            got_count <= 0;
            mismatches <= 0;
        end
        else begin
            take <= 1'b0;
            if (out_valid && !take) begin
                if (out_byte !== 8'(got_count ^ 8'h5A)) begin
                    mismatches <= mismatches + 1;
                    if (mismatches < 8)
                        $display("byte %0d got %02x", got_count, out_byte);
                end
                if (out_last !== (got_count == FRAME_BYTES - 1))
                    $display("FAIL: last flag at byte %0d", got_count);
                got_count <= got_count + 1;
                take <= 1'b1;
            end
        end
    end

    initial begin
        int i;
        for (i = 0; i < FRAME_BYTES; i = i + 1)
            mem[i] = 8'(i ^ 8'h5A);
        cycles = 0;
        repeat (4) @(posedge clk_byte);
        rst_byte = 1'b0;
        rst_ddr = 1'b0;
        repeat (2) @(posedge clk_byte);
        @(posedge clk_byte);
        go = 1'b1;
        @(posedge clk_byte);
        go = 1'b0;

        while (got_count < FRAME_BYTES && cycles < 20000) begin
            @(posedge clk_byte);
            cycles = cycles + 1;
        end

        if (got_count != FRAME_BYTES || mismatches != 0) begin
            $display("FAIL: DDR frame copy got %0d bytes, mismatches %0d",
                     got_count, mismatches);
            $finish(1);
        end
        $display("PASS: DDR frame copy matched %0d bytes", FRAME_BYTES);
        $finish(0);
    end
endmodule
