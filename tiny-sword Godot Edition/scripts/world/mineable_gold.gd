extends Sprite2D
class_name MineableGold

## Gold stone the player can mine with clicks. Shows its highlight variant
## while being worked, crumbles into collectible gold on depletion.

const DamageText := preload("res://scripts/ui/damage_indicator.gd")
const WorldEffects := preload("res://scripts/fx/world_vfx.gd")
const DropScript := preload("res://scripts/world/resource_drop.gd")

@export var max_hp: float = 50.0
@export var gold_drop_count: int = 2

var hp: float
var highlight_texture: Texture2D = null

var _base_texture: Texture2D = null


func _ready() -> void:
	hp = max_hp
	add_to_group("resource_gold")
	_base_texture = texture


func take_damage(amount: float, _source: Node2D = null) -> void:
	if amount <= 0.0:
		return
	hp -= amount
	DamageText.spawn(get_parent(), global_position + Vector2(0, -34), amount, Color(1.0, 0.84, 0.2))
	## Pulse the pack's highlight art (falls back to a flash when missing).
	if highlight_texture:
		texture = highlight_texture
		var back := get_tree().create_timer(0.14)
		back.timeout.connect(func() -> void:
			if is_instance_valid(self) and _base_texture:
				texture = _base_texture
		)
	else:
		modulate = Color(1.4, 1.3, 0.9)
		var tw := create_tween()
		tw.tween_property(self, "modulate", Color.WHITE, 0.16)
	var shake := create_tween()
	shake.tween_property(self, "offset", Vector2(3, 0), 0.04)
	shake.tween_property(self, "offset", Vector2(-2, 0), 0.05)
	shake.tween_property(self, "offset", Vector2.ZERO, 0.04)
	if hp <= 0.0:
		_deplete()


func _deplete() -> void:
	var parent := get_parent()
	if parent:
		WorldEffects.spawn_dust(parent, global_position)
		for i in range(gold_drop_count):
			DropScript.spawn(parent, global_position, "gold")
	queue_free()
