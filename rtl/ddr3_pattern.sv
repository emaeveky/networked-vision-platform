// Write a fixed pattern into DDR and read it back. One burst is BEATS words
// of 16 bytes. BURSTS * BEATS * 16 bytes is the checked region. The hardware
// check covers one 320x240 Mono8 frame (75 * 64 * 16 = 76800).
module ddr3_pattern #(
    parameter int BEATS  = 64,
    parameter int BURSTS = 75
) (
    input  logic         clk,
    input  logic         rst,
    input  logic         calib,

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
    output logic         rready,

    output logic         done,
    output logic         pass
);

    localparam int AW = 0;
    localparam int W  = 1;
    localparam int B  = 2;
    localparam int AR = 3;
    localparam int R  = 4;
    localparam int DN = 5;

    logic [2:0]  state;
    logic        fail;
    logic [6:0]  burst_i;
    logic [7:0]  beat_i;

    wire [27:0] burst_addr = burst_i * 28'(BEATS * 16);
    wire [27:0] beat_addr  = burst_addr + (beat_i * 28'd16);

    function automatic logic [127:0] beat_data(input logic [27:0] base);
        logic [127:0] word;
        integer i;
        begin
            word = '0;
            for (i = 0; i < 16; i = i + 1)
                word[i*8 +: 8] = base[7:0] + base[15:8] + 8'(i);
            beat_data = word;
        end
    endfunction

    assign awaddr  = burst_addr;
    assign awlen   = 8'(BEATS - 1);
    assign awsize  = 3'd4;
    assign awburst = 2'b01;
    assign wdata   = beat_data(beat_addr);
    assign wstrb   = 16'hFFFF;
    assign wlast   = (beat_i == 8'(BEATS - 1));
    assign araddr  = burst_addr;
    assign arlen   = 8'(BEATS - 1);
    assign arsize  = 3'd4;
    assign arburst = 2'b01;

    always_ff @(posedge clk) begin
        if (rst) begin
            state   <= 3'(AW);
            fail    <= 1'b0;
            burst_i <= 7'd0;
            beat_i  <= 8'd0;
            awvalid <= 1'b0;
            wvalid  <= 1'b0;
            bready  <= 1'b0;
            arvalid <= 1'b0;
            rready  <= 1'b0;
            done    <= 1'b0;
            pass    <= 1'b0;
        end
        else begin
            case (state)
                3'(AW): begin
                    if (!calib) begin
                        awvalid <= 1'b0;
                    end
                    else begin
                        awvalid <= 1'b1;
                        if (awvalid && awready) begin
                            awvalid <= 1'b0;
                            wvalid  <= 1'b1;
                            beat_i  <= 8'd0;
                            state   <= 3'(W);
                        end
                    end
                end
                3'(W): begin
                    if (wvalid && wready) begin
                        if (beat_i == 8'(BEATS - 1)) begin
                            wvalid <= 1'b0;
                            bready <= 1'b1;
                            state  <= 3'(B);
                        end
                        else
                            beat_i <= beat_i + 8'd1;
                    end
                end
                3'(B): begin
                    if (bvalid && bready) begin
                        bready <= 1'b0;
                        if (bresp != 2'b00)
                            fail <= 1'b1;
                        if (burst_i == 7'(BURSTS - 1)) begin
                            burst_i <= 7'd0;
                            arvalid <= 1'b1;
                            state   <= 3'(AR);
                        end
                        else begin
                            burst_i <= burst_i + 7'd1;
                            awvalid <= 1'b1;
                            state   <= 3'(AW);
                        end
                    end
                end
                3'(AR): begin
                    if (arvalid && arready) begin
                        arvalid <= 1'b0;
                        rready  <= 1'b1;
                        beat_i  <= 8'd0;
                        state   <= 3'(R);
                    end
                end
                3'(R): begin
                    if (rvalid && rready) begin
                        if (rresp != 2'b00 || rdata != beat_data(beat_addr))
                            fail <= 1'b1;
                        if (beat_i == 8'(BEATS - 1)) begin
                            rready <= 1'b0;
                            if (burst_i == 7'(BURSTS - 1)) begin
                                done  <= 1'b1;
                                pass  <= !fail && (rresp == 2'b00) && (rdata == beat_data(beat_addr));
                                state <= 3'(DN);
                            end
                            else begin
                                burst_i <= burst_i + 7'd1;
                                arvalid <= 1'b1;
                                state   <= 3'(AR);
                            end
                        end
                        else
                            beat_i <= beat_i + 8'd1;
                    end
                end
                default: begin
                    done <= 1'b1;
                    pass <= !fail;
                end
            endcase
        end
    end

endmodule
