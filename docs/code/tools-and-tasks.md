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
| `run-skeleton` | import | Runs the skeleton viewer scene, sector boxes around the camera ([[skeleton]]). |
| `import` | | Imports all assets headlessly and regenerates `.godot/`. |
| `check-scripts` | import | Parses every `.gd` file with `--check-only` and fails if any has errors. |
| `smoke` | import | Runs the main scene, then the skeleton viewer scene, headlessly for 60 frames each (120 s timeout per run) and fails if the log contains `SCRIPT ERROR`, `ERROR:`, `Parse Error` or `invalid UID`, printing the offending lines. Catches scene wiring, missing resource and runtime load errors that parsing alone misses. |
| `check` | import, check-scripts, smoke, skeleton-histogram | Additionally loads the project headlessly in editor mode and quits. This is what CI runs ([[ci-and-export]]). |
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
| `skeleton-histogram` | import | Prints the seed 0 sector type histogram and tests `sector_type` against [[skeleton_histogram_seed0]]; `--update` rewrites the reference ([[skeleton]]). Headless; part of `check`. |

`smoke` matches the patterns case-sensitively. Its allow-list for known
benign lines (the `allow` array in the task) is empty, because the run log is
clean. Headless Godot uses the dummy renderer, which never compiles shaders,
so the ray-march shader produces no messages there and shader errors are not
caught by `smoke`.

The window-based checks need a real rendering device because they read back
rendered frames, so they do not run in CI.

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
| [skeleton_histogram.gd](../../scripts/tools/skeleton_histogram.gd) | `skeleton-histogram` | Counts the sector types of the 9 × 9 × 9 sectors around the origin for seed 0, per layer and in total; checks `sector_type` returns a type for 2 000 hashed random cells and the int32 extremes, also under an out-of-range grammar, and that two evaluations (and a fresh `Skeleton`) agree; then compares the table rows with [[skeleton_histogram_seed0]], or rewrites that file with `--update`. |

## How to run or check it

- `mise run check` before every pull request; it must pass.
- Run the check matching what you changed: `preset-check` for presets and the
  registry, `seed-check` and `screenshot-check` (with a display) for the seed
  and HUD, `hash-vectors` for the hash, `skeleton-histogram` for the sector
  grammar, `code-map-check` after adding, moving or removing a source file or
  editing these notes.

## References

- [[0001-all-automation-through-mise]]: why every command is a mise task.
- [[ci-and-export]]: the CI workflows and export tasks in context.
- [[releasing]]: the release tasks in the release process.
- [[maintaining]]: the worktree and pull request tasks in the maintainer loop.
- [[tweak-ui]], [[hash]], [[skeleton]]: what the checks test.
- [[CONVENTIONS]]: keeping these notes in step with the code.
