# Runner inventory (BiloxiStudios org)

**Scope:** GitHub org `BiloxiStudios` (enterprise `grae` has 0 self-hosted runners).
**Updated:** 2026-08-18 by bx-infra. Re-list: `scripts/list-runners.sh`

Exclusive labels added 2026-08-18 (old labels kept so existing `runs-on` still match):

| Exclusive label | `runs-on` pin | Purpose |
|-----------------|---------------|---------|
| `build-desktop-windows` | `[self-hosted, Windows, build-desktop-windows]` | Tauri/NSIS Windows |
| `build-desktop-linux` | `[self-hosted, linux, build-desktop-linux]` | Tauri linux-cpu (RAM+swap) |
| `build-cf-worker` | `[self-hosted, linux, build-cf-worker]` | rustc/wasm wrangler, no desktop LTO |
| `build-e2e` | `[self-hosted, Windows, build-e2e]` | GUI/Playwright Windows |
| `build-e2e-linux` | `[self-hosted, linux, build-e2e-linux]` | docker/browsers linux |
| `build-macos` | `[self-hosted, macOS, build-macos]` | macOS desktop |
| `build-test-windows` | `[self-hosted, Windows, build-test-windows]` | light/test (DOMOVOI 8GB) |

## Live org runners

| GH id | Name | Status | Exclusive | Host / notes |
|------:|------|--------|-----------|--------------|
| 36 | bx-w11-build02 | online idle | **build-desktop-windows** + rust-msvc + **build-mm-win** | HYDRA 10.15.1.117 — preferred desktop; 24G/8c, C: 17G free (below MM 35G floor) |
| 37 | bl-w11-build01 | online idle | **build-desktop-windows** + rust-msvc + **build-mm-win** | 10.15.1.137 standby; 16G/8c, C: 22G free (below MM 35G floor) |
| 42 | CC-W11-BUILD01 | online idle | **build-desktop-windows** + rust-msvc | Cloudcroft |
| 41 | DOMOVOI | online idle | **build-test-windows** | Physical 10.15.1.129, 8GB — not desktop |
| 39 | WIN-G10JLRFN20E | **online** (restarted 2026-08-18; interactive task) | **build-e2e** | Host 10.15.0.78; interactive scheduled task (not a Windows service) |
| 43 | proxmox-linux-7 | online | **build-desktop-linux** | pve2 CT164 |
| 44 | proxmox-linux-8 | online | **build-desktop-linux** | pve2 CT163 |
| 32 | actions-linux-5 | online | **build-e2e-linux** | pve3 CT158 (guest `free` Swap=**16G** via `pct swap:16384` live; 16G zvol `vm-ssd/swap-ct158` is host backing) |
| 33 | actions-linux-6 | online | **build-e2e-linux** | pve3 CT159 (32G RAM; guest `free` Swap=**16G** via `pct swap:16384` live; 16G zvol `vm-ssd/swap-ct159` is host backing) |
| 29 | proxmox-linux-1 | online | **build-cf-worker** | pve1 CT145 (hostname still actions-linux-1) |
| 22 | proxmox-linux-2 | online | **build-cf-worker** | pve1 CT146 |
| 23 | proxmox-linux-3 | online | **build-cf-worker** | pve1 CT147 |
| 24 | proxmox-linux-4 | online | **build-cf-worker** | pve1 CT148 (android label) |
| 28 | proxmox-macos-2 | online idle | **build-macos** | pve macOS |
| 34 | cc-linux-1 | **online** (disk-full crashloop 2026-08-18; pruned + restarted; 899M free — still tight) | **build-cf-worker** | Cloudcroft ESXi esx1 `10.44.0.106` |
| 45 | mm-linux-1 | **online** | **build-mm** + avx2 + Linux,X64 | pve3 CT166 `10.15.1.130` 16c/32G/16Gswap/200G 197G free — MM Linux cargo |

## Hostname collisions / stale (do not register)

| CT | Hostname | Reality |
|----|----------|---------|
| pve1 CT154 | actions-linux-5 | stale `.runner` file (`brainmon-proxmox-2`); **not** GH id 32 |
| pve1 CT157 | actions-linux-6 | **no** GH runner service |
| pve2 CT165 | actions-linux-mm1 | **repo-scoped** `studiobrain-model-manager` (not org list) |

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/list-runners.sh` | dump org runners (needs admin PAT in `GH_TOKEN` or `GH_ADMIN_PAT`) |
| `scripts/apply-dedicated-labels.py` | idempotent POST of exclusive labels |
| `linux/provision.sh` | toolchain (incl. rustup update + unzip + node20/22 + rustc wrappers) |
| `scripts/remediate-linux-toolchain.sh` | guest remediator: PATH/`RUSTUP_HOME` wrappers, `/usr/bin` links, runner `.env` |
| `scripts/push-remediate.sh` | BRAINZ → pve1/2/3 `pct push` + exec remediator |
| `scripts/verify-linux-runner.sh` | in-guest gate (exports RUSTUP_HOME; swap must be ACTIVE) |
| `scripts/audit-linux-runners.sh` | host-side fleet audit |
| `windows/provision-windows-builder.ps1` | Windows toolchain |

## Prerequisites per class

See `common/TOOLCHAIN.md` + `DEDICATED-RUNNERS.md`. Desktop-linux: **32G RAM + real swap**. CF-worker: rustc ≥1.88, `RUSTUP_TOOLCHAIN=stable`. Never mix `build-desktop-linux` and `build-e2e-linux` on one CT.
