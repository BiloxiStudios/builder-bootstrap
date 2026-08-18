<#
  register-runner.ps1 — register this box as a BiloxiStudios ORG GitHub Actions runner.
  Mints an EPHEMERAL registration-token from the vaultwarden PRIMARY PAT; the raw PAT
  never lands on the box. Idempotent (removes a stale same-name registration first).
  Run elevated. See ../SKILL.md.

  Params:
    -Org         : GitHub org (default BiloxiStudios).
    -Site        : site code — cc (Cloudcroft) | bx (Biloxi). Used for the runner
                   name + an informational location label. Naming convention
                   (bizanator 2026-07-20): <site>-w11-build<NN>, hypervisor-agnostic
                   (e.g. cc-w11-build01, bx-w11-build01). The underlying hypervisor
                   (HyperV/ESXi/proxmox) is deliberately NOT in the name/labels.
    -RunnerName  : runner name (default = COMPUTERNAME — set it to the convention via
                   Rename-Computer during provision). Clone flow: pass a NEW name.
    -Labels      : runner labels. Default is HYPERVISOR-AGNOSTIC so a runner on ANY
                   site/hypervisor serves the windows build leg:
                   self-hosted,Windows,X64,windows-11,<site>. ⚠️ Do NOT hardcode
                   'proxmox' — the CC box is HyperV, not proxmox; the release
                   windows-x64 leg's selector should be [self-hosted,Windows,X64]
                   (location-agnostic), with <site> as an informational tag only.
    -RunnerRoot  : install dir (default E:\actions-runner — match the Dev Drive).
    -Pat         : the PRIMARY PAT. Prefer piping from vaultwarden at call time rather
                   than passing on the command line (avoids shell history). E.g.:
                   $pat = <vaultwarden get_item 'GitHub PAT — BizaNator PRIMARY'>
                   .\register-runner.ps1 -Site cc -Pat $pat
#>
[CmdletBinding()]
param(
  [ValidateSet('cc','bx')][string]$Site = 'bx',
  [string]$Org        = 'BiloxiStudios',
  [string]$RunnerName = $env:COMPUTERNAME,
  [string]$Labels     = '',
  [string]$RunnerRoot = 'E:\actions-runner',
  [Parameter(Mandatory)][string]$Pat
)
# Hypervisor-agnostic default labels + the site tag (informational, not routing).
if ([string]::IsNullOrEmpty($Labels)) { $Labels = "self-hosted,Windows,X64,windows-11,$Site" }
$ErrorActionPreference = 'Stop'
function Log($m){ Write-Host "[register] $m" -ForegroundColor Green }
$hdr = @{ Authorization = "token $Pat"; Accept = 'application/vnd.github+json' }

# --- CLONE HYGIENE: purge stale/foreign runner services from the source image -----
# A clone-from-snapshot inherits the SOURCE box's runner services — GitHub's default
# `actions.runner.<org>.<name>` AND any custom NSSM wrapper (e.g. `GitHubActionsRunner`),
# possibly for a DIFFERENT org (we've seen `actions-runner-<OldOrg>-*`). Left in place they
# spawn a SECOND listener → session conflict / duplicate jobs (SBAI-5440 via the clone).
# Remove every runner service that isn't THIS runner before we register a clean one.
Log "Clone hygiene: purging stale/foreign runner services..."
Get-Service -ErrorAction SilentlyContinue | Where-Object {
    ($_.Name -like 'actions.runner.*' -or $_.Name -like '*GitHubActionsRunner*' -or $_.Name -like 'actions-runner-*') `
    -and ($_.Name -notlike "*$RunnerName*")
} | ForEach-Object {
    Log "  removing stale service $($_.Name)"
    Stop-Service $_.Name -Force -ErrorAction SilentlyContinue
    & sc.exe delete $_.Name | Out-Null   # covers native + NSSM-wrapped services
}
# Drop a leftover runner registration file from the source image so config.cmd is clean.
foreach ($f in @("$RunnerRoot\.runner", "$RunnerRoot\.credentials", "$RunnerRoot\.credentials_rsaparams")) {
    if (Test-Path $f) { Log "  removing stale $f"; Remove-Item $f -Force -ErrorAction SilentlyContinue }
}

# --- mint an ephemeral registration-token (short-lived; PAT stays off the box) ----
Log "Minting ephemeral org registration-token for $Org..."
$reg = Invoke-RestMethod -Method Post -Headers $hdr "https://api.github.com/orgs/$Org/actions/runners/registration-token"
Log "Registration-token minted (expires $($reg.expires_at))."

# --- remove a stale same-name registration (clone / re-provision) -----------------
try {
  $existing = (Invoke-RestMethod -Headers $hdr "https://api.github.com/orgs/$Org/actions/runners?per_page=100").runners |
              Where-Object { $_.name -eq $RunnerName }
  if ($existing) {
    Log "Removing stale runner registration '$RunnerName' (id $($existing.id))..."
    Invoke-RestMethod -Method Delete -Headers $hdr "https://api.github.com/orgs/$Org/actions/runners/$($existing.id)" | Out-Null
  }
} catch { Log "Stale-check skipped: $($_.Exception.Message)" }

# --- download + configure the runner ----------------------------------------------
if (-not (Test-Path "$RunnerRoot\config.cmd")) {
  New-Item -ItemType Directory -Force -Path $RunnerRoot | Out-Null
  $rel = Invoke-RestMethod -Headers $hdr "https://api.github.com/repos/actions/runner/releases/latest"
  $asset = $rel.assets | Where-Object { $_.name -match 'win-x64.*\.zip$' } | Select-Object -First 1
  Log "Downloading runner $($rel.tag_name)..."
  Invoke-WebRequest $asset.browser_download_url -OutFile "$RunnerRoot\runner.zip"
  Expand-Archive "$RunnerRoot\runner.zip" -DestinationPath $RunnerRoot -Force
}
Push-Location $RunnerRoot
Log "Configuring runner '$RunnerName' [$Labels]..."
& .\config.cmd --unattended --replace --url "https://github.com/$Org" --token $reg.token `
    --name $RunnerName --labels $Labels --work '_work' --runasservice

# --- PATH gotcha: runner reads .path, NOT the user PATH ----------------------------
$toolPaths = @(
  "$env:USERPROFILE\.cargo\bin",
  "${env:ProgramFiles}\CMake\bin",
  "${env:ProgramFiles}\Git\cmd",
  "${env:ProgramFiles}\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin"
) | Where-Object { Test-Path $_ }
($env:Path.Split(';') + $toolPaths | Select-Object -Unique) -join ';' | Set-Content "$RunnerRoot\.path"
Log ".path written with toolchain dirs."

& .\svc.cmd start 2>&1 | Out-Null
Pop-Location
Log "Runner '$RunnerName' registered + service started. Verify with verify-builder.ps1."
