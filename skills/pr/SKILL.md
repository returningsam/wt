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
one push of the orphan `screenshots/<branch>` branch (§5). Nothing else — no other branch, no
force-push after the PR exists, no merge, no writes to the original checkout, no other edit to
the issue.

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
(`git branch -r --sort=-committerdate | grep -v /screenshots/ | head -20`) —
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

**Enumerate from the diff.** Each distinct visual change gets one row. When the same change
repeats across many screens, show one representative screen and name the others in the row's
label. Cover the states the diff touches (hover or focus, error, empty, loading, a mobile
breakpoint, dark mode) when the change looks different there. Don't add states the change
doesn't affect. Some screens only appear after an interaction (a button press, an open modal,
a form error). List those from the diff and the PR description, with the steps to reach them.

**Capture from the main checkout.** The user runs the dev environment in `main/`. Never start
a dev server or app yourself, and never run git in `main/`. Ask the user (`AskUserQuestion`)
twice, once per state. Each time, give them the commands to run in `main/`, ask them to start
the dev environment, and ask for the URL or screen to capture from:

```bash
git switch --detach <merge-base SHA>   # before: git merge-base origin/<base> HEAD
git switch <branch> && git pull        # after: <branch> tracks wt/<branch>
```

Take every before shot, then ask for the after state. Use whatever browser tooling the
session has (Playwright, a browser or preview tool), and the session's device tools for an
iOS or Android simulator. Capture at the screen's native size with a device pixel ratio of
1, reduced motion on, and wait for images, fonts, and animations to settle before each shot.
Keep the viewport, data, and scroll position the same within each before/after pair. Take
the viewport, not a full-page scroll, unless the change is page-wide.

Save the PNGs in a fresh directory outside the worktree (`mktemp -d`) that holds only these
shots, never in the PR branch, as `NN-<slug>-before.png` and `NN-<slug>-after.png`.

**Confirm each change with a pixel diff.** Compare every pair with ImageMagick:

```bash
magick compare -metric AE -fuzz 3% before.png after.png null: 2>&1   # differing pixels
```

`magick compare` exits 1 when the images differ, so don't chain it with `&&`.

Carousels, loading images, video, and animation also produce differences. Take the before set
twice, and treat any screen that differs between those two runs as noise. Every remaining
difference should match something in the diff. Report one that doesn't, rather than dropping
it. A screen the diff should change that shows no difference means the capture is wrong (a
stale build, the wrong state), so fix that before going on.

**Make each change visible at table size.** The PR table shrinks images to about a quarter of
their size, so a 20px shift renders as 5px and the pair looks identical. Give every row a
close-up, unless the change is obvious in the full shot at its embedded width (a new screen,
a large layout change). A close-up crops the pixel-diff box at 1:1 with at least 40px of
padding, using the same crop on both images. When the change is a position or alignment,
widen the crop to include the reference it moved against, such as the container edge or the
centre.

```bash
magick compare -fuzz 3% -compose src -highlight-color white -lowlight-color black \
  before.png after.png mask.png
magick mask.png -fuzz 10% -format '%@' info:   # diff box as WxH+X+Y
magick before.png -crop <W>x<H>+<X>+<Y> +repage NN-<slug>-before-close.png
```

Annotate a subtle change, meaning the diff box covers under about 5% of the frame or the
change moves under about 10px at the embedded width. Draw the same guide on both close-ups: a
line at the reference for a position change, an outline around the diff box otherwise.

```bash
magick in.png -stroke '#ff2d55' -strokewidth 2 -fill none -draw 'line 540,0 540,520' out.png
magick in.png -stroke '#ff2d55' -strokewidth 2 -fill none -draw 'rectangle 10,10 300,80' out.png
```

Before pushing, resize each pair to its embedded width (`magick in.png -resize 420x out.png`)
and look at both images. If you can't tell them apart, the row needs a tighter close-up or an
annotation.

**Push them to an orphan branch.** Git plumbing builds the commit without touching the
worktree. When the branch already exists from an earlier pass, the new commit builds on top
of it, so the push stays a fast-forward and older links keep working:

```bash
dir=<the screenshots dir>
ref=refs/heads/screenshots/<branch>
tree=$(for f in "$dir"/*.png; do
  printf '100644 blob %s\t%s\n' "$(git hash-object -w "$f")" "$(basename "$f")"
done | git mktree)
git fetch -q origin "+${ref}:refs/remotes/origin/screenshots/<branch>" 2>/dev/null
parent=$(git rev-parse -q --verify refs/remotes/origin/screenshots/<branch>)
commit=$(git commit-tree "$tree" ${parent:+-p} $parent -m "screenshots for <branch> [skip ci]")
git ls-tree --name-only "$commit"   # must list every PNG before you push
git push origin "${commit}:${ref}"
```

Keep the braces in `${commit}`; zsh reads `$commit:r` as a modifier. `[skip ci]` keeps push
workflows from running on a branch with no code. Each image's URL is
`https://github.com/<owner>/<repo>/raw/<commit>/<file>`, with `<owner>/<repo>` from
`gh repo view --json nameWithOwner -q .nameWithOwner`. Pinning to the commit SHA keeps the
links stable, and `/raw/` URLs render for logged-in viewers of a private repo. Leave the
branch in place after merge, since the PR's images point at it.

If capture can't be done (the user can't run the dev environment now, or a state needs
credentials or seed data they don't have), don't stall. Open the PR without the missing rows
and list them in the report. If the screenshots push fails, open the PR without the table and
report that too. It doesn't count as a Stops failure.

## 6. Open the PR

```bash
git push origin HEAD:<branch>   # wt/<branch> → origin/<branch>; always name the target
gh pr create --head <branch> --base <base> --assignee @me --title "…" --body "…"
```

`gh pr create` prints the PR URL as its last line. Keep it for §7; if it got lost, recover it
with `gh pr view <branch> --json url -q .url`.

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
  the `Closes`/`Refs` line. It's the one exception to the terse-bullets rule. Open it with one
  line naming the before and after commits. Columns are a short label for the screen and state
  (naming the other screens when it's representative), Before, and After. A close-up row
  follows its full-shot row. A new screen puts "None" in the Before cell; a removed one puts
  "Removed" in the After cell. Give every image an explicit width: 300 for a portrait full
  shot, 420 for a landscape one, and at least 440 for a close-up (its natural width when
  that's under about 880):

  ```
  Before `f02ef8c`, after `2feee98`.

  | Screen | Before | After |
  |---|---|---|
  | Settings, dark mode (same on Profile, Billing) | <img src="url" width="420"> | <img src="url" width="420"> |
  | Settings, close-up | <img src="url" width="440"> | <img src="url" width="440"> |
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
- Any screenshot §5 couldn't capture or push, and why.

Leave out every line with nothing to say. Don't report an absent issue or board, a board move
that went through, the worktree's path, or how to pull the branch; the user knows the layout.
Leave the worktree on disk, and clean up with `wt rm <branch>` only if the user asks.

## Stops

- The diff grows past what the issue needs, or turns into a refactor the issue didn't ask
  for → say so, get a go-ahead before continuing past §3.
- Push fails, `gh` unauthenticated, or verification fails for a reason unrelated to the change →
  stop with the actual output. Never open a PR on a tree you couldn't verify.
