extends Control

## In-game HUD — tile chrome + live minimap (no top-left resource strip).

signal menu_requested
signal settings_requested
signal resume_requested

const MENU_SCENE := "res://tiny_swords_logo.tscn"
const SETTINGS_SCENE := "res://scenes/ui/settings.tscn"

const MINIMAP_PX := 128
const MINIMAP_RADIUS_CELLS := 28
const MINIMAP_UPDATE_SEC := 0.25

@onready var _world_title: Label = get_node_or_null("%WorldTitle") as Label
@onready var _seed_label: Label = get_node_or_null("%SeedLabel") as Label
@onready var _hint_label: Label = get_node_or_null("%HintLabel") as Label
@onready var _info_label: Label = get_node_or_null("%InfoLabel") as Label
@onready var _pause_panel: Control = get_node_or_null("%PausePanel") as Control
@onready var _loading: Control = get_node_or_null("%LoadingOverlay") as Control
@onready var _loading_status: Label = get_node_or_null("%LoadingStatus") as Label
@onready var _loading_fill_clip: Control = get_node_or_null("%LoadingFillClip") as Control
@onready var _loading_percent: Label = get_node_or_null("%LoadingPercent") as Label
@onready var _loading_sword: Control = get_node_or_null("%LoadingSword") as Control
@onready var _loading_panel: Control = get_node_or_null("%LoadingPanel") as Control
@onready var _loading_backdrop: Node2D = get_node_or_null("%MenuWorldBackdrop") as Node2D
@onready var _spark_a: Control = get_node_or_null("%SparkA") as Control
@onready var _spark_b: Control = get_node_or_null("%SparkB") as Control
@onready var _spark_c: Control = get_node_or_null("%SparkC") as Control
@onready var _minimap_view: TextureRect = get_node_or_null("%MinimapView") as TextureRect
@onready var _player_marker: Control = get_node_or_null("%PlayerMarker") as Control
@onready var _health_fill_clip: Control = get_node_or_null("%HealthFillClip") as Control
@onready var _health_label: Label = get_node_or_null("%HealthLabel") as Label

var _world: Node
var _player: Node2D
var _minimap_img: Image
var _minimap_tex: ImageTexture
var _minimap_timer: float = 0.0
var _marker_pulse: float = 0.0
var _max_hp: float = 100.0
var _hp: float = 100.0
var _loading_anim: float = 0.0
var _loading_progress: float = 0.0
var _loading_display: float = 0.0
var _loading_closing: bool = false

const HEALTH_FILL_MAX_WIDTH := 224.0
const HEALTH_FILL_LEFT := 48.0
const HEALTH_FILL_TOP := 18.0
const HEALTH_FILL_BOTTOM := 46.0
const LOADING_FILL_MAX_WIDTH := 224.0
const LOADING_FILL_LEFT := 144.0
const LOADING_FILL_TOP := 238.0
const LOADING_FILL_BOTTOM := 266.0
const LOADING_MIN_SEC := 3.2
const LOADING_LERP_SPEED := 28.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = not (get_parent() is CanvasLayer)
	z_index = 100
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _pause_panel:
		_pause_panel.visible = false
	if _loading:
		_loading.visible = false
	_init_minimap()
	_wire_buttons()
	set_health(100.0, 100.0)
	set_info("Explore the world")


func _process(delta: float) -> void:
	_marker_pulse += delta * 4.0
	if _loading and _loading.visible:
		_update_loading_animation(delta)
	if _player_marker and _player_marker.visible:
		var s := 1.0 + 0.12 * sin(_marker_pulse)
		_player_marker.scale = Vector2(s, s)
	if _world == null or _player == null or not is_instance_valid(_player):
		return
	if _player_marker:
		_player_marker.rotation = _player.rotation
	_minimap_timer -= delta
	if _minimap_timer <= 0.0:
		if _world.has_method("is_streaming_busy") and _world.is_streaming_busy():
			_minimap_timer = 0.35
			return
		_minimap_timer = MINIMAP_UPDATE_SEC
		_redraw_minimap()


func bind_world(world: Node, player: Node2D) -> void:
	_world = world
	_player = player
	_minimap_timer = 0.0
	_redraw_minimap()
	if player != null and ("hp" in player) and ("max_hp" in player):
		set_health(float(player.get("hp")), float(player.get("max_hp")))
		if player.has_signal("health_changed") and not player.health_changed.is_connected(set_health):
			player.health_changed.connect(set_health)


func set_health(current: float, maximum: float = -1.0) -> void:
	var took_damage := current < _hp
	if maximum > 0.0:
		_max_hp = maximum
	_hp = clampf(current, 0.0, _max_hp)
	if _health_fill_clip:
		var ratio := 0.0 if _max_hp <= 0.0 else (_hp / _max_hp)
		_health_fill_clip.offset_left = HEALTH_FILL_LEFT
		_health_fill_clip.offset_top = HEALTH_FILL_TOP
		_health_fill_clip.offset_bottom = HEALTH_FILL_BOTTOM
		_health_fill_clip.offset_right = HEALTH_FILL_LEFT + HEALTH_FILL_MAX_WIDTH * ratio
	if _health_label:
		_health_label.text = "%d / %d" % [int(round(_hp)), int(round(_max_hp))]
	if took_damage:
		modulate = Color(1.0, 0.72, 0.72)
		var tw := create_tween()
		tw.tween_property(self, "modulate", Color.WHITE, 0.18)


func _init_minimap() -> void:
	_minimap_img = Image.create(MINIMAP_PX, MINIMAP_PX, false, Image.FORMAT_RGBA8)
	_minimap_img.fill(Color(0, 0, 0, 0))
	_minimap_tex = ImageTexture.create_from_image(_minimap_img)
	if _minimap_view:
		_minimap_view.texture = _minimap_tex
		_minimap_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _redraw_minimap() -> void:
	if _minimap_img == null or _world == null or _player == null:
		return
	if not _world.has_method("sample_height") or not _world.has_method("global_to_cell"):
		return
	var center: Vector2i = _world.global_to_cell(_player.global_position)
	var half := MINIMAP_PX * 0.5
	var span := float(MINIMAP_RADIUS_CELLS * 2)
	var radius := half - 1.0
	## Cache a padded height grid so coast/cliff checks stay cheap.
	var grid_n := MINIMAP_RADIUS_CELLS * 2 + 3
	var origin := Vector2i(center.x - MINIMAP_RADIUS_CELLS - 1, center.y - MINIMAP_RADIUS_CELLS - 1)
	var heights: PackedInt32Array = PackedInt32Array()
	heights.resize(grid_n * grid_n)
	for gy in grid_n:
		for gx in grid_n:
			if _world.has_method("cached_height_at"):
				heights[gy * grid_n + gx] = int(_world.cached_height_at(Vector2i(origin.x + gx, origin.y + gy)))
			else:
				heights[gy * grid_n + gx] = int(_world.sample_height(origin.x + gx, origin.y + gy))
	for py in MINIMAP_PX:
		for px in MINIMAP_PX:
			var dx := float(px) - half + 0.5
			var dy := float(py) - half + 0.5
			var dist := sqrt(dx * dx + dy * dy)
			if dist > radius:
				_minimap_img.set_pixel(px, py, Color(0, 0, 0, 0))
				continue
			var cell_x := center.x + int(floor(dx * span / float(MINIMAP_PX)))
			var cell_y := center.y + int(floor(dy * span / float(MINIMAP_PX)))
			var lx := cell_x - origin.x
			var ly := cell_y - origin.y
			var h: int = heights[ly * grid_n + lx]
			var col := _terrain_color(h, cell_x, cell_y, heights, grid_n, lx, ly)
			## Soft circular fade — no opaque background outside the map.
			var edge := clampf((radius - dist) / 10.0, 0.0, 1.0)
			col.a = edge
			_minimap_img.set_pixel(px, py, col)
	_draw_ring(half - 0.5, half - 0.5, radius - 1.0, Color(0.95, 0.85, 0.55, 0.55))
	_minimap_tex.update(_minimap_img)


func _terrain_color(
	h: int,
	cell_x: int,
	cell_y: int,
	heights: PackedInt32Array,
	grid_n: int,
	lx: int,
	ly: int
) -> Color:
	var base: Color
	match h:
		-1:
			var deep := Color(0.14, 0.36, 0.68, 1.0)
			var shallow := Color(0.22, 0.52, 0.82, 1.0)
			base = deep if ((cell_x + cell_y) & 1) == 0 else shallow
			if _neighbor_ge(heights, grid_n, lx, ly, 0):
				base = Color(0.38, 0.72, 0.88, 1.0)
		0:
			var a := Color(0.36, 0.68, 0.24, 1.0)
			var b := Color(0.44, 0.74, 0.30, 1.0)
			base = a if ((cell_x * 3 + cell_y * 7) & 1) == 0 else b
			if _neighbor_eq(heights, grid_n, lx, ly, -1):
				base = Color(0.55, 0.72, 0.34, 1.0)
		1:
			base = Color(0.58, 0.76, 0.36, 1.0)
			if _height_at(heights, grid_n, lx, ly + 1) < 1:
				base = Color(0.52, 0.48, 0.38, 1.0)
		2:
			base = Color(0.78, 0.74, 0.58, 1.0)
			if _height_at(heights, grid_n, lx, ly + 1) < 2:
				base = Color(0.62, 0.56, 0.46, 1.0)
		_:
			base = Color(0.28, 0.28, 0.28, 1.0)
	return base


func _height_at(heights: PackedInt32Array, grid_n: int, lx: int, ly: int) -> int:
	if lx < 0 or ly < 0 or lx >= grid_n or ly >= grid_n:
		return 0
	return heights[ly * grid_n + lx]


func _neighbor_eq(heights: PackedInt32Array, grid_n: int, lx: int, ly: int, value: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _height_at(heights, grid_n, lx + d.x, ly + d.y) == value:
			return true
	return false


func _neighbor_ge(heights: PackedInt32Array, grid_n: int, lx: int, ly: int, value: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _height_at(heights, grid_n, lx + d.x, ly + d.y) >= value:
			return true
	return false


func _draw_ring(cx: float, cy: float, r: float, color: Color) -> void:
	var steps := int(TAU * r)
	for i in steps:
		var a := TAU * float(i) / float(steps)
		var px := int(round(cx + cos(a) * r))
		var py := int(round(cy + sin(a) * r))
		if px >= 0 and py >= 0 and px < MINIMAP_PX and py < MINIMAP_PX:
			var prev := _minimap_img.get_pixel(px, py)
			_minimap_img.set_pixel(px, py, prev.lerp(color, color.a))


func _wire_buttons() -> void:
	var pause_btn := get_node_or_null("%PauseButton") as BaseButton
	if pause_btn:
		pause_btn.pressed.connect(toggle_pause)
	var resume_btn := get_node_or_null("%ResumeButton") as BaseButton
	if resume_btn:
		resume_btn.pressed.connect(_on_resume)
	var settings_btn := get_node_or_null("%SettingsButton") as BaseButton
	if settings_btn:
		settings_btn.pressed.connect(_on_settings)
	var menu_btn := get_node_or_null("%MenuButton") as BaseButton
	if menu_btn:
		menu_btn.pressed.connect(_on_menu)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _loading and _loading.visible:
			return
		toggle_pause()
		get_viewport().set_input_as_handled()


func set_world_title(title: String) -> void:
	if _world_title:
		_world_title.text = title


func set_seed_text(seed_value: int) -> void:
	if _seed_label:
		_seed_label.text = "Seed: %d" % seed_value


func set_hint(text: String) -> void:
	if _hint_label:
		_hint_label.text = text


func set_info(text: String) -> void:
	if _info_label:
		_info_label.text = text


func show_loading(status: String = "Loading…") -> void:
	if _loading == null:
		return
	_loading.visible = true
	_loading.modulate = Color(1, 1, 1, 1)
	_loading_anim = 0.0
	_loading_progress = 0.0
	_loading_display = 0.0
	_loading_closing = false
	_set_loading_fill(0.0)
	if _loading_status:
		_loading_status.text = status
	if _loading_percent:
		_loading_percent.text = "0%"
	if _loading_panel:
		_loading_panel.scale = Vector2(0.92, 0.92)
		_loading_panel.modulate.a = 0.0


func set_loading_progress(phase_name: String, percent: float) -> void:
	if _loading == null or not _loading.visible:
		return
	if _loading_status:
		_loading_status.text = phase_name
	## Keep the bar from jumping; display value lerps in _process.
	_loading_progress = clampf(percent, 0.0, 100.0)


func hide_loading() -> void:
	if _loading == null or not _loading.visible:
		return
	_loading_closing = true
	_loading_progress = 100.0
	if _loading_status:
		_loading_status.text = "Ready"
	## Stay up until the smooth fill catches up and a minimum time has passed.
	while is_instance_valid(self) and _loading.visible and (
		_loading_display < 99.5 or _loading_anim < LOADING_MIN_SEC
	):
		await get_tree().process_frame
	if not is_instance_valid(_loading):
		return
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_loading, "modulate:a", 0.0, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if is_instance_valid(_loading):
		_loading.visible = false
		_loading.modulate.a = 1.0
	_loading_closing = false


func _set_loading_fill(ratio: float) -> void:
	if _loading_fill_clip == null:
		return
	var t := clampf(ratio, 0.0, 1.0)
	_loading_fill_clip.offset_left = LOADING_FILL_LEFT
	_loading_fill_clip.offset_top = LOADING_FILL_TOP
	_loading_fill_clip.offset_bottom = LOADING_FILL_BOTTOM
	_loading_fill_clip.offset_right = LOADING_FILL_LEFT + LOADING_FILL_MAX_WIDTH * t


func _update_loading_animation(delta: float) -> void:
	_loading_anim += delta
	var t := _loading_anim
	## Smooth progress fill (doesn't snap with each stage).
	var catch_up := LOADING_LERP_SPEED * delta
	if _loading_closing:
		catch_up *= 1.6
	_loading_display = move_toward(_loading_display, _loading_progress, catch_up)
	_set_loading_fill(_loading_display / 100.0)
	if _loading_percent:
		_loading_percent.text = "%d%%" % int(round(_loading_display))

	## Gentle pan/zoom on the menu world TileMap backdrop.
	if _loading_backdrop:
		_loading_backdrop.position = Vector2(
			-40.0 + sin(t * 0.22) * 28.0,
			-20.0 + cos(t * 0.18) * 18.0
		)
		var z := 1.08 + 0.025 * sin(t * 0.35)
		_loading_backdrop.scale = Vector2(z, z)

	if _loading_panel:
		var appear := clampf(t * 2.2, 0.0, 1.0)
		var pop := 0.92 + 0.08 * appear
		_loading_panel.scale = Vector2(pop, pop)
		_loading_panel.modulate.a = appear
		_loading_panel.rotation = sin(t * 1.4) * 0.012
	if _loading_sword:
		_loading_sword.position.y = 292.0 + sin(t * 3.0) * 6.0
		_loading_sword.rotation = sin(t * 2.2) * 0.08
	if _loading_status:
		_loading_status.modulate.a = 0.7 + 0.3 * (0.5 + 0.5 * sin(t * 4.0))
	_animate_spark(_spark_a, t, 0.18, 0.22, 1.1)
	_animate_spark(_spark_b, t + 1.7, 0.78, 0.38, 0.85)
	_animate_spark(_spark_c, t + 3.1, 0.55, 0.72, 1.35)


func _animate_spark(spark: Control, t: float, nx: float, ny: float, speed: float) -> void:
	if spark == null:
		return
	var vp := get_viewport_rect().size
	var bob := sin(t * speed) * 18.0
	var drift := cos(t * speed * 0.7) * 28.0
	spark.position = Vector2(vp.x * nx + drift, vp.y * ny + bob)
	spark.modulate.a = 0.35 + 0.55 * (0.5 + 0.5 * sin(t * speed * 2.0))
	var s := 0.8 + 0.5 * (0.5 + 0.5 * sin(t * speed * 1.6))
	spark.scale = Vector2(s, s)


func toggle_pause() -> void:
	if _pause_panel == null:
		return
	var now_paused := not _pause_panel.visible
	_pause_panel.visible = now_paused
	get_tree().paused = now_paused
	if not now_paused:
		resume_requested.emit()


func _on_resume() -> void:
	if _pause_panel:
		_pause_panel.visible = false
	get_tree().paused = false
	resume_requested.emit()


func _on_settings() -> void:
	settings_requested.emit()
	get_tree().paused = false
	if _pause_panel:
		_pause_panel.visible = false
	var settings := load(SETTINGS_SCENE) as PackedScene
	if settings == null:
		return
	var menu := settings.instantiate() as Control
	menu.name = "SettingsOverlay"
	menu.top_level = true
	menu.z_index = 100
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	if menu.has_method("prepare_as_overlay"):
		menu.prepare_as_overlay()
	if menu.has_method("fade_in"):
		menu.fade_in()
	if menu.has_signal("closed"):
		menu.closed.connect(func() -> void:
			if is_instance_valid(menu):
				menu.queue_free()
		)


func _on_menu() -> void:
	get_tree().paused = false
	menu_requested.emit()
	get_tree().change_scene_to_file(MENU_SCENE)
