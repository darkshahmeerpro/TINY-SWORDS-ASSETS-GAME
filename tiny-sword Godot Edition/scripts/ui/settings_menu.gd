extends Control

## Wires the TileMap settings UI. Opens as an overlay with fade (no scene swap).

signal closed

const MENU_SCENE := "res://tiny_swords_logo.tscn"
const FADE_DURATION := 0.4

const FPS_VALUES := [0, 30, 60, 120, 144]
const BIND_NODES := {
	"move_left": "BindMoveLeft",
	"move_right": "BindMoveRight",
	"move_up": "BindMoveUp",
	"move_down": "BindMoveDown",
	"ui_cancel": "BindCancel",
}

var _panel: Node2D
var _overlay: CanvasItem
var _dim: CanvasItem
var _tab_graphics: Button
var _tab_controls: Button
var _tab_access: Button
var _graphics_page: Control
var _controls_page: Control
var _access_page: Control
var _status: Label
var _down_bar: VScrollBar
var _waiting_action: String = ""
var _bind_buttons: Dictionary = {}
var _overlay_mode: bool = false
var _is_open: bool = false
var _tween: Tween
var _closing: bool = false
var _syncing_scroll: bool = false


func _ready() -> void:
	_bind_nodes()
	_populate_resolution_options()
	_load_values_into_ui()
	_connect_signals()
	_show_tab(0)
	_setup_down_bar()
	if _overlay_mode:
		## Opened via menu overlay — fade_in() is called by the host.
		return
	## Standalone scene entry.
	modulate.a = 0.0
	await get_tree().process_frame
	_fade_open()


func prepare_as_overlay() -> void:
	_overlay_mode = true
	modulate.a = 0.0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func fade_in() -> void:
	if _is_open:
		return
	_is_open = true
	_closing = false
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_open()


func fade_out() -> void:
	if _closing:
		return
	_closing = true
	_is_open = false
	_waiting_action = ""
	_kill_tween()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	_tween.finished.connect(_on_fade_out_finished)


func _fade_open() -> void:
	_kill_tween()
	if _panel:
		_panel.modulate.a = 1.0
	if _overlay:
		_overlay.modulate.a = 1.0
	modulate.a = 0.0
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "modulate:a", 1.0, FADE_DURATION)


func _on_fade_out_finished() -> void:
	if _is_open:
		return
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed.emit()
	if _overlay_mode:
		queue_free()
	_closing = false


func _kill_tween() -> void:
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_tween = null


func _bind_nodes() -> void:
	_panel = %Panel
	_overlay = get_node_or_null("%Overlay") as CanvasItem
	_dim = get_node_or_null("Dim") as CanvasItem
	_tab_graphics = %TabGraphics
	_tab_controls = %TabControls
	_tab_access = %TabAccessibility
	_graphics_page = %GraphicsPage
	_controls_page = %ControlsPage
	_access_page = %AccessibilityPage
	_status = %Status
	_down_bar = get_node_or_null("%DownBar") as VScrollBar

	for action in BIND_NODES:
		_bind_buttons[action] = get_node("%" + BIND_NODES[action]) as Button


func _populate_resolution_options() -> void:
	var opt: OptionButton = %Resolution
	opt.clear()
	for r in GameSettings.RESOLUTIONS:
		opt.add_item("%d × %d" % [r.x, r.y])


func _load_values_into_ui() -> void:
	## Sync from live GameSettings — do not reload/apply display (avoids fullscreen hitch).
	%DisplayMode.select(clampi(GameSettings.display_mode, 0, 2))

	var res_i := 0
	for i in GameSettings.RESOLUTIONS.size():
		if GameSettings.RESOLUTIONS[i] == GameSettings.resolution:
			res_i = i
			break
	%Resolution.select(res_i)

	%Vsync.button_pressed = GameSettings.vsync

	var fps_i := 0
	for i in FPS_VALUES.size():
		if FPS_VALUES[i] == GameSettings.fps_cap:
			fps_i = i
			break
	%FpsCap.select(fps_i)

	%Quality.select(clampi(GameSettings.quality, 0, 2))
	%Fov.value = GameSettings.fov
	%FovValue.text = "%d°" % int(round(GameSettings.fov))
	%MotionBlur.button_pressed = GameSettings.motion_blur

	%MouseSens.value = GameSettings.mouse_sensitivity * 100.0
	%MouseSensValue.text = "%d%%" % int(round(%MouseSens.value))
	%PadSens.value = GameSettings.controller_sensitivity * 100.0
	%PadSensValue.text = "%d%%" % int(round(%PadSens.value))
	%InvertX.button_pressed = GameSettings.invert_x
	%InvertY.button_pressed = GameSettings.invert_y
	%MouseAccel.button_pressed = GameSettings.mouse_acceleration

	%Subtitles.button_pressed = GameSettings.subtitles
	%TextSize.select(clampi(GameSettings.text_size, 0, 2))
	%Colorblind.select(clampi(GameSettings.colorblind_mode, 0, 3))
	%Difficulty.select(clampi(GameSettings.difficulty, 0, 2))

	_refresh_all_binds()


func _connect_signals() -> void:
	_tab_graphics.pressed.connect(_show_tab.bind(0))
	_tab_controls.pressed.connect(_show_tab.bind(1))
	_tab_access.pressed.connect(_show_tab.bind(2))

	%DisplayMode.item_selected.connect(func(i: int) -> void:
		GameSettings.set_display_mode(i)
		_flash("Display mode updated")
	)
	%Resolution.item_selected.connect(func(i: int) -> void:
		GameSettings.set_resolution(GameSettings.RESOLUTIONS[i])
		_flash("Resolution updated")
	)
	%Vsync.toggled.connect(func(on: bool) -> void:
		GameSettings.set_vsync(on)
	)
	%FpsCap.item_selected.connect(func(i: int) -> void:
		GameSettings.set_fps_cap(FPS_VALUES[i])
		_flash("FPS cap updated")
	)
	%Quality.item_selected.connect(func(i: int) -> void:
		GameSettings.set_quality(i)
		_flash("Quality updated")
	)
	%Fov.value_changed.connect(func(v: float) -> void:
		GameSettings.set_fov(v)
		%FovValue.text = "%d°" % int(round(v))
	)
	%MotionBlur.toggled.connect(func(on: bool) -> void:
		GameSettings.set_motion_blur(on)
	)

	%MouseSens.value_changed.connect(func(v: float) -> void:
		GameSettings.set_mouse_sensitivity(v / 100.0)
		%MouseSensValue.text = "%d%%" % int(round(v))
	)
	%PadSens.value_changed.connect(func(v: float) -> void:
		GameSettings.set_controller_sensitivity(v / 100.0)
		%PadSensValue.text = "%d%%" % int(round(v))
	)
	%InvertX.toggled.connect(func(on: bool) -> void:
		GameSettings.set_invert_x(on)
	)
	%InvertY.toggled.connect(func(on: bool) -> void:
		GameSettings.set_invert_y(on)
	)
	%MouseAccel.toggled.connect(func(on: bool) -> void:
		GameSettings.set_mouse_acceleration(on)
	)

	for action in _bind_buttons:
		_bind_buttons[action].pressed.connect(_on_rebind_pressed.bind(action))

	%Subtitles.toggled.connect(func(on: bool) -> void:
		GameSettings.set_subtitles(on)
	)
	%TextSize.item_selected.connect(func(i: int) -> void:
		GameSettings.set_text_size(i)
		_flash("Text size updated")
	)
	%Colorblind.item_selected.connect(func(i: int) -> void:
		GameSettings.set_colorblind_mode(i)
		_flash("Colorblind mode updated")
	)
	%Difficulty.item_selected.connect(func(i: int) -> void:
		GameSettings.set_difficulty(i)
		_flash("Difficulty updated")
	)

	%ResetButton.pressed.connect(_on_reset_pressed)
	%BackButton.pressed.connect(_on_back_pressed)


func _show_tab(index: int) -> void:
	_waiting_action = ""
	_graphics_page.visible = index == 0
	_controls_page.visible = index == 1
	_access_page.visible = index == 2
	_tab_graphics.modulate = Color.WHITE if index == 0 else Color(0.72, 0.76, 0.84, 1)
	_tab_controls.modulate = Color.WHITE if index == 1 else Color(0.72, 0.76, 0.84, 1)
	_tab_access.modulate = Color.WHITE if index == 2 else Color(0.72, 0.76, 0.84, 1)
	_refresh_all_binds()
	_sync_down_bar()


func _on_rebind_pressed(action: String) -> void:
	_waiting_action = action
	_status.text = "Waiting for input — %s" % GameSettings.action_display_name(action)
	_refresh_all_binds()


func _input(event: InputEvent) -> void:
	if _waiting_action.is_empty():
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_waiting_action = ""
			_status.text = "Rebind cancelled"
			_refresh_all_binds()
			get_viewport().set_input_as_handled()
			return
		GameSettings.rebind_action(_waiting_action, event)
		_flash("Bound %s" % GameSettings.action_display_name(_waiting_action))
		_waiting_action = ""
		_refresh_all_binds()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.is_pressed():
		GameSettings.rebind_action(_waiting_action, event)
		_flash("Bound %s" % GameSettings.action_display_name(_waiting_action))
		_waiting_action = ""
		_refresh_all_binds()
		get_viewport().set_input_as_handled()


func _refresh_all_binds() -> void:
	for action in _bind_buttons:
		var btn: Button = _bind_buttons[action]
		if btn == null:
			continue
		if _waiting_action == action:
			btn.text = "Press a key…"
			continue
		var events: Array = GameSettings.keybinds.get(action, [])
		if events.is_empty() and InputMap.has_action(action):
			events = InputMap.action_get_events(action)
		btn.text = GameSettings.event_to_text(events[0]) if not events.is_empty() else "—"


func _flash(msg: String) -> void:
	if _status:
		_status.text = msg


func _on_reset_pressed() -> void:
	GameSettings.reset_to_defaults()
	_waiting_action = ""
	_populate_resolution_options()
	_load_values_into_ui()
	_show_tab(0)
	_flash("Settings reset to default")


func _on_back_pressed() -> void:
	if _overlay_mode:
		fade_out()
		return
	## Standalone: fade, then return to menu.
	_kill_tween()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	_tween.finished.connect(func() -> void:
		get_tree().change_scene_to_file(MENU_SCENE)
	)


func _unhandled_input(event: InputEvent) -> void:
	if _waiting_action != "":
		return
	if _closing:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _setup_down_bar() -> void:
	if _down_bar == null:
		return
	_down_bar.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_down_bar.value_changed.connect(_on_down_bar_changed)
	for page in [_graphics_page, _controls_page, _access_page]:
		if page == null:
			continue
		var internal: VScrollBar = page.get_v_scroll_bar()
		if internal == null:
			continue
		internal.visible = false
		internal.custom_minimum_size.x = 0.0
		internal.value_changed.connect(func(v: float) -> void: _on_page_scroll_changed(page, v))
		page.resized.connect(_sync_down_bar)
		var list := page.get_node_or_null("List") as Control
		if list:
			list.resized.connect(_sync_down_bar)
	## Sliders use the hover cursor too.
	for slider_name in ["Fov", "MouseSens", "PadSens"]:
		var slider := get_node_or_null("%" + slider_name) as Control
		if slider:
			slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_sync_down_bar()


func _active_page() -> ScrollContainer:
	if _controls_page and _controls_page.visible:
		return _controls_page
	if _access_page and _access_page.visible:
		return _access_page
	return _graphics_page


func _sync_down_bar() -> void:
	if _down_bar == null:
		return
	## Hide on Accessibility tab.
	if _access_page and _access_page.visible:
		_down_bar.visible = false
		return
	var page := _active_page()
	if page == null:
		_down_bar.visible = false
		return
	var internal: VScrollBar = page.get_v_scroll_bar()
	if internal == null:
		_down_bar.visible = false
		return
	_syncing_scroll = true
	_down_bar.min_value = internal.min_value
	_down_bar.max_value = maxf(internal.max_value, internal.min_value)
	_down_bar.page = internal.page
	_down_bar.step = internal.step
	_down_bar.set_value_no_signal(internal.value)
	_down_bar.visible = true
	_syncing_scroll = false


func _on_down_bar_changed(v: float) -> void:
	if _syncing_scroll:
		return
	var page := _active_page()
	if page == null:
		return
	var internal: VScrollBar = page.get_v_scroll_bar()
	if internal:
		internal.value = v


func _on_page_scroll_changed(page: ScrollContainer, _v: float) -> void:
	if _syncing_scroll:
		return
	if page != _active_page():
		return
	_sync_down_bar()
