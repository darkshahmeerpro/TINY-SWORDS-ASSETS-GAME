class_name EmptyWorldScene
extends Node2D

## Infinite seeded world — generate chunks, spawn player, stream as they walk.

const PLAYER_SCENE := preload("res://scenes/player/world_player.tscn")
const WORLD_SCENE_PATH := "res://scenes/game/empty_world.tscn"

## Set from the main menu before changing to this scene (replaces WorldSave).
static var launch_world_name: String = "World"
static var launch_seed: int = 0
static var pending_staged_build: bool = true

@onready var world_gen: Node2D = $WorldGen
@onready var entities: Node2D = $Entities
@onready var _hud: Control = $UI/GameHUD

var _player: CharacterBody2D


func _ready() -> void:
	if _hud == null:
		_hud = get_node_or_null("UI/GameHUD") as Control
	if _hud and _hud.has_method("set_world_title"):
		_hud.set_world_title(launch_world_name)

	if launch_seed != 0:
		world_gen.master_seed = launch_seed

	world_gen.set("auto_build_on_ready", false)
	if world_gen.has_method("set_entities_root"):
		world_gen.set_entities_root(entities)
	if world_gen.has_signal("world_generation_progress"):
		if not world_gen.world_generation_progress.is_connected(_on_gen_progress):
			world_gen.world_generation_progress.connect(_on_gen_progress)

	var staged := pending_staged_build

	if staged:
		if _hud and _hud.has_method("show_loading"):
			_hud.show_loading("Generating world…")
		await world_gen.build_world_staged()
		if _hud and _hud.has_method("hide_loading"):
			await _hud.hide_loading()
	else:
		if _hud and _hud.has_method("hide_loading"):
			await _hud.hide_loading()
		world_gen.build_world()

	var world_seed: int = int(world_gen.get_world_seed()) if world_gen.has_method("get_world_seed") else launch_seed
	if _hud and _hud.has_method("set_seed_text"):
		_hud.set_seed_text(world_seed)
	if _hud and _hud.has_method("set_hint"):
		_hud.set_hint("WASD explore · stairs to climb · Esc pause")
	if _hud and _hud.has_method("set_info"):
		_hud.set_info("World ready. Build systems go here.")

	_spawn_player()
	if _hud and _hud.has_method("bind_world"):
		_hud.bind_world(world_gen, _player)


func _spawn_player() -> void:
	_player = entities.get_node_or_null("WorldPlayer") as CharacterBody2D
	if _player == null:
		_player = PLAYER_SCENE.instantiate() as CharacterBody2D
		_player.name = "WorldPlayer"
		entities.add_child(_player)

	if _player.has_method("set_world"):
		_player.set_world(world_gen)
	_player.set("world_path", _player.get_path_to(world_gen))

	var spawn: Vector2 = world_gen.find_spawn_position() if world_gen.has_method("find_spawn_position") else Vector2(32, 32)
	_player.global_position = spawn
	_player.visible = true

	if world_gen.has_method("set_follow_target"):
		world_gen.set_follow_target(_player)

	var old_cam := get_node_or_null("Camera2D") as Camera2D
	if old_cam:
		old_cam.enabled = false


const WATER_TILE_PX := 64.0


func _process(_delta: float) -> void:
	if _player == null:
		return
	var water := get_node_or_null("WaterBackground") as Sprite2D
	if water:
		## The backdrop is a repeating region, so it only has to be re-centred in
		## whole tiles — snapping keeps the ocean pattern from shimmering as the
		## player walks.
		var half: Vector2 = water.region_rect.size * 0.5
		var target: Vector2 = _player.global_position - half
		water.global_position = Vector2(
			snappedf(target.x, WATER_TILE_PX),
			snappedf(target.y, WATER_TILE_PX)
		)


func _on_gen_progress(phase_name: String, progress_percent: float) -> void:
	if _hud and _hud.has_method("set_loading_progress"):
		_hud.set_loading_progress(phase_name, progress_percent)
