class_name SectorGrammar
extends Resource
## Parameters of the hashed sector grammar read by `Skeleton.sector_type()`.
##
## Sizes are in sectors unless the name says metres. Every rule is decided on
## a cell coarser than one sector, so its result spans several sectors:
##     solid    per wall or floor panel on band-aligned planes
##     cavities per cavity_cell^3 sectors
##     shafts   per (ix, iz) column and group of floor layers
##     chasms   per chasm band in x and y
## The defaults are tuned with `mise run skeleton-stats` (issue #78).
## Out-of-range combinations (min above max, a size larger than its cell) are
## clamped when read, so every parameter set gives a total function.
## See docs/algorithms/sector-skeleton-and-walkable-graph.md.

@export_group("Lattice")
## Edge length of one sector in metres (24 fill cells of 2 m).
@export var sector_size: float = 48.0

@export_group("Shaft")
## Chance that a column (ix, iz) holds a shaft through a group of floor layers.
@export_range(0.0, 1.0, 0.01) var shaft_probability: float = 0.12
## Floor layers one shaft decision covers; the shaft continues through the
## open floor panels between them.
@export_range(1, 16) var shaft_layers: int = 3

@export_group("Cavity")
## Edge of the cubic cell a cavity is decided on, in sectors (192 m at 4).
@export_range(1, 16) var cavity_cell: int = 4
## Chance that a cavity cell holds a cavity.
@export_range(0.0, 1.0, 0.01) var cavity_probability: float = 0.15
## Smallest cavity extent along each axis, in sectors.
@export_range(1, 16) var cavity_min_size: int = 3
## Largest cavity extent along each axis, in sectors.
@export_range(1, 16) var cavity_max_size: int = 4

@export_group("Solid")
## Spacing of the bands that each hold one vertical wall plane, in sectors.
@export_range(1, 32) var solid_wall_grid: int = 6
## Edge of the square panels a wall plane closes as a whole, in sectors.
@export_range(1, 128) var solid_wall_panel: int = 12
## Chance that a wall panel is closed.
@export_range(0.0, 1.0, 0.01) var solid_wall_probability: float = 0.6
## Spacing of the bands that each hold one floor plane, in sectors; also the
## mean height of a floor layer.
@export_range(1, 32) var solid_floor_grid: int = 4
## Edge of the square panels a floor plane closes as a whole, in sectors.
@export_range(1, 128) var solid_floor_panel: int = 24
## Chance that a floor panel is closed.
@export_range(0.0, 1.0, 0.01) var solid_floor_probability: float = 0.85

@export_group("Chasm")
## Width of the x band a chasm is decided on, in sectors.
@export_range(1, 256) var chasm_band: int = 32
## Height of the y band a chasm is decided on, in sectors.
@export_range(1, 256) var chasm_band_height: int = 96
## Chance that a band cell holds a chasm.
@export_range(0.0, 1.0, 0.001) var chasm_probability: float = 0.02
## Width of a chasm in x, in sectors (about 280 m at 6).
@export_range(1, 64) var chasm_width: int = 6
## Lowest chasm height, in sectors.
@export_range(1, 256) var chasm_min_height: int = 32
## Highest chasm height, in sectors.
@export_range(1, 256) var chasm_max_height: int = 96
