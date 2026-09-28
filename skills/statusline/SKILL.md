---
name: statusline
description: >
  Install wt-status as the Claude Code status line: the session's issues, worktree state,
  and PR on one line. Use when the user invokes /wt:statusline, or asks to set up or
  remove the wt status line.
---

Point `statusLine` in `~/.claude/settings.json` at `wt-status`. Plugins can't set
`statusLine` themselves, so this skill writes it.

**Authorization:** invoking this skill authorizes editing the `statusLine` key of
`~/.claude/settings.json`, and nothing else in that file.

## 1. Find the script

Use `~/.claude/plugins/marketplaces/wt/bin/wt-status` when it exists: the marketplace
clone keeps its path across plugin updates. Otherwise use `bin/wt-status` two levels up
from this skill's base directory, and tell the user that path changes with each plugin
version, so they'll need to rerun this skill after an update.

Check that `jq` and `gh` are on `PATH`. Without `gh` the line still shows the worktree
state and branch issues, but not PR state, checks, or closed issues.

## 2. Write the setting

Read `~/.claude/settings.json` (it may be a symlink into a dotfiles repo; edit the target).
If `statusLine` is already set to something other than `wt-status`, show it and ask before
replacing it. Then set:

```json
"statusLine": {
  "type": "command",
  "command": "<script path>",
  "refreshInterval": 5
}
```

`refreshInterval` lets the yellow "files changing" arrow fade and picks up the background
`gh` refresh while the session is idle.

To remove it, delete the `statusLine` key.

## 3. Report

One line saying where the setting points, then the legend:

```
545 ~~> 562✓  +3 ↑2
-|   not in a worktree        ...  nothing done yet
~~>  uncommitted edits        -->  commits not pushed
==>  pushed, main/ not pulled ===  pushed and pulled
```

The arrow turns yellow while files are changing. Each issue and PR number has GitHub's
Octicon for its state in front of it, in GitHub's colors: green open, grey draft or not
planned, purple merged or completed, red closed. `✓` `✗` `·` are the PR's checks. Issue
and PR numbers are links (cmd-click).

Mention only the caveats that apply:

- The arrows are ligatures in JetBrains Mono (Ghostty's default). In other fonts they
  show as plain `~~>` and `-->`.
- Inside tmux, links and dotted underlines need
  `set -as terminal-features ',*:hyperlinks:usstyle'`.
- If the numbers show but don't click, launch Claude with `FORCE_HYPERLINK=1`.
