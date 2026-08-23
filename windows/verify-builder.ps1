<#
  verify-builder.ps1 — confirm a StudioBrain Windows builder is fully ready.
  Proves the no-NUL-corruption invariant with a real scratch cargo build.
  Run elevated. See ../SKILL.md. Exits non-zero on any failed check.
#>
[CmdletBinding()]
param([string]$RunnerRoot = 'E:\actions-runner')
$fail = 0
function Check($name, $ok, $detail=''){ if($ok){Write-Host "  [ OK ] $name $detail" -ForegroundColor Green}else{Write-Host "  [FAIL] $name $detail" -ForegroundColor Red; $script:fail++} }
Write-Host "== StudioBrain Windows builder verification ==" -ForegroundColor Cyan

# toolchain
Check 'rustc'  ((& rustc --version 2>$null) -ne $null) (& rustc --version 2>$null)
Check 'cargo'  ((& cargo --version 2>$null) -ne $null) (& cargo --version 2>$null)
# MSVC is NOT required on PATH: rustc/the `cc` crate auto-locate the VC toolset via
# vswhere/registry (find-msvc-tools) for every windows-msvc build, PATH or no PATH —
# this is why GH-hosted runners work with cl.exe absent from PATH too. Checking
# `Get-Command cl.exe` tests the wrong invariant and false-fails healthy boxes
# (verified 2026-08-23, SBAI-7725: bx-w11-build02, the passing production
# desktop-build box, also has no cl.exe on PATH). Check toolset *installation*
# here; the scratch build below proves it actually compiles C via the same
# autodetection path esaxx-rs/aws-lc-sys use in production.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsInstall = if (Test-Path $vswhere) { & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null } else { $null }
Check 'VC Tools MSVC toolset installed' (-not [string]::IsNullOrWhiteSpace($vsInstall)) $vsInstall
Check 'cmake'  ((Get-Command cmake -ErrorAction SilentlyContinue) -ne $null)
Check 'protoc' ((Get-Command protoc -ErrorAction SilentlyContinue) -ne $null)
Check 'git'    ((Get-Command git -ErrorAction SilentlyContinue) -ne $null)
# NETWORK SERVICE owns runner work under Administrators → need system safe.directory
$safe = (& git config --system --get-all safe.directory 2>$null)
Check 'git safe.directory *' ($safe -contains '*' -or ($safe -join ' ') -match '\*') ($safe -join ', ')

# GitHub CLI required for jobs that call `gh run download` (desktop E2E)
Check 'gh CLI' ((Get-Command gh -ErrorAction SilentlyContinue) -ne $null) ((& gh --version 2>$null | Select-Object -First 1) | Out-String).Trim()
# Optional authenticated probe when GH_TOKEN present (workflow provides it; local verify may skip)
if ($env:GH_TOKEN -or $env:GITHUB_TOKEN) {
  $tok = if ($env:GH_TOKEN) { $env:GH_TOKEN } else { $env:GITHUB_TOKEN }
  $env:GH_TOKEN = $tok
  $probe = & gh api user --jq .login 2>$null
  Check 'gh authenticated probe' (-not [string]::IsNullOrWhiteSpace($probe)) $probe
} else {
  Write-Host '  [SKIP] gh authenticated probe (no GH_TOKEN in env - job will inject)' -ForegroundColor DarkGray
}

Check 'nvcc (CUDA)' ((Get-Command nvcc -ErrorAction SilentlyContinue) -ne $null) '(skip if CPU-only box)'

# Defender exclusions active (the VM150 guard)
$excl = (Get-MpPreference).ExclusionProcess
Check 'Defender excludes cargo.exe' ($excl -contains 'cargo.exe')
Check 'Defender excludes link.exe'  ($excl -contains 'link.exe')

# runner .path populated + service online
Check '.path exists' (Test-Path "$RunnerRoot\.path")
$svc = Get-Service 'actions.runner.*' -ErrorAction SilentlyContinue
Check 'runner service running' ($svc -and $svc.Status -eq 'Running') ($svc.Name)

# SSH reachable locally
Check 'sshd running' ((Get-Service sshd -ErrorAction SilentlyContinue).Status -eq 'Running')


# Network + git checkout probe (WIN-G10 hung checkout@v5 — 2026-07-26)
Write-Host "  ... git clone network probe ..." -ForegroundColor DarkGray
$probeDir = Join-Path $env:TEMP ("gitprobe_" + [guid]::NewGuid().ToString('N').Substring(0,8))
try {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $null = & git -c http.version=HTTP/1.1 clone --depth 1 https://github.com/actions/checkout.git $probeDir 2>&1
  $sw.Stop()
  Check 'git clone network probe' (Test-Path (Join-Path $probeDir '.git')) ("ms=$($sw.ElapsedMilliseconds)")
} catch {
  Check 'git clone network probe' $false $_.Exception.Message
} finally {
  Remove-Item $probeDir -Recurse -Force -ErrorAction SilentlyContinue
}

# GUI-E2E: cargo + tauri-driver (WIN-G10 2026-07-26)
# Prefer service-readable C:\cargo home when present
if (Test-Path 'C:\cargo') {
  $env:CARGO_HOME = 'C:\cargo'
  $env:RUSTUP_HOME = 'C:\cargo'
  if ($env:Path -notlike '*C:\cargo\bin*') { $env:Path = "C:\cargo\bin;$env:Path" }
}
Check 'cargo --version' ((Get-Command cargo -ErrorAction SilentlyContinue) -ne $null) ((& cargo --version 2>$null) | Out-String).Trim()
$tdCmd = Get-Command tauri-driver -ErrorAction SilentlyContinue
$tdPath = if ($tdCmd) { $tdCmd.Source } elseif (Test-Path 'C:\cargo\bin\tauri-driver.exe') { 'C:\cargo\bin\tauri-driver.exe' } else { $null }
# tauri-driver has no --version; presence + --help is the gate
$tdHelp = if ($tdPath) { & $tdPath --help 2>&1 | Select-Object -First 1 } else { $null }
Check 'tauri-driver present' ($null -ne $tdPath -and "$tdHelp" -match 'tauri-driver|USAGE') $tdPath

# THE invariant: a real cargo build with no NUL corruption, PLUS a real MSVC cl.exe
# invocation through the `cc` crate's own autodetection (same path esaxx-rs /
# aws-lc-sys take in production desktop builds) — proves the toolset actually
# works end-to-end without depending on PATH placement.
Write-Host "  ... scratch cargo build incl. cc-crate C compile (proves no crate-extraction corruption + real MSVC compile) ..." -ForegroundColor DarkGray
$scratch = Join-Path $env:TEMP ("sbverify_" + [guid]::NewGuid().ToString('N'))
try {
  & cargo new $scratch --bin 2>&1 | Out-Null
  Set-Content -Path (Join-Path $scratch 'dummy.c') -Value 'int sb_verify_probe(void){return 42;}'
  Add-Content -Path (Join-Path $scratch 'Cargo.toml') -Value "`n[build-dependencies]`ncc = `"1`""
  Set-Content -Path (Join-Path $scratch 'build.rs') -Value 'fn main(){ cc::Build::new().file("dummy.c").compile("sb_verify_probe"); }'
  Push-Location $scratch
  $out = & cargo build 2>&1
  Pop-Location
  Check 'scratch cargo build (cc-crate MSVC compile)' ($LASTEXITCODE -eq 0) ($(if($LASTEXITCODE -ne 0){"`n$out"}))
} finally { Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ("== {0} ==" -f $(if($fail -eq 0){'ALL CHECKS PASSED - snapshot this VM as the golden image'}else{"$fail CHECK(S) FAILED"})) -ForegroundColor $(if($fail -eq 0){'Green'}else{'Red'})
exit $fail
