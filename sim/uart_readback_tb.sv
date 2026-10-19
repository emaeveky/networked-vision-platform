`timescale 1ns/1ps

module uart_readback_tb;
    localparam int TEST_BYTES = 64;
    localparam real BIT_NS = 1000.0;

    logic clk = 1'b0;
    logic [3:0] btn = 4'b0001;
    logic uart_txd_in = 1'b1;
    wire uart_rxd_out;
    wire [3:0] led;
    byte unsigned received[$];

    arty_s7_uart_top #(
        .ENABLE_BEACON (1'b0),
        .READBACK_BYTES(TEST_BYTES)
    ) dut (
        .CLK12MHZ(clk),
        .btn(btn),
        .uart_txd_in(uart_txd_in),
        .uart_rxd_out(uart_rxd_out),
        .led(led)
    );

    always #41.6667 clk = ~clk;

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

    initial begin : tx_monitor
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
        int start;

        // Forcing completion swaps the display to write bank0. Preload a
        // distinctive pattern; ingress/storage correctness is covered by
        // vision_core_tb.
        for (i = 0; i < TEST_BYTES; i++)
            dut.u_core.u_mem.poke(0, i, 8'((i * 13) ^ 8'hA7));

        repeat (20) @(posedge clk);
        btn = 4'b0000;
        repeat (300) @(posedge clk);

        // Readback is deliberately available only after a completed frame.
        force dut.frame_complete = 1'b1;
        force dut.current_frame_id = 16'h1234;
        send_byte(8'h52);

        #(BIT_NS * (TEST_BYTES + 20) * 10);

        // Forcing frame_complete also produces the normal five-byte status
        // reply. Locate readback by its distinct sync byte, as the host does.
        start = -1;
        foreach (received[k])
            if (received[k] == 8'hD3 && start < 0)
                start = k;
        if (start < 0)
            $fatal(1, "readback sync D3 was not received");
        if (received.size() < start + TEST_BYTES + 6)
            $fatal(1, "readback ended after %0d of %0d bytes",
                   received.size() - start, TEST_BYTES + 6);

        if (received[start + 1] !== 8'h34 || received[start + 2] !== 8'h12)
            $fatal(1, "readback frame id is %02x%02x",
                   received[start + 2], received[start + 1]);
        if (received[start + 3] !== TEST_BYTES[7:0] ||
            received[start + 4] !== TEST_BYTES[15:8] ||
            received[start + 5] !== TEST_BYTES[23:16])
            $fatal(1, "readback length header is %02x%02x%02x",
                   received[start + 5], received[start + 4], received[start + 3]);

        for (i = 0; i < TEST_BYTES; i++) begin
            if (received[start + i + 6] !== 8'((i * 13) ^ 8'hA7))
                $fatal(1, "pixel %0d=%02x expected %02x",
                       i, received[start + i + 6], 8'((i * 13) ^ 8'hA7));
        end

        $display("PASS: UART readback returned %0d ordered display-buffer bytes",
                 TEST_BYTES);
        $finish;
    end

    initial begin : timeout
        #(BIT_NS * (TEST_BYTES + 200) * 10);
        $fatal(1, "UART readback timed out after %0d bytes", received.size());
    end
endmodule
