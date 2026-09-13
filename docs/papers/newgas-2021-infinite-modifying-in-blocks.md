---
tags:
  - paper
  - wfc
  - model-synthesis
status: current
authors:
  - Adam Newgas (Boris the Brave)
year: 2021
url: https://www.boristhebrave.com/2021/11/08/infinite-modifying-in-blocks/
pdf: link-only
licence: blog post, no licence notice (all rights reserved by default)
---

# Infinite Modifying in Blocks

> [!summary]
> How to generate an endless tile world that always comes out the same,
> whichever part you look at first. The output is built in layers: each block
> depends only on a fixed set of blocks from the layer below, so generating
> any one block takes a fixed amount of work and gives the same result no
> matter what was generated before. That makes infinite, deterministic,
> streamable WFC possible.

## Citation

Adam Newgas (Boris the Brave). 2021. Infinite Modifying in Blocks. Blog post,
8 November 2021.
<https://www.boristhebrave.com/2021/11/08/infinite-modifying-in-blocks/>

Link only: a web page without a licence notice.

## Why it matters here

This is the closest published relative of the recommended boundary scheme.
The project's version is three layers deep: the edges shared by sectors are
solved first, then the faces, then each sector's interior with all six faces
fixed. Because every step is seeded only from its own coordinates, two
neighbouring sectors compute the identical face independently, so sectors can
be generated in any order and on parallel worker threads, and unloading one
costs nothing.

## Used by

- [[RESEARCH_WFC]], section 1 (sector boundaries), section 5 (streaming) and
  decision 1 (boundary scheme).
