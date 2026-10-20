// Arty S7-50 DDR3. The 100 MHz oscillator feeds the controller. The 12 MHz
// clock makes the 200 MHz IDELAY reference. After calibration, one 320x240
// frame is written and read back.
module ddr3_board (
    input  logic        clk12,
    input  logic        clk100,
    input  logic        rst12,
    input  logic        copy_go,
    output logic        copy_busy,
    output logic        copy_rd_en,
    output logic [16:0] copy_rd_addr,
    input  logic [7:0]  copy_rd_data,
    output logic [7:0]  copy_byte,
    output logic        copy_valid,
    output logic        copy_last,
    input  logic        copy_ready,

    input  logic        sink_byte_valid,
    input  logic [7:0]  sink_byte,
    input  logic [18:0] sink_byte_addr,
    output logic        sink_write_idle,
    input  logic        sink_read_go,
    output logic [7:0]  sink_out_byte,
    output logic        sink_out_valid,
    output logic        sink_out_last,
    input  logic        sink_out_ready,
    output logic        sink_busy,

    output logic        calib,
    output logic        test_done,
    output logic        test_pass,

    inout  wire [15:0]  ddr3_dq,
    inout  wire [1:0]   ddr3_dqs_n,
    inout  wire [1:0]   ddr3_dqs_p,
    output logic [13:0] ddr3_addr,
    output logic [2:0]  ddr3_ba,
    output logic        ddr3_ras_n,
    output logic        ddr3_cas_n,
    output logic        ddr3_we_n,
    output logic        ddr3_reset_n,
    output logic [0:0]  ddr3_ck_p,
    output logic [0:0]  ddr3_ck_n,
    output logic [0:0]  ddr3_cke,
    output logic [0:0]  ddr3_cs_n,
    output logic [1:0]  ddr3_dm,
    output logic [0:0]  ddr3_odt
);

    logic        clk200;
    logic        locked;
    logic [15:0] rst_cnt;
    logic        sys_rst;
    logic        ui_clk;
    logic        ui_rst;
    logic        init_calib_complete;
    logic        aresetn;

    logic [27:0] awaddr;
    logic [7:0]  awlen;
    logic [2:0]  awsize;
    logic [1:0]  awburst;
    logic        awvalid;
    logic        awready;
    logic [127:0] wdata;
    logic [15:0] wstrb;
    logic        wlast;
    logic        wvalid;
    logic        wready;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;
    logic [27:0] araddr;
    logic [7:0]  arlen;
    logic [2:0]  arsize;
    logic [1:0]  arburst;
    logic        arvalid;
    logic        arready;
    logic [127:0] rdata;
    logic [1:0]  rresp;
    logic        rlast;
    logic        rvalid;
    logic        rready;
    logic        raw_done;
    logic        raw_pass;
    logic        use_frame;

    logic [27:0] pat_awaddr;
    logic [7:0]  pat_awlen;
    logic [2:0]  pat_awsize;
    logic [1:0]  pat_awburst;
    logic        pat_awvalid;
    logic [127:0] pat_wdata;
    logic [15:0] pat_wstrb;
    logic        pat_wlast;
    logic        pat_wvalid;
    logic        pat_bready;
    logic [27:0] pat_araddr;
    logic [7:0]  pat_arlen;
    logic [2:0]  pat_arsize;
    logic [1:0]  pat_arburst;
    logic        pat_arvalid;
    logic        pat_rready;

    logic [27:0] frm_awaddr;
    logic [7:0]  frm_awlen;
    logic [2:0]  frm_awsize;
    logic [1:0]  frm_awburst;
    logic        frm_awvalid;
    logic [127:0] frm_wdata;
    logic [15:0] frm_wstrb;
    logic        frm_wlast;
    logic        frm_wvalid;
    logic        frm_bready;
    logic [27:0] frm_araddr;
    logic [7:0]  frm_arlen;
    logic [2:0]  frm_arsize;
    logic [1:0]  frm_arburst;
    logic        frm_arvalid;
    logic        frm_rready;
    logic        use_sink;

    logic [27:0] snk_awaddr;
    logic [7:0]  snk_awlen;
    logic [2:0]  snk_awsize;
    logic [1:0]  snk_awburst;
    logic        snk_awvalid;
    logic [127:0] snk_wdata;
    logic [15:0] snk_wstrb;
    logic        snk_wlast;
    logic        snk_wvalid;
    logic        snk_bready;
    logic [27:0] snk_araddr;
    logic [7:0]  snk_arlen;
    logic [2:0]  snk_arsize;
    logic [1:0]  snk_arburst;
    logic        snk_arvalid;
    logic        snk_rready;
    (* ASYNC_REG = "TRUE" *) logic [2:0] sync0;
    (* ASYNC_REG = "TRUE" *) logic [2:0] sync1;

    clk_wiz_200 u_ref (
        .clk_out1 (clk200),
        .locked   (locked),
        .clk_in1  (clk12)
    );

    // sys_rst is active-low. Hold it until the reference clock has been up
    // long enough for the MIG input requirement.
    always_ff @(posedge clk200) begin
        if (!locked)
            rst_cnt <= 16'd0;
        else if (rst_cnt != 16'hFFFF)
            rst_cnt <= rst_cnt + 16'd1;
    end
    assign sys_rst = (rst_cnt == 16'hFFFF);

    mig_arty u_mig (
        .ddr3_addr           (ddr3_addr),
        .ddr3_ba             (ddr3_ba),
        .ddr3_cas_n          (ddr3_cas_n),
        .ddr3_ck_n           (ddr3_ck_n),
        .ddr3_ck_p           (ddr3_ck_p),
        .ddr3_cke            (ddr3_cke),
        .ddr3_ras_n          (ddr3_ras_n),
        .ddr3_reset_n        (ddr3_reset_n),
        .ddr3_we_n           (ddr3_we_n),
        .ddr3_dq             (ddr3_dq),
        .ddr3_dqs_n          (ddr3_dqs_n),
        .ddr3_dqs_p          (ddr3_dqs_p),
        .ddr3_cs_n           (ddr3_cs_n),
        .ddr3_dm             (ddr3_dm),
        .ddr3_odt            (ddr3_odt),
        .init_calib_complete (init_calib_complete),
        .ui_clk              (ui_clk),
        .ui_clk_sync_rst     (ui_rst),
        .mmcm_locked         (),
        .aresetn             (aresetn),
        .app_sr_req          (1'b0),
        .app_ref_req         (1'b0),
        .app_zq_req          (1'b0),
        .app_sr_active       (),
        .app_ref_ack         (),
        .app_zq_ack          (),
        .s_axi_awid          (4'd0),
        .s_axi_awaddr        (awaddr),
        .s_axi_awlen         (awlen),
        .s_axi_awsize        (awsize),
        .s_axi_awburst       (awburst),
        .s_axi_awlock        (1'b0),
        .s_axi_awcache       (4'd0),
        .s_axi_awprot        (3'd0),
        .s_axi_awqos         (4'd0),
        .s_axi_awvalid       (awvalid),
        .s_axi_awready       (awready),
        .s_axi_wdata         (wdata),
        .s_axi_wstrb         (wstrb),
        .s_axi_wlast         (wlast),
        .s_axi_wvalid        (wvalid),
        .s_axi_wready        (wready),
        .s_axi_bid           (),
        .s_axi_bresp         (bresp),
        .s_axi_bvalid        (bvalid),
        .s_axi_bready        (bready),
        .s_axi_arid          (4'd0),
        .s_axi_araddr        (araddr),
        .s_axi_arlen         (arlen),
        .s_axi_arsize        (arsize),
        .s_axi_arburst       (arburst),
        .s_axi_arlock        (1'b0),
        .s_axi_arcache       (4'd0),
        .s_axi_arprot        (3'd0),
        .s_axi_arqos         (4'd0),
        .s_axi_arvalid       (arvalid),
        .s_axi_arready       (arready),
        .s_axi_rid           (),
        .s_axi_rdata         (rdata),
        .s_axi_rresp         (rresp),
        .s_axi_rlast         (rlast),
        .s_axi_rvalid        (rvalid),
        .s_axi_rready        (rready),
        .sys_clk_i           (clk100),
        .clk_ref_i           (clk200),
        .device_temp_i       (12'd0),
        .sys_rst             (sys_rst)
    );

    assign aresetn = ~ui_rst;

    ddr3_pattern #(.BEATS(64), .BURSTS(75)) u_pat (
        .clk     (ui_clk),
        .rst     (ui_rst),
        .calib   (init_calib_complete),
        .awaddr  (pat_awaddr),
        .awlen   (pat_awlen),
        .awsize  (pat_awsize),
        .awburst (pat_awburst),
        .awvalid (pat_awvalid),
        .awready (awready),
        .wdata   (pat_wdata),
        .wstrb   (pat_wstrb),
        .wlast   (pat_wlast),
        .wvalid  (pat_wvalid),
        .wready  (wready),
        .bresp   (bresp),
        .bvalid  (bvalid),
        .bready  (pat_bready),
        .araddr  (pat_araddr),
        .arlen   (pat_arlen),
        .arsize  (pat_arsize),
        .arburst (pat_arburst),
        .arvalid (pat_arvalid),
        .arready (arready),
        .rdata   (rdata),
        .rresp   (rresp),
        .rlast   (rlast),
        .rvalid  (rvalid),
        .rready  (pat_rready),
        .done    (raw_done),
        .pass    (raw_pass)
    );

    assign use_frame = raw_done;

    ddr3_link u_link (
        .clk_byte  (clk12),
        .rst_byte  (rst12),
        .clk_ddr   (ui_clk),
        .rst_ddr   (ui_rst),
        .gate      (raw_done),
        .go        (copy_go),
        .rd_en     (copy_rd_en),
        .rd_addr   (copy_rd_addr),
        .rd_data   (copy_rd_data),
        .out_byte  (copy_byte),
        .out_valid (copy_valid),
        .out_last  (copy_last),
        .out_ready (copy_ready),
        .busy      (copy_busy),
        .awaddr    (frm_awaddr),
        .awlen     (frm_awlen),
        .awsize    (frm_awsize),
        .awburst   (frm_awburst),
        .awvalid   (frm_awvalid),
        .awready   (awready),
        .wdata     (frm_wdata),
        .wstrb     (frm_wstrb),
        .wlast     (frm_wlast),
        .wvalid    (frm_wvalid),
        .wready    (wready),
        .bresp     (bresp),
        .bvalid    (bvalid),
        .bready    (frm_bready),
        .araddr    (frm_araddr),
        .arlen     (frm_arlen),
        .arsize    (frm_arsize),
        .arburst   (frm_arburst),
        .arvalid   (frm_arvalid),
        .arready   (arready),
        .rdata     (rdata),
        .rresp     (rresp),
        .rlast     (rlast),
        .rvalid    (rvalid),
        .rready    (frm_rready)
    );

    ddr3_sink u_sink (
        .clk_byte    (clk12),
        .rst_byte    (rst12),
        .clk_ddr     (ui_clk),
        .rst_ddr     (ui_rst),
        .gate        (raw_done),
        .byte_valid  (sink_byte_valid),
        .byte_data   (sink_byte),
        .byte_addr   (sink_byte_addr),
        .write_idle  (sink_write_idle),
        .read_go     (sink_read_go),
        .out_byte    (sink_out_byte),
        .out_valid   (sink_out_valid),
        .out_last    (sink_out_last),
        .out_ready   (sink_out_ready),
        .busy        (sink_busy),
        .awaddr      (snk_awaddr),
        .awlen       (snk_awlen),
        .awsize      (snk_awsize),
        .awburst     (snk_awburst),
        .awvalid     (snk_awvalid),
        .awready     (awready),
        .wdata       (snk_wdata),
        .wstrb       (snk_wstrb),
        .wlast       (snk_wlast),
        .wvalid      (snk_wvalid),
        .wready      (wready),
        .bresp       (bresp),
        .bvalid      (bvalid),
        .bready      (snk_bready),
        .araddr      (snk_araddr),
        .arlen       (snk_arlen),
        .arsize      (snk_arsize),
        .arburst     (snk_arburst),
        .arvalid     (snk_arvalid),
        .arready     (arready),
        .rdata       (rdata),
        .rresp       (rresp),
        .rlast       (rlast),
        .rvalid      (rvalid),
        .rready      (snk_rready)
    );

    assign use_sink = snk_awvalid | snk_wvalid | snk_bready | snk_arvalid | snk_rready;

    assign awaddr  = use_sink ? snk_awaddr  : (use_frame ? frm_awaddr  : pat_awaddr);
    assign awlen   = use_sink ? snk_awlen   : (use_frame ? frm_awlen   : pat_awlen);
    assign awsize  = use_sink ? snk_awsize  : (use_frame ? frm_awsize  : pat_awsize);
    assign awburst = use_sink ? snk_awburst : (use_frame ? frm_awburst : pat_awburst);
    assign awvalid = use_sink ? snk_awvalid : (use_frame ? frm_awvalid : pat_awvalid);
    assign wdata   = use_sink ? snk_wdata   : (use_frame ? frm_wdata   : pat_wdata);
    assign wstrb   = use_sink ? snk_wstrb   : (use_frame ? frm_wstrb   : pat_wstrb);
    assign wlast   = use_sink ? snk_wlast   : (use_frame ? frm_wlast   : pat_wlast);
    assign wvalid  = use_sink ? snk_wvalid  : (use_frame ? frm_wvalid  : pat_wvalid);
    assign bready  = use_sink ? snk_bready  : (use_frame ? frm_bready  : pat_bready);
    assign araddr  = use_sink ? snk_araddr  : (use_frame ? frm_araddr  : pat_araddr);
    assign arlen   = use_sink ? snk_arlen   : (use_frame ? frm_arlen   : pat_arlen);
    assign arsize  = use_sink ? snk_arsize  : (use_frame ? frm_arsize  : pat_arsize);
    assign arburst = use_sink ? snk_arburst : (use_frame ? frm_arburst : pat_arburst);
    assign arvalid = use_sink ? snk_arvalid : (use_frame ? frm_arvalid : pat_arvalid);
    assign rready  = use_sink ? snk_rready  : (use_frame ? frm_rready  : pat_rready);

    always_ff @(posedge clk12) begin
        sync0 <= {raw_pass, raw_done, init_calib_complete};
        sync1 <= sync0;
    end

    assign calib     = sync1[0];
    assign test_done = sync1[1];
    assign test_pass = sync1[2];

endmodule
