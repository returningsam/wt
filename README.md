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
- `wt new --migrate` — move a repo into the `main/` + `worktrees/` layout. Repairs existing
  worktrees and moves Claude's per-project history to the new path. Run it yourself with the
  editor and dev servers closed; it moves the repo out from under anything open on it.
  Then run `/wt:setup` to write `.wt`.
- `wt rm [--force] <branch | path>` — remove the worktree and its `wt/` branch, and point
  `<branch>` back at `origin/<branch>`. Refuses when the worktree is dirty or its commits
  exist nowhere else.

`wt new` exits 3 when the repo still needs migrating, or when `.wt` is missing.

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

## Status line

`wt status` is a Claude Code status line for worktree sessions. `/wt:statusline` toggles it,
and `/wt:statusline on` or `off` sets it.

```
545 ~~> 562✓  +3 ↑2
```

Issues sit on the left and the PR on the right. The arrow between them is a JetBrains Mono
ligature, and its stroke shows how far the work has gone:

| arrow | state |
|---|---|
| `-\|` | not in a worktree |
| `...` | nothing done yet |
| `~~>` | uncommitted edits |
| `-->` | commits not pushed |
| `==>` | pushed, `main/` hasn't pulled |
| `===` | pushed and pulled |

The arrow turns yellow while files are changing. Each issue and PR number has GitHub's
Octicon for its state in front of it, in GitHub's colors, and `✓` `✗` `·` are the PR's
checks. The icons come from the Nerd Font symbols Ghostty bundles; other terminals need a
Nerd Font. Issue and PR numbers are links. Issues come from `i<number>` in
the branch name and from the PR's closing references. The `gh` lookups run in the
background and are cached for 60 seconds in `~/.cache/wt-status`.

Claude resets its shell to the project dir after every command, so a session started in
`main/` never sits in the worktree it works on. When `wt new` runs inside a Claude session,
it records the worktree under the session ID in `~/.cache/wt-status/sessions`, and the
status line shows that worktree for the rest of the session, including after
`claude --resume`. `wt rm` clears the record.

## Rules that keep `git pull` working

Never amend, rebase, or reset commits on a `wt/` branch — the main checkout may already have
pulled them. Push with `git push origin HEAD:<branch>`.
