extends "res://addons/gut/test.gd"

const DUNGEON: Script = preload("res://game/scripts/dungeon/dungeon_world.gd")


func before_each() -> void:
	for action: String in ["fb_move_left", "fb_move_right", "fb_move_up", "fb_move_down", "fb_sword", "fb_bow", "fb_interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func _world() -> Node2D:
	var world: Node2D = DUNGEON.new()
	add_child_autofree(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	return world


func test_sealed_chest_keeps_its_red_tint_through_every_opening_frame_and_retry() -> void:
	var world: Node2D = _world()
	var closed: Dictionary = world.get_chest_visual("sealed")
	var tint: Color = closed["tint"]
	assert_ne(tint, Color.WHITE)
	assert_true(closed["dangerous"])
	assert_eq(closed.get("indicator", ""), "exclamation")
	assert_false(closed.get("seal", true), "No crossed seal lines are drawn on the chest")
	assert_eq(closed["warning_key"], "", "The map chest has no text overlay")
	world._clock = 2.0
	world.confirm_sealed_chest()
	for frame: int in range(4):
		world._clock = 2.0 + (frame + 0.25) * world.CHEST_FRAME_TIME
		var opening: Dictionary = world.get_chest_visual("sealed")
		assert_eq(opening["frame"], frame)
		assert_eq(opening["state"], "opening")
		assert_eq(opening["tint"], tint, "The original red model stays red during the original animation")
		assert_false(opening["dangerous"])
		assert_eq(opening.get("indicator", "unexpected"), "")
		assert_eq(opening["warning_key"], "")
	world._clock = 20.0
	assert_eq(world.get_chest_visual("sealed")["state"], "opened")
	assert_eq(world.get_chest_visual("sealed")["tint"], tint)
	assert_eq(world.get_chest_visual("ordinary")["tint"], Color.WHITE)
	assert_eq(world.get_chest_visual("missing"), {})
	world.reset_run(1)
	await get_tree().process_frame
	assert_eq(world.get_chest_visual("sealed")["tint"], tint)
	assert_eq(world.get_chest_visual("sealed")["indicator"], "exclamation")
	assert_eq(world.get_chest_visual("sealed")["state"], "closed")


func test_ladder_uses_authentic_ladder_tile_on_north_wall_with_reachable_interaction_in_every_map() -> void:
	var world: Node2D = _world()
	for level: int in range(3):
		world.reset_run(level)
		await get_tree().process_frame
		var visual: Dictionary = world.get_exit_visual()
		assert_eq(visual["source"], Rect2(144, 48, 16, 16), "Use the original vertical ladder instead of either ground stair tile")
		assert_eq(visual.get("model", ""), "wall_ladder")
		assert_eq(visual["direction"], "up")
		var destination: Rect2 = visual["destination"]
		assert_eq(destination.size, Vector2(32, 32))
		assert_false(world.is_walkable(destination.get_center()))
		assert_ne(destination.get_center(), world.stairs_position)
		assert_eq(visual.get("interaction_position", Vector2.ZERO), world.stairs_position)
		assert_true(world.is_walkable(world.stairs_position))
		assert_eq(world.get_map_tile_visual(Vector2i(destination.get_center() / 32.0))["kind"], "wall")
		assert_gt(world.get_navigation_path(world.player.position, world.stairs_position).size(), 0)
		assert_true(Rect2(Vector2.ZERO, world.MAP_SIZE).encloses(destination))
		assert_gt(world.stairs_position.y, destination.end.y, "The player stands on the room floor below the attached ladder")
		assert_gt(world.stairs_position.distance_to(world.ordinary_chest_position), 58.0, "The exit interaction cannot accidentally open the chest")


func test_ladder_interaction_requires_floor_and_does_not_remove_the_wall_collision() -> void:
	var world: Node2D = _world()
	watch_signals(world)
	for level: int in range(3):
		world.reset_run(level)
		await get_tree().process_frame
		world._key_taken = true
		var wall_center: Vector2 = world.get_exit_visual()["destination"].get_center()
		world._handle_interaction_at(wall_center)
		assert_signal_emit_count(world, "exit_requested", level)
		world._handle_interaction_at(world.stairs_position)
		assert_signal_emit_count(world, "exit_requested", level + 1)
		assert_false(world.is_walkable(wall_center), "Using the ladder does not turn its supporting wall into a walkable cell")
		assert_eq(world.get_navigation_path(world.stairs_position, wall_center).size(), 0)


func test_chest_confirmation_and_rewards_remain_independent_of_simpler_map_art() -> void:
	var world: Node2D = _world()
	watch_signals(world)
	world._handle_interaction_at(world.sealed_chest_position)
	assert_signal_emit_count(world, "sealed_chest_requested", 1)
	assert_false(world._sealed_open, "The warning modal still chooses whether to open")
	world.confirm_sealed_chest()
	world.confirm_sealed_chest()
	assert_true(world._sealed_open)
	assert_signal_emit_count(world, "loot_collected", 0, "Confirmation does not duplicate controller-owned sealed rewards")
	world._handle_interaction_at(world.ordinary_chest_position)
	world._handle_interaction_at(world.ordinary_chest_position)
	assert_signal_emit_count(world, "loot_collected", 1)
	assert_eq(world.get_chest_visual("ordinary")["tint"], Color.WHITE)


func test_ladder_supporting_wall_keeps_a_physical_barrier_in_all_three_maps() -> void:
	var world: Node2D = _world()
	world.process_mode = Node.PROCESS_MODE_INHERIT
	world.set_physics_process(false)
	for level: int in range(3):
		world.reset_run(level)
		world.player.set_physics_process(false)
		for enemy: CharacterBody2D in world._enemies:
			enemy.set_physics_process(false)
		await get_tree().physics_frame
		var visual: Dictionary = world.get_exit_visual()
		var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
			world.to_global(world.stairs_position + Vector2(0, -12)),
			world.to_global(visual["wall_position"]), 1)
		var hit: Dictionary = world.get_world_2d().direct_space_state.intersect_ray(ray)
		assert_false(hit.is_empty(), "A real physics wall remains between the walkable interaction point and the ladder")
		if not hit.is_empty():
			assert_true(hit["collider"] is StaticBody2D)
			assert_eq(hit["collider"].collision_layer, 1)
