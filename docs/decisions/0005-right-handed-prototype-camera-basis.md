---
tags:
  - decision
status: accepted
date: 2026-09-13
links:
  - https://github.com/seletz/megastructure/issues/34
  - https://github.com/seletz/megastructure/pull/35
  - https://github.com/seletz/megastructure/pull/33
---

# Right-Handed Camera Basis in the Prototypes

> [!summary]
> The HTML prototypes turned out to show their image upside down: the camera
> was built so that the top of the screen looked at the ground. Because the
> chasm looks much the same either way up, nobody noticed. We fixed the
> prototypes rather than bending the Godot camera to match them, so both now
> show the same, upright view.

## Context

While comparing the facades port (PR #33) with
[megastructure-chasm.html](../megastructure-chasm.html), the Godot view looked
mirrored left to right. The cause was in the prototypes: their camera "right"
vector was `(cos yaw, 0, -sin yaw)`, which made the derived "up" vector point
down. The image was rotated 180 degrees about the view axis. The chasm is
vertically symmetric, so lit deck tops below the camera appeared at the top
of the screen and read as light from above. The Godot camera was a standard
upright right-handed camera and correct.

## Decision

Fix the prototypes (option 1 of #34): flip the right vector to
`(-cos yaw, 0, sin yaw)` in both shaders and in the JavaScript movement
basis, so strafing still matches the screen. The alternative, rotating every
side-by-side screenshot before comparing, was rejected.

## Consequences

- Prototype and Godot screenshots at the same pose line up without
  post-processing.
- The prototype image rotated once; the world and its look are unchanged.
- Mouse look now turns toward the drag direction.
- The fog gradient ("light bleeding down from far above") finally appears at
  the top of the screen in the prototypes.

## Links

- #34, PR #35.
- PR #33: where the mismatch was found.
- Related: [[0004-shared-integer-hash-replaces-float-hash]] (the other
  change made to the prototypes).
