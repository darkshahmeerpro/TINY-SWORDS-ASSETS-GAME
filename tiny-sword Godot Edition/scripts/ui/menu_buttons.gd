extends Node

## Wires Play / Settings / Exit / world slots without changing their layout.

@export_file("*.tscn") var battle_scene_path: String = "res://scenes/game/battle.tscn"
@export_file("*.tscn") var settings_scene_path: String = "res://scenes/ui/settings.tscn"
@export var click_scale: float = 0.92
@export var click_duration: float = 0.08

const WORLD_ROWS := ["New_world", "New_world2", "New_world3"]
const WORLD_SCENE_PATH := "res://scenes/game/empty_world.tscn"
const SETTINGS_LAYER_NAME := "SettingsOverlayLayer"

var _settings_panel: CanvasItem
var _play_menu: Node
var _menu_root: Node
var _settings_layer: CanvasLayer
var _settings_menu: Control


func _ready() -> void:
	var ui := get_parent()
	if ui == null:
		return

	_menu_root = ui.get_parent()
	if _menu_root:
		_play_menu = _menu_root.get_node_or_null("Play_menu")
		## Keep legacy Settings_menu TileMap hidden; real settings is an overlay.
		_settings_panel = _menu_root.get_node_or_null("Settings_menu") as CanvasItem
		if _settings_panel:
			_settings_panel.visible = false

	var play_btn := ui.get_node_or_null("Play_button") as BaseButton
	var settings_btn := ui.get_node_or_null("Settings_button") as BaseButton
	var exit_btn := ui.get_node_or_null("Exit_button") as BaseButton

	if play_btn:
		_wire_button(play_btn, _on_play_pressed)
	if settings_btn:
		_wire_button(settings_btn, _on_settings_pressed)
	if exit_btn:
		_wire_button(exit_btn, _on_exit_pressed)

	if _play_menu:
		var exit_bg := _play_menu.get_node_or_null("Exit_background") as BaseButton
		if exit_bg == null:
			exit_bg = _play_menu.get_node_or_null("Exit_button/Exit_button") as BaseButton
		if exit_bg == null:
			exit_bg = _play_menu.get_node_or_null("Exit_button") as BaseButton
		if exit_bg:
			# No scale punch — this is a dismiss / back hitbox.
			if not exit_bg.pressed.is_connected(_on_play_menu_back):
				exit_bg.pressed.connect(_on_play_menu_back)
			_make_click_through_label(exit_bg)

		_refresh_world_slots()
		for i in WORLD_ROWS.size():
			var row := _play_menu.get_node_or_null(WORLD_ROWS[i]) as Control
			if row == null:
				continue
			var world_btn := row.get_node_or_null("Button") as BaseButton
			if world_btn:
				_wire_press_effect(world_btn, row)
				if not world_btn.pressed.is_connected(_on_world_slot_pressed.bind(i)):
					world_btn.pressed.connect(_on_world_slot_pressed.bind(i))


func _refresh_world_slots() -> void:
	if _play_menu == null:
		return
	for i in WORLD_ROWS.size():
		var row := _play_menu.get_node_or_null(WORLD_ROWS[i]) as Label
		if row == null:
			continue
		row.text = "World %d" % (i + 1)
		var hammer := row.get_node_or_null("Hammer_icon") as CanvasItem
		if hammer:
			hammer.visible = false


func _on_world_slot_pressed(slot_index: int) -> void:
	EmptyWorldScene.launch_world_name = "World %d" % (slot_index + 1)
	EmptyWorldScene.launch_seed = randi()
	EmptyWorldScene.pending_staged_build = true
	get_tree().change_scene_to_file(WORLD_SCENE_PATH)


func _wire_button(btn: BaseButton, action: Callable) -> void:
	_wire_press_effect(btn, btn)
	if not btn.pressed.is_connected(action):
		btn.pressed.connect(action)


func _wire_press_effect(btn: BaseButton, visual: Control) -> void:
	_make_click_through_label(btn)
	call_deferred("_center_pivot", visual)
	if not visual.resized.is_connected(_on_visual_resized.bind(visual)):
		visual.resized.connect(_on_visual_resized.bind(visual))
	if not btn.button_down.is_connected(_on_press_down.bind(visual)):
		btn.button_down.connect(_on_press_down.bind(visual))
	if not btn.button_up.is_connected(_on_press_up.bind(visual)):
		btn.button_up.connect(_on_press_up.bind(visual))


func _center_pivot(target: Control) -> void:
	if is_instance_valid(target):
		target.pivot_offset = target.size * 0.5


func _on_visual_resized(target: Control) -> void:
	target.pivot_offset = target.size * 0.5


func _on_btn_resized(btn: BaseButton) -> void:
	btn.pivot_offset = btn.size * 0.5


func _make_click_through_label(btn: BaseButton) -> void:
	for child in btn.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_press_down(visual: Control) -> void:
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(visual, "scale", Vector2(click_scale, click_scale), click_duration)


func _on_press_up(visual: Control) -> void:
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(visual, "scale", Vector2.ONE, click_duration)


func _on_button_down(btn: BaseButton) -> void:
	_on_press_down(btn)


func _on_button_up(btn: BaseButton) -> void:
	_on_press_up(btn)


func _on_play_pressed() -> void:
	if _play_menu and _play_menu.has_method("fade_in"):
		_play_menu.fade_in()
		return
	get_tree().change_scene_to_file(battle_scene_path)


func _on_play_menu_back() -> void:
	if _play_menu and _play_menu.has_method("fade_out"):
		_play_menu.fade_out()


func _on_settings_pressed() -> void:
	## Overlay fade — no scene change (avoids fullscreen stutter).
	if _settings_menu != null and is_instance_valid(_settings_menu):
		if _settings_menu.has_method("fade_in"):
			_settings_menu.fade_in()
		return

	if _menu_root == null:
		get_tree().change_scene_to_file(settings_scene_path)
		return

	var packed := load(settings_scene_path) as PackedScene
	if packed == null:
		return

	_settings_layer = _menu_root.get_node_or_null(SETTINGS_LAYER_NAME) as CanvasLayer
	if _settings_layer == null:
		_settings_layer = CanvasLayer.new()
		_settings_layer.name = SETTINGS_LAYER_NAME
		_settings_layer.layer = 100
		_menu_root.add_child(_settings_layer)

	_settings_menu = packed.instantiate() as Control
	if _settings_menu == null:
		return
	if _settings_menu.has_method("prepare_as_overlay"):
		_settings_menu.prepare_as_overlay()
	_settings_layer.add_child(_settings_menu)
	if _settings_menu.has_signal("closed"):
		_settings_menu.closed.connect(_on_settings_closed)
	if _settings_menu.has_method("fade_in"):
		_settings_menu.fade_in()


func _on_settings_closed() -> void:
	_settings_menu = null
	if _settings_layer != null and is_instance_valid(_settings_layer):
		var layer := _settings_layer
		_settings_layer = null
		layer.queue_free()


func _on_exit_pressed() -> void:
	get_tree().quit()
