---
tags:
  - decision
status: open
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/issues/40
  - https://github.com/seletz/megastructure/pull/33
  - https://github.com/seletz/megastructure/pull/39
  - "[[0006-tightened-distance-field-bounds]]"
---

# Keep the Overlaid Facade Layouts for Now

> [!warning] Undecided
> This question is open in #40 and waits for a decision from the owner. Until
> then the port keeps the prototype's behaviour.

> [!summary]
> Each wall of the chasm is secretly two facades drawn on top of each other,
> each with its own random layout. A recess, a removed buttress or an opening
> only shows where both layouts agree, so these features are much rarer than
> their settings suggest. The Godot port copies this quirk from the prototype
> for now, because it is what the reference looks like.

## Context

In the prototype, and in `chasm_facades()` in
[chasm.gdshaderinc](../../shaders/include/chasm.gdshaderinc), each facade
side is evaluated at `abs(p.z)`, so both walls receive both layouts. Effective
rates: terrace recesses about 10 % instead of 32 %, buttress removal about
6 % instead of 25 %, openings about 25 % instead of 50 %; some lit openings
never show. Noted in PRs #33 and #39.

## Decision

Not yet taken. Options from #40:

- **(a) Keep it**, since it is how the prototype looks. This is the current
  state.
- **(b) One layout per wall**, keyed on the sign of `z`, so the nominal rates
  apply. Changes the look for a given seed.
- **(c) A knob** to switch between the two.

## Consequences

- Until decided, comparisons with the prototype stay exact.
- Tuning the rate uniforms has a weaker effect than their names suggest.
- Either choice is low effort. The ray-marcher is throwaway, so the choice
  matters mostly as a record of which look the mesh-based world should aim
  for.

## Links

- #40; PRs #33, #39.
- Related: [[0006-tightened-distance-field-bounds]],
  [[0003-ray-marcher-is-a-throwaway-prototype]].
