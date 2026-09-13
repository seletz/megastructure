---
tags:
  - paper
  - moc
status: current
---

# Papers and References

> [!summary]
> The index of every paper, article, talk, code repository and manual page
> that the design documents rely on. Each entry has its own note with the full
> citation, a plain-language summary, why it matters for this project, and
> which notes and code use it. Two PDFs are stored in `pdf/` because their
> licences allow it; everything else is linked.

## Licensing rule

A PDF is committed to `pdf/` only when its licence allows redistribution:
arXiv papers under an open licence, papers published under Creative Commons
(for example JCGT), and author-hosted copies that carry an explicit
permissive notice. Publisher versions from ACM, IEEE or Springer, author
copies without such a notice, and "all rights reserved" documents are never
committed; their notes give the citation and link to the online copy.
Blog posts, talks, repositories and manual pages are always linked, not
copied. Each note records the decision in its front matter (`pdf: local` or
`pdf: link-only`, and `licence:`) and explains it under "Citation". Stored
PDFs stay unmodified and under 15 MB. See also
[[CONVENTIONS#Papers and licensing]].

## Wave Function Collapse and model synthesis

| Title | Year | Local PDF | Licence | Note |
| --- | --- | --- | --- | --- |
| WaveFunctionCollapse (Gumin) | 2016 | no | MIT code, no paper | [[gumin-2016-wavefunctioncollapse]] |
| WaveFunctionCollapse Is Constraint Solving in the Wild | 2017 | no | © ACM | [[karth-2017-wfc-is-constraint-solving]] |
| Example-Based Model Synthesis | 2007 | no | © ACM; code MIT | [[merrell-2007-example-based-model-synthesis]] |
| Continuous Model Synthesis | 2008 | no | © ACM | [[merrell-2008-continuous-model-synthesis]] |
| Model Synthesis (PhD thesis) | 2009 | no | © author, all rights reserved | [[merrell-2009-model-synthesis-thesis]] |
| Model Synthesis: A General Procedural Modeling Algorithm | 2011 | no | © IEEE | [[merrell-2011-model-synthesis-general-procedural-modeling]] |
| Comparing Model Synthesis and Wave Function Collapse | 2021 | no | no licence notice | [[merrell-2021-comparing-model-synthesis-and-wfc]] |
| Punch Out Model Synthesis | 2025 | yes | CC BY 4.0 (arXiv) | [[zzyzek-2025-punch-out-model-synthesis]] |

## Write-ups, talks and libraries

| Title | Year | Local PDF | Licence | Note |
| --- | --- | --- | --- | --- |
| DeBroglie | 2018 | no | MIT code | [[newgas-2018-debroglie]] |
| Tessera | 2019 | no | commercial; docs without licence | [[newgas-2019-tessera]] |
| Wave Function Collapse Tips and Tricks | 2020 | no | blog, no licence notice | [[newgas-2020-wfc-tips-and-tricks]] |
| Wave Function Collapse Explained | 2020 | no | blog, no licence notice | [[newgas-2020-wfc-explained]] |
| Model Synthesis and Modifying in Blocks | 2021 | no | blog, no licence notice | [[newgas-2021-model-synthesis-and-modifying-in-blocks]] |
| Infinite Modifying in Blocks | 2021 | no | blog, no licence notice | [[newgas-2021-infinite-modifying-in-blocks]] |
| Infinite Procedurally Generated City with WFC | 2019 | no | blog, no licence notice; code MIT | [[kleineberg-2019-infinite-city-wfc]] |
| Superpositions, Sudoku, the Wave Function Collapse Algorithm | 2020 | no | video | [[donald-2020-superpositions-sudoku-wfc]] |
| Wave Function Collapse in Bad North | 2018 | no | recorded talk | [[stalberg-2018-wfc-in-bad-north]] |
| Organic Towns from Square Tiles | 2019 | no | recorded talk | [[stalberg-2019-organic-towns-from-square-tiles]] |
| The Story of Townscaper | 2021 | no | recorded talk | [[stalberg-2021-the-story-of-townscaper]] |
| Beyond Townscapers | 2021 | no | recorded talk | [[stalberg-2021-beyond-townscapers]] |
| fast-wfc | 2018 | no | MIT code | [[fehr-2018-fast-wfc]] |

## Hashing

| Title | Year | Local PDF | Licence | Note |
| --- | --- | --- | --- | --- |
| PCG: A Family of Random Number Generators | 2014 | no | © author | [[oneill-2014-pcg]] |
| Hash Functions for GPU Rendering | 2020 | yes | CC BY-ND 3.0 (JCGT) | [[jarzynski-2020-hash-functions-gpu-rendering]] |

## Ray marching and signed distance functions

| Title | Year | Local PDF | Licence | Note |
| --- | --- | --- | --- | --- |
| Raymarching Distance Fields | 2008 | no | text reserved; snippets MIT | [[quilez-2008-raymarching-distance-fields]] |
| Distance Functions | undated | no | text reserved; snippets MIT | [[quilez-distance-functions]] |
| Soft Shadows in Raymarched SDFs | 2010 | no | text reserved; snippets MIT | [[quilez-2010-soft-shadows]] |
| Better Fog | 2010 | no | text reserved; snippets MIT | [[quilez-2010-better-fog]] |
| Normals for an SDF | 2015 | no | text reserved; snippets MIT | [[quilez-2015-sdf-normals]] |

## Godot documentation

Manual pages are living documents, so their notes are named
`godot-docs-<page>` without a year and cite the date they were checked.

| Title | Year | Local PDF | Licence | Note |
| --- | --- | --- | --- | --- |
| Advanced Post-Processing | undated | no | CC BY 3.0 | [[godot-docs-advanced-post-processing]] |
| GridMap | undated | no | MIT (class reference) | [[godot-docs-gridmap]] |
| MultiMesh | undated | no | MIT (class reference) | [[godot-docs-multimesh]] |
| WorkerThreadPool | undated | no | MIT (class reference) | [[godot-docs-workerthreadpool]] |
| Thread-Safe APIs | undated | no | CC BY 3.0 | [[godot-docs-thread-safe-apis]] |
| RandomNumberGenerator | undated | no | MIT (class reference) | [[godot-docs-randomnumbergenerator]] |

## Not given a note

Some links in [[RESEARCH_WFC]] are pointers rather than sources the design
depends on, and stay inline there: the survey of Godot WFC addons (section 6),
godot-rust and godot-cpp, Godot issue and proposal threads, the GDScript
versus C# benchmark posts, the Godot 4.7 release notes, the Wikipedia article
on model synthesis, and Godot manual pages that are only mentioned in passing
(static typing, visibility ranges, mesh LOD, global illumination, occlusion
culling, `ConcavePolygonShape3D`). They get a note when a design decision
starts to rest on them.
