# Daily-driver productivity layer

Design a first productivity pass for the Hyprland-based dotfiles. The goal is not to onboard a new Hyprland user; it is to refine an experienced user's existing daily-driver workflow around fixed activity workspaces, a fast Obsidian scratchpad, a curated command center, and tmux as the stable terminal base.

## Decision

Use a layered model:

| Layer | Responsibility |
|-------|----------------|
| Hyprland | Own window behavior, workspaces, scratchpads, and muscle-memory binds. |
| Scripts in `dot_local/bin` | Execute reusable workflow actions such as toggling Obsidian or creating notes. |
| Command center | Expose frequent actions without requiring terminal friction. |
| Quickshell | Observe and display state; avoid becoming the primary workflow engine in this phase. |
| Tmux | Remain the stable shell/dev session foundation; defer Zellij optimization. |

This keeps ownership clear and prevents workflow logic from being scattered across the compositor, QML, shell aliases, and launcher configuration.

## Priorities

1. Polish Hyprland windows, workspaces, and scratchpads.
2. Add a command-center flow for quick actions.
3. Improve terminal/project movement with tmux after the desktop layer is stable.

Out of scope for this first pass:

- Reworking Zellij.
- Turning Quickshell into a full cockpit.
- Large visual theme work beyond what is needed for productivity.
- Beginner-oriented Hyprland defaults or explanations.

## Workspace model

Workspaces are activity-based, fixed where muscle memory matters, and flexible where temporary work matters.

| Workspace | Role |
|-----------|------|
| `1` | Browser |
| `2` | Shell / terminal |
| `3` | Dev / editor |
| `4` | Dynamic |
| `5` | Dynamic |
| `6` | Dynamic |
| `7` | Chat / Slack / Discord |

App rules may route obvious apps to their expected workspaces, but the design must not over-constrain the user. Workspaces `4-6` intentionally stay dynamic for research, experiments, temporary windows, or overflow.

Quickshell should reinforce this map in the top bar, but Hyprland remains the source of behavior.

## Scratchpad model

The primary scratchpad is Obsidian.

Requirements:

- Toggle Obsidian as a floating window above the current workspace.
- Do not move the user to a dedicated notes workspace.
- Use one primary Obsidian vault.
- Provide a stable bind for show/hide.
- Prefer quick visibility and low context switching over a complex notes workspace model.

Design intent: Obsidian acts as a cognitive overlay, not as another app in the workspace grid.

## Command center model

The launcher should evolve into a curated command center, not just an app launcher.

Initial action priority:

1. Quick note in Obsidian.
2. Clipboard history and snippets.
3. System commands such as lock, logout, reboot, audio, Wi-Fi, and theme actions.

The command center should expose high-frequency actions first. Screenshots and project/tmux launching are useful but lower priority for the first slice.

## Terminal model

Tmux remains the stable terminal center.

- Workspace `2` is the main shell/session space.
- Workspace `3` is the dev/editor activity space, but tmux can still carry dev workflows when that is natural.
- Command-center support for "open project + tmux session" can come after Hyprland and notes flows are working.
- Zellij remains installed and available, but is not optimized in this phase.

The desktop should stop forcing tmux to compensate for window/workspace friction. Once the compositor workflow is stable, tmux improvements can focus on sessions rather than navigation patches.

## Implementation direction

Recommended first slice:

1. Encode the activity workspace map in Hyprland and Quickshell display.
2. Add or refine app rules for browser, terminal, editor, and chat apps.
3. Add an Obsidian scratchpad toggle script and Hyprland bind.
4. Add a quick-note command targeting the single primary vault.
5. Expose quick note, clipboard/snippets, and system commands through the command center.
6. Verify the workflow manually on the real machine and add lightweight doctor checks only where they catch real regressions.

## Acceptance criteria

- The user can reach browser, shell, dev, and chat by fixed workspace muscle memory.
- Workspaces `4-6` remain free for dynamic use.
- Obsidian can be toggled as a floating overlay from any workspace.
- Quick note capture does not require changing workspaces.
- The launcher exposes command-center actions in the agreed priority order.
- Tmux behavior remains stable and existing Zellij config is not disrupted.

## Review notes

Review this spec for workflow ownership first: Hyprland should own behavior, scripts should own actions, command center should expose actions, and Quickshell should avoid becoming a logic sink.
