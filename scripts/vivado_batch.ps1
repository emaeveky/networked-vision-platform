param(
    [Parameter(Mandatory = $true)]
    [string]$TclScript,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$Vivado = "C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat"
if (-not (Test-Path $Vivado)) {
    throw "Vivado 2026.1 not found at $Vivado"
}
$Script = Join-Path $PSScriptRoot $TclScript
if (-not (Test-Path $Script)) {
    throw "Missing Tcl script: $Script"
}

# A Vivado GUI holding this project keeps a lock on build/vivado/vision_uart.runs.
# create_project -force then deletes the old bitstream and aborts partway, which
# leaves the board running stale logic. Refuse to start instead.
$running = @(Get-Process -Name vivado -ErrorAction SilentlyContinue)
if ($running.Count -gt 0 -and -not $Force) {
    throw ("Vivado is already running (PID $($running.Id -join ', ')). " +
           "Close the Vivado GUI first, or re-run with -Force. " +
           "A batch rebuild while the GUI holds the project lock deletes the " +
           "bitstream without producing a new one.")
}

$root = Split-Path $PSScriptRoot -Parent
$lockFiles = @(Get-ChildItem -Path (Join-Path $root "build\vivado") -Recurse -Filter "*.lpr" -ErrorAction SilentlyContinue)
if ($lockFiles.Count -gt 0 -and -not $Force) {
    Write-Warning "Stale Vivado lock files found; removing them:"
    $lockFiles | ForEach-Object { Write-Warning "  $($_.FullName)" }
    $lockFiles | Remove-Item -Force -ErrorAction SilentlyContinue
}

& $Vivado -mode batch -source $Script
if ($LASTEXITCODE -ne 0) {
    throw "Vivado failed with exit code $LASTEXITCODE"
}
