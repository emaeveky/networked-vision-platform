// Copy one frame from a one-cycle-latency byte memory into DDR, then hand
// the same bytes back. `go` is a one-cycle start. The byte memory is on
// clk_byte; the AXI port is on clk_ddr. `gate` (DDR clock) must be high
// before the controller will accept the beats.
module ddr3_link #(
    parameter int FRAME_BYTES = 76800
) (
    input  logic        clk_byte,
    input  logic        rst_byte,
    input  logic        clk_ddr,
    input  logic        rst_ddr,
    input  logic        gate,

    input  logic        go,

    output logic        rd_en,
    output logic [16:0] rd_addr,
    input  logic [7:0]  rd_data,

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

    logic         active;
    logic         inflight;
    logic [16:0]  ptr;
    logic [3:0]   slot;
    logic [127:0] pack;
    logic [127:0] word;
    logic         word_valid;
    logic [15:0]  words_sent;
    logic         gathering;

    logic         have;
    logic [3:0]   bi;
    logic [127:0] hold;
    logic [15:0]  words_got;

    logic [127:0] to_data;
    logic         to_valid;
    logic         to_ready;
    logic         to_ready_ddr;
    logic [127:0] from_data;
    logic         from_valid;
    logic         from_ready;
    logic [127:0] rword;
    logic         rword_valid;
    logic         rword_ready;

    (* ASYNC_REG = "TRUE" *) logic cdc_sync_go0;
    (* ASYNC_REG = "TRUE" *) logic cdc_sync_go1;

    assign rd_en     = gathering && !inflight && !word_valid && (ptr < 17'(FRAME_BYTES));
    assign rd_addr   = ptr;
    assign busy      = active;
    assign out_byte  = hold[bi*8 +: 8];
    assign out_valid = have;
    assign out_last  = have && (bi == 4'hF) && (words_got == 16'(WORDS - 1));
    assign from_ready = active && !gathering && !have;

    function automatic logic [127:0] insert_byte(
        input logic [127:0] base,
        input logic [3:0]   which,
        input logic [7:0]   value
    );
        insert_byte = base;
        insert_byte[which*8 +: 8] = value;
    endfunction

    always_ff @(posedge clk_ddr) begin
        if (rst_ddr) begin
            cdc_sync_go0 <= 1'b0;
            cdc_sync_go1 <= 1'b0;
        end
        else begin
            cdc_sync_go0 <= active;
            cdc_sync_go1 <= cdc_sync_go0;
        end
    end

    cdc_mailbox #(.WIDTH(128)) u_to_ddr (
        .src_clk   (clk_byte),
        .src_rst   (rst_byte),
        .src_valid (word_valid),
        .src_ready (to_ready),
        .src_data  (word),
        .dst_clk   (clk_ddr),
        .dst_rst   (rst_ddr),
        .dst_valid (to_valid),
        .dst_ready (to_ready_ddr),
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

    ddr3_frame #(.WORDS(WORDS)) u_frame (
        .clk         (clk_ddr),
        .rst         (rst_ddr),
        .gate        (gate),
        .go          (cdc_sync_go1),
        .wword       (to_data),
        .wword_valid (to_valid),
        .wword_ready (to_ready_ddr),
        .rword       (rword),
        .rword_valid (rword_valid),
        .rword_ready (rword_ready),
        .awaddr      (awaddr),
        .awlen       (awlen),
        .awsize      (awsize),
        .awburst     (awburst),
        .awvalid     (awvalid),
        .awready     (awready),
        .wdata       (wdata),
        .wstrb       (wstrb),
        .wlast       (wlast),
        .wvalid      (wvalid),
        .wready      (wready),
        .bresp       (bresp),
        .bvalid      (bvalid),
        .bready      (bready),
        .araddr      (araddr),
        .arlen       (arlen),
        .arsize      (arsize),
        .arburst     (arburst),
        .arvalid     (arvalid),
        .arready     (arready),
        .rdata       (rdata),
        .rresp       (rresp),
        .rlast       (rlast),
        .rvalid      (rvalid),
        .rready      (rready)
    );

    always_ff @(posedge clk_byte) begin
        if (rst_byte) begin
            active     <= 1'b0;
            inflight   <= 1'b0;
            ptr        <= 17'd0;
            slot       <= 4'd0;
            pack       <= 128'd0;
            word       <= 128'd0;
            word_valid <= 1'b0;
            words_sent <= 16'd0;
            gathering  <= 1'b0;
            have       <= 1'b0;
            bi         <= 4'd0;
            hold       <= 128'd0;
            words_got  <= 16'd0;
        end
        else begin
            if (!active && go) begin
                active     <= 1'b1;
                gathering  <= 1'b1;
                inflight   <= 1'b0;
                ptr        <= 17'd0;
                slot       <= 4'd0;
                pack       <= 128'd0;
                word_valid <= 1'b0;
                words_sent <= 16'd0;
                have       <= 1'b0;
                bi         <= 4'd0;
                words_got  <= 16'd0;
            end
            else if (active && gathering) begin
                if (rd_en) begin
                    inflight <= 1'b1;
                    ptr      <= ptr + 17'd1;
                    slot     <= ptr[3:0];
                end
                else
                    inflight <= 1'b0;

                if (inflight) begin
                    pack <= insert_byte(pack, slot, rd_data);
                    if (slot == 4'hF) begin
                        word       <= insert_byte(pack, slot, rd_data);
                        word_valid <= 1'b1;
                    end
                end
                else if (word_valid && to_ready) begin
                    word_valid <= 1'b0;
                    if (words_sent == 16'(WORDS - 1))
                        gathering <= 1'b0;
                    else
                        words_sent <= words_sent + 16'd1;
                end
            end
            else if (active && !gathering) begin
                if (!have && from_valid) begin
                    hold <= from_data;
                    have <= 1'b1;
                    bi   <= 4'd0;
                end
                else if (have && out_ready) begin
                    if (bi == 4'hF) begin
                        have <= 1'b0;
                        if (words_got == 16'(WORDS - 1))
                            active <= 1'b0;
                        else
                            words_got <= words_got + 16'd1;
                    end
                    else
                        bi <= bi + 4'd1;
                end
            end
        end
    end

endmodule
