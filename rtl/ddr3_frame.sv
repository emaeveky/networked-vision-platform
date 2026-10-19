// Move WORDS 16-byte beats to DDR, then read the same beats back. `go` is a
// level. One transfer runs while `gate` is high, and it will not start again
// until `go` drops.
module ddr3_frame #(
    parameter int WORDS = 4800
) (
    input  logic         clk,
    input  logic         rst,
    input  logic         gate,
    input  logic         go,

    input  logic [127:0] wword,
    input  logic         wword_valid,
    output logic         wword_ready,

    output logic [127:0] rword,
    output logic         rword_valid,
    input  logic         rword_ready,

    output logic [27:0]  awaddr,
    output logic [7:0]   awlen,
    output logic [2:0]   awsize,
    output logic [1:0]   awburst,
    output logic         awvalid,
    input  logic         awready,

    output logic [127:0] wdata,
    output logic [15:0]  wstrb,
    output logic         wlast,
    output logic         wvalid,
    input  logic         wready,

    input  logic [1:0]   bresp,
    input  logic         bvalid,
    output logic         bready,

    output logic [27:0]  araddr,
    output logic [7:0]   arlen,
    output logic [2:0]   arsize,
    output logic [1:0]   arburst,
    output logic         arvalid,
    input  logic         arready,

    input  logic [127:0] rdata,
    input  logic [1:0]   rresp,
    input  logic         rlast,
    input  logic         rvalid,
    output logic         rready
);

    localparam int IDLE = 0;
    localparam int TAKE = 1;
    localparam int AW   = 2;
    localparam int WW   = 3;
    localparam int B    = 4;
    localparam int AR   = 5;
    localparam int RR   = 6;
    localparam int HOLD = 7;
    localparam int DN   = 8;

    logic [3:0]  state;
    logic        ran;
    logic [15:0] word_i;
    logic [127:0] beat;

    assign wword_ready = (state == TAKE[3:0]);
    assign awaddr      = {8'd0, word_i, 4'd0};
    assign awlen       = 8'd0;
    assign awsize      = 3'd4;
    assign awburst     = 2'b01;
    assign wdata       = beat;
    assign wstrb       = 16'hFFFF;
    assign wlast       = 1'b1;
    assign araddr      = {8'd0, word_i, 4'd0};
    assign arlen       = 8'd0;
    assign arsize      = 3'd4;
    assign arburst     = 2'b01;

    always_ff @(posedge clk) begin
        if (rst) begin
            state       <= IDLE[3:0];
            ran         <= 1'b0;
            word_i      <= 16'd0;
            beat        <= 128'd0;
            awvalid     <= 1'b0;
            wvalid      <= 1'b0;
            bready      <= 1'b0;
            arvalid     <= 1'b0;
            rready      <= 1'b0;
            rword       <= 128'd0;
            rword_valid <= 1'b0;
        end
        else begin
            if (!go)
                ran <= 1'b0;

            case (state)
                IDLE[3:0]: begin
                    if (go && gate && !ran) begin
                        ran    <= 1'b1;
                        word_i <= 16'd0;
                        state  <= TAKE[3:0];
                    end
                end
                TAKE[3:0]: begin
                    if (wword_valid) begin
                        beat    <= wword;
                        awvalid <= 1'b1;
                        state   <= AW[3:0];
                    end
                end
                AW[3:0]: begin
                    if (awvalid && awready) begin
                        awvalid <= 1'b0;
                        wvalid  <= 1'b1;
                        state   <= WW[3:0];
                    end
                end
                WW[3:0]: begin
                    if (wvalid && wready) begin
                        wvalid <= 1'b0;
                        bready <= 1'b1;
                        state  <= B[3:0];
                    end
                end
                B[3:0]: begin
                    if (bvalid && bready) begin
                        bready <= 1'b0;
                        if (word_i == 16'(WORDS - 1)) begin
                            word_i  <= 16'd0;
                            arvalid <= 1'b1;
                            state   <= AR[3:0];
                        end
                        else begin
                            word_i <= word_i + 16'd1;
                            state  <= TAKE[3:0];
                        end
                    end
                end
                AR[3:0]: begin
                    if (arvalid && arready) begin
                        arvalid <= 1'b0;
                        rready  <= 1'b1;
                        state   <= RR[3:0];
                    end
                end
                RR[3:0]: begin
                    if (rvalid && rready) begin
                        rready      <= 1'b0;
                        rword       <= rdata;
                        rword_valid <= 1'b1;
                        if (word_i == 16'(WORDS - 1))
                            state <= DN[3:0];
                        else
                            state <= HOLD[3:0];
                    end
                end
                HOLD[3:0]: begin
                    if (rword_valid && rword_ready) begin
                        rword_valid <= 1'b0;
                        word_i      <= word_i + 16'd1;
                        arvalid     <= 1'b1;
                        state       <= AR[3:0];
                    end
                end
                default: begin
                    if (rword_valid && rword_ready) begin
                        rword_valid <= 1'b0;
                        state       <= IDLE[3:0];
                    end
                end
            endcase
        end
    end

endmodule
