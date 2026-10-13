`timescale 1ns/1ps

// Board-level test: drives the FTDI serial line exactly like the host does and
// decodes the status reply on uart_rxd_out.
//
// Stress knobs (plusargs; defaults reproduce a clean host run):
//   +packets=N        packets per frame (64 = full frame, fewer = parser smoke test)
//   +frames=N         number of consecutive frames
//   +first_frame=N    frame_id of the first frame (test 0xFFFF -> 0 wrap)
//   +bit_ps=N         host bit period in ps (1000000 = exact 1 Mbaud)
//   +gap_max_ns=N     random idle 0..N ns after every byte (USB burstiness)
//   +frame_gap_bits=N idle bit-times between frames (0 = back-to-back)
//   +drop_byte=N      silently drop the N-th byte of the whole stream
//   +corrupt_byte=N   XOR the N-th byte of the stream with 0xFF
//   +reset_at_byte=N  pulse BTN0 for 50 clocks when the N-th byte is sent
module arty_top_uart_tb;

    localparam int  PACKET_BYTES = 1200;
    localparam int  PKT_ID_MAX   = 64;
    localparam real RX_BIT_NS    = 1000.0;   // FPGA TX is always 1 Mbaud

    logic       clk = 1'b0;
    logic [3:0] btn = 4'b0001;
    logic       uart_txd_in = 1'b1;
    wire        uart_rxd_out;
    wire [3:0]  led;

    // knobs
    int n_packets      = PKT_ID_MAX;
    int n_frames       = 1;
    int first_frame    = 0;
    int bit_ps         = 1_000_000;
    int gap_max_ns     = 0;
    int frame_gap_bits = 200;
    int drop_byte      = -1;
    int corrupt_byte   = -1;
    int reset_at_byte  = -1;
    real bit_ns;

    // counters
    int byte_index = 0;
    int rx_count = 0;
    int hdr_count = 0;
    int parse_err_count = 0;
    int framing_err_count = 0;
    int payload_err_count = 0;
    int late_count = 0;
    int dropped_count = 0;
    int incomplete_count = 0;
    int duplicate_count = 0;
    int swap_count = 0;

    byte unsigned status_q[$];
    int           status_frame_q[$];   // frame index during which each byte arrived
    int           cur_frame_idx = -1;

    arty_s7_uart_top #(.ENABLE_BEACON(1'b0)) dut (
        .CLK12MHZ     (clk),
        .btn          (btn),
        .uart_txd_in  (uart_txd_in),
        .uart_rxd_out (uart_rxd_out),
        .led          (led)
    );

    always #41.6667 clk = ~clk;

    // ---- host -> FPGA -------------------------------------------------
    task automatic ser_byte(input logic [7:0] value);
        int i;
        logic [7:0] v;
        begin
            v = value;
            if (byte_index == corrupt_byte) begin
                v = value ^ 8'hFF;
                $display("[%0t] corrupting stream byte %0d: %02x -> %02x", $time, byte_index, value, v);
            end
            if (byte_index == drop_byte) begin
                $display("[%0t] dropping stream byte %0d (%02x)", $time, byte_index, value);
            end
            else begin
                uart_txd_in = 1'b0;
                #(bit_ns);
                for (i = 0; i < 8; i = i + 1) begin
                    uart_txd_in = v[i];
                    #(bit_ns);
                end
                uart_txd_in = 1'b1;
                #(bit_ns);
            end
            byte_index = byte_index + 1;
            if (gap_max_ns > 0)
                #($urandom_range(0, gap_max_ns));
        end
    endtask

    task automatic send_packet(input int unsigned frame_id, input int unsigned packet_id);
        int i;
        logic [7:0] b;
        logic [31:0] crc;
        begin
            ser_byte(8'hA5);
            ser_byte(frame_id[7:0]);
            ser_byte(frame_id[15:8]);
            ser_byte(packet_id[7:0]);
            ser_byte(PACKET_BYTES[7:0]);
            ser_byte(PACKET_BYTES[15:8]);
            // Gradient covers every byte value including 0xA5 (fake magic).
            crc = 32'hFFFFFFFF;
            for (i = 0; i < PACKET_BYTES; i = i + 1) begin
                b = (packet_id * 7 + i) & 8'hFF;
                ser_byte(b);
                crc = crc32_byte(crc, b);
            end
            crc = crc ^ 32'hFFFFFFFF;
            ser_byte(crc[7:0]);
            ser_byte(crc[15:8]);
            ser_byte(crc[23:16]);
            ser_byte(crc[31:24]);
        end
    endtask

    function automatic logic [31:0] crc32_byte(input logic [31:0] crc_in, input logic [7:0] data);
        logic [31:0] c;
        int n;
        begin
            c = crc_in ^ {24'd0, data};
            for (n = 0; n < 8; n++) begin
                if (c[0])
                    c = (c >> 1) ^ 32'hEDB88320;
                else
                    c = c >> 1;
            end
            crc32_byte = c;
        end
    endfunction

    // ---- fault: BTN0 press mid-stream ----------------------------------
    initial begin : reset_injector
        wait (reset_at_byte >= 0);
        wait (byte_index == reset_at_byte);
        $display("[%0t] pressing BTN0 at stream byte %0d", $time, byte_index);
        btn[0] = 1'b1;
        repeat (50) @(posedge clk);
        btn[0] = 1'b0;
    end

    // ---- FPGA -> host -------------------------------------------------
    initial begin : rx_monitor
        logic [7:0] b;
        int i;
        forever begin
            @(negedge uart_rxd_out);
            #(RX_BIT_NS * 1.5);
            for (i = 0; i < 8; i = i + 1) begin
                b[i] = uart_rxd_out;
                #(RX_BIT_NS);
            end
            status_q.push_back(b);
            status_frame_q.push_back(cur_frame_idx);
            $display("[%0t] status byte %0d = 0x%02x", $time, status_q.size() - 1, b);
        end
    end

    // ---- internal instrumentation -------------------------------------
    always @(posedge clk) begin
        if (!dut.core_rst) begin
            if (dut.rx_valid)         rx_count          <= rx_count + 1;
            if (dut.hdr_valid)        hdr_count         <= hdr_count + 1;
            if (dut.parse_error)      parse_err_count   <= parse_err_count + 1;
            if (dut.framing_error)    framing_err_count <= framing_err_count + 1;
            if (dut.payload_error)    payload_err_count <= payload_err_count + 1;
            if (dut.late_packet)      late_count        <= late_count + 1;
            if (dut.dropped_frame)    dropped_count     <= dropped_count + 1;
            if (dut.incomplete_frame) incomplete_count  <= incomplete_count + 1;
            if (dut.duplicate_packet) duplicate_count   <= duplicate_count + 1;
            if (dut.swap_pulse)       swap_count        <= swap_count + 1;
        end
    end

    function automatic int status_bytes_for_frame(input int f);
        int n;
        n = 0;
        foreach (status_frame_q[k]) if (status_frame_q[k] == f) n = n + 1;
        return n;
    endfunction

    initial begin : stimulus
        int p, f, k;
        int fid;
        int fails;
        int hdr_before_last;
        int stat_start;

        if ($value$plusargs("packets=%d", n_packets))           $display("packets/frame     = %0d", n_packets);
        if ($value$plusargs("frames=%d", n_frames))             $display("frames            = %0d", n_frames);
        if ($value$plusargs("first_frame=%d", first_frame))     $display("first frame id    = %0d", first_frame);
        if ($value$plusargs("bit_ps=%d", bit_ps))               $display("host bit period   = %0d ps", bit_ps);
        if ($value$plusargs("gap_max_ns=%d", gap_max_ns))       $display("inter-byte gap    <= %0d ns", gap_max_ns);
        if ($value$plusargs("frame_gap_bits=%d", frame_gap_bits)) $display("frame gap         = %0d bits", frame_gap_bits);
        if ($value$plusargs("drop_byte=%d", drop_byte))         $display("drop stream byte  = %0d", drop_byte);
        if ($value$plusargs("corrupt_byte=%d", corrupt_byte))   $display("corrupt byte      = %0d", corrupt_byte);
        if ($value$plusargs("reset_at_byte=%d", reset_at_byte)) $display("reset at byte     = %0d", reset_at_byte);
        bit_ns = bit_ps / 1000.0;

        repeat (20) @(posedge clk);
        btn = 4'b0000;
        // Power-on reset inside the top holds the UART for 256 clocks.
        repeat (300) @(posedge clk);

        for (f = 0; f < n_frames; f = f + 1) begin
            cur_frame_idx = f;
            fid = (first_frame + f) & 16'hFFFF;
            for (p = 0; p < n_packets; p = p + 1) begin
                if (p == n_packets - 1) hdr_before_last = hdr_count;
                send_packet(fid, p);
                if ((p % 16) == 15)
                    $display("[%0t] frame %0d (id %0d): sent %0d packets, rx=%0d hdr=%0d parse_err=%0d framing_err=%0d",
                             $time, f, fid, p + 1, rx_count, hdr_count, parse_err_count, framing_err_count);
            end
            // Give swap + 5 status bytes (50 us) a chance before the next frame starts.
            if (frame_gap_bits > 0)
                #(bit_ns * frame_gap_bits);
            $display("[%0t] frame %0d (id %0d) done, status bytes so far = %0d",
                     $time, f, fid, status_q.size());
        end
        // Always allow the final status to drain, even in back-to-back mode.
        #(RX_BIT_NS * 200);

        $display("----");
        $display("rx bytes        = %0d (sent %0d)", rx_count, byte_index - (drop_byte >= 0 ? 1 : 0));
        $display("headers         = %0d (packets sent %0d)", hdr_count, n_frames * n_packets);
        $display("parse errors    = %0d", parse_err_count);
        $display("framing errors  = %0d", framing_err_count);
        $display("payload errors  = %0d", payload_err_count);
        $display("late packets    = %0d", late_count);
        $display("dropped frames  = %0d", dropped_count);
        $display("incomplete      = %0d", incomplete_count);
        $display("duplicates      = %0d", duplicate_count);
        $display("swaps           = %0d", swap_count);
        $display("status bytes    = %0d", status_q.size());

        fails = 0;

        // ---- clean-link expectations (no fault injection) ----
        if (drop_byte < 0 && corrupt_byte < 0 && reset_at_byte < 0) begin
            if (framing_err_count != 0) begin
                $display("FAIL: %0d framing errors on a clean line (baud tolerance)", framing_err_count);
                fails++;
            end
            if (hdr_count != n_frames * n_packets) begin
                $display("FAIL: parser accepted %0d of %0d headers", hdr_count, n_frames * n_packets);
                fails++;
            end
            if (n_packets == PKT_ID_MAX) begin
                if (status_q.size() != 5 * n_frames) begin
                    $display("FAIL: expected %0d status bytes, got %0d", 5 * n_frames, status_q.size());
                    fails++;
                end
                else begin
                    for (f = 0; f < n_frames; f = f + 1) begin
                        fid = (first_frame + f) & 16'hFFFF;
                        $display("frame %0d status = %02x %02x %02x %02x %02x", f,
                                 status_q[f*5+0], status_q[f*5+1], status_q[f*5+2],
                                 status_q[f*5+3], status_q[f*5+4]);
                        if (status_q[f*5+0] !== 8'h5A) begin $display("FAIL: bad sync, frame %0d", f); fails++; end
                        if ({status_q[f*5+2], status_q[f*5+1]} !== fid[15:0]) begin
                            $display("FAIL: status frame id %0d, expected %0d", {status_q[f*5+2], status_q[f*5+1]}, fid); fails++;
                        end
                        if (status_q[f*5+3] !== 8'd64) begin $display("FAIL: packet count %0d, frame %0d", status_q[f*5+3], f); fails++; end
                        if (status_q[f*5+4] !== 8'h00) begin $display("FAIL: error flags %02x, frame %0d", status_q[f*5+4], f); fails++; end
                    end
                end
            end
        end
        // ---- fault-injection expectations: the link must recover ----
        else begin
            if (hdr_count <= hdr_before_last) begin
                $display("FAIL: parser never resynchronised; last packet header was not accepted");
                fails++;
            end
            else
                $display("parser resynchronised: last packet header accepted");
            if (n_frames >= 2 && n_packets == PKT_ID_MAX) begin
                // The final frame is sent after the fault; it must produce exactly one status.
                k = status_bytes_for_frame(n_frames - 1);
                if (k != 5) begin
                    $display("FAIL: final frame produced %0d status bytes, expected 5", k);
                    fails++;
                end
                else begin
                    stat_start = status_q.size() - 5;
                    $display("final frame status = %02x %02x %02x %02x %02x",
                             status_q[stat_start], status_q[stat_start+1], status_q[stat_start+2],
                             status_q[stat_start+3], status_q[stat_start+4]);
                    if (status_q[stat_start+3] !== 8'd64) begin
                        $display("FAIL: final frame packet count %0d", status_q[stat_start+3]); fails++;
                    end
                end
            end
        end

        if (fails == 0)
            $display("PASS");
        else
            $display("FAILED with %0d problem(s)", fails);
        $finish;
    end

endmodule
