`timescale 1ns/1ps

// 8x8 stand-in for the hardware threshold and Sobel readback paths.
// The filters use the real modules; only the frame dimensions are reduced.
module uart_process_tb;
    localparam int W = 8;
    localparam int H = 8;
    localparam int PIXELS = W * H;
    localparam int SOBEL_PIXELS = (W - 2) * (H - 2);
    localparam real BIT_NS = 1000.0;

    logic clk = 1'b0;
    logic [3:0] btn = 4'b0001;
    logic uart_txd_in = 1'b1;
    wire uart_rxd_out;
    wire [3:0] led;
    byte unsigned image [0:PIXELS-1];
    byte unsigned received [$];

    arty_s7_uart_top #(
        .ENABLE_BEACON (1'b0),
        .READBACK_BYTES(PIXELS),
        .FRAME_W       (W),
        .FRAME_H       (H)
    ) dut (
        .CLK12MHZ    (clk),
        .btn         (btn),
        .uart_txd_in (uart_txd_in),
        .uart_rxd_out(uart_rxd_out),
        .led         (led)
    );

    always #41.6667 clk = ~clk;

    function automatic logic [7:0] pix(input int x, input int y);
        pix = image[y * W + x];
    endfunction

    function automatic logic [7:0] sobel_at(input int x, input int y);
        int gx, gy, mag;
        begin
            gx = -pix(x-1, y-1) + pix(x+1, y-1)
               - 2*pix(x-1, y) + 2*pix(x+1, y)
               - pix(x-1, y+1) + pix(x+1, y+1);
            gy = -pix(x-1, y-1) - 2*pix(x, y-1) - pix(x+1, y-1)
               + pix(x-1, y+1) + 2*pix(x, y+1) + pix(x+1, y+1);
            mag = (gx < 0 ? -gx : gx) + (gy < 0 ? -gy : gy);
            sobel_at = (mag > 255) ? 8'hFF : mag[7:0];
        end
    endfunction

    task automatic send_byte(input logic [7:0] value);
        int i;
        begin
            uart_txd_in = 1'b0;
            #(BIT_NS);
            for (i = 0; i < 8; i++) begin
                uart_txd_in = value[i];
                #(BIT_NS);
            end
            uart_txd_in = 1'b1;
            #(BIT_NS);
        end
    endtask

    task automatic expect_result(
        input logic [7:0] command,
        input int count,
        input bit threshold_mode
    );
        int start, i, x, y, n;
        logic [7:0] want;
        begin
            received.delete();
            send_byte(command);
            #(BIT_NS * (count + 30) * 10);
            start = -1;
            foreach (received[k])
                if (received[k] == 8'hD3 && start < 0)
                    start = k;
            if (start < 0 || received.size() < start + count + 6) begin
                $display("active=%0b hold=%0b feed_done=%0b feed_cap=%0b feed_addr=%0d col=%0d row=%0d valid=%0b",
                         dut.readback_active, dut.hold_valid, dut.feed_done, dut.feed_capture,
                         dut.feed_addr, dut.u_sobel.col, dut.u_sobel.row, dut.u_sobel.m_valid);
                $display("command %02x start=%0d count=%0d bytes:", command, start, received.size());
                foreach (received[k]) $display("  [%0d]=%02x", k, received[k]);
                $fatal(1, "command %02x produced %0d bytes, expected at least %0d",
                       command, received.size(), count + 6);
            end
            n = 0;
            for (y = 0; y < H; y++) begin
                for (x = 0; x < W; x++) begin
                    if (threshold_mode || (x >= 1 && x <= W-2 && y >= 1 && y <= H-2)) begin
                        want = threshold_mode
                            ? ((pix(x, y) > 8'd128) ? 8'hFF : 8'h00)
                            : sobel_at(x, y);
                        if (received[start + 6 + n] !== want)
                            $fatal(1, "command %02x pixel %0d=%02x expected %02x",
                                   command, n, received[start + 6 + n], want);
                        n++;
                    end
                end
            end
            if (n != count)
                $fatal(1, "checked %0d pixels, expected %0d", n, count);
        end
    endtask

    initial begin : monitor
        logic [7:0] value;
        int i;
        forever begin
            @(negedge uart_rxd_out);
            #(BIT_NS * 1.5);
            for (i = 0; i < 8; i++) begin
                value[i] = uart_rxd_out;
                #(BIT_NS);
            end
            received.push_back(value);
        end
    end

    initial begin : stimulus
        int i;
        for (i = 0; i < PIXELS; i++)
            image[i] = (i * 17 + 9) & 8'hFF;
        for (i = 0; i < PIXELS; i++) begin
            dut.u_core.u_mem.bank0[i] = image[i];
            dut.u_core.u_mem.bank1[i] = image[i];
        end

        repeat (20) @(posedge clk);
        btn = 4'b0000;
        repeat (300) @(posedge clk);
        force dut.frame_complete = 1'b1;
        force dut.current_frame_id = 16'h0007;

        expect_result(8'h54, PIXELS, 1'b1);
        expect_result(8'h45, SOBEL_PIXELS, 1'b0);
        $display("PASS: threshold and Sobel UART readback matched golden pixels");
        $finish;
    end
endmodule
