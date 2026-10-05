extends RefCounted
class_name FortressAnimationLibrary

static var _frames: Dictionary = {}


static func clear_cache() -> void:
	_frames.clear()


# Cached resources are read-only; actors keep independent playback state.
static func character_frames(folder: String, prefix: String, frame_size: Vector2i, definitions: Dictionary) -> SpriteFrames:
	var cache_key: String = JSON.stringify([folder, prefix, frame_size.x, frame_size.y, definitions])
	if _frames.has(cache_key):
		return _frames[cache_key]
	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation("default")
	for animation_name: String in definitions:
		var definition: Array = definitions[animation_name]
		var texture: Texture2D = load("res://game/assets/%s/%s_%s.png" % [folder, prefix, definition[0]])
		frames.add_animation(animation_name)
		frames.set_animation_speed(animation_name, definition[2])
		frames.set_animation_loop(animation_name, animation_name in ["idle", "walk"])
		for index: int in range(definition[1]):
			var atlas: AtlasTexture = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(index * frame_size.x, 0, frame_size.x, frame_size.y)
			var duration: float = definition[3][index] if definition.size() > 3 else 1.0
			frames.add_frame(animation_name, atlas, duration)
	_frames[cache_key] = frames
	return frames
