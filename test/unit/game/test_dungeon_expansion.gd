extends "res://addons/gut/test.gd"

const DUNGEON_SCRIPT: Script = preload("res://game/scripts/dungeon/dungeon_world.gd")
const ENEMY_SCRIPT: Script = preload("res://game/scripts/combat/fortress_skeleton.gd")


func before_each() -> void:
	for action: String in ["fb_move_left", "fb_move_right", "fb_move_up", "fb_move_down", "fb_sword", "fb_bow", "fb_interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func _new_world() -> Node2D:
	var dungeon: Node2D = DUNGEON_SCRIPT.new()
	add_child_autofree(dungeon)
	dungeon.process_mode = Node.PROCESS_MODE_DISABLED
	return dungeon


func _supports_levels(dungeon: Node2D) -> bool:
	assert_true(dungeon.has_method("get_level_info"), "The runtime exposes its selected authored level")
	if not dungeon.has_method("get_level_info"):
		return false
	return true


func _defeat_encounter(dungeon: Node2D, attack_id: String) -> void:
	for generation: int in range(2):
		var current_enemies: Array = dungeon._enemies.duplicate()
		for enemy: CharacterBody2D in current_enemies:
			if is_instance_valid(enemy) and enemy.revival.pending:
				enemy._physics_process(enemy.revival.total_duration())
				enemy.health.tick(0.4)
			if is_instance_valid(enemy) and enemy.health.is_alive():
				enemy.set_physics_process(false)
				if enemy.slime_generation == 1:
					enemy.health.tick(0.26)
				enemy.receive_damage(1000, "%s-%d" % [attack_id, generation])
		await get_tree().process_frame


func _reachable_cells(dungeon: Node2D, start: Vector2) -> Dictionary:
	var first: Vector2i = Vector2i(floori(start.x / 32.0), floori(start.y / 32.0))
	var visited: Dictionary = {first: true}
	var queue: Array[Vector2i] = [first]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if visited.has(next):
				continue
			if dungeon.is_walkable(Vector2(next) * 32.0 + Vector2(16.0, 28.0)):
				visited[next] = true
				queue.append(next)
	return visited


func test_three_authored_layouts_are_distinct_and_have_reachable_rewards() -> void:
	var dungeon: Node2D = _new_world()
	if not _supports_levels(dungeon):
		return
	var signatures: Array[String] = []
	for level_index: int in range(3):
		dungeon.reset_run(level_index)
		await get_tree().process_frame
		var info: Dictionary = dungeon.get_level_info()
		assert_eq(info["index"], level_index)
		var reachable: Dictionary = _reachable_cells(dungeon, info["player_start"])
		var points: Array = [info["ordinary_chest"], info["sealed_chest"], info["key"], info["stairs"]]
		points.append_array(info["potions"])
		for point: Vector2 in points:
			assert_true(reachable.has(Vector2i(floori(point.x / 32.0), floori(point.y / 32.0))), "Every reward and return stair is connected in level %d" % level_index)
		var signature: String = ""
		for y: int in range(15):
			for x: int in range(32):
				signature += "1" if dungeon.is_walkable(Vector2(x * 32 + 16, y * 32 + 28)) else "0"
		assert_false(signatures.has(signature), "Each level changes the physical floor topology")
		signatures.append(signature)


func test_each_level_guardians_physically_unlock_all_reward_gates() -> void:
	var dungeon: Node2D = _new_world()
	if not _supports_levels(dungeon):
		return
	for level_index: int in range(3):
		dungeon.reset_run(level_index)
		dungeon.process_mode = Node.PROCESS_MODE_INHERIT
		dungeon.set_physics_process(false)
		dungeon.player.set_physics_process(false)
		for enemy: CharacterBody2D in dungeon._enemies:
			enemy.set_physics_process(false)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var info: Dictionary = dungeon.get_level_info()
		for gate: Rect2 in info["gates"]:
			dungeon.player.position = gate.get_center() + Vector2(-52.0, 12.0)
			assert_not_null(dungeon.player.move_and_collide(Vector2(104.0, 0.0)), "A locked gate blocks actual movement")
		await _defeat_encounter(dungeon, "clear-level-%d" % level_index)
		await get_tree().physics_frame
		await get_tree().physics_frame
		assert_eq(dungeon._middle_guardians, 0)
		for gate: Rect2 in info["gates"]:
			dungeon.player.position = gate.get_center() + Vector2(-52.0, 12.0)
			assert_null(dungeon.player.move_and_collide(Vector2(104.0, 0.0)), "Defeating guardians opens every physical route to the reward area")


func test_retry_restores_selected_level_health_and_one_time_rewards() -> void:
	var dungeon: Node2D = _new_world()
	if not _supports_levels(dungeon):
		return
	dungeon.reset_run(2)
	await get_tree().process_frame
	var info: Dictionary = dungeon.get_level_info()
	dungeon._handle_interaction_at(info["ordinary_chest"])
	dungeon.confirm_sealed_chest()
	await _defeat_encounter(dungeon, "retry-clear")
	dungeon._handle_interaction_at(info["key"])
	assert_true(dungeon._key_taken, "A completed encounter clears both vampire lives before the retry fixture takes its key")
	dungeon.player.receive_damage(40, "retry-hurt")
	assert_eq(dungeon.get_player_health(), 60)
	dungeon.reset_run(2)
	await get_tree().process_frame
	assert_eq(dungeon.get_level_info()["index"], 2)
	assert_eq(dungeon.get_player_health(), 100)
	assert_false(dungeon._ordinary_open)
	assert_false(dungeon._sealed_open)
	assert_false(dungeon._key_taken)
	assert_gt(dungeon._middle_guardians, 0)


func test_dungeon_skeleton_uses_original_idle_frames_without_fake_source_animations() -> void:
	var enemy: CharacterBody2D = ENEMY_SCRIPT.new()
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	var frames: SpriteFrames = enemy._sprite.sprite_frames
	var idle_frame: Texture2D = frames.get_frame_texture("idle", 0)
	assert_eq(idle_frame.get_size(), Vector2(32.0, 32.0))
	assert_eq(idle_frame.atlas.resource_path, "res://game/assets/enemies/skeleton_idle.png")
	assert_eq(frames.get_frame_count("idle"), 6)
	assert_eq(frames.get_animation_names(), PackedStringArray(["attack", "death", "hurt", "idle", "walk"]))
	assert_true(frames.get_animation_loop("idle"))


func test_feedback_signal_exists_and_reward_feedback_is_not_duplicated() -> void:
	var dungeon: Node2D = _new_world()
	assert_true(dungeon.has_signal("feedback_requested"))
	if not dungeon.has_signal("feedback_requested"):
		return
	watch_signals(dungeon)
	dungeon._handle_interaction_at(Vector2(224.0, 144.0))
	dungeon._handle_interaction_at(Vector2(224.0, 144.0))
	assert_signal_emit_count(dungeon, "feedback_requested", 1)
	assert_signal_emitted_with_parameters(dungeon, "feedback_requested", ["chest", dungeon.to_global(Vector2(224.0, 144.0))])
	dungeon.confirm_sealed_chest()
	dungeon.confirm_sealed_chest()
	assert_signal_emit_count(dungeon, "feedback_requested", 2)


func test_locked_levels_have_no_reward_path_then_full_physics_routes_after_unlock() -> void:
	var dungeon: Node2D = _new_world()
	if not _supports_levels(dungeon):
		return
	for level_index: int in range(3):
		dungeon.reset_run(level_index)
		dungeon.process_mode = Node.PROCESS_MODE_INHERIT
		dungeon.set_physics_process(false)
		dungeon.player.set_physics_process(false)
		for enemy: CharacterBody2D in dungeon._enemies:
			enemy.set_physics_process(false)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var info: Dictionary = dungeon.get_level_info()
		assert_true(dungeon.get_navigation_path(info["player_start"], info["key"]).is_empty(), "Locked reward gates prevent bypassing guardian fights")
		await _defeat_encounter(dungeon, "open-path-%d" % level_index)
		await get_tree().physics_frame
		await get_tree().physics_frame
		for goal: Vector2 in [info["key"], info["sealed_chest"], info["stairs"]]:
			var path: PackedVector2Array = dungeon.get_navigation_path(dungeon.player.position, goal)
			assert_gt(path.size(), 0, "The unlocked map provides a complete path to each gameplay goal")
			if path.is_empty():
				continue
			dungeon.player.position = path[0]
			for index: int in range(1, path.size()):
				var collision: KinematicCollision2D = dungeon.player.move_and_collide(path[index] - dungeon.player.position)
				assert_null(collision, "Authored routes fit the actual foot collider in level %d" % level_index)
			assert_lt(dungeon.player.position.distance_to(goal), 58.0, "The route ends inside actual interaction range")


func test_skeleton_chases_through_bent_corridor_without_sticking_to_wall() -> void:
	var dungeon: Node2D = _new_world()
	if not _supports_levels(dungeon):
		return
	dungeon.reset_run(1)
	dungeon.process_mode = Node.PROCESS_MODE_INHERIT
	dungeon.player.set_physics_process(false)
	var enemy: CharacterBody2D = dungeon._enemies[0]
	var previous_time_scale: float = Engine.time_scale
	Engine.time_scale = 8.0
	await get_tree().create_timer(11.0).timeout
	Engine.time_scale = previous_time_scale
	assert_lt(enemy.global_position.distance_to(dungeon.player.global_position), 100.0, "An active skeleton follows the authored bent corridor into the entrance room")
