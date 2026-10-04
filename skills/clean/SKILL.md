---
name: clean
description: >
  Find stale git worktrees in the current repo, remove the ones whose work is already
  merged, and sort the rest into safe-to-remove, needs a decision, and keep for the user to
  pick from. Use when the user invokes
  /wt:clean, or asks to clean up, prune, or list stale worktrees.
---

Clean up worktrees in the current repo. Gather facts, classify, remove merged work, ask
about the rest, then remove what the user picks.

**Authorization:** invoking this skill authorizes `git fetch --prune`, `git worktree prune`,
removing merged worktrees (§2) without asking, and removing the worktrees the user selects
in §3. Nothing else: no pushes, no edits inside a
worktree, no changes to `main/`'s checked-out branch.

## 1. Gather

Run from anywhere in the repo. Find the main checkout with
`git rev-parse --path-format=absolute --git-common-dir` (its parent). Then:

```bash
git -C <root> fetch -q --prune origin
git -C <root> worktree prune -v
git -C <root> worktree list --porcelain
default=$(git -C <root> symbolic-ref -q --short refs/remotes/origin/HEAD || echo main)
```

Report what `worktree prune` removed; those were entries whose directory was already gone.

Skip the main checkout and the worktree this session is running in. For every other
worktree, collect:

- **Branch.** From the `branch` line. Detached or not under `wt/` is a legacy or foreign
  worktree (often under `.claude/worktrees/`); `wt rm` won't take it, see §4.
- **Dirty.** `git -C <dir> status --porcelain | wc -l`, split into tracked changes and
  untracked files.
- **Unique commits.** Commits on `wt/<branch>` that aren't on `<branch>`, `origin/<branch>`,
  or `$default`. This is the same check `wt rm` makes:
  `git log --oneline wt/<branch> --not <branch> origin/<branch> $default` (drop refs that
  don't exist).
- **PR.** `gh pr list --head <branch> --state all --json number,state,url,headRefOid,mergedAt`.
  Skip this column if `gh` isn't authenticated, and say so.
- **Last activity.** `git log -1 --format=%cr wt/<branch>` and the directory's mtime.

## 2. Classify

**Merged (remove without asking):** the work already landed, so the worktree goes.

- Clean, PR `MERGED`, and every unique commit is in the PR's `headRefOid`
  (`git merge-base --is-ancestor wt/<branch> <headRefOid>`). When the remote branch is gone
  after a squash merge, `wt rm` needs `--force`.
- Clean, and `wt/<branch>` is an ancestor of `$default` (a regular merge).

Only ask first if `lsof` (§3) finds a process using the directory.

**Safe to remove:** clean, no unique commits, but no merge found (pushed without a merged
PR, or never used).

**Needs a decision:**

- Dirty in any way. List the changed paths.
- Unique commits with no PR, or a PR that's `CLOSED` without merging. List the commits.
- PR `MERGED` but the worktree has commits after `headRefOid`.

**Keep:** PR `OPEN`, or activity within the last 3 days and no PR. Show these so the user
sees the whole picture, but don't offer them for removal unless asked.

## 3. Ask

Before removing any worktree, merged ones included, warn if a dev server or editor might be
using it. Check with `lsof -t +d <dir> 2>/dev/null | head` (non-recursive, fast) and name any
processes found.

Remove the merged bucket first (§4). Then print one compact table per bucket, merged
included so the user sees what went. Columns are worktree dir name, branch, PR link, last
activity, and the reason for the bucket. Then use `AskUserQuestion` with
`multiSelect: true`: one question for safe-to-remove (all listed) and one for
needs-a-decision. With more than 4 in a bucket, offer "all of them", "none", and "let me
list them" instead of one option per worktree.

## 4. Remove

For each selected `wt/` worktree:

```bash
wt rm <branch>            # clean, no unique commits
wt rm --force <branch>    # verified merge wt rm refuses, or the user chose to drop the work
```

Use `--force` only for a verified merge, or for a needs-a-decision worktree
the user selected knowing what it drops. If `wt rm` refuses anything else, report its
message and move on; don't retry with `--force`.

For a legacy or foreign worktree, use `git -C <root> worktree remove <dir>` (add `--force`
under the same rule), then delete its branch with `git branch -d`, never `-D` unless the
user chose to drop the work.

## 5. Report

A few lines: what was removed, what was kept and why, and anything that failed with the
tool's message. If `.claude/worktrees/` is now empty, mention it can be deleted.
