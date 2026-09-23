# wt

Git worktrees in a predictable layout, on branches the main checkout can pull from.

```
<repo>/
├── main/                     main checkout — dev servers run here
└── worktrees/
    └── wt-fix-i545-foo/      worktree on branch wt/fix/i545-foo
```

An agent commits on `wt/<branch>` in the worktree. `<branch>` in `main/` tracks that branch
locally, so `git switch <branch> && git pull` in `main/` picks the work up without removing
the worktree, and hot reload keeps running.

## Install

```sh
claude plugin marketplace add returningsam/wt
claude plugin install wt@wt
```

The plugin's `bin/` is on Claude's `PATH`. For a plain terminal, add it yourself:

```sh
export PATH="$HOME/.claude/plugins/marketplaces/wt/bin:$PATH"
```

## Commands

- `wt-new [--base <ref>] <branch>` — create `worktrees/wt-<branch>` on `wt/<branch>`, and
  point `<branch>` in `main/` at it. Prints the worktree path. Starts from an existing local
  or remote `<branch>` when there is one, otherwise from the default branch.
- `wt-new --migrate` — move a repo into the `main/` + `worktrees/` layout. Repairs existing
  worktrees and moves Claude's per-project history to the new path. Run it yourself with the
  editor and dev servers closed; it moves the repo out from under anything open on it.
- `wt-rm [--force] <branch | path>` — remove the worktree and its `wt/` branch, and point
  `<branch>` back at `origin/<branch>`. Refuses when the worktree is dirty or its commits
  exist nowhere else.

`wt-new` exits 3 when the repo still needs migrating.

## Claude integration

`WorktreeCreate` and `WorktreeRemove` hooks route `claude --worktree` and worktree-isolated
subagents through `wt-new` and `wt-rm`, so agent worktrees land in the same layout.

The `worktree-pr` skill fixes a bug in a worktree, runs independent reviews over it,
then opens an assigned PR from `wt/<branch>` to `origin/<branch>`.

The `wt-clean` skill lists the repo's worktrees, sorts them by whether removing them loses
anything, and runs `wt-rm` on the ones you pick.

## Rules that keep `git pull` working

Never amend, rebase, or reset commits on a `wt/` branch — the main checkout may already have
pulled them. Push with `git push origin HEAD:<branch>`.
