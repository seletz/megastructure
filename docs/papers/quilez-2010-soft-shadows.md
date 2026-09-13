---
tags:
  - paper
  - sdf
status: current
authors:
  - Inigo Quilez
year: 2010
url: https://iquilezles.org/articles/rmshadows/
pdf: link-only
licence: article text and images reserved by the author; code snippets MIT (site-wide notice)
---

# Soft Shadows in Raymarched SDFs

> [!summary]
> A cheap way to get soft-edged shadows in a ray-marched scene. To check
> whether a point is in shadow, march a ray towards the light; at every step
> the distance function says how close the ray passed to some geometry. The
> closer it passed, relative to how far it has travelled, the darker the
> penumbra. A single ray thus gives a soft shadow instead of a hard one.

## Citation

Inigo Quilez. *Soft Shadows in Raymarched SDFs*. Web article, iquilezles.org,
2010.
<https://iquilezles.org/articles/rmshadows/>

Link only: the site states that its code snippets are under the MIT
licence but that the rest is protected, so the article itself is not
copied here.

## Why it matters here

The chasm's key light uses exactly this estimate: `res = min(res, k * h / t)`
while stepping towards the light, with `k` exposed as the `shadow_softness`
uniform. It is what gives the facades and decks their soft shadows without
shadow maps.

## Used by

- [[PLAN_0.1.0]], epic #12 (look and lighting).
- Code: `lighting_shadow()` in
  [lighting.gdshaderinc](../../shaders/include/lighting.gdshaderinc).
- Prototype: `shadow()` in
  [megastructure-chasm.html](../megastructure-chasm.html).
