#!/bin/zsh
# WorktreeCreate hook: routes Claude-created worktrees through wt-new.
input=$(cat)
cd "$(jq -r .cwd <<<$input)" || exit 1
exec ${CLAUDE_PLUGIN_ROOT:-${0:a:h:h}}/bin/wt-new "$(jq -r .name <<<$input)"
