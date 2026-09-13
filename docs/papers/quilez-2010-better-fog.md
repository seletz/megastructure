---
tags:
  - paper
  - sdf
status: current
authors:
  - Inigo Quilez
year: 2010
url: https://iquilezles.org/articles/fog/
pdf: link-only
licence: article text and images reserved by the author; code snippets MIT (site-wide notice)
---

# Better Fog

> [!summary]
> Most renderers treat fog as a simple fade to one colour with distance. This
> article shows small additions that look much better: fog whose colour
> depends on the viewing direction (brighter towards the light), fog that
> thins with height, and fog that absorbs different colours at different
> rates. Each costs a line or two of shader code.

## Citation

Inigo Quilez. *Better Fog*. Web article, iquilezles.org, 2010.
<https://iquilezles.org/articles/fog/>

Link only: the site states that its code snippets are under the MIT
licence but that the rest is protected, so the article itself is not
copied here.

## Why it matters here

Fog carries most of the megastructure's sense of scale. The chasm shader uses
exponential distance fog whose colour depends on the ray's vertical direction:
near black looking down, a cold grey glow looking up, as if light bleeds in
from far above. That direction-dependent fog colour is the idea from this
article.

## Used by

- [[PLAN_0.1.0]], epic #12 (fog, tone mapping, grain, vignette).
- [[MEGASTRUCTURE_CONCEPT]], look and lighting.
- Code: the fog functions in
  [post.gdshaderinc](../../shaders/include/post.gdshaderinc).
- Prototype: the fog block at the end of `main()` in
  [megastructure-chasm.html](../megastructure-chasm.html).
