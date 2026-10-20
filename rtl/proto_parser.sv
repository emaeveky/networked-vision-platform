module proto_parser (
    input  logic        clk,
    input  logic        rst,

    input  logic        rx_valid,
    input  logic [7:0]  rx_data,
    input  logic        wide_ok = 1'b0,
    output logic        rx_ready,

    output logic        hdr_valid,
    output logic [15:0] frame_id,
    output logic [5:0]  packet_id,
    output logic [7:0]  packet_id_full,
    output logic [10:0] payload_len,
    output logic        data_valid,
    output logic [7:0]  data,
    output logic        data_last,
    output logic        parse_error,
    output logic        crc_ok,
    output logic        crc_error,
    output logic        idle
);

    localparam logic [7:0] MAGIC = 8'hA5;
    localparam int          PACKET_BYTES = 1200;

    typedef enum logic [2:0] {
        ST_MAGIC,
        ST_FID_LO,
        ST_FID_HI,
        ST_PKT,
        ST_LEN_LO,
        ST_LEN_HI,
        ST_PAYLOAD,
        ST_CRC
    } state_t;

    state_t      state;
    logic [15:0] frame_id_r;
    logic [7:0]  packet_id_r;
    logic [15:0] len_r;
    logic [10:0] count;
    logic [1:0]  crc_count;
    logic [31:0] crc_run;
    logic [23:0] crc_bytes;

    // zlib.crc32: reflected poly 0xEDB88320, init and xorout 0xFFFFFFFF.
    function automatic logic [31:0] crc32_byte(input logic [31:0] crc, input logic [7:0] data);
        logic [31:0] c;
        int i;
        begin
            c = crc ^ {24'd0, data};
            for (i = 0; i < 8; i++) begin
                if (c[0])
                    c = (c >> 1) ^ 32'hEDB88320;
                else
                    c = c >> 1;
            end
            crc32_byte = c;
        end
    endfunction

    assign rx_ready = 1'b1;
    assign idle     = (state == ST_MAGIC);

    always_ff @(posedge clk) begin
        if (rst) begin
            state        <= ST_MAGIC;
            frame_id_r   <= 16'd0;
            packet_id_r  <= 8'd0;
            len_r         <= 16'd0;
            count        <= 11'd0;
            crc_count    <= 2'd0;
            crc_run      <= 32'hFFFFFFFF;
            crc_bytes    <= 24'd0;
            hdr_valid    <= 1'b0;
            data_valid   <= 1'b0;
            data         <= 8'd0;
            data_last    <= 1'b0;
            parse_error  <= 1'b0;
            crc_ok       <= 1'b0;
            crc_error    <= 1'b0;
        end
        else begin
            hdr_valid   <= 1'b0;
            data_valid  <= 1'b0;
            data_last   <= 1'b0;
            parse_error <= 1'b0;
            crc_ok      <= 1'b0;
            crc_error   <= 1'b0;

            if (rx_valid) begin
                case (state)
                    ST_MAGIC: begin
                        if (rx_data == MAGIC)
                            state <= ST_FID_LO;
                        else
                            parse_error <= 1'b1;
                    end
                    ST_FID_LO: begin
                        frame_id_r[7:0] <= rx_data;
                        state <= ST_FID_HI;
                    end
                    ST_FID_HI: begin
                        frame_id_r[15:8] <= rx_data;
                        state <= ST_PKT;
                    end
                    ST_PKT: begin
                        packet_id_r <= rx_data;
                        state <= ST_LEN_LO;
                    end
                    ST_LEN_LO: begin
                        len_r[7:0] <= rx_data;
                        state <= ST_LEN_HI;
                    end
                    ST_LEN_HI: begin
                        len_r[15:8] <= rx_data;
                        if ({rx_data, len_r[7:0]} != 16'(PACKET_BYTES) ||
                            (!wide_ok && packet_id_r[7:6] != 2'b00)) begin
                            parse_error <= 1'b1;
                            state <= ST_MAGIC;
                        end
                        else begin
                            hdr_valid <= 1'b1;
                            count     <= 11'd0;
                            crc_run   <= 32'hFFFFFFFF;
                            state     <= ST_PAYLOAD;
                        end
                    end
                    ST_PAYLOAD: begin
                        data_valid <= 1'b1;
                        data       <= rx_data;
                        count      <= count + 11'd1;
                        crc_run    <= crc32_byte(crc_run, rx_data);
                        if (count == 11'(PACKET_BYTES - 1)) begin
                            data_last <= 1'b1;
                            crc_count <= 2'd0;
                            state     <= ST_CRC;
                        end
                    end
                    ST_CRC: begin
                        // Payload bytes are already forwarded. crc_ok/crc_error
                        // tell the frame engine whether to keep the packet.
                        crc_count <= crc_count + 2'd1;
                        if (crc_count == 2'd0)
                            crc_bytes[7:0] <= rx_data;
                        else if (crc_count == 2'd1)
                            crc_bytes[15:8] <= rx_data;
                        else if (crc_count == 2'd2)
                            crc_bytes[23:16] <= rx_data;
                        else begin
                            if ((crc_run ^ 32'hFFFFFFFF) == {rx_data, crc_bytes})
                                crc_ok <= 1'b1;
                            else
                                crc_error <= 1'b1;
                            state <= ST_MAGIC;
                        end
                    end
                    default: state <= ST_MAGIC;
                endcase
            end
        end
    end

    assign frame_id       = frame_id_r;
    assign packet_id      = packet_id_r[5:0];
    assign packet_id_full = packet_id_r;
    assign payload_len    = 11'(PACKET_BYTES);

endmodule
