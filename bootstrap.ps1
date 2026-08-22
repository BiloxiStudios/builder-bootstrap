<#
  bootstrap.ps1 — entrypoint for Windows builders (SimpleHelp / irm | iex).
  Downloads this repo's windows/provision script and runs it elevated.

  Examples:
    irm https://raw.githubusercontent.com/BiloxiStudios/builder-bootstrap/main/bootstrap.ps1 | iex
    .\bootstrap.ps1 -SkipCuda -Site bx
#>
[CmdletBinding()]
param(
  [string]$Branch = 'main',
  [string]$Site = 'bx',
  [string]$SshPubKey = '',
  [string]$SimpleHelpMsi = '',
  [switch]$SkipCuda,
  [switch]$VerifyOnly,
  [switch]$SkipProvision
)
$ErrorActionPreference = 'Stop'
$Base = "https://raw.githubusercontent.com/BiloxiStudios/builder-bootstrap/$Branch"

function Get-Remote($rel, $dest) {
  New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
  Invoke-WebRequest -Uri "$Base/$rel" -OutFile $dest -UseBasicParsing
}

$work = Join-Path $env:TEMP ("builder-bootstrap-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
Write-Host "[bootstrap] workdir $work" -ForegroundColor Cyan

Get-Remote 'windows/provision-windows-builder.ps1' "$work\provision-windows-builder.ps1"
Get-Remote 'windows/verify-builder.ps1' "$work\verify-builder.ps1"
Get-Remote 'windows/register-runner.ps1' "$work\register-runner.ps1"

Push-Location $work
try {
  if (-not $SkipProvision -and -not $VerifyOnly) {
    $provArgs = @{}
    if ($SkipCuda) { $provArgs.SkipCuda = $true }
    if ($SshPubKey) { $provArgs.SshPubKey = $SshPubKey }
    if ($SimpleHelpMsi) { $provArgs.SimpleHelpMsi = $SimpleHelpMsi }
    # Low-RAM physical boxes (DOMOVOI ~8GB): prefer C:\cargo over Dev Drive create failures
    & "$work\provision-windows-builder.ps1" @provArgs
  }
  # NOTE: must be $(...) (subexpression), not bare (...) — after the & call operator,
  # PowerShell 5.1 parses arguments in "argument mode" where a bare (if ...) tries to
  # invoke `if` as a command name (CommandNotFoundException) instead of evaluating it
  # as an expression. Confirmed live on BL-W11-BUILD01 (SBAI-7502).
  & "$work\verify-builder.ps1" -RunnerRoot $(if (Test-Path 'E:\actions-runner') { 'E:\actions-runner' } else { 'C:\actions-runner' })
  Write-Host @"

[bootstrap] Toolchain verify finished.
Next: register runner (PAT never stored on disk):
  `$pat = <from Vaultwarden 'GitHub PAT — BizaNator PRIMARY'>
  .\register-runner.ps1 -Site $Site -Pat `$pat -Labels "self-hosted,Windows,X64,windows-11,$Site,rust-msvc"

"@ -ForegroundColor Green
} finally {
  Pop-Location
}
