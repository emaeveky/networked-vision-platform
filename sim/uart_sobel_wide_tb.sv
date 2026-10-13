`timescale 1ns/1ps

// Wider than the header latency, so the first Sobel pixel is produced while
// the UART is already waiting in the payload state. The 8x8 bench finishes
// its kernel during the header and hides that handshake.
module uart_sobel_wide_tb;
    localparam int W = 200;
    localparam int H = 4;
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
        int i, start, n, x, y;
        logic [7:0] want;
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

        send_byte(8'h45);
        #(BIT_NS * (SOBEL_PIXELS + 40) * 10);
        start = -1;
        foreach (received[k])
            if (received[k] == 8'hD3 && start < 0)
                start = k;
        if (start < 0 || received.size() < start + SOBEL_PIXELS + 6) begin
            $display("bytes=%0d start=%0d active=%0b hold=%0b feed_done=%0b col=%0d row=%0d",
                     received.size(), start, dut.readback_active, dut.hold_valid,
                     dut.feed_done, dut.u_sobel.col, dut.u_sobel.row);
            $fatal(1, "short readback");
        end
        n = 0;
        for (y = 1; y <= H - 2; y++) begin
            for (x = 1; x <= W - 2; x++) begin
                want = sobel_at(x, y);
                if (received[start + 6 + n] !== want) begin
                    $display("pixel %0d got %02x expected %02x (prev %02x next %02x)",
                             n, received[start + 6 + n], want,
                             n > 0 ? received[start + 6 + n - 1] : 8'hxx,
                             received[start + 6 + n + 1]);
                    $fatal(1, "wide Sobel mismatch");
                end
                n++;
            end
        end
        $display("PASS: wide Sobel UART readback matched");
        $finish;
    end
endmodule
