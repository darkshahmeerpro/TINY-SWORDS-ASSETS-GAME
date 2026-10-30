extends Node

## Custom Tiny Swords cursors for the whole project.
## Default = Cursor_01, button hover = Cursor_02, disabled button = Cursor_03.

const CURSOR_DEFAULT: Texture2D = preload("res://assets/ui_pack/UI Elements/Cursors/Cursor_01.png")
const CURSOR_HOVER: Texture2D = preload("res://assets/ui_pack/UI Elements/Cursors/Cursor_02.png")
const CURSOR_DISABLED: Texture2D = preload("res://assets/ui_pack/UI Elements/Cursors/Cursor_03.png")
## Tip of the pointer in the 64x64 art.
const HOTSPOT := Vector2(8, 8)

var _wired: Dictionary = {} # instance_id -> true


func _ready() -> void:
	Input.set_custom_mouse_cursor(CURSOR_DEFAULT, Input.CURSOR_ARROW, HOTSPOT)
	Input.set_custom_mouse_cursor(CURSOR_HOVER, Input.CURSOR_POINTING_HAND, HOTSPOT)
	Input.set_custom_mouse_cursor(CURSOR_DISABLED, Input.CURSOR_FORBIDDEN, HOTSPOT)
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_scan_tree", get_tree().root)


func _process(_delta: float) -> void:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered is BaseButton:
		_refresh_button_cursor(hovered as BaseButton)
	elif hovered is Slider or hovered is ScrollBar:
		hovered.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _on_node_added(node: Node) -> void:
	_wire_button(node)
	_wire_drag_control(node)


func _scan_tree(node: Node) -> void:
	_wire_button(node)
	_wire_drag_control(node)
	for child in node.get_children():
		_scan_tree(child)


func _wire_drag_control(node: Node) -> void:
	## HSlider / VScrollBar use the hover cursor (Cursor_02).
	if node is Slider or node is ScrollBar:
		(node as Control).mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _wire_button(node: Node) -> void:
	if not (node is BaseButton):
		return
	var btn := node as BaseButton
	var id := btn.get_instance_id()
	if _wired.has(id):
		return
	_wired[id] = true
	_refresh_button_cursor(btn)
	btn.mouse_entered.connect(_refresh_button_cursor.bind(btn))
	btn.visibility_changed.connect(_refresh_button_cursor.bind(btn))
	btn.tree_exiting.connect(_on_button_exiting.bind(btn))


func _on_button_exiting(btn: BaseButton) -> void:
	_wired.erase(btn.get_instance_id())


func _refresh_button_cursor(btn: BaseButton) -> void:
	if not is_instance_valid(btn):
		return
	if btn.disabled:
		btn.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
	else:
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
