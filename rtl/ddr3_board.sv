// Arty S7-50 DDR3. The 100 MHz oscillator feeds the controller. The 12 MHz
// clock makes the 200 MHz IDELAY reference. After calibration, one 320x240
// frame is written and read back.
module ddr3_board (
    input  logic        clk12,
    input  logic        clk100,

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
        .awaddr  (awaddr),
        .awlen   (awlen),
        .awsize  (awsize),
        .awburst (awburst),
        .awvalid (awvalid),
        .awready (awready),
        .wdata   (wdata),
        .wstrb   (wstrb),
        .wlast   (wlast),
        .wvalid  (wvalid),
        .wready  (wready),
        .bresp   (bresp),
        .bvalid  (bvalid),
        .bready  (bready),
        .araddr  (araddr),
        .arlen   (arlen),
        .arsize  (arsize),
        .arburst (arburst),
        .arvalid (arvalid),
        .arready (arready),
        .rdata   (rdata),
        .rresp   (rresp),
        .rlast   (rlast),
        .rvalid  (rvalid),
        .rready  (rready),
        .done    (raw_done),
        .pass    (raw_pass)
    );

    always_ff @(posedge clk12) begin
        sync0 <= {raw_pass, raw_done, init_calib_complete};
        sync1 <= sync0;
    end

    assign calib     = sync1[0];
    assign test_done = sync1[1];
    assign test_pass = sync1[2];

endmodule
