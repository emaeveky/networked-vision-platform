module vision_core (
    input  logic        clk,
    input  logic        rst,
    input  logic        swap_ready,

    input  logic        hdr_valid,
    input  logic [15:0] frame_id,
    input  logic [5:0]  packet_id,
    input  logic [10:0] payload_len,

    input  logic        data_valid,
    input  logic [7:0]  data,
    input  logic        data_last,
    input  logic        crc_ok,
    input  logic        crc_error,

    input  logic        rd_en,
    input  logic [16:0] rd_addr,
    output logic [7:0]  rd_data,
    output logic        rd_bank,
    output logic        wr_bank,

    output logic        pkt_accept,
    output logic        duplicate_packet,
    output logic        late_packet,
    output logic        incomplete_frame,
    output logic        dropped_frame,
    output logic        payload_error,
    output logic        frame_complete,
    output logic        wr_allowed,
    output logic        swap_pulse,
    output logic        pending_display,
    output logic [15:0] current_frame_id,
    output logic [6:0]  unique_packet_count,
    output logic [16:0] write_count
);

    logic        mem_we;
    logic [16:0] mem_addr;
    logic [7:0]  mem_wdata;
    logic [63:0] received_map;
    logic        have_frame;
    logic        writer_busy;
    logic        writer_payload_error;
    logic [16:0] write_count_r;

    frame_engine u_engine (
        .clk                 (clk),
        .rst                 (rst),
        .wr_allowed          (wr_allowed),
        .hdr_valid           (hdr_valid),
        .frame_id            (frame_id),
        .packet_id           (packet_id),
        .crc_ok              (crc_ok),
        .crc_error           (crc_error),
        .pkt_accept          (pkt_accept),
        .duplicate_packet    (duplicate_packet),
        .late_packet         (late_packet),
        .incomplete_frame    (incomplete_frame),
        .dropped_frame       (dropped_frame),
        .frame_complete      (frame_complete),
        .current_frame_id    (current_frame_id),
        .unique_packet_count (unique_packet_count),
        .received_map        (received_map),
        .have_frame          (have_frame)
    );

    pixel_writer u_writer (
        .clk          (clk),
        .rst          (rst),
        .pkt_accept    (pkt_accept),
        .packet_id    (packet_id),
        .payload_len  (payload_len),
        .data_valid   (data_valid),
        .data         (data),
        .data_last    (data_last),
        .mem_we       (mem_we),
        .mem_addr     (mem_addr),
        .mem_wdata    (mem_wdata),
        .payload_error(writer_payload_error),
        .busy         (writer_busy)
    );

    assign payload_error = writer_payload_error | crc_error;

    always_ff @(posedge clk) begin
        if (rst)
            write_count_r <= 17'd0;
        else if (mem_we) begin
            write_count_r <= write_count_r + 17'd1;
        end
    end

    assign write_count = write_count_r;

    double_buffer_ctrl u_buf (
        .clk              (clk),
        .rst              (rst),
        .frame_complete    (frame_complete),
        // Completion is the last packet's good CRC, which is after its pixels
        // have been written. Still hold the swap if a writer is mid-packet.
        .swap_ready       (swap_ready && !writer_busy),
        .wr_bank          (wr_bank),
        .rd_bank          (rd_bank),
        .wr_allowed       (wr_allowed),
        .swap_pulse       (swap_pulse),
        .pending_display  (pending_display)
    );

    frame_mem u_mem (
        .clk     (clk),
        .wr_en   (mem_we),
        .wr_bank (wr_bank),
        .wr_addr (mem_addr),
        .wr_data (mem_wdata),
        .rd_en   (rd_en),
        .rd_bank (rd_bank),
        .rd_addr (rd_addr),
        .rd_data (rd_data)
    );

endmodule
