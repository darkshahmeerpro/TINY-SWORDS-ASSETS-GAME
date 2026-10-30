extends Node
class_name EnemySpawner

## Chunk-driven enemy spawning: listens to the procedural engine's
## chunk_generated signal and rolls seeded, biome-appropriate spawns.
## Despawns automatically when the engine unloads a chunk's cells is not
## needed — this node tracks per-chunk enemies and frees them itself.

const ENEMY_SCENE := preload("res://scenes/enemies/world_enemy.tscn")

## Stats + SpriteFrames per enemy type. Frame resources are loaded lazily so a
## missing import never crashes world gen.
const ENEMY_DB := {
	"torch_goblin": {"frames": "res://resources/enemies/torch_goblin_frames.tres", "hp": 30.0, "damage": 6.0, "speed": 115.0},
	"spear_goblin": {"frames": "res://resources/enemies/spear_goblin_frames.tres", "hp": 35.0, "damage": 8.0, "speed": 105.0},
	"pig_rider": {"frames": "res://resources/enemies/pig_rider_frames.tres", "hp": 50.0, "damage": 10.0, "speed": 145.0},
	"hex_shaman": {"frames": "res://resources/enemies/hex_shaman_frames.tres", "hp": 25.0, "damage": 10.0, "speed": 90.0},
	"troll": {"frames": "res://resources/enemies/troll_frames.tres", "hp": 120.0, "damage": 18.0, "speed": 60.0, "scale": 1.15},
	"spider": {"frames": "res://resources/enemies/spider_frames.tres", "hp": 25.0, "damage": 6.0, "speed": 130.0},
	"gnoll": {"frames": "res://resources/enemies/gnoll_frames.tres", "hp": 40.0, "damage": 8.0, "speed": 100.0},
	"thief": {"frames": "res://resources/enemies/thief_frames.tres", "hp": 30.0, "damage": 6.0, "speed": 150.0},
	"minotaur": {"frames": "res://resources/enemies/minotaur_frames.tres", "hp": 100.0, "damage": 16.0, "speed": 80.0, "scale": 1.15},
	"bear": {"frames": "res://resources/enemies/bear_frames.tres", "hp": 80.0, "damage": 14.0, "speed": 95.0},
	"snake": {"frames": "res://resources/enemies/snake_frames.tres", "hp": 20.0, "damage": 5.0, "speed": 110.0},
	"lizard": {"frames": "res://resources/enemies/lizard_frames.tres", "hp": 30.0, "damage": 7.0, "speed": 100.0},
	"gnome": {"frames": "res://resources/enemies/gnome_frames.tres", "hp": 25.0, "damage": 5.0, "speed": 120.0},
	"bomb_fish": {"frames": "res://resources/enemies/bomb_fish_frames.tres", "hp": 25.0, "damage": 10.0, "speed": 85.0, "aquatic": true},
	"harpoon_shark": {"frames": "res://resources/enemies/harpoon_shark_frames.tres", "hp": 45.0, "damage": 10.0, "speed": 95.0, "aquatic": true},
	"paddle_shark": {"frames": "res://resources/enemies/paddle_shark_frames.tres", "hp": 40.0, "damage": 8.0, "speed": 90.0, "aquatic": true},
}

## Biome -> weighted enemy pools (TinySwordsProceduralEngine.Biome values).
const BIOME_POOLS := {
	TinySwordsProceduralEngine.Biome.MEADOW: [], ## player realm stays safe
	TinySwordsProceduralEngine.Biome.SAVANNAH: ["gnoll", "gnoll", "thief", "thief", "gnome", "minotaur"],
	TinySwordsProceduralEngine.Biome.GLOOM_FOREST: ["hex_shaman", "hex_shaman", "spider", "spider", "troll"],
	TinySwordsProceduralEngine.Biome.SCORCHED: ["torch_goblin", "torch_goblin", "spear_goblin", "spear_goblin", "pig_rider"],
	TinySwordsProceduralEngine.Biome.PINE_HIGHLANDS: ["bear", "snake", "snake", "lizard", "lizard", "spider"],
}
const WATER_POOL := ["bomb_fish", "harpoon_shark", "paddle_shark"]

@export var world_path: NodePath
@export var entities_path: NodePath
## No enemies spawn within this radius (cells) of the world origin.
@export var safety_radius_cells: int = 44
## Max land enemies rolled per chunk.
@export_range(0, 6, 1) var max_enemies_per_chunk: int = 3
## Chance each chunk hosts any enemies at all.
@export_range(0.0, 1.0, 0.01) var chunk_spawn_chance: float = 0.55
## Chance a coastal water chunk spawns one aquatic enemy.
@export_range(0.0, 1.0, 0.01) var water_spawn_chance: float = 0.25

var _world: TinySwordsProceduralEngine
var _entities: Node2D
var _chunk_enemies: Dictionary = {} ## Vector2i -> Array[WorldEnemy]
var _frames_cache: Dictionary = {}


func _ready() -> void:
	_world = get_node_or_null(world_path) as TinySwordsProceduralEngine
	if _world == null:
		_world = get_tree().get_first_node_in_group("world_gen") as TinySwordsProceduralEngine
	_entities = get_node_or_null(entities_path) as Node2D
	if _world == null:
		push_warning("EnemySpawner: no world_gen found")
		return
	if _entities == null:
		_entities = _world.entities_root
	if not _world.chunk_generated.is_connected(_on_chunk_generated):
		_world.chunk_generated.connect(_on_chunk_generated)


func _process(_delta: float) -> void:
	## Free enemies whose chunk was unloaded by the streaming engine.
	if _world == null:
		return
	var stale: Array = []
	for chunk in _chunk_enemies.keys():
		if not _world._loaded_chunks.has(chunk):
			stale.append(chunk)
	for chunk in stale:
		_despawn_chunk(chunk)


func _on_chunk_generated(chunk: Vector2i) -> void:
	if _world == null or _entities == null or _chunk_enemies.has(chunk):
		return
	var list: Array = []
	_chunk_enemies[chunk] = list

	var size: int = TinySwordsProceduralEngine.CHUNK_SIZE
	var origin := Vector2i(chunk.x * size, chunk.y * size)
	var chash: int = absi(hash(Vector3i(_world.master_seed + 4242, chunk.x, chunk.y)))

	## Whole chunk inside the safety zone? Skip early.
	var center := origin + Vector2i(size >> 1, size >> 1)
	if Vector2(center).length() < float(safety_radius_cells):
		return

	_roll_land_spawns(chunk, origin, chash, list)
	_roll_water_spawns(chunk, origin, chash, list)


func _roll_land_spawns(chunk: Vector2i, origin: Vector2i, chash: int, list: Array) -> void:
	if float(chash % 1000) / 1000.0 > chunk_spawn_chance:
		return
	var biome: int = _world.sample_biome_at(origin + Vector2i(8, 8))
	var pool: Array = BIOME_POOLS.get(biome, [])
	if pool.is_empty():
		return

	var count: int = 1 + ((chash >> 6) % max_enemies_per_chunk)
	var placed := 0
	var attempts := 0
	while placed < count and attempts < 24:
		attempts += 1
		var ahash: int = absi(hash(Vector4i(_world.master_seed, chunk.x, chunk.y, attempts)))
		var cell := origin + Vector2i(ahash % TinySwordsProceduralEngine.CHUNK_SIZE, (ahash >> 5) % TinySwordsProceduralEngine.CHUNK_SIZE)
		if not _valid_land_cell(cell):
			continue
		var type_name: String = pool[(ahash >> 10) % pool.size()]
		_spawn(type_name, cell, list)
		placed += 1


func _roll_water_spawns(chunk: Vector2i, origin: Vector2i, chash: int, list: Array) -> void:
	if float((chash >> 10) % 1000) / 1000.0 > water_spawn_chance:
		return
	var attempts := 0
	while attempts < 16:
		attempts += 1
		var ahash: int = absi(hash(Vector4i(_world.master_seed + 77, chunk.x, chunk.y, attempts)))
		var cell := origin + Vector2i(ahash % TinySwordsProceduralEngine.CHUNK_SIZE, (ahash >> 5) % TinySwordsProceduralEngine.CHUNK_SIZE)
		if _world.sample_height(cell.x, cell.y) != TinySwordsProceduralEngine.ElevationLevel.WATER:
			continue
		var type_name: String = WATER_POOL[(ahash >> 10) % WATER_POOL.size()]
		_spawn(type_name, cell, list)
		return


func _valid_land_cell(cell: Vector2i) -> bool:
	if Vector2(cell).length() < float(safety_radius_cells):
		return false
	if _world.sample_height(cell.x, cell.y) == TinySwordsProceduralEngine.ElevationLevel.WATER:
		return false
	if _world.is_stair_cell(cell):
		return false
	return true


func _spawn(type_name: String, cell: Vector2i, list: Array) -> void:
	var stats: Dictionary = ENEMY_DB.get(type_name, {})
	if stats.is_empty():
		return
	var frames := _load_frames(stats.frames)
	if frames == null:
		return
	var enemy := ENEMY_SCENE.instantiate() as WorldEnemy
	enemy.name = "%s_%d_%d" % [type_name, cell.x, cell.y]
	enemy.position = Vector2(
		(float(cell.x) + 0.5) * TinySwordsProceduralEngine.CELL_SIZE_PX,
		(float(cell.y) + 0.5) * TinySwordsProceduralEngine.CELL_SIZE_PX
	)
	_entities.add_child(enemy)
	enemy.configure(type_name, frames, stats, _world)
	list.append(enemy)
	if stats.get("aquatic", false):
		WorldVfx.spawn_splash(_entities, enemy.position)
	else:
		WorldVfx.spawn_dust(_entities, enemy.position)


func _load_frames(path: String) -> SpriteFrames:
	if _frames_cache.has(path):
		return _frames_cache[path]
	var frames: SpriteFrames = null
	if ResourceLoader.exists(path):
		frames = load(path) as SpriteFrames
	_frames_cache[path] = frames
	if frames == null:
		push_warning("EnemySpawner: missing frames %s" % path)
	return frames


func _despawn_chunk(chunk: Vector2i) -> void:
	for enemy in _chunk_enemies.get(chunk, []):
		if is_instance_valid(enemy):
			enemy.queue_free()
	_chunk_enemies.erase(chunk)
