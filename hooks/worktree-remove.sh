#!/bin/zsh
# WorktreeRemove hook: routes Claude worktree removal through wt rm.
exec ${CLAUDE_PLUGIN_ROOT:-${0:a:h:h}}/bin/wt rm "$(jq -r .worktree_path)"
