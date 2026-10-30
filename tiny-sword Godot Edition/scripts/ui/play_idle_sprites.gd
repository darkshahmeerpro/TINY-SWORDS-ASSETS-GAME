extends Node2D

## Plays the idle animation on every AnimatedSprite2D under this node.

func _ready() -> void:
	call_deferred("_play_all_idles")


func _play_all_idles() -> void:
	_play_idle_recursive(self)


func _play_idle_recursive(node: Node) -> void:
	if node is AnimatedSprite2D:
		var sprite := node as AnimatedSprite2D
		# Sheep manage their own idle/eat loop.
		if sprite.get_script() != null and str(sprite.get_script().resource_path).ends_with("sheep_eat_ai.gd"):
			pass
		elif sprite.sprite_frames != null and sprite.sprite_frames.has_animation(&"idle"):
			sprite.play(&"idle")
	for child in node.get_children():
		_play_idle_recursive(child)
