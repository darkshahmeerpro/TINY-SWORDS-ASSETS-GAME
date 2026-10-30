extends CharacterBody2D
class_name Unit
const DamageText := preload("res://scripts/ui/damage_indicator.gd")
const WorldEffects := preload("res://scripts/fx/world_vfx.gd")

signal died(unit: Unit)
signal selected_changed(unit: Unit, is_selected: bool)

enum State { IDLE, MOVE, CHASE, ATTACK, DEAD }

@export var team: String = "blue"
@export var unit_type: String = "warrior"
@export var max_hp: float = 100.0
@export var move_speed: float = 120.0
@export var attack_range: float = 48.0
@export var attack_damage: float = 12.0
@export var attack_cooldown: float = 0.8
@export var aggro_range: float = 220.0
@export var is_ranged: bool = false
@export var projectile_scene: PackedScene

var hp: float = 100.0
var state: int = State.IDLE
var selected: bool = false
var is_player_controllable: bool = false
var has_move_target: bool = false
var attack_move: bool = false
var move_target: Vector2 = Vector2.ZERO
var combat_target: Unit = null
var attack_timer: float = 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var agent: NavigationAgent2D = $NavigationAgent2D
@onready var health_bar: ProgressBar = $HealthBar
@onready var aggro_area: Area2D = $AggroArea


func _ready() -> void:
	hp = max_hp
	is_player_controllable = team == "blue"
	add_to_group("units")
	add_to_group("team_%s" % team)
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = hp
		health_bar.visible = false
	if agent:
		agent.max_speed = move_speed
	_setup_shapes()
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(&"idle"):
		sprite.play(&"idle")


func _setup_shapes() -> void:
	var body_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_shape and body_shape.shape == null:
		var circle := CircleShape2D.new()
		circle.radius = 14.0
		body_shape.shape = circle
	var aggro_shape := get_node_or_null("AggroArea/AggroShape") as CollisionShape2D
	if aggro_shape and aggro_shape.shape == null:
		var circle2 := CircleShape2D.new()
		circle2.radius = aggro_range
		aggro_shape.shape = circle2


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	attack_timer = maxf(0.0, attack_timer - delta)
	if is_player_controllable:
		_player_think()
	else:
		_ai_think()
	_process_movement(delta)
	_update_animation()
	if health_bar:
		health_bar.value = hp
		health_bar.visible = hp < max_hp or selected


func _player_think() -> void:
	if attack_move or combat_target != null:
		_acquire_target()
		if combat_target != null and is_instance_valid(combat_target) and combat_target.state != State.DEAD:
			var dist := global_position.distance_to(combat_target.global_position)
			if dist <= attack_range:
				state = State.ATTACK
				has_move_target = false
				if agent:
					agent.set_target_position(global_position)
				_try_attack()
			else:
				state = State.CHASE
				has_move_target = true
				move_target = combat_target.global_position
				if agent:
					agent.set_target_position(move_target)
			return
	if has_move_target:
		state = State.MOVE
	else:
		state = State.IDLE


func _ai_think() -> void:
	_acquire_target()
	if combat_target != null and is_instance_valid(combat_target) and combat_target.state != State.DEAD:
		var dist := global_position.distance_to(combat_target.global_position)
		if dist <= attack_range:
			state = State.ATTACK
			has_move_target = false
			if agent:
				agent.set_target_position(global_position)
			_try_attack()
		else:
			state = State.CHASE
			has_move_target = true
			move_target = combat_target.global_position
			if agent:
				agent.set_target_position(move_target)
	else:
		state = State.IDLE
		has_move_target = false


func _acquire_target() -> void:
	if combat_target != null and is_instance_valid(combat_target) and combat_target.state != State.DEAD:
		return
	combat_target = null
	var best: Unit = null
	var best_d := INF
	for u in get_tree().get_nodes_in_group("units"):
		if not (u is Unit):
			continue
		var other := u as Unit
		if other == self or other.team == team or other.state == State.DEAD:
			continue
		var d := global_position.distance_to(other.global_position)
		if d < best_d and d <= aggro_range:
			best_d = d
			best = other
	combat_target = best


func _process_movement(_delta: float) -> void:
	if agent == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if state == State.ATTACK or state == State.IDLE or state == State.DEAD:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if agent.is_navigation_finished():
		has_move_target = false
		if state == State.MOVE:
			state = State.IDLE
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var next_pos := agent.get_next_path_position()
	var dir := global_position.direction_to(next_pos)
	velocity = dir * move_speed
	move_and_slide()
	if absf(dir.x) > 0.1 and sprite:
		sprite.flip_h = dir.x < 0.0


func _try_attack() -> void:
	if attack_timer > 0.0:
		return
	if combat_target == null or not is_instance_valid(combat_target):
		return
	attack_timer = attack_cooldown
	if is_ranged and projectile_scene != null:
		var proj := projectile_scene.instantiate()
		get_tree().current_scene.add_child(proj)
		if proj.has_method("setup"):
			proj.setup(self, combat_target, attack_damage)
		elif "global_position" in proj:
			proj.global_position = global_position
	else:
		combat_target.take_damage(attack_damage, self)


func take_damage(amount: float, _source: Unit = null) -> void:
	if state == State.DEAD:
		return
	hp -= amount
	DamageText.spawn(get_parent(), global_position + Vector2(0, -52), amount, Color(1.0, 0.88, 0.35))
	if sprite:
		sprite.modulate = Color(1.0, 0.5, 0.5)
		var tw := create_tween()
		tw.tween_property(sprite, "modulate", Color.WHITE, 0.16)
	if hp <= 0.0:
		_die()


func _die() -> void:
	state = State.DEAD
	hp = 0.0
	selected = false
	velocity = Vector2.ZERO
	died.emit(self)
	WorldEffects.spawn_dust(get_parent(), global_position)
	queue_free()


func set_selected(value: bool) -> void:
	selected = value
	selected_changed.emit(self, selected)


func command_move(world_pos: Vector2, is_attack_move: bool = false) -> void:
	if state == State.DEAD:
		return
	attack_move = is_attack_move
	combat_target = null
	has_move_target = true
	move_target = world_pos
	state = State.MOVE
	if agent:
		agent.set_target_position(world_pos)


func command_attack(target: Unit) -> void:
	if state == State.DEAD or target == null:
		return
	combat_target = target
	attack_move = true
	has_move_target = true
	move_target = target.global_position
	state = State.CHASE
	if agent:
		agent.set_target_position(target.global_position)


func _update_animation() -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var anim := &"idle"
	match state:
		State.MOVE, State.CHASE:
			if sprite.sprite_frames.has_animation(&"run"):
				anim = &"run"
			elif sprite.sprite_frames.has_animation(&"walk"):
				anim = &"walk"
		State.ATTACK:
			if sprite.sprite_frames.has_animation(&"attack"):
				anim = &"attack"
			elif sprite.sprite_frames.has_animation(&"guard"):
				anim = &"guard"
		_:
			anim = &"idle"
	if sprite.animation != anim and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
