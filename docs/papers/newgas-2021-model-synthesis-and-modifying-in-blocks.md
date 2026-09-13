---
tags:
  - paper
  - wfc
  - model-synthesis
status: current
authors:
  - Adam Newgas (Boris the Brave)
year: 2021
url: https://www.boristhebrave.com/2021/10/26/model-synthesis-and-modifying-in-blocks/
pdf: link-only
licence: blog post, no licence notice (all rights reserved by default)
---

# Model Synthesis and Modifying in Blocks

> [!summary]
> A hands-on account of implementing Merrell's "modifying in blocks" on top of
> a WFC solver. Plain WFC gets less reliable the bigger the output, until "it
> is virtually impossible to get a successful run no matter how many times you
> restart". Working in small overlapping blocks over an already-valid output
> fixes that and allowed much larger results, but the author found it fiddly,
> sensitive to the order of the blocks, and wasteful where blocks overlap.

## Citation

Adam Newgas (Boris the Brave). 2021. Model Synthesis and Modifying in Blocks.
Blog post, 26 October 2021.
<https://www.boristhebrave.com/2021/10/26/model-synthesis-and-modifying-in-blocks/>

Link only: a web page without a licence notice.

## Why it matters here

It is the practitioner's view of the trade-off behind the fill layer design:
a whole-world solve fails, block solving works but depends on order. The
project avoids the order problem by making the blocks the sectors themselves
and computing the shared faces independently of load order; see
[[newgas-2021-infinite-modifying-in-blocks]].

## Used by

- [[RESEARCH_WFC]], section 1 (algorithm choice).
- Related: [[merrell-2007-example-based-model-synthesis]].
