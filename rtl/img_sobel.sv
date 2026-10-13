(* DONT_TOUCH = "yes", KEEP_HIERARCHY = "yes" *)
module img_sobel #(
    parameter int WIDTH  = 8,
    parameter int HEIGHT = 8
) (
    input  logic       clk,
    input  logic       rst,

    input  logic       s_valid,
    input  logic [7:0] s_data,
    input  logic       s_last,
    output logic       s_ready,

    output logic       m_valid,
    output logic [7:0] m_data,
    output logic       m_last,
    input  logic       m_ready
);

    localparam int XW   = $clog2(WIDTH);
    localparam int BITS = WIDTH * 8;

    // Fixed 8-bit shift: the byte leaving the delay line is the pixel from
    // one row ago. It is a register output, sampled with the taps below.
    (* srl_style = "registers" *) logic [BITS-1:0] row_d1;
    (* srl_style = "registers" *) logic [BITS-1:0] row_d2;
    wire  [7:0] prev1 = row_d1[BITS-1 -: 8];
    wire  [7:0] prev2 = row_d2[BITS-1 -: 8];

    logic [XW-1:0] col;
    logic [15:0]   row;

    logic [7:0] a1, a2;
    logic [7:0] b1, b2;
    logic [7:0] c1, c2;

    wire interior = (row >= 16'd2) && (col >= 2);
    // Bottom-right pixel of the 3x3 is the one being accepted. Center is
    // (col-1, row-1), so the first emitted center is (1, 1).
    wire signed [11:0] gx = -12'(a1) + 12'(prev2)
                          - (12'(b1) <<< 1) + (12'(prev1) <<< 1)
                          - 12'(c1) + 12'(s_data);
    wire signed [11:0] gy = -12'(a1) - (12'(a2) <<< 1) - 12'(prev2)
                          + 12'(c1) + (12'(c2) <<< 1) + 12'(s_data);
    wire [11:0] ax = gx[11] ? 12'(-gx) : 12'(gx);
    wire [11:0] ay = gy[11] ? 12'(-gy) : 12'(gy);
    wire [11:0] mag = ax + ay;
    wire [7:0] mag8 = (mag > 12'd255) ? 8'hFF : mag[7:0];

    // Same handshake as img_threshold: the result register and its valid
    // bit update together on the accept cycle. A second pipeline stage here
    // was synthesized one sample behind the valid bit.
    assign s_ready = !m_valid || m_ready;

    always_ff @(posedge clk) begin
        if (rst) begin
            col     <= '0;
            row     <= 16'd0;
            row_d1  <= '0;
            row_d2  <= '0;
            a1 <= 8'd0; a2 <= 8'd0;
            b1 <= 8'd0; b2 <= 8'd0;
            c1 <= 8'd0; c2 <= 8'd0;
            m_valid <= 1'b0;
            m_data  <= 8'd0;
            m_last  <= 1'b0;
        end
        else if (s_ready) begin
            if (s_valid && interior) begin
                m_valid <= 1'b1;
                m_last  <= s_last;
                m_data  <= mag8;
            end
            else
                m_valid <= 1'b0;

            if (s_valid) begin
                a1 <= a2; a2 <= prev2;
                b1 <= b2; b2 <= prev1;
                c1 <= c2; c2 <= s_data;
                row_d1 <= {row_d1[BITS-9:0], s_data};
                row_d2 <= {row_d2[BITS-9:0], prev1};

                if (s_last) begin
                    col <= '0;
                    row <= 16'd0;
                end
                else if (col == XW'(WIDTH - 1)) begin
                    col <= '0;
                    row <= row + 16'd1;
                end
                else
                    col <= col + 1'b1;
            end
        end
    end

endmodule
