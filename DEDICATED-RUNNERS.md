# Dedicated runners (owner 2026-08-18)

**Problem:** a shared `self-hosted,linux,proxmox` pool lets any job land on any CT. That caused
unzip-missing "flakes", rustc 1.85 vs 1.88, and a 3h38m link hang on `actions-linux-6` (pve3 CT159)
when RAM peaked at 32G with **no swap**. Backups pile up because workers steal each other's boxes.

**Rule:** one **proven machine per build type** (not one per repo). Workflows pin `runs-on` to an
exclusive label. Repos that share a *kind* of build share a runner; different kinds never share.

## Idle vs start-on-GitHub-request (Linux LXC)

Classic GitHub self-hosted runners **must already be connected** to pick up a job. GitHub does not
wake a stopped LXC.

| Mode | How | Latency | When to use |
|------|-----|---------|-------------|
| **Idle LXC (preferred)** | CT `onboot=1`, runner service listening | seconds | LXC idle is ~0 CPU; reserved RAM is the only cost |
| Start-on-request | webhook/workflow_job → `pct start` → wait for runner online | 30–90s + flake if start fails | only if RAM reservation on the *host* is the constraint |
| Ephemeral ARC (k8s) | job spins a pod | cold start | not the current fleet |

**Decision:** keep dedicated LXCs **running idle**. Do not invent a wake-on-job path unless pve RAM
is actually exhausted.

## Exclusive labels (additive first)

| Label | Job class | Proven host (2026-08-18) | Needs |
|-------|-----------|--------------------------|--------|
| `build-desktop-windows` | Tauri/NSIS Windows | **bx-w11-build02** (HYDRA) | rust-msvc, unzip n/a |
| `build-desktop-linux` | Tauri linux-cpu | **proxmox-linux-7/8** (pve2/vm2, CT164/CT163) | 32G+ RAM **and real swap**, rust, unzip, protoc |
| `build-cf-worker` | rustc/wasm wrangler deploys | dedicated LXC, rustc ≥1.88 (`RUSTUP_TOOLCHAIN=stable`) | not the desktop linker |
| `build-e2e` | Playwright / docker / GUI | **bx-w11-e2e01** on WIN-G10 (`10.15.0.78`) | isolation from cargo link |
| `build-e2e-linux` | docker/browsers linux | **actions-linux-5/6** (pve3/vm3, CT158/CT159) — 16G swap re-verified active 2026-08-22 | 32G+ RAM **and real swap** |
| `build-macos` | Tauri mac | existing macOS VMs / GH-hosted | GUI session caveats |
| `mm` | model-manager (keep `avx2` / `rust-msvc`) | **mm-linux-1** pve3 CT166; Win: bx/bl rust-msvc | Linux: 32G+swap+AVX2, not CT158/159. Win: rust-msvc, no `proxmox` |

**Do not** give `build-desktop-linux` and `build-e2e` to the same CT. Docker + LTO link on one 32G
box is how CT159 hung.

## WIN-G10JLRFN20E (`10.15.0.78`)

Windows Server 2022 + Hyper-V, 16 threads, ~64 GB RAM. Already hosts **`bx-w11-e2e01`** (8 vCPU / 16 GB).
Not empty — use leftover capacity for extra Windows/e2e VMs, **not** as a Linux LXC host.

## Per-repo vs per-build-type

Per-repo (1 LXC × every GitHub repo) wastes RAM and duplicates rust/node/protoc. Per-**build-type**
gives the reliability win (known-good image) without exploding the fleet.

## Workflow pin (example)

```yaml
# studiobrain-app desktop linux
runs-on: [self-hosted, linux, build-desktop-linux]
# cloud worker rust
runs-on: [self-hosted, linux, build-cf-worker]
```

Add the exclusive label to the proven runner **before** changing `runs-on`. Then drop the shared
`proxmox` label so random jobs stop landing there.

## Inventory + scripts

- **[RUNNERS.md](RUNNERS.md)** — live table (GH ids, exclusive labels, host map)
- `scripts/list-runners.sh` — dump org runners (`GH_ADMIN_PAT`)
- `scripts/apply-dedicated-labels.py` — re-apply exclusive labels (idempotent)

Labels were applied 2026-08-18 on the BiloxiStudios org (enterprise `grae` has 0 self-hosted). Existing labels were **kept** so current `runs-on` still work; pin workflows to exclusive labels next.

## Ticket

SBAI-7416 (dedicated runner fleet). SBAI-7498 (2026-08-22): resolved vm1/vm3 duplicate Proxmox CT
names (CT154/CT157 renamed off `actions-linux-5/6`), re-verified CT159 guest swap active, confirmed
`build-desktop-linux` (pve2) and `build-e2e-linux` (pve3) are on separate nodes. See RUNNERS.md.
