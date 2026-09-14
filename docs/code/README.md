---
tags:
  - code-map
  - moc
status: current
---

# Code Map

> [!summary]
> Where things live in the source tree and how to try them. The project is
> small: one scene with a flying camera, one large shader that draws the
> whole chasm, a shared hash, a live tweak panel with presets, a set of check
> scripts, and a CI workflow. Each note below explains one of these areas in
> plain words, links its files, and says how to run or check it. Every file
> under `scripts/`, `shaders/` and `scenes/` is linked from exactly one note;
> `mise run code-map-check` enforces that.

Last verified against commit `3cd3cad`.

## Areas

| Area | Note | Covers |
| --- | --- | --- |
| Camera and scene | [[camera-and-scene]] | The main scene, the free-fly camera, the quad the world is drawn on, the environment. |
| Ray-march shader | [[raymarch-shader]] | The world shader and its includes: marching loop, materials, lighting, fog, post, debug views. |
| Hash | [[hash]] | The shared integer hash in the shader and in GDScript, and its reference vectors. |
| Skeleton | [[skeleton]] | The sector grammar parameters and `sector_type`, the first generator layer, and the sector box viewer scene. |
| Walkable graph | [[walkable-graph]] | Portals on the faces between open sectors and interior nodes, the second generator layer. |
| Tileset | [[tileset]] | Tile prototypes with sockets, weights, families and rotations, the tileset resource and its validator. |
| Solver | [[solver]] | `SectorSolver`, which fills a cell grid with tiles by Wave Function Collapse, the sector borders, sector jobs on worker threads, and their checks. |
| Tweak UI | [[tweak-ui]] | World seed, parameter registry, tweak panel, seed control, presets, HUD and their keys. |
| Tools and tasks | [[tools-and-tasks]] | Every mise task and every check script in `scripts/tools/`. |
| CI and export | [[ci-and-export]] | The GitHub check and release workflows, branch protection, the Linux and macOS export presets and templates. |

## Keeping the map current

- A pull request that adds, moves or removes a file under `scripts/`,
  `shaders/` or `scenes/` updates the matching note, and
  `mise run code-map-check` must pass.
- A pull request that changes what a note describes updates the note (see
  [[CONVENTIONS]]).
- After checking the notes against the code, update the commit above.

## Related

- [[Home]]: the wiki's starting page.
- [[algorithms/README|Algorithm notes]]: the ideas behind the code.
- [[decisions/README|Decision log]]: why the code is the way it is.
