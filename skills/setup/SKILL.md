---
name: setup
description: >
  Write or update the .wt file that marks a repo as using the main/ + worktrees/ layout,
  with its display name and GitHub project board. Use when the user invokes /wt:setup,
  when wt new exits 3 because .wt is missing and the user asks to fix it, or after
  wt new --migrate.
argument-hint: "[name]"
---

Write `<container>/.wt` for the current repo. `wt new` refuses to create worktrees
without it, and the custom T3 Code build reads it for the project name.

**Authorization:** invoking this skill authorizes read-only `git` and `gh` commands, and
writing `<container>/.wt` after the user confirms its contents. Nothing else: no edits
inside `main/` or any worktree, no git config changes, no T3 changes without a separate yes.

## 1. Find the container

```bash
common=$(git rev-parse --path-format=absolute --git-common-dir)
root=$(dirname "$common")        # the main checkout
container=$(dirname "$root")
```

The repo must already be in the layout: `$root` ends in `/main` and `$container/worktrees`
exists. If it isn't, stop and tell the user to run `wt new --migrate` themselves (it moves
the repo out from under this session, so never run it yourself).

If git commands in `$root` fail with "must be run in a work tree", check
`git -C $root config core.bare`. A main checkout with `core.bare = true` is broken; report
it with the fix (`git -C $root config core.bare false`) and stop until the user fixes it or
asks you to.

If `$container/.wt` already exists, read it with `git config -f $container/.wt --list` and
treat this run as an update: keep existing values unless the user asks to change them.

## 2. Gather the values

**name.** The argument if given. Otherwise suggest one from the container folder and the
`origin` remote (`git -C $root remote get-url origin`), preferring the name the user would
call the project out loud: `newark-arts` over `web`, `bk-rail` over `app`. Lowercase with
dashes.

**project.** The GitHub project board, as `<owner>/<number>`. Start from the boards the
repo's recent issues are on; the board can belong to a different owner than the repo:

```bash
gh issue list -R "$(gh repo view --json nameWithOwner -q .nameWithOwner)" --state all \
  --limit 40 --json projectItems -q '[.[].projectItems[].title] | group_by(.) | map("\(length)\t\(.[0])") | .[]'
```

Then find that board's number with `gh project list --owner <owner> --limit 100
--format json`, checking the repo's owner first. One clear board: suggest it. Several, or
none on the issues: list the owner's open boards and ask. No boards, or `gh` fails: leave
`project` out.

## 3. Confirm and write

Show the file you'd write:

```
[wt]
	name = bk-rail
	project = brooklynrail/1
```

Wait for the user to confirm or edit. Then write it with git so the format is exact:

```bash
git config -f "$container/.wt" wt.name "<name>"
git config -f "$container/.wt" wt.project "<owner>/<number>"   # only if there is one
```

Report the path and contents in two lines.

## 4. T3 Code project name

T3 Code saves a project's title when the project is added, so an existing project keeps its
old title (often `main`). Check:

```bash
sqlite3 ~/.t3/userdata/state.sqlite \
  "select project_id, title from projection_projects where workspace_root = '$root' and deleted_at is null;"
```

If a project exists and its title differs from `name`, offer to rename it. On yes, run
`t3 project rename <workspace root> <name>` if the `t3` CLI is available; otherwise tell the
user to rename it in the project's settings. Never write to `state.sqlite` directly.
