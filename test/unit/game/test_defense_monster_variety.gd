extends "res://addons/gut/test.gd"

const WorldScript = preload("res://game/scripts/defense/fortress_world.gd")
const LedgerScript = preload("res://game/scripts/defense/wave_ledger.gd")

func _world() -> WorldScript:
	var world: WorldScript = WorldScript.new()
	world.set_process(false)
	add_child_autofree(world)
	return world

func after_each() -> void:
	for index: int in range(4):
		await get_tree().process_frame

func test_six_towers_and_all_runtime_arrays_follow_slot_count() -> void:
	var world: WorldScript = _world()
	assert_eq(world.tower_points.size(), 6)
	world.prepare([1, 0, 1, 2, 1, 2])
	assert_eq(world.tower_levels, [1, 0, 1, 2, 1, 2])
	assert_eq(world.tower_clocks.size(), 6)
	assert_eq(world.archer_shoot_seconds.size(), 6)
	assert_eq(world.archer_facing_left.size(), 6)
	var slots: Array[int] = []
	for actor: Dictionary in world.get_draw_order():
		if actor["type"] == "tower":
			slots.append(actor["slot"])
	slots.sort()
	assert_eq(slots, [0, 2, 3, 4, 5])

func test_short_and_invalid_level_arrays_normalize_without_stale_slots() -> void:
	var world: WorldScript = _world()
	world.prepare([2, -1, 99])
	assert_eq(world.tower_levels, [2, 0, 2, 0, 0, 0])
	world.prepare([])
	assert_eq(world.tower_levels, [0, 0, 0, 0, 0, 0])
	world.prepare([1, 1, 1, 1, 1, 1, 2])
	assert_eq(world.tower_levels.size(), 6)

func test_worker_and_delivery_are_removed_but_original_trees_remain() -> void:
	var world: WorldScript = _world()
	assert_false(world.has_method("play_supply_delivery"))
	assert_true(world.find_children("*", "AnimatedSprite2D", true, false).is_empty(), "No worker sprite exists")
	assert_eq(world.get("worker"), null)
	assert_true(world.textures.has("tree"))
	assert_eq(world.textures["tree"].resource_path, "res://game/assets/tiny_swords/tree.png")
	assert_true(world.has_method("get_tree_visuals"))
	if world.has_method("get_tree_visuals"):
		assert_eq(world.call("get_tree_visuals").size(), 3)

func test_archer_is_three_times_original_size_with_all_feet_and_muzzles_aligned() -> void:
	var world: WorldScript = _world()
	assert_eq(world.balance.archer_scale, 3.0)
	world.prepare([1, 1, 1, 1, 1, 1])
	for slot: int in range(world.tower_points.size()):
		for facing: bool in [false, true]:
			world.archer_facing_left[slot] = facing
			var layers: Array[Dictionary] = world.get_tower_layers(slot)
			var platform: Vector2 = layers[0]["destination"].position + Vector2(128, 75)
			assert_eq(layers[1]["destination"].position + Vector2(150, 180), platform)
			assert_eq(layers[1]["destination"].size, Vector2(-300 if facing else 300, 300))
			assert_eq(world.get_archer_muzzle(slot), platform + Vector2(-24 if facing else 24, -30))
			assert_lt(layers[2]["destination"].position.y, platform.y)

func test_invalid_tower_visual_requests_are_bounded() -> void:
	var world: WorldScript = _world()
	assert_eq(world.get_tower_layers(-1), [])
	assert_eq(world.get_tower_layers(6), [])
	assert_eq(world.get_archer_muzzle(-1), Vector2.ZERO)
	assert_eq(world.get_archer_muzzle(6), Vector2.ZERO)

func test_alarm_kind_metadata_matches_actual_single_added_pending_enemy() -> void:
	var ledger: RefCounted = LedgerScript.new()
	assert_true(ledger.has_method("alarm_enemy_kind"))
	assert_true(ledger.has_method("alarm_enemy_count"))
	if not ledger.has_method("alarm_enemy_kind") or not ledger.has_method("alarm_enemy_count"):
		return
	for round_value: int in range(1, 4):
		ledger.begin_wave(false, round_value)
		var normal: Array[String] = ledger.pending.duplicate()
		ledger.begin_wave(true, round_value)
		assert_eq(ledger.pending.size(), normal.size() + 1)
		assert_eq(ledger.pending.slice(0, normal.size()), normal)
		assert_eq(ledger.pending.back(), ledger.call("alarm_enemy_kind", round_value))
		assert_eq(ledger.call("alarm_enemy_count", round_value), 1)
		assert_true(["skeleton", "armored_skeleton", "skull", "vampire"].has(ledger.pending.back()))

func test_later_rounds_have_progressive_dungeon_pack_variety() -> void:
	var ledger: RefCounted = LedgerScript.new()
	for round_value: int in range(1, 4):
		ledger.begin_wave(false, round_value)
		var kinds: Dictionary = {}
		for kind: String in ledger.pending:
			kinds[kind] = true
		assert_eq(ledger.pending.size(), 4 + round_value * 2)
		if round_value == 1:
			assert_true(kinds.has("orc"))
		else:
			assert_false(kinds.has("orc"))
			assert_false(kinds.has("tnt"))
			assert_gte(kinds.size(), 3 if round_value == 2 else 4)

func test_every_declared_enemy_spawns_with_definition_and_preserves_kind() -> void:
	var world: WorldScript = _world()
	assert_true(world.has_method("get_enemy_definition"))
	if not world.has_method("get_enemy_definition"):
		return
	for kind: String in ["orc", "slime", "skeleton", "armored_skeleton", "skull", "vampire"]:
		world.start_wave(false, [0, 0, 0, 0, 0, 0], 3)
		world.ledger.pending.clear()
		world.ledger.pending.append(kind)
		world._spawn_enemy()
		var enemy: Dictionary = world.enemies[1]
		var definition: Dictionary = world.call("get_enemy_definition", kind)
		assert_eq(enemy["kind"], kind)
		assert_eq(enemy["hp"], definition["health"])
		assert_eq(enemy["speed"], definition["speed"])
		assert_eq(enemy["castle_damage"], definition["damage"])
		assert_gt(enemy["health_bar_offset"], 0.0)
		world._update_enemies(0.25)
		assert_gt(enemy["pos"].distance_to(enemy["points"][0]), 0.0)
	assert_eq(world.call("get_enemy_definition", "unknown"), {})

func test_final_tower_slot_shoots_once_with_original_damage_and_cooldown() -> void:
	var world: WorldScript = _world()
	world.start_wave(false, [0, 0, 0, 0, 0, 1], 2)
	world._spawn_enemy()
	world.enemies[1]["pos"] = Vector2(370, 466)
	world._update_towers(0.0)
	assert_eq(world.arrows.size(), 1)
	if world.arrows.size() == 1:
		assert_eq(world.arrows[0]["pos"], world.get_archer_muzzle(5))
		assert_eq(world.arrows[0]["damage"], 8)
		assert_almost_eq(world.tower_clocks[5], 0.9, 0.0001)
	world._update_towers(0.0)
	assert_eq(world.arrows.size(), 1)

func test_all_tower_ground_footprints_avoid_every_round_road_and_each_other() -> void:
	var world: WorldScript = _world()
	assert_eq(world.get_building_footprints().size(), 7)
	for round_value: int in range(1, 4):
		world.set_round_preview(round_value)
		for route: Dictionary in world.get_route_preview():
			var points: PackedVector2Array = route["points"]
			for index: int in range(1, points.size()):
				var count: int = ceili(points[index - 1].distance_to(points[index]) / 12.0)
				for sample_index: int in range(count + 1):
					var point: Vector2 = points[index - 1].lerp(points[index], (sample_index as float) / maxi(1, count))
					var footprints_on_route: Array[Rect2] = world.get_building_footprints()
					for footprint_index: int in range(footprints_on_route.size()):
						var footprint: Rect2 = footprints_on_route[footprint_index]
						if footprint_index < world.tower_points.size():
							footprint = footprint.grow(world.ROAD_HALF_WIDTH)
						assert_false(footprint.has_point(point))
	var footprints: Array[Rect2] = world.get_building_footprints()
	for index: int in range(footprints.size()):
		for previous: int in range(index):
			assert_false(footprints[index].intersects(footprints[previous]))

func test_original_alpha_bounds_of_towers_archers_and_trees_do_not_overlap() -> void:
	var world: WorldScript = _world()
	var tower_alpha: Rect2i = world.textures["wood_tower"].get_image().get_region(Rect2i(0, 0, 256, 192)).get_used_rect()
	var tree_alpha: Rect2i = world.textures["tree"].get_image().get_region(Rect2i(0, 0, 192, 192)).get_used_rect()
	var sprites: Array[Rect2] = []
	for slot: int in range(world.tower_points.size()):
		var layers: Array[Dictionary] = world.get_tower_layers(slot)
		var tower_bounds: Rect2 = Rect2(layers[0]["destination"].position + Vector2(tower_alpha.position), Vector2(tower_alpha.size))
		var archer_bounds: Rect2 = Rect2(layers[1]["destination"].position + Vector2(41, 39) * 3.0, Vector2(19, 21) * 3.0)
		sprites.append(tower_bounds.merge(archer_bounds))
	for index: int in range(sprites.size()):
		for previous: int in range(index):
			assert_false(sprites[index].intersects(sprites[previous]))
		for tree: Dictionary in world.get_tree_visuals():
			var tree_bounds: Rect2 = Rect2(tree["destination"].position + Vector2(tree_alpha.position), Vector2(tree_alpha.size))
			assert_false(sprites[index].intersects(tree_bounds))

func test_unknown_spawn_kind_is_rejected_without_leaving_an_alive_blocker() -> void:
	var world: WorldScript = _world()
	world.start_wave(false, [])
	world.ledger.pending.clear()
	world.ledger.pending.append("unknown")
	world._spawn_enemy()
	assert_eq(world.enemies.size(), 0)
	assert_eq(world.ledger.alive.size(), 0)
	assert_true(world.ledger.pending.is_empty())
	assert_true(world.ledger.is_complete())

func test_alarm_metadata_and_invalid_round_sizes_are_bounded() -> void:
	var ledger: RefCounted = LedgerScript.new()
	assert_eq(ledger.alarm_enemy_kind(-50), "armored_skeleton")
	assert_eq(ledger.alarm_enemy_kind(99), "vampire")
	var invalid_sizes: Array[int] = [-1, 0, -2]
	ledger.begin_wave(true, -4, invalid_sizes)
	assert_eq(ledger.pending, ["orc", "armored_skeleton"])
	var empty_sizes: Array[int] = []
	ledger.begin_wave(false, 99, empty_sizes)
	assert_eq(ledger.pending.size(), 10)
	assert_true(ledger.pending.has("vampire"))

func test_catalog_varieties_use_distinct_speed_and_actual_castle_damage() -> void:
	var world: WorldScript = _world()
	var damages: Array[int] = []
	world.castle_damaged.connect(func(amount: int) -> void: damages.append(amount))
	for kind: String in ["skeleton", "armored_skeleton", "skull", "vampire"]:
		world.start_wave(false, [])
		world.ledger.pending.clear()
		world.ledger.pending.append(kind)
		world._spawn_enemy()
		var definition: Dictionary = world.get_enemy_definition(kind)
		world._update_enemies(1.0)
		assert_almost_eq(world.enemies[1]["traveled"], definition["speed"], 0.0001)
		world.enemies[1]["pos"] = world.enemies[1]["points"][-1]
		world.enemies[1]["arrived"] = true
		var first_window: Vector2 = load("res://game/data/monsters/monster_catalog.gd").attack_windows(kind)[0]
		world.enemies[1]["clock"] = first_window.x - 0.01
		world._set_enemy_action(world.enemies[1], "attack", true)
		world.enemies[1]["action_elapsed"] = first_window.x - 0.01
		world._update_enemies(0.02)
		assert_eq(damages[-1], definition["damage"])
	assert_eq(damages, [10, 18, 8, 20])

func test_six_built_towers_fire_and_kill_one_enemy_without_double_death_events() -> void:
	var world: WorldScript = _world()
	world.start_wave(false, [1, 1, 1, 1, 1, 1])
	world._spawn_enemy()
	world.enemies[1]["pos"] = Vector2(400, 330)
	var feedback: Array[String] = []
	world.feedback_requested.connect(func(event: String, _at: Vector2) -> void: feedback.append(event))
	world._update_towers(0.0)
	assert_eq(world.arrows.size(), 6)
	assert_eq(feedback.count("tower_shot"), 6)
	for clock: float in world.tower_clocks:
		assert_almost_eq(clock, 0.9, 0.0001)
	world._update_arrows(1.0)
	assert_false(world.enemies.has(1))
	assert_eq(world.arrows.size(), 0)
	assert_eq(world.ledger.alive.size(), 0)
	assert_eq(feedback.count("enemy_death"), 1)
	world._update_arrows(1.0)
	assert_eq(feedback.count("enemy_death"), 1)

func test_prepare_and_start_wave_accept_the_worlds_own_level_array_without_erasing_it() -> void:
	var world: WorldScript = _world()
	var expected: Array[int] = [1, 1, 2, 0, 0, 1]
	world.prepare(expected)
	world.prepare(world.tower_levels)
	assert_eq(world.tower_levels, expected)
	world.start_wave(false, world.tower_levels, 2)
	assert_eq(world.tower_levels, expected)
	assert_eq(world.ledger.pending.size(), 8)
