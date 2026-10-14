// Frozen reference frame. A capture copies the display bank, one pixel per
// clock, through the shared frame memory read port. Later motion samples this
// copy instead of the previous display bank, so a still object stays detected.
module bg_frame #(
    parameter int FRAME_BYTES = 76800
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

    (* ram_style = "block" *) reg [7:0] mem [0:FRAME_BYTES-1];
    logic [16:0] cap_addr;
    logic        cap_hold;

    assign rd_en   = busy && (cap_addr < 17'(FRAME_BYTES));
    assign rd_addr = cap_addr;

    always_ff @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            busy        <= 1'b0;
            armed       <= 1'b0;
            cap_addr    <= 17'd0;
            cap_hold    <= 1'b0;
            sample_data <= 8'd0;
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
                if (cap_hold)
                    mem[cap_addr - 17'd1] <= rd_data;
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

            if (sample_en)
                sample_data <= mem[sample_addr];
        end
    end

endmodule
