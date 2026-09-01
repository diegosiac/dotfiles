# Gentleman.Dots vendor snapshots

Gentleman.Dots is the reviewed upstream baseline for selected configurations:

- Repository: `https://github.com/Gentleman-Programming/Gentleman.Dots`

Snapshots are not updated during bootstrap or `chezmoi apply`.

## Update flow

1. Run the relevant sync script.
2. Review the upstream commit, adapter inputs, and `git diff`.
3. Run the focused contract test and validate the config in a VM.
4. Commit only after the snapshot is validated.

## Neovim

- Source path: `GentlemanNvim/nvim`
- Destination path: `dot_config/nvim`
- Sync script: `vendor/gentleman-dots/sync-nvim.sh`
- Adapter: `nvim-omarchy.patch`, guarded by exact upstream preimages and the installed Omarchy contract snapshot.

### Verification

Run all six focused checks before accepting an update:

```bash
bash tests/vendor-nvim-omarchy.sh
bash tests/vendor-nvim-omarchy-sync.sh
bash tests/nvim-nodejs.sh
bash tests/nvim-gemini.sh
bash tests/nvim-lazy-lock.sh
bash tests/nvim-materialization.sh
```

The sync clones upstream into staging, verifies every adapted preimage and Omarchy integration hash, applies the adapter with `git apply --check`, runs the contract test, and only then atomically replaces the reviewed snapshot. Any drift fails closed and leaves both the destination and metadata unchanged.

Omarchy owns dynamic Neovim themes and remote clipboard behavior through Chezmoi-managed symlinks to package/runtime contracts. Omarchy refreshes or reinstalls may replace the live Neovim config; this Chezmoi source remains the recovery truth. Lazy installs dependencies on normal Neovim startup, so validate updates in a VM without using the sync workflow to install plugins.
