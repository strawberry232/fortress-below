extends "res://addons/gut/test.gd"

const EFFECT_SCRIPT: String = "res://game/scripts/fx/pixel_effects.gd"

func after_each() -> void:
	get_tree().paused = false
	await get_tree().process_frame

func _create_effects() -> Node2D:
	var exists: bool = ResourceLoader.exists(EFFECT_SCRIPT)
	assert_true(exists, "The effect manager exists")
	if not exists:
		return null
	var script: Script = load(EFFECT_SCRIPT)
	var manager: Node2D = script.new()
	add_child_autofree(manager)
	return manager

func test_hit_uses_the_original_gray_row_and_global_position() -> void:
	var manager: Node2D = _create_effects()
	if manager == null:
		return
	var effect: AnimatedSprite2D = manager.spawn_effect("sword_hit", Vector2(250, 180))
	assert_not_null(effect)
	if effect == null:
		return
	assert_eq(effect.global_position, Vector2(250, 180))
	assert_true(effect.is_playing())
	assert_false(effect.sprite_frames.get_animation_loop("effect"))
	var texture: AtlasTexture = effect.sprite_frames.get_frame_texture("effect", 0) as AtlasTexture
	assert_not_null(texture)
	if texture == null:
		return
	assert_eq(texture.region, Rect2(0, 320, 64, 64))
	assert_true(texture.atlas.resource_path.ends_with("/fx/hit.png"))
	assert_eq(effect.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)

func test_separate_effects_finish_and_free_their_nodes() -> void:
	var manager: Node2D = _create_effects()
	if manager == null:
		return
	manager.spawn_effect("sword_hit", Vector2.ZERO)
	manager.spawn_effect("heal", Vector2(100, 50))
	manager.spawn_effect("castle_hit", Vector2(200, 80))
	assert_eq(manager.get_child_count(), 3)
	assert_null(manager.spawn_effect("unknown_effect", Vector2.ZERO))
	assert_eq(manager.get_child_count(), 3)
	await get_tree().create_timer(1.2).timeout
	await get_tree().process_frame
	assert_eq(manager.get_child_count(), 0, "One-shot animations leave no sprite nodes behind")

func test_paused_effects_stop_advancing_then_clean_up_after_resume() -> void:
	var manager: Node2D = _create_effects()
	if manager == null:
		return
	var effect: AnimatedSprite2D = manager.spawn_effect("heal", Vector2.ZERO)
	await get_tree().create_timer(0.1).timeout
	get_tree().paused = true
	var frame_before: int = effect.frame
	await get_tree().create_timer(0.2, true).timeout
	assert_eq(effect.frame, frame_before)
	get_tree().paused = false
	await get_tree().create_timer(1.1).timeout
	await get_tree().process_frame
	assert_eq(manager.get_child_count(), 0)

func test_bounded_simultaneous_effects_and_clear_do_not_leak() -> void:
	var manager: Node2D = _create_effects()
	if manager == null:
		return
	var limit: int = manager.get("max_effects")
	for index: int in range(limit):
		assert_not_null(manager.spawn_effect("enemy_hit", Vector2(index, 0)))
	assert_null(manager.spawn_effect("enemy_hit", Vector2.ZERO), "A full effect pool declines another sprite")
	assert_eq(manager.get_child_count(), limit)
	manager.clear()
	await get_tree().process_frame
	assert_eq(manager.get_child_count(), 0)
