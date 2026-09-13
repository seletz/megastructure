---
tags:
  - decision
status: accepted
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/issues/40
  - https://github.com/seletz/megastructure/pull/33
  - https://github.com/seletz/megastructure/pull/39
  - "[[0006-tightened-distance-field-bounds]]"
---

# Facade Layout Overlay as a Knob, Prototype Default

> [!summary]
> Each wall of the chasm is secretly two facades drawn on top of each other,
> each with its own random layout. A recess, a removed buttress or an opening
> only shows where both layouts agree, so these features are much rarer than
> their settings suggest. The port keeps this look by default but exposes it
> as the `facade_overlay` uniform: switched off, each wall gets exactly one
> layout and the settings mean what they say.

## Context

In the prototype, and in `chasm_facade()` in
[chasm.gdshaderinc](../../shaders/include/chasm.gdshaderinc), each facade
side is evaluated at `abs(p.z)`, so both walls receive both layouts. Effective
rates: terrace recesses about 10 % instead of 32 %, buttress removal about
6 % instead of 25 %, openings about 25 % instead of 50 %; some lit openings
never show. Noted in PRs #33 and #39.

Options from #40:

- **(a) Keep it**, since it is how the prototype looks.
- **(b) One layout per wall**, keyed on the sign of `z`, so the nominal rates
  apply. Changes the look for a given seed.
- **(c) A knob** to switch between the two.

## Decision

Option (c), decided by the owner in #40. `uniform bool facade_overlay = true;`
sits in the chasm group of the shader and the tweak panel.

- **On (default):** the prototype's behaviour, `z = abs(p.z)`, both layouts
  on both walls.
- **Off:** `z = p.z`. The side +1 facade exists only on the +z wall and the
  side -1 facade, evaluated at the mirrored point, only on the -z wall. Both
  are still evaluated for every point; from the other half `z` is negative
  and the distance to that facade only grows, so the minimum stays a valid
  lower bound.

## Consequences

- With the default, comparisons with the prototype stay exact.
- With the knob off, recesses, removed buttresses and openings appear at
  their nominal rates, so the rate uniforms have the effect their names
  suggest. The look for a given seed changes.
- The ray-marcher is throwaway, so the knob mostly records which look the
  mesh-based world could aim for; that choice is still open.

## Links

- #40; PRs #33, #39.
- Related: [[0006-tightened-distance-field-bounds]],
  [[0003-ray-marcher-is-a-throwaway-prototype]],
  [[chasm-distance-field]].
