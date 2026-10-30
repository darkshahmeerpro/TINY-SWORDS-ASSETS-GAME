class_name WorldVfx
extends RefCounted

## Tiny static helper for the Tiny Swords particle strips.
## Strips are square-frame horizontal sheets (frame size = image height).

const DUST_PATHS := ["res://assets/fx/Dust_01.png", "res://assets/fx/Dust_02.png"]
const FIRE_PATHS := ["res://assets/fx/Fire_01.png", "res://assets/fx/Fire_02.png", "res://assets/fx/Fire_03.png"]
const EXPLOSION_PATHS := ["res://assets/fx/Explosion_01.png", "res://assets/fx/Explosion_02.png"]
const SPLASH_PATH := "res://assets/fx/Water Splash.png"

static var _frames_cache: Dictionary = {}


## One-shot dust puff (enemy spawn/despawn, building placement).
static func spawn_dust(parent: Node, pos: Vector2) -> void:
	_spawn_one_shot(parent, pos, DUST_PATHS[randi() % DUST_PATHS.size()], 14.0)


## One-shot water splash (aquatic spawns, things hitting water).
static func spawn_splash(parent: Node, pos: Vector2) -> void:
	_spawn_one_shot(parent, pos, SPLASH_PATH, 14.0)


## One-shot explosion (big deaths, destroyed structures).
static func spawn_explosion(parent: Node, pos: Vector2) -> void:
	_spawn_one_shot(parent, pos, EXPLOSION_PATHS[randi() % EXPLOSION_PATHS.size()], 12.0)


## Light feedback for melee and harvesting impacts.
static func spawn_hit(parent: Node, pos: Vector2) -> void:
	_spawn_one_shot(parent, pos, DUST_PATHS[randi() % DUST_PATHS.size()], 18.0)


## Looping fire attached to a structure (goblin huts). Returns the sprite.
static func attach_fire(parent: Node, pos: Vector2, fire_scale: float = 1.0) -> AnimatedSprite2D:
	var frames := _strip_frames(FIRE_PATHS[randi() % FIRE_PATHS.size()], 10.0, true)
	if frames == null:
		return null
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.position = pos
	sprite.scale = Vector2(fire_scale, fire_scale)
	parent.add_child(sprite)
	sprite.play(&"fx")
	return sprite


static func _spawn_one_shot(parent: Node, pos: Vector2, path: String, fps: float) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var frames := _strip_frames(path, fps, false)
	if frames == null:
		return
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.position = pos
	parent.add_child(sprite)
	sprite.animation_finished.connect(sprite.queue_free)
	sprite.play(&"fx")


static func _strip_frames(path: String, fps: float, loop: bool) -> SpriteFrames:
	var key := "%s|%f|%s" % [path, fps, loop]
	if _frames_cache.has(key):
		return _frames_cache[key]
	var frames: SpriteFrames = null
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			var size: int = tex.get_height()
			var count: int = maxi(1, floori(float(tex.get_width()) / float(maxi(size, 1))))
			frames = SpriteFrames.new()
			frames.remove_animation(&"default")
			frames.add_animation(&"fx")
			frames.set_animation_speed(&"fx", fps)
			frames.set_animation_loop(&"fx", loop)
			for i in range(count):
				var atlas := AtlasTexture.new()
				atlas.atlas = tex
				atlas.region = Rect2(i * size, 0, size, size)
				frames.add_frame(&"fx", atlas)
	_frames_cache[key] = frames
	return frames
