extends TileMap

## Fades this Play_menu TileMap in/out on demand (not on scene ready).

@export var fade_duration: float = 0.45

var _tween: Tween
var _is_open: bool = false


func _ready() -> void:
	modulate.a = 0.0
	visible = false
	_set_interactive(false)


func is_open() -> bool:
	return _is_open


func slide_in() -> void:
	fade_in()


func slide_out() -> void:
	fade_out()


func fade_in() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	_set_interactive(true)
	_kill_tween()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "modulate:a", 1.0, fade_duration)


func fade_out() -> void:
	if not _is_open:
		return
	_is_open = false
	_kill_tween()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	_tween.finished.connect(_on_fade_out_finished)


func _on_fade_out_finished() -> void:
	if not _is_open:
		visible = false
		_set_interactive(false)


func _kill_tween() -> void:
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_tween = null


func _set_interactive(enabled: bool) -> void:
	for child in get_children():
		if child is Control:
			(child as Control).mouse_filter = (
				Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
			)
		if child is BaseButton:
			(child as BaseButton).disabled = not enabled
