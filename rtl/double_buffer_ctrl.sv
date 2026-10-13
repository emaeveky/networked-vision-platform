module double_buffer_ctrl (
    input  logic clk,
    input  logic rst,

    input  logic frame_complete,
    input  logic swap_ready,

    output logic wr_bank,
    output logic rd_bank,
    output logic wr_allowed,
    output logic swap_pulse,
    output logic pending_display
);

    logic complete_latched;
    logic frame_complete_d;

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_bank          <= 1'b0;
            rd_bank          <= 1'b1;
            complete_latched <= 1'b0;
            swap_pulse      <= 1'b0;
            frame_complete_d <= 1'b0;
        end
        else begin
            frame_complete_d <= frame_complete;

            if (frame_complete && !frame_complete_d)
                complete_latched <= 1'b1;

            if (complete_latched && swap_ready) begin
                rd_bank          <= wr_bank;
                wr_bank          <= ~wr_bank;
                complete_latched <= 1'b0;
                swap_pulse      <= 1'b1;
            end
            else begin
                swap_pulse <= 1'b0;
            end
        end
    end

    assign pending_display = complete_latched;
    assign wr_allowed      = !complete_latched;

endmodule
