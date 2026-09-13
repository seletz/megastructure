---
tags:
  - code-map
  - hash
status: current
---

# Hash

> [!summary]
> Every "random" choice in the world, such as whether a window is lit or where
> a bridge crosses, comes from one small function: give it the world seed, a
> grid cell and a salt number, and it returns the same pseudo-random value
> every time. The function exists twice in this repository, once in the shader
> and once in GDScript, and both must produce exactly the same bits, so that
> code on the CPU can later agree with what the GPU draws. A task prints
> reference values that both are checked against.

## The two implementations

- [hash.gdshaderinc](../../shaders/include/hash.gdshaderinc): the shader
  version. It declares the `uniform uint seed` that the whole shader reads,
  and uses 32-bit unsigned arithmetic directly.
- [hash.gd](../../scripts/hash.gd) (`class_name Hash`): the GDScript version.
  GDScript integers are 64-bit, so every intermediate is masked to 32 bits and
  multiplications are split into 16-bit halves to avoid overflow. The seed is
  passed as an argument instead of a uniform.

Both expose the same functions:

| Function | Returns |
| --- | --- |
| `pcg` / `hash_pcg` | A PCG-style permutation of one 32-bit word. |
| `hash3_u` | The raw 32-bit hash of `(seed, cell, salt)`, mixing the salt, then x, y and z in turn. |
| `hash3` | A float in 0..1 (exclusive) from the top 24 bits, exact in float32. |
| `hash2`, `hash1` | `hash3` with the missing cell coordinates set to 0. |

A **cell** is an integer grid coordinate (a position divided by a cell size
and floored). A **salt** keeps independent decisions on the same cell apart:
the chasm uses one salt for "is there an opening here", another for "how deep
is this terrace", and so on. The salts match the HTML prototypes, so the same
seed gives the same layout there.

The world seed itself lives in `WorldState` and is copied into the shader's
`seed` uniform by `SeedUniform`; both are described in [[tweak-ui]].

## Reference vectors

`mise run hash-vectors` runs a small script (listed in [[tools-and-tasks]])
that prints a Markdown table of `hash3_u` and `hash3` for eight fixed inputs,
including negative cells and the largest seeds and salts. The output must
match the table in [[hash_vectors]], which also has a JavaScript snippet
for checking the prototypes' version against the same values. There is no
automatic check of the shader version; it is kept identical by reading.

## How to run or check it

- `mise run hash-vectors` and compare with [[hash_vectors]].
- `mise run seed-check` confirms that the shader follows the seed and that the
  same seed renders the same frame ([[tools-and-tasks]]).
- When either implementation changes, change the other in the same pull
  request and regenerate the table.

## References

- [[integer-hash]]: why the hash is built this way and how it replaced the
  float hash.
- [[hash_vectors]]: definition and reference values.
- [[0004-shared-integer-hash-replaces-float-hash]]: the decision.
- [[PLAN_0.0.1#Decision: shared integer hash]]: where it was first recorded.
- Papers: [[oneill-2014-pcg]], [[jarzynski-2020-hash-functions-gpu-rendering]].
- [[raymarch-shader]]: the shader that includes the hash.
