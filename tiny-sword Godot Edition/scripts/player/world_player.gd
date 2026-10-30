extends CharacterBody2D

## Top-down walker. Mountains only via stairs; trees/water block movement.
const DamageText := preload("res://scripts/ui/damage_indicator.gd")
const WorldEffects := preload("res://scripts/fx/world_vfx.gd")

signal health_changed(current: float, maximum: float)
signal inventory_changed(inventory: Dictionary)
signal died

@export var move_speed: float = 220.0
@export var max_hp: float = 100.0
@export var world_path: NodePath = NodePath("../WorldGen")
@export var attack_damage: float = 20.0
@export var attack_range: float = 108.0
@export var action_cooldown: float = 0.48
@export var respawn_delay: float = 2.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _camera: Camera2D = $Camera2D

var _world: Node
var hp: float = 100.0
var inventory: Dictionary = {"wood": 0, "meat": 0, "gold": 0}
var _action_time: float = 0.0
var _hurt_time: float = 0.0
var _dead: bool = false
var _spawn_position: Vector2


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 ## Hit tree trunks + cliff/water barriers.
	hp = max_hp
	_spawn_position = global_position
	if _camera:
		_camera.make_current()
	if _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation(&"idle"):
		_sprite.play(&"idle")
	_world = get_node_or_null(world_path)
	if _world == null:
		_world = get_tree().get_first_node_in_group("world_gen")
	health_changed.emit(hp, max_hp)


func set_world(world: Node) -> void:
	_world = world


func apply_damage(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	_hurt_time = 0.18
	_flash(Color(1.0, 0.42, 0.42))
	DamageText.spawn(get_parent(), global_position + Vector2(0, -56), amount, Color(1.0, 0.32, 0.25))
	health_changed.emit(hp, max_hp)
	if hp <= 0.0:
		_die()


func heal(amount: float) -> void:
	if _dead:
		return
	hp = minf(max_hp, hp + amount)
	health_changed.emit(hp, max_hp)


func add_resource(type: String, amount: int = 1) -> void:
	inventory[type] = int(inventory.get(type, 0)) + amount
	inventory_changed.emit(inventory)


func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_context_action(get_global_mouse_position())


func _physics_process(delta: float) -> void:
	_action_time = maxf(0.0, _action_time - delta)
	_hurt_time = maxf(0.0, _hurt_time - delta)
	if _dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if _action_time > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir.length_squared() < 0.01:
		velocity = Vector2.ZERO
		_play_idle()
		move_and_slide()
		return

	var from_cell := _cell_at(global_position)
	## Prefer full diagonal; fall back to axis slide when blocked.
	var want := global_position + dir.normalized() * move_speed * _delta_safe()
	var to_cell := _cell_at(want)
	if _can_enter(from_cell, to_cell):
		velocity = dir.normalized() * move_speed
	else:
		var to_x := _cell_at(Vector2(want.x, global_position.y))
		var to_y := _cell_at(Vector2(global_position.x, want.y))
		var vx := dir.x * move_speed if _can_enter(from_cell, to_x) else 0.0
		var vy := dir.y * move_speed if _can_enter(from_cell, to_y) else 0.0
		velocity = Vector2(vx, vy)

	move_and_slide()

	_sprite.flip_h = dir.x < 0.0
	if _sprite.sprite_frames and _sprite.sprite_frames.has_animation(&"run"):
		if _sprite.animation != &"run":
			_sprite.play(&"run")


## Click shapes sized to each target's VISIBLE art, not its node origin.
## Trees draw ~170px above their trunk origin; units draw ~56px above their feet.
const CLICK_TARGETS := {
	"enemies": {"radius": 48.0, "center": Vector2(0, -30)},
	"resource_sheep": {"radius": 44.0, "center": Vector2(0, -26)},
	"harvestable_trees": {"rect": Rect2(-54.0, -178.0, 108.0, 196.0)},
	"resource_gold": {"radius": 42.0, "center": Vector2(0, -12)},
}


func _try_context_action(click_pos: Vector2) -> void:
	if _action_time > 0.0:
		return
	var target := _find_damageable_at(click_pos)
	if target:
		## Range is measured to the target itself so tall sprites clicked near
		## their top don't fail the check.
		if global_position.distance_to(target.global_position) > attack_range:
			return
		_begin_action(target.global_position)
		target.take_damage(attack_damage, self)
		WorldEffects.spawn_hit(get_parent(), target.global_position + Vector2(0, -20))
		return
	if global_position.distance_to(click_pos) <= attack_range and _is_water(click_pos):
		_begin_action(click_pos)
		_shoreline_splash(click_pos)


func _find_damageable_at(click_pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_score := INF
	for group_name in CLICK_TARGETS.keys():
		var shape: Dictionary = CLICK_TARGETS[group_name]
		for candidate in get_tree().get_nodes_in_group(group_name):
			if not (candidate is Node2D) or not candidate.has_method("take_damage"):
				continue
			var node := candidate as Node2D
			var hit := false
			var score := INF
			if shape.has("rect"):
				var rect: Rect2 = shape.rect
				rect.position += node.global_position
				hit = rect.has_point(click_pos)
				score = click_pos.distance_to(rect.get_center())
			else:
				var center: Vector2 = node.global_position + shape.center
				score = click_pos.distance_to(center)
				hit = score <= float(shape.radius)
			if hit and score < best_score:
				best_score = score
				best = node
	return best


func _is_water(pos: Vector2) -> bool:
	if _world == null or not _world.has_method("sample_height"):
		return false
	var cell := _cell_at(pos)
	return int(_world.sample_height(cell.x, cell.y)) == -1


func _begin_action(target_pos: Vector2) -> void:
	_action_time = action_cooldown
	if target_pos.x != global_position.x:
		_sprite.flip_h = target_pos.x < global_position.x
	if _sprite.sprite_frames and _sprite.sprite_frames.has_animation(&"interact"):
		_sprite.play(&"interact")


func _shoreline_splash(target_pos: Vector2) -> void:
	var parent := get_parent()
	if parent:
		WorldEffects.spawn_splash(parent, target_pos)
	var base := _sprite.position
	var tw := create_tween()
	tw.tween_property(_sprite, "position", base + Vector2(0, -10), 0.10)
	tw.tween_property(_sprite, "position", base, 0.16)


func _flash(color: Color) -> void:
	if _sprite == null:
		return
	_sprite.modulate = color
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate", Color.WHITE, 0.18)


func _die() -> void:
	_dead = true
	velocity = Vector2.ZERO
	_flash(Color(0.35, 0.35, 0.35))
	died.emit()
	WorldEffects.spawn_dust(get_parent(), global_position)
	await get_tree().create_timer(respawn_delay).timeout
	global_position = _spawn_position
	hp = max_hp
	_dead = false
	health_changed.emit(hp, max_hp)
	_play_idle()


func _delta_safe() -> float:
	return maxf(get_physics_process_delta_time(), 0.001)


func _cell_at(global_pos: Vector2) -> Vector2i:
	if _world and _world.has_method("global_to_cell"):
		return _world.global_to_cell(global_pos)
	return Vector2i(floori(global_pos.x / 64.0), floori(global_pos.y / 64.0))


func _can_enter(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if _world and _world.has_method("can_enter_cell"):
		return bool(_world.can_enter_cell(from_cell, to_cell))
	return true


func _play_idle() -> void:
	if _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation(&"idle"):
		if _sprite.animation != &"idle":
			_sprite.play(&"idle")
