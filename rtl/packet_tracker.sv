module packet_tracker (
    input  logic       clk,
    input  logic       rst,
    input  logic       clear,
    input  logic       packet_valid,
    input  logic [5:0] packet_id,

    output logic [63:0] received_map,
    output logic [6:0]  unique_packet_count,
    output logic        duplicate_packet,
    output logic        frame_complete
);

    logic start_fresh;

    always_comb begin
        start_fresh = rst || clear;
    end

    always_ff @(posedge clk) begin
        if (start_fresh) begin
            received_map        <= 64'b0;
            unique_packet_count <= 7'd0;
            duplicate_packet    <= 1'b0;
            frame_complete      <= 1'b0;

            // A header that arrives with clear starts the new frame this cycle.
            if (!rst && packet_valid) begin
                received_map[packet_id] <= 1'b1;
                unique_packet_count       <= 7'd1;
            end
        end
        else begin
            duplicate_packet <= 1'b0;

            if (packet_valid && !frame_complete) begin
                if (received_map[packet_id]) begin
                    duplicate_packet <= 1'b1;
                end
                else begin
                    received_map[packet_id] <= 1'b1;
                    unique_packet_count    <= unique_packet_count + 7'd1;

                    if (unique_packet_count == 7'd63) begin
                        frame_complete <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
