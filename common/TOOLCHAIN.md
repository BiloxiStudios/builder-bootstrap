# Toolchain manifest (StudioBrain builders)

Pin **latest stable** unless a workflow explicitly pins older (owner rule). Re-run bootstrap to refresh.

## Required on every builder

| Component | Notes |
|-----------|--------|
| Git | system `safe.directory *` on Windows (NETWORK SERVICE) |
| Rust stable | Windows: `x86_64-pc-windows-msvc` under service-readable `C:\cargo` or Dev Drive. Linux: `/usr/local/cargo` + **`RUSTUP_HOME=/usr/local/rustup` in `/etc/environment` AND the runner `.env`** — rustc is a rustup proxy; without RUSTUP_HOME it re-downloads into `$HOME/.rustup` and `command -v rustc` looks MISSING on pct exec PATH. **Always `rustup update stable` on provision** — runners that only bootstrap when rustup is *absent* sat on 1.85.1 while crates needed 1.88 (cloud PRs #901/#902: set `RUSTUP_TOOLCHAIN=stable` in CI too; directory overrides can beat `rustup default`). Symlink rustc/cargo into `/usr/bin` so GH services with PATH=`/usr/bin:/bin` still see them. |
| Node 20 LTS | desktop workflows; wrangler ≥4 needs Node **22+**. Bake both `/usr/local/node20` and `/usr/local/node22` (`node20`/`node22` on PATH). |
| Node 22 | Required for wrangler (cloud #1103). Official tarball → `/usr/local/node22`; symlink `/usr/bin/node22`. |
| CMake | Tauri / native |
| **protoc** | `arduino/setup-protoc` needs `unzip` on Linux; prefer preinstalling both. Pin a version (`29.3`); do **not** query the unauth GH API (60/hr shared NAT). Symlink `/usr/bin/protoc`. |
| **unzip** (Linux) | Missing = deterministic protoc fail (SBAI-7403 night) |
| **xz-utils** (Linux) | Required to extract official Node tarballs (`tar -xJf`) |
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
