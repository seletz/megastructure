---
tags:
  - paper
  - model-synthesis
  - wfc
status: current
authors:
  - Paul Merrell
year: 2021
url: https://paulmerrell.org/wp-content/uploads/2021/07/comparison.pdf
pdf: link-only
licence: author-hosted, no licence notice (all rights reserved by default)
---

# Comparing Model Synthesis and Wave Function Collapse

> [!summary]
> A short report in which Merrell runs his 2007 model synthesis and Gumin's
> WFC side by side. His conclusion: they are two versions of the same
> algorithm, with two differences. WFC always fills the most constrained cell
> first, and it tries to fill the whole output at once instead of in small
> blocks. For small outputs the two behave the same. For some large outputs
> WFC keeps failing for more than twenty minutes where model synthesis
> succeeds in seconds.

## Citation

Paul Merrell. 2021. *Comparing Model Synthesis and Wave Function Collapse*.
Technical note, 28 July 2021.
<https://paulmerrell.org/wp-content/uploads/2021/07/comparison.pdf>

Link only: the PDF is hosted by the author without any licence notice, so
redistribution is not permitted. (It is also 14 MB.)

## Why it matters here

- It is the source for the claim that the failure rate of plain WFC on large
  outputs comes mostly from the lowest-entropy order and from not working in
  blocks, and that "for small textures and models, the order has little
  impact and the failure rate is low in either case".
- That supports two choices for the fill layer: a sector (24³ cells) is small
  enough to solve in one go, and the cell-choice heuristic can be the simple
  integer one.

## Used by

- [[RESEARCH_WFC]], section 1 (algorithm choice) and section 3 (failure
  model).
