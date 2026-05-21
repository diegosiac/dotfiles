# Daily-driver productivity layer: first slice plan

Implement the first productivity slice as a small Hyprland-led workflow change: fixed activity workspaces, an Obsidian overlay scratchpad, a quick-note action, command-center exposure, and only low-risk Quickshell label alignment. Do not touch tmux or Zellij in this slice.

## Review path

1. Review `dot_config/hypr/hyprland.conf` first for behavior ownership, binds, workspace routing, and rollback safety.
2. Review `dot_local/bin` scripts next for reusable actions and assumptions about Obsidian/vault paths.
3. Review command-center config after validation identifies where Walker/Elephant actions live in this repo.
4. Review Quickshell last, only if the workspace label change stays cosmetic and small.

## Scope

In scope:

| Area | Target outcome |
|------|----------------|
| Workspaces | `1` browser, `2` shell, `3` dev, `4-6` dynamic, `7` chat. |
| Window rules | Route only validated obvious apps; keep `4-6` unconstrained. |
| Obsidian scratchpad | Toggle one primary vault as a floating overlay above the current workspace. |
| Quick note | Capture a note into the primary Obsidian vault without changing workspace. |
| Command center | Expose quick note first, clipboard/snippets second, system commands third. |
| Quickshell | Align workspace display labels with the activity map if the diff remains low-risk. |

Out of scope:

- Tmux/session redesign.
- Zellij optimization.
- Large Quickshell cockpit behavior.
- Visual theme polish beyond workspace label clarity.
- Beginner Hyprland explanations or generic onboarding defaults.

## Work units

| Unit | Purpose | Target files | Verification | Rollback boundary |
|------|---------|--------------|--------------|-------------------|
| 1. Validate runtime identities | Confirm app window classes/titles, Obsidian launch behavior, primary vault path, and command-center config location before encoding rules. | No lasting file changes; notes may be recorded in the implementation PR. | Run `hyprctl clients` with browser, terminal, editor, chat, and Obsidian open. Confirm whether Walker/Elephant command entries are file-backed in this dotfiles repo. | No rollback needed; validation-only unit. |
| 2. Workspace map and app routing | Encode fixed workspace intent while leaving `4-6` dynamic. | `dot_config/hypr/hyprland.conf` | `hyprctl reload`; open validated browser/shell/dev/chat apps; confirm expected placement; manually move overflow to `4-6`. | Revert only workspace/windowrule block and related binds if routing is noisy. |
| 3. Obsidian overlay scratchpad | Add a stable script and bind that toggles Obsidian as a floating overlay on the current workspace. | `dot_local/bin/executable_obsidian-scratchpad-toggle`, `dot_config/hypr/hyprland.conf` | From workspaces `1`, `2`, `3`, and `7`, trigger bind twice; confirm show/hide behavior, floating state, size/position, and no forced workspace switch. | Remove the script and Hyprland bind/window rules; existing Obsidian install remains untouched. |
| 4. Quick-note command | Add a reusable command that creates or opens a quick note in the single primary vault. | `dot_local/bin/executable_obsidian-quick-note` | Run script directly; confirm note appears in the expected vault path and does not require workspace switching. Test failure message when Obsidian/vault path is missing. | Remove the script and command-center entry; no config migrations. |
| 5. Command-center entries | Surface quick note, clipboard/snippets, and system commands in priority order once launcher config location is validated. | Validation-dependent: Walker/Elephant config path if present; otherwise document the gap before implementation. | Open command center; confirm quick note is the first productivity action; confirm clipboard/snippets and lock/reboot/audio/Wi-Fi/theme actions are reachable. | Revert only launcher action entries; scripts remain callable if unit 3/4 are kept. |
| 6. Quickshell label alignment | Show activity labels or clearer workspace hints if the current QML change stays small. | `dot_config/quickshell/components/WorkspaceIsland.qml` | Restart Quickshell; confirm labels match `1 Browser`, `2 Shell`, `3 Dev`, `4-6 Dynamic`, `7 Chat` intent without breaking click-to-switch. | Revert only QML label changes; Hyprland behavior remains source of truth. |

## Validation tasks before exact rules

- Capture validated class/title data for `zen-browser`, terminal, editor, Slack/Discord, and Obsidian with `hyprctl clients`.
- Confirm the primary Obsidian vault path and whether `obsidian://` URI handling is reliable on this machine.
- Confirm whether clipboard/snippet actions should use existing installed tools or require a package/config addition.
- Locate the real command-center configuration surface for Walker/Elephant; current repo search did not show a versioned launcher config directory.
- Confirm whether Quickshell workspace labels should remain numeric or include compact text labels; implement only if readable in the current top bar width.

## Risks

| Risk | Mitigation |
|------|------------|
| Window classes differ from package names. | Treat classes/titles as validation output, not design assumptions. |
| Obsidian may open a new window instead of reusing the scratchpad. | Make the script idempotent around observed clients and test from multiple workspaces. |
| Quick-note path could hardcode a machine-specific vault path. | Prefer a single explicit variable/config point in the script and fail loudly if missing. |
| Launcher config may not be represented in dotfiles yet. | Do not invent config structure; add entries only after the actual surface is found. |
| Quickshell label text could crowd the bar. | Keep Quickshell optional and cosmetic; drop it from slice 1 if it expands the diff. |
| App routing could over-constrain dynamic work. | Route only obvious validated apps; preserve `4-6` as manual/dynamic spaces. |

## Verification checklist

- [ ] `hyprctl reload` succeeds after Hyprland changes.
- [ ] `SUPER+1`, `SUPER+2`, `SUPER+3`, and `SUPER+7` preserve the fixed activity map.
- [ ] Workspaces `4-6` remain free of automatic routing rules.
- [ ] Obsidian toggles as a floating overlay above the current workspace from at least three different workspaces.
- [ ] Quick note can be triggered directly from `dot_local/bin` and through the command center.
- [ ] Command-center action order matches: quick note, clipboard/snippets, system commands.
- [ ] Existing tmux and Zellij behavior is not modified.
- [ ] Quickshell still starts and workspace click switching still works if label alignment is included.

## Review workload forecast

| Unit | Estimated changed lines | Chained PR recommendation |
|------|-------------------------|---------------------------|
| 1. Runtime validation | `0-20` documentation/review notes | No. |
| 2. Workspace map and app routing | `20-50` | No. |
| 3. Obsidian overlay scratchpad | `60-120` | No, unless script complexity grows. |
| 4. Quick-note command | `40-90` | No, unless vault handling expands. |
| 5. Command-center entries | `20-80` after config location is known | No, but split if launcher config must be introduced from scratch. |
| 6. Quickshell label alignment | `10-40` | No; drop from slice if it exceeds this range. |
| Full first slice | `150-400` expected | Chained PRs not recommended if kept under 400 changed lines. Start a second chained slice if command-center config creation or Quickshell changes push the diff beyond 400 lines. |

## Delivery guardrails

- Keep each work unit independently reviewable and rollbackable.
- Keep docs with visible workflow changes if implementation changes behavior users need to understand.
- Stop before tmux/Zellij work; that is a later slice.
- If runtime validation contradicts the approved spec, update the plan/spec before coding rather than forcing rules into Hyprland.
