#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
lock_file="${1:-$repo_root/dot_config/nvim/lazy-lock.json}"
lazy_config="${2:-$repo_root/dot_config/nvim/lua/config/lazy.lua}"

python3 - "$lock_file" "$lazy_config" <<'PY'
from hashlib import sha256
from pathlib import Path
import json
import sys

lock_path, config_path = map(Path, sys.argv[1:])
expected_sha256 = "76d7d8aa72adeda6fce549690cdd98a757a9f578a697c4e5401a8e3d9ec5f836"
biome_import = "lazyvim.plugins.extras.lang.typescript.biome"
first_biome_commit = "242f0983de9fdb70f0d82057a8039e32bc171764"
expected_entries = {
    "LazyVim": {"branch": "main", "commit": first_biome_commit},
    "blink-copilot": {"branch": "main", "commit": "7ad8209b2f880a2840c94cdcd80ab4dc511d4f39"},
    "claudecode.nvim": {"branch": "main", "commit": "2390c6e45c4789072c293ac69de051d169668b29"},
    "mason-nvim-dap.nvim": {"branch": "main", "commit": "9a10e096703966335bd5c46c8c875d5b0690dade"},
    "mini.nvim": {"branch": "main", "commit": "a311ed247d527db9592bb434356badc705363746"},
    "nvim-nio": {"branch": "master", "commit": "edcc181a875301dd21840189aa2f2f9ad69fc172"},
    "snacks.nvim": {"branch": "main", "commit": "b0f21fa745953ac6bb096a4811cb32e42d7ca714"},
    "veil.nvim": {"branch": "main", "commit": "c838a0e17540764ec644a6ecf9b7d8b78966b263"},
}
removed_entries = {"blink-cmp-copilot", "claude-code.nvim", "nvim-dap-go"}

lock_bytes = lock_path.read_bytes()
if sha256(lock_bytes).hexdigest() != expected_sha256:
    raise SystemExit("FAIL: Neovim lock SHA-256 differs from the proven clean-data payload")

locks = json.loads(lock_bytes)
if not isinstance(locks, dict) or len(locks) != 86:
    raise SystemExit("FAIL: Neovim lock must contain exactly 86 entries")
if list(locks) != sorted(locks):
    raise SystemExit("FAIL: Neovim lock keys are not deterministically ordered")

for name, expected in expected_entries.items():
    if locks.get(name) != expected:
        raise SystemExit(f"FAIL: Neovim lock entry differs from the proven payload: {name}")
for name in removed_entries:
    if name in locks:
        raise SystemExit(f"FAIL: stale Neovim lock entry remains: {name}")

canonical_lines = ["{"]
for index, name in enumerate(sorted(locks)):
    entry = locks[name]
    if set(entry) != {"branch", "commit"}:
        raise SystemExit(f"FAIL: Neovim lock entry has an unexpected shape: {name}")
    comma = "," if index < len(locks) - 1 else ""
    canonical_lines.append(
        f'  {json.dumps(name)}: {{ "branch": {json.dumps(entry["branch"])}, '
        f'"commit": {json.dumps(entry["commit"])} }}{comma}'
    )
canonical = "\n".join([*canonical_lines, "}", ""])
if lock_bytes.decode("utf-8") != canonical:
    raise SystemExit("FAIL: Neovim lock formatting is not canonical")

config = config_path.read_text(encoding="utf-8")
import_contract = f'{{ import = "{biome_import}" }}'
if config.count(import_contract) != 1:
    raise SystemExit("FAIL: configured TypeScript Biome import is missing or duplicated")
if locks["LazyVim"]["commit"] != first_biome_commit:
    raise SystemExit("FAIL: LazyVim is not pinned to the verified first TypeScript Biome commit")

print("PASS: Neovim lock contains 86 canonical clean-data entries")
print("PASS: LazyVim is pinned to the verified first TypeScript Biome commit")
PY
