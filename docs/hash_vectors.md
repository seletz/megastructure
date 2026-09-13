---
tags:
  - algorithm
  - hash
  - reference
status: current
---

# Shared integer hash: reference vectors

> [!summary]
> Where a column is missing or a bridge spans the chasm is decided by one
> integer hash of the seed, a cell position and a salt number. The hash exists
> in three places (the Godot shader, GDScript and the HTML prototypes) and all
> three must give exactly the same result, otherwise the CPU and the GPU would
> disagree about the world. This note defines the function and lists reference
> values that every implementation is checked against.

Layout decisions (which column is removed, where a bridge spans the chasm,
how much grime a surface gets) are driven by one integer hash of
`(seed, cell, salt)`. It is implemented three times and all three must agree
bit for bit:

- [`shaders/include/hash.gdshaderinc`](../shaders/include/hash.gdshaderinc):
  Godot shading language, `uint` arithmetic only, seeded by `uniform uint seed`.
- [`scripts/hash.gd`](../scripts/hash.gd): GDScript, 64-bit ints masked to
  32 bits.
- [`megastructure.html`](megastructure.html) and
  [`megastructure-chasm.html`](megastructure-chasm.html): GLSL ES 3.00 `uint`
  in the fragment shader, plus a JavaScript `hash3()` using `Math.imul` and
  `>>> 0` for checks from the browser console.

## Definition

All arithmetic is unsigned 32-bit. Negative cell coordinates are taken as
their two's complement bit pattern.

```
pcg(v):
    s = v * 747796405 + 2891336453
    w = ((s >> ((s >> 28) + 4)) ^ s) * 277803737
    return (w >> 22) ^ w

hash3_u(seed, cell, salt):
    h = pcg(seed ^ pcg(salt))
    h = pcg(h ^ cell.x)
    h = pcg(h ^ cell.y)
    h = pcg(h ^ cell.z)
    return h

hash3(seed, cell, salt) = (hash3_u(seed, cell, salt) >> 8) / 2^24
```

`hash3` returns a value in `[0, 1)`. Only the top 24 bits are used so the
result is exact in float32 as well as in float64.

Callers floor a position into an integer cell and pick a salt per independent
decision on that cell, for example `hash3(ivec3(ivec2(bid), 0), 31u)` for "is
there a bridge in this cell" and `32u` for its x offset.

## Vectors

Produced by `mise run hash-vectors`:

| seed | cell | salt | u32 | value |
| ---: | :--- | ---: | ---: | ---: |
| 0 | (0, 0, 0) | 0 | 920646579 | 0.214354694 |
| 1 | (0, 0, 0) | 0 | 3842895649 | 0.894743860 |
| 0 | (1, 2, 3) | 0 | 1123372911 | 0.261555612 |
| 0 | (0, 0, 0) | 7 | 512537842 | 0.119334459 |
| 12345 | (-1, -2, -3) | 31 | 3729010711 | 0.868227959 |
| 4294967295 | (2147483647, -2147483648, 0) | 4294967295 | 2468706953 | 0.574790597 |
| 3735928559 | (17, -40, 255) | 42 | 3631325278 | 0.845483780 |
| 2654435769 | (-100000, 7, 123456) | 60 | 1065414419 | 0.248061121 |

## Checking the JavaScript version

The same function as in the prototypes; paste into `node` or a browser console
and compare with the table above:

```js
function pcg(v){
  const s = (Math.imul(v, 747796405) + 2891336453) >>> 0;
  const w = Math.imul((s >>> ((s >>> 28) + 4)) ^ s, 277803737);
  return ((w >>> 22) ^ w) >>> 0;
}
function hash3u(seed, x, y, z, salt){
  let h = pcg((seed ^ pcg(salt)) >>> 0);
  h = pcg((h ^ x) >>> 0); h = pcg((h ^ y) >>> 0); h = pcg((h ^ z) >>> 0);
  return h;
}
const hash3 = (seed, x, y, z, salt) => (hash3u(seed, x, y, z, salt) >>> 8) / 16777216;

for (const [seed, x, y, z, salt] of [
  [0, 0, 0, 0, 0], [1, 0, 0, 0, 0], [0, 1, 2, 3, 0], [0, 0, 0, 0, 7],
  [12345, -1, -2, -3, 31], [4294967295, 2147483647, -2147483648, 0, 4294967295],
  [3735928559, 17, -40, 255, 42], [2654435769, -100000, 7, 123456, 60],
]) console.log(`| ${seed} | (${x}, ${y}, ${z}) | ${salt} | ${hash3u(seed, x, y, z, salt)} | ${hash3(seed, x, y, z, salt).toFixed(9)} |`);
```

In a prototype page the seed in use is `state.seed`, so
`hash3(state.seed, x, y, z, salt)` gives the value the shader sees for that
cell.

The shader include was checked on the GPU by rendering `hash3_u` for each row
into an RGBA8 viewport and reading the bytes back; the values match the table.
