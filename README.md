# builder-bootstrap

Self-deployable toolchain + GitHub Actions runner setup for **StudioBrain / BiloxiStudios** builders.

One script per OS. Idempotent. Safe to re-run. Designed for:

- Fresh boxes (HYDRA Hyper-V, Proxmox LXC/VM, physical Dell like DOMOVOI, Cloudcroft Hyper-V, macOS build VMs)
- SimpleHelp / grae.support “run script” one-liners
- Agent re-provision (`bx-infra` / `windows-build-deploy` skill)

## Quick start (SimpleHelp / SSH one-liners)

### Windows (elevated PowerShell)

```powershell
irm https://raw.githubusercontent.com/BiloxiStudios/builder-bootstrap/main/bootstrap.ps1 | iex
# or with options:
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/BiloxiStudios/builder-bootstrap/main/bootstrap.ps1))) -SkipCuda -Site bx
```

### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/BiloxiStudios/builder-bootstrap/main/bootstrap.sh | sudo bash -s -- --site bx
```

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/BiloxiStudios/builder-bootstrap/main/bootstrap.sh | bash -s -- --site bx --os mac
```

After toolchain install, register the runner (needs a short-lived org registration token — mint from VW `GitHub PAT — BizaNator PRIMARY`, never store the PAT on the box):

```powershell
# Windows
.\windows\register-runner.ps1 -Site bx -Pat $env:GH_PAT -Labels "self-hosted,Windows,X64,windows-11,bx,rust-msvc"
```

```bash
# Linux / macOS — see linux/register-runner.sh
sudo ./linux/register-runner.sh --site bx --name "$(hostname)" --labels "self-hosted,linux,proxmox"
```

## What gets installed

See [`common/TOOLCHAIN.md`](common/TOOLCHAIN.md). Summary:

| Tool | Windows | Linux | macOS |
|------|---------|-------|-------|
| Git | yes | yes | yes |
| Rust (stable) | msvc | gnu | darwin |
| Node 20 LTS | yes | yes | yes |
| CMake | yes | yes | yes |
| protoc | yes (official zip) | yes | yes |
| unzip | n/a (Expand-Archive) | **required** | yes |
| gh CLI | yes | yes | yes |
| VS Build Tools / Xcode CLT | VS2022 | build-essential | xcode-select |
| CUDA | optional (`-SkipCuda`) | optional | n/a |
| OpenSSH server | yes | yes | yes (Remote Login) |
| Defender / Dev Drive hardening | yes | n/a | n/a |
| SimpleHelp agent | optional URL | optional | optional |

## Verify

```powershell
.\windows\verify-builder.ps1
```

```bash
./linux/verify-builder.sh
./macos/verify-builder.sh
```

A builder is **not** ready for production jobs until verify exits 0 (includes a scratch `cargo build` on Windows).

## Layout

```
bootstrap.ps1 / bootstrap.sh     # OS detect + fetch/run platform provision
windows/                         # provision + verify + register (existing skill scripts)
linux/
macos/
common/TOOLCHAIN.md              # version pins / rationale
```

## Ownership

- Infra seat: `bx-infra` (Biloxi runners, DOMOVOI, HYDRA)
- Desktop builds: `sb-desktop`
- Do **not** commit PATs or MAK keys. Pass at runtime from Vaultwarden.

## Canonical locations

| Copy | Path |
|------|------|
| **NAS Studio Skills (owner-canonical)** | `B:\Brains\Skills\BuilderBootstrap\` → `/mnt/tank/Studio/Brains/Skills/BuilderBootstrap/` |
| GitHub (SimpleHelp `curl`/`irm`) | https://github.com/BiloxiStudios/builder-bootstrap |
| Index | `B:\Brains\_Skills\SKILLS_INDEX.md` |

Keep NAS and GitHub in sync when editing.

## Related

- Skill: `WindowsBuildDeploy` (Windows deep runbook)
- Topology: `studio-infra-topology` §2.4b runner fleet table
- Ticket: SBAI-7406
