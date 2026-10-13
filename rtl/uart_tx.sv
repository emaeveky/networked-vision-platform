module uart_tx #(
    parameter int CLOCK_HZ = 12_000_000,
    parameter int BAUD     = 1_000_000
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       data_valid,
    input  logic [7:0] data,
    output logic       ready,
    output logic       serial_out
);

    localparam int CLKS_PER_BIT = CLOCK_HZ / BAUD;
    localparam int COUNT_W = $clog2(CLKS_PER_BIT + 1);

    logic [9:0] shift;
    logic [3:0] bits_left;
    logic [COUNT_W-1:0] clock_count;

    assign ready = (bits_left == 0);
    assign serial_out = ready ? 1'b1 : shift[0];

    always_ff @(posedge clk) begin
        if (rst) begin
            shift       <= 10'h3FF;
            bits_left   <= 4'd0;
            clock_count <= '0;
        end
        else if (ready) begin
            clock_count <= '0;
            if (data_valid) begin
                // UART sends start, eight data bits LSB-first, then stop.
                shift     <= {1'b1, data, 1'b0};
                bits_left <= 4'd10;
            end
        end
        else if (clock_count == COUNT_W'(CLKS_PER_BIT - 1)) begin
            clock_count <= '0;
            shift       <= {1'b1, shift[9:1]};
            bits_left   <= bits_left - 1'b1;
        end
        else begin
            clock_count <= clock_count + 1'b1;
        end
    end

endmodule
