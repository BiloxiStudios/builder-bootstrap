# Toolchain manifest (StudioBrain builders)

Pin **latest stable** unless a workflow explicitly pins older (owner rule). Re-run bootstrap to refresh.

## Required on every builder

| Component | Notes |
|-----------|--------|
| Git | system `safe.directory *` on Windows (NETWORK SERVICE) |
| Rust stable | Windows: `x86_64-pc-windows-msvc` under service-readable `C:\cargo` or Dev Drive. **Always `rustup update stable` on provision** — runners that only bootstrap when rustup is *absent* sat on 1.85.1 while crates needed 1.88 (cloud PRs #901/#902: set `RUSTUP_TOOLCHAIN=stable` in CI too; directory overrides can beat `rustup default`). |
| Node 20 LTS | desktop workflows; Create Release / wrangler may need Node **22+** on Windows release hosts |
| CMake | Tauri / native |
| **protoc** | `arduino/setup-protoc` needs `unzip` on Linux; prefer preinstalling both |
| **unzip** (Linux) | Missing = deterministic protoc fail (SBAI-7403 night) |
| gh CLI | `gh run download` in E2E |
| OpenSSH | agent operability |

## Windows-only

| Component | Notes |
|-----------|--------|
| VS2022 Build Tools + VCTools + Win11 SDK | MSVC link |
| Defender exclusions / Dev Drive | prevents cargo NUL corruption (VM150 class) |
| PowerShell 7 (`pwsh`) | workflow `shell: pwsh` |
| CUDA toolkit | optional; Gate-2 GPU fusion |
| NSIS | Tauri Windows installer (see ci-runner-setup.md WOW64 notes) |

## Labels (GitHub Actions)

- Windows: `self-hosted,Windows,X64,windows-11,<site>,rust-msvc` — **no `proxmox`** on Windows
- Linux desktop pool: `self-hosted,linux,proxmox`
- Linux actions pool: `self-hosted,linux` (+ site tags as needed)

`<site>` = `bx` | `bl` | `cc` | physical hostname tag.
