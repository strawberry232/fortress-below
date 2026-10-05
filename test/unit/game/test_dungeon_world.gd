extends "res://addons/gut/test.gd"

const DUNGEON_PATH: String = "res://game/scripts/dungeon/dungeon_world.gd"


func before_each() -> void:
	for action: String in ["fb_move_left", "fb_move_right", "fb_move_up", "fb_move_down", "fb_sword", "fb_bow", "fb_interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func _new_dungeon() -> Node2D:
	assert_true(FileAccess.file_exists(DUNGEON_PATH), "The dungeon implementation exists")
	if not FileAccess.file_exists(DUNGEON_PATH):
		return null
	var dungeon_script: Script = load(DUNGEON_PATH)
	var dungeon: Node2D = dungeon_script.new()
	add_child_autofree(dungeon)
	dungeon.process_mode = Node.PROCESS_MODE_DISABLED
	return dungeon


func test_ordinary_chest_loot_emits_once_and_reset_restores_it() -> void:
	var dungeon: Node2D = _new_dungeon()
	if dungeon == null:
		return
	watch_signals(dungeon)
	dungeon._handle_interaction_at(Vector2(224.0, 144.0))
	dungeon._handle_interaction_at(Vector2(224.0, 144.0))
	assert_signal_emit_count(dungeon, "loot_collected", 1)
	assert_signal_emitted_with_parameters(dungeon, "loot_collected", [25])
	dungeon.reset_run()
	await get_tree().process_frame
	dungeon._handle_interaction_at(Vector2(224.0, 144.0))
	assert_signal_emit_count(dungeon, "loot_collected", 2)
	assert_eq(dungeon.get_player_health(), 100)


func test_sealed_chest_requests_confirmation_then_closes_without_bank_reward() -> void:
	var dungeon: Node2D = _new_dungeon()
	if dungeon == null:
		return
	watch_signals(dungeon)
	dungeon._handle_interaction_at(Vector2(416.0, 112.0))
	assert_signal_emit_count(dungeon, "sealed_chest_requested", 1)
	dungeon.confirm_sealed_chest()
	dungeon.confirm_sealed_chest()
	dungeon._handle_interaction_at(Vector2(416.0, 112.0))
	assert_signal_emit_count(dungeon, "sealed_chest_requested", 1)
	assert_signal_emit_count(dungeon, "loot_collected", 0)


func test_stairs_emit_exit_request_and_health_death_only_once() -> void:
	var dungeon: Node2D = _new_dungeon()
	if dungeon == null:
		return
	watch_signals(dungeon)
	dungeon._handle_interaction_at(dungeon.stairs_position)
	assert_signal_emit_count(dungeon, "exit_requested", 1)
	dungeon.player.receive_damage(1000, "test-death")
	dungeon.player.receive_damage(1000, "test-death-again")
	assert_signal_emit_count(dungeon, "failed", 1)
	assert_eq(dungeon.get_player_health(), 0)


func test_walkable_rooms_connect_only_through_corridors() -> void:
	var dungeon: Node2D = _new_dungeon()
	if dungeon == null:
		return
	assert_true(dungeon.is_walkable(Vector2(100.0, 200.0)))
	assert_true(dungeon.is_walkable(Vector2(320.0, 256.0)))
	assert_true(dungeon.is_walkable(Vector2(672.0, 256.0)))
	assert_false(dungeon.is_walkable(Vector2(320.0, 100.0)))
	assert_false(dungeon.is_walkable(Vector2(0.0, 0.0)))


func test_reward_key_requires_guard_defeat_and_is_collected_once() -> void:
	var dungeon: Node2D = _new_dungeon()
	if dungeon == null:
		return
	watch_signals(dungeon)
	dungeon._handle_interaction_at(Vector2(880.0, 144.0))
	assert_signal_emit_count(dungeon, "goal_key_collected", 0)
	var reward_guard: CharacterBody2D = dungeon._enemies[2]
	reward_guard.receive_damage(100, "guard-clear")
	dungeon._handle_interaction_at(Vector2(880.0, 144.0))
	dungeon._handle_interaction_at(Vector2(880.0, 144.0))
	assert_signal_emit_count(dungeon, "goal_key_collected", 1)


func test_middle_guardians_open_gate_and_physical_walls_block_walkers() -> void:
	var dungeon: Node2D = _new_dungeon()
	if dungeon == null:
		return
	dungeon.process_mode = Node.PROCESS_MODE_INHERIT
	dungeon.set_physics_process(false)
	dungeon.player.set_physics_process(false)
	for enemy: CharacterBody2D in dungeon._enemies:
		enemy.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	dungeon.player.position = Vector2(272.0, 144.0)
	var collision: KinematicCollision2D = dungeon.player.move_and_collide(Vector2(100.0, 0.0))
	assert_not_null(collision, "Walls physically block movement outside the connecting passage")
	assert_lt(dungeon.player.position.x, 288.0)
	dungeon._enemies[0].receive_damage(100, "middle-clear-1")
	dungeon._enemies[1].receive_damage(100, "middle-clear-2")
	await get_tree().process_frame
	assert_eq(dungeon._middle_guardians, 2, "The slain guardian slime leaves two guardians to defeat")
	for enemy: CharacterBody2D in dungeon._enemies:
		if enemy.monster_kind == "slime" and enemy.slime_generation == 1 and enemy.health.is_alive():
			enemy.set_physics_process(false)
			enemy.health.tick(0.26)
			enemy.receive_damage(100, "middle-fragment-clear")
	await get_tree().physics_frame
	await get_tree().physics_frame
	dungeon.player.position = Vector2(620.0, 268.0)
	var passage_collision: KinematicCollision2D = dungeon.player.move_and_collide(Vector2(140.0, 0.0))
	assert_null(passage_collision, "Defeating the middle guards physically opens the reward-room passage")
	assert_gt(dungeon.player.position.x, 704.0)
