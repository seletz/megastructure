---
tags:
  - paper
  - hash
status: current
authors:
  - Mark Jarzynski
  - Marc Olano
year: 2020
url: https://jcgt.org/published/0009/03/02/
pdf: local
licence: CC BY-ND 3.0 (JCGT, stated on the paper)
---

# Hash Functions for GPU Rendering

> [!summary]
> Shaders often need random-looking numbers that are the same every time for
> the same input, for example "is there a window at this grid cell?". This
> paper tests many hash functions used for that on GPUs, both for how random
> their output really is and for how fast they run, and recommends the best
> ones for each budget. Its advice for a single 32-bit input is the `pcg`
> hash, applied repeatedly when there are several inputs; this is exactly the
> hash the project uses.

## Citation

Mark Jarzynski and Marc Olano. 2020. Hash Functions for GPU Rendering.
*Journal of Computer Graphics Techniques (JCGT)* 9, 3, 20–38.
<https://jcgt.org/published/0009/03/02/>

Local copy: [jarzynski-2020-hash-functions-gpu-rendering.pdf](pdf/jarzynski-2020-hash-functions-gpu-rendering.pdf)
(© 2020 the authors, distributed under
[CC BY-ND 3.0](https://creativecommons.org/licenses/by-nd/3.0/); stored
unmodified).

## Why it matters here

- It is the evidence behind the choice of `pcg` as the shared integer hash:
  on the paper's speed/quality comparison, "pcg is a good default choice in
  terms of both quality and performance", including when several inputs are
  combined by nesting.
- The hash uses only unsigned 32-bit integer operations, so the Godot shader,
  GDScript and the JavaScript/GLSL prototypes all compute bit-identical
  values, which floating-point hashes such as the paper's `trig` cannot
  guarantee.

## Used by

- [[hash_vectors]]: the nested form `pcg(h ^ cell.x)` ... is the paper's
  recommended way to hash several inputs.
- [[PLAN_0.1.0]], decision "shared integer hash".
- [[RESEARCH_WFC]], section 1 (determinism): every solver draw is `hash3_u`.
- Code: [hash.gdshaderinc](../../shaders/include/hash.gdshaderinc),
  [hash.gd](../../scripts/hash.gd),
  [hash_vectors.gd](../../scripts/tools/hash_vectors.gd).
- Related: [[oneill-2014-pcg]].
