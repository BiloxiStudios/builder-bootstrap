#!/usr/bin/env python3
"""Idempotent: add exclusive build-* labels on BiloxiStudios org runners.
Does not remove existing labels (current workflows keep matching).
PAT: GH_ADMIN_PAT or GH_TOKEN (admin:org).
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

ORG = "BiloxiStudios"

# runner_id -> exclusive labels to ADD
PLAN: dict[int, list[str]] = {
    36: ["build-desktop-windows", "mm"],  # bx-w11-build02 — rust-msvc kept
    37: ["build-desktop-windows", "mm"],  # bl-w11-build01 — rust-msvc kept
    42: ["build-desktop-windows", "rust-msvc"],  # CC-W11-BUILD01
    41: ["build-test-windows"],  # DOMOVOI
    39: ["build-e2e"],  # WIN-G10JLRFN20E
    43: ["build-desktop-linux"],  # proxmox-linux-7
    44: ["build-desktop-linux"],  # proxmox-linux-8
    32: ["build-e2e-linux"],  # actions-linux-5
    33: ["build-e2e-linux"],  # actions-linux-6
    29: ["build-cf-worker"],  # proxmox-linux-1
    22: ["build-cf-worker"],  # proxmox-linux-2
    23: ["build-cf-worker"],  # proxmox-linux-3
    24: ["build-cf-worker"],  # proxmox-linux-4
    28: ["build-macos"],  # proxmox-macos-2
    34: ["build-cf-worker"],  # cc-linux-1
}


def main() -> int:
    token = os.environ.get("GH_ADMIN_PAT") or os.environ.get("GH_TOKEN")
    if not token:
        print("Set GH_ADMIN_PAT", file=sys.stderr)
        return 1
    rc = 0
    for rid, labs in PLAN.items():
        req = urllib.request.Request(
            f"https://api.github.com/orgs/{ORG}/actions/runners/{rid}/labels",
            data=json.dumps({"labels": labs}).encode(),
            headers={
                "Authorization": f"token {token}",
                "Accept": "application/vnd.github+json",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req) as resp:
                data = json.loads(resp.read().decode())
            names = [x["name"] for x in data.get("labels", [])]
            print(f"{rid} OK {names}")
        except urllib.error.HTTPError as e:
            print(f"{rid} ERR {e.code} {e.read().decode()[:200]}", file=sys.stderr)
            rc = 1
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
