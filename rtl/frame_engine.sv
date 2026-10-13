module frame_engine (
    input  logic        clk,
    input  logic        rst,
    input  logic        wr_allowed,

    input  logic        hdr_valid,
    input  logic [15:0] frame_id,
    input  logic [5:0]  packet_id,
    input  logic        crc_ok,
    input  logic        crc_error,

    output logic        pkt_accept,
    output logic        duplicate_packet,
    output logic        late_packet,
    output logic        incomplete_frame,
    output logic        dropped_frame,
    output logic        frame_complete,
    output logic [15:0] current_frame_id,
    output logic [6:0]  unique_packet_count,
    output logic [63:0] received_map,
    output logic        have_frame
);

    logic        tracker_valid;
    logic        tracker_clear;
    logic        have_frame_r;
    logic [15:0] current_frame_id_r;
    logic        complete_seen;
    logic [15:0] fid_delta;
    logic        fid_older;
    logic        commit_later;
    logic        flag_duplicate;
    logic        arm;
    logic [5:0]  commit_pid;

    // Modular distance so 0xFFFF -> 0x0000 counts as "newer", not "late".
    // Anything up to 32767 frames ahead is new; behind is late.
    assign fid_delta = frame_id - current_frame_id_r;
    assign fid_older = fid_delta[15];

    packet_tracker tracker (
        .clk                 (clk),
        .rst                 (rst),
        .clear               (tracker_clear),
        .packet_valid        (tracker_valid),
        .packet_id           ((crc_ok && arm) ? commit_pid : packet_id),
        .received_map        (received_map),
        .unique_packet_count (unique_packet_count),
        .duplicate_packet    (duplicate_packet),
        .frame_complete      (frame_complete)
    );

    always_comb begin
        tracker_valid    = 1'b0;
        tracker_clear     = 1'b0;
        pkt_accept        = 1'b0;
        late_packet       = 1'b0;
        incomplete_frame  = 1'b0;
        dropped_frame     = 1'b0;
        commit_later      = 1'b0;
        flag_duplicate    = 1'b0;

        if (hdr_valid) begin
            if (!have_frame_r) begin
                if (wr_allowed) begin
                    pkt_accept   = 1'b1;
                    commit_later = 1'b1;
                end
                else begin
                    dropped_frame = 1'b1;
                end
            end
            else if (frame_id == current_frame_id_r) begin
                if (!complete_seen) begin
                    if (received_map[packet_id])
                        flag_duplicate = 1'b1;
                    else begin
                        pkt_accept   = 1'b1;
                        commit_later = 1'b1;
                    end
                end
            end
            else if (fid_older) begin
                late_packet = 1'b1;
            end
            else begin
                if (wr_allowed || complete_seen) begin
                    if (!complete_seen) begin
                        incomplete_frame = 1'b1;
                    end
                    if (wr_allowed) begin
                        tracker_clear = 1'b1;
                        pkt_accept    = 1'b1;
                        commit_later  = 1'b1;
                    end
                    else begin
                        dropped_frame = 1'b1;
                    end
                end
                else begin
                    dropped_frame = 1'b1;
                end
            end
        end

        // The received-map bit is set only after the payload CRC matches.
        // A duplicate is flagged at the header, because that packet is already kept.
        if (crc_ok && arm)
            tracker_valid = 1'b1;
        else if (flag_duplicate)
            tracker_valid = 1'b1;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            have_frame_r        <= 1'b0;
            current_frame_id_r <= 16'd0;
            complete_seen      <= 1'b0;
            arm                <= 1'b0;
            commit_pid         <= 6'd0;
        end
        else begin
            if (hdr_valid) begin
                arm <= commit_later;
                if (commit_later)
                    commit_pid <= packet_id;
            end
            else if (crc_ok || crc_error)
                arm <= 1'b0;

            if (pkt_accept && (!have_frame_r || frame_id != current_frame_id_r)) begin
                have_frame_r        <= 1'b1;
                current_frame_id_r <= frame_id;
                complete_seen      <= 1'b0;
            end
            else if (frame_complete) begin
                complete_seen <= 1'b1;
            end
        end
    end

    assign current_frame_id = current_frame_id_r;
    assign have_frame        = have_frame_r;

endmodule
