<#
  provision-windows-builder.ps1  —  StudioBrain Windows build runner, toolchain + hardening.
  Run elevated on a fresh Win11 VM. Idempotent. See ../SKILL.md.

  Params:
    -DevDriveLetter  : letter for the Dev Drive that hosts .cargo + runner work dir (default E).
                       If a Dev Drive can't be created, falls back to Defender path exclusions.
    -BuildUser       : local build/runner account (default svc-build).
    -SshPubKey       : path to the operator SSH public key to authorize (optional).
    -SimpleHelpMsi   : path/URL to the grae.support SimpleHelp agent MSI (optional).
    -SkipCuda        : CPU-only box (no GPU); skips the CUDA toolkit.
    -MakKey          : Windows 11 Pro MAK key for activation. Prefer piping from vaultwarden
                       at call time (item "Windows 11 Pro MAK key (MS Partner — build VMs)")
                       rather than hardcoding — keeps the key out of the script/image.
#>
[CmdletBinding()]
param(
  [string]$DevDriveLetter = 'E',
  [string]$BuildUser      = 'svc-build',
  [string]$SshPubKey      = '',
  [string]$SimpleHelpMsi  = '',
  [string]$MakKey         = '',
  [switch]$SkipCuda
)
$ErrorActionPreference = 'Stop'
function Log($m){ Write-Host "[provision] $m" -ForegroundColor Cyan }

# --- 1. Dev Drive (preferred) or Defender exclusions (fallback) -------------------
$cargoHome  = "$($DevDriveLetter):\cargo"
$runnerRoot = "$($DevDriveLetter):\actions-runner"
$devDriveOk = $false
try {
  # A Dev Drive is ReFS + performance mode; Defender scans it in async/trusted mode,
  # which is what prevents the crate-extraction NUL corruption. Requires free space
  # on a VHDX or a spare volume. Adjust the source to your VM's disk layout.
  if (-not (Test-Path "$($DevDriveLetter):\")) {
    Log "Creating Dev Drive on $DevDriveLetter (ReFS, 100GB VHDX)..."
    $vhd = "C:\devdrive.vhdx"
    New-VHD -Path $vhd -SizeBytes 100GB -Dynamic | Out-Null
    Mount-VHD -Path $vhd
    $disk = Get-VHD $vhd | Get-Disk
    Initialize-Disk $disk.Number -PartitionStyle GPT
    $part = New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter $DevDriveLetter
    Format-Volume -DriveLetter $DevDriveLetter -DevDrive -Confirm:$false | Out-Null
  }
  fsutil devdrv query "$($DevDriveLetter):" | Out-Null
  $devDriveOk = $true
  Log "Dev Drive $DevDriveLetter ready."
} catch {
  Log "Dev Drive unavailable ($($_.Exception.Message)); using C: + Defender exclusions instead."
  $cargoHome  = 'C:\cargo'
  $runnerRoot = 'C:\actions-runner'
}
New-Item -ItemType Directory -Force -Path $cargoHome,$runnerRoot | Out-Null

# Defender exclusions are belt-and-suspenders even WITH a Dev Drive — the VM150
# corruption is the single worst failure mode; make it impossible.
Log "Applying Defender exclusions (paths + processes)..."
foreach ($p in @($cargoHome, $runnerRoot, "$env:LOCALAPPDATA\Temp")) { Add-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue }
foreach ($e in @('cargo.exe','rustc.exe','link.exe','git.exe','cl.exe')) { Add-MpPreference -ExclusionProcess $e -ErrorAction SilentlyContinue }
setx CARGO_HOME $cargoHome /M | Out-Null
$env:CARGO_HOME = $cargoHome

# --- 2. Toolchain -----------------------------------------------------------------
function Winget($id){
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Log "winget missing — skip $id (install App Installer / use MSI fallbacks for cmake+protoc+gh)"
    return
  }
  winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
}
Log "Installing VS2022 BuildTools (C++ workload)..."
Winget 'Microsoft.VisualStudio.2022.BuildTools'
# Ensure the C++ + Windows SDK components (winget installs the shell; add workload):
$vsInstaller = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
if (Test-Path $vsInstaller) {
  & $vsInstaller modify --quiet --norestart --installPath "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools" `
    --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.Windows11SDK.22621 --includeRecommended | Out-Null
}
Log "Installing Rust (rustup, msvc target), cmake, git, LLVM, PowerShell 7, Node 20, gh..."
Winget 'Rustlang.Rustup'; & "$env:USERPROFILE\.cargo\bin\rustup.exe" default stable-x86_64-pc-windows-msvc 2>&1 | Out-Null
Winget 'Kitware.CMake'; Winget 'Git.Git'; Winget 'LLVM.LLVM'
# PowerShell 7 (pwsh): required by the CI workflow's `shell: pwsh` steps AND by the
# Gate-2 harness (gate2-ai-proof.ps1). Old snapshot bases predate it → provision-once.
Winget 'Microsoft.PowerShell'
Winget 'OpenJS.NodeJS.LTS'
Winget 'GitHub.cli'
if (-not $SkipCuda) { Log "Installing CUDA toolkit..."; Winget 'Nvidia.CUDA' }

# Service-readable cargo home (NETWORK SERVICE cannot see Admin profile ~/.cargo)
if (-not (Test-Path 'C:\cargo')) {
  New-Item -ItemType Directory -Force -Path 'C:\cargo','C:\cargo\bin' | Out-Null
}
setx CARGO_HOME 'C:\cargo' /M | Out-Null
setx RUSTUP_HOME 'C:\cargo' /M | Out-Null
$env:CARGO_HOME = 'C:\cargo'; $env:RUSTUP_HOME = 'C:\cargo'
# Prefer machine cargo when present
if (Test-Path "$env:USERPROFILE\.cargo\bin\rustup.exe") {
  & "$env:USERPROFILE\.cargo\bin\rustup.exe" default stable-x86_64-pc-windows-msvc 2>&1 | Out-Null
}
git config --system --add safe.directory '*' 2>$null

# protoc: PROVISION-ONCE here (not per-build) so the CI workflow's install step no-ops
# on fleet runners. The winget package doesn't reliably land protoc.exe on PATH, so install
# the official release to a stable dir + persist it on the machine PATH — robust for clones.
Log "Installing protoc (official release → stable PATH)..."
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
if (-not (Get-Command protoc -ErrorAction SilentlyContinue)) {
  $protocDir = 'C:\tools\protoc'
  New-Item -ItemType Directory -Force -Path $protocDir | Out-Null
  $rel = Invoke-RestMethod -Headers @{ 'User-Agent' = 'sb-winbuild' } 'https://api.github.com/repos/protocolbuffers/protobuf/releases/latest'
  $asset = $rel.assets | Where-Object { $_.name -match 'protoc-.*-win64\.zip$' } | Select-Object -First 1
  Invoke-WebRequest $asset.browser_download_url -OutFile "$env:TEMP\protoc.zip"
  Expand-Archive "$env:TEMP\protoc.zip" -DestinationPath $protocDir -Force
  $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
  if ($machinePath -notlike "*$protocDir\bin*") {
    [Environment]::SetEnvironmentVariable('Path', "$machinePath;$protocDir\bin", 'Machine')
  }
  Log "  protoc installed to $protocDir\bin (on Machine PATH)"
} else { Log "  protoc already present" }

# --- 3. Remote access: OpenSSH + firewall + SMB results share ----------------------
Log "Enabling OpenSSH Server (key-based)..."
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue | Out-Null
Set-Service sshd -StartupType Automatic; Start-Service sshd
if ($SshPubKey -and (Test-Path $SshPubKey)) {
  $adminKeys = "$env:ProgramData\ssh\administrators_authorized_keys"
  Get-Content $SshPubKey | Set-Content $adminKeys
  icacls $adminKeys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null
}
Log "Firewall: SSH(22) inbound, SMB(445) LAN-only..."
New-NetFirewallRule -DisplayName 'SB-SSH'  -Direction Inbound -Protocol TCP -LocalPort 22  -Action Allow -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName 'SB-SMB'  -Direction Inbound -Protocol TCP -LocalPort 445 -RemoteAddress LocalSubnet -Action Allow -ErrorAction SilentlyContinue | Out-Null
$share = 'C:\sb-results'; New-Item -ItemType Directory -Force -Path $share | Out-Null
if (-not (Get-SmbShare -Name 'sb-results' -ErrorAction SilentlyContinue)) {
  New-SmbShare -Name 'sb-results' -Path $share -FullAccess "$env:COMPUTERNAME\$BuildUser","Administrators" | Out-Null
}
Log "Results share ready: \\$env:COMPUTERNAME\sb-results"

# --- 4. grae.support SimpleHelp remote-admin (vision-enabled desktop) --------------
if ($SimpleHelpMsi) {
  Log "Installing grae.support SimpleHelp agent..."
  if ($SimpleHelpMsi -match '^https?://') { $dst="$env:TEMP\simplehelp.msi"; Invoke-WebRequest $SimpleHelpMsi -OutFile $dst; $SimpleHelpMsi=$dst }
  Start-Process msiexec.exe -ArgumentList "/i `"$SimpleHelpMsi`" /qn" -Wait
}

# --- 5. Windows activation (MAK from vault; skip if the image is already licensed) ---
if ($MakKey) {
  Log "Activating Windows (MAK)..."
  cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /ipk $MakKey | Out-Null
  cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /ato | Out-Null
  $lic = (cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /dli) -join ' '
  $status = if ($lic -match 'Licensed') { 'Licensed' } else { 'NOT licensed — verify slmgr /dli' }
  Log "Activation status: $status"
}

Log "DONE. Next: register-runner.ps1 (mint ephemeral token from vaultwarden PRIMARY PAT)."
Log "Then verify-builder.ps1, then SNAPSHOT this VM as the golden image."
