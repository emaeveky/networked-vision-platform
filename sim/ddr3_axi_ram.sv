// Accepts one write burst or one read burst at a time.
module ddr3_axi_ram #(
    parameter int BYTES = 256
) (
    input  logic         clk,
    input  logic         rst,

    input  logic [27:0]  awaddr,
    input  logic [7:0]   awlen,
    input  logic         awvalid,
    output logic         awready,

    input  logic [127:0] wdata,
    input  logic         wlast,
    input  logic         wvalid,
    output logic         wready,

    output logic [1:0]   bresp,
    output logic         bvalid,
    input  logic         bready,

    input  logic [27:0]  araddr,
    input  logic [7:0]   arlen,
    input  logic         arvalid,
    output logic         arready,

    output logic [127:0] rdata,
    output logic [1:0]   rresp,
    output logic         rlast,
    output logic         rvalid,
    input  logic         rready
);

    localparam int IDLE  = 0;
    localparam int WRITE = 1;
    localparam int RESP  = 2;
    localparam int READ  = 3;

    reg [7:0] mem [0:BYTES-1];
    logic [1:0]  state;
    logic [27:0] addr;
    logic [7:0]  left;

    integer i;

    assign awready = (state == IDLE);
    assign arready = (state == IDLE) && !awvalid;
    assign wready  = (state == WRITE);
    assign bresp   = 2'b00;
    assign rresp   = 2'b00;

    always_ff @(posedge clk) begin
        if (rst) begin
            state  <= IDLE[1:0];
            bvalid <= 1'b0;
            rvalid <= 1'b0;
            rlast  <= 1'b0;
            addr   <= 28'd0;
            left   <= 8'd0;
            rdata  <= 128'd0;
        end
        else begin
            case (state)
                IDLE[1:0]: begin
                    if (awvalid) begin
                        state <= WRITE[1:0];
                        addr  <= awaddr;
                        left  <= awlen;
                    end
                    else if (arvalid) begin
                        state <= READ[1:0];
                        addr  <= araddr;
                        left  <= arlen;
                    end
                end
                WRITE[1:0]: begin
                    if (wvalid) begin
                        for (i = 0; i < 16; i = i + 1)
                            mem[addr + 28'(i)] <= wdata[i*8 +: 8];
                        if (left == 8'd0 || wlast) begin
                            state  <= RESP[1:0];
                            bvalid <= 1'b1;
                        end
                        else begin
                            left <= left - 8'd1;
                            addr <= addr + 28'd16;
                        end
                    end
                end
                RESP[1:0]: begin
                    if (bvalid && bready) begin
                        bvalid <= 1'b0;
                        state  <= IDLE[1:0];
                    end
                end
                default: begin
                    if (rvalid && rready) begin
                        if (left == 8'd0) begin
                            rvalid <= 1'b0;
                            rlast  <= 1'b0;
                            state  <= IDLE[1:0];
                        end
                        else begin
                            left  <= left - 8'd1;
                            addr  <= addr + 28'd16;
                            rlast <= (left == 8'd1);
                            for (i = 0; i < 16; i = i + 1)
                                rdata[i*8 +: 8] <= mem[addr + 28'd16 + 28'(i)];
                        end
                    end
                    else begin
                        rvalid <= 1'b1;
                        rlast  <= (left == 8'd0);
                        for (i = 0; i < 16; i = i + 1)
                            rdata[i*8 +: 8] <= mem[addr + 28'(i)];
                    end
                end
            endcase
        end
    end

endmodule
