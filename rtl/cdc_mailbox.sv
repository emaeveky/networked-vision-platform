// One-word mailbox between two clocks. The payload is written a cycle before
// the request toggle, and the receiver copies it before acknowledging.
module cdc_mailbox #(
    parameter int WIDTH = 128
) (
    input  logic             src_clk,
    input  logic             src_rst,
    input  logic             src_valid,
    output logic             src_ready,
    input  logic [WIDTH-1:0] src_data,

    input  logic             dst_clk,
    input  logic             dst_rst,
    output logic             dst_valid,
    input  logic             dst_ready,
    output logic [WIDTH-1:0] dst_data
);

    logic             req;
    logic             arm;
    logic [WIDTH-1:0] hold;
    logic             ack;

    (* ASYNC_REG = "TRUE" *) logic cdc_sync_ack0;
    (* ASYNC_REG = "TRUE" *) logic cdc_sync_ack1;
    (* ASYNC_REG = "TRUE" *) logic cdc_sync_req0;
    (* ASYNC_REG = "TRUE" *) logic cdc_sync_req1;
    (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] cdc_sync_cap;

    logic pending;

    assign src_ready = (req == cdc_sync_ack1) && !arm;
    assign dst_valid = pending;
    assign dst_data  = cdc_sync_cap;

    always_ff @(posedge src_clk) begin
        if (src_rst) begin
            req           <= 1'b0;
            arm           <= 1'b0;
            cdc_sync_ack0 <= 1'b0;
            cdc_sync_ack1 <= 1'b0;
        end
        else begin
            cdc_sync_ack0 <= ack;
            cdc_sync_ack1 <= cdc_sync_ack0;
            if (src_ready && src_valid) begin
                hold <= src_data;
                arm  <= 1'b1;
            end
            else if (arm) begin
                req <= ~req;
                arm <= 1'b0;
            end
        end
    end

    always_ff @(posedge dst_clk) begin
        if (dst_rst) begin
            cdc_sync_req0 <= 1'b0;
            cdc_sync_req1 <= 1'b0;
            ack           <= 1'b0;
            pending       <= 1'b0;
        end
        else begin
            cdc_sync_req0 <= req;
            cdc_sync_req1 <= cdc_sync_req0;
            if (!pending && (cdc_sync_req1 != ack)) begin
                cdc_sync_cap <= hold;
                pending      <= 1'b1;
            end
            else if (pending && dst_ready) begin
                pending <= 1'b0;
                ack     <= ~ack;
            end
        end
    end

endmodule
