`timescale 1ns/1ps

module proto_parser_tb;
    logic        clk = 1'b0;
    logic        rst;
    logic        rx_valid;
    logic [7:0]  rx_data;
    logic        rx_ready;
    logic        hdr_valid;
    logic [15:0] frame_id;
    logic [5:0]  packet_id;
    logic [10:0] payload_len;
    logic        data_valid;
    logic [7:0]  data;
    logic        data_last;
    logic        parse_error;
    logic        crc_ok;
    logic        crc_error;
    logic        idle;

    localparam int PACKET_BYTES = 1200;

    proto_parser dut (
        .clk         (clk),
        .rst         (rst),
        .rx_valid    (rx_valid),
        .rx_data     (rx_data),
        .rx_ready    (rx_ready),
        .hdr_valid   (hdr_valid),
        .frame_id    (frame_id),
        .packet_id   (packet_id),
        .payload_len (payload_len),
        .data_valid  (data_valid),
        .data        (data),
        .data_last   (data_last),
        .parse_error (parse_error),
        .crc_ok      (crc_ok),
        .crc_error   (crc_error),
        .idle        (idle)
    );

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

    always #5 clk = ~clk;

    task automatic send_byte(input logic [7:0] b);
        begin
            rx_valid = 1'b1;
            rx_data  = b;
            @(posedge clk);
            #1;
            rx_valid = 1'b0;
        end
    endtask

    int payload_count;

    always_ff @(posedge clk) begin
        if (rst)
            payload_count <= 0;
        else if (data_valid)
            payload_count <= data_last ? 0 : payload_count + 1;
    end

    initial begin
        logic [31:0] crc;
        int i;
        rst      = 1'b1;
        rx_valid = 1'b0;
        rx_data  = 8'd0;
        @(posedge clk);
        #1;
        rst = 1'b0;

        crc = 32'hFFFFFFFF;
        begin
            byte unsigned check_msg[0:8];
            check_msg[0] = 8'h31; check_msg[1] = 8'h32; check_msg[2] = 8'h33;
            check_msg[3] = 8'h34; check_msg[4] = 8'h35; check_msg[5] = 8'h36;
            check_msg[6] = 8'h37; check_msg[7] = 8'h38; check_msg[8] = 8'h39;
            for (i = 0; i < 9; i++)
                crc = crc32_byte(crc, check_msg[i]);
        end
        if ((crc ^ 32'hFFFFFFFF) !== 32'hCBF43926)
            $fatal(1, "CRC32 check value is %08x", crc ^ 32'hFFFFFFFF);

        send_byte(8'h00);
        if (!parse_error)
            $fatal(1, "Bad magic was not flagged");

        send_byte(8'hA5);
        send_byte(8'h22);
        send_byte(8'h01);
        send_byte(8'd7);
        send_byte(8'd176);
        send_byte(8'd4);
        if (!hdr_valid || frame_id !== 16'h0122 || packet_id !== 6'd7 || payload_len !== 11'(PACKET_BYTES))
            $fatal(1, "Header did not match little-endian prototype packet");

        crc = 32'hFFFFFFFF;
        for (i = 0; i < PACKET_BYTES; i++) begin
            send_byte(8'(i));
            crc = crc32_byte(crc, 8'(i));
        end
        crc = crc ^ 32'hFFFFFFFF;

        if (!data_last)
            $fatal(1, "Parser did not strobe last on the 1200th payload byte");

        send_byte(crc[7:0]);
        send_byte(crc[15:8]);
        send_byte(crc[23:16]);
        send_byte(crc[31:24]);
        if (!crc_ok || crc_error)
            $fatal(1, "Good payload CRC was not accepted (ok=%0b err=%0b)", crc_ok, crc_error);

        send_byte(8'hA5);
        send_byte(8'h22);
        send_byte(8'h01);
        send_byte(8'd7);
        send_byte(8'd176);
        send_byte(8'd4);
        for (i = 0; i < PACKET_BYTES; i++)
            send_byte(8'(i));
        send_byte(crc[7:0]);
        send_byte(crc[15:8]);
        send_byte(crc[23:16]);
        send_byte(crc[31:24] ^ 8'hFF);
        if (crc_ok || !crc_error)
            $fatal(1, "Bad payload CRC was not rejected (ok=%0b err=%0b)", crc_ok, crc_error);

        $display("PASS: proto_parser decoded the header and checked zlib CRC32");
        $finish;
    end
endmodule
