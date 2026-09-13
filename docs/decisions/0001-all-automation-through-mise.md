---
tags:
  - decision
status: accepted
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/pull/28
  - https://github.com/seletz/megastructure/issues/23
  - "[[0002-issue-branch-worktrees-and-merge-commits]]"
---

# All Automation Through Mise

> [!summary]
> Every way of building, checking, running or exporting the project is a
> named task in one file, `mise.toml`, and mise also installs the exact Godot
> version. A developer, a CI job and a helper script all type the same command
> and get the same result.

## Context

A Godot project needs a pinned engine version, a headless import, a script
check, export templates and a few tools of our own (such as printing hash
reference vectors). Spread across shell scripts, README snippets and CI YAML,
those steps drift apart, and "works on my machine" follows.

## Decision

[mise](https://mise.jdx.dev/) pins the tools (Godot 4.7.2, Node) and holds
every task in [mise.toml](../../mise.toml): `editor`, `run`, `import`,
`check-scripts`, `check`, `templates`, `hash-vectors` and the export task. No
automation lives anywhere else. CI installs mise and runs `mise run check`,
nothing more ([check.yml](../../.github/workflows/check.yml)).

## Consequences

- `mise run check` is the single gate: it must pass locally before pushing
  and is the required status on `develop`.
- When CI showed that the headless editor load passed with a broken script,
  the fix went into the task (`check-scripts`), so local runs got it too
  (#28).
- New tooling is added as a mise task, and the README task table is updated
  with it.
- Contributors need mise installed; everything else follows from it.

## Links

- #23, PR #28: CI runs `mise run check`; `check-scripts` added.
- CONTRIBUTING.md, section "Checks".
- Related: [[0002-issue-branch-worktrees-and-merge-commits]].
