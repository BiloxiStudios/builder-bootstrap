# Runner inventory (BiloxiStudios org)

**Scope:** GitHub org `BiloxiStudios` (enterprise `grae` has 0 self-hosted runners).
**Updated:** 2026-08-22 by Boss (SBAI-7498). Re-list: `scripts/list-runners.sh`

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
| 36 | bx-w11-build02 | online idle | **build-desktop-windows** + rust-msvc + **build-mm-win** | HYDRA 10.15.1.117 — preferred desktop; 24G/8c, C: 256G / **159G free** (VHDX 256G on HYDRA) |
| 37 | bl-w11-build01 | online idle | **build-desktop-windows** + rust-msvc + **build-mm-win** | 10.15.1.137 standby; 16G/8c, C: 256G / **165G free** (VHDX 256G on BRANDON-LAP) |
| 42 | CC-W11-BUILD01 | online idle | **build-desktop-windows** + rust-msvc | Cloudcroft |
| 41 | DOMOVOI | online idle | **build-test-windows** | Physical 10.15.1.129, 8GB — not desktop |
| 39 | WIN-G10JLRFN20E | **online** (restarted 2026-08-18; interactive task) | **build-e2e** | Host 10.15.0.78; interactive scheduled task (not a Windows service) |
| 43 | proxmox-linux-7 | online | **build-desktop-linux** | pve2 CT164 |
| 44 | proxmox-linux-8 | online | **build-desktop-linux** | pve2 CT163 |
| 32 | actions-linux-5 | online | **build-e2e-linux** | pve3(vm3) CT158 (guest `free`/`swapon --show`/`/proc/swaps` re-verified 2026-08-22: Swap=**16G active**, 1.8M used; 16G zvol `vm-ssd/swap-ct158` is host backing) |
| 33 | actions-linux-6 | online | **build-e2e-linux** | pve3(vm3) CT159 (32G RAM; guest `free`/`swapon --show`/`/proc/swaps` re-verified 2026-08-22: Swap=**16G active**, 1.8M used; 16G zvol `vm-ssd/swap-ct159` is host backing) |
| 29 | proxmox-linux-1 | online | **build-cf-worker** | pve1 CT145 (hostname still actions-linux-1) |
| 22 | proxmox-linux-2 | online | **build-cf-worker** | pve1 CT146 |
| 23 | proxmox-linux-3 | online | **build-cf-worker** | pve1 CT147 |
| 24 | proxmox-linux-4 | online | **build-cf-worker** | pve1 CT148 (android label) |
| 28 | proxmox-macos-2 | online idle | **build-macos** | pve macOS |
| 34 | cc-linux-1 | **online** (disk-full crashloop 2026-08-18; pruned + restarted; 899M free — still tight) | **build-cf-worker** | Cloudcroft ESXi esx1 `10.44.0.106` |
| 45 | mm-linux-1 | **online** | **build-mm** + avx2 + Linux,X64 | pve3 CT166 `10.15.1.130` 16c/32G/16Gswap/200G 197G free — MM Linux cargo |

**Workload separation proof (SBAI-7498, 2026-08-22):** `build-desktop-linux` (GH 43/44) lives on
**pve2/vm2** CT163/CT164; `build-e2e-linux` (GH 32/33) lives on **pve3/vm3** CT158/CT159 — different
Proxmox nodes entirely, confirmed via `pvesh get /cluster/resources --type vm`. Before/after org
roster diff (`scripts/list-runners.sh`, 2026-08-22 01:17Z → 01:2xZ) shows zero identity churn from
the CT154/CT157 rename below — neither stale CT was ever in the org roster.

## Hostname collisions / stale — RESOLVED 2026-08-22 (SBAI-7498)

Proxmox container **name** field was literally duplicated between vm1 and vm3 (`pvesh` showed two
CTs each named `actions-linux-5` / `actions-linux-6`), not just an OS-level hostname string. Renamed
the vm1 (pve1) copies to their true identity; the vm3 (pve3) copies are the real, active, org-listed
GH runners (GH id 32/33) and were **not** touched.

| CT | Old name (pre-fix) | New name | Reality |
|----|---------------------|----------|---------|
| vm1 CT154 | actions-linux-5 | **brainmon-proxmox-2** | Live repo-scoped runner (agentId 22, `BizaNator/BrainMon`) — active `Runner.Listener` process, untouched by rename, verified same PID before/after |
| vm1 CT157 | actions-linux-6 | **retired-ct157** | Fully stale: former repo-scoped runner `proxmox-linux-6` (`BiloxiStudios/studiobrain-cloud`) migrated away; no `.runner` file, no systemd unit, no process. Renamed only — container not destroyed pending owner confirmation to reclaim/delete |
| vm3 CT158 | actions-linux-5 | *(unchanged)* | Real GH id 32, org roster, `build-e2e-linux` |
| vm3 CT159 | actions-linux-6 | *(unchanged)* | Real GH id 33, org roster, `build-e2e-linux` |
| pve2 CT165 | actions-linux-mm1 | *(unchanged)* | **repo-scoped** `studiobrain-model-manager` (not org list) — out of scope for this pass |

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
