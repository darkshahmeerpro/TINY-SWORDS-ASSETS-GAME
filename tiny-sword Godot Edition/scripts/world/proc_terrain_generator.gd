@tool
extends Node2D
class_name ProcTerrainGenerator

## Rules-strict Tiny Swords procgen (.cursor/rules + Pixel Frog layer stack).
## BG → Foam → Flat → Shadow1 → Elev1 → Shadow2 → Elev2 → Decor

enum LayerStack {
	BG_COLOR,
	WATER_FOAM,
	FLAT_GROUND,
	ELEV1_SHADOW,
	ELEV1_GROUND,
	ELEV2_SHADOW,
	ELEV2_GROUND,
	DECOR,
}

## Discrete height: 0 water, 1 flat, 2 elev1, 3 elev2.
enum HeightLevel { WATER = 0, FLAT = 1, ELEV1 = 2, ELEV2 = 3 }

const TILE_SIZE := 64
const FOAM_SCENE := preload("res://scenes/world/water_foam.tscn")

## Cardinal cliff bitmask: N=1, E=2, S=4, W=8
const CLIFF_N := 1
const CLIFF_E := 2
const CLIFF_S := 4
const CLIFF_W := 8

@export_group("Actions")
@export_tool_button("Generate") var generate_action: Callable = generate
@export_tool_button("Clear") var clear_action: Callable = clear_all

@export_group("Map")
@export var map_size: Vector2i = Vector2i(48, 32)
@export var clear_before_generate: bool = true

@export_group("Noise")
@export var seed_val: int = 42
@export_range(0.001, 0.2, 0.001) var continent_frequency: float = 0.028
@export_range(0.001, 0.2, 0.001) var elevation_frequency: float = 0.05
@export_range(1, 8, 1) var octaves: int = 4

@export_group("Biome Thresholds")
@export_range(0.0, 1.0, 0.01) var water_max: float = 0.42
@export_range(0.0, 1.0, 0.01) var elev1_min: float = 0.55
@export_range(0.0, 1.0, 0.01) var elev2_min: float = 0.78

@export_group("Layers")
@export var foam_layer_path: NodePath = ^"FoamLayer"
@export var ground_layer_path: NodePath = ^"GroundLayer"
@export var shadow_layer1_path: NodePath = ^"ShadowLayer1"
@export var elevated_layer1_path: NodePath = ^"ElevatedLayer1"
@export var shadow_layer2_path: NodePath = ^"ShadowLayer2"
@export var elevated_layer2_path: NodePath = ^"ElevatedLayer2"
@export var decor_layer_path: NodePath = ^"DecorLayer"
@export var tile_set: TileSet

@export_group("Terrain")
@export var ground_source_id: int = 2
@export var terrain_set: int = 0
@export var flat_terrain: int = 0
@export var elevated_terrain: int = 1
@export var shadow_source_id: int = 12
@export var shadow_atlas: Vector2i = Vector2i(0, 0)
@export var walkable_cliff_atlas: Vector2i = Vector2i(6, 4)
@export var water_cliff_atlas: Vector2i = Vector2i(6, 5)
@export var elevated_center_atlas: Vector2i = Vector2i(6, 1)
@export var stair_top_atlas: Vector2i = Vector2i(6, 1)
@export var stair_cliff_bottom_atlas: Vector2i = Vector2i(6, 4)

@export_group("Decor")
@export_range(0.0, 1.0, 0.01) var tree_density: float = 0.4
@export_range(0.0, 1.0, 0.01) var bush_density: float = 0.08
@export var decor_min_spacing: int = 0
@export var tree_source_ids: PackedInt32Array = PackedInt32Array([4, 5, 6, 7])
@export var bush_source_ids: PackedInt32Array = PackedInt32Array([6, 7])

var _foam_layer: TileMapLayer
var _ground_layer: TileMapLayer
var _shadow1: TileMapLayer
var _elev1: TileMapLayer
var _shadow2: TileMapLayer
var _elev2: TileMapLayer
var _decor_layer: TileMapLayer
var _foam_sprites: Node2D
var _continent: FastNoiseLite
var _elevation: FastNoiseLite
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Rulebook: shift shadow render by one 64px tile down per elevation index.
func CalculateTileOffsets(elevation_index: int) -> Vector2:
	return Vector2(0, TILE_SIZE * elevation_index)


func _ready() -> void:
	_resolve_layers()
	_apply_shadow_offsets()
	_ensure_tileset()
	if Engine.is_editor_hint():
		return
	generate()


func _resolve_layers() -> void:
	_foam_layer = get_node_or_null(foam_layer_path) as TileMapLayer
	_ground_layer = get_node_or_null(ground_layer_path) as TileMapLayer
	_shadow1 = get_node_or_null(shadow_layer1_path) as TileMapLayer
	_elev1 = get_node_or_null(elevated_layer1_path) as TileMapLayer
	_shadow2 = get_node_or_null(shadow_layer2_path) as TileMapLayer
	_elev2 = get_node_or_null(elevated_layer2_path) as TileMapLayer
	_decor_layer = get_node_or_null(decor_layer_path) as TileMapLayer
	# Legacy fallbacks
	if _shadow1 == null:
		_shadow1 = get_node_or_null("ShadowLayer") as TileMapLayer
	if _elev1 == null:
		_elev1 = get_node_or_null("ElevatedLayer") as TileMapLayer
	if _elev1 == null:
		_elev1 = get_node_or_null("CliffLayer") as TileMapLayer

	_foam_sprites = get_node_or_null("FoamSprites") as Node2D
	if _foam_sprites == null and _foam_layer:
		_foam_sprites = _foam_layer.get_node_or_null("FoamSprites") as Node2D
	if _foam_sprites == null:
		_foam_sprites = Node2D.new()
		_foam_sprites.name = "FoamSprites"
		var parent: Node = _foam_layer if _foam_layer else self
		parent.add_child(_foam_sprites)
		if Engine.is_editor_hint():
			_foam_sprites.owner = get_tree().edited_scene_root


func _apply_shadow_offsets() -> void:
	if _shadow1:
		_shadow1.position = CalculateTileOffsets(1)
	if _shadow2:
		_shadow2.position = CalculateTileOffsets(2)


func _ensure_tileset() -> void:
	if tile_set == null:
		tile_set = load("res://resources/terrain/procgen_tileset.tres") as TileSet
	if tile_set == null:
		push_warning("ProcTerrainGenerator: no TileSet assigned")
		return
	if not Engine.is_editor_hint():
		tile_set = tile_set.duplicate(true)
	ProcgenTilesetSetup.ensure_configured(tile_set, ground_source_id)
	for layer in [_foam_layer, _ground_layer, _shadow1, _elev1, _shadow2, _elev2, _decor_layer]:
		if layer:
			layer.tile_set = tile_set


func clear_all() -> void:
	_resolve_layers()
	for layer in [_foam_layer, _ground_layer, _shadow1, _elev1, _shadow2, _elev2, _decor_layer]:
		if layer:
			layer.clear()
	_clear_foam_sprites()


func _clear_foam_sprites() -> void:
	if _foam_sprites == null:
		return
	for child in _foam_sprites.get_children():
		child.queue_free()


func generate() -> void:
	_resolve_layers()
	_apply_shadow_offsets()
	_ensure_tileset()
	if _ground_layer == null or _elev1 == null:
		push_warning("ProcTerrainGenerator: Ground/ElevatedLayer1 missing")
		return

	if clear_before_generate:
		clear_all()

	_rng.seed = seed_val
	_continent = FastNoiseLite.new()
	_continent.seed = seed_val
	_continent.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_continent.frequency = continent_frequency
	_continent.fractal_type = FastNoiseLite.FRACTAL_FBM
	_continent.fractal_octaves = octaves

	_elevation = FastNoiseLite.new()
	_elevation.seed = seed_val + 1337
	_elevation.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_elevation.frequency = elevation_frequency
	_elevation.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_elevation.fractal_octaves = 3

	var width: int = maxi(map_size.x, 1)
	var height: int = maxi(map_size.y, 1)
	var levels: Array = []
	levels.resize(width)
	for x in width:
		var col: Array = []
		col.resize(height)
		for y in height:
			col[y] = _classify_height(x, y)
		levels[x] = col

	var flat_cells: Array[Vector2i] = []
	var elev1_cells: Array[Vector2i] = []
	var elev2_cells: Array[Vector2i] = []
	for x in width:
		for y in height:
			var cell := Vector2i(x, y)
			match levels[x][y]:
				HeightLevel.FLAT:
					flat_cells.append(cell)
				HeightLevel.ELEV1:
					elev1_cells.append(cell)
				HeightLevel.ELEV2:
					elev2_cells.append(cell)

	# Flat ground
	if not flat_cells.is_empty():
		_ground_layer.set_cells_terrain_connect(flat_cells, terrain_set, flat_terrain, true)

	# Elevation 1 tops + cliffs + shadows
	if not elev1_cells.is_empty() and _elev1:
		_elev1.set_cells_terrain_connect(elev1_cells, terrain_set, elevated_terrain, true)
		_place_cliff_bitmasks(levels, width, height, HeightLevel.ELEV1, _elev1)
		_place_shadows(elev1_cells, _shadow1)

	# Elevation 2 tops + cliffs + shadows
	if not elev2_cells.is_empty() and _elev2:
		_elev2.set_cells_terrain_connect(elev2_cells, terrain_set, elevated_terrain, true)
		_place_cliff_bitmasks(levels, width, height, HeightLevel.ELEV2, _elev2)
		_place_shadows(elev2_cells, _shadow2)

	_place_stairs(levels, width, height)
	_place_foam(levels, width, height)
	_place_decor(levels, width, height)

	if Engine.is_editor_hint():
		update_configuration_warnings()


func _norm(noise: FastNoiseLite, x: int, y: int) -> float:
	return clampf((noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5, 0.0, 1.0)


func _classify_height(x: int, y: int) -> int:
	var land: float = _norm(_continent, x, y)
	if land <= water_max:
		return HeightLevel.WATER
	var elev: float = _norm(_elevation, x, y)
	if elev >= elev2_min:
		return HeightLevel.ELEV2
	if elev >= elev1_min:
		return HeightLevel.ELEV1
	return HeightLevel.FLAT


func _neighbor_height(levels: Array, width: int, height: int, x: int, y: int, d: Vector2i) -> int:
	var nx: int = x + d.x
	var ny: int = y + d.y
	if nx < 0 or ny < 0 or nx >= width or ny >= height:
		return HeightLevel.WATER
	return levels[nx][ny]


## Build N/E/S/W cliff bitmask; separate water cliffs from walkable cliffs.
func _build_cliff_mask(levels: Array, width: int, height: int, x: int, y: int, my_level: int) -> Dictionary:
	var dirs := [
		{"bit": CLIFF_N, "d": Vector2i(0, -1)},
		{"bit": CLIFF_E, "d": Vector2i(1, 0)},
		{"bit": CLIFF_S, "d": Vector2i(0, 1)},
		{"bit": CLIFF_W, "d": Vector2i(-1, 0)},
	]
	var water_mask := 0
	var walkable_mask := 0
	for entry in dirs:
		var nh: int = _neighbor_height(levels, width, height, x, y, entry["d"])
		if nh >= my_level:
			continue
		if nh == HeightLevel.WATER:
			water_mask |= entry["bit"]
		else:
			walkable_mask |= entry["bit"]
	return {"water": water_mask, "walkable": walkable_mask}


func _place_cliff_bitmasks(
	levels: Array, width: int, height: int, my_level: int, layer: TileMapLayer
) -> void:
	if layer == null or tile_set == null or not tile_set.has_source(ground_source_id):
		return
	for x in width:
		for y in height:
			if levels[x][y] != my_level:
				continue
			var masks: Dictionary = _build_cliff_mask(levels, width, height, x, y, my_level)
			var water_mask: int = masks["water"]
			var walkable_mask: int = masks["walkable"]
			if water_mask == 0 and walkable_mask == 0:
				continue
			# Prefer water cliffs when that edge touches water; else walkable cliffs.
			# Paint on the lower neighbor cell south/east/etc. for visible face.
			_paint_cliff_edges(layer, Vector2i(x, y), water_mask, true)
			_paint_cliff_edges(layer, Vector2i(x, y), walkable_mask, false)


func _paint_cliff_edges(layer: TileMapLayer, cell: Vector2i, mask: int, toward_water: bool) -> void:
	if mask == 0:
		return
	var atlas: Vector2i = water_cliff_atlas if toward_water else walkable_cliff_atlas
	var offsets := {
		CLIFF_N: Vector2i(0, -1),
		CLIFF_E: Vector2i(1, 0),
		CLIFF_S: Vector2i(0, 1),
		CLIFF_W: Vector2i(-1, 0),
	}
	for bit in offsets.keys():
		if (mask & bit) == 0:
			continue
		var face_cell: Vector2i = cell + offsets[bit]
		layer.set_cell(face_cell, ground_source_id, atlas, 0)


func _place_shadows(elevated_cells: Array[Vector2i], shadow_layer: TileMapLayer) -> void:
	## Same cell as elevated top; layer.position from CalculateTileOffsets shifts render down.
	if shadow_layer == null or tile_set == null:
		return
	if not tile_set.has_source(shadow_source_id):
		return
	for cell in elevated_cells:
		shadow_layer.set_cell(cell, shadow_source_id, shadow_atlas, 0)


func _place_stairs(levels: Array, width: int, height: int) -> void:
	## Case 1: elev borders walkable (flat / lower elev) without water → one top center.
	## Case 2: elev borders water cliff edge → top + cliff-bottom splice.
	## Sparse: one stair every few cells along south edges so cliffs stay readable.
	if tile_set == null or not tile_set.has_source(ground_source_id):
		return
	var pairs := [
		{"level": HeightLevel.ELEV1, "layer": _elev1, "lower": HeightLevel.FLAT},
		{"level": HeightLevel.ELEV2, "layer": _elev2, "lower": HeightLevel.ELEV1},
	]
	for pair in pairs:
		var layer: TileMapLayer = pair["layer"]
		if layer == null:
			continue
		var my_level: int = pair["level"]
		var lower: int = pair["lower"]
		for x in width:
			for y in height:
				if levels[x][y] != my_level:
					continue
				if (x + y) % 5 != 0:
					continue
				var south: int = _neighbor_height(levels, width, height, x, y, Vector2i(0, 1))
				if south != lower and south != HeightLevel.WATER:
					continue
				var cell := Vector2i(x, y)
				var below := Vector2i(x, y + 1)
				if south == HeightLevel.WATER:
					layer.set_cell(cell, ground_source_id, stair_top_atlas, 0)
					layer.set_cell(below, ground_source_id, stair_cliff_bottom_atlas, 0)
				else:
					layer.set_cell(cell, ground_source_id, stair_top_atlas, 0)


func _place_foam(levels: Array, width: int, height: int) -> void:
	## Foam on every flat/elev cell that borders deep water; stagger frames.
	_clear_foam_sprites()
	if _foam_sprites == null:
		return
	if _foam_layer:
		_foam_layer.clear()

	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for x in width:
		for y in height:
			var level: int = levels[x][y]
			if level == HeightLevel.WATER:
				continue
			var touches_water := false
			for d in dirs:
				if _neighbor_height(levels, width, height, x, y, d) == HeightLevel.WATER:
					touches_water = true
					break
			if not touches_water:
				continue
			var cell := Vector2i(x, y)
			var splash: AnimatedSprite2D = FOAM_SCENE.instantiate() as AnimatedSprite2D
			var local_pos: Vector2
			if _foam_layer:
				local_pos = _foam_layer.map_to_local(cell)
			elif _ground_layer:
				local_pos = _ground_layer.map_to_local(cell)
			else:
				local_pos = Vector2(cell) * float(TILE_SIZE) + Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)
			splash.position = local_pos
			_foam_sprites.add_child(splash)
			if Engine.is_editor_hint():
				splash.owner = get_tree().edited_scene_root
			if splash.sprite_frames and splash.sprite_frames.has_animation(&"foam"):
				var count: int = splash.sprite_frames.get_frame_count(&"foam")
				if count > 0:
					splash.frame = _rng.randi() % count
				splash.play(&"foam")


func _place_decor(levels: Array, width: int, height: int) -> void:
	if _decor_layer == null:
		return
	var occupied: Dictionary = {}
	for x in width:
		for y in height:
			var level: int = levels[x][y]
			if level == HeightLevel.WATER:
				continue
			if _borders_water(levels, width, height, x, y):
				continue
			if level >= HeightLevel.ELEV1 and _is_cliff_rim(levels, width, height, x, y, level):
				continue
			if decor_min_spacing > 0 and _too_close(occupied, x, y, decor_min_spacing):
				continue

			var roll: float = _rng.randf()
			var cell := Vector2i(x, y)
			var chance: float = tree_density
			if level == HeightLevel.ELEV1:
				chance *= 0.7
			elif level == HeightLevel.ELEV2:
				chance *= 0.5
			if roll < chance and tree_source_ids.size() > 0:
				var sid: int = tree_source_ids[_rng.randi() % tree_source_ids.size()]
				if sid >= 4 and sid <= 7:
					_decor_layer.set_cell(cell, sid, Vector2i(0, 0), 0)
					occupied[cell] = true
			elif level == HeightLevel.FLAT and roll < chance + bush_density and bush_source_ids.size() > 0:
				var sid_b: int = bush_source_ids[_rng.randi() % bush_source_ids.size()]
				if sid_b >= 4 and sid_b <= 7:
					_decor_layer.set_cell(cell, sid_b, Vector2i(0, 0), 0)
					occupied[cell] = true


func _borders_water(levels: Array, width: int, height: int, x: int, y: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		if _neighbor_height(levels, width, height, x, y, d) == HeightLevel.WATER:
			return true
	return false


func _is_cliff_rim(levels: Array, width: int, height: int, x: int, y: int, my_level: int) -> bool:
	var masks: Dictionary = _build_cliff_mask(levels, width, height, x, y, my_level)
	return masks["water"] != 0 or masks["walkable"] != 0


func _too_close(occupied: Dictionary, x: int, y: int, spacing: int) -> bool:
	for cell in occupied.keys():
		var c: Vector2i = cell
		if absi(c.x - x) <= spacing and absi(c.y - y) <= spacing:
			return true
	return false


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if get_node_or_null(ground_layer_path) == null:
		warnings.append("GroundLayer missing.")
	if get_node_or_null(elevated_layer1_path) == null and get_node_or_null("ElevatedLayer") == null:
		warnings.append("ElevatedLayer1 missing.")
	if get_node_or_null(shadow_layer1_path) == null and get_node_or_null("ShadowLayer") == null:
		warnings.append("ShadowLayer1 missing.")
	return warnings
