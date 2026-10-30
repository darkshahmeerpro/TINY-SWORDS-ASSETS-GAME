@tool
extends Node2D
class_name TinySwordsProceduralEngine

## Seed-based infinite Tiny Swords world (Minecraft-style chunks).
## Mountains follow the menu map style: elevated grass tops (cols 5–7)
## + stone cliffs row 4 (terrain) / row 5 (water), painted on separate layers.

signal world_generation_started
signal world_generation_progress(phase_name: String, progress_percent: float)
signal world_generation_completed
signal world_generation_failed(error_message: String)
signal chunk_generated(chunk_coord: Vector2i)

enum ElevationLevel { WATER = -1, FLAT = 0, ELEV1 = 1, ELEV2 = 2 }
## Biome regions decide terrain tint, tree species, resources and enemies.
## MEADOW = player realm (safe, green). Others are progressively hostile.
enum Biome { MEADOW, SAVANNAH, GLOOM_FOREST, SCORCHED, PINE_HIGHLANDS }

## Multiplicative terrain tints, sampled through the biome field shader. Kept at
## or below 1.0 so tinting stays a pure darken/shift and never blows out.
const BIOME_TINTS := {
	Biome.MEADOW: Color(1, 1, 1),
	Biome.SAVANNAH: Color(1.0, 0.92, 0.66), ## sun-dried grass, warm not neon
	Biome.GLOOM_FOREST: Color(0.70, 0.68, 0.88), ## cool dusk violet
	Biome.SCORCHED: Color(1.0, 0.70, 0.53), ## baked clay instead of hot red
	Biome.PINE_HIGHLANDS: Color(0.78, 0.93, 0.86), ## cold mint highlands
}
## Cells within this radius of the origin are always MEADOW (player realm).
const MEADOW_SAFE_RADIUS_CELLS: int = 40

const BIOME_SHADER := preload("res://resources/shaders/biome_tint.gdshader")
## Field covers BIOME_FIELD_TEXELS * BIOME_FIELD_CELLS_PER_TEXEL cells, centred
## on the player. Coarse texels are deliberate: linear filtering turns them into
## a soft multi-cell gradient at every biome frontier.
const BIOME_FIELD_TEXELS: int = 48
const BIOME_FIELD_CELLS_PER_TEXEL: int = 4

const ATLAS_ID: int = 2
const SHADOW_SOURCE_ID: int = 12
const CELL_SIZE_PX: int = 64
const CHUNK_SIZE: int = 16
const FOAM_SCENE := preload("res://scenes/world/water_foam.tscn")

const TERRAIN_SET_MAIN: int = 0
const TERRAIN_FLAT_GROUND: int = 1
const TERRAIN_ELEVATED_GROUND: int = 2

## Menu-matched atlases (Tilemap_menu / color5 layout).
## Menu mountain layer is ~95% tops (cols 5–7, rows 0–2) + south cliffs (6,4)/(6,5).
const ELEV_ORIGIN := Vector2i(5, 0) ## 4×4 elevated grass autotile block
const SHADOW_ATLAS := Vector2i(0, 0)

## Cliff wall (rows 4-5 of the atlas). Row 4 is a repeatable middle segment,
## row 5 carries the finished rounded base, so a one-level drop must use row 5.
## Columns follow the same convention as the grass blocks.
const WALL_ROW_MID: int = 4
const WALL_ROW_BASE: int = 5
const WALL_COL_WEST_END: int = 5
const WALL_COL_MIDDLE: int = 6
const WALL_COL_EAST_END: int = 7
const WALL_COL_SINGLE: int = 8

## Stairs: the mirrored grass ramp wedges on the left of the atlas. Laid out as
## a 2×2 block over a cut-away section of wall, they read as a path climbing
## between two banks: upper row tapers, lower row lands on the ground.
const RAMP_WEST_UPPER := Vector2i(0, 4)
const RAMP_EAST_UPPER := Vector2i(3, 4)
const RAMP_WEST_LOWER := Vector2i(0, 5)
const RAMP_EAST_LOWER := Vector2i(3, 5)
const RAMP_WIDTH: int = 2
const RAMP_DEPTH: int = 2 ## rows of ramp below the rim

## Tree1/Tree2 art = blue-green pines (cold/mountain look); Tree3/Tree4 art = round
## yellow-green leafy trees (temperate look) — split by biome instead of one mixed pool.
const PINE_TREE_SCENES := [
	preload("res://scenes/world/trees/tree1.tscn"),
	preload("res://scenes/world/trees/tree2.tscn"),
]
const WOODLAND_TREE_SCENES := [
	preload("res://scenes/world/trees/tree3.tscn"),
	preload("res://scenes/world/trees/tree4.tscn"),
]

## Ground/water decorations (no collision — pure scenery, player walks through).
const BUSH_FRAMES := [
	preload("res://resources/decorations/bushes_bushe1_frames.tres"),
	preload("res://resources/decorations/bushes_bushe2_frames.tres"),
	preload("res://resources/decorations/bushes_bushe3_frames.tres"),
	preload("res://resources/decorations/bushes_bushe4_frames.tres"),
]
const ROCK_TEXTURES := [
	preload("res://assets/decorations/Rocks/Rock1.png"),
	preload("res://assets/decorations/Rocks/Rock2.png"),
	preload("res://assets/decorations/Rocks/Rock3.png"),
	preload("res://assets/decorations/Rocks/Rock4.png"),
]
const WATER_ROCK_FRAMES := [
	preload("res://resources/decorations/rocks_in_the_water_water_rocks_01_frames.tres"),
	preload("res://resources/decorations/rocks_in_the_water_water_rocks_02_frames.tres"),
	preload("res://resources/decorations/rocks_in_the_water_water_rocks_03_frames.tres"),
	preload("res://resources/decorations/rocks_in_the_water_water_rocks_04_frames.tres"),
]

## Resources: gold veins on high ground, sheep herds in meadows.
const GOLD_STONE_TEXTURES := [
	preload("res://assets/resources_pack/Gold/Gold Stones/Gold Stone 1.png"),
	preload("res://assets/resources_pack/Gold/Gold Stones/Gold Stone 2.png"),
	preload("res://assets/resources_pack/Gold/Gold Stones/Gold Stone 3.png"),
	preload("res://assets/resources_pack/Gold/Gold Stones/Gold Stone 4.png"),
	preload("res://assets/resources_pack/Gold/Gold Stones/Gold Stone 5.png"),
	preload("res://assets/resources_pack/Gold/Gold Stones/Gold Stone 6.png"),
]
const MineableGoldScript := preload("res://scripts/world/mineable_gold.gd")
const GOLD_STONE_HIGHLIGHTS := [
	preload("res://assets/resources_pack/Gold/Gold Stones/Gold Stone 1_Highlight.png"),
	preload("res://assets/resources_pack/Gold/Gold Stones/Gold Stone 2_Highlight.png"),
	preload("res://assets/resources_pack/Gold/Gold Stones/Gold Stone 3_Highlight.png"),
	preload("res://assets/resources_pack/Gold/Gold Stones/Gold Stone 4_Highlight.png"),
	preload("res://assets/resources_pack/Gold/Gold Stones/Gold Stone 5_Highlight.png"),
	preload("res://assets/resources_pack/Gold/Gold Stones/Gold Stone 6_Highlight.png"),
]
const SHEEP_SCENE := preload("res://scenes/units/idle/sheep_idle.tscn")
const DEAD_TREE_TEXTURE := preload("res://assets/enemies/Root Troll/Dead Tree.png")
const GLOOM_PROPS := [
	preload("res://assets/enemies/Root Troll/Bones_01.png"),
	preload("res://assets/enemies/Root Troll/Bones_02.png"),
	preload("res://assets/enemies/Root Troll/Bones_03.png"),
	preload("res://assets/enemies/Root Troll/Skull Spike_01.png"),
	preload("res://assets/enemies/Root Troll/Skull Spike_02.png"),
]

## POI structures per biome (paths loaded lazily so missing imports never
## break terrain generation).
const POI_GOBLIN_HUT := "res://assets/enemies/Goblin Raiders/Goblin Hut/Goblin Hut.png"
const POI_CAVE := "res://assets/enemies/Caveborn/Cave/Cave_Idle.png"
const POI_TOWER_RED := "res://assets/buildings/Red Buildings/Tower.png"
const POI_TOWER_PURPLE := "res://assets/buildings/Purple Buildings/Tower.png"
const POI_FISH_HUT := "res://assets/enemies/Pirate Fish/Fish Hut/Fish Hut.png"

@export_category("Engine Control")
@export var trigger_build: bool = false:
	set(val):
		if val and Engine.is_editor_hint():
			build_world()
		trigger_build = false

@export var auto_build_on_ready: bool = true
@export var tile_set: TileSet
@export_range(0.0, 1.0, 0.01) var stage_delay_sec: float = 0.4

@export_group("Infinite World")
@export var infinite_world: bool = true
@export_range(1, 6, 1) var load_radius_chunks: int = 3
@export_range(2, 10, 1) var unload_radius_chunks: int = 5
@export_range(1, 8, 1) var initial_chunk_radius: int = 2
@export_range(1, 4, 1) var stream_phases_per_frame: int = 1

@export_group("Seed & Noise (Minecraft-style)")
## Same seed → same terrain forever (like Minecraft).
@export var master_seed: int = 1337
@export_range(0.001, 0.2, 0.001) var noise_frequency: float = 0.028
@export_range(1, 8, 1) var noise_octaves: int = 4
## Landmass scale: lower = bigger continents and wider oceans.
@export_range(0.0005, 0.02, 0.0005) var continent_frequency: float = 0.004
## Coastline raggedness (domain warp strength, in cells).
@export_range(0.0, 120.0, 1.0) var coast_warp: float = 45.0

@export_group("Height Thresholds")
## Continent value below this is ocean.
@export_range(-1.0, 1.0, 0.01) var water_threshold: float = -0.05
@export_range(-1.0, 1.0, 0.01) var elev1_threshold: float = 0.22
@export_range(-1.0, 1.0, 0.01) var elev2_threshold: float = 0.55

@export_group("Biomes & Decor")
@export_range(0.001, 0.05, 0.001) var biome_frequency: float = 0.006
@export_range(0.001, 0.05, 0.001) var moisture_frequency: float = 0.009
@export_range(0.0, 1.0, 0.01) var plains_tree_density: float = 0.05
@export_range(0.0, 1.0, 0.01) var woodland_tree_density: float = 0.2
@export_range(0.0, 1.0, 0.01) var pine_forest_tree_density: float = 0.26
@export_range(0.0, 0.5, 0.005) var bush_density: float = 0.035
@export_range(0.0, 0.5, 0.005) var rock_density: float = 0.015
@export_range(0.0, 0.5, 0.005) var water_rock_density: float = 0.01
@export var tree_source_ids: PackedInt32Array = PackedInt32Array([4, 5, 6, 7])

@export_group("Resources (per-chunk caps)")
## Chance a chunk hosts one gold vein (3-5 stones, high ground only).
@export_range(0.0, 1.0, 0.01) var gold_vein_chance: float = 0.4
## Chance a MEADOW chunk hosts one sheep herd (2-4 sheep).
@export_range(0.0, 1.0, 0.01) var sheep_herd_chance: float = 0.15
## Chance a hostile-biome chunk hosts one POI structure (hut/cave/tower).
@export_range(0.0, 1.0, 0.01) var poi_chance: float = 0.14

@export_group("Traversal")
## How often stairs appear along south mountain rims (1 = every rim cell).
@export_range(2, 12, 1) var stair_spacing: int = 5

@export_group("Node Layer References")
@export var layer_deep_water: TileMapLayer
@export var layer_water_foam: TileMapLayer
@export var layer_flat_ground: TileMapLayer
@export var layer_shadows1: TileMapLayer
@export var layer_stone1: TileMapLayer
@export var layer_grass1: TileMapLayer
@export var layer_shadows2: TileMapLayer
@export var layer_stone2: TileMapLayer
@export var layer_grass2: TileMapLayer
@export var layer_decor: TileMapLayer
## Y-sorted parent for trees + player (set from empty_world).
@export var entities_root: Node2D

var _noise: FastNoiseLite = FastNoiseLite.new()
var _biome_noise: FastNoiseLite = FastNoiseLite.new()
## Dedicated fields: sharing one noise object made ridges track the coastline.
var _continent_noise: FastNoiseLite = FastNoiseLite.new()
var _relief_noise: FastNoiseLite = FastNoiseLite.new()
var _ridge_noise: FastNoiseLite = FastNoiseLite.new()
var _moisture_noise: FastNoiseLite = FastNoiseLite.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _foam_sprites: Node2D
var _loaded_chunks: Dictionary = {} ## Vector2i -> true
## Chunks whose terrain tiles exist. Set as soon as painting starts (before the
## chunk is fully loaded) so seam healing works during the staged initial build.
var _painted_chunks: Dictionary = {}
var _follow_target: Node2D
var _streaming_enabled: bool = false
var _stair_cells: Dictionary = {} ## Vector2i -> true (rim + ramp rows of each stair)
var _tree_cells: Dictionary = {} ## Vector2i -> Node
var _blocked_cells: Dictionary = {} ## Vector2i -> true (building footprints)
var _barrier_root: Node2D
var _chunk_barriers: Dictionary = {} ## Vector2i chunk -> Node2D
var _chunk_trees: Dictionary = {} ## Vector2i chunk -> Array[Node]
var _chunk_decor: Dictionary = {} ## Vector2i chunk -> Array[Node]
## Runtime streaming is time-sliced: terrain, then decor, then signal.
var _stream_queue: Array[Dictionary] = []
var _queued_chunks: Dictionary = {}
var _unload_queue: Array[Vector2i] = []
var _chunk_layouts: Dictionary = {} ## Vector2i -> generated layout (movement/minimap cache)
var _last_stream_center := Vector2i(2147483647, 2147483647)
## Deterministic memo caches — values never change for a given seed.
var _raw_cache: Dictionary = {}
var _height_cache: Dictionary = {}
## Biome tint field (smooth transitions, sampled by biome_tint.gdshader).
var _biome_field_image: Image
var _biome_field_texture: ImageTexture
var _biome_material_ground: ShaderMaterial
var _biome_material_stone: ShaderMaterial
var _biome_field_origin_cell := Vector2i(2147483647, 2147483647)
var _biome_field_valid: bool = false


func CalculateTileOffsets(elevation_index: int) -> Vector2:
	return Vector2(0, CELL_SIZE_PX * elevation_index)


func _ready() -> void:
	add_to_group("world_gen")
	_auto_bind_layers()
	_apply_shadow_offsets()
	_ensure_tileset()
	_ensure_foam_root()
	_ensure_barrier_root()
	if not Engine.is_editor_hint():
		_configure_noise()
		if auto_build_on_ready:
			build_world()


func set_entities_root(root: Node2D) -> void:
	entities_root = root


func _ensure_barrier_root() -> void:
	_barrier_root = get_node_or_null("Barriers") as Node2D
	if _barrier_root == null:
		_barrier_root = Node2D.new()
		_barrier_root.name = "Barriers"
		add_child(_barrier_root)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not _streaming_enabled or _follow_target == null:
		return
	ensure_chunks_around(_follow_target.global_position)
	_process_stream_queue()
	_process_unload_queue()


func set_follow_target(target: Node2D) -> void:
	_follow_target = target
	_streaming_enabled = true


func _auto_bind_layers() -> void:
	if layer_deep_water == null:
		layer_deep_water = get_node_or_null("DeepWaterLayer") as TileMapLayer
	if layer_water_foam == null:
		layer_water_foam = get_node_or_null("FoamLayer") as TileMapLayer
	if layer_flat_ground == null:
		layer_flat_ground = get_node_or_null("GroundLayer") as TileMapLayer
	if layer_shadows1 == null:
		layer_shadows1 = get_node_or_null("ShadowLayer1") as TileMapLayer
	if layer_stone1 == null:
		layer_stone1 = get_node_or_null("StoneLayer1") as TileMapLayer
	if layer_grass1 == null:
		layer_grass1 = get_node_or_null("GrassLayer1") as TileMapLayer
	if layer_shadows2 == null:
		layer_shadows2 = get_node_or_null("ShadowLayer2") as TileMapLayer
	if layer_stone2 == null:
		layer_stone2 = get_node_or_null("StoneLayer2") as TileMapLayer
	if layer_grass2 == null:
		layer_grass2 = get_node_or_null("GrassLayer2") as TileMapLayer
	if layer_decor == null:
		layer_decor = get_node_or_null("DecorLayer") as TileMapLayer


func _apply_shadow_offsets() -> void:
	## Only shadows are shifted; grass/stone stay on the grid like the menu TileMap.
	if layer_shadows1:
		layer_shadows1.position = CalculateTileOffsets(1)
	if layer_shadows2:
		layer_shadows2.position = CalculateTileOffsets(2)


func _configure_noise() -> void:
	_raw_cache.clear()
	_height_cache.clear()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.seed = master_seed
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = noise_octaves
	_noise.frequency = noise_frequency
	_rng.seed = master_seed

	## Continents: very low frequency + domain warp, so coastlines meander into
	## bays and peninsulas instead of reading as circular blobs.
	_continent_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_continent_noise.seed = master_seed + 1201
	_continent_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_continent_noise.fractal_octaves = 3
	_continent_noise.frequency = continent_frequency
	_continent_noise.domain_warp_enabled = coast_warp > 0.0
	_continent_noise.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	_continent_noise.domain_warp_amplitude = coast_warp
	_continent_noise.domain_warp_frequency = continent_frequency * 2.0

	## Local relief: the rolling hills inside a landmass.
	_relief_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_relief_noise.seed = master_seed + 2803
	_relief_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_relief_noise.fractal_octaves = 4
	_relief_noise.frequency = 0.02

	## Ridged fractal gives connected mountain spines rather than blobs.
	_ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge_noise.seed = master_seed + 4409
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge_noise.fractal_octaves = 4
	_ridge_noise.frequency = 0.01

	## Independent, much lower-frequency fields so biome regions span many chunks
	## (Minecraft-style), instead of following the terrain height noise.
	_biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_biome_noise.seed = master_seed + 7331
	_biome_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_biome_noise.fractal_octaves = 2
	_biome_noise.frequency = biome_frequency

	_moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_moisture_noise.seed = master_seed + 9157
	_moisture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_moisture_noise.fractal_octaves = 2
	_moisture_noise.frequency = moisture_frequency


## Thresholds are set from the measured quantiles of these noise fields (which
## span roughly ±0.75 fairly evenly, not clustered near zero) so each biome gets
## a deliberate share of the world instead of whatever the numbers happen to give.
const BIOME_TEMP_HOT := 0.34 ## warmest ~28%
const BIOME_TEMP_COLD := -0.34 ## coldest ~28%
const BIOME_MOIST_HOT_DRY := -0.12 ## dry side of the hot band → wasteland
const BIOME_MOIST_COLD_WET := 0.0 ## wet side of the cold band → dark forest
const BIOME_MOIST_TEMPERATE_WET := 0.42 ## only the wettest temperate land
const BIOME_MOIST_TEMPERATE_DRY := -0.42 ## only the driest temperate land
const BIOME_ALPINE_TEMP_MAX := 0.30 ## hot mesas stay scorched, not alpine


## Biomes live on a temperature × moisture map (Whittaker-style) rather than
## bands sliced out of one noise, so regions interlock in irregular patches.
## High ground also pulls toward PINE_HIGHLANDS so mountains read as alpine.
func _sample_biome(x: int, y: int) -> Biome:
	## Player realm: everything near world spawn stays friendly green meadow.
	if Vector2(float(x), float(y)).length() < float(MEADOW_SAFE_RADIUS_CELLS):
		return Biome.MEADOW

	var temperature: float = _biome_noise.get_noise_2d(float(x), float(y))
	var moisture: float = _moisture_noise.get_noise_2d(float(x), float(y))

	## Altitude cools the land: real peaks turn alpine regardless of latitude.
	## Uses the finished height, not the raw noise, so the bias follows actual
	## mountains instead of pre-cleanup speckle.
	var height: int = sample_height(x, y)
	if height >= ElevationLevel.ELEV2:
		return Biome.PINE_HIGHLANDS
	if height >= ElevationLevel.ELEV1 and temperature < BIOME_ALPINE_TEMP_MAX:
		return Biome.PINE_HIGHLANDS

	if temperature > BIOME_TEMP_HOT:
		## Hot: dry side bakes to wasteland, damp side is dry grassland.
		return Biome.SCORCHED if moisture < BIOME_MOIST_HOT_DRY else Biome.SAVANNAH
	if temperature < BIOME_TEMP_COLD:
		## Cold: wet side grows dark forest, dry side stays bare highland.
		return Biome.GLOOM_FOREST if moisture > BIOME_MOIST_COLD_WET else Biome.PINE_HIGHLANDS
	## Temperate belt: only its extremes tip over, so meadow stays the world's
	## default green and the player realm blends outward into it.
	if moisture > BIOME_MOIST_TEMPERATE_WET:
		return Biome.GLOOM_FOREST
	if moisture < BIOME_MOIST_TEMPERATE_DRY:
		return Biome.SAVANNAH
	return Biome.MEADOW


func sample_biome_at(cell: Vector2i) -> Biome:
	return _sample_biome(cell.x, cell.y)


func _ensure_tileset() -> void:
	if tile_set == null:
		tile_set = load("res://resources/terrain/procgen_tileset.tres") as TileSet
	if tile_set == null:
		return
	var ts: TileSet = tile_set
	if not Engine.is_editor_hint():
		ts = tile_set.duplicate(true)
		tile_set = ts
	ProcgenTilesetSetup.ensure_configured(ts, ATLAS_ID)
	for layer in _all_layers():
		if layer:
			layer.tile_set = ts


## ---------------------------------------------------------------------------
## Biome tint field (smooth colour transitions via shader)
## ---------------------------------------------------------------------------
func _ensure_biome_materials() -> void:
	if _biome_field_texture != null:
		return
	var image := Image.create(BIOME_FIELD_TEXELS, BIOME_FIELD_TEXELS, false, Image.FORMAT_RGB8)
	image.fill(Color.WHITE)
	_biome_field_texture = ImageTexture.create_from_image(image)
	_biome_field_image = image

	_biome_material_ground = ShaderMaterial.new()
	_biome_material_ground.shader = BIOME_SHADER
	_biome_material_ground.set_shader_parameter("biome_field", _biome_field_texture)
	_biome_material_ground.set_shader_parameter("strength", 1.0)

	## Rock reads as rock in every climate, so its tint is much weaker.
	_biome_material_stone = ShaderMaterial.new()
	_biome_material_stone.shader = BIOME_SHADER
	_biome_material_stone.set_shader_parameter("biome_field", _biome_field_texture)
	_biome_material_stone.set_shader_parameter("strength", 0.45)

	for layer in [layer_flat_ground, layer_grass1, layer_grass2]:
		if layer:
			layer.material = _biome_material_ground
	for layer in [layer_stone1, layer_stone2]:
		if layer:
			layer.material = _biome_material_stone


## Refills the field around `center_cell`. Only called when the player crosses a
## chunk boundary, so this is a few thousand cheap samples very rarely.
func _update_biome_field(center_cell: Vector2i) -> void:
	_ensure_biome_materials()
	if _biome_field_image == null:
		return
	var span_cells: int = BIOME_FIELD_TEXELS * BIOME_FIELD_CELLS_PER_TEXEL
	var origin_cell := center_cell - Vector2i(span_cells >> 1, span_cells >> 1)
	if origin_cell == _biome_field_origin_cell and _biome_field_valid:
		return
	_biome_field_origin_cell = origin_cell
	_biome_field_valid = true

	var half: int = BIOME_FIELD_CELLS_PER_TEXEL >> 1
	for ty in range(BIOME_FIELD_TEXELS):
		for tx in range(BIOME_FIELD_TEXELS):
			var cell := origin_cell + Vector2i(
				tx * BIOME_FIELD_CELLS_PER_TEXEL + half,
				ty * BIOME_FIELD_CELLS_PER_TEXEL + half
			)
			_biome_field_image.set_pixel(tx, ty, BIOME_TINTS[_sample_biome(cell.x, cell.y)])
	_biome_field_texture.update(_biome_field_image)

	var origin_px := Vector2(origin_cell) * float(CELL_SIZE_PX)
	var span_px := Vector2.ONE * float(span_cells * CELL_SIZE_PX)
	## Half-texel inset so uv 0..1 maps to texel centres, not edges.
	var texel_px := float(BIOME_FIELD_CELLS_PER_TEXEL * CELL_SIZE_PX)
	for mat in [_biome_material_ground, _biome_material_stone]:
		if mat == null:
			continue
		mat.set_shader_parameter("field_origin", origin_px + Vector2.ONE * texel_px * 0.5)
		mat.set_shader_parameter("field_span", span_px - Vector2.ONE * texel_px)


func _all_layers() -> Array:
	return [
		layer_deep_water, layer_water_foam, layer_flat_ground,
		layer_shadows1, layer_stone1, layer_grass1,
		layer_shadows2, layer_stone2, layer_grass2, layer_decor,
	]


func _ensure_foam_root() -> void:
	if layer_water_foam == null:
		return
	_foam_sprites = layer_water_foam.get_node_or_null("FoamSprites") as Node2D
	if _foam_sprites == null:
		_foam_sprites = Node2D.new()
		_foam_sprites.name = "FoamSprites"
		layer_water_foam.add_child(_foam_sprites)


## ---------------------------------------------------------------------------
## Seeded height sample (deterministic for infinite world)
## ---------------------------------------------------------------------------
const _HEIGHT_CACHE_MAX := 180000 ## ~700 chunks of cells before a reset

func sample_height(wx: int, wy: int) -> int:
	var key := Vector2i(wx, wy)
	var cached: int = _height_cache.get(key, -99)
	if cached != -99:
		return cached
	var h := _sample_height_uncached(wx, wy)
	if _height_cache.size() > _HEIGHT_CACHE_MAX:
		_height_cache.clear()
	_height_cache[key] = h
	return h


func _sample_height_uncached(wx: int, wy: int) -> int:
	## Morphology is per-cell from raw noise only so chunks always agree.
	var center: int = _raw_height(wx, wy)
	var n4: Array[int] = [
		_raw_height(wx, wy - 1),
		_raw_height(wx + 1, wy),
		_raw_height(wx, wy + 1),
		_raw_height(wx - 1, wy),
	]
	var elev_n4 := 0
	for v in n4:
		if v >= ElevationLevel.ELEV1:
			elev_n4 += 1

	## Close operator: keep / grow chunky plateaus (menu mountains are fat blobs).
	var elev1 := false
	if center >= ElevationLevel.ELEV1:
		elev1 = elev_n4 >= 2 ## erode speckles
	elif center == ElevationLevel.FLAT and elev_n4 >= 3:
		elev1 = true ## dilate into flat pockets

	if not elev1:
		## Coastline smoothing: fill one-cell ponds, shave one-cell land spits.
		var water_n4 := 0
		for v in n4:
			if v == ElevationLevel.WATER:
				water_n4 += 1
		if center == ElevationLevel.WATER:
			return ElevationLevel.FLAT if water_n4 <= 1 else ElevationLevel.WATER
		return ElevationLevel.WATER if water_n4 >= 4 else ElevationLevel.FLAT

	## Elev2 nests strictly inside elev1 (inset: all 4 neighbors elev1+).
	var elev2_n4 := 0
	for v in n4:
		if v >= ElevationLevel.ELEV2:
			elev2_n4 += 1
	if center >= ElevationLevel.ELEV2 and elev_n4 == 4 and elev2_n4 >= 2:
		## Also require diagonals so peaks aren't diamond spikes.
		var diag_ok := 0
		for d in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			if _raw_height(wx + d.x, wy + d.y) >= ElevationLevel.ELEV1:
				diag_ok += 1
		if diag_ok >= 3:
			return ElevationLevel.ELEV2
	return ElevationLevel.ELEV1


func _raw_height(wx: int, wy: int) -> int:
	var key := Vector2i(wx, wy)
	var cached: int = _raw_cache.get(key, -99)
	if cached != -99:
		return cached
	var fx := float(wx)
	var fy := float(wy)
	## Ocean/land is decided purely by the continent field, so coasts are one
	## continuous line instead of a mix of four correlated noises.
	var land: float = _continent_noise.get_noise_2d(fx, fy)
	var result: int
	if land < water_threshold:
		result = ElevationLevel.WATER
	else:
		## Mountains need to be well inland: `inland` ramps from 0 at the shore
		## to 1 deep in the interior, so ranges form in the middle of landmasses
		## and coastlines stay walkable beach-level ground.
		var inland: float = smoothstep(water_threshold + 0.06, water_threshold + 0.42, land)
		var relief: float = _relief_noise.get_noise_2d(fx, fy)
		var ridge: float = _ridge_noise.get_noise_2d(fx, fy)
		var h: float = relief * 0.55 + ridge * inland * 0.9
		if h > elev2_threshold and inland > 0.6:
			result = ElevationLevel.ELEV2
		elif h > elev1_threshold:
			result = ElevationLevel.ELEV1
		else:
			result = ElevationLevel.FLAT
	if _raw_cache.size() > _HEIGHT_CACHE_MAX:
		_raw_cache.clear()
	_raw_cache[key] = result
	return result

func cell_to_chunk(cell: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(cell.x) / float(CHUNK_SIZE)),
		floori(float(cell.y) / float(CHUNK_SIZE))
	)


func global_to_cell(global_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(global_pos.x / float(CELL_SIZE_PX)),
		floori(global_pos.y / float(CELL_SIZE_PX))
	)


## ---------------------------------------------------------------------------
## Public build API (loading scene + editor)
## ---------------------------------------------------------------------------
func build_world() -> void:
	_prepare()
	world_generation_started.emit()
	_clear_all()
	_generate_chunk_disk(Vector2i.ZERO, initial_chunk_radius)
	_set_layers_visible(true)
	world_generation_progress.emit("Complete", 100.0)
	world_generation_completed.emit()
	_streaming_enabled = true


## Layer-by-layer initial reveal (per .cursor/rules): every chunk in the initial
## disk advances through the SAME rule-layer together before the next layer
## begins, instead of finishing one chunk (all layers) before the next chunk.
func build_world_staged() -> void:
	_prepare()
	world_generation_started.emit()
	_clear_all()
	_set_layers_visible(true)

	var chunks: Array[Vector2i] = _initial_chunk_list()
	var layouts: Dictionary = {} ## Vector2i chunk -> layout Dictionary
	for chunk in chunks:
		layouts[chunk] = _compute_chunk_layout(chunk)

	var total_stages := 8
	var stage := 0

	## Layer 0: BG Color (Water) — the deep ocean already exists (WaterBackground);
	## this beat just opens the sequence in the correct rule order.
	stage += 1
	world_generation_progress.emit("Layer 0 — Water", 100.0 * stage / total_stages)
	await _stage_pause()

	## Layer 1: Water Foam (Coastlines).
	stage += 1
	for chunk in chunks:
		_paint_chunk_foam(layouts[chunk])
	world_generation_progress.emit("Layer 1 — Water Foam", 100.0 * stage / total_stages)
	await _stage_pause()

	## Layer 2: Flat Ground (Base Terrain).
	stage += 1
	for chunk in chunks:
		_paint_chunk_flat(layouts[chunk])
	world_generation_progress.emit("Layer 2 — Flat Ground", 100.0 * stage / total_stages)
	await _stage_pause()

	## Layer 3, Step A: Shadows (Elevation 1) — placed before the elevated ground.
	stage += 1
	for chunk in chunks:
		_place_shadows(layouts[chunk].elev1, layer_shadows1)
	world_generation_progress.emit("Layer 3 — Shadows (Elevation 1)", 100.0 * stage / total_stages)
	await _stage_pause()

	## Layer 3, Step B: Elevated Ground (Elevation 1) — cliffs, tops, stairs.
	stage += 1
	for chunk in chunks:
		_paint_chunk_elevation(layouts[chunk], ElevationLevel.ELEV1, layer_stone1, layer_grass1)
	world_generation_progress.emit("Layer 3 — Elevated Ground (Elevation 1)", 100.0 * stage / total_stages)
	await _stage_pause()

	## Layer 4, Step A: Shadows (Elevation 2), nested on top of Elevation 1.
	stage += 1
	for chunk in chunks:
		_place_shadows(layouts[chunk].elev2, layer_shadows2)
	world_generation_progress.emit("Layer 4 — Shadows (Elevation 2)", 100.0 * stage / total_stages)
	await _stage_pause()

	## Layer 4, Step B: Elevated Ground (Elevation 2) — cliffs, tops, stairs.
	stage += 1
	for chunk in chunks:
		_paint_chunk_elevation(layouts[chunk], ElevationLevel.ELEV2, layer_stone2, layer_grass2)
	world_generation_progress.emit("Layer 4 — Elevated Ground (Elevation 2)", 100.0 * stage / total_stages)
	await _stage_pause()

	## Layer 5: Decor & Collision — depends on the fully-defined terrain above.
	stage += 1
	for chunk in chunks:
		_paint_chunk_decor(chunk, layouts[chunk])
	world_generation_progress.emit("Layer 5 — Decor & Collision", 100.0 * stage / total_stages)
	await _stage_pause()

	for chunk in chunks:
		_loaded_chunks[chunk] = true
		_chunk_layouts[chunk] = layouts[chunk]
		chunk_generated.emit(chunk)

	world_generation_progress.emit("Ready", 100.0)
	world_generation_completed.emit()
	_streaming_enabled = true


func _initial_chunk_list() -> Array[Vector2i]:
	var chunks: Array[Vector2i] = []
	for cy in range(-initial_chunk_radius, initial_chunk_radius + 1):
		for cx in range(-initial_chunk_radius, initial_chunk_radius + 1):
			chunks.append(Vector2i(cx, cy))
	return chunks


func _prepare() -> void:
	_auto_bind_layers()
	_apply_shadow_offsets()
	_ensure_tileset()
	_ensure_foam_root()
	_ensure_barrier_root()
	_configure_noise()
	_biome_field_valid = false
	_update_biome_field(Vector2i.ZERO)
	if entities_root == null:
		entities_root = get_node_or_null("../Entities") as Node2D


func _validate_architecture() -> bool:
	if layer_flat_ground == null or layer_grass1 == null or layer_stone1 == null:
		world_generation_failed.emit("Missing terrain layers.")
		return false
	return true


func _clear_all() -> void:
	for layer in _all_layers():
		if layer:
			layer.clear()
	_clear_foam()
	_clear_all_trees()
	_clear_all_decor()
	_clear_all_barriers()
	_stair_cells.clear()
	_blocked_cells.clear()
	_loaded_chunks.clear()
	_painted_chunks.clear()
	_stream_queue.clear()
	_queued_chunks.clear()
	_unload_queue.clear()
	_chunk_layouts.clear()
	_raw_cache.clear()
	_height_cache.clear()
	_last_stream_center = Vector2i(2147483647, 2147483647)


## ---------------------------------------------------------------------------
## Chunk streaming
## ---------------------------------------------------------------------------
func ensure_chunks_around(global_pos: Vector2) -> void:
	var center: Vector2i = cell_to_chunk(global_to_cell(global_pos))
	if center == _last_stream_center:
		return
	_last_stream_center = center
	_update_biome_field(global_to_cell(global_pos))
	for dy in range(-load_radius_chunks, load_radius_chunks + 1):
		for dx in range(-load_radius_chunks, load_radius_chunks + 1):
			var key := center + Vector2i(dx, dy)
			if not _loaded_chunks.has(key) and not _queued_chunks.has(key):
				_stream_queue.append({"chunk": key, "phase": 0, "layout": {}})
				_queued_chunks[key] = true

	## Nearby chunks first: reduces visible pop-in while keeping each frame bounded.
	_stream_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.chunk as Vector2i).distance_squared_to(center) < (b.chunk as Vector2i).distance_squared_to(center)
	)

	## Unload far chunks
	for key in _loaded_chunks.keys():
		var c: Vector2i = key
		if absi(c.x - center.x) > unload_radius_chunks or absi(c.y - center.y) > unload_radius_chunks:
			if not _unload_queue.has(c):
				_unload_queue.append(c)


func is_streaming_busy() -> bool:
	return not _stream_queue.is_empty() or not _unload_queue.is_empty()


func _process_stream_queue() -> void:
	for _step in range(stream_phases_per_frame):
		if _stream_queue.is_empty():
			return
		var job: Dictionary = _stream_queue.pop_front()
		var chunk: Vector2i = job.chunk
		if _loaded_chunks.has(chunk):
			_queued_chunks.erase(chunk)
			continue
		var phase: int = job.phase
		if phase == 0:
			job.layout = _compute_chunk_layout(chunk)
			job.phase = 1
			_stream_queue.append(job)
		elif phase == 1:
			var layout: Dictionary = job.layout
			_paint_chunk_flat(layout)
			_paint_chunk_foam(layout)
			_place_shadows(layout.elev1, layer_shadows1)
			_paint_chunk_elevation(layout, ElevationLevel.ELEV1, layer_stone1, layer_grass1)
			_place_shadows(layout.elev2, layer_shadows2)
			_paint_chunk_elevation(layout, ElevationLevel.ELEV2, layer_stone2, layer_grass2)
			job.phase = 2
			_stream_queue.append(job)
		else:
			var layout: Dictionary = job.layout
			_paint_chunk_decor(chunk, layout)
			_chunk_layouts[chunk] = layout
			_loaded_chunks[chunk] = true
			_queued_chunks.erase(chunk)
			## Deferred signal lets terrain tile updates settle before enemy node/VFX work.
			call_deferred("_emit_chunk_generated", chunk)


func _emit_chunk_generated(chunk: Vector2i) -> void:
	if _loaded_chunks.has(chunk):
		chunk_generated.emit(chunk)


func _process_unload_queue() -> void:
	if not _unload_queue.is_empty():
		_unload_chunk(_unload_queue.pop_front())


func _generate_chunk_disk(origin: Vector2i, radius: int) -> void:
	for cy in range(origin.y - radius, origin.y + radius + 1):
		for cx in range(origin.x - radius, origin.x + radius + 1):
			_generate_chunk(Vector2i(cx, cy))


## Samples heights for a chunk (with padding for edge-aware autotiling) and
## classifies interior cells into flats/elev1/elev2 lists. Shared by the fast
## runtime streaming path and the layer-by-layer initial staged build.
func _compute_chunk_layout(chunk: Vector2i) -> Dictionary:
	var origin := Vector2i(chunk.x * CHUNK_SIZE, chunk.y * CHUNK_SIZE)
	var flats: Array[Vector2i] = []
	var elev1: Array[Vector2i] = []
	var elev2: Array[Vector2i] = []

	## Sample a padded region so cliff/foam/autotile edges see neighbors outside the chunk.
	var pad := 2
	var heights: Dictionary = {} ## Vector2i -> ElevationLevel
	for ly in range(-pad, CHUNK_SIZE + pad):
		for lx in range(-pad, CHUNK_SIZE + pad):
			var cell := origin + Vector2i(lx, ly)
			heights[cell] = sample_height(cell.x, cell.y)

	## Collect interior cells for painting.
	for ly in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var cell := origin + Vector2i(lx, ly)
			var h: int = heights[cell]
			match h:
				ElevationLevel.FLAT:
					flats.append(cell)
				ElevationLevel.ELEV1:
					flats.append(cell) ## Flat under elev (menu has ground under mountains).
					elev1.append(cell)
				ElevationLevel.ELEV2:
					flats.append(cell)
					elev1.append(cell) ## Elev2 nests on elev1 mass visually.
					elev2.append(cell)

	return {
		"chunk": chunk,
		"origin": origin,
		"heights": heights,
		"flats": flats,
		"elev1": elev1,
		"elev2": elev2,
	}


func _paint_chunk_flat(layout: Dictionary) -> void:
	var flats: Array[Vector2i] = layout.flats
	## Marked up front so sibling chunks painted later in the same pass know they
	## may re-resolve this chunk's border cells.
	_painted_chunks[layout.chunk] = true
	if layer_flat_ground == null or flats.is_empty():
		return
	var cells: Array[Vector2i] = []
	cells.append_array(flats)
	cells.append_array(_loaded_ring_cells(layout, ElevationLevel.FLAT))
	layer_flat_ground.set_cells_terrain_connect(
		cells, TERRAIN_SET_MAIN, TERRAIN_FLAT_GROUND, true
	)


## Cells in the 1-cell ring around this chunk that sit at `min_level` or above
## AND belong to an already-loaded chunk.
##
## Terrain connect resolves a cell from its painted neighbours, so a chunk
## painted while its neighbour was still empty used to keep an outer "open edge"
## tile forever — a fluffy seam along every chunk border. Feeding the ring back
## into the same call re-resolves those shared cells with full information.
func _loaded_ring_cells(layout: Dictionary, min_level: int) -> Array[Vector2i]:
	var origin: Vector2i = layout.origin
	var heights: Dictionary = layout.heights
	var out: Array[Vector2i] = []
	for ly in range(-1, CHUNK_SIZE + 1):
		for lx in range(-1, CHUNK_SIZE + 1):
			var inside_x: bool = lx >= 0 and lx < CHUNK_SIZE
			var inside_y: bool = ly >= 0 and ly < CHUNK_SIZE
			if inside_x and inside_y:
				continue
			var cell := origin + Vector2i(lx, ly)
			if not _painted_chunks.has(cell_to_chunk(cell)):
				continue
			if int(heights.get(cell, sample_height(cell.x, cell.y))) >= min_level:
				out.append(cell)
	return out


func _paint_chunk_foam(layout: Dictionary) -> void:
	_place_foam_in_chunk(layout.origin, layout.heights)


## Cliffs → tops → stairs for a single elevation level (rule Step B + stairs).
## Shadows (Step A) are placed separately via _place_shadows() so the staged
## build can reveal them as their own layer, one beat before this step.
func _paint_chunk_elevation(layout: Dictionary, level: ElevationLevel, stone_layer: TileMapLayer, grass_layer: TileMapLayer) -> void:
	## Stairs run first so the wall pass already knows where the openings are and
	## can terminate the flanking runs with end caps.
	_place_stairs_in_chunk(layout, level, grass_layer, stone_layer)
	_paint_inbound_cliffs(layout, level, stone_layer)
	_place_elevated_tops(layout, level, grass_layer)


func _paint_chunk_decor(chunk: Vector2i, layout: Dictionary) -> void:
	_place_barriers_in_chunk(chunk, layout.origin, layout.heights)
	## Structures claim their footprint first; everything below skips those cells
	## so nothing sprouts through a roof.
	_place_pois_in_chunk(chunk, layout.origin, layout.heights)
	_place_trees_in_chunk(chunk, layout.origin, layout.heights)
	_place_decor_in_chunk(chunk, layout.origin, layout.heights)
	_place_resources_in_chunk(chunk, layout.origin, layout.heights)


## Per-chunk scenery list, created on first use so every placement pass appends
## to the same array instead of replacing it.
func _chunk_decor_list(chunk: Vector2i) -> Array:
	if not _chunk_decor.has(chunk):
		_chunk_decor[chunk] = []
	return _chunk_decor[chunk]


func _generate_chunk(chunk: Vector2i) -> void:
	if _loaded_chunks.has(chunk):
		return
	if not _validate_architecture():
		return

	var layout: Dictionary = _compute_chunk_layout(chunk)

	## Layer order matching menu + rules: flat → foam → shadow → stone → grass.
	_paint_chunk_flat(layout)
	_paint_chunk_foam(layout)

	## Elev1: shadows, cliffs, tops, then stairs cut openings in cliffs.
	_place_shadows(layout.elev1, layer_shadows1)
	_paint_chunk_elevation(layout, ElevationLevel.ELEV1, layer_stone1, layer_grass1)

	## Elev2 nested on elev1 mass.
	_place_shadows(layout.elev2, layer_shadows2)
	_paint_chunk_elevation(layout, ElevationLevel.ELEV2, layer_stone2, layer_grass2)

	_paint_chunk_decor(chunk, layout)

	_chunk_layouts[chunk] = layout
	_loaded_chunks[chunk] = true
	chunk_generated.emit(chunk)


func _unload_chunk(chunk: Vector2i) -> void:
	var origin := Vector2i(chunk.x * CHUNK_SIZE, chunk.y * CHUNK_SIZE)
	for ly in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var cell := origin + Vector2i(lx, ly)
			for layer in _all_layers():
				if layer:
					layer.erase_cell(cell)
			_erase_foam_at(cell)
			_stair_cells.erase(cell)
			_tree_cells.erase(cell)
			_blocked_cells.erase(cell)
	_unload_chunk_trees(chunk)
	_unload_chunk_decor(chunk)
	_unload_chunk_barriers(chunk)
	_loaded_chunks.erase(chunk)
	_painted_chunks.erase(chunk)
	_chunk_layouts.erase(chunk)


## ---------------------------------------------------------------------------
## Elevated tops + cliff walls
## ---------------------------------------------------------------------------
## Plateau tops are autotiled from the elevated 16-tile block, so 1-cell necks,
## single buttes and ragged rims all resolve correctly instead of being forced
## into a 3×3 approximation.
func _place_elevated_tops(layout: Dictionary, level: ElevationLevel, grass_layer: TileMapLayer) -> void:
	if grass_layer == null or tile_set == null or not tile_set.has_source(ATLAS_ID):
		return
	var source: Array[Vector2i] = layout.elev1 if level == ElevationLevel.ELEV1 else layout.elev2
	if source.is_empty():
		return
	var cells: Array[Vector2i] = []
	cells.append_array(source)
	cells.append_array(_loaded_ring_cells(layout, level))
	grass_layer.set_cells_terrain_connect(
		cells, TERRAIN_SET_MAIN, TERRAIN_ELEVATED_GROUND, true
	)


func _is_elev(cell: Vector2i, my_elev: int, heights: Dictionary) -> bool:
	return int(heights.get(cell, sample_height(cell.x, cell.y))) >= my_elev


## True when `cell` is the ground directly south of a rim at `level`, i.e. the
## cell whose face shows the cliff. Stair openings deliberately report false so
## neighbouring walls cap themselves off around the ramp.
func _has_wall(cell: Vector2i, level: int, heights: Dictionary) -> bool:
	if _stair_cells.has(cell):
		return false
	if int(heights.get(cell, sample_height(cell.x, cell.y))) >= level:
		return false
	return _is_elev(cell + Vector2i(0, -1), level, heights)


func _wall_atlas(cell: Vector2i, level: int, heights: Dictionary) -> Vector2i:
	var w: bool = _has_wall(cell + Vector2i(-1, 0), level, heights)
	var e: bool = _has_wall(cell + Vector2i(1, 0), level, heights)
	var col: int = WALL_COL_MIDDLE
	if not w and e:
		col = WALL_COL_WEST_END
	elif w and not e:
		col = WALL_COL_EAST_END
	elif not w and not e:
		col = WALL_COL_SINGLE
	## One level of drop lands on ground, so it needs the base segment. Row 4 is
	## only for a face that keeps going down past this cell.
	var landing: int = int(heights.get(cell, sample_height(cell.x, cell.y)))
	var row: int = WALL_ROW_BASE if landing >= level - 1 else WALL_ROW_MID
	return Vector2i(col, row)


func _paint_inbound_cliffs(layout: Dictionary, level: ElevationLevel, stone_layer: TileMapLayer) -> void:
	if stone_layer == null or tile_set == null or not tile_set.has_source(ATLAS_ID):
		return
	var origin: Vector2i = layout.origin
	var heights: Dictionary = layout.heights
	for ly in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var cell := origin + Vector2i(lx, ly)
			if not _has_wall(cell, level, heights):
				continue
			stone_layer.set_cell(cell, ATLAS_ID, _wall_atlas(cell, level, heights), 0)


## Re-resolves a single wall cell (used when a stair opening changes its
## neighbours' end caps after the wall was already painted).
func _repaint_wall(cell: Vector2i, level: int, heights: Dictionary, stone_layer: TileMapLayer) -> void:
	if stone_layer == null:
		return
	if _has_wall(cell, level, heights):
		stone_layer.set_cell(cell, ATLAS_ID, _wall_atlas(cell, level, heights), 0)


func _place_shadows(cells: Array[Vector2i], shadow_layer: TileMapLayer) -> void:
	## Shadow under the plateau footprint; layer Y offset handles 2.5D lift.
	if shadow_layer == null or tile_set == null or not tile_set.has_source(SHADOW_SOURCE_ID):
		return
	for cell in cells:
		shadow_layer.set_cell(cell, SHADOW_SOURCE_ID, SHADOW_ATLAS, 0)


func _place_foam_in_chunk(origin: Vector2i, heights: Dictionary) -> void:
	if _foam_sprites == null or layer_water_foam == null:
		return
	for ly in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var cell := origin + Vector2i(lx, ly)
			var h: int = heights[cell]
			if h == ElevationLevel.WATER:
				continue
			if not _borders_water_dict(cell, heights):
				continue
			## Avoid duplicate foam if regenerating.
			_erase_foam_at(cell)
			var splash: AnimatedSprite2D = FOAM_SCENE.instantiate() as AnimatedSprite2D
			splash.name = "Foam_%d_%d" % [cell.x, cell.y]
			splash.position = layer_water_foam.map_to_local(cell)
			_foam_sprites.add_child(splash)
			if splash.sprite_frames and splash.sprite_frames.has_animation(&"foam"):
				var count: int = splash.sprite_frames.get_frame_count(&"foam")
				if count > 0:
					splash.frame = _rng.randi() % count
				splash.play(&"foam")


func _place_trees_in_chunk(chunk: Vector2i, origin: Vector2i, heights: Dictionary) -> void:
	## Spawn tree scenes into the Y-sorted Entities node so they draw above/behind the player.
	if entities_root == null:
		return
	var list: Array = []
	_chunk_trees[chunk] = list
	for ly in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var cell := origin + Vector2i(lx, ly)
			if heights[cell] != ElevationLevel.FLAT:
				continue
			if _borders_water_dict(cell, heights):
				continue
			if _stair_cells.has(cell) or _blocked_cells.has(cell):
				continue
			var biome: Biome = _sample_biome(cell.x, cell.y)
			var scenes: Array
			var density: float
			match biome:
				Biome.PINE_HIGHLANDS:
					scenes = PINE_TREE_SCENES
					density = pine_forest_tree_density
				Biome.GLOOM_FOREST:
					scenes = WOODLAND_TREE_SCENES
					density = woodland_tree_density
				Biome.SAVANNAH:
					scenes = WOODLAND_TREE_SCENES
					density = plains_tree_density * 0.6
				Biome.SCORCHED:
					scenes = [] ## dead trees, handled below
					density = plains_tree_density * 0.5
				_:
					scenes = WOODLAND_TREE_SCENES
					density = plains_tree_density
			var h: int = hash(Vector3i(master_seed, cell.x, cell.y))
			var roll: float = float(absi(h) % 10000) / 10000.0
			if roll > density:
				continue
			var pos := Vector2((float(cell.x) + 0.5) * CELL_SIZE_PX, (float(cell.y) + 0.85) * CELL_SIZE_PX)
			var tree: Node2D
			if scenes.is_empty():
				## Scorched wasteland grows leafless dead trees (pure scenery).
				var dead := Sprite2D.new()
				dead.texture = DEAD_TREE_TEXTURE
				dead.offset = Vector2(0, -DEAD_TREE_TEXTURE.get_height() * 0.28)
				tree = dead
			else:
				var idx: int = absi(h) % scenes.size()
				tree = scenes[idx].instantiate() as Node2D
			tree.name = "Tree_%d_%d" % [cell.x, cell.y]
			tree.position = pos
			tree.modulate = _biome_prop_tint(biome)
			entities_root.add_child(tree)
			list.append(tree)
			_tree_cells[cell] = tree


func _unload_chunk_trees(chunk: Vector2i) -> void:
	if not _chunk_trees.has(chunk):
		return
	for tree in _chunk_trees[chunk]:
		if is_instance_valid(tree):
			tree.queue_free()
	_chunk_trees.erase(chunk)


func _clear_all_trees() -> void:
	for chunk in _chunk_trees.keys():
		_unload_chunk_trees(chunk)
	_chunk_trees.clear()
	_tree_cells.clear()


## ---------------------------------------------------------------------------
## Decorations (bushes, rocks, water rocks) — pure scenery, no collision
## ---------------------------------------------------------------------------
func _place_decor_in_chunk(chunk: Vector2i, origin: Vector2i, heights: Dictionary) -> void:
	if entities_root == null:
		return
	var list: Array = _chunk_decor_list(chunk)
	for ly in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var cell := origin + Vector2i(lx, ly)
			var h: int = heights[cell]
			var pos := Vector2((float(cell.x) + 0.5) * CELL_SIZE_PX, (float(cell.y) + 0.5) * CELL_SIZE_PX)
			var roll_hash: int = absi(hash(Vector3i(master_seed + 577, cell.x, cell.y)))
			var roll: float = float(roll_hash % 10000) / 10000.0

			if _blocked_cells.has(cell):
				continue

			if h == ElevationLevel.WATER:
				## Animated rocks poking out of the ocean, away from the shoreline foam.
				if roll < water_rock_density and not _borders_land(cell, heights):
					list.append(_spawn_animated_decor(WATER_ROCK_FRAMES[roll_hash % WATER_ROCK_FRAMES.size()], pos, "WaterRock"))
				continue

			if h != ElevationLevel.FLAT:
				continue
			if _tree_cells.has(cell) or _stair_cells.has(cell):
				continue
			if _borders_water_dict(cell, heights):
				continue

			## Meadows get extra bushes so open grassland still feels alive.
			var biome: Biome = _sample_biome(cell.x, cell.y)
			var bushes: float = bush_density * (2.0 if biome == Biome.MEADOW else 1.0)
			if biome == Biome.SCORCHED:
				bushes *= 0.3 ## wasteland is barren
			if roll < bushes:
				var bush := _spawn_animated_decor(BUSH_FRAMES[roll_hash % BUSH_FRAMES.size()], pos, "Bush")
				bush.modulate = _biome_prop_tint(biome)
				list.append(bush)
			elif roll < bushes + rock_density:
				var rock := Sprite2D.new()
				rock.name = "Rock_%d_%d" % [cell.x, cell.y]
				## Gloom Forest scatters bones/skull spikes instead of plain rocks.
				if biome == Biome.GLOOM_FOREST:
					rock.texture = GLOOM_PROPS[roll_hash % GLOOM_PROPS.size()]
				else:
					rock.texture = ROCK_TEXTURES[roll_hash % ROCK_TEXTURES.size()]
				rock.position = pos
				entities_root.add_child(rock)
				list.append(rock)


## Subtle sprite tint so props blend into their biome's terrain colorway.
func _biome_prop_tint(biome: Biome) -> Color:
	return Color.WHITE.lerp(BIOME_TINTS[biome], 0.45)


## ---------------------------------------------------------------------------
## POI structures — biome landmarks (goblin huts, caves, towers, fish huts)
## ---------------------------------------------------------------------------
func _place_pois_in_chunk(chunk: Vector2i, origin: Vector2i, heights: Dictionary) -> void:
	if entities_root == null:
		return
	var chash: int = absi(hash(Vector3i(master_seed + 3117, chunk.x, chunk.y)))
	if float(chash % 1000) / 1000.0 > poi_chance:
		return

	var half: int = CHUNK_SIZE >> 1
	var center := origin + Vector2i(half, half)
	## POIs never crowd the player realm.
	if Vector2(center).length() < float(MEADOW_SAFE_RADIUS_CELLS + 8):
		return

	## Ocean chunks get a Fish Hut anchored on the shoreline instead.
	if int(heights.get(center, sample_height(center.x, center.y))) == ElevationLevel.WATER:
		_place_fish_hut(chunk, origin, heights, chash)
		return

	var biome: Biome = _sample_biome(center.x, center.y)
	var tex_path := ""
	var with_fire := false
	match biome:
		Biome.SCORCHED:
			tex_path = POI_GOBLIN_HUT
			with_fire = true
		Biome.GLOOM_FOREST:
			tex_path = POI_GOBLIN_HUT if (chash >> 4) % 2 == 0 else POI_TOWER_PURPLE
			with_fire = tex_path == POI_GOBLIN_HUT
		Biome.SAVANNAH:
			tex_path = POI_TOWER_RED
		Biome.PINE_HIGHLANDS:
			tex_path = POI_CAVE
		_:
			return ## Meadow stays pristine.

	var tex: Texture2D = _load_poi_texture(tex_path)
	if tex == null:
		return
	var footprint := _structure_footprint(tex)

	## Find a pad that actually fits the art, on uniform ground, inset from the
	## chunk edge so the building never straddles a border.
	var anchor := Vector2i.ZERO
	var found := false
	for attempt in range(24):
		var ahash: int = absi(hash(Vector4i(master_seed + 13, chunk.x, chunk.y, attempt)))
		var span_x: int = maxi(1, CHUNK_SIZE - 2 - footprint.x)
		var span_y: int = maxi(1, CHUNK_SIZE - 2 - footprint.y)
		var cell := origin + Vector2i(1 + (ahash % span_x), 1 + ((ahash >> 5) % span_y))
		if _poi_pad_clear(cell, footprint, heights, false):
			anchor = cell
			found = true
			break
	if not found:
		return

	_spawn_structure(chunk, anchor, footprint, tex, "POI", with_fire)


## Pirate Fish hut stands out on the water (it is a hut on stilts), anchored to a
## patch of sea that touches the shore.
func _place_fish_hut(chunk: Vector2i, origin: Vector2i, heights: Dictionary, chash: int) -> void:
	var tex: Texture2D = _load_poi_texture(POI_FISH_HUT)
	if tex == null:
		return
	var footprint := _structure_footprint(tex)
	for attempt in range(24):
		var ahash: int = absi(hash(Vector4i(master_seed + 29, chunk.x, chunk.y, attempt + chash % 7)))
		var span_x: int = maxi(1, CHUNK_SIZE - 2 - footprint.x)
		var span_y: int = maxi(1, CHUNK_SIZE - 2 - footprint.y)
		var cell := origin + Vector2i(1 + (ahash % span_x), 1 + ((ahash >> 5) % span_y))
		if not _poi_pad_clear(cell, footprint, heights, true):
			continue
		## Must touch land somewhere along its footprint, or it reads as adrift.
		var touches_shore := false
		for dx in range(footprint.x):
			for dy in range(footprint.y):
				if _borders_land(cell + Vector2i(dx, dy), heights):
					touches_shore = true
		if not touches_shore:
			continue
		_spawn_structure(chunk, cell, footprint, tex, "FishHut", false)
		return


## Ground footprint in cells. Width follows the art; depth is shallower because
## most of a building's height is roof drawn above its base.
func _structure_footprint(tex: Texture2D) -> Vector2i:
	var frames: int = _strip_frames(tex)
	var frame_w: int = maxi(1, tex.get_width() / frames)
	var wide: int = maxi(1, ceili(float(frame_w) / float(CELL_SIZE_PX)))
	return Vector2i(wide, clampi(wide - 1, 1, 3))


## Sprite strips (goblin hut, cave, fish hut) are square frames laid out in a
## row; static art rounds down to a single frame.
func _strip_frames(tex: Texture2D) -> int:
	var h: int = maxi(1, tex.get_height())
	return maxi(1, int(round(float(tex.get_width()) / float(h))))


func _load_poi_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _spawn_structure(
	chunk: Vector2i,
	anchor: Vector2i,
	footprint: Vector2i,
	tex: Texture2D,
	label: String,
	with_fire: bool
) -> void:
	var frames: int = _strip_frames(tex)
	var frame_w: int = maxi(1, tex.get_width() / frames)
	var frame_h: int = maxi(1, tex.get_height())

	var sprite := AnimatedSprite2D.new()
	sprite.name = "%s_%d_%d" % [label, anchor.x, anchor.y]
	sprite.sprite_frames = _build_strip_frames(tex, frames, frame_w, frame_h)

	## Sort by where the building meets the ground: the centre of its last
	## footprint row, so the player passes in front of it correctly.
	var base_row_center := Vector2(
		(float(anchor.x) + float(footprint.x) * 0.5) * CELL_SIZE_PX,
		(float(anchor.y) + float(footprint.y) - 0.5) * CELL_SIZE_PX
	)
	sprite.position = base_row_center
	## Lift the art so its lowest opaque pixel rests on the bottom of that row.
	sprite.offset = Vector2(0, float(CELL_SIZE_PX) * 0.5 + float(frame_h) * 0.5 - float(_art_bottom_px(tex, frame_h)))
	entities_root.add_child(sprite)
	if sprite.sprite_frames.has_animation(&"idle"):
		sprite.play(&"idle")
	_chunk_decor_list(chunk).append(sprite)

	## Claim the ground so trees, bushes, gold and sheep keep clear.
	for dx in range(footprint.x):
		for dy in range(footprint.y):
			_blocked_cells[anchor + Vector2i(dx, dy)] = true

	_add_structure_collider(chunk, anchor, footprint)

	if with_fire:
		WorldVfx.attach_fire(sprite, Vector2(6, -float(frame_h) * 0.30), 0.7)


func _build_strip_frames(tex: Texture2D, frames: int, frame_w: int, frame_h: int) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.set_animation_speed(&"default", 8.0)
	sf.add_animation(&"idle")
	sf.set_animation_speed(&"idle", 8.0)
	sf.set_animation_loop(&"idle", true)
	for i in range(frames):
		if frames == 1:
			sf.add_frame(&"idle", tex)
			continue
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(float(i * frame_w), 0.0, float(frame_w), float(frame_h))
		sf.add_frame(&"idle", atlas)
	return sf


## Y offset (within a frame) of the lowest opaque pixel, so art with transparent
## padding underneath still sits flush on the ground.
func _art_bottom_px(tex: Texture2D, frame_h: int) -> int:
	var img: Image = tex.get_image()
	if img == null:
		return frame_h
	if img.is_compressed():
		return frame_h
	var used: Rect2i = img.get_used_rect()
	if used.size.y <= 0:
		return frame_h
	return mini(frame_h, used.end.y)


func _add_structure_collider(chunk: Vector2i, anchor: Vector2i, footprint: Vector2i) -> void:
	var holder: Node2D = _chunk_barriers.get(chunk, null) as Node2D
	if holder == null or not is_instance_valid(holder):
		return
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector2(
		(float(anchor.x) + float(footprint.x) * 0.5) * CELL_SIZE_PX,
		(float(anchor.y) + float(footprint.y) * 0.5) * CELL_SIZE_PX
	)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(
		float(footprint.x) * CELL_SIZE_PX * 0.9,
		float(footprint.y) * CELL_SIZE_PX * 0.9
	)
	shape.shape = rect
	body.add_child(shape)
	holder.add_child(body)


## Uniform, unobstructed ground of the requested size. `on_water` flips the test
## for stilted structures that belong in the sea.
func _poi_pad_clear(anchor: Vector2i, footprint: Vector2i, heights: Dictionary, on_water: bool) -> bool:
	var base: int = int(heights.get(anchor, sample_height(anchor.x, anchor.y)))
	if on_water:
		if base != ElevationLevel.WATER:
			return false
	elif base == ElevationLevel.WATER:
		return false
	for dy in range(footprint.y):
		for dx in range(footprint.x):
			var c := anchor + Vector2i(dx, dy)
			if int(heights.get(c, sample_height(c.x, c.y))) != base:
				return false
			if _tree_cells.has(c) or _stair_cells.has(c) or _blocked_cells.has(c):
				return false
			## On land, keep clear of the shoreline so nothing overhangs water.
			if not on_water and _borders_water_dict(c, heights):
				return false
	return true


## One gold vein and/or one sheep herd per chunk, seeded and capped.
func _place_resources_in_chunk(chunk: Vector2i, origin: Vector2i, heights: Dictionary) -> void:
	if entities_root == null:
		return
	var list: Array = _chunk_decor_list(chunk)

	var chash: int = absi(hash(Vector3i(master_seed + 901, chunk.x, chunk.y)))
	var half: int = CHUNK_SIZE >> 1
	var center := origin + Vector2i(half, half)
	var biome: Biome = _sample_biome(center.x, center.y)

	## --- Gold vein: high ground only, favored in Savannah/Scorched hills ---
	var vein_chance: float = gold_vein_chance if biome in [Biome.SAVANNAH, Biome.SCORCHED] else gold_vein_chance * 0.25
	if float(chash % 1000) / 1000.0 < vein_chance:
		var elevated: Array[Vector2i] = []
		for ly in range(CHUNK_SIZE):
			for lx in range(CHUNK_SIZE):
				var cell := origin + Vector2i(lx, ly)
				if _stair_cells.has(cell) or _blocked_cells.has(cell):
					continue
				if int(heights[cell]) >= ElevationLevel.ELEV1:
					elevated.append(cell)
		if elevated.size() >= 4:
			var anchor: Vector2i = elevated[(chash >> 4) % elevated.size()]
			var stones: int = 3 + ((chash >> 8) % 3) ## 3-5 stones per vein
			for i in range(stones):
				var shash: int = absi(hash(Vector4i(master_seed, anchor.x, anchor.y, i)))
				var cell := anchor + Vector2i((shash % 3) - 1, ((shash >> 3) % 3) - 1)
				if not heights.has(cell) or int(heights[cell]) < ElevationLevel.ELEV1:
					cell = anchor
				var tex_idx: int = shash % GOLD_STONE_TEXTURES.size()
				var stone: Sprite2D = MineableGoldScript.new()
				stone.name = "GoldStone_%d_%d_%d" % [cell.x, cell.y, i]
				stone.texture = GOLD_STONE_TEXTURES[tex_idx]
				stone.highlight_texture = GOLD_STONE_HIGHLIGHTS[tex_idx]
				stone.position = Vector2(
					(float(cell.x) + 0.3 + 0.4 * float((shash >> 6) % 2)) * CELL_SIZE_PX,
					(float(cell.y) + 0.3 + 0.4 * float((shash >> 7) % 2)) * CELL_SIZE_PX
				)
				entities_root.add_child(stone)
				list.append(stone)

	## --- Sheep herd: open meadow flats only ---
	if biome == Biome.MEADOW and float((chash >> 12) % 1000) / 1000.0 < sheep_herd_chance:
		var open_flats: Array[Vector2i] = []
		for ly in range(2, CHUNK_SIZE - 2):
			for lx in range(2, CHUNK_SIZE - 2):
				var cell := origin + Vector2i(lx, ly)
				if int(heights[cell]) != ElevationLevel.FLAT:
					continue
				if _tree_cells.has(cell) or _stair_cells.has(cell) or _blocked_cells.has(cell):
					continue
				if _borders_water_dict(cell, heights):
					continue
				open_flats.append(cell)
		if open_flats.size() >= 6:
			var anchor: Vector2i = open_flats[(chash >> 16) % open_flats.size()]
			var count: int = 2 + ((chash >> 20) % 3) ## 2-4 sheep per herd
			for i in range(count):
				var shash: int = absi(hash(Vector4i(master_seed + 5, anchor.x, anchor.y, i)))
				var pos := Vector2(
					(float(anchor.x) + 0.5) * CELL_SIZE_PX + float((shash % 96)) - 48.0,
					(float(anchor.y) + 0.5) * CELL_SIZE_PX + float(((shash >> 8) % 96)) - 48.0
				)
				var sheep := SHEEP_SCENE.instantiate() as Node2D
				sheep.name = "Sheep_%d_%d_%d" % [anchor.x, anchor.y, i]
				sheep.position = pos
				if (shash >> 5) % 2 == 0 and sheep is AnimatedSprite2D:
					(sheep as AnimatedSprite2D).flip_h = true
				sheep.add_to_group("resource_sheep")
				entities_root.add_child(sheep)
				list.append(sheep)

	_chunk_decor[chunk] = list


func _spawn_animated_decor(frames: SpriteFrames, pos: Vector2, label: String) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.name = "%s_%d_%d" % [label, int(pos.x), int(pos.y)]
	sprite.sprite_frames = frames
	sprite.position = pos
	entities_root.add_child(sprite)
	if frames.has_animation(&"idle"):
		var count: int = frames.get_frame_count(&"idle")
		if count > 0:
			sprite.frame = _rng.randi() % count
		sprite.play(&"idle")
	return sprite


func _borders_land(cell: Vector2i, heights: Dictionary) -> bool:
	for d in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		var n: Vector2i = cell + d
		if int(heights.get(n, sample_height(n.x, n.y))) != ElevationLevel.WATER:
			return true
	return false


func _unload_chunk_decor(chunk: Vector2i) -> void:
	if not _chunk_decor.has(chunk):
		return
	for decor in _chunk_decor[chunk]:
		if is_instance_valid(decor):
			decor.queue_free()
	_chunk_decor.erase(chunk)


func _clear_all_decor() -> void:
	for chunk in _chunk_decor.keys():
		_unload_chunk_decor(chunk)
	_chunk_decor.clear()


## ---------------------------------------------------------------------------
## Stairs + walk rules (no mountain climb without stairs)
## ---------------------------------------------------------------------------
func _place_stairs_in_chunk(
	layout: Dictionary,
	level: ElevationLevel,
	grass_layer: TileMapLayer,
	stone_layer: TileMapLayer
) -> void:
	if grass_layer == null or stone_layer == null:
		return
	var origin: Vector2i = layout.origin
	var heights: Dictionary = layout.heights
	var spacing: int = maxi(stair_spacing, 2)
	var placed := false
	var fallback := Vector2i(2147483647, 2147483647)

	## The ramp reaches RAMP_DEPTH rows below the rim and RAMP_WIDTH cells east,
	## and must stay inside this chunk so unloading a neighbour can never erase
	## half of it.
	for ly in range(CHUNK_SIZE - RAMP_DEPTH):
		for lx in range(CHUNK_SIZE - RAMP_WIDTH + 1):
			var cell := origin + Vector2i(lx, ly)
			if not _stair_site_clear(cell, level, heights):
				continue
			if fallback.x == 2147483647:
				fallback = cell
			if absi(hash(Vector3i(master_seed + 91, cell.x, cell.y))) % spacing != 0:
				continue
			_carve_stair(cell, level, heights, grass_layer, stone_layer)
			placed = true

	## Reachability guarantee: a chunk with elevated ground always gets a way up,
	## otherwise its gold veins could be stranded.
	if not placed and fallback.x != 2147483647:
		_carve_stair(fallback, level, heights, grass_layer, stone_layer)


## A stair needs a straight run of rim cells with clear lower ground behind the
## whole ramp footprint, and no other opening already perforating this rim.
func _stair_site_clear(cell: Vector2i, level: int, heights: Dictionary) -> bool:
	var lower: int = level - 1
	for dx in range(RAMP_WIDTH):
		var rim := cell + Vector2i(dx, 0)
		if int(heights.get(rim, sample_height(rim.x, rim.y))) != level:
			return false
		for dy in range(1, RAMP_DEPTH + 1):
			var c := rim + Vector2i(0, dy)
			if int(heights.get(c, sample_height(c.x, c.y))) != lower:
				return false
	## Keep openings apart so a rim isn't riddled with holes.
	for dx in range(-RAMP_WIDTH, RAMP_WIDTH * 2):
		for dy in range(0, RAMP_DEPTH + 1):
			if _stair_cells.has(cell + Vector2i(dx, dy)):
				return false
	return true


func _carve_stair(
	cell: Vector2i,
	level: int,
	heights: Dictionary,
	grass_layer: TileMapLayer,
	stone_layer: TileMapLayer
) -> void:
	## Rim + every ramp row counts as stair ground so can_enter_cell allows the
	## one-level climb here and nowhere else.
	for dx in range(RAMP_WIDTH):
		for dy in range(RAMP_DEPTH + 1):
			_stair_cells[cell + Vector2i(dx, dy)] = true

	var upper := [RAMP_WEST_UPPER, RAMP_EAST_UPPER]
	var lower := [RAMP_WEST_LOWER, RAMP_EAST_LOWER]
	for dx in range(RAMP_WIDTH):
		for dy in range(1, RAMP_DEPTH + 1):
			var target := cell + Vector2i(dx, dy)
			stone_layer.erase_cell(target)
			var atlas: Vector2i = upper[dx] if dy == 1 else lower[dx]
			grass_layer.set_cell(target, ATLAS_ID, atlas, 0)

	## The wall runs either side of the opening now terminate, so re-resolve them.
	_repaint_wall(cell + Vector2i(-1, 1), level, heights, stone_layer)
	_repaint_wall(cell + Vector2i(RAMP_WIDTH, 1), level, heights, stone_layer)


func can_enter_cell(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if from_cell == to_cell:
		return true
	if _blocked_cells.has(to_cell):
		return false
	var ht: int = _cached_height(to_cell)
	if ht == ElevationLevel.WATER:
		return false
	## Trees don't block the whole 64px cell; the tree scene's own StaticBody2D
	## (small CircleShape2D on the trunk) handles collision, so the player can
	## walk into/under the canopy and only bump the trunk itself.
	var hf: int = _cached_height(from_cell)
	if ht == hf:
		return true
	## Elevation change only through registered stair cells.
	if _stair_cells.has(from_cell) and _stair_cells.has(to_cell):
		return absi(ht - hf) == 1
	return false


func _cached_height(cell: Vector2i) -> int:
	var chunk := cell_to_chunk(cell)
	var layout: Dictionary = _chunk_layouts.get(chunk, {})
	if not layout.is_empty() and layout.heights.has(cell):
		return int(layout.heights[cell])
	return sample_height(cell.x, cell.y)


func cached_height_at(cell: Vector2i) -> int:
	return _cached_height(cell)


func is_stair_cell(cell: Vector2i) -> bool:
	return _stair_cells.has(cell)


## ---------------------------------------------------------------------------
## Physics barriers (water + non-stair cliff faces)
## ---------------------------------------------------------------------------
func _place_barriers_in_chunk(chunk: Vector2i, origin: Vector2i, heights: Dictionary) -> void:
	## Physics blockers for water only. Mountain climb is gated by can_enter_cell + stairs
	## so flat land at the cliff foot stays walkable.
	if _barrier_root == null:
		return
	var holder := Node2D.new()
	holder.name = "ChunkBarriers_%d_%d" % [chunk.x, chunk.y]
	_barrier_root.add_child(holder)
	_chunk_barriers[chunk] = holder

	for ly in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var cell := origin + Vector2i(lx, ly)
			if heights[cell] == ElevationLevel.WATER:
				_add_cell_blocker(holder, cell)


func _add_cell_blocker(parent: Node2D, cell: Vector2i) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector2((float(cell.x) + 0.5) * CELL_SIZE_PX, (float(cell.y) + 0.5) * CELL_SIZE_PX)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(CELL_SIZE_PX * 0.92, CELL_SIZE_PX * 0.92)
	shape.shape = rect
	body.add_child(shape)
	parent.add_child(body)


func _unload_chunk_barriers(chunk: Vector2i) -> void:
	if not _chunk_barriers.has(chunk):
		return
	var holder: Node = _chunk_barriers[chunk]
	if is_instance_valid(holder):
		holder.queue_free()
	_chunk_barriers.erase(chunk)


func _clear_all_barriers() -> void:
	for chunk in _chunk_barriers.keys():
		_unload_chunk_barriers(chunk)
	_chunk_barriers.clear()


func _borders_water_dict(cell: Vector2i, heights: Dictionary) -> bool:
	for d in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		var n: Vector2i = cell + d
		var nh: int = heights.get(n, sample_height(n.x, n.y))
		if nh == ElevationLevel.WATER:
			return true
	return false


func _erase_foam_at(cell: Vector2i) -> void:
	if _foam_sprites == null or layer_water_foam == null:
		return
	var want := "Foam_%d_%d" % [cell.x, cell.y]
	var node := _foam_sprites.get_node_or_null(want)
	if node:
		_foam_sprites.remove_child(node)
		node.free()


func _clear_foam() -> void:
	if _foam_sprites == null:
		return
	for child in _foam_sprites.get_children():
		_foam_sprites.remove_child(child)
		child.free()


func _set_layers_visible(vis: bool) -> void:
	for layer in _all_layers():
		if layer:
			layer.visible = vis


func find_spawn_position() -> Vector2:
	## Search near origin for flat land (not water, not tree).
	for r in range(0, 64):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r and r > 0:
					continue
				if sample_height(dx, dy) != ElevationLevel.FLAT:
					continue
				var cell := Vector2i(dx, dy)
				if _tree_cells.has(cell):
					continue
				return Vector2((float(dx) + 0.5) * CELL_SIZE_PX, (float(dy) + 0.5) * CELL_SIZE_PX)
	return Vector2(CELL_SIZE_PX * 0.5, CELL_SIZE_PX * 0.5)


func get_world_seed() -> int:
	return master_seed
	

func _stage_pause() -> void:
	if stage_delay_sec <= 0.0:
		await get_tree().process_frame
	else:
		await get_tree().create_timer(stage_delay_sec).timeout
