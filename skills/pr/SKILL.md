---
name: pr
description: >
  Implement a GitHub issue or a described change (a bug fix, a feature, anything a PR can
  resolve) in an isolated git worktree, get independent subagent reviews before anything is
  pushed, fold them in, then open an assigned PR with before/after screenshots when the UI
  changes. Use when the user invokes /wt:pr, or asks to fix a bug or implement an issue in a
  worktree and PR it.
---

Implement an issue or change in a worktree, harden it against independent reviews, then open
the PR. Nothing leaves the machine until the findings are triaged and applied.

**Authorization:** invoking this skill authorizes one local commit sequence on the worktree
branch, one `git push` of it, one `gh pr create`, and the two status moves on the issue's
project-board item described in §1 and §6. When the PR has visual changes, it also authorizes
sending the repo's screenshot generator a request, and starting that generator's thread when
none exists (§6). Nothing else — no other branch, no force-push after the PR exists, no merge,
no writes to the original checkout, no other edit to the issue.

## 1. Resolve the issue, then claim it

Argument is a description of the change or an issue URL / `#123` / number. For an issue read the
comments too (`gh issue view <n> --comments`) — the scope often lives there, not in the body.

Restate the work in a sentence. For a bug, that's observed vs. expected and where it likely
lives. For anything else, it's what changes and where. Ask **before** cutting the worktree if
it's a wishlist of several problems, two readings give different diffs, a feature has more
than one reasonable approach, or the spec is out of reach (a private Figma link, say). Keep
the issue number for the `Closes #N` or `Refs #N` trailer (§6).

Some parts of an issue can't be done in a PR: a dashboard setting, a CMS edit, a decision
someone else owns. Call them out in the restatement and scope the run to the rest. If none of
it can be done in a PR, stop and say so.

**Claim the issue before §2, not after the PR.** The board is `wt.project` in the repo's
`.wt` (`git config -f <container>/.wt wt.project`, where the container is the main
checkout's parent), as `<owner>/<number>`. With no issue or no `wt.project`, skip the board
steps here and in §6 and don't mention them anywhere. Otherwise, once the restatement holds
and you're going to work the issue, move its item on that board to the in-progress status
straight away.
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
`gh project field-list <project> --owner <org> --format json`. If the issue isn't on that
board, nothing resembling an in-progress status exists, or the edit fails, keep it for the
report and carry on. Never stall the work over the board.

## 2. Cut the worktree

Base branch = the integration branch CLAUDE.md names (e.g. a `staging` release gate), else
`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.

Branch name: match existing convention
(`git branch -r --sort=-committerdate | head -20`) —
usually `<type>/i<issue>-<slug>`, where the type (`fix`, `feat`, `chore`, …) matches the work
and the repo's existing branches. Create the worktree with
`wt new --base origin/<base> <branch>` (not `EnterWorktree`). It prints the worktree path as its
last stdout line; `cd` there and confirm with `pwd && git status -sb`. You're on `wt/<branch>`;
`<branch>` in the main checkout tracks it, so the user can `git pull` there at any time to test
your commits.

If `wt new` exits 3, the repo isn't in the `main/` + `worktrees/` layout yet, or it is but
has no `.wt` file. Relay its instructions to the user and stop. A missing `.wt` is fixed
with `/wt:setup`; offer it, but don't run it without a yes.

All work happens in the worktree — never edit the original checkout. Install deps with the
package manager the committed lockfile implies.

## 3. Implement

Hand the implementation to an implementer agent, and pick its effort from the work. Every
implementer runs on Opus. Look at the code the restatement points to first, enough to judge
how hard the change is, then pick one:

| Agent | When |
|---|---|
| `wt:implementer-medium` | Docs, copy, config, or a small change whose location is already known |
| `wt:implementer-high` | A bug whose cause needs tracing, or a feature in one area. The default when unsure |
| `wt:implementer-xhigh` | The cause is still unknown after a first look, the change spans subsystems, or it touches auth, migrations, concurrency, a public API, or money |

Spawn it in the foreground (`run_in_background: false`) and give it the worktree path, the
restatement from §1, the issue URL and its relevant comments, the base branch, and the repo's
verification command (`yarn validate`, `npm test`, `make check`, …). If those agent types
aren't available, spawn `general-purpose` with `model: opus` and the agent file's
instructions, and say so in the report.

When it returns, check its work rather than its summary: `git log <base>..HEAD` shows the
commit, and verification passes when you run it yourself. If it stopped instead (no real
defect, the code already does it, the scope grew), relay that and stop the run. If its result
is wrong or incomplete, spawn it again with what's missing, one tier higher if the miss looks
like the work was harder than you judged. Keep the adjacent problems it noted for §7.

## 4. Review — before anything is published

Invoke the **herd-review** skill (`Skill(skill: "herd-review")`) on the worktree. Hand it:

- the worktree path and the exact diff command (`git diff <base>...HEAD`),
- the restatement from §1 and the issue URL, if there is one,
- an explicit instruction that this is a `/wt:pr` run: **apply confirmed blocking and
  worth-fixing findings without asking**, since the run continues straight to the PR.

It reads the change, sizes the review to its risk, spawns read-only reviewers, triages the
merged findings against the code, and applies the confirmed ones. Keep its list of applied and
rejected findings for §7.

Re-run verification after the findings land, then add one clean commit for them. Never amend,
rebase, or reset committed work — the user may have pulled it, and rewritten history breaks
their `git pull`.

## 5. Screenshots

Run this after the review findings are committed, so the after shots show the final state.
It applies when the diff changes rendered UI: web pages, components, native app screens.
Backend, CLI, docs, config, and refactors with no rendered difference skip this section and
§8, and neither the PR body nor the report mentions screenshots.

Each repo has one screenshot generator, a separate session that runs `/wt:shots`. It captures
on its own worktree and dev servers and adds the Screenshots table to the PR. This run never
captures, and never switches, pulls, or starts anything in `main/`. Its part is the request,
since it knows the diff.

**Enumerate from the diff.** Each distinct visual change gets one row. When the same change
repeats across many screens, show one representative screen and name the others in the row's
label. Cover the states the diff touches (hover or focus, error, empty, loading, a mobile
breakpoint, dark mode) when the change looks different there. Don't add states the change
doesn't affect. Some screens only appear after an interaction (a button press, an open modal,
a form error). List those from the diff and the PR description, with the steps to reach them.

**Write the request now, and send it in §6** once the PR exists. Start it with `/wt:shots`
and the PR URL, then give:

- How to reach each screen: the route, scenario or story, displays or breakpoints, and the
  exact list of steps or states. Name any app input (a colorway, a feature flag, a signed-in
  role) to use on both sides.
- What changes on each screen, with coordinates where you know them, and which screens should
  show no change.
- Known noise and what to do about it: a live timer, a step that advances on its own, an
  enter animation.
- Close-ups worth having, such as a small element on a large frame.

Leave the SHAs out, or give them only as a cross-check. The generator reads them from the PR.

## 6. Open the PR

```bash
git push origin HEAD:<branch>   # wt/<branch> → origin/<branch>; always name the target
```

Write the body by the rules below, then run one `gh pr create`:

```bash
gh pr create --head <branch> --base <base> --assignee @me --title "…" --body "…"
```

`gh pr create` prints the PR URL as its last line. Keep it for the steps below and §7. If it
got lost, recover it with `gh pr view <branch> --json url -q .url`.

With screenshots, send the §5 request once the PR exists. The generator's thread is titled
`Screenshot generator: <name>`, where `<name>` is `wt.name` in the repo's `.wt`.

- **In T3**, find it with `t3_thread_search` for "Screenshot generator" (it searches this
  project by default), skipping archived threads. Send the request with `t3_thread_send` and
  `mode: "queue"`, so it waits behind other requests, and keep the run it returns for §8.
- **If T3 has none**, search once more, since another run may have just started one. Then
  start it with `t3_thread_launch`, with that title, this thread's project and no
  `workspaceStrategy`, and the request as its message. Keep its link and run for §8.
- **Outside T3**, look in `ListAgents` for a peer with that name and send the request with
  `SendMessage`. Nothing there can start a session, so with no peer, put the request in the
  report for the user to paste into a new session.

A failed send doesn't count as a Stops failure. Say so in the report.

`--assignee @me` is required. Description rules (standing user preferences):

- Terse bullets under `###` headings grouped by surface. Each: **bolded** statement of what
  changed, then at most one clause of why — dropped when self-evident. Outcome first, not
  mechanism.
- No prose paragraphs, no narrative summary, no restating the diff.
- No "Test plan" section. No "lint/type-check/CI is green" filler. No diff stats (line
  counts, `+X / −Y`, files changed).
- Keep `Closes #N` when there's an issue; with none, leave the trailer out. If the PR leaves any part of the issue or request undone, use `Refs #N`
  instead so merging doesn't close the issue. Never mention the reviews, the subagents, or this
  skill — the body describes the branch's current state only.
- If it stacks on another branch, it builds "on top of that branch", never "that branch's tip".
- Leave out a Screenshots section. The generator adds one before the `Closes`/`Refs` line.

With the PR open, move the board item on from in-progress to whatever status means *awaiting
review* (`Ready for review`, `In review`, …), using the same `item-edit` call as §1. Same
caveat: if there's no such status or the edit fails, keep it for the report and move on.

## 7. Report

The report's first line is always the PR link, with the full URL as both text and target:

```
PR: [<full URL>](<full URL>)
```

Never a bare `#123`, and never leave the link out, even when the run ends with a warning.
Then:

- What the change does (a sentence or two), and which implementer tier did it.
- What the reviews changed: findings applied, findings rejected + why.
- Anything adjacent left alone deliberately, and any part of the issue a PR can't do.
- A board move that §1 or §6 couldn't make, and why.
- Screenshots: the generator thread's link and that the request is queued. If no request
  went out, why, and the request in a code block for the user to paste.

Leave out every line with nothing to say. Don't report an absent issue or board, a board move
that went through, the worktree's path, or how to pull the branch; the user knows the layout.
Leave the worktree on disk, and clean up with `wt rm <branch>` only if the user asks.

## 8. Screenshot follow-up

After the report, wait for the generator's reply. In T3 that's `t3_thread_wait` on the
request's run, then `t3_thread_read` for its last message. When the wait times out and
returns `next`, follow it and end the turn. Over `SendMessage`, the reply arrives as a
message. Never poll.

Check the reply against the diff. A screen that should have changed but showed no change, or
a difference the diff doesn't explain, means the request or the code is wrong. If it's the
request, send a corrected one the same way. If it's the code, tell the user rather than
fixing it unasked. Then give the user a short follow-up: the table is on the PR, plus any
unverified rows, layout problems, or rows the generator couldn't capture.

If the branch gets new commits that change rendered UI later in this session, send a new
request so the generator redoes the table.

## Stops

- The diff grows past what the issue needs, or turns into a refactor the issue didn't ask
  for → say so, get a go-ahead before continuing past §3.
- Push fails, `gh` unauthenticated, or verification fails for a reason unrelated to the change →
  stop with the actual output. Never open a PR on a tree you couldn't verify.
