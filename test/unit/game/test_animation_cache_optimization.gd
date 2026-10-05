extends "res://addons/gut/test.gd"

const Catalog = preload("res://game/data/monsters/monster_catalog.gd")
const CharacterFramesLibrary = preload("res://game/scripts/combat/fortress_animation_library.gd")


func _original_sample(definition: Dictionary, action: String, elapsed: float) -> Dictionary:
	var animation: Dictionary = definition["animations"][action]
	var milliseconds: float = 0.0
	for duration: Variant in animation["durations_ms"]:
		milliseconds += duration
	var at: float = maxf(0.0, elapsed)
	if animation["loop"]:
		at = fmod(at, milliseconds / 1000.0)
	var index: int = animation["durations_ms"].size() - 1
	for frame: int in range(animation["durations_ms"].size()):
		var duration: float = animation["durations_ms"][frame] / 1000.0
		if at < duration:
			index = frame
			break
		at -= duration
	var split: bool = animation["paths"].size() > 1
	return {"path": animation["paths"][index if split else 0], "source": Rect2(Vector2.ZERO if split else Vector2(index * definition["frame_size"].x, 0), Vector2(definition["frame_size"])), "frame": index}


func test_kind_frames_are_shared_but_actor_playback_remains_independent() -> void:
	for kind: String in Catalog.TYPES:
		var first: SpriteFrames = Catalog.create_frames(kind)
		var second: SpriteFrames = Catalog.create_frames(kind)
		assert_same(first, second, "Actors of one type share immutable frame resources")
		var left: AnimatedSprite2D = AnimatedSprite2D.new()
		var right: AnimatedSprite2D = AnimatedSprite2D.new()
		add_child_autofree(left)
		add_child_autofree(right)
		left.sprite_frames = first
		right.sprite_frames = second
		left.animation = &"death"
		left.frame = first.get_frame_count("death") - 1
		right.animation = &"walk"
		right.frame = 1
		assert_eq(left.animation, &"death")
		assert_eq(right.animation, &"walk")
		assert_eq(left.frame, first.get_frame_count("death") - 1)
		assert_eq(right.frame, 1)
	assert_ne(Catalog.create_frames("skeleton"), Catalog.create_frames("armored_skeleton"))


func test_cached_definitions_samples_and_windows_remain_isolated_from_callers() -> void:
	var original: Dictionary = Catalog.get_definition("orc")
	var expected: Dictionary = Catalog.sample("orc", "death", 0.31)
	var changed: Dictionary = Catalog.get_definition("orc")
	changed["health"] = 1
	changed["animations"]["death"]["durations_ms"][3] = 1
	changed["animations"]["death"]["paths"][0] = "missing"
	assert_eq(Catalog.get_definition("orc"), original)
	assert_eq(Catalog.sample("orc", "death", 0.31), expected)
	var sample: Dictionary = Catalog.sample("orc", "death", 0.31)
	sample["frame"] = 100
	assert_eq(Catalog.sample("orc", "death", 0.31), expected)
	var windows: Array[Vector2] = Catalog.attack_windows("armored_skeleton")
	windows[0] = Vector2.ZERO
	assert_almost_eq(Catalog.attack_windows("armored_skeleton")[0].x, 0.5, 0.000001)
	assert_eq(Catalog.sample("missing", "idle", 0.0), {})
	assert_eq(Catalog.sample("skeleton", "missing", 0.0), {})
	assert_eq(Catalog.action_duration("missing", "death"), 0.0)
	assert_eq(Catalog.attack_windows("missing"), [] as Array[Vector2])
	assert_eq(Catalog.create_frames("missing").get_animation_names().size(), 0)


func test_cached_sampling_preserves_authored_timings_at_boundaries_and_loops() -> void:
	for kind: String in Catalog.TYPES:
		var definition: Dictionary = Catalog.get_definition(kind)
		for action: String in Catalog.ACTIONS:
			var elapsed: float = 0.0
			var milliseconds: float = 0.0
			for duration: Variant in definition["animations"][action]["durations_ms"]:
				milliseconds += duration
				for offset: float in [-0.000001, 0.0, 0.000001]:
					assert_eq(Catalog.sample(kind, action, elapsed + offset), _original_sample(definition, action, elapsed + offset), "%s %s boundary %f" % [kind, action, elapsed + offset])
				elapsed += duration / 1000.0
			assert_eq(Catalog.action_duration(kind, action), milliseconds / 1000.0)
			for at: float in [-1.0, milliseconds / 1000.0, 2.01 * milliseconds / 1000.0, 100.0]:
				assert_eq(Catalog.sample(kind, action, at), _original_sample(definition, action, at))


func test_character_frame_cache_keys_include_timing_and_size() -> void:
	var definitions: Dictionary = {"idle": ["idle", 6, 10.0], "death": ["death", 4, 10.0, [1.0, 1.0, 1.0, 6.0]]}
	var first: SpriteFrames = CharacterFramesLibrary.character_frames("tiny_rpg", "soldier", Vector2i(100, 100), definitions)
	assert_same(first, CharacterFramesLibrary.character_frames("tiny_rpg", "soldier", Vector2i(100, 100), definitions.duplicate(true)))
	definitions["death"][3][3] = 5.0
	var changed: SpriteFrames = CharacterFramesLibrary.character_frames("tiny_rpg", "soldier", Vector2i(100, 100), definitions)
	assert_ne(first, changed)
	assert_eq(first.get_frame_duration("death", 3), 6.0)
	assert_eq(changed.get_frame_duration("death", 3), 5.0)
	var smaller: SpriteFrames = CharacterFramesLibrary.character_frames("tiny_rpg", "soldier", Vector2i(50, 50), definitions)
	assert_ne(smaller, changed)
	assert_eq((smaller.get_frame_texture("idle", 1) as AtlasTexture).region, Rect2(50, 0, 50, 50))


func test_explicit_asset_cache_reset_rebuilds_resources_without_mutating_existing_actors() -> void:
	var catalog: Script = load("res://game/data/monsters/monster_catalog.gd")
	var library: Script = load("res://game/scripts/combat/fortress_animation_library.gd")
	assert_true(catalog.has_method("clear_cache"))
	assert_true(library.has_method("clear_cache"))
	if not catalog.has_method("clear_cache") or not library.has_method("clear_cache"):
		return
	var before: SpriteFrames = Catalog.create_frames("skeleton")
	var expected: Dictionary = Catalog.sample("skeleton", "death", 0.6)
	catalog.call("clear_cache")
	var rebuilt: SpriteFrames = Catalog.create_frames("skeleton")
	assert_ne(before, rebuilt)
	assert_eq(Catalog.sample("skeleton", "death", 0.6), expected)
	assert_eq(before.get_frame_count("death"), rebuilt.get_frame_count("death"))
	var definitions: Dictionary = {"idle": ["idle", 6, 10.0]}
	var player_before: SpriteFrames = CharacterFramesLibrary.character_frames("tiny_rpg", "soldier", Vector2i(100, 100), definitions)
	library.call("clear_cache")
	assert_ne(player_before, CharacterFramesLibrary.character_frames("tiny_rpg", "soldier", Vector2i(100, 100), definitions))
