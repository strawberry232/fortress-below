extends "res://addons/gut/test.gd"

const DUNGEON_SCRIPT: Script = preload("res://game/scripts/dungeon/dungeon_world.gd")


func before_each() -> void:
	for action: String in ["fb_move_left", "fb_move_right", "fb_move_up", "fb_move_down", "fb_sword", "fb_bow", "fb_interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func _new_world() -> Node2D:
	var dungeon: Node2D = DUNGEON_SCRIPT.new()
	add_child_autofree(dungeon)
	dungeon.set_physics_process(false)
	return dungeon


func _stop_actors(dungeon: Node2D) -> void:
	dungeon.player.set_physics_process(false)
	for enemy: CharacterBody2D in dungeon._enemies:
		enemy.set_physics_process(false)


func _adult_slime(dungeon: Node2D) -> CharacterBody2D:
	for enemy: CharacterBody2D in dungeon._enemies:
		if enemy.monster_kind == "slime" and enemy.slime_generation == 0:
			return enemy
	return null


func _body_clear(actor: CharacterBody2D) -> bool:
	var foot_shape: CollisionShape2D = actor.get_child(0)
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = foot_shape.shape
	query.transform = foot_shape.global_transform
	query.collision_mask = 1
	query.collide_with_areas = false
	return actor.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func test_real_circle_can_split_beside_concave_wall_corner_and_unlock_gate() -> void:
	var dungeon: Node2D = _new_world()
	_stop_actors(dungeon)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var adult: CharacterBody2D = _adult_slime(dungeon)
	adult.position = Vector2(360.6, 244.6)
	await get_tree().physics_frame
	assert_true(_body_clear(adult), "The actual radius-12 circle fits beside the concave wall corner")
	assert_true(adult.receive_damage(1000, "concave-corner-death"))
	await get_tree().process_frame
	_stop_actors(dungeon)
	var fragments: Array[CharacterBody2D] = []
	for enemy: CharacterBody2D in dungeon._enemies:
		if enemy.monster_kind == "slime" and enemy.slime_generation == 1 and enemy.health.is_alive():
			fragments.append(enemy)
	assert_eq(fragments.size(), 2, "A valid circular footprint cannot be rejected because a rectangular sample reaches the wall")
	if fragments.size() != 2:
		return
	await get_tree().physics_frame
	for fragment: CharacterBody2D in fragments:
		assert_true(_body_clear(fragment), "Spawned child colliders remain outside real walls")
		assert_gt(dungeon.get_navigation_path(dungeon.player.position, fragment.position).size(), 0)
	dungeon._enemies[0].receive_damage(1000, "remaining-skeleton")
	fragments[0].health.tick(0.26)
	fragments[0].receive_damage(1000, "first-child")
	fragments[1].health.tick(0.26)
	fragments[1].receive_damage(1000, "second-child")
	assert_eq(dungeon._middle_guardians, 0, "The corner case cannot leave reserved but nonexistent guardians")
	assert_gt(dungeon.get_navigation_path(dungeon.player.position, dungeon.key_position).size(), 0)


func test_all_three_maps_spawn_clear_children_at_physically_legal_corner_positions() -> void:
	var dungeon: Node2D = _new_world()
	var corners: Array[Vector2] = [Vector2(360.6, 244.6), Vector2(328.6, 195.4), Vector2(360.6, 244.6)]
	for level_index: int in range(3):
		dungeon.reset_run(level_index)
		_stop_actors(dungeon)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var adult: CharacterBody2D = _adult_slime(dungeon)
		adult.position = corners[level_index]
		await get_tree().physics_frame
		assert_true(_body_clear(adult), "The regression origin is physically legal in map %d" % level_index)
		adult.receive_damage(1000, "corner-map-%d" % level_index)
		await get_tree().process_frame
		_stop_actors(dungeon)
		var fragments: Array[CharacterBody2D] = []
		for enemy: CharacterBody2D in dungeon._enemies:
			if enemy.monster_kind == "slime" and enemy.slime_generation == 1 and enemy.health.is_alive():
				fragments.append(enemy)
		assert_eq(fragments.size(), 2)
		await get_tree().physics_frame
		for fragment: CharacterBody2D in fragments:
			assert_true(_body_clear(fragment))
			assert_gt(dungeon.get_navigation_path(dungeon.player.position, fragment.position).size(), 0)


func test_invalid_split_origin_cannot_leave_phantom_guardians() -> void:
	var dungeon: Node2D = _new_world()
	_stop_actors(dungeon)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var adult: CharacterBody2D = _adult_slime(dungeon)
	adult.position = Vector2(-200.0, -200.0)
	adult.receive_damage(1000, "invalid-debug-position")
	await get_tree().process_frame
	assert_eq(dungeon._middle_guardians, 1, "Malformed off-map positions cannot leave reserved guardians without living bodies")
	dungeon._enemies[0].receive_damage(1000, "last-real-guardian")
	assert_eq(dungeon._middle_guardians, 0)
	assert_gt(dungeon.get_navigation_path(dungeon.player.position, dungeon.key_position).size(), 0)
