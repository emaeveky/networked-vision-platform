module img_threshold (
    input  logic       clk,
    input  logic       rst,
    input  logic [7:0] threshold,

    input  logic       s_valid,
    input  logic [7:0] s_data,
    input  logic       s_last,
    output logic       s_ready,

    output logic       m_valid,
    output logic [7:0] m_data,
    output logic       m_last,
    input  logic       m_ready
);

    assign s_ready = !m_valid || m_ready;

    always_ff @(posedge clk) begin
        if (rst) begin
            m_valid <= 1'b0;
            m_data  <= 8'd0;
            m_last  <= 1'b0;
        end
        else if (s_ready) begin
            m_valid <= s_valid;
            if (s_valid) begin
                m_data <= (s_data > threshold) ? 8'hFF : 8'h00;
                m_last <= s_last;
            end
        end
    end

endmodule
