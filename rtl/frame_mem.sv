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
    localparam int CHUNK = 4096;
    localparam int NCHUNK = 19;

    // One 4K chunk is one RAMB36. A single 76800-deep array was mapping to
    // 24 of them, and three frames of that used every block RAM on the part.
    wire [4:0]  wr_chunk = wr_addr[16:12];
    wire [11:0] wr_off   = wr_addr[11:0];
    wire [4:0]  rd_chunk = rd_addr[16:12];
    wire [11:0] rd_off   = rd_addr[11:0];
    wire        wr_ok    = wr_en && (wr_addr < 17'(FRAME_BYTES));
    wire        rd_ok    = rd_en && (rd_addr < 17'(FRAME_BYTES));

    logic [7:0] rd0_word [0:NCHUNK-1];
    logic [7:0] rd1_word [0:NCHUNK-1];
    logic [4:0] rd_chunk_q;
    logic       rd_bank_q;

    generate
        for (genvar ci = 0; ci < NCHUNK; ci++) begin : gchunk
            (* ram_style = "block" *) reg [7:0] b0 [0:CHUNK-1];
            (* ram_style = "block" *) reg [7:0] b1 [0:CHUNK-1];
            logic [7:0] rd0;
            logic [7:0] rd1;

            always_ff @(posedge clk) begin
                if (wr_ok && wr_chunk == 5'(ci) && !wr_bank)
                    b0[wr_off] <= wr_data;
                if (wr_ok && wr_chunk == 5'(ci) && wr_bank)
                    b1[wr_off] <= wr_data;
                if (rd_ok && rd_chunk == 5'(ci)) begin
                    rd0 <= b0[rd_off];
                    rd1 <= b1[rd_off];
                end
            end

            assign rd0_word[ci] = rd0;
            assign rd1_word[ci] = rd1;
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (rd_ok) begin
            rd_chunk_q <= rd_chunk;
            rd_bank_q  <= rd_bank;
        end
    end

    assign rd_data = rd_bank_q ? rd1_word[rd_chunk_q] : rd0_word[rd_chunk_q];

    // synthesis translate_off
    // Simulation-only preload. A variable generate index is not legal here,
    // so each 4K chunk is selected explicitly.
    task automatic poke(input integer bank, input integer addr, input logic [7:0] value);
        begin
            case (addr[16:12])
                5'd0:  if (bank == 0) gchunk[0].b0[addr[11:0]]  = value; else gchunk[0].b1[addr[11:0]]  = value;
                5'd1:  if (bank == 0) gchunk[1].b0[addr[11:0]]  = value; else gchunk[1].b1[addr[11:0]]  = value;
                5'd2:  if (bank == 0) gchunk[2].b0[addr[11:0]]  = value; else gchunk[2].b1[addr[11:0]]  = value;
                5'd3:  if (bank == 0) gchunk[3].b0[addr[11:0]]  = value; else gchunk[3].b1[addr[11:0]]  = value;
                5'd4:  if (bank == 0) gchunk[4].b0[addr[11:0]]  = value; else gchunk[4].b1[addr[11:0]]  = value;
                5'd5:  if (bank == 0) gchunk[5].b0[addr[11:0]]  = value; else gchunk[5].b1[addr[11:0]]  = value;
                5'd6:  if (bank == 0) gchunk[6].b0[addr[11:0]]  = value; else gchunk[6].b1[addr[11:0]]  = value;
                5'd7:  if (bank == 0) gchunk[7].b0[addr[11:0]]  = value; else gchunk[7].b1[addr[11:0]]  = value;
                5'd8:  if (bank == 0) gchunk[8].b0[addr[11:0]]  = value; else gchunk[8].b1[addr[11:0]]  = value;
                5'd9:  if (bank == 0) gchunk[9].b0[addr[11:0]]  = value; else gchunk[9].b1[addr[11:0]]  = value;
                5'd10: if (bank == 0) gchunk[10].b0[addr[11:0]] = value; else gchunk[10].b1[addr[11:0]] = value;
                5'd11: if (bank == 0) gchunk[11].b0[addr[11:0]] = value; else gchunk[11].b1[addr[11:0]] = value;
                5'd12: if (bank == 0) gchunk[12].b0[addr[11:0]] = value; else gchunk[12].b1[addr[11:0]] = value;
                5'd13: if (bank == 0) gchunk[13].b0[addr[11:0]] = value; else gchunk[13].b1[addr[11:0]] = value;
                5'd14: if (bank == 0) gchunk[14].b0[addr[11:0]] = value; else gchunk[14].b1[addr[11:0]] = value;
                5'd15: if (bank == 0) gchunk[15].b0[addr[11:0]] = value; else gchunk[15].b1[addr[11:0]] = value;
                5'd16: if (bank == 0) gchunk[16].b0[addr[11:0]] = value; else gchunk[16].b1[addr[11:0]] = value;
                5'd17: if (bank == 0) gchunk[17].b0[addr[11:0]] = value; else gchunk[17].b1[addr[11:0]] = value;
                default: if (bank == 0) gchunk[18].b0[addr[11:0]] = value; else gchunk[18].b1[addr[11:0]] = value;
            endcase
        end
    endtask
    // synthesis translate_on

endmodule
