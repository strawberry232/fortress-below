extends "res://addons/gut/test.gd"

const DEFENSE: Script = preload("res://game/scripts/defense/fortress_world.gd")


func _world(kind: String = "vampire", arrived: bool = false) -> Node2D:
	var world: Node2D = DEFENSE.new()
	add_child_autofree(world)
	world.set_process(false)
	var levels: Array[int] = [0, 0, 0, 0, 0, 0]
	world.start_wave(false, levels, 3)
	world.ledger.pending.assign([kind])
	world._spawn_enemy()
	var enemy: Dictionary = world.enemies[1]
	enemy["pos"] = Vector2(200, 245)
	enemy["traveled"] = 184.0
	enemy["progress"] = enemy["traveled"] / enemy["path_length"]
	if arrived:
		enemy["pos"] = enemy["points"][-1]
		enemy["traveled"] = enemy["path_length"]
		enemy["progress"] = 1.0
		enemy["waypoint"] = enemy["points"].size()
		world._update_enemies(0.0)
	return world


func _hit(world: Node2D, damage: int, enemy_id: int = 1) -> void:
	var enemy: Dictionary = world.enemies[enemy_id]
	world.arrows.append({"pos": enemy["pos"] - Vector2(0, 18), "target": enemy_id, "damage": damage})
	world._update_arrows(0.01)


func _first_defeat(world: Node2D) -> bool:
	_hit(world, world.enemies[1]["max_hp"] + 1)
	assert_true(world.enemies.has(1), "First defeat keeps the same vampire in the active ledger")
	return world.enemies.has(1)


func test_first_defeat_retains_identity_route_and_wave_obligation() -> void:
	var world: Node2D = _world()
	var enemy: Dictionary = world.enemies[1]
	var initial: Dictionary = enemy.duplicate(true)
	if not _first_defeat(world):
		return
	assert_true(world.ledger.alive.has(1))
	assert_false(world.ledger.is_complete())
	assert_eq(world.remaining_enemies(), 1)
	assert_eq(world.corpses.size(), 0, "Temporary ashes use the existing actor, not a final corpse")
	assert_eq(enemy["hp"], 0)
	assert_eq(enemy["pos"], initial["pos"])
	for key: String in ["route_id", "waypoint", "traveled", "path_length", "progress", "arrived", "facing_left"]:
		assert_eq(enemy[key], initial[key], "Temporary defeat preserves " + key)
	assert_eq(enemy["action"], "death")
	assert_eq(enemy["hurt_left"], 0.0)
	assert_true(enemy.has("revival"))
	if enemy.has("revival"):
		assert_true(enemy["revival"].pending)
		assert_eq(enemy["revival"].lives_left, 1)


func test_ashes_keep_original_last_frame_and_reverse_without_targeting_or_motion() -> void:
	var world: Node2D = _world()
	if not _first_defeat(world):
		return
	var enemy: Dictionary = world.enemies[1]
	var stopped_at: Vector2 = enemy["pos"]
	world.ledger.pending.assign(["orc"])
	world._spawn_enemy()
	world.enemies[2]["pos"] = stopped_at
	world.selected_enemy = 1
	assert_eq(world._choose_target(stopped_at), 2, "A selected ash pile cannot steal arrows from a living enemy")
	_hit(world, 500)
	assert_eq(enemy["hp"], 0)
	assert_eq(world.arrows.size(), 0, "An arrow already in flight is discarded when its target becomes ashes")
	world._update_enemies(1.41)
	assert_eq(enemy["pos"], stopped_at)
	assert_true(world.has_method("get_enemy_visual"))
	if not world.has_method("get_enemy_visual"):
		return
	var ashes: Dictionary = world.get_enemy_visual(enemy)
	assert_false(ashes["show_health_bar"])
	assert_eq(ashes["sample"]["frame"], 13, "The original fourteenth frame stays visible as ashes")
	assert_eq(ashes["sample"]["phase"], "ashes")
	world._update_enemies(2.99)
	world._update_enemies(0.7)
	var rising: Dictionary = world.get_enemy_visual(enemy)
	assert_eq(rising["sample"]["phase"], "reforming")
	assert_lt(rising["sample"]["frame"], 13, "Reverse playback moves toward a whole body")
	assert_gt(rising["sample"]["frame"], 0)
	assert_eq(enemy["pos"], stopped_at)
	assert_eq(enemy["hp"], 0)
	assert_eq(world.corpses.size(), 0)
	assert_eq(world._choose_target(stopped_at), 2)


func test_castle_vampire_recovers_full_health_after_reverse_then_starts_new_windup() -> void:
	var world: Node2D = _world("vampire", true)
	var received: Array[int] = []
	world.castle_damaged.connect(func(amount: int) -> void: received.append(amount))
	var enemy: Dictionary = world.enemies[1]
	var stopped_at: Vector2 = enemy["pos"]
	if not _first_defeat(world):
		return
	world._update_enemies(5.79)
	assert_eq(received.size(), 0)
	assert_eq(enemy["hp"], 0)
	world._update_enemies(0.02)
	assert_eq(received.size(), 0, "Completing resurrection does not spend leftover delta on a castle attack")
	assert_eq(enemy["hp"], 110, "The second life starts at the full original elite health")
	assert_eq(enemy["max_hp"], 110)
	assert_eq(enemy["pos"], stopped_at)
	assert_true(world.ledger.alive.has(1))
	assert_false(enemy["revival"].pending)
	assert_eq(enemy["revival"].lives_left, 1)
	assert_eq(enemy["clock"], 0.0)
	assert_eq(enemy["action_elapsed"], 0.0)
	assert_false(enemy["attack_applied"])
	assert_true(enemy.get("applied_hits", {}).is_empty())
	_hit(world, 500)
	assert_eq(enemy["hp"], 110, "Short resurrection protection prevents same-frame arrow bursts")
	world._update_enemies(0.34)
	assert_eq(received.size(), 0)
	world._update_enemies(0.07)
	world._update_enemies(0.0)
	world._update_enemies(0.39)
	assert_eq(received.size(), 0, "The second life must telegraph a fresh attack")
	world._update_enemies(0.02)
	assert_eq(received, [20])
	var visual: Dictionary = world.get_enemy_visual(enemy)
	assert_true(visual["show_health_bar"])
	assert_eq(visual["lives_left"], 1)


func test_second_defeat_is_final_once_and_wave_waits_for_the_final_corpse() -> void:
	var world: Node2D = _world()
	var completed: Array[bool] = []
	world.wave_completed.connect(func() -> void: completed.append(true))
	if not _first_defeat(world):
		return
	world._update_enemies(10.0)
	assert_eq(world.enemies[1]["hp"], 110)
	world._update_enemies(0.36)
	_hit(world, 111)
	assert_false(world.enemies.has(1))
	assert_false(world.ledger.alive.has(1))
	assert_eq(world.corpses.size(), 1)
	assert_eq(world.remaining_enemies(), 0)
	assert_true(world.ledger.is_complete())
	world._process(0.0)
	assert_eq(completed.size(), 0, "Final death animation still finishes before wave completion")
	world._process(1.7)
	assert_eq(world.corpses.size(), 0)
	assert_eq(completed.size(), 1)
	assert_false(world.running)
	world._process(10.0)
	assert_eq(completed.size(), 1)
	assert_eq(world.enemies.size(), 0, "There is no third life")


func test_prepare_cancels_old_revival_and_new_wave_resets_two_lives() -> void:
	var world: Node2D = _world()
	if not _first_defeat(world):
		return
	world._update_enemies(2.0)
	var levels: Array[int] = [0, 0, 0, 0, 0, 0]
	world.prepare(levels)
	world._update_enemies(10.0)
	assert_eq(world.enemies.size(), 0)
	assert_eq(world.corpses.size(), 0)
	assert_eq(world.arrows.size(), 0)
	assert_false(world.running)
	assert_false(world.ledger.initialized)
	world.start_wave(false, levels, 3)
	world.ledger.pending.assign(["vampire"])
	world._spawn_enemy()
	assert_eq(world.enemies[1]["hp"], 110)
	assert_eq(world.enemies[1]["revival"].lives_left, 2)
	assert_false(world.enemies[1]["revival"].pending)
	assert_eq(world.get_enemy_visual(world.enemies[1])["lives_left"], 2)


func test_other_species_have_one_life_and_keep_their_original_final_death() -> void:
	for kind: String in ["orc", "skeleton", "armored_skeleton", "skull", "slime"]:
		var world: Node2D = _world(kind)
		_hit(world, world.enemies[1]["max_hp"] + 1)
		assert_eq(world.enemies.size(), 0, kind + " remains a single-life tower-defense enemy")
		assert_false(world.ledger.alive.has(1))
		assert_eq(world.corpses.size(), 1)
		assert_eq(world.corpses[0]["kind"], kind)


func test_negative_time_and_paused_world_do_not_advance_revival() -> void:
	var world: Node2D = _world()
	if not _first_defeat(world):
		return
	var enemy: Dictionary = world.enemies[1]
	world._update_enemies(-10.0)
	assert_eq(enemy["revival"].elapsed, 0.0)
	assert_eq(enemy["hp"], 0)
	world.running = false
	world._process(10.0)
	assert_eq(enemy["revival"].elapsed, 0.0, "A stopped wave cannot resurrect old enemies")
	assert_eq(enemy["hp"], 0)


func test_arrow_damage_rejects_nonpositive_values_without_healing_or_staggering() -> void:
	var world: Node2D = _world()
	var enemy: Dictionary = world.enemies[1]
	for damage: int in [0, -10]:
		_hit(world, damage)
		assert_eq(enemy["hp"], 110)
		assert_eq(enemy["hurt_left"], 0.0)
		assert_eq(enemy["action"], "walk")
		assert_eq(world.arrows.size(), 0)


func test_firepower_feedback_marks_only_constructed_archer_platforms() -> void:
	var world: Node2D = _world()
	var levels: Array[int] = [1, 0, 2, 0, 0, 0]
	world.start_wave(false, levels)
	var feedback: Array[Dictionary] = []
	world.feedback_requested.connect(func(event: String, at: Vector2) -> void:
		if event == "rally":
			feedback.append({"event": event, "at": at})
	)
	assert_true(world.activate_rally())
	assert_eq(feedback.size(), 2, "Each constructed archer gets the firepower feedback")
	if feedback.size() == 2:
		assert_eq(feedback[0]["at"], world.to_global(world.tower_points[0] - world.TOWER_FOOT + world.ARCHER_PLATFORM))
		assert_eq(feedback[1]["at"], world.to_global(world.tower_points[2] - world.TOWER_FOOT + world.ARCHER_PLATFORM))
	assert_false(world.activate_rally())
	assert_eq(feedback.size(), 2, "The cooldown prevents a duplicate activation")
	var empty_levels: Array[int] = [0, 0, 0, 0, 0, 0]
	world.start_wave(false, empty_levels)
	assert_true(world.activate_rally())
	assert_eq(feedback.size(), 2, "Unbuilt slots do not get an archer effect")


func test_manual_selection_ignores_ashes_and_recovery_protection() -> void:
	var world: Node2D = _world()
	var enemy: Dictionary = world.enemies[1]
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = world.get_global_transform_with_canvas() * enemy["pos"]
	world._unhandled_input(click)
	assert_eq(world.selected_enemy, 1, "A normal live vampire can be selected manually")
	if not _first_defeat(world):
		return
	assert_eq(world.selected_enemy, -1)
	world._unhandled_input(click)
	assert_eq(world.selected_enemy, -1, "An ash pile cannot gain a manual attack selection")
	world._update_enemies(5.8)
	world._unhandled_input(click)
	assert_eq(world.selected_enemy, -1, "The reformed body cannot be selected during birth protection")
	world._update_enemies(0.36)
	world._unhandled_input(click)
	assert_eq(world.selected_enemy, 1, "Manual selection returns with the second life")


func test_same_frame_defeat_discards_prior_inflight_arrows_only_for_that_target() -> void:
	var world: Node2D = _world()
	world.ledger.pending.assign(["orc"])
	world._spawn_enemy()
	world.enemies[2]["pos"] = Vector2(200, 505)
	world.arrows.append({"pos": Vector2(0, 227), "target": 1, "damage": 8})
	world.arrows.append({"pos": Vector2(0, 487), "target": 2, "damage": 8})
	if not _first_defeat(world):
		return
	assert_eq(world.arrows.size(), 1, "Temporary death immediately removes earlier arrows to the same target")
	if world.arrows.size() == 1:
		assert_eq(world.arrows[0]["target"], 2, "Another living target keeps its already flying arrow")
	world._update_enemies(5.8)
	world._update_enemies(0.36)
	world.arrows.append({"pos": Vector2(0, 227), "target": 1, "damage": 8})
	_hit(world, 111)
	assert_false(world.enemies.has(1))
	assert_eq(world.arrows.size(), 1, "Final death immediately removes earlier arrows to the same target")
	if world.arrows.size() == 1:
		assert_eq(world.arrows[0]["target"], 2)
