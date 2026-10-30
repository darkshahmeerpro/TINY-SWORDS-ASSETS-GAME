extends AnimatedSprite2D

## Ambient sheep which can be attacked, flees after a hit, and drops meat.
const DamageText := preload("res://scripts/ui/damage_indicator.gd")
const WorldEffects := preload("res://scripts/fx/world_vfx.gd")
const DropScript := preload("res://scripts/world/resource_drop.gd")

@export var idle_time_min: float = 1.5
@export var idle_time_max: float = 3.5
@export var max_hp: float = 35.0
@export var flee_speed: float = 85.0

var _idle_left: float = 0.0
var _eating: bool = false
var hp: float = 35.0
var _flee_time: float = 0.0
var _flee_direction := Vector2.ZERO


func _ready() -> void:
	add_to_group("resource_sheep")
	hp = max_hp
	animation_finished.connect(_on_animation_finished)
	_start_idle()


func _process(delta: float) -> void:
	if _flee_time > 0.0:
		_flee_time -= delta
		position += _flee_direction * flee_speed * delta
		if sprite_frames and sprite_frames.has_animation(&"move"):
			play(&"move")
		return
	if _eating:
		return
	_idle_left -= delta
	if _idle_left <= 0.0:
		_start_eat()


func _start_idle() -> void:
	_eating = false
	play(&"idle")
	_idle_left = randf_range(idle_time_min, idle_time_max)


func _start_eat() -> void:
	if sprite_frames == null or not sprite_frames.has_animation(&"eat"):
		_start_idle()
		return
	_eating = true
	play(&"eat")


func _on_animation_finished() -> void:
	if animation == &"eat":
		_start_idle()


func take_damage(amount: float, source: Node2D = null) -> void:
	if amount <= 0.0:
		return
	hp -= amount
	DamageText.spawn(get_parent(), global_position + Vector2(0, -44), amount, Color(1.0, 0.9, 0.4))
	modulate = Color(1.0, 0.55, 0.55)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.16)
	if source:
		_flee_direction = source.global_position.direction_to(global_position)
	else:
		_flee_direction = Vector2.RIGHT.rotated(randf() * TAU)
	flip_h = _flee_direction.x < 0.0
	_flee_time = 1.4
	_eating = false
	if hp <= 0.0:
		_die()


func _die() -> void:
	var parent := get_parent()
	if parent:
		WorldEffects.spawn_dust(parent, global_position)
		DropScript.spawn(parent, global_position, "meat")
	queue_free()
