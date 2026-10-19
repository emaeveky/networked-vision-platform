`timescale 1ns/1ps

// The display memory is one cycle behind the address, same as frame_mem.
module bg_frame_tb;
    localparam int N = 4;

    logic        clk = 1'b0;
    logic        rst;
    logic        start;
    logic        abort;
    logic [7:0]  rd_data;
    logic        rd_en;
    logic [16:0] rd_addr;
    logic        busy;
    logic        armed;
    logic        done;
    logic        sample_en;
    logic [16:0] sample_addr;
    logic [7:0]  sample_data;

    reg [7:0] picture [0:N-1];
    logic [7:0] rd_data_q;

    bg_frame #(.FRAME_BYTES(N), .CHUNK(N)) dut (
        .clk         (clk),
        .rst         (rst),
        .start       (start),
        .abort       (abort),
        .rd_data     (rd_data),
        .rd_en       (rd_en),
        .rd_addr     (rd_addr),
        .busy        (busy),
        .armed       (armed),
        .done        (done),
        .sample_en   (sample_en),
        .sample_addr (sample_addr),
        .sample_data (sample_data)
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk)
        if (rd_en)
            rd_data_q <= picture[rd_addr];

    assign rd_data = rd_data_q;

    integer i;
    integer errors;

    initial begin
        rst         = 1'b1;
        start       = 1'b0;
        abort       = 1'b0;
        sample_en   = 1'b0;
        sample_addr = 17'd0;
        rd_data_q   = 8'd0;
        picture[0]  = 8'd10;
        picture[1]  = 8'd20;
        picture[2]  = 8'd30;
        picture[3]  = 8'd40;
        repeat (2) @(posedge clk);
        #1;
        rst = 1'b0;

        @(posedge clk);
        #1;
        start = 1'b1;
        @(posedge clk);
        #1;
        start = 1'b0;

        begin : wait_done
            integer guard;
            guard = 0;
            while (!done) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
                if (guard > 20)
                    $fatal(1, "capture did not finish");
            end
        end
        if (!armed)
            $fatal(1, "capture finished without arming the background");

        errors = 0;
        for (i = 0; i < N; i = i + 1) begin
            sample_en   = 1'b1;
            sample_addr = 17'(i);
            @(posedge clk);
            #1;
            sample_en = 1'b0;
            @(posedge clk);
            #1;
            if (sample_data !== picture[i]) begin
                $display("pixel %0d is %0d, expected %0d", i, sample_data, picture[i]);
                errors = errors + 1;
            end
        end
        if (errors != 0)
            $fatal(1, "background copy mismatched %0d pixels", errors);

        // A second capture that is interrupted must drop the armed flag.
        picture[0] = 8'd1;
        @(posedge clk);
        #1;
        start = 1'b1;
        @(posedge clk);
        #1;
        start = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        abort = 1'b1;
        @(posedge clk);
        #1;
        abort = 1'b0;
        if (busy || armed)
            $fatal(1, "aborted capture left busy=%0b armed=%0b", busy, armed);

        $display("PASS: background copy matched and an abort disarmed it");
        $finish;
    end
endmodule
