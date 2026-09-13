# Research: WFC / model synthesis for the sector fill layer

Scope: the fill layer of `MEGASTRUCTURE_CONCEPT.md` §2.3 (2 m voxels, 24³ = 13 824
cells per 48 m sector, hand-authored tiles with a socket per face, walkable-graph
cells pre-collapsed, deterministic per `(seed, sector)`), implemented in Godot
4.7 with Godot-native rendering. The ray-marched renderer from 0.0.1 is a
throwaway (`PLAN_0.0.1.md`, "Scope"); nothing below depends on it except the
shared integer hash (`docs/hash_vectors.md`), which the fill layer must reuse.

Short version: use a simple-tiled adjacency solver, treat each sector as one
Merrell-style "block" whose faces are fixed before the interior is solved,
make every random decision a call to the project hash, keep the solver behind
an interface that a GDExtension can replace later, and place with
`MultiMeshInstance3D` after a short `GridMap` phase.

## 1. Algorithm choice

Three candidates:

**Overlapping model** (Gumin's original, N×N patterns learned from an example
bitmap or voxel model; [mxgmn/WaveFunctionCollapse](https://github.com/mxgmn/WaveFunctionCollapse)).
It needs an example volume and produces per-voxel labels, not tile placements.
Our tiles are hand-authored meshes with sockets, and the tile vocabulary is
already fixed by the prototypes (§3 of the concept). Gumin also notes that the
3D overlapping model with 5×5×5 blocks is expensive. Reject.

**Simple-tiled WFC** (Gumin's "SimpleTiledModel": tiles + allowed-neighbour
pairs, min-entropy cell choice, propagation, restart on contradiction). This is
the model the concept already assumes. Pre-collapsed cells are trivial: restrict
the cell's domain before the first observation ("It's extremely easy to add
support for constraints by forcing a particular cell to contain a particular
tile", [Boris the Brave, tips](https://www.boristhebrave.com/2020/02/08/wave-function-collapse-tips-and-tricks/)).
Sector boundaries are the same mechanism: fix the boundary cells to whatever
the neighbour produced. Its known weakness is scale: as the output grows, the
chance of a contradiction somewhere grows until "it is virtually impossible to
get a successful run no matter how many times you restart"
([Boris the Brave, modifying in blocks](https://www.boristhebrave.com/2021/10/26/model-synthesis-and-modifying-in-blocks/)).
Merrell's comparison paper attributes much of the extra failure to the
lowest-entropy ordering on large outputs, whereas for small outputs "the order
has little impact and the failure rate is low in either case"
([Merrell 2021, comparison.pdf](https://paulmerrell.org/wp-content/uploads/2021/07/comparison.pdf)).

**Model synthesis, modify-in-blocks** (Merrell 2007/2009,
[paulmerrell.org](https://paulmerrell.org/model-synthesis/),
[merrell42/model-synthesis](https://github.com/merrell42/model-synthesis), MIT).
Same constraint solver (AC-4 or AC-3 propagation, no backtracking) but the
output starts from a trivial valid state (all "ground"/solid), and is modified
one small block at a time with the block's border fixed to the surrounding
already-valid tiles; a failed block is simply retried or left as it was. It is
the scaling fix for the weakness above. Boris's port went "much larger" than
plain WFC on a hard tileset but found it "very fiddly" and "sensitive to
generation order", with redundant work from the block overlap
([same article](https://www.boristhebrave.com/2021/10/26/model-synthesis-and-modifying-in-blocks/)).
A recent refinement, Punch Out Model Synthesis, erodes the boundary of an
already-resolved region when a sub-block fails, and introduces the useful idea
of a "tile correlation length" that bounds the block size a tileset can
tolerate ([arXiv 2501.14786](https://arxiv.org/abs/2501.14786)).

**Recommendation.** A simple-tiled solver, with the sector as the block. The
distinction between "WFC" and "model synthesis" mostly evaporates at this
granularity: a 24³ sector with fixed faces and a universal solid fallback *is*
a modify-in-blocks step over an implicit all-solid world. What we take from
Merrell is the discipline, not the code: start from a trivially valid state,
fix the borders, solve one block, never let a block failure poison its
neighbours. Concretely:

- **Pre-collapsed cells.** Walkable-graph cells get a *domain restriction*, not
  a single tile: `{floor, floor+column, doorway}` for corridor cells, a specific
  oriented stair tile for stair cells. Restricting instead of collapsing keeps
  the solver free to pick walls and columns around the path.
- **Sector boundaries.** Two options. (a) Order-dependent: a sector copies the
  boundary tiles of whichever neighbours already exist. Simple, but the result
  of sector S then depends on load order, which violates "every decision is a
  pure function of (seed, cell coordinates)" and makes unloading non-free.
  (b) Order-independent: solve shared faces first. Each 24² face between two
  non-solid sectors is a 2D solve seeded by `hash3(seed, face_cell, salt)`,
  itself pre-collapsed at the graph portals; edges (24¹) are solved before
  faces so that adjacent faces agree at their shared line; then the interior is
  solved with all six faces fixed. Both sectors compute the identical face
  independently, so any sector can be generated in isolation and in parallel.
  This is the scheme to use. It is the 3D analogue of Boris's layered
  "infinite modifying in blocks", which gets its constant-time, deterministic
  property from a fixed dependency tree per block ("there's a fixed amount of
  work to be done for each block of the output",
  [Boris the Brave](https://www.boristhebrave.com/2021/11/08/infinite-modifying-in-blocks/));
  our tree is edges → faces → interior, depth 3.
  Risk: fixing all six faces can over-constrain the interior. The universal
  solid tile (§3) guarantees an interior solution always exists; the remaining
  risk is aesthetic, and the mitigation is to weight faces heavily toward
  solid and air so the interesting geometry lives inside the sector.
- **Determinism.** Every random draw is `hash3_u(seed, cell, salt)` with a
  per-sector counter folded into the salt. Do not use `RandomNumberGenerator`
  for anything that must be reproducible: "The underlying algorithm is an
  implementation detail and should not be depended upon"
  ([class reference](https://docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html)).
  This also keeps a later GDExtension port bit-identical to the GDScript one.
  Floating-point entropy ties are another source of drift; see §3.

## 2. Socket-based adjacency authoring

The convention that has proven itself for 3D modules is Marian42's, also used
in Martin Donald's video and the notes on it
([marian42.de/article/wfc](https://marian42.de/article/wfc/),
[Christian Mills' notes](https://christianjmills.com/posts/wave-function-collapse-for-3d-notes/index.html)):

- Six sockets per module: `+x -x +z -z` (horizontal) and `+y -y` (vertical).
- Horizontal socket = integer id plus a symmetry tag: `3s` is mirror-symmetric
  and matches `3s`; `3` (asymmetric) matches only its mirrored counterpart `3f`.
  The rule "a matches b" is: same id, and either both `s`, or exactly one is
  `f`.
- Vertical socket = integer id plus a rotation index `_0.._3`, or `i` for
  rotation-invariant: `5_1` on a top face matches `5_1` on the bottom face of
  the tile above. This is what stops a stair landing from sitting on a rotated
  stair.
- Rotations are generated, not authored: a prototype with `rotations = 4`
  expands to four tiles; each rotation permutes the horizontal sockets and
  increments the vertical rotation index modulo 4. Symmetric prototypes declare
  `rotations = 1` or `2` (Gumin's `X / I / L / T / \ / F` letters express the
  same thing for 2D, [mxgmn README](https://github.com/mxgmn/WaveFunctionCollapse)).
  Mirrored variants (negative scale) are not worth it initially; they flip
  winding and normals, and the tileset in §3 of the concept has no chiral
  modules that need them.
- An explicit `air` module (all sockets `0s`/`0i`) and a `solid` module (all
  sockets `1s`/`1i`) exist as ordinary tiles; the "universal" behaviour of solid
  (§3) is expressed by a wildcard socket, not by special-casing the solver.
- Marian42 also keeps an explicit exclusion list to forbid pairs that are
  socket-compatible but ugly; keep this door open but expect not to need it.

**Derivation.** `allowed[dir][a]` is a bitset over tiles: `b` is set iff
`socket(a, dir)` matches `socket(b, opposite(dir))`. This is O(tiles² × 6) once
at load; for ~20 prototypes × ≤4 rotations it is negligible.

**Validation** (a headless `mise` task, run in CI):

1. Every socket id used on a `+d` face has at least one match on some `-d`
   face, otherwise the tile can never have a neighbour in that direction and
   will cause a contradiction whenever it is placed away from the boundary.
2. Every tile has a non-empty allowed set in all six directions (same failure,
   weaker check).
3. Reachability: BFS over the adjacency graph starting from `air` and `solid`;
   any tile not reached is unreachable in practice, because every sector starts
   as air/solid on its faces.
4. Symmetric-tagged sockets really are symmetric: quantise the tile mesh's
   vertices lying on that face plane, hash the set, and compare with the hash
   of the mirrored set. The same "face profile hash" can later *derive* socket
   ids automatically (Stålberg's Bad North talk describes deriving adjacency
   from geometry rather than hand-writing pairs,
   [EPC 2018](https://www.youtube.com/watch?v=0bcZb-SsnrA)), but for the
   box-only placeholder tileset hand-written ids in a resource file are faster
   to iterate on.
5. Solve a 6³ grid with no constraints 100 times; report per-tile placement
   counts. Tiles with zero placements are effectively dead (usually a weight or
   socket mistake). Boris's "if you drop a tile, WFC tries its best with what
   remains" is the flip side: dead tiles are a diagnostic, not a crash.

Store the tileset as a Godot `Resource` (`.tres`) so the inspector edits it
and `mise run check` parses it; Godot 4.7 also adds a dedicated `MeshLibrary`
editor, which helps the GridMap phase ([Godot 4.7 release notes](https://godotengine.org/releases/4.7/)).

## 3. Contradiction handling, entropy and propagation

**Failure model.** With a universal solid tile the argument is exact: solid is
never removed from any unconstrained cell's domain, because its support in
every direction is the neighbour's whole domain; a domain therefore can only
become empty if the cell was pre-restricted to non-solid tiles *and* every
neighbour's domain lost all tiles compatible with that restriction, which
again requires those neighbours to be pre-restricted. So contradictions can
only occur between pre-collapsed cells that were inconsistent to begin with,
i.e. a bug in the path-graph rasteriser, and the all-solid interior is always a
valid completion. This is the "start from a trivial solution" property that
makes Merrell's approach robust ([merrell42/model-synthesis](https://github.com/merrell42/model-synthesis)).

The catch is that a fully universal solid produces stairs that walk into
walls and bridges that end in mass. Realistically a handful of sockets (stair
exits, bridge and catwalk ends, doorway floors) must *not* accept solid. Then
contradictions become possible but rare, and the expected failure rate at 24³
is low because the block is small and the tileset is mostly permissive
("for small textures and models, the order has little impact and the failure
rate is low", [Merrell 2021](https://paulmerrell.org/wp-content/uploads/2021/07/comparison.pdf)).
Tile weights matter mainly through the heuristic: heavy weights on air and
solid make early observations pick permissive tiles, which keeps domains open.

**Policy (in order):**

1. Restart the sector with sub-seed `n+1` (salt bump), cap at e.g. 8 attempts.
   Deterministic, no state, matches the concept doc.
2. After the cap, deterministic degradation: keep the pre-collapsed cells,
   fill the rest by propagation from an all-solid assignment, log the sector.
   The player still gets a walkable path.
3. No backtracking. Marian42 needed it for a ~100-module city with hard
   constraints and still judged the experience "unsuitable for commercial
   games" when errors surface late ([marian42](https://marian42.de/article/wfc/));
   DeBroglie shows full backtracking is implementable but costs time and memory
   ([DeBroglie](https://github.com/BorisTheBrave/DeBroglie)). Revisit only if
   step 2 fires visibly often, which would indicate a tileset problem rather
   than a solver problem.

**Cell choice.** Gumin uses minimum Shannon entropy so weights influence the
order ([Boris, WFC explained](https://www.boristhebrave.com/2020/04/13/wave-function-collapse-explained/)).
Karth and Smith found a lexicographic (scanline) order performs similarly
because it keeps choices close to previous ones
([Karth & Smith 2017](https://adamsmith.as/papers/wfc_is_constraint_solving_in_the_wild.pdf)),
and Merrell reports scanline gives a lower failure rate on large outputs with
no quality cost, at the price of directional artefacts ([Wikipedia summary](https://en.wikipedia.org/wiki/Model_synthesis)).
For a 24³ block use "minimum remaining values" (domain size) with a hashed
tie-break: it needs no floats, is bit-reproducible across GDScript and a native
port, and at this size is indistinguishable from Shannon entropy. Keep Shannon
as an option behind a flag for A/B comparison. Weighted tile choice within a
cell: prefix sums of integer weights over the remaining domain, index by
`hash3_u`.

**Propagation.** Two standard designs:

- *AC-4 support counts* (Gumin's `compatible[cell][tile][dir]` arrays; Boris
  describes the mechanism; Merrell's code and fast-wfc use it): incremental,
  O(1) per removed support, but the table is `cells × tiles × 6` counters. At
  13 824 × ~80 × 6 ≈ 6.6 M entries, a `PackedByteArray` (counts ≤ 255) costs
  ~7 MB per in-flight sector. Fine in native code, heavy for GDScript.
- *Bitset AC-3*: domain per cell is `k` 64-bit ints (GDScript `int` is 64-bit;
  80 tiles → 2 words). When a cell's domain shrinks, for each direction compute
  `mask = OR over remaining tiles of allowed[dir][tile]` and `AND` it into the
  neighbour; enqueue the neighbour if it changed. Per update cost is
  O(|domain| × k) word ops, no counters, memory is `cells × k` ints. This is the
  right design for the GDScript prototype and probably sufficient forever.

Precompute `allowed[dir][tile]` as `PackedInt64Array` and store the wave as
one `PackedInt64Array` of `cells × k` words; both are thread-friendly and
serialise trivially. Keep a `PackedInt32Array` domain-size cache per cell for
the MRV heuristic, plus a min-heap or a simple bucket-by-size list (the 24³
grid is small enough that a bucket scan is fine).

## 4. Performance in Godot 4

**Expectations.** GDScript is a bytecode interpreter; typed GDScript uses
"optimized opcodes when operand/argument types are known at compile time"
([static typing guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html)),
and 4.6 further reduced call overhead. Historic measurements put untyped
GDScript at ~10× slower than C# on a Game-of-Life loop (Godot 3.2,
[godot#36060](https://github.com/godotengine/godot/issues/36060)); the gap is
"most pronounced" in tight numerical loops, which a propagator is
([StraySpark 2026](https://www.strayspark.studio/blog/gdscript-vs-csharp-godot-2026-choosing-scripting-language)).
Rough budget for one sector with the bitset design: ~14 k observations, each
propagating to a few dozen cells with a few hundred word operations → 10⁶–10⁷
primitive operations, i.e. roughly 0.5–3 s in typed GDScript per sector on one
worker thread. That is acceptable for "WFC in one sector" and marginal for
streaming (a 3³ neighbourhood is 27 sectors; parallel workers help, and only
non-solid sectors need solving). Measure before deciding; a benchmark task is
part of the solver epic.

**When to go native.** If a stratum sector takes > 1 s in GDScript after
typing and bitsets, move only `SectorSolver.solve()` to a GDExtension. Rust via
[godot-rust/gdext](https://github.com/godot-rust/gdext) supports 4.7
([changelog](https://github.com/godot-rust/gdext/blob/master/Changelog.md))
and mise can pin the toolchain; C++ via
[godot-cpp](https://github.com/godotengine/godot-cpp) is the other option. C#
would be a middle step but adds a .NET dependency to a project that is
otherwise GDScript, and does not remove the "recompile per change" cost once
you are past the interpreter. The interface stays the same either way: input
`PackedInt64Array` domains + tileset tables, output `PackedInt32Array` tile
index per cell. Expect 20–100× over GDScript from a native propagator
(fast-wfc reports "an order of magnitude" over an already-native baseline just
from data-layout work, [fast-wfc](https://github.com/math-fehr/fast-wfc), MIT).

**Threads.** One `WorkerThreadPool.add_task()` per sector; poll
`is_task_completed()` from `_process` and always call
`wait_for_task_completion()` afterwards ("Every task must be waited for
completion" so resources are cleaned up,
[WorkerThreadPool](https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html)).
Never wait for a task from inside another task. Rules for what the task may
touch ([thread-safe APIs](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html)):

- No scene tree access. Building nodes outside the tree is allowed, but the
  cheaper pattern is to produce plain data (`PackedFloat32Array` MultiMesh
  buffer per tile type, `PackedVector3Array` collision faces, tile ids) and let
  the main thread create nodes.
- `RenderingServer` and `PhysicsServer3D` calls are not thread-safe unless the
  separate-thread project settings are enabled; assigning `MultiMesh.buffer` or
  `ConcavePolygonShape3D.set_faces()` goes through those servers, so do it on
  the main thread. Those are single bulk calls per sector and cheap.
- Packed arrays and `Array`/`Dictionary` element reads/writes are fine from a
  thread; anything that resizes needs a mutex. Give each task its own arrays
  and hand them back by value.
- Tile mesh faces (`Mesh.get_faces()`) are read once on the main thread at
  startup and cached per tile as `PackedVector3Array`; workers only transform
  and concatenate them.

**Memory layout.** Wave: `PackedInt64Array(cells × k)`. Allowed masks:
`PackedInt64Array(6 × tiles × k)`. Domain sizes: `PackedByteArray(cells)`.
Result: `PackedInt32Array(cells)` tile index (rotation baked into the index).
All indexable by `x + 24*(y + 24*z)`; nothing is a `Dictionary`.

## 5. Placement in Godot

**GridMap vs MultiMeshInstance3D.** `GridMap` renders each octant with an
internal MultiMesh per mesh, supports 24 orthogonal orientations via
`get_orthogonal_index_from_basis()`, and has built-in static collision and a
2 m default cell size that matches ours
([GridMap](https://docs.godotengine.org/en/stable/classes/class_gridmap.html)).
It is the fastest way to walk on a solved sector, and with 4.7's MeshLibrary
editor the box tileset takes minutes to set up. Its limits are known: one draw
call per (octant, mesh) which does not scale with large tilesets
([godot-proposals#12110](https://github.com/godotengine/godot-proposals/issues/12110)),
no per-instance custom data, and it is not a `VisualInstance3D` so it cannot
be layer-culled. For streaming, switch to one `MultiMeshInstance3D` per
(tile mesh, sector): ~20 nodes per sector, one draw call each, transforms
uploaded in one `PackedFloat32Array` via `buffer`/`set_buffer`, and
`custom_aabb` set to the sector box to avoid AABB recomputation
([MultiMesh](https://docs.godotengine.org/en/stable/classes/class_multimesh.html)).
Rotation goes into the instance transform, so rotated variants share a
MultiMesh. Note that the class reference does not document the `buffer` float
layout; the placement issue should verify it against
`multimesh_get_buffer()` of a hand-built instance (12 floats per 3D
transform, then 4 for colour and 4 for custom data when enabled) and pin it
with a test.

**Collision.** Early: GridMap's own collision. Later: one
`StaticBody3D` + `ConcavePolygonShape3D` per sector, faces built on the worker
by transforming the cached tile faces (skip faces of solid cells that touch
other solid cells to keep the mesh small). Trimesh is "the slowest 3D
collision shape to check collisions against" but is intended for static
geometry, which this is
([ConcavePolygonShape3D](https://docs.godotengine.org/en/stable/classes/class_concavepolygonshape3d.html));
Jolt (already the project's physics engine) handles large static trimeshes
well. Alternative for a box-only tileset: one `BoxShape3D` per run-length of
solid cells; fewer triangles for the capsule to test but more shapes; try
trimesh first.

**Streaming.** Load sectors within radius R (Chebyshev distance in sector
units) of the player's sector, unload beyond R+1; the extra ring is the
hysteresis. Because faces are order-independent (§1), loading order is
irrelevant and unloading is just `queue_free()`. Keep a small LRU of solved
sector results so walking back and forth does not re-solve.

**LOD and impostors.** Visibility ranges give artist-controlled HLOD with
hysteresis margins, `visibility_parent` hides children when the parent
impostor shows, and MultiMeshInstance3D supports ranges directly
([visibility ranges](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html)).
So: per sector, MultiMesh nodes with `visibility_range_end ≈ 2 sectors`, and a
single impostor mesh (sector box with slab lines, or a simplified merge of the
solid cells) with `visibility_range_begin` at the same distance. Automatic
mesh LOD is per node, so all instances in a MultiMesh share one LOD level
([mesh LOD](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html));
irrelevant for box placeholders. Fog does the rest.

**Godot features that fit.** Forward+ with exponential fog and a single
`OmniLight3D` headlight is the look. Global illumination: SDFGI is the only GI
that regenerates for geometry created at runtime and "scales to any world
size", but it is among the most expensive techniques and shows cascade
shifts; VoxelGI needs baking per region and leaks through thin walls
([GI overview](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/introduction_to_global_illumination.html),
[SDFGI](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_sdfgi.html)).
Start without GI (near-black ambient is the design), evaluate SDFGI in the
look pass. Occlusion culling does not bake MultiMeshInstance3D, but an
`ArrayOccluder3D` per sector built from the solid-cell boxes is cheap and
effective for interiors
([occlusion culling](https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html)).
4.7's `AreaLight3D` is a candidate for the rare lit opening.

## 6. Existing addons and reference implementations

Godot 4 (none is a drop-in for socket-authored 3D tiles with pre-collapsed
cells; all are worth reading for structure):

| Project | Licence | Notes |
| --- | --- | --- |
| [AlexeyBond/godot-constraint-solving](https://github.com/AlexeyBond/godot-constraint-solving) (asset 1951) | MIT, GDScript | Learn-from-example, backtracking, multithreaded 2D; GridMap only as a flat plane, "3d map generation not yet implemented". Good reference for a GDScript solver's structure and its preconditions API. |
| [Mehdi-Saleh/Godot-WFC-Csharp](https://github.com/Mehdi-Saleh/Godot-WFC-Csharp) (asset 2473) | MIT, C#, 4.2 | Sample-based 2D/3D over GridMap with threading; wrong authoring model for us. |
| [MarkusMannil/WaveFunctionCollapse3DPlugin](https://github.com/MarkusMannil/WaveFunctionCollapse3DPlugin) (asset 2888) | MIT | Godot 3.5, rule editor for object sides. |
| [Astral-Sheep/WaveFunctionCollapse](https://github.com/Astral-Sheep/WaveFunctionCollapse) | MIT, C#, 4.0 | 2D/3D core with interfaces; small. |
| [willosborne/wave-function-collapse-godot](https://github.com/willosborne/wave-function-collapse-godot) | no licence | C#, 3D sockets from Blender tiles; read only. |
| [Max-Beier/wavefunctioncollapse-godot](https://github.com/Max-Beier/wavefunctioncollapse-godot), [douze/estm](https://github.com/douze/estm) | MIT | Nascent / 2D Godot 3.4. |

Godot 4.7 replaced the Asset Library with an Asset Store; the numbered
asset-library links above still resolve.

Other engines and languages, well documented:

- [mxgmn/WaveFunctionCollapse](https://github.com/mxgmn/WaveFunctionCollapse), MIT, C#: the reference simple-tiled model and symmetry letters.
- [merrell42/model-synthesis](https://github.com/merrell42/model-synthesis), MIT, C++: modify-in-blocks, AC-4/AC-3 propagation, 3D tiled model output.
- [marian42/wavefunctioncollapse](https://github.com/marian42/wavefunctioncollapse), MIT, Unity C#: the socket/rotation convention, boundary constraint maps, infinite slots, backtracking.
- [BorisTheBrave/DeBroglie](https://github.com/BorisTheBrave/DeBroglie), MIT, C#: 3D, backtracking, path and fixed-tile constraints, tile symmetry handling; the best-engineered open solver to crib propagator and constraint interfaces from. Tessera (Unity Asset Store, US$4.99 / US$49.99 Pro) is its commercial sibling; its docs on infinite generation are useful, its code is not reusable.
- [math-fehr/fast-wfc](https://github.com/math-fehr/fast-wfc), MIT, C++: performance-oriented overlapping/tiled solver; the reference if a native port is needed.

Verdict: write the solver fresh in typed GDScript (it is ~500 lines), borrow
the tileset conventions from Marian42 and the propagator structure from
DeBroglie/Merrell, and reuse nothing from the Godot addons except ideas.

## 7. Proposed breakdown of milestone 0.0.2

Five epics, following the concept's milestone order. Each sub-issue is one
branch/worktree `<number>-<slug>` and one PR against `develop`. "AC" =
acceptance criteria; every AC that can be checked headlessly becomes a
`mise` task and runs in CI.

### Epic A: Skeleton viewer

Sector types from a hashed grammar and a debug view to tune it.

- **A1 `sector_type(seed, ix, iy, iz)` and grammar parameters.** Pure GDScript
  function over `hash3_u`, returning stratum/shaft/cavity/solid/chasm with the
  grammar biases from concept §2.1 (vertical continuation of shafts, horizontal
  spread of strata, clustered voids). Parameters live in the existing tweak
  registry. AC: unit test script under `scripts/tools/` prints a 9×9×9 type
  histogram for seed 0 and asserts the function is total and deterministic
  (two calls agree); the reference type counts for seed 0 are checked into
  `docs/`.
- **A2 Sector box debug renderer.** A scene that draws every sector within
  radius R of the free-fly camera as a colour-coded wireframe/box via one
  MultiMeshInstance3D per type, refreshing as the camera crosses sector
  bounds. AC: 5³ region draws at 60 fps; type colours match a legend in the
  HUD; R adjustable from the panel.
- **A3 Grammar tuning pass.** Iterate biases until the outside view reads as
  structured, with before/after screenshots at a fixed camera pose attached to
  the PR. AC: shafts span ≥ 3 sectors vertically on average; solid mass
  partitions the region into ≥ 2 visually separated blocks per 5³.

### Epic B: Walkable graph

Deterministic connectivity per 3³ region, rendered as lines, verified by
union-find.

- **B1 Portals and interior nodes.** For each pair of adjacent non-solid
  sectors, one portal point on the shared face chosen by hash; one interior
  node per stratum sector. AC: portal positions are identical whichever of the
  two sectors asks for them (test over 100 random pairs).
- **B2 Spanning tree plus hashed loops.** Kruskal over sector adjacency with
  hashed edge weights inside each 3³ region, then extra hashed edges; vertical
  edges rare and long. AC: union-find over every 5³ window for seeds 0..9
  reports one component per window of non-solid sectors; test is a `mise`
  task.
- **B3 Graph debug lines.** Draw edges as `ImmediateMesh` lines coloured by
  edge type, toggled from the panel. AC: screenshot of a 3³ region with legend.
- **B4 Edge rasteriser (the fill contract).** Convert each sector's edges to a
  list of `(cell, domain restriction, orientation)` records: corridor cells →
  floor family, stair edges → oriented stair tiles, bridges → bridge family.
  This is the only input the solver accepts from the graph. AC: the record list
  for a sector depends only on `(seed, sector)`; a test checks that no two
  records in one sector conflict (same cell, disjoint domains) over 1 000
  random sectors.

### Epic C: Tileset and adjacency

- **C1 Tile resource format.** A `Resource` describing mesh, weight, six
  sockets (`id`, `s`/`f`, vertical rotation index), `rotations` (1/2/4) and an
  optional exclusion list; a `Tileset` resource holding them. AC: loads under
  `mise run check`; documented in `docs/`.
- **C2 Rotation expansion and adjacency derivation.** Expand prototypes to
  rotated tiles; build `allowed[dir][tile]` as `PackedInt64Array` bitsets.
  AC: unit tests for the socket matching rules (`s`/`s`, `n`/`nf`, vertical
  rotation index) and for a 90° rotation permuting sockets correctly.
- **C3 Tileset validation task.** `mise run tiles-check`: dead sockets,
  directions with empty allowed sets, reachability from air/solid, symmetric
  sockets checked against the mirrored face profile of the mesh, and a
  100-run 6³ placement histogram. AC: task fails on a deliberately broken
  fixture tileset and passes on the real one; runs in CI.
- **C4 Box-only placeholder tileset.** ~10 prototypes as `BoxMesh`/simple
  `ArrayMesh` at the concept's proportions: air, solid, floor slab, slab edge
  with parapet, column, wall, wall with doorway, stair (one stratum in 3 cells),
  bridge segment, catwalk. AC: passes C3; a screenshot of every rotated tile in
  a contact sheet scene.

### Epic D: Solver

- **D1 Solver core.** Typed GDScript `SectorSolver` with `PackedInt64Array`
  wave, bitset AC-3 propagation, MRV cell choice with hashed tie-break, hashed
  weighted tile choice, all randomness from `hash3_u` with a counter salt.
  AC: solves an unconstrained 8³ grid with the C4 tileset; the same
  `(seed, sector)` yields byte-identical output across runs and across the
  editor/headless runtimes.
- **D2 Pre-collapse and restart policy.** Accept B4 records and fixed
  boundary faces; restart with bumped sub-seed up to N attempts, then the
  deterministic all-solid degradation; report attempts and outcome. AC: a test
  with inconsistent records fails fast with a clear error; a test with
  consistent records never returns a cell violating them.
- **D3 Face-first boundary solve.** Solve shared edges, then faces, then the
  interior, each seeded from its own geometric key. AC: the face computed from
  sector S and from S+1 is identical (test over 100 random faces); two
  adjacent solved sectors have no socket mismatch across the shared face.
- **D4 Benchmark task.** `mise run wfc-bench` solves 10 stratum sectors and
  prints mean/max time, attempts, and contradiction count. AC: numbers
  recorded in the PR; if mean > 1 s on the dev machine, open a follow-up issue
  for the GDExtension port with the interface frozen by D1.

### Epic E: Placement, walking and streaming

- **E1 GridMap placement.** Map solver output to `set_cell_item` with
  orthogonal orientation indices; walk it with a `CharacterBody3D` capsule
  using the existing camera controls. AC: one stratum sector at seed 0 is
  walkable from portal to portal along the B4 path without falling through or
  getting stuck.
- **E2 MultiMesh placement and merged collision.** Replace GridMap with one
  MultiMeshInstance3D per (mesh, sector) built from a worker-produced
  `PackedFloat32Array` buffer (layout pinned by a test), plus one
  `ConcavePolygonShape3D` per sector from worker-transformed cached tile faces.
  AC: same walk as E1 passes; draw calls per sector ≤ number of tile meshes;
  buffer layout test.
- **E3 Worker-thread sector jobs.** `WorkerThreadPool` task per sector
  producing plain data; main thread polls, waits, and instantiates. AC: the
  main thread never blocks > 4 ms per frame while 27 sectors are solved
  (measured with the profiler); every task id is waited on (no leak warning on
  exit).
- **E4 Streaming with hysteresis and LRU.** Load within R, unload beyond R+1,
  cache solved results, sector impostor via visibility ranges. AC: walking
  through 10 sectors in a straight line never shows a hole at a boundary;
  memory returns to baseline after walking back; a settings entry for R.

## Decisions to make

1. **Boundary scheme:** face-first order-independent faces (recommended) vs
   copy-from-loaded-neighbour. Decide before D3; it changes the streaming
   design.
2. **How universal is `solid`:** fully universal (provably no contradictions,
   uglier stairs and bridge ends) vs a few non-solid-accepting sockets with
   restart. Recommend the latter with the all-solid degradation as the floor.
3. **Cell-choice heuristic:** MRV with hashed tie-break (recommended, integer
   only) vs Shannon entropy. Keep both behind a flag until D4 data exists.
4. **Native threshold:** the D4 number above which `SectorSolver.solve()` moves
   to a Rust GDExtension. Proposed: > 1 s per stratum sector.
5. **GridMap lifetime:** only E1, or keep it as a debug/editor tool alongside
   the MultiMesh path.
6. **Path-cell semantics:** domain families (recommended) vs single fixed tiles
   per path cell; affects B4 and the tileset's socket design.
7. **Whether pipes and cables are tiles at all** (concept §7): recommend a
   separate decoration pass after the decay pass, keeping the tileset small.
