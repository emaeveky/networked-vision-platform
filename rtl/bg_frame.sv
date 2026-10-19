// Frozen reference frame. A capture copies the display bank, one pixel per
// clock, through the shared frame memory read port. Later motion samples this
// copy instead of the previous display bank, so a still object stays detected.
module bg_frame #(
    parameter int FRAME_BYTES = 76800,
    // 4096 packs one RAMB36. The small testbench uses a chunk of its own size.
    parameter int CHUNK = 4096
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        start,
    input  logic        abort,
    input  logic [7:0]  rd_data,

    output logic        rd_en,
    output logic [16:0] rd_addr,
    output logic        busy,
    output logic        armed,
    output logic        done,

    input  logic        sample_en,
    input  logic [16:0] sample_addr,
    output logic [7:0]  sample_data
);

    logic [16:0] cap_addr;
    logic        cap_hold;
    // Same 4K split as frame_mem. A short simulation uses one small array.
    wire         mem_we = busy && cap_hold && !abort;

    assign rd_en   = busy && (cap_addr < 17'(FRAME_BYTES));
    assign rd_addr = cap_addr;

    always_ff @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            busy        <= 1'b0;
            armed       <= 1'b0;
            cap_addr    <= 17'd0;
            cap_hold    <= 1'b0;
        end
        else begin
            if (start && !busy) begin
                busy     <= 1'b1;
                armed    <= 1'b0;
                cap_addr <= 17'd0;
                cap_hold <= 1'b0;
            end
            else if (abort && busy) begin
                // A frame that arrives mid-copy leaves a half-written reference.
                busy     <= 1'b0;
                armed    <= 1'b0;
                cap_hold <= 1'b0;
            end
            else if (busy) begin
                if (cap_hold && cap_addr == 17'(FRAME_BYTES)) begin
                    busy     <= 1'b0;
                    armed    <= 1'b1;
                    done     <= 1'b1;
                    cap_hold <= 1'b0;
                end
                else begin
                    cap_hold <= 1'b1;
                    cap_addr <= cap_addr + 17'd1;
                end
            end
        end
    end

    localparam int NCHUNK = (FRAME_BYTES + CHUNK - 1) / CHUNK;
    logic [7:0] chunk_rd [0:NCHUNK-1];
    logic [4:0] sample_chunk_q;
    wire [16:0] wr_addr = cap_addr - 17'd1;

    generate
        for (genvar ci = 0; ci < NCHUNK; ci++) begin : gchunk
            (* ram_style = "block" *) reg [7:0] mem [0:CHUNK-1];
            logic [7:0] rd;

            always_ff @(posedge clk) begin
                if (mem_we && (wr_addr / CHUNK) == ci)
                    mem[wr_addr % CHUNK] <= rd_data;
                if (sample_en && (sample_addr / CHUNK) == ci)
                    rd <= mem[sample_addr % CHUNK];
            end

            assign chunk_rd[ci] = rd;
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (rst)
            sample_chunk_q <= 5'd0;
        else if (sample_en)
            sample_chunk_q <= 5'(sample_addr / CHUNK);
    end

    // The selected chunk's read register updates on the same edge as the
    // select, so the byte is valid the cycle after sample_en.
    assign sample_data = chunk_rd[sample_chunk_q];

endmodule
