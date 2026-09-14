---
tags:
  - code-map
  - tooling
status: current
---

# Tools and Tasks

> [!summary]
> Everything you do with the project, from opening the editor to running a
> check, is a named task in one file, [mise.toml](../../mise.toml). The tool
> `mise` also installs the exact Godot version the project needs, so you never
> call a separately installed Godot. Most checks are small GDScript programs
> in `scripts/tools/` that load the main scene, poke at it and print "ok" or
> "FAIL" lines; each has its own task.

## Setup

`mise install` fetches the pinned tools from [mise.toml](../../mise.toml):
Godot 4.7.2-stable, Node 26, and the Godot MCP server package. The file also
sets `GODOT_PATH` to the mise-managed Godot binary, because the MCP server
only looks there. Run tasks with `mise run <task>`; `mise tasks` lists them.

## Tasks

Tasks marked "import" first run the `import` task, so the `.godot/` cache is
up to date.

| Task | Depends on | What it does |
| --- | --- | --- |
| `editor` | | Opens the project in the Godot editor. |
| `run` | import | Runs the main scene. |
| `run-skeleton` | import | Runs the skeleton viewer scene, wireframe sector cubes around the camera ([[skeleton]]). |
| `import` | | Imports all assets headlessly and regenerates `.godot/`. |
| `check-scripts` | import | Parses every `.gd` file with `--check-only` and fails if any has errors. |
| `smoke` | import | Runs the main scene, then the skeleton viewer and the tile contact sheet scenes, headlessly for 60 frames each (120 s timeout per run) and fails if the log contains `SCRIPT ERROR`, `ERROR:`, `Parse Error` or `invalid UID`, printing the offending lines. Catches scene wiring, missing resource and runtime load errors that parsing alone misses. |
| `check` | import, check-scripts, smoke, panel-check, skeleton-histogram, skeleton-stats, graph-check, graph-connectivity, raster-check, tileset-check, adjacency-check, tiles-check-fixtures, tileset-build-check, tiles-check-placeholder | Additionally loads the project headlessly in editor mode and quits. This is what CI runs ([[ci-and-export]]). |
| `templates` | | Downloads the export templates for the pinned Godot version into `~/.local/share/godot/export_templates/`, skipping if present. |
| `export` | import | Exports a release build: `mise run export <preset> <output>`. |
| `export-debug` | import | Same as `export` with a debug build. |
| `release:notes` | | Prints the Unreleased section of [[CHANGELOG]], the notes of the next release. |
| `release:changelog-roll` | | `release:changelog-roll <version> [--date YYYY-MM-DD] [--dry-run]`: renames Unreleased to `<version> - <date>`, opens a fresh Unreleased section above it and commits `chore(release): <version>`. |
| `release:bump` | | `release:bump <patch\|minor\|major> [--push] [--dry-run]`: raises `config/version` in `project.godot`, commits `chore(release): start <new>`, pushes the current branch with `--push` and prints the new version. |
| `release:package` | | `release:package <linux\|macos>`: packs the exported build into `build/release/megastructure-<version>-linux-x86_64.tar.gz` or `-macos-universal.zip`; in the release workflow it fails if the tag does not match the version. |
| `release:release` | | Releases the version in `project.godot`: checks it runs on a clean, up-to-date `develop` with `gh` logged in, then calls `release:notes` and `release:changelog-roll`, tags `v<version>`, pushes, creates the GitHub release and calls `release:bump patch` and pushes. `--dry-run` prints every command instead. See [[releasing]]. |
| `wt:new` | | `wt:new <issue> <slug> [--base-dir DIR] [--herdr] [--dry-run]`: fetches, creates the worktree `<issue>-<slug>` on a new branch from `origin/develop` (default folder `~/.herdr/worktrees/megastructure`), trusts it with mise and prints its path. See [[maintaining]]. |
| `wt:rm` | | `wt:rm <branch> [--dry-run]`: refuses on uncommitted changes, an unfinished rebase or merge, or commits that are on no branch of origin; otherwise removes the worktree, deletes the branch and prunes. |
| `pr:status` | | Lists open pull requests with branch, merge state and check results. |
| `pr:merge` | | `pr:merge <number> [--no-rebase] [--timeout SECONDS] [--dry-run]`: rebases the PR's worktree onto `origin/develop` (aborting on conflict), pushes with `--force-with-lease`, waits for the `check` run of the pushed HEAD, merges with a merge commit and fast-forwards `develop` in the main checkout. See [[maintaining]]. |
| `mcp` | | Runs the Godot MCP server over stdio, used by `.mcp.json`. |
| `clean` | | Deletes `.godot/` and `build/`. |
| `hash-vectors` | import | Prints the hash reference table ([[hash]]). Headless. |
| `ui-params` | import | Prints the shader parameter groups the tweak panel discovers ([[tweak-ui]]). Headless. |
| `seed-check` | import | Tests the seed control and seed-reproducible frames. Opens a window. |
| `screenshot-check` | import | Tests the HUD screenshot. Opens a window. |
| `preset-check` | import | Tests that presets round-trip bit for bit. Headless. |
| `code-map-check` | import | Tests that every source file is linked from exactly one code map note. Headless. |
| `shot` | import | `shot <scene> <out.png> [--seed N] [--pose x,y,z,yaw,pitch] [--frames N] [--params k=v,...] [--resolution WxH] [--ui] [--window]`: renders one frame of a scene to a PNG under `xvfb-run` (X11, OpenGL) so no window opens; without `xvfb-run`, or with `--window`, it opens a normal window. See [[screenshots]]. |
| `skeleton-histogram` | import | Prints the seed 0 sector type histogram and tests `sector_type` against [[skeleton_histogram_seed0]]; `--update` rewrites the reference ([[skeleton]]). Headless; part of `check`. |
| `skeleton-stats` | import | Measures the sector grammar over 20 random 5³ regions per seed 0 to 4 and fails unless shafts run at least 3 sectors on average and solid splits a region into at least 2 non-solid components on average ([[sector-skeleton-and-walkable-graph]]). Headless; part of `check`. |
| `graph-check` | import | Checks the walkable graph's portals and interior nodes over 100 random adjacent open sector pairs per seed 0 to 4 ([[walkable-graph]]). Headless; part of `check`. |
| `graph-connectivity` | import | Checks the walkable graph's edges for every boundary scheme and tunnel weight variant over a random and a chasm-centred 15³ sample per seed 0 to 9 and fails unless every region-aligned 3³, 6³ and 9³ window has one component of open sectors; reports per variant the tunnel fraction, tunnels with a chasm or cavity end, strict 5³ windows and the mean vertical run ([[walkable-graph-connectivity]]). `--variants=a,b` runs only some. Headless; part of `check`. |
| `raster-check` | import | Checks the edge rasteriser over 1 000 random sectors at seeds 0 to 4: determinism, no conflicting records, cells inside the sector, portal openings in both endpoint sectors, no rejected edge, and every walk changing level only on stairs and ladders; prints family counts and the stair cells level changes produce ([[edge-rasteriser]]). Headless; part of `check`. |
| `tileset-check` | import | Checks the tile resource format: the socket string grammar on every face, a prototype of every tile family, that the fixture tileset validates and that the broken fixture reports exactly its expected errors ([[tileset]]). Headless; part of `check`. |
| `adjacency-check` | import | Checks tile rotation expansion and the adjacency bitsets: socket matching rules, a hand-computed quarter turn against Godot's basis, the worked example, exclusions both ways, the fixture tileset's table, the word layout past 64 tiles, pairwise agreement and symmetry; prints build times and the fixture dump ([[tileset]]). Headless; part of `check`. |
| `adjacency-dump` | import | Prints the rotated tiles and adjacency table of a tileset: `mise run adjacency-dump <res://…tres>`; exits 1 with the validation errors of an invalid one ([[tileset]]). |
| `tiles-check` | import | Validates a tileset beyond its format: `mise run tiles-check <tileset.tres> [--max-contradiction-rate R] [--runs N] [--seed N]`. Fails on dead sockets, directions with no allowed tile, tiles unreachable from air and solid, `Ns` faces whose mesh profile is not mirror-symmetric, a tile never placed in 100 runs on a 6³ grid, or a contradiction rate above the threshold (default 0.5); prints the placement histogram ([[socket-adjacency#Validation]]). Headless. |
| `tiles-check-fixtures` | import | Self-test of `tiles-check`: the fixture tileset passes, the dead socket fixture fails with exactly its expected categories, placement is deterministic per seed, and the mesh symmetry check passes, fails and skips built meshes ([[tileset]]). Headless; part of `check`. |
| `tileset-build` | import | Regenerates `resources/tilesets/placeholder.tres` from `resources/tilesets/placeholder_builder.gd`, the box-only placeholder tileset ([[tileset#The placeholder tileset]]). Headless. |
| `tileset-build-check` | import | Builds the placeholder tileset into a temporary file and fails when the committed resource differs (script ids aside) or when it misses a tile family ([[tileset]]). Headless; part of `check`. |
| `tiles-check-placeholder` | import | `tiles-check` on the placeholder tileset with the default options ([[socket-adjacency#Worked example: the placeholder tileset]]). Headless; part of `check`. |
| `panel-check` | import | Clicks every kind of script-backed widget in the skeleton viewer's tweak panel and checks each setter ran ([[tweak-ui]]). Headless; part of `check`. |

`smoke` matches the patterns case-sensitively. Its allow-list for known
benign lines (the `allow` array in the task) is empty, because the run log is
clean. Headless Godot uses the dummy renderer, which never compiles shaders,
so the ray-march shader produces no messages there and shader errors are not
caught by `smoke`.

The window-based checks need a real rendering device because they read back
rendered frames, so they do not run in CI. To get an image of a scene without
a window, use `shot`, which renders inside Xvfb ([[screenshots]]). Every
other tool task runs `--headless`.

The `release:*` tasks follow one rule: `develop` always carries the NEXT
version. `release:release` tags the version already in `project.godot` and
never edits it before tagging; right afterwards `release:bump patch` moves
`develop` on ([[0014-develop-is-always-the-next-version]]). The file-changing
release tasks print each command as `+ command` and accept `--dry-run`, and
so do the `wt:*` and `pr:*` tasks that change anything.

## Tool scripts

Each script `extends SceneTree` and is started with
`godot --path . --script res://scripts/tools/<name>.gd` by its task. The
checks print one `ok` or `FAIL` line per expectation and a final summary, and
exit with status 1 on any failure.

| Script | Task | What it does |
| --- | --- | --- |
| [hash_vectors.gd](../../scripts/tools/hash_vectors.gd) | `hash-vectors` | Prints `hash3_u` and `hash3` for eight fixed inputs as a Markdown table; must match [[hash_vectors]]. |
| [registry_dump.gd](../../scripts/tools/registry_dump.gd) | `ui-params` | Builds a parameter registry on the main scene's ray-march material and prints every group and parameter with type, default, range and step. |
| [seed_check.gd](../../scripts/tools/seed_check.gd) | `seed-check` | Checks seed parsing and clamping, that `seed_changed` fires once per change, that the uniform follows the seed, that a different seed renders a different frame and the same seed an identical one (grain and HUD turned off), and the seed field and R key. |
| [screenshot_check.gd](../../scripts/tools/screenshot_check.gd) | `screenshot-check` | Takes a HUD screenshot and checks the file name, folder and resolution, and that the HUD and panel were hidden for that frame and shown again afterwards; then presses H, F1 and P and checks they toggle the HUD and hint and save a screenshot, and are ignored while the seed field has focus. |
| [preset_check.gd](../../scripts/tools/preset_check.gd) | `preset-check` | Changes every parameter, the seed and the camera, saves a preset, loads the defaults, reloads the preset from disk and compares everything bitwise, including a restart and delete; also tests name validation and exact float reading. Uses a scratch `user://preset_check` folder. |
| [code_map_check.gd](../../scripts/tools/code_map_check.gd) | `code-map-check` | Collects every file under `scripts/`, `shaders/` and `scenes/` (except `.uid` and `.import`), scans the links in `docs/code/*.md`, and fails if a file is linked from no note or from more than one, or if a link points at a missing source file. |
| [shot.gd](../../scripts/tools/shot.gd) | `shot` | Loads a scene with saved presets off, sets the seed, the FreeFlyCamera pose and registry params by name (typed by the registry), waits the frames, grabs a frame with `Hud.grab_frame` (HUD and panel hidden unless `--ui`), checks the resolution and saves the PNG; prints `shot: <problem>` and exits 1 on any error. |
| [skeleton_histogram.gd](../../scripts/tools/skeleton_histogram.gd) | `skeleton-histogram` | Counts the sector types of the 9 × 9 × 9 sectors around the origin for seed 0, per layer and in total; checks `sector_type` returns a type for 2 000 hashed random cells and the int32 extremes, also under an out-of-range grammar, and that two evaluations (and a fresh `Skeleton`) agree; then compares the table rows with [[skeleton_histogram_seed0]], or rewrites that file with `--update`. |
| [skeleton_stats.gd](../../scripts/tools/skeleton_stats.gd) | `skeleton-stats` | Samples 20 random 5 × 5 × 5 sector regions for each seed 0 to 4 and prints the type fractions, the mean vertical shaft run (each run followed past the region to its full length), the non-solid components per region (6-connected union-find), the cavity clusters per region and the stratum run lengths along x, z and y; fails below 3 sectors of shaft run or 2 components. `measure()` and `print_stats()` are static, so a scratch script can compare grammars. |
| [graph_check.gd](../../scripts/tools/graph_check.gd) | `graph-check` | For each seed 0 to 4, draws random adjacent sector pairs (within ±100 000 sectors) until 100 have two open sectors and 20 a solid one; checks `portal(a, b)` equals `portal(b, a)` and the portal of a fresh graph exactly, lies on the shared face at least one cell inside its edges, on the 2 m grid and, on a vertical face, at the floor level of the lower sector's interior node; that the x and z edge portals around 20 sample sectors, tunnels included, lie at the lower sector's hub level; that solid pairs and 8 kinds of non-adjacent pair (same sector, diagonals, two or three apart) return null; that both sectors' interior nodes carry their type and lie inside the margin on the grid at a floor level; and that `nodes_in_region` of a 3³ region returns exactly its open sectors in order. |
| [graph_connectivity_check.gd](../../scripts/tools/graph_connectivity_check.gd) | `graph-connectivity` | For each graph variant in `VARIANTS` (boundary scheme and `void_wall_tunnels_last`, default marked) and each seed 0 to 9, takes the 5³ regions (15³ sectors) at a hashed offset within ±10 000 regions, and again centred on the lower x wall of the first chasm along +x, and computes their edges and the boundary edges between them on a caching skeleton; checks every edge joins face-adjacent sectors in order with the kind `edge_kind` gives and a portal on their face (equal to `portal` for open pairs), that a fresh graph gives identical region edges, that regions whose open sectors are open-connected with no solid terminal have no tunnel, and that `edges_for_sector` matches for 40 sectors. Then union-find per window, only over edges with both ends inside: fails unless all 125 region-aligned 3³, 64 6³ and 27 9³ windows have one component of non-solid sectors; prints how many of the 1 331 5³ windows at every offset of the random sample have one, next to what every open-open adjacency without tunnels would reach, the tunnel fraction, the tunnels with a chasm or cavity end (and how many lie on boundary faces), the faces left without an edge, the edge kinds and the mean vertical run (stacked stair and ladder edges), then one table row per variant and sample. |
| [raster_check.gd](../../scripts/tools/raster_check.gd) | `raster-check` | Checks `merge` is commutative and idempotent over every pair of families and orientations. For each seed 0 to 4, draws 200 sectors within ±100 000 (salt 904) and rasterises each on a caching skeleton and on a fresh graph, which must agree record for record; checks one record per cell inside 0..23, that every record of each edge's walk merges into the final record without conflict, that both endpoint sectors of every edge hold a portal opening at its portal cell, that no edge is rejected, that the records form one 26-connected group, and steps through each walk from the hub to the portal: flat to flat only at one level, onto, along and off stairs in their orientation, on and off ladders. Prints the family counts, the mean records and stair cells per sector and the stair, ladder and landing cells of the walks. |
| [tileset_check.gd](../../scripts/tools/tileset_check.gd) | `tileset-check` | Parses valid and invalid socket strings (`3s`, `3f`, `5_2`, `0i`; `03`, `3S`, `5_4`, a bare `5` on a vertical face) on all six faces and compares id, symmetric, flipped and rotation, and the string printed back; validates a `BoxMesh` prototype of every `TileFamily` and of `FAMILY_NONE` and rejects families −2 and 7; loads `tests/fixtures/tilesets/fixture_tileset.tres` and checks it validates, its prototypes, `find`, meshes, weight, rotations and parsed sockets, and that `missing_families` and `validate(true)` report the six families other than floor; loads `broken_tileset.tres` and compares its `validate()` list with the 14 expected lines in order. |
| [adjacency_check.gd](../../scripts/tools/adjacency_check.gd) | `adjacency-check`, `adjacency-dump` | Checks `TileLibrary.sockets_match` and `partner_key` on 28 horizontal and vertical pairs; turns `1 2s 5_0 6_3 3f 4` once and twice against hand-computed rows, four times and back, and compares `QUARTER_TURN` with each face normal turned by `Basis(Vector3.UP, PI / 2)`; rebuilds the A/B/C worked example of [[socket-adjacency]]; checks an exclusion between a prototype and all four rotations of another in all six directions; loads the fixture tileset and compares its 5 tile labels, weight, sockets and all 30 bitsets; builds 66 tiles and checks two words per entry, the bits at 63 and 64 and out-of-range arguments; checks every table equals the pairwise socket rule and is symmetric. Prints build times and the fixture dump. With `-- --dump <path>` it only prints that tileset's dump. |
| [tiles_check.gd](../../scripts/tools/tiles_check.gd) | `tiles-check`, `tiles-check-fixtures` | Loads a tileset, builds its `TileLibrary` (stopping at validation errors) and reports, one `FAIL  <category>: <message>` line each: sockets whose partner no tile shows on the opposite face, tiles with an empty allowed bitset in a direction, tiles a breadth-first search from every rotation of air and solid does not reach, `Ns` faces whose mesh vertices within 0.01 m of the face plane have no mirror image across the face's centre line within 0.001 m (`BoxMesh` via `get_mesh_arrays`, `ArrayMesh` via `surface_get_arrays`, warning for no vertex data), tiles never placed and a contradiction rate above `--max-contradiction-rate`. The placement fills a 6³ grid `--runs` times: cells in `hash3_u` order, weighted `hash3` choice, bitset AC-3 propagation, restart with the next attempt seed on a contradiction, at most 8 restarts; prints tile counts, shares and the rate. With `-- --self-test` it checks both fixtures, determinism per seed, the threshold and four built meshes. |
| [panel_check.gd](../../scripts/tools/panel_check.gd) | `panel-check` | Opens the skeleton viewer's tweak panel with Tab and pushes mouse clicks: on the `show_stratum` box and its label, a press without release on `follow_camera`, the up arrows of the `radius`, `shaft_probability` and `solid_wall_grid` spin boxes and the `sector_size` slider; checks the viewer or grammar value changed each time. |

## How to run or check it

- `mise run check` before every pull request; it must pass.
- Run the check matching what you changed: `preset-check` for presets and the
  registry, `seed-check` and `screenshot-check` (with a display) for the seed
  and HUD, `hash-vectors` for the hash, `skeleton-histogram` and `skeleton-stats` for the
  sector grammar, `graph-check`, `graph-connectivity` and `raster-check` for the walkable graph, `tileset-check` for tile resources, `adjacency-check` for rotation expansion and the adjacency table, `tileset-build` then `tiles-check-placeholder` for the placeholder tileset, `panel-check` for the tweak panel widgets, `code-map-check` after adding, moving or removing a source file or
  editing these notes.
- Need to see a change? `mise run shot scenes/main.tscn build/shots/main.png`
  renders it without a window.

## References

- [[0001-all-automation-through-mise]]: why every command is a mise task.
- [[ci-and-export]]: the CI workflows and export tasks in context.
- [[releasing]]: the release tasks in the release process.
- [[maintaining]]: the worktree and pull request tasks in the maintainer loop.
- [[screenshots]]: how `shot` renders without a window, and troubleshooting.
- [[tweak-ui]], [[hash]], [[skeleton]], [[walkable-graph]]: what the checks test.
- [[CONVENTIONS]]: keeping these notes in step with the code.
