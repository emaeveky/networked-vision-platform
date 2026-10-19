$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Invoke-Sim {
    param(
        [string]$Name,
        [string[]]$Sources,
        [string[]]$PlusArgs = @()
    )

    $Out = Join-Path $Root "sim\$Name.vvp"
    & iverilog -g2012 -o $Out @Sources
    if ($LASTEXITCODE -ne 0) {
        throw "iverilog failed for $Name"
    }
    $Log = & vvp $Out @PlusArgs 2>&1 | ForEach-Object { "$_" }
    $Log | Write-Host
    if ($LASTEXITCODE -ne 0) {
        throw "vvp failed for $Name"
    }
    if ($Log -match '^FAIL') {
        throw "$Name $PlusArgs reported a failure"
    }
}

Invoke-Sim "packet_tracker_tb" @(
    "rtl/packet_tracker.sv",
    "sim/packet_tracker_tb.sv"
)
Invoke-Sim "frame_engine_tb" @(
    "rtl/packet_tracker.sv",
    "rtl/frame_engine.sv",
    "sim/frame_engine_tb.sv"
)
Invoke-Sim "double_buffer_ctrl_tb" @(
    "rtl/double_buffer_ctrl.sv",
    "sim/double_buffer_ctrl_tb.sv"
)
Invoke-Sim "img_threshold_tb" @(
    "rtl/img_threshold.sv",
    "sim/img_threshold_tb.sv"
)
Invoke-Sim "img_sobel_tb" @(
    "rtl/img_sobel.sv",
    "sim/img_sobel_tb.sv"
)
Invoke-Sim "motion_pipe_tb" @(
    "rtl/frame_mem.sv",
    "rtl/motion_box.sv",
    "sim/motion_pipe_tb.sv"
)
Invoke-Sim "bg_frame_tb" @(
    "rtl/bg_frame.sv",
    "sim/bg_frame_tb.sv"
)
Invoke-Sim "ddr3_pattern_tb" @(
    "rtl/ddr3_pattern.sv",
    "sim/ddr3_axi_ram.sv",
    "sim/ddr3_pattern_tb.sv"
)
Invoke-Sim "proto_parser_tb" @(
    "rtl/proto_parser.sv",
    "sim/proto_parser_tb.sv"
)
Invoke-Sim "crc_commit_tb" @(
    "rtl/proto_parser.sv",
    "rtl/packet_tracker.sv",
    "rtl/frame_engine.sv",
    "rtl/pixel_writer.sv",
    "rtl/double_buffer_ctrl.sv",
    "rtl/frame_mem.sv",
    "rtl/vision_core.sv",
    "sim/crc_commit_tb.sv"
)
Invoke-Sim "uart_loopback_tb" @(
    "rtl/uart_tx.sv",
    "rtl/uart_rx.sv",
    "sim/uart_loopback_tb.sv"
)
Invoke-Sim "pixel_writer_tb" @(
    "rtl/pixel_writer.sv",
    "rtl/frame_mem.sv",
    "sim/pixel_writer_tb.sv"
)
Invoke-Sim "vision_core_tb" @(
    "rtl/packet_tracker.sv",
    "rtl/frame_engine.sv",
    "rtl/pixel_writer.sv",
    "rtl/double_buffer_ctrl.sv",
    "rtl/frame_mem.sv",
    "rtl/vision_core.sv",
    "sim/vision_core_tb.sv"
)

# Board-level test driving the FTDI serial line bit by bit. Two packets is a
# fast (~10 s) protocol check; the full-frame stress runs are documented in
# sim/arty_top_uart_tb.sv and take a few minutes each:
#   vvp sim/arty_top_uart_tb.vvp +frames=2                         (status reply)
#   vvp sim/arty_top_uart_tb.vvp +frames=2 +first_frame=65535      (frame-id wrap)
#   vvp sim/arty_top_uart_tb.vvp +frames=2 +frame_gap_bits=0       (back-to-back)
#   vvp sim/arty_top_uart_tb.vvp +frames=2 +drop_byte=50000        (resync)
#   vvp sim/arty_top_uart_tb.vvp +packets=2 +bit_ps=1040000        (baud +4%)
$TopSources = @(
    "rtl/uart_rx.sv",
    "rtl/uart_tx.sv",
    "rtl/proto_parser.sv",
    "rtl/packet_tracker.sv",
    "rtl/frame_engine.sv",
    "rtl/pixel_writer.sv",
    "rtl/double_buffer_ctrl.sv",
    "rtl/frame_mem.sv",
    "rtl/vision_core.sv",
    "rtl/img_threshold.sv",
    "rtl/img_sobel.sv",
    "rtl/motion_box.sv",
    "rtl/bg_frame.sv",
    "sim/ddr3_board_stub.sv",
    "rtl/arty_s7_uart_top.sv",
    "sim/arty_top_uart_tb.sv"
)
Invoke-Sim "arty_top_uart_tb" $TopSources -PlusArgs @("+packets=2")
Invoke-Sim "arty_top_uart_tb" $TopSources -PlusArgs @("+packets=2", "+bit_ps=1030000")
Invoke-Sim "arty_top_uart_tb" $TopSources -PlusArgs @("+packets=2", "+bit_ps=970000")
Invoke-Sim "arty_top_uart_tb" $TopSources -PlusArgs @("+packets=4", "+drop_byte=100")
Invoke-Sim "uart_readback_tb" @(
    "rtl/uart_rx.sv",
    "rtl/uart_tx.sv",
    "rtl/proto_parser.sv",
    "rtl/packet_tracker.sv",
    "rtl/frame_engine.sv",
    "rtl/pixel_writer.sv",
    "rtl/double_buffer_ctrl.sv",
    "rtl/frame_mem.sv",
    "rtl/vision_core.sv",
    "rtl/img_threshold.sv",
    "rtl/img_sobel.sv",
    "rtl/motion_box.sv",
    "rtl/bg_frame.sv",
    "sim/ddr3_board_stub.sv",
    "rtl/arty_s7_uart_top.sv",
    "sim/uart_readback_tb.sv"
)
Invoke-Sim "uart_process_tb" @(
    "rtl/uart_rx.sv",
    "rtl/uart_tx.sv",
    "rtl/proto_parser.sv",
    "rtl/packet_tracker.sv",
    "rtl/frame_engine.sv",
    "rtl/pixel_writer.sv",
    "rtl/double_buffer_ctrl.sv",
    "rtl/frame_mem.sv",
    "rtl/vision_core.sv",
    "rtl/img_threshold.sv",
    "rtl/img_sobel.sv",
    "rtl/motion_box.sv",
    "rtl/bg_frame.sv",
    "sim/ddr3_board_stub.sv",
    "rtl/arty_s7_uart_top.sv",
    "sim/uart_process_tb.sv"
)
Invoke-Sim "uart_sobel_wide_tb" @(
    "rtl/uart_rx.sv",
    "rtl/uart_tx.sv",
    "rtl/proto_parser.sv",
    "rtl/packet_tracker.sv",
    "rtl/frame_engine.sv",
    "rtl/pixel_writer.sv",
    "rtl/double_buffer_ctrl.sv",
    "rtl/frame_mem.sv",
    "rtl/vision_core.sv",
    "rtl/img_threshold.sv",
    "rtl/img_sobel.sv",
    "rtl/motion_box.sv",
    "rtl/bg_frame.sv",
    "sim/ddr3_board_stub.sv",
    "rtl/arty_s7_uart_top.sv",
    "sim/uart_sobel_wide_tb.sv"
)

Write-Host "All RTL simulations passed"

Set-Location (Join-Path $Root "host")
& py -3 -m unittest test_host_models.py
if ($LASTEXITCODE -ne 0) {
    throw "Python host tests failed"
}
& py -3 generate_test_frame.py --out (Join-Path $Root "sim\vectors")
if ($LASTEXITCODE -ne 0) {
    throw "Test-frame generator failed"
}

Write-Host "Host models and test-frame generator passed"
