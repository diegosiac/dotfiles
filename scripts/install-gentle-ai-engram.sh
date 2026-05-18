#!/usr/bin/env bash
set -euo pipefail

if ! command -v go >/dev/null 2>&1; then
    echo "go is required. Install packages/arch/base.txt first." >&2
    exit 1
fi

echo "Installing Gentle-AI..."
go install github.com/gentleman-programming/gentle-ai/cmd/gentle-ai@latest

echo "Installing Engram..."
go install github.com/Gentleman-Programming/engram/cmd/engram@latest

echo
echo "Installed binaries to: ${GOBIN:-$HOME/go/bin}"
echo "Restart your shell, then run:"
echo "  engram setup opencode"
echo "  engram setup pi"
echo "  gentle-ai"
