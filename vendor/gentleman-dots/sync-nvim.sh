#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/Gentleman-Programming/Gentleman.Dots.git"
SOURCE_SUBDIR="GentlemanNvim/nvim"
DEST_DIR="dot_config/nvim"
WORK_DIR="${TMPDIR:-/tmp}/gentleman-dots-nvim"

repo_root="$(git rev-parse --show-toplevel)"

rm -rf "$WORK_DIR"
git clone --depth 1 "$REPO_URL" "$WORK_DIR"

upstream_commit="$(git -C "$WORK_DIR" rev-parse HEAD)"

rm -rf "$repo_root/$DEST_DIR"
mkdir -p "$repo_root/$(dirname "$DEST_DIR")"
cp -a "$WORK_DIR/$SOURCE_SUBDIR" "$repo_root/$DEST_DIR"

cat > "$repo_root/vendor/gentleman-dots/nvim.snapshot" <<EOF
repo=$REPO_URL
source_path=$SOURCE_SUBDIR
destination_path=$DEST_DIR
commit=$upstream_commit
synced_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "Vendored Neovim snapshot from $REPO_URL"
echo "Commit: $upstream_commit"
echo "Destination: $DEST_DIR"
echo
echo "Review with: git diff -- $DEST_DIR vendor/gentleman-dots/nvim.snapshot"
