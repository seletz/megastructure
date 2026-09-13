---
tags:
  - paper
  - wfc
status: current
authors:
  - Adam Newgas (Boris the Brave)
year: 2018
url: https://github.com/BorisTheBrave/DeBroglie
pdf: link-only
licence: MIT (source code and documentation site)
---

# DeBroglie

> [!summary]
> An open-source C# library for WFC, written by Boris the Brave. It handles 2D
> and 3D grids, tile rotations and mirrors, and constraints beyond simple
> neighbour rules, such as "these tiles must form a connected path" or "this
> cell must hold this tile". Unlike most WFC code it can also backtrack: undo
> recent choices when it runs into a dead end. It is the best-engineered open
> solver to learn from.

## Citation

Adam Newgas. *DeBroglie*. C# library, 2018 onwards.
<https://github.com/BorisTheBrave/DeBroglie>

Documentation: <https://boristhebrave.github.io/DeBroglie/>

The code is under the MIT licence. There is no paper; the note links to the
repository and its documentation.

## Why it matters here

- Its propagator and constraint interfaces are the model for the planned
  `SectorSolver`: pre-collapsed walkable-graph cells are the same idea as its
  fixed-tile and path constraints.
- It shows that full backtracking is implementable but costs time and memory.
  That is one reason the project chooses restart plus a deterministic
  all-solid fallback instead.

## Used by

- [[RESEARCH_WFC]], section 3 (contradiction handling) and section 6
  (reference implementations).
- Related: [[newgas-2019-tessera]], its commercial sibling.
