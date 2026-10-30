extends RefCounted
class_name ProcgenTilesetSetup

## Terrain indices match TinySwordsProceduralEngine:
## 0 DeepWater (unused for peering), 1 FlatGround, 2 ElevatedGround
##
## The Tiny Swords atlas stores each ground type as a complete 16-tile
## side-matching set laid out 4 wide x 4 tall:
##   column: 0 = west cap, 1 = middle, 2 = east cap, 3 = no horizontal neighbour
##   row:    0 = north cap, 1 = middle, 2 = south cap, 3 = no vertical neighbour
## Registering all 16 (instead of only the inner 3x3) is what lets the autotiler
## resolve 1-cell-wide necks, spits and isolated islands correctly.

const TERRAIN_SET := 0
const TERRAIN_DEEP_WATER := 0
const TERRAIN_FLAT := 1
const TERRAIN_ELEVATED := 2
const DEFAULT_SOURCE_ID := 2

const FLAT_ORIGIN := Vector2i(0, 0)
const ELEVATED_ORIGIN := Vector2i(5, 0)

const SIDE_NEIGHBORS := [
	TileSet.CELL_NEIGHBOR_TOP_SIDE,
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
	TileSet.CELL_NEIGHBOR_LEFT_SIDE,
]
## In TERRAIN_MODE_MATCH_SIDES only the four side bits are valid; touching a
## corner bit at all raises an error, so nothing here may reference them.


static func ensure_configured(tileset: TileSet, source_id: int = DEFAULT_SOURCE_ID) -> bool:
	if tileset == null:
		return false
	if not tileset.has_source(source_id):
		push_warning("ProcgenTilesetSetup: missing source_id %d" % source_id)
		return false

	_ensure_terrain_set(tileset)
	var source := tileset.get_source(source_id) as TileSetAtlasSource
	if source == null:
		return false

	_paint_match_sides_4x4(source, FLAT_ORIGIN, TERRAIN_FLAT)
	_paint_match_sides_4x4(source, ELEVATED_ORIGIN, TERRAIN_ELEVATED)
	return true


static func _ensure_terrain_set(tileset: TileSet) -> void:
	if tileset.get_terrain_sets_count() < 1:
		tileset.add_terrain_set()
	## Side-only matching: the atlas has no corner variants, so asking Godot to
	## score corners would make it fall back to approximate tiles at every edge.
	tileset.set_terrain_set_mode(TERRAIN_SET, TileSet.TERRAIN_MODE_MATCH_SIDES)

	while tileset.get_terrains_count(TERRAIN_SET) < 3:
		tileset.add_terrain(TERRAIN_SET)

	tileset.set_terrain_name(TERRAIN_SET, TERRAIN_DEEP_WATER, "DeepWater")
	tileset.set_terrain_color(TERRAIN_SET, TERRAIN_DEEP_WATER, Color(0.2, 0.45, 0.75))
	tileset.set_terrain_name(TERRAIN_SET, TERRAIN_FLAT, "FlatGround")
	tileset.set_terrain_color(TERRAIN_SET, TERRAIN_FLAT, Color(0.35, 0.75, 0.35))
	tileset.set_terrain_name(TERRAIN_SET, TERRAIN_ELEVATED, "ElevatedGround")
	tileset.set_terrain_color(TERRAIN_SET, TERRAIN_ELEVATED, Color(0.55, 0.45, 0.3))


## Registers the full 4x4 side-matching block starting at `origin`.
static func _paint_match_sides_4x4(source: TileSetAtlasSource, origin: Vector2i, terrain: int) -> void:
	for ly in range(4):
		for lx in range(4):
			var atlas: Vector2i = origin + Vector2i(lx, ly)
			if not source.has_tile(atlas):
				continue
			var td: TileData = source.get_tile_data(atlas, 0)
			if td == null:
				continue
			td.terrain_set = TERRAIN_SET
			td.terrain = terrain
			for neighbor in SIDE_NEIGHBORS:
				td.set_terrain_peering_bit(neighbor, -1)
			## Column 0 opens west, 2 opens east, 3 opens both; 1 is enclosed.
			if lx != 0 and lx != 3:
				td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_LEFT_SIDE, terrain)
			if lx != 2 and lx != 3:
				td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_RIGHT_SIDE, terrain)
			## Row 0 opens north, 2 opens south, 3 opens both; 1 is enclosed.
			if ly != 0 and ly != 3:
				td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_SIDE, terrain)
			if ly != 2 and ly != 3:
				td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, terrain)
