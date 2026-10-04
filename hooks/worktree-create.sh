#!/bin/zsh
# WorktreeCreate hook: routes Claude-created worktrees through wt new.
input=$(cat)
cd "$(jq -r .cwd <<<$input)" || exit 1
# Isolated subagents create worktrees too; keep them off the session's status line.
unset CLAUDE_CODE_SESSION_ID
exec ${CLAUDE_PLUGIN_ROOT:-${0:a:h:h}}/bin/wt new "$(jq -r .name <<<$input)"
