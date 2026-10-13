module uart_rx #(
    parameter int CLOCK_HZ = 12_000_000,
    parameter int BAUD     = 1_000_000
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       serial_in,
    output logic       data_valid,
    output logic [7:0] data,
    output logic       framing_error
);

    localparam int CLKS_PER_BIT = CLOCK_HZ / BAUD;
    localparam int COUNT_W = $clog2(CLKS_PER_BIT + 1);

    typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
    state_t state;

    logic serial_meta;
    logic serial_sync;
    logic [COUNT_W-1:0] clock_count;
    logic [2:0] bit_index;
    logic [7:0] shift;

    // The two flip-flops keep the asynchronous FTDI signal away from the FSM.
    always_ff @(posedge clk) begin
        serial_meta <= serial_in;
        serial_sync <= serial_meta;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state         <= IDLE;
            clock_count   <= '0;
            bit_index     <= 3'd0;
            shift         <= 8'd0;
            data          <= 8'd0;
            data_valid    <= 1'b0;
            framing_error <= 1'b0;
        end
        else begin
            data_valid    <= 1'b0;
            framing_error <= 1'b0;

            case (state)
                IDLE: begin
                    clock_count <= '0;
                    if (!serial_sync)
                        state <= START;
                end
                START: begin
                    // Re-sample in the middle of the start bit to reject glitches.
                    if (clock_count == COUNT_W'(CLKS_PER_BIT / 2 - 1)) begin
                        clock_count <= '0;
                        if (!serial_sync) begin
                            bit_index <= 3'd0;
                            state <= DATA;
                        end
                        else begin
                            state <= IDLE;
                        end
                    end
                    else begin
                        clock_count <= clock_count + 1'b1;
                    end
                end
                DATA: begin
                    if (clock_count == COUNT_W'(CLKS_PER_BIT - 1)) begin
                        clock_count <= '0;
                        shift[bit_index] <= serial_sync;
                        if (bit_index == 3'd7)
                            state <= STOP;
                        else
                            bit_index <= bit_index + 1'b1;
                    end
                    else begin
                        clock_count <= clock_count + 1'b1;
                    end
                end
                STOP: begin
                    if (clock_count == COUNT_W'(CLKS_PER_BIT - 1)) begin
                        clock_count <= '0;
                        state <= IDLE;
                        if (serial_sync) begin
                            data       <= shift;
                            data_valid <= 1'b1;
                        end
                        else begin
                            framing_error <= 1'b1;
                        end
                    end
                    else begin
                        clock_count <= clock_count + 1'b1;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
