#Requires -Version 5.1
<#
.SYNOPSIS
    Audit or repair the PATH shims under %USERPROFILE%\.local\bin.

.DESCRIPTION
    The three command shims (mvninfo.cmd / envcheck.cmd / fsend.cmd) must be SYMLINKS that
    point at the copies living in the skill repos, so that editing the repo takes effect in
    PATH at once and the two sides can never drift apart.

    Hard links are not possible here: .local\bin sits on C: while the repos sit on F:, and
    "mklink /H" answers "the system cannot move the file to a different disk drive".

    Default mode is a read-only audit. With -Apply the script repairs what is wrong:
      missing shim          -> symlink created
      wrong symlink target  -> symlink recreated
      plain copy            -> renamed to <name>.bak-<timestamp>, then symlink created
    Nothing is ever deleted silently, and no shim is touched unless a probe symlink in the
    same directory succeeds first (mirrors the admin / Developer Mode requirement).

.PARAMETER Apply
    Create or repair the shims. Without it nothing is written.

.PARAMETER Only
    Restrict the run to one shim: mvninfo, envcheck or fsend.

.PARAMETER BinDir
    Directory holding the shims. Default: %USERPROFILE%\.local\bin

.PARAMETER RepoRoot
    Root of the skill repos. Default: F:\idea-workspase-skills

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File install-shims.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File install-shims.ps1 -Apply

.NOTES
    Creating a symlink needs administrator rights or Windows Developer Mode (Settings ->
    Privacy and security -> For developers -> Developer Mode).
    Exit code: 0 = every selected shim is a correct symlink, 1 = something is still wrong.
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [ValidateSet('', 'mvninfo', 'envcheck', 'fsend')]
    [string]$Only = '',
    [string]$BinDir = (Join-Path $env:USERPROFILE '.local\bin'),
    [string]$RepoRoot = 'F:\idea-workspase-skills'
)

$ErrorActionPreference = 'Stop'

# ---------- shim table ----------
$shims = @(
    [pscustomobject]@{ Name = 'mvninfo.cmd';  Target = (Join-Path $RepoRoot 'dev-env-upgrade\scripts\mvninfo.cmd') },
    [pscustomobject]@{ Name = 'envcheck.cmd'; Target = (Join-Path $RepoRoot 'dev-env-upgrade\scripts\envcheck.cmd') },
    [pscustomobject]@{ Name = 'fsend.cmd';    Target = (Join-Path $RepoRoot 'ssh-transfer\scripts\fsend.cmd') }
)

# ---------- helpers ----------

# Current state of one shim path: missing / link (with target) / file (plain copy).
function Get-ShimState {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ State = 'missing'; LinkTarget = $null }
    }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.LinkType -in @('SymbolicLink', 'Junction')) {
        $target = @($item.Target) | Select-Object -First 1
        return [pscustomobject]@{ State = 'link'; LinkTarget = $target }
    }
    return [pscustomobject]@{ State = 'file'; LinkTarget = $null }
}

# Probe whether this directory accepts a new symlink, so we fail before touching real files.
function Test-LinkAllowed {
    param([string]$Dir)

    $stamp = 'shim-probe-' + $PID
    $probeLink = Join-Path $Dir ($stamp + '.cmd')
    $probeTarget = Join-Path $Dir ($stamp + '.txt')
    $ok = $false
    $message = ''
    try {
        if (-not (Test-Path -LiteralPath $probeTarget)) {
            New-Item -ItemType File -Path $probeTarget -Force | Out-Null
        }
        New-Item -ItemType SymbolicLink -Path $probeLink -Target $probeTarget -ErrorAction Stop | Out-Null
        $ok = $true
    }
    catch {
        $message = $_.Exception.Message
    }
    finally {
        if (Test-Path -LiteralPath $probeLink) { Remove-Item -LiteralPath $probeLink -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $probeTarget) { Remove-Item -LiteralPath $probeTarget -Force -ErrorAction SilentlyContinue }
    }
    return [pscustomobject]@{ Ok = $ok; Message = $message }
}

# Create one symlink; returns $null on success or the error text.
function New-ShimLink {
    param([string]$Path, [string]$Target)

    try {
        New-Item -ItemType SymbolicLink -Path $Path -Target $Target -ErrorAction Stop | Out-Null
        return $null
    }
    catch {
        return $_.Exception.Message
    }
}

# ---------- main ----------

$selected = @($shims | Where-Object { $Only -eq '' -or $_.Name -eq ($Only + '.cmd') })
if ($selected.Count -eq 0) {
    Write-Host "[shim] no shim selected for -Only '$Only'"
    exit 1
}
if (-not (Test-Path -LiteralPath $BinDir)) {
    Write-Host "[shim] FAIL bin dir not found: $BinDir"
    exit 1
}

Write-Host "[shim] dir : $BinDir"
Write-Host "[shim] repo: $RepoRoot"
if (-not $Apply) { Write-Host '[shim] mode: audit only (pass -Apply to repair)' }
Write-Host ''

# step 1: report current state and collect the work list
$plan = @()
$needWrite = $false
foreach ($s in $selected) {
    $path = Join-Path $BinDir $s.Name
    $state = Get-ShimState -Path $path
    $note = ''
    $broken = $false

    if ($state.State -eq 'missing') {
        $note = 'missing'
        $broken = $true
    }
    elseif ($state.State -eq 'file') {
        $note = 'plain copy (not a symlink)'
        $broken = $true
    }
    else {
        if ($state.LinkTarget -and $state.LinkTarget -eq $s.Target) {
            $note = 'ok -> ' + $state.LinkTarget
        }
        else {
            $note = 'wrong target -> ' + $state.LinkTarget
            $broken = $true
        }
    }
    if ($broken) { $needWrite = $true }
    Write-Host ("  {0,-13} {1}" -f $s.Name, $note)
    $plan += [pscustomobject]@{ Shim = $s; Path = $path; State = $state.State; Broken = $broken }
}

if (-not $Apply) {
    if ($needWrite) {
        Write-Host ''
        Write-Host '[shim] result: at least one shim is not a correct symlink'
        Write-Host '[shim] audit only, nothing changed. Re-run with -Apply to repair.'
        exit 1
    }
    Write-Host ''
    Write-Host '[shim] result: all shims are correct symlinks'
    exit 0
}

if (-not $needWrite) {
    Write-Host ''
    Write-Host '[shim] result: nothing to repair'
    exit 0
}

# step 2: prove we may create symlinks before changing anything
$probe = Test-LinkAllowed -Dir $BinDir
if (-not $probe.Ok) {
    Write-Host ''
    Write-Host '[shim] FAIL cannot create symlinks in this directory, nothing was changed'
    Write-Host ("[shim] reason: " + $probe.Message)
    Write-Host '[shim] fix: run this script from an elevated shell, or turn on Developer Mode'
    exit 1
}

# step 3: repair
$repaired = 0
$failed = 0
foreach ($item in $plan) {
    if (-not $item.Broken) { continue }
    $name = $item.Shim.Name
    $target = $item.Shim.Target

    if (-not (Test-Path -LiteralPath $target)) {
        Write-Host ("  {0,-13} FAIL target missing: {1}" -f $name, $target)
        $failed++
        continue
    }

    $backupNote = ''
    if ($item.State -eq 'file') {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupPath = $item.Path + '.bak-' + $stamp
        try {
            Move-Item -LiteralPath $item.Path -Destination $backupPath -Force -ErrorAction Stop
            $backupNote = ', backup: ' + (Split-Path -Leaf $backupPath)
        }
        catch {
            Write-Host ("  {0,-13} FAIL cannot back up plain copy: {1}" -f $name, $_.Exception.Message)
            $failed++
            continue
        }
    }
    elseif ($item.State -eq 'link') {
        try {
            Remove-Item -LiteralPath $item.Path -Force -ErrorAction Stop
        }
        catch {
            Write-Host ("  {0,-13} FAIL cannot remove stale symlink: {1}" -f $name, $_.Exception.Message)
            $failed++
            continue
        }
    }

    $err = New-ShimLink -Path $item.Path -Target $target
    if ($err) {
        Write-Host ("  {0,-13} FAIL {1}" -f $name, $err)
        if ($backupNote) { Write-Host ("  {0,-13}      the old copy is at {1}" -f '', $backupNote.TrimStart(', ', ' ')) }
        $failed++
        continue
    }

    # step 4: verify the link really points where we asked
    $check = Get-ShimState -Path $item.Path
    if ($check.State -eq 'link' -and $check.LinkTarget -eq $target) {
        Write-Host ("  {0,-13} repaired (was {1}{2})" -f $name, $item.State, $backupNote)
        $repaired++
    }
    else {
        Write-Host ("  {0,-13} FAIL verification failed, got {1}" -f $name, $check.LinkTarget)
        $failed++
    }
}

Write-Host ''
Write-Host ("[shim] result: repaired {0}, failed {1}" -f $repaired, $failed)
if ($failed -gt 0) { exit 1 }
exit 0
