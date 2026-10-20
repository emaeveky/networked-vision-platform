`timescale 1ns/1ps

module ddr3_sink_tb;
    localparam int FRAME_BYTES = 32;

    logic clk_byte = 0;
    logic clk_ddr = 0;
    logic rst_byte = 1;
    logic rst_ddr = 1;
    logic byte_valid = 0;
    logic [7:0] byte_data = 0;
    logic [18:0] byte_addr = 0;
    logic write_idle;
    logic read_go = 0;
    logic [7:0] out_byte;
    logic out_valid;
    logic out_last;
    logic out_ready;
    logic busy;

    logic [27:0] awaddr;
    logic [7:0] awlen;
    logic [2:0] awsize;
    logic [1:0] awburst;
    logic awvalid, awready;
    logic [127:0] wdata;
    logic [15:0] wstrb;
    logic wlast, wvalid, wready;
    logic [1:0] bresp;
    logic bvalid, bready;
    logic [27:0] araddr;
    logic [7:0] arlen;
    logic [2:0] arsize;
    logic [1:0] arburst;
    logic arvalid, arready;
    logic [127:0] rdata;
    logic [1:0] rresp;
    logic rlast, rvalid, rready;

    logic take;
    int got_count;
    int mismatches;
    int cycles;

    always #20 clk_byte = ~clk_byte;
    always #5 clk_ddr = ~clk_ddr;

    ddr3_sink #(.FRAME_BYTES(FRAME_BYTES)) dut (
        .clk_byte(clk_byte), .rst_byte(rst_byte), .clk_ddr(clk_ddr), .rst_ddr(rst_ddr),
        .gate(1'b1),
        .byte_valid(byte_valid), .byte_data(byte_data), .byte_addr(byte_addr),
        .write_idle(write_idle),
        .read_go(read_go),
        .out_byte(out_byte), .out_valid(out_valid), .out_last(out_last),
        .out_ready(out_ready), .busy(busy),
        .awaddr(awaddr), .awlen(awlen), .awsize(awsize), .awburst(awburst),
        .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .araddr(araddr), .arlen(arlen), .arsize(arsize), .arburst(arburst),
        .arvalid(arvalid), .arready(arready),
        .rdata(rdata), .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready)
    );

    ddr3_axi_ram #(.BYTES(FRAME_BYTES)) ram (
        .clk(clk_ddr), .rst(rst_ddr),
        .awaddr(awaddr), .awlen(awlen), .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .araddr(araddr), .arlen(arlen), .arvalid(arvalid), .arready(arready),
        .rdata(rdata), .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready)
    );

    assign out_ready = take;

    always_ff @(posedge clk_byte) begin
        if (rst_byte) begin
            take <= 0;
            got_count <= 0;
            mismatches <= 0;
        end
        else begin
            take <= 0;
            if (out_valid && !take) begin
                if (out_byte !== 8'(got_count ^ 8'hA5)) begin
                    mismatches <= mismatches + 1;
                    if (mismatches < 8)
                        $display("byte %0d got %02x", got_count, out_byte);
                end
                if (out_last !== (got_count == FRAME_BYTES - 1))
                    $display("FAIL: last flag at %0d", got_count);
                got_count <= got_count + 1;
                take <= 1;
            end
        end
    end

    initial begin
        cycles = 0;
        repeat (4) @(posedge clk_byte);
        rst_byte = 0;
        rst_ddr = 0;
        repeat (2) @(posedge clk_byte);
        for (int i = 0; i < FRAME_BYTES; i++) begin
            @(negedge clk_byte);
            byte_valid = 1'b1;
            byte_data = 8'(i ^ 8'hA5);
            byte_addr = 19'(i);
            @(posedge clk_byte);
            @(negedge clk_byte);
            byte_valid = 1'b0;
        end
        while (!write_idle && cycles < 5000) begin
            @(posedge clk_byte);
            cycles = cycles + 1;
        end
        @(negedge clk_byte);
        read_go = 1'b1;
        @(posedge clk_byte);
        @(negedge clk_byte);
        read_go = 1'b0;
        cycles = 0;
        while (got_count < FRAME_BYTES && cycles < 20000) begin
            @(posedge clk_byte);
            cycles = cycles + 1;
        end
        if (!write_idle || got_count != FRAME_BYTES || mismatches != 0) begin
            $display("FAIL: idle %0d bytes %0d mismatches %0d", write_idle, got_count, mismatches);
            $finish(1);
        end
        $display("PASS: DDR sink matched %0d bytes", FRAME_BYTES);
        $finish(0);
    end
endmodule
