module frame_mem (
    input  logic        clk,

    input  logic        wr_en,
    input  logic        wr_bank,
    input  logic [16:0] wr_addr,
    input  logic [7:0]  wr_data,

    input  logic        rd_en,
    input  logic        rd_bank,
    input  logic [16:0] rd_addr,
    output logic [7:0]  rd_data
);

    localparam int FRAME_BYTES = 76800;

    // Each array is one simple dual-port RAM: one write port for camera
    // ingress and one synchronous read port for display/UART readback.
    // Separate read registers are important for Vivado BRAM inference; a
    // ternary selecting between two arrays maps this storage into LUT RAM.
    (* ram_style = "block" *) reg [7:0] bank0 [0:FRAME_BYTES-1];
    (* ram_style = "block" *) reg [7:0] bank1 [0:FRAME_BYTES-1];
    logic [7:0] bank0_rd;
    logic [7:0] bank1_rd;
    logic       rd_bank_q;

    wire [16:0] wr_idx = (wr_addr < 17'(FRAME_BYTES)) ? wr_addr : 17'd0;
    wire [16:0] rd_idx = (rd_addr < 17'(FRAME_BYTES)) ? rd_addr : 17'd0;

    always_ff @(posedge clk) begin
        if (wr_en) begin
            if (wr_bank == 1'b0)
                bank0[wr_idx] <= wr_data;
            else
                bank1[wr_idx] <= wr_data;
        end

        if (rd_en) begin
            bank0_rd  <= bank0[rd_idx];
            bank1_rd  <= bank1[rd_idx];
            rd_bank_q <= rd_bank;
        end
    end

    assign rd_data = rd_bank_q ? bank1_rd : bank0_rd;

endmodule
