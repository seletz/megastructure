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
  mise run wt:new 25 branch-protection   # prints the worktree path
  ```

  It fetches and creates the branch `25-branch-protection` from
  `origin/develop` in `~/.herdr/worktrees/megastructure/25-branch-protection`
  (`--base-dir` or `$WT_BASE_DIR` to change the folder). After the merge,
  remove it from another checkout with `mise run wt:rm 25-branch-protection`,
  which refuses while anything in it would be lost.

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
new `<version> - <date>` heading and gets a git tag (see Releases).

## Checks

All build, run and export automation goes through [mise](https://mise.jdx.dev/)
tasks in `mise.toml`. Before pushing, run:

```sh
mise run check
```

It must pass. CI runs the same task as the required `check` status.

GDScript files use tabs for indentation.

Run Godot with `--headless` for everything that does not need pixels. To get
an image of a scene, use `mise run shot <scene> <out.png>` (seed, pose,
params and resolution as flags); it renders under `xvfb-run` so no window
opens. Workers and agents never write ad-hoc capture scripts or open a Godot
window. Details in
[`docs/process/screenshots.md`](docs/process/screenshots.md).

## Releases

**`develop` always carries the NEXT version.** The version is `config/version`
in `project.godot` (semantic versioning). A release tags the version that is
already there and immediately bumps `develop` to the next patch, so at no time
does `develop` sit on an already released version. A release never edits the
version before tagging.

- Patch release, on a clean and up-to-date `develop`:

  ```sh
  mise run release:release --dry-run   # prints every command
  mise run release:release
  ```

  It dates the changelog (`release:changelog-roll`), tags `v<version>`,
  pushes, creates the GitHub release, bumps the patch version
  (`release:bump patch`) and pushes again. The release workflow then attaches
  a Linux and a macOS build to the release.
- Milestone release: first run `mise run release:bump minor --push` (e.g.
  0.1.3 to 0.2.0) on an issue branch and merge it, then run `release:release`.

The full process, including how to verify a release, is in
[`docs/process/releasing.md`](docs/process/releasing.md).

## Pull requests

1. Push the branch: `git push -u origin <issue>-<slug>`.
2. Open a pull request against `develop`:
   `gh pr create --base develop`. End the body with `Closes #<issue>`.
3. `mise run pr:status` lists the open pull requests with their merge state
   and check results.
4. Merge with `mise run pr:merge <number>` (try `--dry-run` first). It rebases
   the branch's worktree onto `origin/develop` so the branch is up to date and
   the history stays linear inside the branch (it aborts and stops on a
   conflict), pushes with `--force-with-lease`, waits until the `check` run
   of the pushed commit is green, merges with a merge commit and fast-forwards
   `develop` in the main checkout. Squash merging is disabled; the branch is
   deleted on GitHub automatically after the merge. The steps are described
   in [`docs/process/maintaining.md`](docs/process/maintaining.md).
