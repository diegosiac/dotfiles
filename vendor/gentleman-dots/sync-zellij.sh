#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/Gentleman-Programming/Gentleman.Dots.git"
SOURCE_SUBDIR="GentlemanZellij/zellij"
DEST_DIR="dot_config/zellij"
WORK_DIR="${TMPDIR:-/tmp}/gentleman-dots-zellij"

repo_root="$(git rev-parse --show-toplevel)"

rm -rf "$WORK_DIR"
git clone --depth 1 "$REPO_URL" "$WORK_DIR"

upstream_commit="$(git -C "$WORK_DIR" rev-parse HEAD)"

rm -rf "$repo_root/$DEST_DIR"
mkdir -p "$repo_root/$(dirname "$DEST_DIR")"
cp -a "$WORK_DIR/$SOURCE_SUBDIR" "$repo_root/$DEST_DIR"

cat > "$repo_root/vendor/gentleman-dots/zellij.snapshot" <<EOF
repo=$REPO_URL
source_path=$SOURCE_SUBDIR
destination_path=$DEST_DIR
commit=$upstream_commit
synced_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "Vendored Zellij snapshot from $REPO_URL"
echo "Commit: $upstream_commit"
echo "Destination: $DEST_DIR"
echo
echo "Review with: git diff -- $DEST_DIR vendor/gentleman-dots/zellij.snapshot"
