---
tags:
  - paper
  - sdf
status: current
authors:
  - Inigo Quilez
year: 2015
url: https://iquilezles.org/articles/normalsSDF/
pdf: link-only
licence: article text and images reserved by the author; code snippets MIT (site-wide notice)
---

# Normals for an SDF

> [!summary]
> Lighting a surface needs its normal, the direction it faces. For a shape
> defined by a distance function, the normal is the direction in which the
> distance grows fastest, and it can be estimated by sampling the distance
> function at a few points around the surface. The article compares ways to do
> that and recommends the "tetrahedron" method, which needs only four samples
> instead of six.

## Citation

Inigo Quilez. *Normals for an SDF*. Web article, iquilezles.org, 2015.
<https://iquilezles.org/articles/normalsSDF/>

Link only: the site states that its code snippets are under the MIT
licence but that the rest is protected, so the article itself is not
copied here.

## Why it matters here

The ray-march shader computes every surface normal with the tetrahedron
method from this article. The project adds one detail: the sampling offset is
a fixed absolute distance (`normal_epsilon`), because scaling it with camera
distance smeared normals across ledges and terrace borders.

## Used by

- [[PLAN_0.1.0]], epic #12 (surfaces).
- Code: `calc_normal()` in
  [raymarch_world.gdshader](../../shaders/raymarch_world.gdshader).
- Prototype: `normal()` in
  [megastructure-chasm.html](../megastructure-chasm.html).
