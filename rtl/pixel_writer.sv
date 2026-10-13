module pixel_writer (
    input  logic        clk,
    input  logic        rst,

    input  logic        pkt_accept,
    input  logic [5:0] packet_id,
    input  logic [10:0] payload_len,

    input  logic        data_valid,
    input  logic [7:0]  data,
    input  logic        data_last,

    output logic        mem_we,
    output logic [16:0] mem_addr,
    output logic [7:0]  mem_wdata,
    output logic        payload_error,
    output logic        busy
);

    localparam int PACKET_BYTES = 1200;

    logic        active;
    logic [10:0] count;
    logic [16:0] base;

    always_ff @(posedge clk) begin
        if (rst) begin
            active        <= 1'b0;
            count         <= 11'd0;
            base          <= 17'd0;
            mem_we        <= 1'b0;
            mem_addr      <= 17'd0;
            mem_wdata     <= 8'd0;
            payload_error <= 1'b0;
        end
        else begin
            mem_we        <= 1'b0;
            payload_error <= 1'b0;

            if (pkt_accept) begin
                if (payload_len == 11'(PACKET_BYTES)) begin
                    active <= 1'b1;
                    count  <= 11'd0;
                    base   <= 17'd1200 * {11'd0, packet_id};
                end
                else begin
                    payload_error <= 1'b1;
                    active        <= 1'b0;
                end
            end
            else if (active && data_valid) begin
                mem_we    <= 1'b1;
                mem_addr  <= base + {6'd0, count};
                mem_wdata <= data;
                count     <= count + 11'd1;

                if (data_last || (count == 11'(PACKET_BYTES - 1)))
                    active <= 1'b0;
            end
        end
    end

    assign busy = active;

endmodule
