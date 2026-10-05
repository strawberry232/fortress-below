extends "res://addons/gut/test.gd"

const WorldScript = preload("res://game/scripts/defense/fortress_world.gd")
const STEP_SECONDS: float = 1.0 / 60.0

func after_each() -> void:
	for index: int in range(4):
		await get_tree().process_frame

func _world() -> WorldScript:
	var world: WorldScript = WorldScript.new()
	world.set_process(false)
	add_child_autofree(world)
	return world

func _supports_expansion(world: WorldScript) -> bool:
	assert_true(world.has_method("set_round_preview"))
	return world.has_method("set_round_preview")

func _start_round(world: WorldScript, alarm: bool, levels: Array[int], round_index: int) -> void:
	world.call("start_wave", alarm, levels, round_index)

func test_archer_feet_use_real_alpha_bounds_and_front_battlement_masks_legs() -> void:
	var world: WorldScript = _world()
	assert_true(world.has_method("get_tower_layers"))
	if not world.has_method("get_tower_layers"):
		return
	var tower_image: Image = world.textures["wood_tower"].get_image().get_region(Rect2i(0, 0, 256, 192))
	assert_eq(tower_image.get_used_rect(), Rect2i(63, 16, 130, 155))
	assert_true(world.textures.has("soldier_bow"))
	if not world.textures.has("soldier_bow"):
		return
	var archer_image: Image = world.textures["soldier_bow"].get_image()
	var idle_frame: Image = archer_image.get_region(Rect2i(0, 0, 100, 100))
	assert_eq(idle_frame.get_used_rect(), Rect2i(41, 39, 19, 21))
	for slot: int in range(world.tower_points.size()):
		var layers: Array = world.get_tower_layers(slot)
		assert_eq(layers.size(), 3)
		assert_eq(layers[0]["texture_key"], "wood_tower")
		assert_eq(layers[1]["texture_key"], "soldier_bow")
		assert_eq(layers[2]["texture_key"], "wood_tower")
		var archer_rect: Rect2 = layers[1]["destination"]
		var tower_rect: Rect2 = layers[0]["destination"]
		var foot: Vector2 = archer_rect.position + Vector2(50, 60) * (archer_rect.size.x / 100.0)
		var platform: Vector2 = tower_rect.position + Vector2(128, 75)
		assert_almost_eq(foot.x, platform.x, 0.01)
		assert_almost_eq(foot.y, platform.y, 0.01)
		var front: Rect2 = layers[2]["destination"]
		assert_lt(front.position.y, foot.y, "Front battlement covers the standing feet")
		var visible_head_y: float = archer_rect.position.y + 39 * archer_rect.size.y / 100.0
		assert_lt(visible_head_y, front.position.y - 30.0, "The visible torso remains above the battlement")

func test_idle_defense_does_not_create_worker_or_delivery_feedback() -> void:
	var world: WorldScript = _world()
	watch_signals(world)
	assert_false(world.has_method("play_supply_delivery"))
	assert_true(world.find_children("*", "AnimatedSprite2D", true, false).is_empty(), "No worker sprite exists")
	for step: int in range(600):
		world._process(STEP_SECONDS)
	assert_true(world.find_children("*", "AnimatedSprite2D", true, false).is_empty(), "Idle updates cannot create a worker sprite")
	assert_signal_not_emitted(world, "feedback_requested")

func test_combat_has_no_worker_and_original_tree_texture_is_preserved() -> void:
	var world: WorldScript = _world()
	watch_signals(world)
	world.start_wave(false, [0, 0, 0, 0, 0, 0])
	world._process(8.0)
	assert_true(world.find_children("*", "AnimatedSprite2D", true, false).is_empty(), "Combat cannot create a worker sprite")
	assert_true(world.textures.has("tree"))
	assert_eq(world.get_tree_visuals().size(), 3)
	assert_signal_not_emitted(world, "feedback_requested")

func test_archer_facing_flip_preserves_platform_rectangle_origin() -> void:
	var world: WorldScript = _world()
	if not _supports_expansion(world):
		return
	var right: Rect2 = world.get_tower_layers(0)[1]["destination"]
	world.archer_facing_left[0] = true
	var left: Rect2 = world.get_tower_layers(0)[1]["destination"]
	assert_eq(left.position, right.position, "Canvas flipping must not move the sprite away from its tower")
	assert_eq(absf(left.size.x), right.size.x)

func test_early_orcs_use_original_tiny_rpg_textures_and_nearest_pixel_filter() -> void:
	var world: WorldScript = _world()
	assert_eq(world.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	var definition: Dictionary = world.get_enemy_definition("orc")
	assert_eq(definition["frame_size"], Vector2i(100, 100))
	assert_eq(definition["display_scale"], 3.0)
	assert_eq(definition["foot_anchor"], Vector2(50, 60))
	assert_eq(definition["animations"]["walk"]["paths"], ["res://game/assets/tiny_rpg/orc_walk.png"])
	assert_eq(world.get_enemy_definition("torch"), {})
	assert_eq(world.get_enemy_definition("tnt"), {})
	assert_false(world.textures.has("torch"))
	assert_false(world.textures.has("tnt"))

func test_ground_depth_puts_rear_road_enemies_behind_tall_towers() -> void:
	var world: WorldScript = _world()
	assert_true(world.has_method("get_draw_order"))
	if not world.has_method("get_draw_order"):
		return
	world.start_wave(false, [1, 1])
	world._spawn_enemy()
	world._spawn_enemy()
	world.enemies[1]["pos"] = Vector2(550, 330)
	world.enemies[2]["pos"] = Vector2(550, 470)
	var actors: Array = world.get_draw_order()
	var rear_enemy_index: int = -1
	var front_enemy_index: int = -1
	var lower_tower_index: int = -1
	var castle_index: int = -1
	for index: int in range(actors.size()):
		var actor: Dictionary = actors[index]
		if actor["type"] == "castle":
			castle_index = index
		elif actor["type"] == "tower" and actor["slot"] == 1:
			lower_tower_index = index
		elif actor["type"] == "enemy":
			if actor["id"] == 1:
				rear_enemy_index = index
			else:
				front_enemy_index = index
	assert_gte(rear_enemy_index, 0)
	assert_gt(lower_tower_index, rear_enemy_index)
	assert_gt(front_enemy_index, lower_tower_index)
	assert_lt(castle_index, rear_enemy_index, "Enemies at the castle front remain visible")

func test_later_round_alarm_is_not_free_with_one_starter_tower() -> void:
	var world: WorldScript = _world()
	if not _supports_expansion(world):
		return
	for round_value: int in range(2, 4):
		var hp: Array[int] = [100]
		var completed: Array[int] = [0]
		var damage_handler: Callable = func(amount: int) -> void:
			hp[0] = maxi(0, hp[0] - amount)
			if hp[0] == 0:
				world.running = false
		var completion_handler: Callable = func() -> void: completed[0] += 1
		world.castle_damaged.connect(damage_handler)
		world.wave_completed.connect(completion_handler)
		_start_round(world, true, [1, 0], round_value)
		var elapsed: float = 0.0
		while world.running and elapsed < 120.0:
			world._process(STEP_SECONDS)
			elapsed += STEP_SECONDS
		assert_false(world.running)
		assert_eq(hp[0], 0)
		assert_eq(completed[0], 0)
		print("EXPANSION_DEFENSE_FAILURE " + JSON.stringify({"round": round_value, "hp": hp[0], "seconds": snappedf(elapsed, 0.01)}))
		world.castle_damaged.disconnect(damage_handler)
		world.wave_completed.disconnect(completion_handler)

func test_editable_spawn_interval_applies_to_first_round_and_later_rounds() -> void:
	var world: WorldScript = _world()
	if not _supports_expansion(world):
		return
	assert_not_null(world.balance.get("later_round_spawn_intervals"))
	if world.balance.get("later_round_spawn_intervals") == null:
		return
	world.balance.spawn_interval = 5.0
	world.start_wave(false, [0, 0])
	world._process(world.balance.first_spawn_delay)
	assert_eq(world.spawn_clock, 5.0)
	var intervals: Array[float] = [4.0, 3.5]
	world.balance.set("later_round_spawn_intervals", intervals)
	_start_round(world, false, [0, 0], 2)
	world._process(world.balance.first_spawn_delay)
	assert_eq(world.spawn_clock, 4.0)
	_start_round(world, false, [0, 0], 3)
	world._process(world.balance.first_spawn_delay)
	assert_eq(world.spawn_clock, 3.5)

func test_second_and_third_round_use_two_bent_roads_and_progress_targeting() -> void:
	var world: WorldScript = _world()
	if not _supports_expansion(world):
		return
	world.set_round_preview(2)
	var routes: Array = world.get_route_preview()
	assert_eq(routes.size(), 2)
	assert_ne(routes[0]["points"][0].y, routes[1]["points"][0].y)
	for route: Dictionary in routes:
		var points: PackedVector2Array = route["points"]
		assert_gte(points.size(), 4)
		var changes_y: bool = false
		for index: int in range(1, points.size()):
			changes_y = changes_y or points[index].y != points[index - 1].y
			var samples: int = ceili(points[index].distance_to(points[index - 1]) / 8.0)
			for sample_index: int in range(samples + 1):
				var position_on_road: Vector2 = points[index - 1].lerp(points[index], (sample_index as float) / maxi(1, samples))
				for footprint: Rect2 in world.get_building_footprints():
					assert_false(footprint.has_point(position_on_road), "Road avoids building ground footprints")
		assert_true(changes_y)
	_start_round(world, false, [1, 1], 2)
	world._spawn_enemy()
	world._spawn_enemy()
	assert_ne(world.enemies[1]["route_id"], world.enemies[2]["route_id"])
	world.enemies[1]["pos"] = Vector2(520, 330)
	world.enemies[1]["progress"] = 0.2
	world.enemies[2]["pos"] = Vector2(400, 330)
	world.enemies[2]["progress"] = 0.8
	assert_eq(world._choose_target(world.tower_points[0]), 2, "Closest to the exit wins even when its x coordinate is smaller")
	world.selected_enemy = 1
	assert_eq(world._choose_target(world.tower_points[0]), 1)

func test_enemies_follow_each_waypoint_without_cutting_corners() -> void:
	var world: WorldScript = _world()
	if not _supports_expansion(world):
		return
	_start_round(world, false, [0, 0], 2)
	world._spawn_enemy()
	var visited: Dictionary = {}
	var route: PackedVector2Array = world.get_route_preview()[0]["points"]
	for step: int in range(1800):
		world._update_enemies(STEP_SECONDS)
		var enemy: Dictionary = world.enemies[1]
		var pos: Vector2 = enemy["pos"]
		for index: int in range(route.size()):
			if pos.distance_to(route[index]) < 1.0:
				visited[index] = true
		var on_segment: bool = false
		for index: int in range(1, route.size()):
			on_segment = on_segment or Geometry2D.get_closest_point_to_segment(pos, route[index - 1], route[index]).distance_to(pos) < 0.01
		assert_true(on_segment, "Movement remains on the visible road")
		if enemy["progress"] >= 1.0:
			break
	for index: int in range(1, route.size()):
		assert_true(visited.has(index), "Every later waypoint was visited")

func test_real_later_waves_complete_with_affordable_tower_progression() -> void:
	var world: WorldScript = _world()
	if not _supports_expansion(world):
		return
	for round_index: int in range(2, 4):
		for alarm: bool in [false, true]:
			var hp: Array[int] = [100]
			var completed: Array[int] = [0]
			var damage_handler: Callable = func(amount: int) -> void:
				hp[0] = maxi(0, hp[0] - amount)
				if hp[0] == 0:
					world.running = false
			var completion_handler: Callable = func() -> void: completed[0] += 1
			world.castle_damaged.connect(damage_handler)
			world.wave_completed.connect(completion_handler)
			var levels: Array[int] = [2, 1]
			if round_index == 3:
				if alarm:
					levels = [2, 1, 1, 1]
				else:
					levels = [2, 2]
			var spending: int = 0
			for slot: int in range(levels.size()):
				if slot > 0 and levels[slot] > 0:
					spending += 25
				if levels[slot] == 2:
					spending += 35
			assert_lte(spending, 20 + round_index * 25 + (20 if alarm else 0), "The strategy is affordable even without taking seals in earlier rounds")
			_start_round(world, alarm, levels, round_index)
			var seen: Dictionary = {}
			var route_ids: Dictionary = {}
			var alarm_kind: String = world.ledger.alarm_enemy_kind(round_index)
			var expected_alarm_count: int = world.ledger.pending.count(alarm_kind)
			var alarm_kind_count: int = 0
			var used_rally: bool = false
			var firepower_uses: int = 0
			var elapsed: float = 0.0
			while world.running and elapsed < 120.0:
				world._process(STEP_SECONDS)
				elapsed += STEP_SECONDS
				for id: int in world.enemies:
					if not seen.has(id):
						seen[id] = true
						route_ids[world.enemies[id]["route_id"]] = true
						if world.enemies[id]["kind"] == alarm_kind:
							alarm_kind_count += 1
				if not world.arrows.is_empty() and world.ledger.rally_cooldown_left <= 0.0:
					if world.activate_rally():
						used_rally = true
						firepower_uses += 1
			assert_false(world.running)
			assert_gt(hp[0], 0)
			assert_eq(completed[0], 1)
			assert_eq(seen.size(), 4 + round_index * 2 + (1 if alarm else 0))
			assert_eq(alarm_kind_count, expected_alarm_count)
			assert_eq(route_ids.size(), 2)
			assert_eq(world.remaining_enemies(), 0)
			assert_gt(firepower_uses, 1, "Affordable later defenses use the reusable firepower cooldown against revived elites")
			print("EXPANSION_DEFENSE_RESULT " + JSON.stringify({"round": round_index, "alarm": alarm, "hp": hp[0], "seconds": snappedf(elapsed, 0.01), "levels": levels, "rally": used_rally, "firepower_uses": firepower_uses}))
			world.castle_damaged.disconnect(damage_handler)
			world.wave_completed.disconnect(completion_handler)

func test_prepare_after_failure_clears_enemies_arrows_selection_rally_and_ledger() -> void:
	var world: WorldScript = _world()
	if not _supports_expansion(world):
		return
	_start_round(world, true, [1, 1], 3)
	world._spawn_enemy()
	world.selected_enemy = 1
	world.activate_rally()
	world.arrows.append({"pos": Vector2.ZERO, "target": 1, "damage": 8})
	world.prepare([1, 0])
	assert_false(world.running)
	assert_eq(world.remaining_enemies(), 0)
	assert_eq(world.arrows.size(), 0)
	assert_eq(world.selected_enemy, -1)
	assert_eq(world.rally_seconds, 0.0)
	assert_false(world.ledger.is_complete())
	_start_round(world, false, [1, 0], 3)
	assert_eq(world.remaining_enemies(), 10)
	assert_true(world.activate_rally())

func test_prepare_and_retry_remain_silent_without_delivery_system() -> void:
	var world: WorldScript = _world()
	watch_signals(world)
	world.prepare([1, 0, 0, 0, 0, 0])
	world._process(6.0)
	assert_true(world.find_children("*", "AnimatedSprite2D", true, false).is_empty(), "Preparation cannot create a worker sprite")
	assert_false(world.has_method("play_supply_delivery"))
	assert_signal_not_emitted(world, "feedback_requested")

func test_build_hit_death_feedback_use_global_positions_and_do_not_repeat() -> void:
	var world: WorldScript = _world()
	assert_true(world.has_signal("feedback_requested"))
	if not world.has_signal("feedback_requested"):
		return
	world.position = Vector2(40, 70)
	var feedback: Array[Dictionary] = []
	world.feedback_requested.connect(func(event: String, at: Vector2) -> void: feedback.append({"event": event, "at": at}))
	var build_position: Vector2 = Vector2(500, 200)
	world.emit_build_feedback(build_position)
	assert_eq(feedback, [{"event": "build", "at": build_position}])
	world.start_wave(false, [1, 0])
	world._spawn_enemy()
	world.enemies[1]["pos"] = Vector2(400, 330)
	world.enemies[1]["hp"] = 8
	world._update_towers(0.0)
	world._update_arrows(1.0)
	world._update_arrows(1.0)
	assert_eq(feedback.size(), 4)
	assert_eq(feedback[1]["event"], "tower_shot")
	assert_eq(feedback[2], {"event": "enemy_hit", "at": Vector2(440, 382)})
	assert_eq(feedback[3], {"event": "enemy_death", "at": Vector2(440, 400)})

func test_feedback_and_archer_shoot_animation_share_real_muzzle() -> void:
	var world: WorldScript = _world()
	assert_true(world.has_signal("feedback_requested"))
	if not world.has_signal("feedback_requested"):
		return
	world.position = Vector2(50, 80)
	watch_signals(world)
	world.start_wave(false, [1, 0])
	world._spawn_enemy()
	world.enemies[1]["pos"] = Vector2(400, 330)
	world._update_towers(0.0)
	assert_eq(world.arrows[0]["pos"], world.get_archer_muzzle(0))
	assert_gt(absf(world.arrows[0].get("angle", 0.0)), PI / 2.0, "Arrow artwork faces its real left-side target")
	assert_signal_emitted_with_parameters(world, "feedback_requested", ["tower_shot", world.to_global(world.get_archer_muzzle(0))])
	assert_gt(world.get("archer_shoot_seconds")[0], 0.0)
	world._process(1.0)
	assert_signal_emitted(world, "feedback_requested")
	world.prepare([1, 0])
	assert_eq(world.get("archer_shoot_seconds")[0], 0.0)
