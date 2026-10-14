// Bounding box of pixels that differ from the previous frame by more than
// THRESH. sample_valid is aligned with curr_pix/prev_pix/addr: it is high on
// the cycle the synchronous frame memory presents the previous pixel.
module motion_box #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240,
    parameter int THRESH = 16
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        clear,
    input  logic        latch,

    input  logic        sample_valid,
    input  logic [7:0]  curr_pix,
    input  logic [7:0]  prev_pix,
    input  logic [16:0] addr,

    output logic        motion,
    output logic [8:0]  min_x,
    output logic [8:0]  max_x,
    output logic [7:0]  min_y,
    output logic [7:0]  max_y,
    output logic [15:0] pix_count,
    output logic [8:0]  cen_x,
    output logic [7:0]  cen_y
);

    logic        live_motion;
    logic [8:0]  live_min_x;
    logic [8:0]  live_max_x;
    logic [7:0]  live_min_y;
    logic [7:0]  live_max_y;
    logic [15:0] live_count;
    logic [16:0] live_full;
    logic [31:0] live_sum_x;
    logic [31:0] live_sum_y;
    logic        div_wait;
    logic [1:0]  div_phase;
    logic [4:0]  div_bit;
    logic [31:0] div_numer;
    logic [31:0] div_rem;
    logic [31:0] div_quot;
    logic [31:0] div_den;
    logic [31:0] cap_sum_x;
    logic [31:0] cap_sum_y;
    logic [16:0] cap_count;
    logic [31:0] quot_next;
    logic [31:0] rem_next;

    function automatic logic [16:0] row_of(input logic [16:0] value);
        logic [16:0] quot;
        logic [16:0] rem;
        int i;
        begin
            quot = 17'd0;
            rem  = 17'd0;
            for (i = 16; i >= 0; i = i - 1) begin
                rem = {rem[15:0], value[i]};
                if (rem >= 17'(WIDTH)) begin
                    rem     = rem - 17'(WIDTH);
                    quot[i] = 1'b1;
                end
            end
            row_of = quot;
        end
    endfunction

    wire [16:0] row = row_of(addr);
    wire [16:0] col = addr - (row * 17'(WIDTH));
    wire [7:0]  diff = (curr_pix >= prev_pix) ? (curr_pix - prev_pix)
                                              : (prev_pix - curr_pix);
    wire in_frame = (col < 17'(WIDTH)) && (row < 17'(HEIGHT));
    wire hit = sample_valid && in_frame && (diff > 8'(THRESH));
    wire [8:0] col9 = col[8:0];
    wire [7:0] row8 = row[7:0];

    always_ff @(posedge clk) begin
        if (rst) begin
            live_motion <= 1'b0;
            live_min_x  <= 9'd0;
            live_max_x  <= 9'd0;
            live_min_y  <= 8'd0;
            live_max_y  <= 8'd0;
            live_count  <= 16'd0;
            live_full   <= 17'd0;
            live_sum_x  <= 32'd0;
            live_sum_y  <= 32'd0;
            div_wait    <= 1'b0;
            div_phase   <= 2'd0;
            div_bit     <= 5'd0;
            div_numer   <= 32'd0;
            div_rem     <= 32'd0;
            div_quot    <= 32'd0;
            div_den     <= 32'd0;
            cap_sum_x   <= 32'd0;
            cap_sum_y   <= 32'd0;
            cap_count   <= 17'd0;
            motion      <= 1'b0;
            min_x       <= 9'd0;
            max_x       <= 9'd0;
            min_y       <= 8'd0;
            max_y       <= 8'd0;
            pix_count   <= 16'd0;
            cen_x       <= 9'd0;
            cen_y       <= 8'd0;
        end
        else begin
            if (latch) begin
                motion    <= live_motion;
                min_x     <= live_motion ? live_min_x : 9'd0;
                max_x     <= live_motion ? live_max_x : 9'd0;
                min_y     <= live_motion ? live_min_y : 8'd0;
                max_y     <= live_motion ? live_max_y : 8'd0;
                pix_count <= live_count;
                cap_sum_x <= live_sum_x;
                cap_sum_y <= live_sum_y;
                cap_count <= live_full;
                if (live_motion && live_full != 17'd0)
                    div_wait <= 1'b1;
                else begin
                    div_wait  <= 1'b0;
                    div_phase <= 2'd0;
                    cen_x     <= 9'd0;
                    cen_y     <= 8'd0;
                end
            end
            else if (div_wait) begin
                div_wait  <= 1'b0;
                div_phase <= 2'd1;
                div_bit   <= 5'd31;
                div_numer <= cap_sum_x;
                div_den   <= {15'd0, cap_count};
                div_rem   <= 32'd0;
                div_quot  <= 32'd0;
            end
            else if (div_phase != 2'd0) begin
                rem_next  = {div_rem[30:0], div_numer[31]};
                quot_next = {div_quot[30:0], (rem_next >= div_den)};
                if (rem_next >= div_den)
                    rem_next = rem_next - div_den;

                if (div_bit == 5'd0 && div_phase == 2'd1) begin
                    cen_x     <= quot_next[8:0];
                    div_phase <= 2'd2;
                    div_bit   <= 5'd31;
                    div_numer <= cap_sum_y;
                    div_rem   <= 32'd0;
                    div_quot  <= 32'd0;
                end
                else if (div_bit == 5'd0) begin
                    cen_y     <= quot_next[7:0];
                    div_phase <= 2'd0;
                end
                else begin
                    div_bit   <= div_bit - 5'd1;
                    div_numer <= {div_numer[30:0], 1'b0};
                    div_rem   <= rem_next;
                    div_quot  <= quot_next;
                end
            end

            if (clear) begin
                live_motion <= 1'b0;
                live_min_x  <= 9'd0;
                live_max_x  <= 9'd0;
                live_min_y  <= 8'd0;
                live_max_y  <= 8'd0;
                live_count  <= 16'd0;
                live_full   <= 17'd0;
                live_sum_x  <= 32'd0;
                live_sum_y  <= 32'd0;
            end
            else if (hit) begin
                if (!live_motion || col9 < live_min_x)
                    live_min_x <= col9;
                if (!live_motion || col9 > live_max_x)
                    live_max_x <= col9;
                if (!live_motion || row8 < live_min_y)
                    live_min_y <= row8;
                if (!live_motion || row8 > live_max_y)
                    live_max_y <= row8;
                if (live_count != 16'hFFFF)
                    live_count <= live_count + 16'd1;
                live_full   <= live_full + 17'd1;
                live_sum_x  <= live_sum_x + 32'(col);
                live_sum_y  <= live_sum_y + 32'(row);
                live_motion <= 1'b1;
            end
        end
    end

endmodule

// One-cycle delay so curr_pix/addr line up with frame_mem's registered read.
module motion_watch #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240,
    parameter int THRESH = 16
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        clear,
    input  logic        latch,
    input  logic        issue,
    input  logic [7:0]  curr_pix,
    input  logic [16:0] addr,
    input  logic [7:0]  prev_pix,

    output logic        motion,
    output logic [8:0]  min_x,
    output logic [8:0]  max_x,
    output logic [7:0]  min_y,
    output logic [7:0]  max_y,
    output logic [15:0] pix_count,
    output logic [8:0]  cen_x,
    output logic [7:0]  cen_y
);

    logic        pend;
    logic [7:0]  curr_q;
    logic [16:0] addr_q;

    always_ff @(posedge clk) begin
        if (rst)
            pend <= 1'b0;
        else begin
            pend   <= issue;
            curr_q <= curr_pix;
            addr_q <= addr;
        end
    end

    motion_box #(
        .WIDTH  (WIDTH),
        .HEIGHT (HEIGHT),
        .THRESH (THRESH)
    ) u_box (
        .clk          (clk),
        .rst          (rst),
        .clear        (clear),
        .latch        (latch),
        .sample_valid (pend),
        .curr_pix     (curr_q),
        .prev_pix     (prev_pix),
        .addr         (addr_q),
        .motion       (motion),
        .min_x        (min_x),
        .max_x        (max_x),
        .min_y        (min_y),
        .max_y        (max_y),
        .pix_count    (pix_count),
        .cen_x        (cen_x),
        .cen_y        (cen_y)
    );

endmodule
