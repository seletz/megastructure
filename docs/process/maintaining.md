---
tags:
  - process
  - tooling
status: current
---

# Maintaining

> [!summary]
> The day-to-day maintainer loop, from an issue to a merged pull request, is
> four mise tasks: `wt:new` creates the issue worktree, `pr:status` shows what
> is open and whether it can be merged, `pr:merge` rebases a pull request,
> waits for its check and merges it, and `wt:rm` removes the worktree again.
> Each task stops with a clear message instead of carrying on after a
> problem, and every task that changes something accepts `--dry-run`.

## Why tasks instead of shell chains

The same steps used to be typed as ad-hoc shell chains, and each chain hid a
failure at least once: a rebase conflict disappeared behind a pipe, a
worktree was removed while a rebase was still running in it, and CI was
polled for a commit that had never been pushed. The tasks run each step on
its own, never pipe away the output of git, refuse when state would be lost
and check that origin has exactly the commit whose check they wait for
([[0001-all-automation-through-mise]]).

## The loop

```sh
mise run wt:new 110 coordination-tasks   # prints the new worktree path
cd ~/.herdr/worktrees/megastructure/110-coordination-tasks
# work, commit, push, gh pr create --base develop
mise run pr:status                       # open PRs, merge state, checks
mise run pr:merge 111 --dry-run          # checks and commands only
mise run pr:merge 111                    # rebase, push, wait, merge, pull develop
mise run wt:rm 110-coordination-tasks    # from another checkout
```

## wt:new

`mise run wt:new <issue> <slug> [--base-dir DIR] [--herdr] [--dry-run]`

1. Refuses unless the issue is a number and the slug is lowercase words
   joined by `-`, and unless neither the branch `<issue>-<slug>` nor the
   target folder exists.
2. `git fetch origin develop` in the main checkout.
3. Creates the worktree `<base-dir>/<issue>-<slug>` on the new branch
   `<issue>-<slug>` from `origin/develop`. The base folder is `--base-dir`,
   else `$WT_BASE_DIR`, else `~/.herdr/worktrees/megastructure`. With
   `--herdr` (only inside Herdr, `HERDR_ENV=1`) it is created with
   `herdr worktree create` so it also opens as a Herdr workspace.
4. `mise trust` the new worktree's `mise.toml`, since mise trusts folders, not
   repositories.
5. Prints the path, and only the path, on stdout.

## wt:rm

`mise run wt:rm <branch> [--dry-run]`

1. Refuses to remove `develop`, a branch that does not exist, the branch of
   the main checkout, or the worktree the task is started from (run it from
   another checkout, so no shell is left in a deleted folder).
2. Refuses while the worktree has an unfinished rebase, merge, cherry-pick or
   revert, also when the rebase has detached its HEAD, or has uncommitted
   changes.
3. `git fetch --prune origin`, then refuses if the branch has commits that
   are on no branch of origin. A merged branch passes, because pull requests
   are merged with a merge commit and its commits are part of `develop`.
4. `git worktree remove`, `git branch -D`, `git worktree prune`.

## pr:status

`mise run pr:status` lists the open pull requests with their branch, their
merge state and each check's result, e.g. `CLEAN` with `check=success`, or
`BEHIND` when the branch must be rebased first. GitHub computes the merge
state lazily, so `UNKNOWN` right after a push only means "ask again in a few
seconds". It changes nothing.

## pr:merge

`mise run pr:merge <number> [--no-rebase] [--timeout SECONDS] [--dry-run]`

1. Reads the pull request with `gh pr view` and refuses unless it is open,
   targets `develop` and comes from this repository. Finds the worktree that
   has its branch checked out (required unless `--no-rebase`) and refuses if
   that worktree has an unfinished operation or uncommitted changes.
2. `git fetch origin develop <branch>`, and refuses if `origin/<branch>` has
   commits the worktree lacks, since a force push would drop them.
3. Rebases the worktree onto `origin/develop` unless it already contains it.
   On a conflict it runs `git rebase --abort` and stops, with git's output in
   full, so the branch is unchanged and the conflict can be resolved by hand.
4. `git push --force-with-lease` if the local branch differs from origin,
   then checks with `git ls-remote` that origin has exactly the local HEAD.
5. Waits for the `check` check-run of that HEAD commit through
   `gh api repos/{owner}/{repo}/commits/<sha>/check-runs`, every 15 seconds.
   No run yet counts as pending, because the workflow needs a moment to start
   after a push. It stops on any conclusion other than `success` and after
   `--timeout` seconds (default 900, 15 minutes). On a pull request that
   check is the quick tier, `mise run check`, which finishes in a few
   minutes including setup.
6. `gh pr merge --merge --match-head-commit <sha>`: a merge commit, and only
   if the pull request head is still the commit that passed. The branch on
   GitHub is deleted automatically.
7. Updates `develop` in the main checkout with `git pull --ff-only`. Local
   changes there are stashed first and applied again afterwards; the stash
   entry is addressed by its commit, never by position, because all
   worktrees share one stash stack. If they do not apply cleanly the task
   stops and names the stash. If the main checkout is on another branch,
   `git fetch origin develop:develop` moves `develop` without a checkout.
8. Prints the merge commit.

`--no-rebase` skips steps 3 and 4 and waits for the check of the head that is
already pushed. `--dry-run` runs the read-only steps (reading the pull
request, the refusals, the fetch, the current state of the check) and prints
every other command instead of running it.

The worktree stays after a merge; remove it with `wt:rm` once you are done.

## After merging: the full check

The pull request only ran the quick tier. The push of the merge commit to
`develop` runs `mise run check-full` (about 10 minutes), and the same runs
nightly. Look at it with `gh run list --workflow check.yml --branch develop`;
a failure there means a merged change broke a full-size statistical check, so
open an issue and fix it before merging more generator or solver work. For
such changes, run `mise run check-full` in the worktree before `pr:merge`.

## References

- [CONTRIBUTING.md](../../CONTRIBUTING.md): branches, worktrees, commits and
  pull requests.
- [[releasing]]: the release tasks, which follow the same style.
- [[tools-and-tasks]]: every task in the task table.
- [[0001-all-automation-through-mise]]: every step is a mise task.
- [mise.toml](../../mise.toml): the `wt:*` and `pr:*` tasks.
