---
tags:
  - paper
  - model-synthesis
status: current
authors:
  - Paul C. Merrell
year: 2009
url: https://paulmerrell.org/wp-content/uploads/2021/06/thesis.pdf
pdf: link-only
licence: © 2009 Paul C. Merrell, all rights reserved
---

# Model Synthesis (PhD Thesis)

> [!summary]
> Merrell's dissertation collects the model synthesis work in one place and
> adds the theory behind it. The part that matters most for us is the chapter
> on modifying in blocks: it proves that for some tile sets, filling a large
> area all at once gets exponentially harder as the area grows, while for
> others it always works, and it explains why breaking the output into small
> overlapping blocks avoids the problem.

## Citation

Paul C. Merrell. 2009. *Model Synthesis*. Ph.D. Dissertation, Department of
Computer Science, University of North Carolina at Chapel Hill.
<https://paulmerrell.org/wp-content/uploads/2021/06/thesis.pdf>

The PDF is 38 MB. Link only: the copyright page reads "ALL RIGHTS RESERVED".

## Why it matters here

- Pages 41–65 (theorems 3.3.4 and 3.3.6) give the reason a whole-world WFC
  solve would fail and why a per-sector block with fixed borders does not.
  This is the theoretical backing for solving one 24³ sector at a time.
- The same argument explains the risk the research note calls out: fixing all
  six faces can over-constrain the interior unless a permissive fallback tile
  exists.

## Used by

- [[RESEARCH_WFC]], section 1, via the comparison paper
  [[merrell-2021-comparing-model-synthesis-and-wfc]].
- Related: [[merrell-2007-example-based-model-synthesis]],
  [[merrell-2011-model-synthesis-general-procedural-modeling]].
