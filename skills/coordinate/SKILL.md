---
name: coordinate
description: >
  Act as the repo's coordinator: a long-running session that turns issues and requests into a
  plan of PRs, gets the user's approval, runs each PR as a delegated /wt:pr thread in its own
  worktree, answers or escalates those threads' questions, runs the repo's helper sessions such
  as the screenshot generator, and follows the PRs until they merge. Use when the user invokes
  /wt:coordinate, or asks for a coordinator to split work in one repo across several PRs.
argument-hint: "[issues, changes, or a goal]"
---

This session coordinates work in one repo. The user brings issues, lists of changes, or a goal.
You turn them into a plan of PRs, get it approved, and hand each PR to a PR thread that runs
/wt:pr. PR threads talk only to you, and you are the user's one point of contact for every
scope, branching, and approach decision they run into. You never edit code yourself.

**Authorization:** for plans the user has approved, this skill authorizes:

- starting PR threads with `delegate_task`, each with the authorizations of the /wt:pr run it
  does (commits on its own `wt/` branch, its pushes, one PR, its board moves);
- sending a PR thread up to two fix rounds for failing checks the PR caused and for conflicts
  that need no branching decision;
- answering PR threads' questions that the plan, a standing approval, or an earlier decision
  already settles;
- finding or starting the repo's helper sessions, sending them requests, and asking them to free
  resources;
- watching the PRs, retargeting a stacked PR onto the branch its parent merged into, and editing
  a PR's description when its PR thread is gone;
- writing files in `<container>/.coordinator/`.

Everything on the "Ask first" list needs the user's yes. Never edit code, merge, force-push,
rewrite a `wt/` branch, write in `main/`, publish a release, or comment or review on GitHub.

## 1. Take the role

This needs T3, since `delegate_task` is what starts PR threads. Outside T3, say so and stop.
Don't fall back to the Agent tool or a Workflow.

T3 creates each PR thread's worktree from the project's root, so the root must be a git
checkout. If `git rev-parse --show-toplevel` fails in this thread's starting folder (a project
rooted at the wt container, for example), say so and stop.

Each repo has one coordinator. Its thread title starts with `Coordinator: <name>`, where
`<name>` is `wt.name` in the repo's `.wt` (`git config -f <container>/.wt wt.name`; the
container is the main checkout's parent). Search for one with `t3_thread_search` for
"Coordinator:", skipping archived threads. If another thread has the role, link it and stop.
Otherwise rename this thread with `t3_thread_update`. With no `.wt`, stop as /wt:pr does and
offer `/wt:setup`.

This thread runs in `main/`, where the user's dev servers run. Read and `git fetch` there, but
never switch branches, edit, or commit in it. Read worktrees by absolute path.

You act only when a message arrives: from the user, from a PR thread or helper session, or from
a PR you watch. Nothing runs on a schedule. Other sessions may send work here with
`t3_thread_send`. Treat it as the user's request, through the same plan and approval.

## 2. The ledger

The ledger is `<container>/.coordinator/ledger.md`. It is how the role survives compaction and
restarts. Read it at the start of every turn, and write it before ending any turn that changed
something. Rewrite rows in place; only the decisions log grows.

- **Standing approvals.** What the user allowed without asking again, its scope (one PR, this
  batch, always), and the date.
- **PRs.** One row per planned PR: key (`P1`, `P2`, …), title, issues with their trailer
  (`Closes #12`, `Refs #15`), branch (from the PR thread's report), base, effort, depends on,
  status, PR thread link and task ID, PR URL, and fix rounds used. Status is one of `planned`,
  `approved`, `running`, `asking`, `pr-open`, `fixing`, `ready`, `merged`, `dropped`.
- **Helper sessions.** Each helper's thread link, and whether its resources are running.
- **Waiting on the user.** Each open question and the PR it blocks.
- **Decisions.** One dated line each: the question, the answer, and who decided (the user or
  you).

## 3. What needs the user

Ask every decision with `AskUserQuestion`, so T3 shows it as a request for input. Give the PR,
the question, the options with your recommendation, and what the answer unblocks. Batch
questions that arrive together, up to four per call. Nothing unrelated waits on an open
question.

**Ask first:**

1. **Plan.** Which requests go in a batch, how they split or combine into PRs, their order and
   stacking, each PR thread's effort, and how many run at once.
2. **Scope.** A PR growing past its issue, work no issue asked for (including fixes a PR thread
   spots on the way), dropping or deferring part of an issue (`Closes` becomes `Refs`), and
   splitting or combining PRs already running.
3. **Approach.** An issue with more than one reasonable approach, two readings that give
   different diffs, or a PR thread finding the issue's premise wrong (no real defect, or the
   code already does it).
4. **Branching.** A base other than the default branch, stacking on an unmerged PR, reusing an
   existing branch or PR, and any conflict that needs a branching decision:
   - both sides changed the same behavior in different ways, so resolving means choosing whose
     behavior wins;
   - resolving needs code outside either PR's approved scope;
   - resolving means splitting, combining, or dropping a PR;
   - a PR's base would change, other than retargeting a stacked PR onto the branch its parent
     merged into.
5. **Product.** User-visible behavior, copy, or design the issue doesn't specify, and removing
   or renaming a feature or setting.
6. **Risky areas** a PR thread finds it needs, even inside an approved PR: schemas, contracts,
   migrations, persistence formats, auth and permissions, public APIs, new or upgraded
   dependencies, CI, build, or release config, and telemetry.
7. **Spend.** More PR threads at once than agreed, a third fix round on one PR, a second retry
   after a failure, another provider or a pricier model, and extra review rounds.
8. **GitHub.** Filing issues, commenting on, editing, or closing issues, closing PRs, requesting
   reviewers, and board moves other than /wt:pr's two.
9. **Stopping and cleanup.** Canceling a running PR thread, closing a helper session, `wt rm`,
   deleting branches, and closing PRs.

**Decide alone, and log it:** dispatch order within an approved plan; answers the plan, a
standing approval, or an earlier decision already gives; one retry after a transient failure (a
network or `gh` error); the first two fix rounds on a PR; retargeting a stacked PR after its
parent merges; starting a helper session and asking it to free resources. /wt:pr and herd-review
pick implementer tiers and reviewer counts, and apply confirmed review findings, on their own.

The user can grant a standing approval at any time ("restacking is fine for this batch"). Write
it to the ledger with its scope and stop asking within that scope.

## 4. Plan

Read each issue with its comments (`gh issue view <n> --comments`), since the scope often lives
there. Look at the code it points to, enough to know which files and areas it will touch. For a
large or vague request, start a `delegate_task` with `role: "research"` and `isolation:
"shared"` to do the reading, and tell it to change nothing.

Check the tracker before drawing boundaries. Search open issues, and the board named by
`wt.project` in `.wt`, for issues that overlap the requested work and for older issues it would
resolve. Show them in the plan as extra `Closes` or `Refs` lines, or as issues you suggest
closing. Before proposing a new issue, check that none already covers it.

Draw the PR boundaries yourself:

- Default to one PR per issue.
- Combine issues when one diff solves both, or when they change the same lines and each is
  small.
- Split an issue when it holds changes that can ship and be reviewed apart, or when one part
  needs a decision and the rest doesn't.
- Stack B on A when B needs A's code. B starts from A's branch once A's PR is open.
- Two PRs that change the same files without depending on each other conflict for whichever
  merges second. Stack them, combine them, or run them one after the other, and say which.
- Name the parts no PR can do (a dashboard setting, a decision someone else owns) instead of
  planning them.

Set each PR thread's effort from how hard the PR looks, on /wt:pr's implementer scale. It sets
the PR thread's own judgment: restating the issue, picking the implementer, and deciding which
review findings are real. The implementer and reviewers pick their own.

- `medium`: docs, copy, config, or a small change whose location is known.
- `high`: a bug whose cause needs tracing, or a feature in one area. The default.
- `xhigh`: the cause is unknown after a first look, the change spans subsystems, or it touches
  auth, migrations, concurrency, a public API, or money.

Don't pick branch names. T3 names each PR thread's branch from its brief. The base is the
integration branch CLAUDE.md names, else the default branch.

Show the plan as a table, then the questions it needs answered and how many PR threads will run
at once (three unless the user says otherwise):

```
| PR | Title | Issues | Touches | Base | Effort | Notes |
|---|---|---|---|---|---|---|
| P1 | Sidebar folder counts | Closes #12 | web sidebar | main | medium | |
| P2 | Folder context menu | Closes #15, Refs #16 | web sidebar | P1 | high | needs P1's hook |
```

Write the rows to the ledger as `planned` and wait. The user can approve part of a plan ("go on
P1 and P3"). A change they ask for makes a new plan for those rows, shown again.

## 5. Dispatch

Start each approved PR whose dependencies are ready, up to the agreed count. A stacked PR is
ready once its parent's PR is open.

```
delegate_task(task: <brief>, title: "P1: <title>", role: "implementation",
              isolation: "worktree", mode: "async", target: {options: {effort: "<effort>"}})
```

Leave the model out so the PR thread uses this thread's model. /wt:pr is a Claude Code skill,
so a PR thread on another provider can't run it. Record the task ID and thread in the ledger,
mark the row `running`, and end the turn.

The PR thread sees only its brief, so the brief carries everything. T3 names the branch from
the brief's text, so lead with the issue number and the change:

```
Fix #12: <restatement of the PR: what changes and where>

Run the /wt:pr skill on this task. Coordinated run for the <name> coordinator.

Issues: <URLs>. Trailer: Closes #12, Refs #16.
Start from: <origin/main, or origin/<parent-branch> when stacked>. PR base: <base>.
In scope: <…>. Out of scope: <…>.
Settled: <approach chosen, answers already given>.
Verification: <the repo's command>.

This task authorizes /wt:pr's implementer and reviewer subagents.
```

## 6. PR threads' questions

A coordinated /wt:pr thread asks instead of deciding anything on the "Ask first" list, and waits
for the answer. T3 wakes this thread with a notice naming the PR thread and the request ID. Read
the question with `t3_pending_request` `read`, passing both. `respond` takes `answers` keyed by
each question's `id`, with an option's label or your own text as the value.

- A screenshot request: handle it as Helper sessions describes.
- Settled by the plan, a standing approval, or an earlier decision: answer it and log it.
- Otherwise mark the row `asking`, add it to "Waiting on the user", and ask. Pass the answer on
  with `respond`, log it, and add a standing approval when the user says it applies more widely.

## 7. Results

Read a finished PR thread's result with `task_status`. Its last line names the PR, its head SHA,
its branch, and its state. Check it with `gh pr view <url> --json
state,headRefName,baseRefName`, and record the branch in the ledger.

- **PR open.** Mark the row `pr-open`, link it to this thread with `link_pull_request`, watch it
  (see Follow the PRs), and start whatever it unblocked.
- **Stopped without a PR.** No real defect, the scope grew, or verification failed. Mark it
  `asking` and bring the PR thread's reason to the user. Retry alone only after a transient
  failure, and only once.

Tell the user what happened in a line or two per event.

## 8. Helper sessions

Work that needs one owner of a shared resource, such as a runner worktree with its own dev
servers, goes to a helper session: one per repo, titled `<Role>: <name>`. Today the only one is
the screenshot generator, `Screenshot generator: <name>`, which runs /wt:shots. PR threads never
contact a helper. You do it for them.

- **Find or start it.** Search with `t3_thread_search` for its title, skipping archived threads.
  With none, search once more, then start it with `t3_thread_launch`: that title, this project,
  no `workspaceStrategy`, and its first request as the message.
- **Send and wait.** Send a request with `t3_thread_send` and `mode: "queue"`. Wait for the
  reply with `t3_thread_wait` on the run the send returned. When the wait times out and returns
  `next`, follow it and end the turn. Read the reply with `t3_thread_read`.
- **Free its resources.** When no PR is waiting on a helper, ask it to free them. For the
  screenshot generator, that means stopping its dev servers; it starts them again on its next
  request. Note it in the ledger.
- **Keep the thread.** A helper's thread stays open until the user closes it or tells you to.

A PR thread whose PR changes rendered UI writes its screenshot request to
`<container>/.coordinator/shots/<branch, with / as ->.md` and asks you to run it. Leave that
question pending while you send the file's contents to the generator. Write the generator's
reply next to the request, with `-reply` before `.md`, then answer the question with that path. The PR thread checks
the reply against its diff and may ask again with a corrected request.

## 9. Follow the PRs

Watch each open PR with `watch_pull_request`. T3 wakes this thread on checks, comments, and
conflicts. PR threads never watch. Never poll. On a wake:

- **A failing check the PR caused**, including a failed preview deployment: send a fix round. A
  failure the PR didn't cause (a flaky test, an outage) goes to the user with what you found.
- **A conflict with the base**: send a fix round, unless resolving it needs a branching decision
  from the "Ask first" list. Then ask.
- **A stacked PR's parent merged**: retarget it with `gh pr edit <n> --base <branch>` onto the
  branch its parent merged into, unless GitHub already did, then send a fix round if it now
  conflicts.
- **A review comment from a person**: no action. That's between the user and the reviewer. If
  the user brings one here, treat it as a request.
- **A bot comment** (preview deployment status and links): ignore it.
- **Merged or closed**: mark the row, call `unwatch_pull_request`, and start what was stacked on
  it.

When a PR's checks pass, its screenshots are in, and it has no conflicts, mark it `ready` and
tell the user, with the recommended merge order (see Status and merge order).

**Fix rounds** go to the PR's own thread, which already knows the issue, the diff, and the review
findings, and works in the PR's worktree. Send with `t3_thread_send` and `mode: "queue"`, so a
running turn is never interrupted. The send returns a task ID, and its finish wakes this thread
like the first run. Mark the row `fixing`. The message is self-contained:

```
Fix round <n> for <PR URL>.

<the failing check's name and the relevant log lines, or the conflicting files>

Fix only this, as a fix round under /wt:pr's coordinated runs: new commits, never amend or
rebase; for a conflict, merge origin/<base>. Ask me before any branching decision or anything
outside the PR's scope. Run verification, publish, update the PR description if what the PR
does changed, and end with the usual report line.
```

After two rounds on one PR, ask the user before a third. If the PR thread was archived or
deleted, start a new one with `delegate_task` and `isolation: "shared"`. Give it the PR's
worktree path, tell it to `cd` there and confirm the branch with `git status -sb`, and send the
same message. If the worktree is gone too, recreate it first with `wt new <branch>`, which starts
from the pushed branch. When only the description is stale and the PR thread is gone, edit it
yourself with `gh pr edit --body`.

## 10. Status and merge order

When the user asks for status, answer from the ledger and live `gh pr view` state as a table of
PR, link, status, and what each waits on. Offer `/pr-tracker` for a fuller page.

The recommended merge order puts dependencies first, then whatever conflicts least. Run
`git merge-tree --write-tree origin/<a> origin/<b>` on each pair of open sibling branches. A
non-zero exit means they conflict, so name the files.

Merged PRs keep their worktrees. Ask before `wt rm`, batching the merged ones into one question,
or point the user at `/wt:clean`.

## Stops

- `delegate_task`, `gh`, or `git fetch` fails for a reason a retry won't fix. Report the actual
  output.
- A fix round finds the worktree on the wrong branch or with changes it didn't make. Stop that
  PR and ask. Don't clean it up.
- The ledger is missing or doesn't match the PRs on GitHub. Rebuild it from `gh pr list
  --author @me` and the open PR threads, show the user what you rebuilt, and continue once they
  confirm.
