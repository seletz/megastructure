# Contributing

## Planning: milestones, epics, sub-issues

Work is tracked in GitHub issues and grouped in three levels:

- **Milestones** (`gh` milestones, e.g. `0.1.0`) mark a releasable state.
  Each milestone has a plan document in `docs/` (e.g.
  [`docs/PLAN_0.1.0.md`](docs/PLAN_0.1.0.md)).
- **Epics** are issues that describe a larger feature. They carry no code of
  their own and are closed when all their sub-issues are done.
- **Sub-issues** hang off an epic (GitHub sub-issues) and are the unit of
  work: one sub-issue, one branch, one pull request. Every sub-issue is
  assigned to the milestone of its epic.

## Branches and worktrees

- `develop` is the integration branch. It is protected: the `check` status must
  pass on a branch that is up to date with `develop`, force pushes and
  deletion are blocked. Changes land through pull requests only; no approving
  review is required.
- Every change starts from an issue. Name the branch `<issue>-<slug>`, for
  example `25-branch-protection` for issue #25.
- Work on each branch in its own git worktree so several issues can be in
  progress side by side:

  ```sh
  git fetch origin
  git worktree add -b 25-branch-protection ../25-branch-protection origin/develop
  ```

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): subject
```

Common types are `feat`, `fix`, `refactor`, `docs`, `test`, `build`, `ci` and
`chore`. The scope names the affected area (`shader`, `camera`, `tools`,
`readme`, ...). Keep commits small and logical.

## Changelog

Every pull request that changes behaviour, controls, defaults, tooling or
documentation structure adds one line under `Unreleased` in
[`docs/CHANGELOG.md`](docs/CHANGELOG.md), in the matching Added, Changed,
Fixed or Docs list. Each entry is one short plain sentence ending with the pull
request number, for example `(#33)`. Newest items come first everywhere: the
new line goes at the top of its list, and the newest version section sits
directly under `Unreleased`. A release moves the `Unreleased` entries under a
new `<version> - <date>` heading and gets a git tag.

## Checks

All build, run and export automation goes through [mise](https://mise.jdx.dev/)
tasks in `mise.toml`. Before pushing, run:

```sh
mise run check
```

It must pass. CI runs the same task as the required `check` status.

GDScript files use tabs for indentation.

## Pull requests

1. Push the branch: `git push -u origin <issue>-<slug>`.
2. Open a pull request against `develop`:
   `gh pr create --base develop`. End the body with `Closes #<issue>`.
3. Before merging, rebase onto the current `develop` so the branch is up to
   date and the history stays linear inside the branch:

   ```sh
   git fetch origin
   git rebase origin/develop
   git push --force-with-lease
   ```

4. Merge with a merge commit once `check` is green:
   `gh pr merge --merge`. Squash merging is disabled; the branch is deleted
   automatically after the merge.
