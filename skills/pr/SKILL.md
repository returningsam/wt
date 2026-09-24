---
name: pr
description: >
  Fix a bug in an isolated git worktree, get independent subagent reviews before
  anything is pushed, fold them in, then open an assigned PR. Takes a bug description or a
  GitHub issue link. Use when the user invokes /wt:pr, or asks to fix a bug in a
  worktree and PR it.
---

Fix a bug in a worktree, harden it against independent reviews, then open the PR.
Nothing leaves the machine until the findings are triaged and applied.

**Authorization:** invoking this skill authorizes one local commit sequence on the worktree
branch, one `git push` of it, one `gh pr create`, and the two status moves on the issue's
project-board item described in §1 and §5. Nothing else — no other branch, no force-push after
the PR exists, no merge, no writes to the original checkout, no other edit to the issue.

## 1. Resolve the bug, then claim it

Argument is a bug description or an issue URL / `#123` / number. For an issue read the
comments too (`gh issue view <n> --comments`) — the scope often lives there, not in the body.

Restate the bug in a sentence: observed vs. expected, and where it likely lives. If it's a
wishlist of several problems, or two readings give different diffs, ask **before** cutting
the worktree. Keep the issue number for the `Closes #N` trailer.

**Claim the issue before §2, not after the PR.** Once the restatement holds and you're going
to work the issue, move its item on the project board to the in-progress status straight away.
The board is how the user sees what's being worked on; a ticket sitting in `Todo` or `Needs
info` while a worktree is running reads as unclaimed, and moving it only at the end defeats
the point. Find the item with `gh project item-list <project> --owner <org> --format json`,
filtering on `content.repository` as well as the issue number — boards span repos, so numbers
collide — then set it:

```bash
gh project item-edit --id <item> --project-id <proj> \
  --field-id <status-field> --single-select-option-id <in-progress>
```

Project, field and option IDs may already be in memory for this repo; otherwise read them off
`gh project field-list <project> --owner <org> --format json`. If the issue isn't on a board,
or nothing resembling an in-progress status exists, say so in one line and carry on — never
stall the fix over the board.

## 2. Cut the worktree

Base branch = the integration branch CLAUDE.md names (e.g. a `staging` release gate), else
`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.

Branch name: match existing convention (`git branch -r --sort=-committerdate | head -20`) —
usually `fix/i<issue>-<slug>`. Create the worktree with `wt-new --base origin/<base> <branch>`
(not `EnterWorktree`). It prints the worktree path as its last stdout line; `cd` there and
confirm with `pwd && git status -sb`. You're on `wt/<branch>`; `<branch>` in the main checkout
tracks it, so the user can `git pull` there at any time to test your commits.

If `wt-new` exits 3, the repo isn't in the `main/` + `worktrees/` layout yet. Relay its
instructions to the user and stop — the migration moves the repo out from under this session,
so never run `wt-new --migrate` yourself.

All work happens in the worktree — never edit the original checkout. Install deps with the
package manager the committed lockfile implies.

## 3. Implement

- Find the actual defect; don't pattern-match the symptom. If no real defect matches the
  report, stop and say so rather than inventing a plausible change.
- Fix the cause, keep the diff to what the bug needs. Note adjacent problems for the final
  report instead of fixing them.
- Follow repo conventions (CLAUDE.md, the neighbors' idiom and comment density).
- Run the repo's verification command (`yarn validate`, `npm test`, `make check`, …) — it
  must pass before review. Never start a dev server or Storybook.
- Commit locally so reviewers get a stable diff. Subject: plainly what changed and where,
  imperative, no metaphor — rationale goes in the body. No `Co-Authored-By` trailer.

## 4. Review — before anything is published

Invoke the **herd-review** skill (`Skill(skill: "herd-review")`) on the worktree. Hand it:

- the worktree path and the exact diff command (`git diff <base>...HEAD`),
- the bug restatement from §1 and the issue URL, if there is one,
- an explicit instruction that this is a `/wt:pr` run: **apply confirmed blocking and
  worth-fixing findings without asking**, since the run continues straight to the PR.

It reads the change, sizes the review to its risk, spawns read-only reviewers, triages the
merged findings against the code, and applies the confirmed ones. Keep its list of applied and
rejected findings for §6.

Re-run verification after the findings land, then add one clean commit for them. Never amend,
rebase, or reset committed work — the user may have pulled it, and rewritten history breaks
their `git pull`.

## 5. Open the PR

```bash
git push origin HEAD:<branch>   # wt/<branch> → origin/<branch>; always name the target
gh pr create --head <branch> --base <base> --assignee @me --title "…" --body "…"
```

`gh pr create` prints the PR URL as its last line. Keep it for §6; if it got lost, recover it
with `gh pr view <branch> --json url -q .url`.

`--assignee @me` is required. Description rules (standing user preferences):

- Terse bullets under `###` headings grouped by surface. Each: **bolded** statement of what
  changed, then at most one clause of why — dropped when self-evident. Outcome first, not
  mechanism.
- No prose paragraphs, no narrative summary, no restating the diff.
- No "Test plan" section. No "lint/type-check/CI is green" filler. No diff stats (line
  counts, `+X / −Y`, files changed).
- Keep `Closes #N`. Never mention the reviews, the subagents, or this skill — the body
  describes the branch's current state only.
- If it stacks on another branch, it builds "on top of that branch", never "that branch's tip".

With the PR open, move the board item on from in-progress to whatever status means *awaiting
review* (`Ready for review`, `In review`, …), using the same `item-edit` call as §1. Same
caveat: if there's no such status, note it in a line and move on.

## 6. Report

The report's first line is always the PR link, with the full URL as both text and target:

```
PR: [<full URL>](<full URL>)
```

Never a bare `#123`, and never leave the link out, even when the run ends with a warning.
Then:

- What the fix does (a sentence or two).
- What the reviews changed: findings applied, findings rejected + why.
- Anything adjacent left alone deliberately.
- The worktree path, still on disk, and that `git switch <branch> && git pull` in the main
  checkout gets the work. Clean up with `wt-rm <branch>` only if the user asks.
- Where the issue's board item ended up, or why it couldn't be moved.

## Stops

- Fix turns out to be a feature or refactor → say so, get a go-ahead before continuing past §3.
- Push fails, `gh` unauthenticated, or verification fails for a reason unrelated to the fix →
  stop with the actual output. Never open a PR on a tree you couldn't verify.
