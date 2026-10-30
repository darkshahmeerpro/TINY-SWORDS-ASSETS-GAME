extends Node2D
class_name HarvestableTree
const DamageText := preload("res://scripts/ui/damage_indicator.gd")
const WorldEffects := preload("res://scripts/fx/world_vfx.gd")
const DropScript := preload("res://scripts/world/resource_drop.gd")

const STUMP_TEXTURES := [
	preload("res://assets/resources_pack/Wood/Trees/Stump 1.png"),
	preload("res://assets/resources_pack/Wood/Trees/Stump 2.png"),
	preload("res://assets/resources_pack/Wood/Trees/Stump 3.png"),
	preload("res://assets/resources_pack/Wood/Trees/Stump 4.png"),
]

@export var max_hp: float = 60.0
@export var wood_drop_count: int = 2

var hp: float


func _ready() -> void:
	hp = max_hp
	add_to_group("harvestable_trees")


func take_damage(amount: float, _source: Node2D = null) -> void:
	if amount <= 0.0:
		return
	hp -= amount
	DamageText.spawn(get_parent(), global_position + Vector2(0, -110), amount, Color(0.92, 0.76, 0.36))
	modulate = Color(1.0, 0.74, 0.48)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.16)
	## Canopy shake sells the axe impact.
	var sprite := get_node_or_null("Sprite") as Node2D
	if sprite:
		var shake := create_tween()
		shake.tween_property(sprite, "rotation", 0.05, 0.05)
		shake.tween_property(sprite, "rotation", -0.04, 0.08)
		shake.tween_property(sprite, "rotation", 0.0, 0.07)
	if hp <= 0.0:
		_fell()


func _fell() -> void:
	var parent := get_parent()
	if parent:
		WorldEffects.spawn_dust(parent, global_position)
		for i in range(wood_drop_count):
			DropScript.spawn(parent, global_position, "wood")
		## Leave a stump so the clearing reads as chopped, not vanished.
		var stump := Sprite2D.new()
		stump.name = "Stump_%d_%d" % [int(global_position.x), int(global_position.y)]
		stump.texture = STUMP_TEXTURES[randi() % STUMP_TEXTURES.size()]
		stump.position = global_position
		stump.modulate = modulate
		parent.add_child(stump)
	queue_free()
