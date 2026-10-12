<#
.SYNOPSIS
    Deadlock infinite-loading auto-fix for VPN split tunneling.

.DESCRIPTION
    Starts Deadlock through Steam (unless it is already running), watches the console log,
    and when the hideout connection to 127.0.0.1 fails, presses F9 in the game window.
    F9 must be bound to "sv_cheats 1; restart" (see autoexec.cfg in this repository).

    Requires the Steam launch option -condebug, which writes the console to
    game\citadel\console.log. Keys are only sent while Deadlock is the foreground window.
    The script exits when deadlock.exe exits.

    The game folder is found in this order: -GamePath, Steam's library folders,
    then the path of the running deadlock.exe.

.PARAMETER GamePath
    Deadlock install folder (the one containing "game"). Only needed if automatic detection fails.

.PARAMETER LogPath
    Console log to watch. Defaults to <GamePath>\game\citadel\console.log.

.PARAMETER NoLaunch
    Do not start the game; wait for it to be started some other way.

.PARAMETER DryRun
    Print what would be sent instead of pressing keys, and do not wait for deadlock.exe.
    Requires -LogPath or a detectable game folder.
#>
param(
    [string]$GamePath,
    [string]$LogPath,
    [switch]$NoLaunch,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$AppId          = 1422450
$F9ScanCode     = 0x43
$CooldownSec    = 8     # minimum time between two key presses (the game retries about every 11 s)
$FocusWaitSec   = 30    # how long to wait for the game window to be in front
$StaleSec       = 30    # log lines older than this never trigger a key press
$NoLogWarnSec   = 60    # hint about -condebug if no log shows up this long after launch
$PollMs         = 250

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;

public static class DeadlockKeys {
    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)]
    struct InputUnion { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)]
    struct INPUT { public uint type; public InputUnion u; }

    const uint INPUT_KEYBOARD = 1, KEYEVENTF_KEYUP = 0x2, KEYEVENTF_SCANCODE = 0x8;

    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    public static uint ForegroundProcessId() {
        uint id;
        GetWindowThreadProcessId(GetForegroundWindow(), out id);
        return id;
    }

    static INPUT Key(ushort scan, bool up) {
        INPUT i = new INPUT();
        i.type = INPUT_KEYBOARD;
        i.u.ki.wScan = scan;
        i.u.ki.dwFlags = KEYEVENTF_SCANCODE | (up ? KEYEVENTF_KEYUP : 0);
        return i;
    }

    public static bool Tap(ushort scan) {
        int size = Marshal.SizeOf(typeof(INPUT));
        bool down = SendInput(1, new[] { Key(scan, false) }, size) == 1;
        Thread.Sleep(60);
        bool up = SendInput(1, new[] { Key(scan, true) }, size) == 1;
        return down && up;
    }
}
'@

function Write-Status([string]$Message) {
    Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message)
}

function Get-Game { Get-Process -Name deadlock -ErrorAction SilentlyContinue | Select-Object -First 1 }

# Steam keeps a list of library folders; the one holding appmanifest_<AppId>.acf has Deadlock.
function Find-GameInSteam {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { return $null }
    $libraries = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (-not (Test-Path -LiteralPath $libraries)) { return $null }

    foreach ($match in [regex]::Matches((Get-Content -LiteralPath $libraries -Raw), '"path"\s+"([^"]+)"')) {
        $library  = $match.Groups[1].Value -replace '\\\\', '\'
        $manifest = Join-Path $library "steamapps\appmanifest_$AppId.acf"
        if (-not (Test-Path -LiteralPath $manifest)) { continue }
        $installDir = [regex]::Match((Get-Content -LiteralPath $manifest -Raw), '"installdir"\s+"([^"]+)"').Groups[1].Value
        if ($installDir) { return Join-Path $library "steamapps\common\$installDir" }
    }
    return $null
}

# <GamePath>\game\bin\win64\deadlock.exe -> <GamePath>
function Get-GamePathFromProcess($Game) {
    try { $exe = $Game.Path } catch { return $null }
    if (-not $exe) { return $null }
    return Split-Path (Split-Path (Split-Path (Split-Path $exe)))
}

function Test-F9Bind([string]$Root) {
    $autoexec = Join-Path $Root 'game\citadel\cfg\autoexec.cfg'
    if (-not (Test-Path -LiteralPath $autoexec)) {
        Write-Status "No autoexec.cfg found at $autoexec. F9 only works if you bound it yourself."
    }
    elseif (-not (Select-String -LiteralPath $autoexec -Pattern '^\s*bind\s+"?F9"?\s+"sv_cheats 1; ?restart"' -Quiet)) {
        Write-Status "autoexec.cfg has no F9 bind for 'sv_cheats 1; restart'. F9 only works if you bound it yourself."
    }
}

function Send-Fix($Game) {
    if ($DryRun) { Write-Status 'Hang detected -> [dry run] would press F9'; return $true }

    $deadline = (Get-Date).AddSeconds($FocusWaitSec)
    while ([DeadlockKeys]::ForegroundProcessId() -ne $Game.Id) {
        if ($Game.HasExited -or (Get-Date) -gt $deadline) {
            Write-Status 'Hang detected, but Deadlock was not the active window. Will retry on the next attempt.'
            return $false
        }
        Start-Sleep -Milliseconds $PollMs
    }
    Start-Sleep -Milliseconds 1000
    if ([DeadlockKeys]::Tap($F9ScanCode)) { Write-Status 'Hang detected -> pressed F9 (sv_cheats 1; restart)' }
    else { Write-Status 'Hang detected, but sending F9 failed.' }
    return $true
}

# Lines start with "MM/dd HH:mm:ss". Lines without a timestamp count as fresh.
function Test-Fresh([string]$Line) {
    if ($Line -notmatch '^(\d\d)/(\d\d) (\d\d):(\d\d):(\d\d) ') { return $true }
    $now = Get-Date
    try { $time = Get-Date -Year $now.Year -Month $Matches[1] -Day $Matches[2] -Hour $Matches[3] -Minute $Matches[4] -Second $Matches[5] }
    catch { return $true }
    if ($time -gt $now.AddDays(1)) { $time = $time.AddYears(-1) }   # December log read in January
    return ($now - $time).TotalSeconds -le $StaleSec
}

$Host.UI.RawUI.WindowTitle = 'Deadlock loading fix'

if (-not $LogPath) {
    if (-not $GamePath) { $GamePath = Find-GameInSteam }
    if ($GamePath) {
        Write-Status "Deadlock folder: $GamePath"
        Test-F9Bind $GamePath
    }
}

$game = $null
if (-not $DryRun) {
    if (-not ($game = Get-Game)) {
        if ($NoLaunch) { Write-Status 'Waiting for Deadlock to start...' }
        else {
            Write-Status 'Starting Deadlock through Steam...'
            Start-Process "steam://rungameid/$AppId"
        }
        while (-not ($game = Get-Game)) { Start-Sleep -Milliseconds 500 }
    }
    Write-Status "Deadlock is running (PID $($game.Id))."

    if (-not $LogPath -and -not $GamePath) {
        $GamePath = Get-GamePathFromProcess $game
        if ($GamePath) { Write-Status "Deadlock folder: $GamePath"; Test-F9Bind $GamePath }
    }
}

if (-not $LogPath) {
    if (-not $GamePath) { throw 'Could not find the Deadlock folder. Run the script with -GamePath "<path to Deadlock>".' }
    $LogPath = Join-Path $GamePath 'game\citadel\console.log'
}

# Every game session replaces console.log with a new file, so the file is reopened on each
# poll and its first line identifies the session. Old lines are read but never trigger F9.
$session   = $null
$position  = 0
$pending   = ''
$armed     = $false                 # a 127.0.0.1 connection attempt is in progress
$lastFix   = [datetime]::MinValue
$buffer    = New-Object byte[] 65536
$started   = Get-Date
$sawFresh  = $false                 # any line from the current session seen yet
$hinted    = $false

Write-Status "Watching $LogPath"
while ($DryRun -or -not $game.HasExited) {
    $text = ''
    try {
        $stream = [System.IO.File]::Open($LogPath, 'Open', 'Read', 'ReadWrite, Delete')
        try {
            $headLength = $stream.Read($buffer, 0, 512)
            $newline = [Array]::IndexOf($buffer, [byte]10, 0, $headLength)
            if ($newline -ge 0) {
                $head = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $newline)
                if ($head -ne $session -or $stream.Length -lt $position) {
                    $session = $head; $position = 0; $pending = ''; $armed = $false
                }
                if ($stream.Length -gt $position) {
                    $stream.Position = $position
                    $sb = New-Object System.Text.StringBuilder
                    while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $read))
                    }
                    $position = $stream.Position
                    $text = $sb.ToString()
                }
            }
        }
        finally { $stream.Dispose() }
    }
    catch [System.IO.IOException], [System.UnauthorizedAccessException] {
        # Not created yet, or being replaced by a new session.
    }

    if ($text) {
        $lines   = ($pending + $text) -split "`r?`n"
        $pending = $lines[-1]               # last piece may be an unfinished line

        foreach ($line in ($lines | Select-Object -SkipLast 1)) {
            if (-not $sawFresh -and (Test-Fresh $line)) { $sawFresh = $true }

            if ($line -match "creating client connection to '127\.0\.0\.1'") {
                $armed = $true
            }
            elseif ($armed -and $line -match 'WSASendTo 127\.0\.0\.1:\d+ failed') {
                $armed = $false
                if (-not (Test-Fresh $line)) { continue }
                if (((Get-Date) - $lastFix).TotalSeconds -lt $CooldownSec) {
                    Write-Status 'Hang detected again right after a fix; waiting for the next attempt.'
                }
                elseif (Send-Fix $game) { $lastFix = Get-Date }
            }
            elseif ($line -match '\[Client\] Map: "(.+)"' -and $Matches[1] -ne '<empty>') {
                $map = $Matches[1]
                if (Test-Fresh $line) { Write-Status "Loaded map $map." }
            }
        }
    }

    if (-not $DryRun -and -not $sawFresh -and -not $hinted -and ((Get-Date) - $started).TotalSeconds -gt $NoLogWarnSec) {
        Write-Status 'No new console log yet. Is -condebug set in Deadlock''s Steam launch options?'
        $hinted = $true
    }
    Start-Sleep -Milliseconds $PollMs
}
Write-Status 'Deadlock closed. Exiting.'
