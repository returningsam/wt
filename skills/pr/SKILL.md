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
uploading the screenshots as attachments on that PR with `--attach`, and the `gh pr edit`
calls on its body that §6 describes. Nothing else — no other branch, no force-push after the PR
exists, no merge, no writes to the original checkout (apart from the `git switch` and `git pull`
§5 runs there when the user has said it may), no other edit to the issue.

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
Backend, CLI, docs, config, and refactors with no rendered difference skip this section, and
neither the PR body nor the report mentions screenshots.

Check `gh --version` first. Uploading needs gh 2.99.0 or later. With an older gh, skip this
section, open the PR without the table, and tell the user in the report to upgrade gh.

**Enumerate from the diff.** Each distinct visual change gets one row. When the same change
repeats across many screens, show one representative screen and name the others in the row's
label. Cover the states the diff touches (hover or focus, error, empty, loading, a mobile
breakpoint, dark mode) when the change looks different there. Don't add states the change
doesn't affect. Some screens only appear after an interaction (a button press, an open modal,
a form error). List those from the diff and the PR description, with the steps to reach them.

**Capture from the main checkout.** The user runs the dev environment in `main/`. Never start
a dev server or app yourself. Work out both SHAs with commands, never from memory. The after
state is the worktree's `HEAD` (for a PR that's already open, `gh pr view <n> --json
headRefOid,baseRefName`). The before state is `git merge-base origin/<base> <after>`, run after
`git fetch origin <base>` so a stale ref doesn't move it. The only git command you run in
`main/` on your own is the read-only `git -C <main> rev-parse HEAD`. If the user has said you
may switch and pull there yourself, run the commands below. Otherwise ask the user
(`AskUserQuestion`) once per state that still needs capturing, give them the commands to run
in `main/`, and ask them to start the dev environment and name the URL or screen to capture
from:

```bash
git switch --detach <merge-base SHA>   # before
git switch <branch> && git pull        # after: <branch> tracks wt/<branch>
```

Before each capture run, check that `git -C <main> rev-parse HEAD` is the SHA you expect. A
dev server that's still rebuilding after a switch can serve the old build, so reload and retry
once when the first load fails or looks wrong.

**Use the repo's capture script when it has one.** Look for one in CLAUDE.md, AGENTS.md or
the task runner (for example `mise run shots`). It knows how to reach each screen and state,
which is the slow part to work out per PR. Otherwise use whatever browser tooling the session
has (Playwright, a browser or preview tool), and the session's device tools for an iOS or
Android simulator. In a browser, capture at the screen's native size with a device pixel
ratio of 1. A simulator's own screenshot size is fine as it is. Turn reduced motion on, pause
videos at their first frame, and wait for images and fonts. Then take a screenshot every
400ms or so and keep the first one that matches the shot before it, rather than waiting a
fixed time. Keep the viewport, data, and scroll position the same within each before/after
pair, and give every run fresh app state (a new session, account or location) when the app
keeps state between runs. Take the viewport, not a full-page scroll, unless the change is
page-wide.

**Cache the before shots by SHA.** Name each shot for its screen and state alone
(`center-12.1.png`, `settings-dark.png`) and keep the before set in
`~/.cache/wt-shots/<repo>/<merge-base SHA>/`. Several PRs from one base (a batch of branches
cut from the same `main`) share it. Capture the union of what they need once, and reuse it.
Whenever you add a screen to a SHA's folder, take it a second time into `<SHA>-noise/` as its
noise baseline. After that, a PR needs only its after run, in a fresh `mktemp -d` outside the
worktree.

**Confirm each change and make it visible with `wt shots-diff`.** It pairs each after shot
with the before shot of the same name, checks their sizes, counts differing pixels between
them and against the noise baseline, and writes the table's images and a draft of its rows
into `<out-dir>`. Make that another fresh `mktemp -d` outside the worktree, never in the PR
branch:

```bash
wt shots-diff --noise <cache>/<SHA>-noise <cache>/<SHA> <after-dir> <out-dir>
```

It prints one line per screen, and `no change` for a pair that matches. A screen whose noise
count isn't 0 has something moving (carousels, loading images, video, animation): settle it or
mask it and retake it, and if it stays noisy, list it in the report as unverified.
`noise=n/a` means the baseline has no copy of that screen yet, so take one. A screen only the
after set has gets "None" in its before cell. Before-only screens are left out, since the
cache holds other PRs' screens, so name a screen the PR really removes with
`--removed <screen>`. Every remaining
difference should match something in the diff. List one that doesn't in the report rather
than dropping it. A screen the diff should change that shows no change means the capture is
wrong (a stale build, the wrong state), so fix that before going on.

The PR table shrinks a full shot to about a quarter of its size, so a 20px shift renders as
5px and the pair looks identical. For each changed screen, `wt shots-diff` writes the full
shot and one 1:1 close-up per changed region, the same crop on both images, padded by 40px
and kept inside the image. It outlines any region under about 5% of the frame. It flags a
close-up that covers more than about a third of the frame, which means two changes or stray
noise. A screen with more than six regions (a layout shift moves everything below it) gets
no close-ups of its own. Close-ups are named `NN-<screen>-<k>-before-close.png`.

It also writes `sheet-<screen>.png`, each row's pair at its table width. Look at every sheet
once. Where a close-up is wrong, where a layout shift needs crops chosen by hand, or where a
position or alignment change needs a line at its reference (the container edge or the
centre the change moved against), write the close-ups in a crops file and run it again with
`--crops <file>`. All coordinates in the file are in the full frame, so there's no
subtracting:

```
center-15.3 672x380+28+620 -- Center 15.3, section headings
center-15.3 732x580+28+1300 line y=1621 -- Center 15.3, summary and checkout button
left-15.1 234x134+715+594 outline 154x54+755+634 -- Left 15.1, quantity stepper
```

A screen named in the file takes only those close-ups. If you can't tell a pair apart on its
sheet, it needs a tighter close-up or a guide. Drop the close-up rows that a full shot already
shows clearly at its width (a new screen, a large layout change).

If capture can't be done (the user can't run the dev environment now, or a state needs
credentials or seed data they don't have), don't stall. Open the PR without the missing rows
and list them in the report.

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

With screenshots, create the PR with the body minus its Screenshots section. Then write the
whole body to `body.md` in the `wt shots-diff` output directory, starting the table from its
`rows.md` with the labels rewritten, and publish it:

```bash
wt shots-attach <url> <out-dir>
```

It uploads every `./NN-…png` the body names as a GitHub user attachment, the same as dragging
it into the PR editor, 50 per gh call. On a private repo only people with repo access can see
them, and there's no branch to clean up. Uploads can't be deleted, so it uploads only what the
table names. It tries a failed file once more, drops the rows whose images never uploaded,
turns the images into `<img>` tags so their widths hold, and edits the PR body. List any rows
it dropped in the report. A failed upload doesn't count as a Stops failure. To add
screenshots to a PR that's already open, write `body.md` from its current body and run the
same command.

If `wt shots-attach` exits non-zero, it has put the PR body back as it was where it could, and
it says so. The files it uploaded stay uploaded, so fix the cause it names before running it
again rather than retrying straight away. If it still fails, leave the table out and list the
screenshots in the report.

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
- With screenshots from §5, add a `### Screenshots` table after the other sections and before
  the `Closes`/`Refs` line. It's the one exception to the terse-bullets rule. Open it with a
  sentence naming the before commit (the merge base) and the after commit (the branch head).
  Columns are a short label for the screen and state (naming the other screens when it's
  representative), Before, and After. A close-up row follows its full-shot row. A new screen
  puts "None" in the Before cell; a removed one puts "Removed" in the After cell. Write each
  image as a markdown image whose alt text is its width: 300 for a portrait full shot, 420 for
  a landscape one, and the crop's own width up to 440 for a close-up. `wt shots-diff` writes
  them that way, and `wt shots-attach` turns them into `<img>` tags with that width:

  ```
  Before is `f02ef8c` and after is `2feee98`.

  | Screen | Before | After |
  |---|---|---|
  | Settings, dark mode (same on Profile, Billing) | ![420](./01-settings-before.png) | ![420](./01-settings-after.png) |
  | Settings, close-up | ![440](./02-settings-1-before-close.png) | ![440](./02-settings-1-after-close.png) |
  ```

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
- Any screenshot §5 couldn't capture or upload, and why, including a gh too old for `--attach`.

Leave out every line with nothing to say. Don't report an absent issue or board, a board move
that went through, the worktree's path, or how to pull the branch; the user knows the layout.
Leave the worktree on disk, and clean up with `wt rm <branch>` only if the user asks.

## Stops

- The diff grows past what the issue needs, or turns into a refactor the issue didn't ask
  for → say so, get a go-ahead before continuing past §3.
- Push fails, `gh` unauthenticated, or verification fails for a reason unrelated to the change →
  stop with the actual output. Never open a PR on a tree you couldn't verify.
