---
tags:
  - paper
  - wfc
status: current
authors:
  - Marian Kleineberg (marian42)
year: 2019
url: https://marian42.de/article/wfc/
pdf: link-only
licence: blog post without licence notice; the accompanying source code is MIT
---

# Infinite Procedurally Generated City with WFC

> [!summary]
> A write-up of a small game in which you walk through an endless city that is
> generated around you from a hundred or so 3D building blocks. It explains
> how each block describes its six faces with "connectors" so the solver knows
> which blocks can touch, how rotated copies are generated automatically, how
> the world grows in chunks as the player moves, and why the author needed
> backtracking. It ends frankly: errors that appear late made the approach
> feel unsuitable for commercial games.

## Citation

Marian Kleineberg. 2019. Infinite procedurally generated city with the Wave
Function Collapse algorithm. Blog post, 6 January 2019.
<https://marian42.de/article/wfc/>

Code: [marian42/wavefunctioncollapse](https://github.com/marian42/wavefunctioncollapse)
(Unity C#, MIT).

Link only: the article has no licence notice.

## Why it matters here

- The project's socket convention is taken from this article: one socket per
  face, horizontal sockets with a symmetry tag (`3s` matches `3s`, `3`
  matches `3f`), vertical sockets with a rotation index, rotations generated
  from a prototype rather than authored, and an optional exclusion list.
- Its experience with backtracking is part of why the project avoids it.

## Used by

- [[RESEARCH_WFC]], section 2 (socket-based adjacency), section 3
  (contradiction handling) and section 6 (reference implementations).
- Related: [[donald-2020-superpositions-sudoku-wfc]], which uses the same
  convention.
