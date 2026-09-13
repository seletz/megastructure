---
tags:
  - decision
status: accepted
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/issues/55
  - https://github.com/seletz/megastructure/pull/62
  - "[[Home]]"
  - "[[CONVENTIONS]]"
---

# docs/ Is an Obsidian Design Wiki

> [!summary]
> The `docs/` folder is a linked wiki that can be opened in the Obsidian note
> app and still reads fine on GitHub. It records what we build, the plans,
> the algorithms and papers behind them, the decisions and their reasons, and
> where each idea lives in the code. It is written for people, with a plain
> summary at the top of every note.

## Context

By milestone 0.0.2 the reasoning behind the project was scattered across a
concept document, a plan, a research report and dozens of pull request
descriptions. Pull requests are hard to find later, and loose markdown files
do not link to each other.

## Decision

- `docs/` is the vault root; existing documents keep their names so links
  from code, issues and pull requests keep working.
- Notes link with wikilinks, open with a summary callout, and carry front
  matter (`tags`, `status`, `sources`). [[Home]] is the map of content;
  [[CONVENTIONS]] holds the rules.
- Code is linked with relative links, never copied. Paper PDFs are stored
  only when their licence allows redistribution.
- Only minimal Obsidian settings are committed; a `.gdignore` keeps Godot
  from importing the folder.
- Decisions are kept as one note each in this folder.

## Consequences

- A pull request that changes described behaviour, or settles a design
  question, updates or adds the matching note in the same pull request.
- Stale notes are marked superseded and linked to their replacement, not
  deleted.
- Work on the wiki is split into sub-issues: scaffold, papers, algorithms,
  decisions, code map.

## Links

- #55 (epic), PR #62 (vault scaffold, #56); this log is #59.
- [[Home]], [[CONVENTIONS]].
