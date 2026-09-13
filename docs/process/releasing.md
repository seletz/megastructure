---
tags:
  - process
  - tooling
status: current
---

# Releasing

> [!summary]
> A release publishes the version that `develop` already carries. One
> command, `mise run release:release`, dates the changelog, tags the version,
> creates the GitHub release and then immediately moves `develop` on to the
> next patch version. GitHub then builds a Linux and a macOS archive and
> attaches them to the release. **`develop` always carries the NEXT version:
> the version in `project.godot` on `develop` is never one that was already
> released, and a release never edits the version before tagging.**

## Versioning

- Versions follow [semantic versioning](https://semver.org/):
  `MAJOR.MINOR.PATCH`. While the project is below 1.0, a milestone raises the
  minor number (0.1.0 is the exterior prototype, 0.2.0 the cells and Wave
  Function Collapse fill) and fixes between milestones raise the patch number.
- The single source of truth is `config/version` in
  [project.godot](../../project.godot). Godot embeds it in every export (on
  macOS as the bundle version). Tags are `v` plus that version, e.g. `v0.1.0`.
- **`develop` always carries the next, unreleased version.** A release tags
  the version currently in `project.godot` and bumps it to the next patch
  right afterwards, so at no time does `develop` sit on an already released
  version ([[0014-develop-is-always-the-next-version]]).

## What release:release does

Run it on an up-to-date, clean `develop`. It needs push rights to `develop`
(the owner is an administrator, so branch protection lets the task push) and
an authenticated `gh`. Every step is a mise task or a single git or `gh`
command:

1. **Refuses** unless the current branch is `develop`, the working tree is
   clean, `develop` equals `origin/develop` after a fetch, `gh auth status`
   succeeds, the tag does not exist yet and the Unreleased section of the
   changelog is not empty.
2. Reads `VERSION` from `config/version` in `project.godot`. It does not
   change it.
3. `mise run release:notes` saves the Unreleased section as the release notes.
4. `mise run release:changelog-roll VERSION` renames `## Unreleased` to
   `## VERSION - YYYY-MM-DD`, puts a fresh, empty `## Unreleased` above it
   and commits `chore(release): VERSION`.
5. Creates the annotated tag `vVERSION` and pushes `develop` and the tag
   together (`git push --atomic`).
6. `gh release create vVERSION --title vVERSION --notes-file <notes>`
   publishes the release, which starts the release workflow.
7. `mise run release:bump patch` sets `project.godot` to the next patch
   version (0.1.0 becomes 0.1.1) and commits `chore(release): start 0.1.1`;
   then `develop` is pushed.
8. Prints the release URL.

Try it first with `mise run release:release --dry-run`: it runs the checks
(reporting what it would refuse instead of stopping), shows the release notes,
and prints every command instead of executing it; the sub-tasks run in their
own dry-run mode.

## What the GitHub workflow does

[release.yml](../../.github/workflows/release.yml) runs when a release is
published. Two jobs run side by side, `linux` on `ubuntu-latest` and `macos`
on `macos-latest`, and each only calls mise tasks:

1. check out the tagged commit and install mise and its tools;
2. (Linux only) install the libraries Godot needs, as in the check workflow;
3. `mise run templates`;
4. `mise run export linux build/linux/megastructure.x86_64` or
   `mise run export macos build/macos/megastructure.zip`;
5. `mise run release:package linux` or `mise run release:package macos`,
   which writes `build/release/megastructure-VERSION-linux-x86_64.tar.gz` or
   `build/release/megastructure-VERSION-macos-universal.zip` and fails if
   the tag does not match `config/version`;
6. `gh release upload` attaches the archive to the release.

A pull request that changes the workflow or `export_presets.cfg` runs the same
jobs without the upload, so the pipeline is tested before it is needed.

The macOS build is a universal (Intel and Apple Silicon) app that is not
signed or notarized. On first launch, right-click the app and choose Open to
get past Gatekeeper.

## Patch release

Nothing to prepare: `develop` already carries the next patch version.

```sh
git switch develop && git pull
mise run release:release --dry-run   # read the notes and the commands
mise run release:release
```

## Milestone release

When a milestone is finished, `develop` still carries a patch version of the
previous milestone (for example 0.1.3). Raise the minor version first, on an
issue branch like any other change, then release:

```sh
mise run release:bump minor --push   # 0.1.3 -> 0.2.0, commits "chore(release): start 0.2.0" and pushes
# open and merge the pull request, then on develop:
mise run release:release
```

The skipped patch version was never released, so nothing is lost. Use
`release:bump major` the same way for 1.0.0. `release:bump` accepts
`--push` (push the current branch after committing) and `--dry-run` too.

## Verifying a release

- The release page (the URL the task prints, or `gh release view vVERSION`)
  shows the changelog section as its notes.
- Both workflow jobs are green (`gh run list --workflow release.yml`) and the
  release has two assets, the Linux `.tar.gz` and the macOS `.zip`
  (`gh release view vVERSION --json assets --jq '.assets[].name'`).
- [[CHANGELOG]] has a `## VERSION - YYYY-MM-DD` section under an empty
  `## Unreleased`.
- `project.godot` on `develop` carries the next patch version, and
  `git show vVERSION:project.godot` carries the released one.
- Unpack the Linux archive and run `megastructure.x86_64`.

## References

- [[0014-develop-is-always-the-next-version]]: why the version moves on
  right after a release.
- [[ci-and-export]]: the export presets and both workflows.
- [[maintaining]]: the worktree and pull request tasks.
- [[tools-and-tasks]]: every release task in the task table.
- [[CONVENTIONS#Changelog]]: how changelog entries are written.
- [mise.toml](../../mise.toml): the `release:*` tasks.
