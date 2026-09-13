---
tags:
  - paper
  - wfc
status: current
authors:
  - Adam Newgas (Boris the Brave)
year: 2020
url: https://www.boristhebrave.com/2020/04/13/wave-function-collapse-explained/
pdf: link-only
licence: blog post, no licence notice (all rights reserved by default)
---

# Wave Function Collapse Explained

> [!summary]
> A plain-language walk-through of how WFC works, using a small tile example.
> It explains the three moving parts: each cell keeps a list of tiles it could
> still become; the solver repeatedly picks the least certain cell and fixes
> one tile there; and a propagation step removes tiles from neighbouring
> cells that can no longer fit. It also explains why cells are picked by
> "entropy": so that tile weights influence both what is chosen and in which
> order.

## Citation

Adam Newgas (Boris the Brave). 2020. Wave Function Collapse Explained. Blog
post, 13 April 2020.
<https://www.boristhebrave.com/2020/04/13/wave-function-collapse-explained/>

Link only: a web page without a licence notice.

## Why it matters here

The best short introduction to the algorithm for anyone reading the solver
design. It describes the support-count propagation (AC-4) that Gumin's code
uses, which the research note compares with the bitset propagation planned
for GDScript, and the entropy heuristic that the project plans to replace
with an integer one.

## Used by

- [[RESEARCH_WFC]], section 3 (cell choice, propagation).
