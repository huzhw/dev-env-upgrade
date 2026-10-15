# ============================================================
# check-versions.ps1 - dev-env-upgrade one-shot env checker
# Pure ASCII (PS 5.1 safe). Chinese labels come from
# versions-config.json (UTF-8) read at runtime.
#
# Usage:
#   powershell -File check-versions.ps1              # full check
#   powershell -File check-versions.ps1 -Only Jdk,Maven
#   powershell -File check-versions.ps1 -Repo        # single line: maven local repo
#   powershell -File check-versions.ps1 -Json
#   powershell -File check-versions.ps1 -Offline     # local only, no network
#   powershell -File check-versions.ps1 -Size        # also compute repo size (slow!)
#
# Network: this machine's shell egress goes through the local
# policy proxy at http://127.0.0.1:2816 (allowlist). IWR ignores
# env-var proxies -> always pass -Proxy explicitly. Every query is
# wrapped: a single failure prints UNKNOWN and never aborts.
# ============================================================
[CmdletBinding()]
param(
  # NOTE: keep this a plain string - `powershell -File x.ps1 -Only A,B`
  # passes "A,B" as ONE token (PS 5.1 does not split on commas for -File).
  [string]$Only = 'All',
  [switch]$Repo,      # print effective maven localRepository only (old mvninfo)
  [switch]$Json,
  [switch]$Size,      # compute repo size (slow, 20GB)
  [switch]$Offline,   # skip network queries
  [int]$TimeoutSec = 15
)
# normalize/validate -Only
# IMPORTANT: do NOT assign the split array back into $Only - the param is
# typed [string], so a string[] would be re-joined with spaces ("A B C").
[string[]]$OnlyList = @($Only -split '[,;\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$valid = @('All','Jdk','Maven','Ide','Node','Python','Go','Rust','Cli')
foreach ($o in $OnlyList) {
  if ($valid -notcontains $o) { Write-Error ("Invalid -Only value '{0}'. Valid: {1}" -f $o, ($valid -join ',')); exit 2 }
}

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Script:Proxy   = 'http://127.0.0.1:2816'
$Script:CfgPath = Join-Path $PSScriptRoot 'versions-config.json'
$Script:Cfg     = $null
if (Test-Path $Script:CfgPath) {
  try { $Script:Cfg = [IO.File]::ReadAllText($Script:CfgPath, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { $Script:Cfg = $null }
}
function Lab([string]$k, [string]$fb) {
  if ($Script:Cfg -and $Script:Cfg.labels -and $Script:Cfg.labels.$k) { return [string]$Script:Cfg.labels.$k }
  return $fb
}

# ---------- helpers ----------
function Get-RegMachineEnv([string]$name) {
  try {
    $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment')
    if ($k) { $v = $k.GetValue($name, $null); if ($v) { return [string]$v } }
  } catch {}
  return $null
}
function Get-RegUserEnv([string]$name) {
  try {
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    if ($k) { $v = $k.GetValue($name, $null); if ($v) { return [string]$v } }
  } catch {}
  return $null
}

function Invoke-HttpText {
  param([string]$Url, [switch]$Json)
  try {
    $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec -Proxy $Script:Proxy -Headers @{ 'User-Agent' = 'dev-env-upgrade' } -ErrorAction Stop
    return [string]$r.Content
  } catch { return $null }
}
function Invoke-GhLatest {
  param([string]$Repo)   # owner/name
  try {
    $out = & gh api "repos/$Repo/releases/latest" --jq '.tag_name' 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) { return ([string]($out | Select-Object -First 1)).Trim() }
  } catch {}
  return $null
}

function Test-GtVer([string]$a, [string]$b) {
  # numeric compare of dotted versions; returns true if a > b
  if (-not $a -or -not $b) { return $false }
  if ($a -eq $b) { return $false }
  $pa = $a -split '\.'; $pb = $b -split '\.'
  for ($i = 0; $i -lt [Math]::Max($pa.Count, $pb.Count); $i++) {
    $x = 0; $y = 0
    if ($i -lt $pa.Count) { [void][int]::TryParse($pa[$i], [ref]$x) }
    if ($i -lt $pb.Count) { [void][int]::TryParse($pb[$i], [ref]$y) }
    if ($x -gt $y) { return $true }
    if ($x -lt $y) { return $false }
  }
  return $false
}
function Get-NormalVer([string]$v) {
  # strip common prefixes: v, go, node-
  if (-not $v) { return $null }
  return ($v -replace '^(v|go|node-)+', '')
}
function Get-JdkNum([string]$ver) {
  # normalize JDK versions to a comparable dotted string:
  #   1.8.0_451 -> 8.0.451 ; 8u451 -> 8.0.451 ; 17.0.20 -> 17.0.20
  #   jdk8u504-b01 (tag) -> 8.0.504 ; jdk-17.0.20.1+1 -> 17.0.20.1
  if (-not $ver) { return $null }
  $v = $ver.Trim()
  $m = [regex]::Match($v, '^1\.(\d+)\.0_(\d+)'); if ($m.Success) { return ('{0}.0.{1}' -f $m.Groups[1].Value, $m.Groups[2].Value) }
  $m = [regex]::Match($v, '^(?i)jdk-?(\d+)u(\d+)'); if ($m.Success) { return ('{0}.0.{1}' -f $m.Groups[1].Value, $m.Groups[2].Value) }
  $m = [regex]::Match($v, '^(?i)jdk-?(\d+(?:\.\d+)*)'); if ($m.Success) { return $m.Groups[1].Value }
  return (Get-NormalVer $v)
}
function Get-Major([string]$ver) {
  if (-not $ver) { return 0 }
  $m = [regex]::Match($ver, '^\d+')
  if ($m.Success) { return [int]$m.Value }
  return 0
}

# results collector: list of PSCustomObject
$Script:Rows = New-Object System.Collections.ArrayList
function Add-Row([string]$Comp, $Local, $Latest, [string]$Note, [string]$Status) {
  [void]$Script:Rows.Add([pscustomobject]@{
    component = $Comp; local = $Local; latest = $Latest; status = $Status; note = $Note
  })
}

function Get-StatusLocal([string]$c, $local, $latest, [string]$note) {
  if (-not $latest) { Add-Row $c $local $null $note (Lab 'unknown' 'UNKNOWN') }
  elseif (-not $local) { Add-Row $c (Lab 'notFound' 'NOT FOUND') $latest $note (Lab 'unknown' 'UNKNOWN') }
  else {
    $st = if (Test-GtVer (Get-NormalVer $latest) (Get-NormalVer $local)) { Lab 'upgradable' 'UPGRADABLE' } else { Lab 'upToDate' 'UP-TO-DATE' }
    Add-Row $c $local $latest $note $st
  }
}
function Get-StatusJdk($local, $latest, [string]$note) {
  # JDK tags (jdk8u504-b01) vs local (1.8.0_451) need JDK-specific normalization
  if (-not $latest) { Add-Row 'JDK' $local $null $note (Lab 'unknown' 'UNKNOWN') }
  elseif (-not $local) { Add-Row 'JDK' (Lab 'notFound' 'NOT FOUND') $latest $note (Lab 'unknown' 'UNKNOWN') }
  else {
    $st = if (Test-GtVer (Get-JdkNum $latest) (Get-JdkNum $local)) { Lab 'upgradable' 'UPGRADABLE' } else { Lab 'upToDate' 'UP-TO-DATE' }
    Add-Row 'JDK' $local $latest $note $st
  }
}

# ---------- Repo mode (old mvninfo use case) ----------
if ($Repo) {
  # priority: user-level %USERPROFILE%\.m2\settings.xml > %MAVEN_HOME%\conf\settings.xml
  $m2   = Join-Path $env:USERPROFILE '.m2\settings.xml'
  $mh   = Get-RegMachineEnv 'MAVEN_HOME'
  $conf = if ($mh) { Join-Path $mh 'conf\settings.xml' } else { $null }
  $picked = $null; $src = $null
  foreach ($pair in @(@($m2, 'user .m2'), @($conf, 'maven conf'))) {
    if ($pair[0] -and (Test-Path $pair[0])) {
      $t = [IO.File]::ReadAllText($pair[0])
      $m = [regex]::Match($t, '<localRepository>([^<]+)</localRepository>')
      if ($m.Success) { $picked = $m.Groups[1].Value.Trim(); $src = $pair[1]; break }
    }
  }
  if (-not $picked) { $picked = Join-Path $env:USERPROFILE '.m2\repository'; $src = 'default (no localRepository declared)' }
  # -Repo -Json: structured output for scripts (must return BEFORE the text
  # output below, since this branch returns early and never reaches the
  # -Json collector at the bottom of the file).
  if ($Json) {
    $obj = [ordered]@{
      repo   = $picked
      source = $src
      conf   = $conf
      exists = (Test-Path $picked)
    }
    if ($Size -and (Test-Path $picked)) {
      $n = 0L; $b = 0L
      foreach ($f in [IO.Directory]::EnumerateFiles($picked, '*', [IO.SearchOption]::AllDirectories)) {
        $n++; try { $b += ([IO.FileInfo]$f).Length } catch {}
      }
      $obj['bytes'] = $b; $obj['files'] = $n
    }
    Write-Output ($obj | ConvertTo-Json -Depth 2)
    return
  }
  Write-Output ("repo   = {0}" -f $picked)
  Write-Output ("source = {0}" -f $src)
  if ($conf) { Write-Output ("conf   = {0}" -f $conf) }
  if (-not (Test-Path $picked)) { Write-Output ("warn   = repo path does not exist yet") }
  if ($Size -and (Test-Path $picked)) {
    $files = 0L; $bytes = 0L
    foreach ($f in [IO.Directory]::EnumerateFiles($picked, '*', [IO.SearchOption]::AllDirectories)) {
      $files++; try { $bytes += ([IO.FileInfo]$f).Length } catch {}
    }
    Write-Output ("size   = {0} bytes / {1} files" -f $bytes, $files)
  }
  return
}

# ---------- local probes ----------
$want = { param($n) ($OnlyList -contains 'All') -or ($OnlyList -contains $n) }

# JDK
if (& $want 'Jdk') {
  $jh = $env:JAVA_HOME; if (-not $jh) { $jh = Get-RegMachineEnv 'JAVA_HOME' }
  $lv = $null; $bt = ''
  if ($jh -and (Test-Path (Join-Path $jh 'release'))) {
    $t = [IO.File]::ReadAllText((Join-Path $jh 'release'))
    $m = [regex]::Match($t, 'JAVA_VERSION="([^"]+)"');  if ($m.Success) { $lv = $m.Groups[1].Value }
    $m = [regex]::Match($t, 'BUILD_TYPE="([^"]+)"');    if ($m.Success) { $bt = $m.Groups[1].Value }
    $m = [regex]::Match($t, 'IMPLEMENTOR="([^"]+)"');   if ($m.Success -and $m.Groups[1].Value) { $bt = ($bt + ' ' + $m.Groups[1].Value).Trim() }
  }
  $maj = 8
  if ($lv -match '^1\.(\d+)') { $maj = [int]$Matches[1] }
  elseif ($lv -match '^(\d+)') { $maj = [int]$Matches[1] }
  $latest = $null; $note = ''
  if (-not $Offline) {
    $latest = Invoke-GhLatest ("adoptium/temurin{0}-binaries" -f $maj)
    if (-not $latest) { $note = Lab 'queryFailedHint' 'fallback: web_fetch api.adoptium.net' }
  }
  Get-StatusJdk $lv $latest $note
  if ($bt) { $Script:Rows | Where-Object { $_.component -eq 'JDK' } | Select-Object -Last 1 | ForEach-Object { $_.note = (($_.note, $bt) | Where-Object { $_ }) -join ' | ' } }
}

# Maven
if (& $want 'Maven') {
  $mh = $env:MAVEN_HOME; if (-not $mh) { $mh = Get-RegMachineEnv 'MAVEN_HOME' }
  $lv = $null
  if ($mh -and (Test-Path (Join-Path $mh 'bin\mvn.cmd'))) {
    $o = & (Join-Path $mh 'bin\mvn.cmd') '-version' 2>$null | Select-Object -First 3
    foreach ($line in $o) { $m = [regex]::Match($line, 'Apache Maven ([0-9][^\s]+)'); if ($m.Success) { $lv = $m.Groups[1].Value; break } }
  }
  $latest = $null; $note = ''
  if (-not $Offline) {
    $t = Invoke-HttpText 'https://mirrors.cloud.tencent.com/nexus/repository/maven-public/org/apache/maven/apache-maven/maven-metadata.xml'
    if ($t) {
      $vs = [regex]::Matches($t, '<version>([^<]+)</version>') | ForEach-Object { $_.Groups[1].Value } |
        Where-Object { $_ -match '^\d+\.\d+\.\d+$' }
      $best = $null
      foreach ($v in $vs) { if (-not $best -or (Test-GtVer $v $best)) { $best = $v } }
      $latest = $best
      if ($latest) { $note = 'JDK8 usable line = 3.x latest' }
    }
    if (-not $latest) { $note = Lab 'queryFailedHint' 'fallback: web_fetch dlcdn.apache.org' }
  }
  Get-StatusLocal 'Maven' $lv $latest $note
}

# IDE (IntelliJ IDEA)
if (& $want 'Ide') {
  $lv = $null; $bn = $null; $dir = $null
  foreach ($root in @('F:\JetBrains', 'C:\Program Files\JetBrains')) {
    if (-not (Test-Path $root)) { continue }
    foreach ($d in (Get-ChildItem $root -Directory -ErrorAction SilentlyContinue)) {
      $pi = Join-Path $d.FullName 'product-info.json'
      if (Test-Path $pi) {
        try {
          $j = [IO.File]::ReadAllText($pi) | ConvertFrom-Json
          if ($j.productCode -eq 'IU' -or $j.name -match 'IntelliJ IDEA') {
            $lv = [string]$j.version; $bn = [string]$j.buildNumber; $dir = $d.FullName
          }
        } catch {}
      }
    }
  }
  $latest = $null; $note = 'version from product-info.json (dir name is stale!)'
  if (-not $Offline) { $note = $note + ' | latest: data.services.jetbrains.com blocked -> use web_fetch' }
  Get-StatusLocal 'IDEA' $(if ($lv -and $bn) { "$lv ($bn)" } else { $lv }) $latest $note
}

# Node
if (& $want 'Node') {
  # NOTE: bare `node` may resolve to the DSH bundled runtime
  # (%APPDATA%\dsh-tauri\runtime\node.exe) which is NOT the dev toolchain.
  # Authoritative local version = the nvm symlink target's node.exe.
  $nvmHome = $env:NVM_HOME; if (-not $nvmHome) { $nvmHome = Get-RegUserEnv 'NVM_HOME' }
  $sym = $null; $symLink = $null
  if ($nvmHome) {
    try { $symLink = Get-RegUserEnv 'NVM_SYMLINK' } catch {}
    if (-not $symLink) { $symLink = 'F:\nodejs' }
    if (Test-Path $symLink) {
      $item = Get-Item $symLink -Force -ErrorAction SilentlyContinue
      if ($item -and $item.LinkType) { $sym = Split-Path $item.Target -Leaf }
    }
  }
  $lv = $null; $lvSrc = ''
  $symNode = if ($symLink) { Join-Path $symLink 'node.exe' } else { $null }
  if ($symNode -and (Test-Path $symNode)) {
    try {
      $o = [string]((& $symNode -v 2>$null | Select-Object -First 1))
      $m = [regex]::Match($o, 'v?(\d+\.\d+\.\d+)'); if ($m.Success) { $lv = $m.Groups[1].Value; $lvSrc = 'nvm symlink' }
    } catch {}
  }
  if (-not $lv) {
    try { $lv = ((& node -v 2>$null | Select-Object -First 1)) } catch {}
    if ($lv) { $lv = ([string]$lv).Trim(); $lvSrc = 'PATH (may be DSH runtime!)' }
  }
  if ($lv) { $lv = ([string]$lv).Trim() }
  $latest = $null; $note = ''
  if (-not $Offline) {
    $t = Invoke-HttpText 'https://registry.npmmirror.com/-/binary/node/index.json'
    if ($t) {
      try {
        $arr = $t | ConvertFrom-Json
        $latestCur = $null; $latestLts = $null
        foreach ($e in $arr) {
          $v = ([string]$e.version) -replace '^v', ''
          if (-not $latestCur -or (Test-GtVer $v $latestCur)) { $latestCur = $v }
          if ($e.lts -and $e.lts -ne $false) { if (-not $latestLts -or (Test-GtVer $v $latestLts)) { $latestLts = $v } }
        }
        $latest = $latestLts
        $note = "LTS=$latestLts current=$latestCur"
      } catch {}
    }
    if (-not $latest) { $note = Lab 'queryFailedHint' 'fallback: web_fetch nodejs.org/dist/index.json' }
  }
  if ($sym) { $note = ($note, "nvm active=$sym") -join ' | ' }
  if ($lvSrc) { $note = ($note, "local from $lvSrc") -join ' | ' }
  Get-StatusLocal 'Node' $lv $latest $note
}

# Python
if (& $want 'Python') {
  $lv = $null
  try { $o = (& pyenv version 2>$null | Select-Object -First 1); $m = [regex]::Match([string]$o, '(\d+\.\d+\.\d+)'); if ($m.Success) { $lv = $m.Groups[1].Value } } catch {}
  $latest = $null; $note = ''
  if (-not $Offline) {
    $t = Invoke-HttpText 'https://mirrors.aliyun.com/python-release/windows/'
    if ($t) {
      $best = $null
      foreach ($mm in [regex]::Matches($t, 'python-(\d+\.\d+\.\d+)-amd64\.exe')) {
        $v = $mm.Groups[1].Value
        if (-not $best -or (Test-GtVer $v $best)) { $best = $v }
      }
      $latest = $best
    }
    if (-not $latest) { $note = Lab 'queryFailedHint' 'fallback: web_fetch python.org' }
  }
  Get-StatusLocal 'Python' $lv $latest $note
}

# Go
if (& $want 'Go') {
  $lv = $null
  try { $o = [string]((& go version 2>$null | Select-Object -First 1)); $m = [regex]::Match($o, 'go(\d+\.\d+(\.\d+)?)'); if ($m.Success) { $lv = $m.Groups[1].Value } } catch {}
  $latest = $null; $note = ''
  if (-not $Offline) {
    # aliyun ?mode=json now returns an HTML page; parse the directory
    # listing for go<ver>.windows-amd64 artifacts instead
    $t = Invoke-HttpText 'https://mirrors.aliyun.com/golang/'
    if ($t) {
      foreach ($mm in [regex]::Matches($t, 'go(\d+\.\d+(?:\.\d+)?)[\.-]windows-amd64')) {
        $v = $mm.Groups[1].Value
        if (-not $latest -or (Test-GtVer $v $latest)) { $latest = $v }
      }
    }
    if (-not $latest) { $note = Lab 'queryFailedHint' 'goproxy.cn / golang.google.cn blocked' }
  }
  Get-StatusLocal 'Go' $lv $latest $note
}

# Rust
if (& $want 'Rust') {
  $lv = $null
  try { $o = [string]((& rustc --version 2>$null | Select-Object -First 1)); $m = [regex]::Match($o, 'rustc (\d+\.\d+\.\d+)'); if ($m.Success) { $lv = $m.Groups[1].Value } } catch {}
  $latest = $null; $note = ''
  if (-not $Offline) {
    $latest = Invoke-GhLatest 'rust-lang/rust'
    if (-not $latest) { $note = Lab 'queryFailedHint' 'static.rust-lang.org / tuna blocked' }
  }
  Get-StatusLocal 'Rust' $lv $(if ($latest) { Get-NormalVer $latest } else { $latest }) $note
}

# CLI tools
if (& $want 'Cli') {
  $cliDefs = @(
    @{ n = 'jq';    a = @('--version'); rx = 'jq-?(\d+\.\d+(\.\d+)?)' },
    @{ n = 'tokei'; a = @('--version'); rx = 'tokei (\d+\.\d+\.\d+)' },
    @{ n = 'xh';    a = @('--version'); rx = 'xh (\d+\.\d+\.\d+)' },
    @{ n = 'gh';    a = @('--version'); rx = 'gh version (\d+\.\d+\.\d+)' },
    @{ n = 'git';   a = @('--version'); rx = 'git version (\d+\.\d+\.\d+[^ ]*)' }
  )
  foreach ($d in $cliDefs) {
    $cmd = Get-Command $d.n -ErrorAction SilentlyContinue
    $lv = $null
    if ($cmd) {
      try {
        $o = [string]((& $d.n @($d.a) 2>$null | Select-Object -First 1))
        $m = [regex]::Match($o, $d.rx); if ($m.Success) { $lv = $m.Groups[1].Value }
      } catch {}
    }
    $latest = $null; $note = ''
    if (-not $Offline) {
      if ($Script:Cfg -and $Script:Cfg.repos -and $Script:Cfg.repos.($d.n)) {
        $r = $Script:Cfg.repos.($d.n)
        $latest = Invoke-GhLatest ("{0}/{1}" -f $r.owner, $r.name)
        $latest = Get-NormalVer $latest
      }
      if (-not $latest) { $note = Lab 'queryFailedHint' 'gh api failed' }
    }
    Get-StatusLocal ("CLI " + $d.n) $lv $latest $note
  }
  # officecli: no github releases source, local only
  $oc = Get-Command officecli -ErrorAction SilentlyContinue
  $olv = $null
  if ($oc) { try { $m = [regex]::Match([string]((& officecli --version 2>$null | Select-Object -First 1)), '(\d+\.\d+\.\d+)'); if ($m.Success) { $olv = $m.Groups[1].Value } } catch {} }
  Add-Row 'CLI officecli' $olv $null 'no upstream source registered' (Lab 'unknown' 'UNKNOWN')
}

# ---------- output ----------
if ($Json) {
  $Script:Rows | ConvertTo-Json -Depth 3
  return
}

Write-Output (Lab 'title' '=== dev-env-upgrade env check ===')
Write-Output ("{0,-16} {1,-24} {2,-24} {3,-12} {4}" -f (Lab 'component' 'COMPONENT'), (Lab 'local' 'LOCAL'), (Lab 'latest' 'LATEST'), (Lab 'status' 'STATUS'), (Lab 'note' 'NOTE'))
foreach ($r in $Script:Rows) {
  Write-Output ("{0,-16} {1,-24} {2,-24} {3,-12} {4}" -f $r.component, $r.local, $r.latest, $r.status, $r.note)
}
