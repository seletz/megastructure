---
tags:
  - paper
  - wfc
  - talk
status: current
authors:
  - Oskar Stålberg
year: 2018
url: https://www.youtube.com/watch?v=0bcZb-SsnrA
pdf: link-only
licence: recorded talk; no licence for redistribution
---

# Wave Function Collapse in Bad North

> [!summary]
> A conference talk by the developer of the games Bad North and Townscaper on
> how WFC builds the small island levels of Bad North from 3D tiles. The idea
> most relevant to us is that the rules for which tiles may touch are not
> written by hand: they are derived from the tile geometry itself, by
> comparing the shapes of the faces that meet.

## Citation

Oskar Stålberg. 2018. Wave Function Collapse in Bad North. Talk at the
Everything Procedural Conference (EPC) 2018, Breda University of Applied
Sciences. Video: <https://www.youtube.com/watch?v=0bcZb-SsnrA>

Link only: a recorded talk.

## Why it matters here

The planned tileset validation computes a "face profile hash" from the
vertices lying on each tile face to check that sockets marked symmetric
really are. The same hash could later derive socket ids automatically, as in
this talk. For the first box-only tileset, hand-written socket ids are faster
to iterate on.

## Used by

- [[RESEARCH_WFC]], section 2 (validation, step 4).
- Related talks: [[stalberg-2019-organic-towns-from-square-tiles]],
  [[stalberg-2021-the-story-of-townscaper]],
  [[stalberg-2021-beyond-townscapers]].
