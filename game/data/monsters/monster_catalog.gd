extends RefCounted
class_name FortressMonsterCatalog

const TYPES: Array[String] = ["skeleton", "armored_skeleton", "skull", "vampire", "orc", "slime"]
const ACTIONS: Array[String] = ["idle", "walk", "attack", "hurt", "death"]
const DEFINITIONS: Dictionary = {
	"skeleton": {"name_key": "UI_MONSTER_SKELETON", "health": 40, "speed": 65.0, "damage": 15},
	"armored_skeleton": {"name_key": "UI_MONSTER_ARMORED_SKELETON", "health": 60, "speed": 48.0, "damage": 18},
	"skull": {"name_key": "UI_MONSTER_SKULL", "health": 30, "speed": 110.0, "damage": 10},
	"vampire": {"name_key": "UI_MONSTER_VAMPIRE", "health": 120, "speed": 92.0, "damage": 26},
	"orc": {"name_key": "UI_MONSTER_ORC", "health": 50, "speed": 54.0, "damage": 15},
	"slime": {"name_key": "UI_MONSTER_SLIME", "health": 45, "speed": 58.0, "damage": 12}
}
const HIT_FRAMES: Dictionary = {
	"skeleton": [[6, 8]], "armored_skeleton": [[5, 7], [10, 12]],
	"orc": [[3, 5]], "slime": [[4, 6]], "vampire": [[4, 12]], "skull": [[3, 4]]
}
static var _profiles: Dictionary = {}
static var _definitions: Dictionary = {}
static var _animations: Dictionary = {}
static var _windows: Dictionary = {}
static var _frames: Dictionary = {}

static func clear_cache() -> void:
	_profiles.clear()
	_definitions.clear()
	_animations.clear()
	_windows.clear()
	_frames.clear()

static func attack_windows(kind: String) -> Array[Vector2]:
	if _windows.has(kind):
		return (_windows[kind] as Array[Vector2]).duplicate()
	var result: Array[Vector2] = []
	var definition: Dictionary = _cached_definition(kind)
	if definition.is_empty() or not HIT_FRAMES.has(kind):
		return result
	var durations: Array = definition["animations"]["attack"]["durations_ms"]
	for interval: Array in HIT_FRAMES[kind]:
		var start: float = 0.0
		var end: float = 0.0
		for index: int in range(mini(interval[1], durations.size())):
			end += durations[index] / 1000.0
			if index < interval[0]:
				start = end
		result.append(Vector2(start, end))
	_windows[kind] = result
	return result.duplicate()

static func get_definition(kind: String) -> Dictionary:
	return _cached_definition(kind).duplicate(true)

static func _cached_definition(kind: String) -> Dictionary:
	if not DEFINITIONS.has(kind):
		return {}
	if _definitions.has(kind):
		return _definitions[kind]
	if _profiles.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/monsters/animation_profiles.json"))
		if not parsed is Dictionary:
			return {}
		_profiles = parsed
	if not _profiles.has(kind):
		return {}
	var definition: Dictionary = DEFINITIONS[kind].duplicate(true)
	definition.merge(_profiles[kind].duplicate(true))
	var size: Array = definition["frame_size"]
	var foot: Array = definition["foot_anchor"]
	definition["frame_size"] = Vector2i(size[0], size[1])
	definition["foot_anchor"] = Vector2(foot[0], foot[1])
	definition["id"] = kind
	_definitions[kind] = definition
	return definition

static func _cached_animation(kind: String, action: String) -> Dictionary:
	var definition: Dictionary = _cached_definition(kind)
	if definition.is_empty() or not definition["animations"].has(action):
		return {}
	if _animations.has(kind) and _animations[kind].has(action):
		return _animations[kind][action]
	var animation: Dictionary = definition["animations"][action]
	var milliseconds: float = 0.0
	var durations: Array[float] = []
	var samples: Array[Dictionary] = []
	var split: bool = animation["paths"].size() > 1
	for index: int in range(animation["durations_ms"].size()):
		var duration: Variant = animation["durations_ms"][index]
		milliseconds += duration
		durations.append(duration / 1000.0)
		samples.append({"path": animation["paths"][index if split else 0], "source": Rect2(Vector2.ZERO if split else Vector2(index * definition["frame_size"].x, 0), Vector2(definition["frame_size"])), "frame": index})
	var compiled: Dictionary = {"duration": milliseconds / 1000.0, "durations": durations, "samples": samples, "loop": animation["loop"]}
	if not _animations.has(kind):
		_animations[kind] = {}
	_animations[kind][action] = compiled
	return compiled

static func action_duration(kind: String, action: String) -> float:
	var animation: Dictionary = _cached_animation(kind, action)
	return animation.get("duration", 0.0)

static func sample(kind: String, action: String, elapsed: float) -> Dictionary:
	var animation: Dictionary = _cached_animation(kind, action)
	if animation.is_empty() or animation["samples"].is_empty():
		return {}
	var at: float = maxf(0.0, elapsed)
	if animation["loop"]:
		if animation["duration"] <= 0.0:
			return {}
		at = fmod(at, animation["duration"])
	var index: int = animation["durations"].size() - 1
	for frame: int in range(animation["durations"].size()):
		var duration: float = animation["durations"][frame]
		if at < duration:
			index = frame
			break
		at -= duration
	return animation["samples"][index].duplicate()

# Callers share these resources and only change AnimatedSprite2D playback state.
static func create_frames(kind: String) -> SpriteFrames:
	if _frames.has(kind):
		return _frames[kind]
	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation("default")
	var definition: Dictionary = _cached_definition(kind)
	if definition.is_empty():
		return frames
	for action: String in ACTIONS:
		var animation: Dictionary = definition["animations"][action]
		frames.add_animation(action)
		frames.set_animation_speed(action, 10.0)
		frames.set_animation_loop(action, animation["loop"])
		for index: int in range(animation["durations_ms"].size()):
			var split: bool = animation["paths"].size() > 1
			var atlas: AtlasTexture = AtlasTexture.new()
			atlas.atlas = load(animation["paths"][index if split else 0]) as Texture2D
			atlas.region = Rect2(Vector2.ZERO if split else Vector2(index * definition["frame_size"].x, 0), Vector2(definition["frame_size"]))
			frames.add_frame(action, atlas, animation["durations_ms"][index] / 100.0)
	_frames[kind] = frames
	return frames
