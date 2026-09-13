---
tags:
  - decision
  - moc
status: current
---

# Decision Log

> [!summary]
> One note per design decision, in the style of architecture decision
> records: why the question came up, what we chose, what follows from it, and
> the issues and pull requests behind it. A decision is `accepted` once it is
> in effect, `proposed` when research recommends it but it is not yet
> settled, and `open` when it waits for the owner.

## Decisions

| No. | Date | Title | Status |
| --- | --- | --- | --- |
| 0001 | 2026-09-13 | [[0001-all-automation-through-mise\|All automation through mise]] | accepted |
| 0002 | 2026-09-13 | [[0002-issue-branch-worktrees-and-merge-commits\|Issue-branch worktrees with merge commits]] | accepted |
| 0003 | 2026-09-13 | [[0003-ray-marcher-is-a-throwaway-prototype\|The ray-marched renderer is a throwaway prototype]] | accepted |
| 0004 | 2026-09-13 | [[0004-shared-integer-hash-replaces-float-hash\|Shared integer hash replaces the float hash]] | accepted |
| 0005 | 2026-09-13 | [[0005-right-handed-prototype-camera-basis\|Right-handed camera basis in the prototypes]] | accepted |
| 0006 | 2026-09-13 | [[0006-tightened-distance-field-bounds\|Distance-field bounds tightened versus the prototype]] | accepted |
| 0007 | 2026-09-13 | [[0007-facade-layout-overlay-knob\|Facade layout overlay as a knob, prototype default]] | accepted |
| 0008 | 2026-09-13 | [[0008-godot-native-rendering-for-the-generative-world\|Godot-native rendering for the generative world]] | accepted |
| 0009 | 2026-09-13 | [[0009-face-first-order-independent-sector-boundaries\|Face-first, order-independent sector boundaries]] | proposed |
| 0010 | 2026-09-13 | [[0010-near-universal-solid-tile-with-seeded-restarts\|Near-universal solid tile with seeded restarts, no backtracking]] | proposed |
| 0011 | 2026-09-13 | [[0011-typed-gdscript-solver-first\|Typed GDScript solver first, native extension past a threshold]] | proposed |
| 0012 | 2026-09-13 | [[0012-docs-is-an-obsidian-design-wiki\|docs/ is an Obsidian design wiki]] | accepted |
| 0013 | 2026-09-13 | [[0013-film-grain-off-by-default\|Film grain off by default]] | accepted |
| 0014 | 2026-09-13 | [[0014-develop-is-always-the-next-version\|Develop is always the next version]] | accepted |
| 0015 | 2026-09-13 | [[0015-hashed-multi-scale-sector-grammar\|Hashed multi-scale sector grammar]] | accepted |

The remaining questions in [[RESEARCH_WFC#Decisions to make]] (cell-choice
heuristic, GridMap lifetime, path-cell semantics, pipes and cables) get a
note here once they are taken up.

## Writing a decision note

- File name `NNNN-kebab-title.md`, the next free number; numbers are never
  reused.
- Front matter: `tags: [decision]`, `status` (`accepted`, `proposed` or
  `open`), `date` (when the decision was taken or raised) and `links` (issues,
  pull requests, related notes).
- A summary callout, then the sections Context, Decision, Consequences and
  Links. Under 300 words.
- Undecided notes say so in a callout at the top.
- A decision that is reversed stays in the log: set its status to
  `superseded`, link the note that replaces it, and add the new note to the
  table.
- Follow [[CONVENTIONS]] for everything else.
