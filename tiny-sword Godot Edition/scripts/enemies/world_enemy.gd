extends CharacterBody2D
class_name WorldEnemy
const DamageText := preload("res://scripts/ui/damage_indicator.gd")
const WorldEffects := preload("res://scripts/fx/world_vfx.gd")

## Biome enemy: wanders near its spawn, chases and attacks the player on sight.
## Movement respects the procedural world's cell rules (no cliff climbing; aquatic
## enemies stay in water). Spawned/configured by EnemySpawner.

signal died(enemy: WorldEnemy)

@export var enemy_type: String = "enemy"
@export var max_hp: float = 40.0
@export var move_speed: float = 100.0
@export var aggro_range: float = 260.0
@export var attack_range: float = 56.0
@export var attack_damage: float = 8.0
@export var attack_cooldown: float = 1.2
@export var wander_radius: float = 160.0
@export var aquatic: bool = false

var hp: float = 40.0
var world: Node = null

var _home: Vector2
var _wander_target: Vector2
var _wander_wait: float = 0.0
var _attack_timer: float = 0.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1
	hp = max_hp
	_home = global_position
	_wander_target = _home
	if _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation(&"idle"):
		_sprite.play(&"idle")


func configure(type_name: String, frames: SpriteFrames, stats: Dictionary, world_ref: Node) -> void:
	enemy_type = type_name
	world = world_ref
	max_hp = stats.get("hp", max_hp)
	hp = max_hp
	move_speed = stats.get("speed", move_speed)
	attack_damage = stats.get("damage", attack_damage)
	aggro_range = stats.get("aggro", aggro_range)
	aquatic = stats.get("aquatic", false)
	var scale_f: float = stats.get("scale", 1.0)
	if _sprite == null:
		_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if _sprite:
		_sprite.sprite_frames = frames
		_sprite.scale = Vector2(scale_f, scale_f)
		if frames and frames.has_animation(&"idle"):
			_sprite.play(&"idle")


func _physics_process(delta: float) -> void:
	_attack_timer = maxf(0.0, _attack_timer - delta)

	var player := get_tree().get_first_node_in_group("player") as Node2D
	var player_hp = player.get("hp") if player != null else null
	var player_alive: bool = player_hp != null and float(player_hp) > 0.0
	var moving := false

	if player_alive and global_position.distance_to(player.global_position) <= aggro_range:
		var dist := global_position.distance_to(player.global_position)
		if dist <= attack_range:
			velocity = Vector2.ZERO
			_try_attack(player)
		else:
			moving = _step_towards(player.global_position, delta)
	else:
		moving = _wander(delta)

	move_and_slide()
	_update_animation(moving)


func _wander(delta: float) -> bool:
	if global_position.distance_to(_wander_target) < 12.0:
		_wander_wait -= delta
		if _wander_wait <= 0.0:
			_wander_wait = randf_range(1.2, 3.5)
			var angle := randf() * TAU
			_wander_target = _home + Vector2.RIGHT.rotated(angle) * randf_range(24.0, wander_radius)
		velocity = Vector2.ZERO
		return false
	return _step_towards(_wander_target, delta, 0.55)


## Moves one step toward `target` if the world's cell rules allow it.
func _step_towards(target: Vector2, delta: float, speed_mult: float = 1.0) -> bool:
	var dir := global_position.direction_to(target)
	var speed := move_speed * speed_mult
	var from_cell := _cell_at(global_position)
	var want := global_position + dir * speed * maxf(delta, 0.001)
	if _cell_ok(from_cell, _cell_at(want)):
		velocity = dir * speed
	else:
		## Axis slide fallback (same trick as the player controller).
		var vx := dir.x * speed if _cell_ok(from_cell, _cell_at(Vector2(want.x, global_position.y))) else 0.0
		var vy := dir.y * speed if _cell_ok(from_cell, _cell_at(Vector2(global_position.x, want.y))) else 0.0
		velocity = Vector2(vx, vy)
		if velocity.length_squared() < 1.0:
			## Fully blocked: pick a new wander spot next frame.
			_wander_target = global_position
			return false
	if _sprite and absf(dir.x) > 0.05:
		_sprite.flip_h = dir.x < 0.0
	return true


func _cell_at(pos: Vector2) -> Vector2i:
	if world and world.has_method("global_to_cell"):
		return world.global_to_cell(pos)
	return Vector2i(floori(pos.x / 64.0), floori(pos.y / 64.0))


func _cell_ok(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if world == null:
		return true
	if aquatic:
		## Aquatic enemies swim: only water cells are passable.
		if world.has_method("sample_height"):
			return int(world.sample_height(to_cell.x, to_cell.y)) == -1
		return true
	if world.has_method("can_enter_cell"):
		return bool(world.can_enter_cell(from_cell, to_cell))
	return true


func _try_attack(player: Node2D) -> void:
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_cooldown
	if _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation(&"attack"):
		_sprite.play(&"attack")
	if player.has_method("apply_damage"):
		player.apply_damage(attack_damage)


func take_damage(amount: float, source: Node2D = null) -> void:
	if amount <= 0.0:
		return
	hp -= amount
	DamageText.spawn(get_parent(), global_position + Vector2(0, -48), amount, Color(1.0, 0.88, 0.38))
	if _sprite:
		_sprite.modulate = Color(1, 0.6, 0.6)
		var tw := create_tween()
		tw.tween_property(_sprite, "modulate", Color.WHITE, 0.2)
	if source:
		velocity += source.global_position.direction_to(global_position) * 110.0
	if hp <= 0.0:
		died.emit(self)
		var parent := get_parent()
		if parent:
			if aquatic:
				WorldEffects.spawn_splash(parent, global_position)
			else:
				WorldEffects.spawn_dust(parent, global_position)
		queue_free()


func _update_animation(moving: bool) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	## Let a started attack anim finish its loop pass before switching.
	if _sprite.animation == &"attack" and _attack_timer > attack_cooldown * 0.5:
		return
	var anim: StringName = &"run" if moving else &"idle"
	if _sprite.animation != anim and _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)
