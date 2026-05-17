# Gentleman.Dots vendor snapshots

Selected configurations in this dotfiles repository are vendored from:

- Repository: `https://github.com/Gentleman-Programming/Gentleman.Dots`

They are copied as reviewed snapshots, not auto-updated during bootstrap or `chezmoi apply`.

## Update flow

1. Run the relevant sync script.
2. Review `git diff`.
3. Test the updated config in the VM.
4. Commit only after the snapshot is validated.

## Zellij

- Source path: `GentlemanZellij/zellij`
- Destination path: `dot_config/zellij`
- Sync script: `vendor/gentleman-dots/sync-zellij.sh`

## Tmux

- Source path: `GentlemanTmux/tmux.conf`
- Destination path: `dot_tmux.conf`
- Sync script: `vendor/gentleman-dots/sync-tmux.sh`
- Plugin install: `run_once_after_20-install-tmux-plugins.sh`
