param(
    [string]$TaskRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$TaskOutput = '',
    [string]$TaskEngine = '',
    [string]$TaskId = '002C.5',
    [string]$TaskQaRoot = '',
    [string]$TaskPython = 'python',
    [string]$TaskOnly = '',
    [switch]$CorrectionV2
)
$ErrorActionPreference = 'Stop'
$TaskHelperDirectory = Join-Path $TaskRoot 'tools\workspace'
# Shared helper supplies the same task root and engine discovery as all other
# tooling; explicit output remains available for historical capture recipes.
if (-not $TaskOutput) {
    $TaskHelperArguments = @((Join-Path $TaskHelperDirectory 'workspace.py'))
    if ($TaskQaRoot) { $TaskHelperArguments += @('--qa-root', $TaskQaRoot) }
    $TaskHelperArguments += @('create-task', $TaskId)
    $TaskWorkspace = & $TaskPython @TaskHelperArguments
    if ($LASTEXITCODE -ne 0) { throw 'Task QA workspace creation failed' }
    $TaskOutput = Join-Path $TaskWorkspace 'temp\identity-motion'
}
if (-not $TaskEngine) {
    $TaskBootstrap = 'import sys; sys.path.insert(0, sys.argv[1]); import workspace; print(workspace.find_tool("godot"))'
    $TaskEngine = & $TaskPython -c $TaskBootstrap $TaskHelperDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Godot discovery failed; pass -TaskEngine or set TOPGAME_GODOT' }
}
New-Item -ItemType Directory -Force -Path $TaskOutput | Out-Null
# Real proc windows found through the identical full-reserve/input-only diagnostic.
# No state is edited to make a capture happen. Warm-up executes all real ticks.
$TaskWindows = [ordered]@{
    impact_wake=10.8; redline=72.8; iron_comet=28.8; dead_centre=0.0;
    afterimage=3.0; chain_impact=51.0; clutch=147.8; high_gear=3.0;
    orbit_drive=7.7; crash_guard=14.8; momentum_bank=1.3; predator_line=0.0;
    crosscut=6.0; runaway=10.0; breakneck=17.3; bulwark=0.5;
    counterweight=0.5; ghost_circuit=3.7; slipstream=15.0; terminal_velocity=3.6; flow_state=3.0
}
if ($CorrectionV2) { $TaskWindows.orbit_drive = 13.4 }
foreach ($TaskFamily in $TaskWindows.Keys) {
    if ($TaskOnly -and $TaskFamily -notin $TaskOnly.Split(',')) { continue }
    $TaskAvi = Join-Path $TaskOutput "$TaskFamily.avi"
    $TaskManifest = Join-Path $TaskOutput "$TaskFamily.json"
    $TaskFrames = Join-Path $TaskOutput "$TaskFamily-frames"
    $TaskStdout = Join-Path $TaskOutput "$TaskFamily.stdout.log"
    $TaskStderr = Join-Path $TaskOutput "$TaskFamily.stderr.log"
    $TaskArguments = @('--path', ('"{0}"' -f $TaskRoot), '--script', 'res://tests/capture_identity_motion.gd',
        '--write-movie', ('"{0}"' -f $TaskAvi), '--fixed-fps', '60', '--disable-vsync', '--', '--blind',
        "--family=$TaskFamily", "--start=$($TaskWindows[$TaskFamily])", '--length=6',
        ('"--manifest={0}"' -f $TaskManifest), ('"--frames={0}"' -f $TaskFrames))
    if ($CorrectionV2 -and $TaskFamily -eq 'orbit_drive') { $TaskArguments += '--policy=long_drift' }
    $TaskProcess = Start-Process -FilePath $TaskEngine -ArgumentList $TaskArguments -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput $TaskStdout -RedirectStandardError $TaskStderr
    $TaskErrors = Get-Content -LiteralPath $TaskStderr -Raw
    if ($TaskProcess.ExitCode -ne 0 -or $TaskErrors -match 'SCRIPT ERROR|ERROR:') { throw "$TaskFamily capture failed: $TaskErrors" }
    $TaskReport = Get-Content -LiteralPath $TaskManifest -Raw | ConvertFrom-Json
    if ($TaskReport.runs[0].capture_frames -ne 360) { throw "$TaskFamily did not capture the intended real window" }
    Write-Output "$TaskFamily captured real6s; procs=$($TaskReport.runs[0].window_counters | ConvertTo-Json -Compress)"
}
