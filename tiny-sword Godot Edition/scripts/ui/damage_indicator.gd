class_name DamageIndicator
extends Label

## Lightweight world-space floating combat text.

static func spawn(parent: Node, world_pos: Vector2, amount: float, tint: Color = Color.WHITE) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var indicator := DamageIndicator.new()
	indicator.text = "-%d" % int(round(amount))
	indicator.position = world_pos
	indicator.z_index = 100
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indicator.add_theme_font_size_override("font_size", 26)
	indicator.add_theme_color_override("font_color", tint)
	indicator.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.04, 0.9))
	indicator.add_theme_constant_override("outline_size", 6)
	parent.add_child(indicator)
	var drift := Vector2(randf_range(-16.0, 16.0), -42.0)
	var tween := indicator.create_tween().set_parallel()
	tween.tween_property(indicator, "position", indicator.position + drift, 0.55)
	tween.tween_property(indicator, "modulate:a", 0.0, 0.55)
	tween.chain().tween_callback(indicator.queue_free)
