#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/Gentleman-Programming/Gentleman.Dots.git"
SOURCE_FILE="GentlemanTmux/tmux.conf"
DEST_FILE="dot_tmux.conf"
WORK_DIR="${TMPDIR:-/tmp}/gentleman-dots-tmux"

repo_root="$(git rev-parse --show-toplevel)"

rm -rf "$WORK_DIR"
git clone --depth 1 "$REPO_URL" "$WORK_DIR"

upstream_commit="$(git -C "$WORK_DIR" rev-parse HEAD)"

cp "$WORK_DIR/$SOURCE_FILE" "$repo_root/$DEST_FILE"

cat > "$repo_root/vendor/gentleman-dots/tmux.snapshot" <<EOF
repo=$REPO_URL
source_path=$SOURCE_FILE
destination_path=$DEST_FILE
commit=$upstream_commit
synced_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "Vendored Tmux snapshot from $REPO_URL"
echo "Commit: $upstream_commit"
echo "Destination: $DEST_FILE"
echo
echo "Review with: git diff -- $DEST_FILE vendor/gentleman-dots/tmux.snapshot"
