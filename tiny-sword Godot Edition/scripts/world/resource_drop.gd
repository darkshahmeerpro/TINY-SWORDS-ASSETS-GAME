extends Sprite2D
class_name ResourceDrop

## Collectible resource dropped by trees, sheep, and gold veins.
## Hops out on spawn, then magnets to the player and adds to their inventory.

const TEXTURES := {
	"wood": preload("res://assets/resources_pack/Wood/Wood Resource/Wood Resource.png"),
	"meat": preload("res://assets/resources_pack/Meat/Meat Resource/Meat Resource.png"),
	"gold": preload("res://assets/resources_pack/Gold/Gold Resource/Gold_Resource.png"),
}

const MAGNET_RADIUS := 72.0
const COLLECT_RADIUS := 20.0
const MAGNET_SPEED := 340.0

var resource_type: String = "wood"
var amount: int = 1

var _settle_time: float = 0.35 ## brief hop before it can be collected


static func spawn(parent: Node, pos: Vector2, type: String, count: int = 1) -> void:
	if parent == null or not is_instance_valid(parent) or not TEXTURES.has(type):
		return
	## Self-load keeps this working even before the global class cache exists.
	var drop: Sprite2D = (load("res://scripts/world/resource_drop.gd") as GDScript).new()
	drop.resource_type = type
	drop.amount = count
	drop.texture = TEXTURES[type]
	drop.position = pos
	drop.z_index = 5
	drop.name = "%sDrop" % type.capitalize()
	parent.add_child(drop)
	## Pop-out hop so drops from the same source spread visibly.
	var land := pos + Vector2(randf_range(-26.0, 26.0), randf_range(6.0, 22.0))
	var tw := drop.create_tween()
	tw.tween_property(drop, "position", land + Vector2(0, -18), 0.16)
	tw.tween_property(drop, "position", land, 0.14)


func _ready() -> void:
	add_to_group("resource_drops")
	scale = Vector2(0.75, 0.75)


func _physics_process(delta: float) -> void:
	if _settle_time > 0.0:
		_settle_time -= delta
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > MAGNET_RADIUS:
		return
	global_position = global_position.move_toward(player.global_position, MAGNET_SPEED * delta)
	if dist <= COLLECT_RADIUS:
		if player.has_method("add_resource"):
			player.add_resource(resource_type, amount)
		queue_free()
