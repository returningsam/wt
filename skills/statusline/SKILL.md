---
name: statusline
description: >
  Turn the wt Claude Code status line on or off: the session's issues, worktree
  state, and PR on one line. Takes an optional `on` or `off`; with neither it toggles. Use
  when the user invokes /wt:statusline, or asks to set up, enable, disable, or remove the
  wt status line.
argument-hint: "[on|off]"
---

Point `statusLine` in `~/.claude/settings.json` at `wt status`, or remove it. Plugins
can't set `statusLine` themselves, so this skill writes it.

**Authorization:** invoking this skill authorizes editing the `statusLine` key of
`~/.claude/settings.json`, and nothing else in that file.

## 0. Pick the action

Read `~/.claude/settings.json` (it may be a symlink into a dotfiles repo; edit the target).
The wt status line is on when `statusLine.command` ends in `/wt status`. A command ending in
`/wt-status` is the wt status line from before 0.8.0, whose script no longer exists. Treat it
as the wt status line everywhere below, except that the toggle turns it on, not off.

- `on`: turn it on, even if it's already on (this refreshes a stale command path).
- `off`: turn it off. If it's already off, say so and stop.
- No argument: toggle. Off, some other status line, or a pre-0.8.0 one means turn it on.

To turn it off, delete the `statusLine` key and report it in one line. Skip the rest of
this skill. If `statusLine` points at something other than the wt status line, leave it
alone and say the wt status line isn't the current one.

To turn it on, continue below.

## 1. Find the command

Use `~/.claude/plugins/marketplaces/wt/bin/wt` when it exists: the marketplace clone keeps
its path across plugin updates. Otherwise use `bin/wt` two levels up from this skill's base
directory, and tell the user that path changes with each plugin version, so they'll need to
rerun this skill after an update. Write a path under `$HOME` with a leading `~/` rather
than quoting it. Claude Code runs the command through `sh -c`, which expands `~`, and a
quoted path would stop step 0 from recognizing it.

Check that `jq` and `gh` are on `PATH`. Without `gh` the line still shows the worktree
state and branch issues, but not PR state, checks, or closed issues.

## 2. Write the setting

If `statusLine` is already set to something other than the wt status line, show it and ask
before replacing it. Then set:

```json
"statusLine": {
  "type": "command",
  "command": "<path>/bin/wt status",
  "refreshInterval": 5
}
```

`refreshInterval` lets the yellow "files changing" arrow fade and picks up the background
`gh` refresh while the session is idle.

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
- Inside tmux, links need `set -as terminal-features ',*:hyperlinks'`, and Claude needs
  `FORCE_HYPERLINK=1` exported from the shell, since `TERM_PROGRAM=tmux` makes it drop
  links. With tmux `mouse on`, open links with cmd+shift+click.
- If the numbers show but don't click, launch Claude with `FORCE_HYPERLINK=1`.
