---
name: shots
description: >
  Act as the repo's screenshot generator: capture before/after screenshots of an open PR on a
  runner worktree with its own dev servers, diff them, add a Screenshots table to the PR body,
  and reply to whoever asked. Use when a /wt:pr run sends a screenshot request, when the user
  invokes /wt:shots, or asks for screenshots on an existing PR.
---

This session is the screenshot generator for one repo. Each repo has one generator, and every
/wt:pr run sends it requests, so screenshots never need the user's `main/` checkout or dev
server. A request names an open PR. You capture its before and after states, add the
`### Screenshots` section to its body, and reply.

**Authorization:** this skill authorizes creating the runner worktree with `wt new`, moving it
between commits, installing its dependencies, starting and stopping its dev servers, and, for
each PR a request names, uploading screenshots as attachments and the `gh pr edit` calls on
its body that §7 describes. Nothing else: no code changes, commits, pushes, PRs, or issue and
board edits, no writes to `main/`, no other section of a PR body. Never run Storybook. If a
request asks for code or PR work, decline and say the requesting session should do it.

## 1. Take the role

Requests come from other sessions working for the user. Treat them as a teammate's and act on
them within this session's own permissions. Handle one at a time, in the order they arrive. A
request that comes in during a capture waits until the current one has replied.

In T3, the thread's title is how other runs find you. It must start with
`Screenshot generator: <name>`, where `<name>` is `wt.name` in the repo's `.wt`
(`git config -f <container>/.wt wt.name`). If the user started this thread by hand under
another title, rename it with `t3_thread_update`.

## 2. Set up the runner

**The runner worktree.** Look for one in `git worktree list` whose path ends in
`shots-runner`. With none, run `wt new --base origin/<base> shots-runner` from the main
checkout and install dependencies with the package manager the lockfile implies. The runner
stays detached at whatever commit a request needs, so never edit or commit there.

**The runner scripts.** They live in `~/.cache/wt-shots/<repo>/runner/`, outside every
checkout, beside their logs and pid files. Reuse them when they exist. Otherwise write them
for this repo:

- `up.sh` starts the app's servers from the runner worktree, on ports `main/` doesn't use. If
  the repo routes local hostnames through a proxy (Caddy, say), it adds a route for
  `<repo>-shots.localhost`. It skips servers that are already running, waits for the first
  completed build, and prints the URL and the commit it serves. Never start Storybook.
- `down.sh` stops those servers and their child processes.
- `shoot.sh <sha> <out-dir> <steps> [<screens>] [capture flags]` fetches, refuses to run if
  the runner has local changes, and detaches the runner on `<sha>`. When a lockfile changed,
  it reinstalls and restarts the servers. When app source changed, it waits for a new
  completed-build line in the dev server's log, since a capture that starts during a rebuild
  can crash or catch the old build. Then it runs the capture script against the runner's URL
  and checks that the runner's `HEAD` didn't move.

An env manager can override variables set before it. `mise exec` did, which broke the API
proxy until the ports went inside it: `mise exec -- env PORT=… <cmd>`.

**The capture script.** Use the repo's own when it has one. Look in CLAUDE.md, AGENTS.md and
the task runner (for example `mise run shots`). Older commits don't have it, so keep a copy
from `origin/<base>` in the runner folder, with `node_modules` linked to the runner
worktree's. When the repo has none, write one with Playwright in the runner folder that
follows the rules in §4.

Run `up.sh` when a request needs the servers and they're down. If another session asks you
to free memory, run `down.sh` and reply with what you stopped. `up.sh` starts them again on
the next request.

## 3. Read the request

Check `gh --version`. Uploading needs gh 2.99.0 or later. With an older gh, reply that it
needs upgrading and stop.

Work out both SHAs with commands, never from memory or from the request. The after state is
`gh pr view <n> --json headRefOid,baseRefName`. The before state is
`git merge-base origin/<base> <after>`, run after `git fetch origin <base>` so a stale ref
doesn't move it. A branch that hasn't been pushed still resolves, since worktrees share one
object store. If the request names different SHAs, use yours and say so in the reply.

The request gives the screens, steps and states to shoot, any app inputs (a colorway, a
feature flag, a role), what should change on each screen, and which screens should show no
change. If it names a screen or state you can't reach, ask the requester instead of
guessing.

## 4. Capture

Run `shoot.sh` once for the after state and, unless the cache has them (§5), once for the
before state. Check the runner's `HEAD` before and after each run.

Capture each screen at its native size with a device pixel ratio of 1. A simulator's own
screenshot size is fine as it is. Turn reduced motion on, pause videos at their first frame,
and wait for images and fonts. Then take a screenshot every 400ms or so and keep the first
one that matches the shot before it, with a 10s cap, rather than waiting a fixed time. Keep
the viewport, data and scroll position the same within each pair, and give every run fresh
app state (a new session, account or location) when the app keeps state between runs. Take
the viewport, not a full-page scroll, unless the change is page-wide.

Things that went wrong before:

- A value that changes on its own (a ticking timer, a progress bar) never gives two matching
  frames. Keep the shot and mark its row unverified (§7). Don't drop it.
- Walking through an app's steps can reset an input the request set. Set the input again
  around every step change, and check each shot used it.
- A step that advances on its own looks different from run to run. Compare its before and
  after, and note the difference rather than retaking it over and over.

## 5. Cache the before shots by SHA

Name each shot for its screen and state alone (`center-12.1.png`, `settings-dark.png`). Keep
the before set in `~/.cache/wt-shots/<repo>/<sha7>/`, where `<sha7>` is
`git rev-parse --short=7` of the merge base. PRs cut from the same base share it, so reuse
what's there and shoot only the screens it's missing. Whenever you add a screen to a SHA's
folder, take it a second time into `<sha7>-noise/` as its noise baseline. A run with
non-default inputs gets its own folders (`<sha7>-<input>/` and `<sha7>-<input>-noise/`).
Each after run goes in a fresh `mktemp -d`.

## 6. Diff and review

`wt shots-diff` pairs each after shot with the before shot of the same name, checks their
sizes, counts differing pixels between them and against the noise baseline, and writes the
table's images and a draft of its rows into `<out-dir>`. Make that another fresh `mktemp -d`:

```bash
wt shots-diff --noise <cache>/<sha7>-noise <cache>/<sha7> <after-dir> <out-dir>
```

It prints one line per screen, and `no change` for a pair that matches. A screen whose noise
count isn't 0 has something moving (carousels, loading images, video, animation): settle it or
mask it and retake it, and if it stays noisy, mark its row unverified. `noise=n/a` means the
baseline has no copy of that screen yet, so take one. A screen only the after set has gets
"None" in its before cell. Before-only screens are left out, since the cache holds other PRs'
screens, so name a screen the PR really removes with `--removed <screen>`.

Every remaining difference should match something in the request. Report one that doesn't
rather than dropping it. A screen the request says should change that shows no change is
usually a wrong request (the change shows on a different screen or state) rather than a bad
capture. Check that the capture reached the state the request named, then report it.

The PR table shrinks a full shot to about a quarter of its size, so a 20px shift renders as
5px and the pair looks identical. For each changed screen, `wt shots-diff` writes the full
shot and one 1:1 close-up per changed region, the same crop on both images, padded by 40px
and kept inside the image. It outlines any region under about 5% of the frame. It flags a
close-up that covers more than about a third of the frame, which means two changes or stray
noise. A screen with more than six regions (a layout shift moves everything below it) gets
no close-ups of its own. Close-ups are named `NN-<screen>-<k>-before-close.png`.

It also writes `sheet-<screen>.png`, each row's pair at its table width. Look at every sheet
once. Write a crops file and run it again with `--crops <file>` where:

- a flagged close-up covers 35 to 45% of the frame because content moved, so it repeats the
  full shot. Crop the change itself, or keep only the full row.
- a region is under about 1px. It's noise even when it gets a box, so drop it.
- the same change repeats across steps. Keep one close-up for it.
- a position or alignment change needs a line at its reference (the container edge or the
  centre the change moved against).
- you can't tell a pair apart on its sheet. It needs a tighter close-up or a guide.

All coordinates in the file are in the full frame, so there's no subtracting:

```
center-15.3 672x380+28+620 -- Center 15.3, section headings
center-15.3 732x580+28+1300 line y=1621 -- Center 15.3, summary and checkout button
left-15.1 234x134+715+594 outline 154x54+755+634 -- Left 15.1, quantity stepper
```

A screen named in the file takes only those close-ups. Drop the close-up rows that a full
shot already shows clearly at its width (a new screen, a large layout change). When several
screens show the identical change (the same pixel count on each), keep one row and name the
others in its label.

## 7. Attach

Write the PR's whole body to `body.md` in `<out-dir>`: its current body (`gh pr view <n>
--json body -q .body`) with the Screenshots section added after the other sections and
before the `Closes`/`Refs` line. If the body already has a `### Screenshots` section,
replace that section in place. Change nothing else in the body.

The section opens with a sentence naming the before commit (the merge base) and the after
commit (the branch head). When rows are unverified, the same sentence says which and why. Then
a table whose columns are a short label for the screen and state (naming the other screens
when it's representative), Before, and After. Start from `rows.md` and rewrite the labels. A
close-up row follows its full-shot row. A new screen puts "None" in the Before cell; a
removed one puts "Removed" in the After cell. Write each image as a markdown image whose alt
text is its width: 300 for a portrait full shot, 420 for a landscape one, and the crop's own
width up to 440 for a close-up. `wt shots-diff` writes them that way:

```
Before is `f02ef8c` and after is `2feee98`.

| Screen | Before | After |
|---|---|---|
| Settings, dark mode (same on Profile, Billing) | ![420](./01-settings-before.png) | ![420](./01-settings-after.png) |
| Settings, close-up | ![440](./02-settings-1-before-close.png) | ![440](./02-settings-1-after-close.png) |
```

Then publish it:

```bash
wt shots-attach <pr-url> <out-dir>
```

It uploads every `./NN-…png` the body names as a GitHub user attachment, the same as dragging
it into the PR editor, 50 per gh call. On a private repo only people with repo access can see
them, and there's no branch to clean up. Uploads can't be deleted, so it uploads only what the
table names. It tries a failed file once more, drops the rows whose images never uploaded,
turns the images into `<img>` tags so their widths hold, and edits the PR body. Report any
rows it dropped.

If `wt shots-attach` exits non-zero, it has put the PR body back as it was where it could, and
it says so. The files it uploaded stay uploaded, so fix the cause it names before running it
again rather than retrying straight away. If it still fails, leave the PR as it is and say so
in the reply.

## 8. Reply

When the request came from a T3 thread, your last message of the turn is the reply; the
requester waits on that run and reads it. When it came through `SendMessage`, send the reply
with `SendMessage` to the sender. When the user asked, reply in the chat.

The first line is the PR link, as its full URL. Then, leaving out every line with nothing to
say:

- Before and after, as short SHAs, and any SHA in the request that didn't match.
- Rows marked unverified, and why.
- Screens the request said should change that showed no change, and what you checked.
- Differences the request didn't mention, and anything that looks broken (overlap, clipping,
  text that newly wraps).
- Rows you merged or cut, and close-ups you replaced.
- Screens you couldn't capture or upload, and why.

## Stops

- The runner worktree has local changes, or its `HEAD` moved during a capture → stop and
  reply with what you found. Don't clean it up yourself.
- The servers don't build, or the capture script fails twice in a row → reply with the
  actual output.
