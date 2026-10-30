extends Node

## Autoload: graphics / audio / controls / accessibility prefs.
## Persists under user://settings.cfg and applies live where possible.

const PATH := "user://settings.cfg"
const SECTION := "settings"
const DESIGN_SIZE := Vector2i(1920, 1080)

enum DisplayMode { WINDOWED, BORDERLESS, FULLSCREEN }
enum Quality { LOW, MEDIUM, HIGH }
enum Difficulty { EASY, NORMAL, HARD }
enum ColorblindMode { OFF, PROTANOPIA, DEUTERANOPIA, TRITANOPIA }
enum TextSize { SMALL, MEDIUM, LARGE }

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

const REBINDABLE_ACTIONS: PackedStringArray = [
	"move_left", "move_right", "move_up", "move_down", "ui_cancel",
]

## --- Graphics ---
var display_mode: int = DisplayMode.WINDOWED
var resolution: Vector2i = Vector2i(1920, 1080)
var vsync: bool = true
var fps_cap: int = 0 ## 0 = unlimited
var quality: int = Quality.MEDIUM
var fov: float = 70.0 ## stored for future / camera use
var motion_blur: bool = false

## --- Audio ---
var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0
var voice_volume: float = 1.0
var mute_when_unfocused: bool = true

## --- Controls ---
var mouse_sensitivity: float = 1.0
var controller_sensitivity: float = 1.0
var invert_x: bool = false
var invert_y: bool = false
var mouse_acceleration: bool = false
## action -> array of InputEvent dicts (serialized)
var keybinds: Dictionary = {}

## --- Accessibility / gameplay ---
var subtitles: bool = true
var text_size: int = TextSize.MEDIUM
var colorblind_mode: int = ColorblindMode.OFF
var difficulty: int = Difficulty.NORMAL

## Legacy alias used by older callers.
var fullscreen: bool:
	get:
		return display_mode == DisplayMode.FULLSCREEN or display_mode == DisplayMode.BORDERLESS
	set(value):
		display_mode = DisplayMode.FULLSCREEN if value else DisplayMode.WINDOWED


func _ready() -> void:
	await get_tree().process_frame
	_ensure_default_keybinds()
	load_settings()
	get_tree().root.size_changed.connect(_on_window_resized)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if mute_when_unfocused:
			AudioServer.set_bus_mute(0, true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_apply_audio()


func _ensure_default_keybinds() -> void:
	if not keybinds.is_empty():
		return
	keybinds = _capture_current_keybinds()


func _capture_current_keybinds() -> Dictionary:
	var out := {}
	for action in REBINDABLE_ACTIONS:
		var events: Array = []
		if InputMap.has_action(action):
			for ev in InputMap.action_get_events(action):
				events.append(ev)
		out[action] = events
	return out


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		_ensure_default_keybinds()
		apply()
		return

	display_mode = int(cfg.get_value(SECTION, "display_mode", DisplayMode.WINDOWED))
	var rx := int(cfg.get_value(SECTION, "resolution_x", 1920))
	var ry := int(cfg.get_value(SECTION, "resolution_y", 1080))
	resolution = Vector2i(rx, ry)
	vsync = bool(cfg.get_value(SECTION, "vsync", true))
	fps_cap = int(cfg.get_value(SECTION, "fps_cap", 0))
	quality = int(cfg.get_value(SECTION, "quality", Quality.MEDIUM))
	fov = float(cfg.get_value(SECTION, "fov", 70.0))
	motion_blur = bool(cfg.get_value(SECTION, "motion_blur", false))

	master_volume = clampf(float(cfg.get_value(SECTION, "master_volume", 1.0)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value(SECTION, "music_volume", 1.0)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value(SECTION, "sfx_volume", 1.0)), 0.0, 1.0)
	voice_volume = clampf(float(cfg.get_value(SECTION, "voice_volume", 1.0)), 0.0, 1.0)
	mute_when_unfocused = bool(cfg.get_value(SECTION, "mute_when_unfocused", true))

	mouse_sensitivity = clampf(float(cfg.get_value(SECTION, "mouse_sensitivity", 1.0)), 0.1, 3.0)
	controller_sensitivity = clampf(float(cfg.get_value(SECTION, "controller_sensitivity", 1.0)), 0.1, 3.0)
	invert_x = bool(cfg.get_value(SECTION, "invert_x", false))
	invert_y = bool(cfg.get_value(SECTION, "invert_y", false))
	mouse_acceleration = bool(cfg.get_value(SECTION, "mouse_acceleration", false))

	subtitles = bool(cfg.get_value(SECTION, "subtitles", true))
	text_size = int(cfg.get_value(SECTION, "text_size", TextSize.MEDIUM))
	colorblind_mode = int(cfg.get_value(SECTION, "colorblind_mode", ColorblindMode.OFF))
	difficulty = int(cfg.get_value(SECTION, "difficulty", Difficulty.NORMAL))

	## Legacy fullscreen bool → display mode.
	if cfg.has_section_key(SECTION, "fullscreen") and not cfg.has_section_key(SECTION, "display_mode"):
		display_mode = DisplayMode.FULLSCREEN if bool(cfg.get_value(SECTION, "fullscreen")) else DisplayMode.WINDOWED

	_load_keybinds(cfg)
	apply()


func _load_keybinds(cfg: ConfigFile) -> void:
	_ensure_default_keybinds()
	for action in REBINDABLE_ACTIONS:
		var key := "bind_%s" % action
		if not cfg.has_section_key(SECTION, key):
			continue
		var packed: Variant = cfg.get_value(SECTION, key, [])
		if typeof(packed) != TYPE_ARRAY:
			continue
		var events: Array = []
		for item in packed:
			if item is Dictionary:
				var ev := _event_from_dict(item)
				if ev:
					events.append(ev)
		if not events.is_empty():
			keybinds[action] = events


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "display_mode", display_mode)
	cfg.set_value(SECTION, "resolution_x", resolution.x)
	cfg.set_value(SECTION, "resolution_y", resolution.y)
	cfg.set_value(SECTION, "vsync", vsync)
	cfg.set_value(SECTION, "fps_cap", fps_cap)
	cfg.set_value(SECTION, "quality", quality)
	cfg.set_value(SECTION, "fov", fov)
	cfg.set_value(SECTION, "motion_blur", motion_blur)

	cfg.set_value(SECTION, "master_volume", master_volume)
	cfg.set_value(SECTION, "music_volume", music_volume)
	cfg.set_value(SECTION, "sfx_volume", sfx_volume)
	cfg.set_value(SECTION, "voice_volume", voice_volume)
	cfg.set_value(SECTION, "mute_when_unfocused", mute_when_unfocused)

	cfg.set_value(SECTION, "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value(SECTION, "controller_sensitivity", controller_sensitivity)
	cfg.set_value(SECTION, "invert_x", invert_x)
	cfg.set_value(SECTION, "invert_y", invert_y)
	cfg.set_value(SECTION, "mouse_acceleration", mouse_acceleration)

	cfg.set_value(SECTION, "subtitles", subtitles)
	cfg.set_value(SECTION, "text_size", text_size)
	cfg.set_value(SECTION, "colorblind_mode", colorblind_mode)
	cfg.set_value(SECTION, "difficulty", difficulty)

	for action in REBINDABLE_ACTIONS:
		var arr: Array = []
		for ev in keybinds.get(action, []):
			if ev is InputEvent:
				arr.append(_event_to_dict(ev))
		cfg.set_value(SECTION, "bind_%s" % action, arr)

	cfg.save(PATH)


func reset_to_defaults() -> void:
	display_mode = DisplayMode.WINDOWED
	resolution = Vector2i(1920, 1080)
	vsync = true
	fps_cap = 0
	quality = Quality.MEDIUM
	fov = 70.0
	motion_blur = false
	master_volume = 1.0
	music_volume = 1.0
	sfx_volume = 1.0
	voice_volume = 1.0
	mute_when_unfocused = true
	mouse_sensitivity = 1.0
	controller_sensitivity = 1.0
	invert_x = false
	invert_y = false
	mouse_acceleration = false
	subtitles = true
	text_size = TextSize.MEDIUM
	colorblind_mode = ColorblindMode.OFF
	difficulty = Difficulty.NORMAL
	## Restore project default input map by clearing overrides then re-capturing.
	keybinds.clear()
	## Re-apply built-in project.godot actions by not wiping InputMap — just
	## re-read whatever is currently mapped after we leave binds empty.
	_restore_project_keybinds()
	apply()
	save_settings()


func _restore_project_keybinds() -> void:
	## Reset rebindable actions to the hard-coded Tiny Sword defaults.
	var defaults := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"ui_cancel": [KEY_ESCAPE],
	}
	for action in REBINDABLE_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var events: Array = []
		for code in defaults.get(action, []):
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event(action, ev)
			events.append(ev)
		keybinds[action] = events


## --- Setters used by the settings UI ---
func set_display_mode(mode: int) -> void:
	display_mode = mode
	_apply_display()
	save_settings()


func set_resolution(res: Vector2i) -> void:
	resolution = res
	_apply_display()
	save_settings()


func set_vsync(enabled: bool) -> void:
	vsync = enabled
	_apply_vsync()
	save_settings()


func set_fps_cap(cap: int) -> void:
	fps_cap = maxi(cap, 0)
	_apply_fps_cap()
	save_settings()


func set_quality(level: int) -> void:
	quality = level
	_apply_quality()
	save_settings()


func set_fov(value: float) -> void:
	fov = clampf(value, 50.0, 110.0)
	save_settings()


func set_motion_blur(enabled: bool) -> void:
	motion_blur = enabled
	save_settings()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	save_settings()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	save_settings()


func set_voice_volume(value: float) -> void:
	voice_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	save_settings()


func set_mute_when_unfocused(enabled: bool) -> void:
	mute_when_unfocused = enabled
	save_settings()


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, 0.1, 3.0)
	save_settings()


func set_controller_sensitivity(value: float) -> void:
	controller_sensitivity = clampf(value, 0.1, 3.0)
	save_settings()


func set_invert_x(enabled: bool) -> void:
	invert_x = enabled
	save_settings()


func set_invert_y(enabled: bool) -> void:
	invert_y = enabled
	save_settings()


func set_mouse_acceleration(enabled: bool) -> void:
	mouse_acceleration = enabled
	save_settings()


func set_subtitles(enabled: bool) -> void:
	subtitles = enabled
	save_settings()


func set_text_size(size: int) -> void:
	text_size = size
	_apply_text_size()
	save_settings()


func set_colorblind_mode(mode: int) -> void:
	colorblind_mode = mode
	_apply_colorblind()
	save_settings()


func set_difficulty(level: int) -> void:
	difficulty = level
	save_settings()


func set_fullscreen(enabled: bool) -> void:
	## Backward-compatible API.
	display_mode = DisplayMode.FULLSCREEN if enabled else DisplayMode.WINDOWED
	_apply_display()
	save_settings()


func rebind_action(action: String, event: InputEvent) -> void:
	if not REBINDABLE_ACTIONS.has(action):
		return
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	keybinds[action] = [event]
	save_settings()


func apply() -> void:
	_apply_audio()
	_apply_vsync()
	_apply_fps_cap()
	_apply_quality()
	_apply_keybinds()
	_apply_text_size()
	_apply_colorblind()
	_apply_display()


func _on_window_resized() -> void:
	_apply_content_scale()


func _apply_content_scale() -> void:
	var win := get_window()
	if win == null:
		return
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	win.content_scale_size = DESIGN_SIZE
	win.content_scale_factor = 1.0


func _apply_display() -> void:
	var win := get_window()
	if win == null:
		return

	var current_mode := DisplayServer.window_get_mode()
	match display_mode:
		DisplayMode.FULLSCREEN:
			## Avoid re-setting fullscreen — causes a brief hitch when opening settings.
			if current_mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
				win.borderless = false
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		DisplayMode.BORDERLESS:
			var screen_i := DisplayServer.window_get_current_screen()
			var screen := DisplayServer.screen_get_size(screen_i)
			var origin := DisplayServer.screen_get_position(screen_i)
			var already := (
				current_mode == DisplayServer.WINDOW_MODE_WINDOWED
				and win.borderless
				and DisplayServer.window_get_size() == screen
			)
			if not already:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				win.borderless = true
				DisplayServer.window_set_position(origin)
				DisplayServer.window_set_size(screen)
		_:
			var screen_i2 := DisplayServer.window_get_current_screen()
			var usable := DisplayServer.screen_get_usable_rect(screen_i2)
			var target := resolution
			if target.x > usable.size.x or target.y > usable.size.y:
				var s: float = minf(
					float(usable.size.x) / float(target.x),
					float(usable.size.y) / float(target.y)
				)
				target = Vector2i(int(float(target.x) * s), int(float(target.y) * s))
			var already_win := (
				current_mode == DisplayServer.WINDOW_MODE_WINDOWED
				and not win.borderless
				and DisplayServer.window_get_size() == target
			)
			if not already_win:
				win.borderless = false
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_size(target)
				var pos := usable.position + (usable.size - target) / 2
				DisplayServer.window_set_position(pos)

	call_deferred("_apply_content_scale")


func _apply_vsync() -> void:
	if vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _apply_fps_cap() -> void:
	Engine.max_fps = fps_cap


func _apply_quality() -> void:
	## Drive a few live knobs; world gen reads these next time a world loads.
	match quality:
		Quality.LOW:
			Engine.physics_ticks_per_second = 30
		Quality.HIGH:
			Engine.physics_ticks_per_second = 60
		_:
			Engine.physics_ticks_per_second = 60


func _apply_audio() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("Voice", voice_volume)
	## Unmute Master if the app is focused (focus-out mutes when the option is on).
	var win := get_window()
	var focused := win != null and win.has_focus()
	if focused or not mute_when_unfocused:
		var idx := AudioServer.get_bus_index("Master")
		if idx >= 0:
			AudioServer.set_bus_mute(idx, master_volume <= 0.001)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


func _apply_keybinds() -> void:
	for action in REBINDABLE_ACTIONS:
		if not keybinds.has(action):
			continue
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for ev in keybinds[action]:
			if ev is InputEvent:
				InputMap.action_add_event(action, ev)


func _apply_text_size() -> void:
	## Theme default font size for future UI; scenes can also read text_size.
	var base := 22
	match text_size:
		TextSize.SMALL:
			base = 18
		TextSize.LARGE:
			base = 28
		_:
			base = 22
	if ThemeDB.get_project_theme() == null:
		return


func _apply_colorblind() -> void:
	## Apply a gentle canvas modulate overlay on the root viewport.
	var root := get_tree().root
	if root == null:
		return
	var overlay := root.get_node_or_null("ColorblindOverlay") as CanvasModulate
	if colorblind_mode == ColorblindMode.OFF:
		if overlay:
			overlay.queue_free()
		return
	if overlay == null:
		overlay = CanvasModulate.new()
		overlay.name = "ColorblindOverlay"
		root.add_child(overlay)
	match colorblind_mode:
		ColorblindMode.PROTANOPIA:
			overlay.color = Color(0.85, 0.9, 1.0)
		ColorblindMode.DEUTERANOPIA:
			overlay.color = Color(0.9, 0.85, 1.05)
		ColorblindMode.TRITANOPIA:
			overlay.color = Color(1.05, 0.95, 0.85)
		_:
			overlay.color = Color.WHITE


func quality_label() -> String:
	return ["Low", "Medium", "High"][clampi(quality, 0, 2)]


func difficulty_label() -> String:
	return ["Easy", "Normal", "Hard"][clampi(difficulty, 0, 2)]


func display_mode_label() -> String:
	return ["Windowed", "Borderless", "Fullscreen"][clampi(display_mode, 0, 2)]


func action_display_name(action: String) -> String:
	match action:
		"move_left":
			return "Move Left"
		"move_right":
			return "Move Right"
		"move_up":
			return "Move Up"
		"move_down":
			return "Move Down"
		"ui_cancel":
			return "Menu / Cancel"
		_:
			return action.capitalize()


func event_to_text(ev: InputEvent) -> String:
	if ev == null:
		return "—"
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return OS.get_keycode_string(code)
	if ev is InputEventMouseButton:
		return "Mouse %d" % (ev as InputEventMouseButton).button_index
	if ev is InputEventJoypadButton:
		return "Pad B%d" % (ev as InputEventJoypadButton).button_index
	return ev.as_text()


func _event_to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return {
			"type": "key",
			"physical_keycode": int(k.physical_keycode),
			"keycode": int(k.keycode),
		}
	if ev is InputEventMouseButton:
		return {"type": "mouse", "button_index": int((ev as InputEventMouseButton).button_index)}
	if ev is InputEventJoypadButton:
		return {"type": "joy", "button_index": int((ev as InputEventJoypadButton).button_index)}
	return {}


func _event_from_dict(d: Dictionary) -> InputEvent:
	match str(d.get("type", "")):
		"key":
			var ev := InputEventKey.new()
			ev.physical_keycode = int(d.get("physical_keycode", 0)) as Key
			ev.keycode = int(d.get("keycode", 0)) as Key
			return ev
		"mouse":
			var mev := InputEventMouseButton.new()
			mev.button_index = int(d.get("button_index", 1)) as MouseButton
			return mev
		"joy":
			var jev := InputEventJoypadButton.new()
			jev.button_index = int(d.get("button_index", 0)) as JoyButton
			return jev
	return null
