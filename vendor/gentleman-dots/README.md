# Gentleman.Dots vendor snapshots

Selected configurations in this dotfiles repository are vendored from:

- Repository: `https://github.com/Gentleman-Programming/Gentleman.Dots`

They are copied as reviewed snapshots, not auto-updated during bootstrap or `chezmoi apply`.

## Update flow

1. Run the relevant sync script.
2. Review `git diff`.
3. Test the updated config in the VM.
4. Commit only after the snapshot is validated.

## Herdr

- Source path: `herdr/config.toml`
- Destination path: `dot_config/herdr/config.toml`
- Sync script: `vendor/gentleman-dots/sync-herdr.sh`
- Binary install: `herdr` from the AUR list in `packages/arch/aur.txt`
- Agent integrations: not vendored. Install per agent with `herdr integration install <agent>`.

Upstream copies this file into place and runs `chmod u+w` because Home Manager
would otherwise link it read-only from the Nix store. Chezmoi already writes a
regular writable file, so no equivalent step is needed here.

## Neovim

- Source path: `GentlemanNvim/nvim`
- Destination path: `dot_config/nvim`
- Sync script: `vendor/gentleman-dots/sync-nvim.sh`
- Plugin/dependency install: handled by Neovim/Lazy on first launch; validate in the VM before committing updates.
