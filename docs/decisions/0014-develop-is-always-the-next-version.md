---
tags:
  - decision
status: accepted
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/issues/108
  - "[[releasing]]"
  - "[[0001-all-automation-through-mise]]"
---

# Develop Is Always the Next Version

> [!summary]
> The version in `project.godot` on `develop` is always a version that has
> not been released yet. A release tags the version that is already there and
> bumps `develop` to the next patch version straight away; it never edits the
> version before tagging.

## Context

The project needs repeatable releases with Linux and macOS builds, and Godot
embeds `config/version` in every export. If the version were raised just
before tagging, `develop` would carry an old, already released number between
releases, and every development build would claim to be a released version.
It would also make the release commit do two jobs at once.

## Decision

- `config/version` in `project.godot` is the single source of truth, in
  semantic versioning; tags are `vVERSION`.
- **`develop` always carries the NEXT version.** `mise run release:release`
  tags the version currently in `project.godot`, publishes the release and
  then runs `mise run release:bump patch`, commits and pushes, so at no time
  does `develop` sit on an already released version.
- A release never edits the version before tagging. Moving to a new
  milestone (0.1.x to 0.2.0) is a separate `mise run release:bump minor`
  change merged before the release.

## Consequences

- Any build from `develop` reports a version that is not yet released, so it
  is never mistaken for a release build.
- The tagged commit differs from its parent only in the changelog.
- A skipped patch number (0.1.3 bumped to 0.2.0) is normal and harmless.
- The release task needs direct push access to `develop`, which the owner has
  as an administrator.

## Links

- #108: release pipeline and release tasks.
- [[releasing]]: the full release process.
- Related: [[0001-all-automation-through-mise]].
