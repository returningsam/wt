# wt

Git worktrees in a predictable layout, on branches the main checkout can pull from.

```
<repo>/
├── .wt                       layout marker: name and project board
├── main/                     main checkout — dev servers run here
└── worktrees/
    └── wt-fix-i545-foo/      worktree on branch wt/fix/i545-foo
```

An agent commits on `wt/<branch>` in the worktree. `<branch>` in `main/` tracks that branch
locally, so `git switch <branch> && git pull` in `main/` picks the work up without removing
the worktree, and hot reload keeps running.

## The .wt file

`<repo>/.wt` marks the layout. `wt new` won't create worktrees without it. It uses
git-config syntax, so both shell scripts and git can read it:

```
[wt]
	name = bk-rail
	project = UseAllFive/12
```

- `name` — the project's display name. The custom T3 Code build uses it for project titles.
- `project` — the repo's GitHub project board as `<owner>/<number>`, for issue skills.

`/wt:setup` writes the file after looking at the repo, and you confirm it first.

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

- `wt new [--base <ref>] <branch>` — create `worktrees/wt-<branch>` on `wt/<branch>`, and
  point `<branch>` in `main/` at it. Prints the worktree path. Starts from an existing local
  or remote `<branch>` when there is one, otherwise from the default branch.
- `wt rm [--force] <branch | path>` — remove the worktree and its `wt/` branch, and point
  `<branch>` back at `origin/<branch>`. Refuses when the worktree is dirty or its commits
  exist nowhere else.
- `wt migrate` — move a repo into the `main/` + `worktrees/` layout. Repairs existing
  worktrees and moves Claude's per-project history to the new path. Run it with the editor and
  dev servers closed; it moves the repo out from under anything open on it.
  Then run `/wt:setup` to write `.wt`.

`wt new` exits 3 when the repo still needs migrating, or when `.wt` is missing. `wt` with no
arguments lists the commands.

Before 0.8.0 these were separate scripts named `wt-new` and `wt-rm`. In 0.8.0,
`wt migrate` was `wt new --migrate`.

## Claude integration

`WorktreeCreate` and `WorktreeRemove` hooks route `claude --worktree` and worktree-isolated
subagents through `wt new` and `wt rm`, so agent worktrees land in the same layout.

The `pr` skill (`/wt:pr`) implements an issue in a worktree (a bug fix, a feature, anything a
PR can resolve), runs independent reviews over it, then opens an assigned PR from `wt/<branch>`
to `origin/<branch>`. It hands the implementation to one of the plugin's `implementer-*`
agents, all on Opus, picking `medium`, `high`, or `xhigh` effort from how hard the work looks.

The `setup` skill (`/wt:setup`) writes or updates `.wt`. It suggests a name and finds the
repo's project board from the boards its recent issues are on.

The `clean` skill (`/wt:clean`) lists the repo's worktrees, sorts them by whether removing
them loses anything, and runs `wt rm` on the ones you pick.

## Rules that keep `git pull` working

Never amend, rebase, or reset commits on a `wt/` branch — the main checkout may already have
pulled them. Push with `git push origin HEAD:<branch>`.
