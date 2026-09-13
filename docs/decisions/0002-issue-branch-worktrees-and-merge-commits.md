---
tags:
  - decision
status: accepted
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/pull/31
  - https://github.com/seletz/megastructure/issues/25
  - "[[0001-all-automation-through-mise]]"
---

# Issue-Branch Worktrees With Merge Commits

> [!summary]
> Every change starts from a GitHub issue, lives on a branch named after it
> in its own git worktree, and lands on `develop` through a pull request that
> is rebased and then merged with a merge commit. Commit messages follow the
> Conventional Commits style. Several issues can be worked on side by side,
> and the history shows which commits belong to which issue.

## Context

Work is planned as milestones, epics and sub-issues, and several sub-issues
are often in progress at once. Switching one checkout between branches is
slow and error-prone, and squash merges would hide the small, logical commits
inside each change.

## Decision

- One sub-issue, one branch `<issue>-<slug>` (for example
  `25-branch-protection`), one pull request against `develop`.
- Each branch is checked out in its own git worktree.
- Before merging, the branch is rebased onto `develop`; it is then merged with
  a merge commit. Squash merging is disabled and branches are deleted on
  merge.
- Commits use `type(scope): subject`, for example `fix(prototypes): ...`.
- `develop` is protected: the `check` status must pass on an up-to-date
  branch; no force pushes or deletion.

## Consequences

- `git log --first-parent develop` reads as a list of merged issues; the
  commits inside each merge stay linear and readable.
- The pull request body ends with `Closes #<issue>`, so issues close on merge.
- Rebasing before merge means a force push (`--force-with-lease`) on the
  feature branch, never on `develop`.

## Links

- #25, PR #31: merge settings, branch protection, CONTRIBUTING.md.
- CONTRIBUTING.md, sections "Branches and worktrees", "Commits" and "Pull
  requests".
- Related: [[0001-all-automation-through-mise]].
