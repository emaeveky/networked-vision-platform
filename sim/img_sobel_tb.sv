`timescale 1ns/1ps

module img_sobel_tb;
    localparam int WIDTH  = 8;
    localparam int HEIGHT = 8;

    logic       clk = 1'b0;
    logic       rst;
    logic       s_valid;
    logic [7:0] s_data;
    logic       s_last;
    logic       s_ready;
    logic       m_valid;
    logic [7:0] m_data;
    logic       m_last;
    logic       m_ready;

    logic [7:0] image [0:WIDTH*HEIGHT-1];
    logic [7:0] got   [0:(WIDTH-2)*(HEIGHT-2)-1];
    int          got_n;
    int          exp_n;

    img_sobel #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) dut (
        .clk     (clk),
        .rst     (rst),
        .s_valid (s_valid),
        .s_data  (s_data),
        .s_last  (s_last),
        .s_ready (s_ready),
        .m_valid (m_valid),
        .m_data  (m_data),
        .m_last  (m_last),
        .m_ready (m_ready)
    );

    always #5 clk = ~clk;

    function automatic logic [7:0] pix(input int x, input int y);
        pix = image[y * WIDTH + x];
    endfunction

    function automatic logic [7:0] expected(input int x, input int y);
        int gx, gy, mag;
        begin
            gx = -pix(x-1, y-1) + pix(x+1, y-1)
               - 2 * pix(x-1, y) + 2 * pix(x+1, y)
               - pix(x-1, y+1) + pix(x+1, y+1);
            gy = -pix(x-1, y-1) - 2 * pix(x, y-1) - pix(x+1, y-1)
               + pix(x-1, y+1) + 2 * pix(x, y+1) + pix(x+1, y+1);
            mag = (gx < 0 ? -gx : gx) + (gy < 0 ? -gy : gy);
            if (mag > 255)
                expected = 8'hFF;
            else
                expected = mag[7:0];
        end
    endfunction

    always_ff @(posedge clk) begin
        if (rst)
            got_n <= 0;
        else if (m_valid && m_ready) begin
            got[got_n] <= m_data;
            got_n      <= got_n + 1;
        end
    end

    initial begin
        m_ready = 1'b1;
        s_valid = 1'b0;
        s_last  = 1'b0;
        s_data  = 8'd0;
        rst     = 1'b1;
        for (int i = 0; i < WIDTH * HEIGHT; i++)
            image[i] = 8'(i * 3);
        @(posedge clk);
        #1;
        rst = 1'b0;

        for (int i = 0; i < WIDTH * HEIGHT; i++) begin
            wait (s_ready);
            s_valid = 1'b1;
            s_data  = image[i];
            s_last  = (i == WIDTH * HEIGHT - 1);
            @(posedge clk);
            #1;
        end
        s_valid = 1'b0;
        s_last  = 1'b0;

        repeat (4) @(posedge clk);

        exp_n = 0;
        for (int y = 1; y < HEIGHT - 1; y++) begin
            for (int x = 1; x < WIDTH - 1; x++) begin
                if (got[exp_n] !== expected(x, y))
                    $fatal(1, "Sobel mismatch at %0d,%0d got %0d expected %0d",
                           x, y, got[exp_n], expected(x, y));
                exp_n++;
            end
        end
        if (got_n !== exp_n)
            $fatal(1, "Sobel output count %0d expected %0d", got_n, exp_n);

        $display("PASS: img_sobel 8x8 interior matched |Gx|+|Gy|");
        $finish;
    end
endmodule
