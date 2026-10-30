extends TileMap

## Slides this UI TileMap and the Tiny Swords logo into place.

@export var logo_path: NodePath = ^"TinySwordsLogo"

@export var slide_duration: float = 0.85
@export var ui_delay: float = 0.12
## Logo starts this far off-screen, then slides to its editor position.
@export var logo_offset: Vector2 = Vector2(-900, 0)
@export var ui_offset: Vector2 = Vector2(-1100, 0)

@onready var _logo: Node2D = get_node_or_null(logo_path) as Node2D


func _ready() -> void:
	call_deferred("_play_slide_in")


func _play_slide_in() -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Slide this UI node; child logo rides along (avoids double-moving local+parent).
	var ui_rest := position
	position = ui_rest + ui_offset
	modulate = Color(1, 1, 1, 1)

	tween.tween_property(self, "position", ui_rest, slide_duration)
