param(
    [string]$TaskRoot = 'C:\GPT GAME BUILDING\topgame-task-002c5',
    [string]$TaskOutput = 'C:\GPT GAME BUILDING\task-002c5-qa\art-addendum\motion',
    [string]$TaskEngine = 'E:\Desktop\Godot_v4.7.2-stable_win64_console.exe',
    [string]$TaskOnly = ''
)
$ErrorActionPreference = 'Stop'
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
    $TaskProcess = Start-Process -FilePath $TaskEngine -ArgumentList $TaskArguments -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput $TaskStdout -RedirectStandardError $TaskStderr
    $TaskErrors = Get-Content -LiteralPath $TaskStderr -Raw
    if ($TaskProcess.ExitCode -ne 0 -or $TaskErrors -match 'SCRIPT ERROR|ERROR:') { throw "$TaskFamily capture failed: $TaskErrors" }
    $TaskReport = Get-Content -LiteralPath $TaskManifest -Raw | ConvertFrom-Json
    if ($TaskReport.runs[0].capture_frames -ne 360) { throw "$TaskFamily did not capture the intended real window" }
    Write-Output "$TaskFamily captured real6s; procs=$($TaskReport.runs[0].window_counters | ConvertTo-Json -Compress)"
}
