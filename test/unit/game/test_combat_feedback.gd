extends "res://addons/gut/test.gd"

const PLAYER_SCRIPT: Script = preload("res://game/scripts/combat/fortress_player.gd")
const ENEMY_SCRIPT: Script = preload("res://game/scripts/combat/fortress_orc.gd")


func before_each() -> void:
	for action: String in ["fb_move_left", "fb_move_right", "fb_move_up", "fb_move_down", "fb_sword", "fb_bow", "fb_interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func test_player_feedback_tracks_real_action_and_damage_once() -> void:
	var player: CharacterBody2D = PLAYER_SCRIPT.new()
	add_child_autofree(player)
	player.set_physics_process(false)
	var events: Array[String] = []
	player.feedback_requested.connect(func(event: String, _at: Vector2) -> void: events.append(event))
	player._start_attack("attack")
	assert_eq(events, ["sword"])
	player._physics_process(0.65)
	player._start_attack("bow")
	player._physics_process(0.69)
	assert_eq(events, ["sword"], "Drawing the bow has not released its sound/projectile yet")
	player._physics_process(0.02)
	player._physics_process(0.1)
	assert_eq(events, ["sword", "bow"], "The released arrow emits only one feedback request")
	player.receive_damage(15, "feedback-hit")
	player.receive_damage(15, "feedback-hit")
	player.health.tick(0.6)
	player.receive_damage(100, "feedback-fatal")
	assert_eq(events, ["sword", "bow", "player_hurt", "player_death"])


func test_original_soldier_has_complete_non_looping_bow_hurt_and_death() -> void:
	var player: CharacterBody2D = PLAYER_SCRIPT.new()
	add_child_autofree(player)
	player.set_physics_process(false)
	var frames: SpriteFrames = player._sprite.sprite_frames
	for name: String in ["bow", "hurt", "death"]:
		assert_false(frames.get_animation_loop(name))
	assert_eq(frames.get_frame_count("idle"), 6)
	assert_eq(frames.get_frame_count("walk"), 8)
	assert_eq(frames.get_frame_count("attack"), 6)
	assert_eq(frames.get_frame_count("bow"), 9)
	assert_eq(frames.get_frame_count("hurt"), 4)
	assert_eq(frames.get_frame_count("death"), 4)
	assert_eq(player._sprite.position, Vector2(0.0, -30.0))


func test_orc_death_feedback_is_once_and_does_not_also_emit_hurt() -> void:
	var enemy: CharacterBody2D = ENEMY_SCRIPT.new()
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	var events: Array[String] = []
	enemy.feedback_requested.connect(func(event: String, _at: Vector2) -> void: events.append(event))
	enemy.receive_damage(15, "minor-hit")
	enemy.health.tick(0.2)
	enemy.receive_damage(100, "fatal-hit")
	enemy.receive_damage(100, "late-hit")
	assert_eq(events, ["enemy_hurt", "enemy_death"])


func test_original_death_animation_keeps_600_ms_final_frame() -> void:
	var player: CharacterBody2D = PLAYER_SCRIPT.new()
	add_child_autofree(player)
	player.set_physics_process(false)
	var enemy: CharacterBody2D = ENEMY_SCRIPT.new()
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	assert_eq(player._sprite.sprite_frames.get_frame_duration("death", 3), 6.0)
	assert_eq(enemy._sprite.sprite_frames.get_frame_duration("death", 3), 6.0)


func test_hurt_animation_remains_visible_for_its_four_original_frames() -> void:
	var player: CharacterBody2D = PLAYER_SCRIPT.new()
	add_child_autofree(player)
	player.set_physics_process(false)
	var enemy: CharacterBody2D = ENEMY_SCRIPT.new()
	enemy.position = Vector2(60.0, 0.0)
	enemy.target = player
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	player.receive_damage(15, "hurt-clip")
	enemy.receive_damage(15, "hurt-clip")
	player._physics_process(0.3)
	enemy._physics_process(0.3)
	assert_eq(player._sprite.animation, &"hurt")
	assert_eq(enemy._sprite.animation, &"hurt")
