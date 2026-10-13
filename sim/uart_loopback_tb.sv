`timescale 1ns/1ps

module uart_loopback_tb;
    localparam int CLOCK_HZ = 12_000_000;
    localparam int BAUD     = 1_000_000;

    logic clk = 1'b0;
    logic rst;
    logic tx_valid;
    logic [7:0] tx_data;
    logic tx_ready;
    logic serial;
    logic rx_valid;
    logic [7:0] rx_data;
    logic framing_error;

    uart_tx #(.CLOCK_HZ(CLOCK_HZ), .BAUD(BAUD)) tx (
        .clk        (clk),
        .rst        (rst),
        .data_valid (tx_valid),
        .data       (tx_data),
        .ready      (tx_ready),
        .serial_out (serial)
    );

    uart_rx #(.CLOCK_HZ(CLOCK_HZ), .BAUD(BAUD)) rx (
        .clk           (clk),
        .rst           (rst),
        .serial_in     (serial),
        .data_valid    (rx_valid),
        .data          (rx_data),
        .framing_error (framing_error)
    );

    always #41.666 clk = ~clk;

    task automatic send(input logic [7:0] value);
        begin
            wait (tx_ready);
            tx_data  = value;
            tx_valid = 1'b1;
            @(posedge clk);
            #1;
            tx_valid = 1'b0;
            wait (rx_valid);
            if (rx_data !== value)
                $fatal(1, "UART got %02x, expected %02x", rx_data, value);
            if (framing_error)
                $fatal(1, "Unexpected UART framing error");
            @(posedge clk);
        end
    endtask

    initial begin
        rst      = 1'b1;
        tx_valid = 1'b0;
        tx_data  = 8'd0;
        repeat (4) @(posedge clk);
        #1;
        rst = 1'b0;

        send(8'h00);
        send(8'hA5);
        send(8'h5A);
        send(8'hFF);

        $display("PASS: UART TX/RX loopback at 1 Mbaud");
        $finish;
    end
endmodule
