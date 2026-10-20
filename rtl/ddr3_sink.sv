// Stream bytes into DDR at absolute addresses, then read FRAME_BYTES back
// from address 0. Bytes in a 16-byte group must arrive in order. The group
// address is 16-byte aligned, which is true for 1200-byte packets.
module ddr3_sink #(
    parameter int FRAME_BYTES = 307200
) (
    input  logic        clk_byte,
    input  logic        rst_byte,
    input  logic        clk_ddr,
    input  logic        rst_ddr,
    input  logic        gate,

    input  logic        byte_valid,
    input  logic [7:0]  byte_data,
    input  logic [18:0] byte_addr,
    output logic        write_idle,

    input  logic        read_go,
    output logic [7:0]  out_byte,
    output logic        out_valid,
    output logic        out_last,
    input  logic        out_ready,
    output logic        busy,

    output logic [27:0]  awaddr,
    output logic [7:0]   awlen,
    output logic [2:0]   awsize,
    output logic [1:0]   awburst,
    output logic         awvalid,
    input  logic         awready,
    output logic [127:0] wdata,
    output logic [15:0]  wstrb,
    output logic         wlast,
    output logic         wvalid,
    input  logic         wready,
    input  logic [1:0]   bresp,
    input  logic         bvalid,
    output logic         bready,
    output logic [27:0]  araddr,
    output logic [7:0]   arlen,
    output logic [2:0]   arsize,
    output logic [1:0]   arburst,
    output logic         arvalid,
    input  logic         arready,
    input  logic [127:0] rdata,
    input  logic [1:0]   rresp,
    input  logic         rlast,
    input  logic         rvalid,
    output logic         rready
);

    localparam int WORDS = FRAME_BYTES / 16;
    localparam int IDLE = 0;
    localparam int AW   = 1;
    localparam int WW   = 2;
    localparam int BR   = 3;
    localparam int AR   = 4;
    localparam int RR   = 5;
    localparam int HOLD = 6;
    localparam int DN   = 7;

    logic [127:0] pack;
    logic [127:0] word;
    logic [27:0]  word_addr;
    logic         word_valid;
    logic [3:0]   outstanding;
    logic         reading;

    logic [155:0] to_data;
    logic         to_valid;
    logic         to_ready;
    logic         to_take;
    logic [127:0] from_data;
    logic         from_valid;
    logic         from_ready;
    logic [127:0] rword;
    logic         rword_valid;
    logic         rword_ready;

    logic [2:0]   state;
    logic [15:0]  word_i;
    logic         read_ran;
    logic         wr_tog;

    (* ASYNC_REG = "TRUE" *) logic cdc_sync_rd0;
    (* ASYNC_REG = "TRUE" *) logic cdc_sync_rd1;
    (* ASYNC_REG = "TRUE" *) logic cdc_sync_wt0;
    (* ASYNC_REG = "TRUE" *) logic cdc_sync_wt1;
    logic wt_seen;

    logic         have;
    logic [3:0]   bi;
    logic [127:0] hold;
    logic [15:0]  words_got;

    wire inc = word_valid && to_ready;
    wire dec = cdc_sync_wt1 != wt_seen;

    assign awlen   = 8'd0;
    assign awsize  = 3'd4;
    assign awburst = 2'b01;
    assign wstrb   = 16'hFFFF;
    assign wlast   = 1'b1;
    assign arlen   = 8'd0;
    assign arsize  = 3'd4;
    assign arburst = 2'b01;
    assign araddr  = {8'd0, word_i, 4'd0};

    assign write_idle = (outstanding == 4'd0) && !word_valid;
    assign busy       = reading;
    assign out_byte   = hold[bi*8 +: 8];
    assign out_valid  = have;
    assign out_last   = have && (bi == 4'hF) && (words_got == 16'(WORDS - 1));
    assign from_ready = reading && !have;

    function automatic logic [127:0] insert_byte(
        input logic [127:0] base,
        input logic [3:0]   which,
        input logic [7:0]   value
    );
        insert_byte = base;
        insert_byte[which*8 +: 8] = value;
    endfunction

    always_ff @(posedge clk_byte) begin
        if (rst_byte) begin
            pack         <= 128'd0;
            word         <= 128'd0;
            word_addr    <= 28'd0;
            word_valid   <= 1'b0;
            outstanding  <= 4'd0;
            reading      <= 1'b0;
            wt_seen      <= 1'b0;
            cdc_sync_wt0 <= 1'b0;
            cdc_sync_wt1 <= 1'b0;
            have         <= 1'b0;
            bi           <= 4'd0;
            hold         <= 128'd0;
            words_got    <= 16'd0;
        end
        else begin
            cdc_sync_wt0 <= wr_tog;
            cdc_sync_wt1 <= cdc_sync_wt0;
            wt_seen      <= cdc_sync_wt1;
            outstanding  <= outstanding + {3'd0, inc} - {3'd0, dec};

            if (byte_valid && !word_valid) begin
                pack <= insert_byte(pack, byte_addr[3:0], byte_data);
                if (byte_addr[3:0] == 4'hF) begin
                    word       <= insert_byte(pack, byte_addr[3:0], byte_data);
                    word_addr  <= {9'd0, byte_addr[18:4], 4'd0};
                    word_valid <= 1'b1;
                end
            end
            else if (word_valid && to_ready)
                word_valid <= 1'b0;

            if (!reading && read_go) begin
                reading   <= 1'b1;
                have      <= 1'b0;
                bi        <= 4'd0;
                words_got <= 16'd0;
            end
            else if (reading) begin
                if (!have && from_valid) begin
                    hold <= from_data;
                    have <= 1'b1;
                    bi   <= 4'd0;
                end
                else if (have && out_ready) begin
                    if (bi == 4'hF) begin
                        have <= 1'b0;
                        if (words_got == 16'(WORDS - 1))
                            reading <= 1'b0;
                        else
                            words_got <= words_got + 16'd1;
                    end
                    else
                        bi <= bi + 4'd1;
                end
            end
        end
    end

    cdc_mailbox #(.WIDTH(156)) u_to_ddr (
        .src_clk   (clk_byte),
        .src_rst   (rst_byte),
        .src_valid (word_valid),
        .src_ready (to_ready),
        .src_data  ({word_addr, word}),
        .dst_clk   (clk_ddr),
        .dst_rst   (rst_ddr),
        .dst_valid (to_valid),
        .dst_ready (to_take),
        .dst_data  (to_data)
    );

    cdc_mailbox #(.WIDTH(128)) u_from_ddr (
        .src_clk   (clk_ddr),
        .src_rst   (rst_ddr),
        .src_valid (rword_valid),
        .src_ready (rword_ready),
        .src_data  (rword),
        .dst_clk   (clk_byte),
        .dst_rst   (rst_byte),
        .dst_valid (from_valid),
        .dst_ready (from_ready),
        .dst_data  (from_data)
    );

    always_ff @(posedge clk_ddr) begin
        if (rst_ddr) begin
            state        <= IDLE[2:0];
            word_i       <= 16'd0;
            read_ran     <= 1'b0;
            wr_tog       <= 1'b0;
            cdc_sync_rd0 <= 1'b0;
            cdc_sync_rd1 <= 1'b0;
            awaddr       <= 28'd0;
            awvalid      <= 1'b0;
            wdata        <= 128'd0;
            wvalid       <= 1'b0;
            bready       <= 1'b0;
            arvalid      <= 1'b0;
            rready       <= 1'b0;
            rword        <= 128'd0;
            rword_valid  <= 1'b0;
        end
        else begin
            cdc_sync_rd0 <= reading;
            cdc_sync_rd1 <= cdc_sync_rd0;
            if (!cdc_sync_rd1)
                read_ran <= 1'b0;

            case (state)
                IDLE[2:0]: begin
                    if (to_valid && to_take) begin
                        awaddr  <= to_data[155:128];
                        wdata   <= to_data[127:0];
                        awvalid <= 1'b1;
                        state   <= AW[2:0];
                    end
                    else if (cdc_sync_rd1 && !read_ran && gate) begin
                        read_ran <= 1'b1;
                        word_i   <= 16'd0;
                        arvalid  <= 1'b1;
                        state    <= AR[2:0];
                    end
                end
                AW[2:0]: begin
                    if (awvalid && awready) begin
                        awvalid <= 1'b0;
                        wvalid  <= 1'b1;
                        state   <= WW[2:0];
                    end
                end
                WW[2:0]: begin
                    if (wvalid && wready) begin
                        wvalid <= 1'b0;
                        bready <= 1'b1;
                        state  <= BR[2:0];
                    end
                end
                BR[2:0]: begin
                    if (bvalid && bready) begin
                        bready <= 1'b0;
                        wr_tog <= ~wr_tog;
                        state  <= IDLE[2:0];
                    end
                end
                AR[2:0]: begin
                    if (arvalid && arready) begin
                        arvalid <= 1'b0;
                        rready  <= 1'b1;
                        state   <= RR[2:0];
                    end
                end
                RR[2:0]: begin
                    if (rvalid && rready) begin
                        rready      <= 1'b0;
                        rword       <= rdata;
                        rword_valid <= 1'b1;
                        if (word_i == 16'(WORDS - 1))
                            state <= DN[2:0];
                        else
                            state <= HOLD[2:0];
                    end
                end
                HOLD[2:0]: begin
                    if (rword_valid && rword_ready) begin
                        rword_valid <= 1'b0;
                        word_i      <= word_i + 16'd1;
                        arvalid     <= 1'b1;
                        state       <= AR[2:0];
                    end
                end
                default: begin
                    if (rword_valid && rword_ready) begin
                        rword_valid <= 1'b0;
                        state       <= IDLE[2:0];
                    end
                end
            endcase
        end
    end

    assign to_take = (state == IDLE[2:0]) && gate && !(cdc_sync_rd1 && !read_ran);

endmodule
