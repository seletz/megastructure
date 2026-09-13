class_name SectorGrammar
extends Resource
## Parameters of the hashed sector grammar read by `Skeleton.sector_type()`.
##
## Sizes are in sectors unless the name says metres. Every rule is decided on
## a cell coarser than one sector, so its result spans several sectors:
##     shafts   per (ix, iz) column and vertical segment
##     cavities per cavity_cell^3 sectors
##     solid    per solid_grid^3 block (walls and floors)
##     chasms   per chasm band in x and y
## Out-of-range combinations (min above max, a size larger than its cell) are
## clamped when read, so every parameter set gives a total function.
## See docs/algorithms/sector-skeleton-and-walkable-graph.md.

@export_group("Lattice")
## Edge length of one sector in metres (24 fill cells of 2 m).
@export var sector_size: float = 48.0

@export_group("Shaft")
## Chance that a column segment holds a shaft run.
@export_range(0.0, 1.0, 0.01) var shaft_probability: float = 0.42
## Shortest shaft run, in sectors.
@export_range(1, 64) var shaft_min_len: int = 3
## Longest shaft run, in sectors.
@export_range(1, 64) var shaft_max_len: int = 9
## Height of the vertical segment each run is placed in, in sectors. At least
## shaft_max_len; runs in neighbouring segments may touch.
@export_range(1, 128) var shaft_segment: int = 12

@export_group("Cavity")
## Edge of the cubic cell a cavity is decided on, in sectors (144 m at 3).
@export_range(1, 16) var cavity_cell: int = 3
## Chance that a cavity cell holds a cavity.
@export_range(0.0, 1.0, 0.01) var cavity_probability: float = 0.14
## Smallest cavity extent along each axis, in sectors.
@export_range(1, 16) var cavity_min_size: int = 2
## Largest cavity extent along each axis, in sectors.
@export_range(1, 16) var cavity_max_size: int = 3

@export_group("Solid")
## Edge of the cubic block solid walls and floors are decided on, in sectors.
@export_range(1, 32) var solid_grid: int = 5
## Chance that a block closes its vertical wall plane in x, and again in z.
@export_range(0.0, 1.0, 0.01) var solid_wall_probability: float = 0.35
## Chance that a block closes its horizontal floor plane.
@export_range(0.0, 1.0, 0.01) var solid_floor_probability: float = 0.15

@export_group("Chasm")
## Width of the x band a chasm is decided on, in sectors.
@export_range(1, 256) var chasm_band: int = 32
## Height of the y band a chasm is decided on, in sectors.
@export_range(1, 256) var chasm_band_height: int = 64
## Chance that a band cell holds a chasm.
@export_range(0.0, 1.0, 0.001) var chasm_probability: float = 0.02
## Width of a chasm in x, in sectors (about 280 m at 6).
@export_range(1, 64) var chasm_width: int = 6
## Lowest chasm height, in sectors.
@export_range(1, 256) var chasm_min_height: int = 16
## Highest chasm height, in sectors.
@export_range(1, 256) var chasm_max_height: int = 48
