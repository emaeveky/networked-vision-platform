module packet_tracker (
    input  logic       clk,
    input  logic       rst,
    input  logic       packet_valid,
    input  logic [5:0] packet_id,

    output logic [63:0] received_map,
    output logic [6:0]  unique_packet_count,
    output logic        duplicate_packet,
    output logic        frame_complete
);

always_ff @(posedge clk) begin
    if (rst) begin
        received_map        <= 64'b0;
        unique_packet_count <= 7'd0;
        duplicate_packet    <= 1'b0;
        frame_complete      <= 1'b0;
    end
    else begin
        // This output is a one-clock pulse, so clear it by default.
        duplicate_packet <= 1'b0;

        if (packet_valid && !frame_complete) begin
            if (received_map[packet_id]) begin
                // This packet ID was already recorded.
                duplicate_packet <= 1'b1;
            end
            else begin
                // Record the first arrival of this packet ID.
                received_map[packet_id] <= 1'b1;
                unique_packet_count    <= unique_packet_count + 7'd1;

                // The old count is 63 when the 64th unique packet arrives.
                if (unique_packet_count == 7'd63) begin
                    frame_complete <= 1'b1;
                end
            end
        end
    end
end

endmodule
