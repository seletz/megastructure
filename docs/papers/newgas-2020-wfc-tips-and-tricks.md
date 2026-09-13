---
tags:
  - paper
  - wfc
status: current
authors:
  - Adam Newgas (Boris the Brave)
year: 2020
url: https://www.boristhebrave.com/2020/02/08/wave-function-collapse-tips-and-tricks/
pdf: link-only
licence: blog post, no licence notice (all rights reserved by default)
---

# Wave Function Collapse Tips and Tricks

> [!summary]
> A practical blog post by the author of the DeBroglie library on making WFC
> behave: how to design tile sets, how to steer the output with fixed tiles
> and weights, and how to cope when it fails. The most useful point for us is
> that constraints are cheap: forcing a cell to hold a particular tile, or a
> particular set of tiles, is just removing options before the solver starts.

## Citation

Adam Newgas (Boris the Brave). 2020. Wave Function Collapse Tips and Tricks.
Blog post, 8 February 2020.
<https://www.boristhebrave.com/2020/02/08/wave-function-collapse-tips-and-tricks/>

Link only: a web page without a licence notice.

## Why it matters here

- It confirms the mechanism for pre-collapsed cells: walkable-graph cells and
  fixed sector faces are domain restrictions applied before the first
  observation ("It's extremely easy to add support for constraints by forcing
  a particular cell to contain a particular tile").
- Its remark that WFC "tries its best with what remains" when a tile is
  unusable is the basis for the dead-tile check in the planned tileset
  validation task.

## Used by

- [[RESEARCH_WFC]], section 1 (pre-collapsed cells) and section 2
  (validation).
