extends "res://addons/gut/test.gd"

const WorldScript = preload("res://game/scripts/defense/fortress_world.gd")
const StateScript = preload("res://game/scripts/state/run_state.gd")
const STEP_SECONDS: float = 1.0 / 60.0
const MAX_SIMULATION_SECONDS: float = 120.0


func after_each() -> void:
	for index: int in range(4):
		await get_tree().process_frame


func _world() -> WorldScript:
	var world: WorldScript = WorldScript.new()
	world.set_process(false)
	add_child_autofree(world)
	return world


func _defense_state(alarm: bool, build_second: bool, upgrade_first: bool = false) -> StateScript:
	var state: StateScript = StateScript.new()
	state.new_run()
	assert_true(state.begin_dungeon())
	assert_true(state.collect_gold(25))
	if alarm:
		assert_true(state.open_sealed_chest())
	assert_true(state.take_goal_key())
	assert_true(state.settle_loot())
	if build_second:
		assert_true(state.build_tower(1))
	if upgrade_first:
		assert_true(state.upgrade_tower(0))
	assert_true(state.start_defense())
	return state


func _connect_castle(world: WorldScript, state: StateScript, result: Dictionary) -> void:
	world.castle_damaged.connect(func(amount: int) -> void:
		result["damage_events"] += 1
		result["total_damage"] += amount
		state.damage_castle(amount)
		if state.phase == StateScript.Phase.FAILED:
			world.running = false
	)
	world.wave_completed.connect(func() -> void:
		result["completed_events"] += 1
		state.finish_defense()
	)


func _simulate_route(label: String, alarm: bool, build_second: bool, use_rally: bool, upgrade_first: bool = false) -> Dictionary:
	var world: WorldScript = _world()
	var state: StateScript = _defense_state(alarm, build_second, upgrade_first)
	var result: Dictionary = {"route": label, "damage_events": 0, "total_damage": 0, "completed_events": 0, "rally_used": false, "orc_spawned": 0, "alarm_spawned": 0}
	var seen: Dictionary = {}
	_connect_castle(world, state, result)
	world.start_wave(state.alarm, state.tower_levels)
	var elapsed: float = 0.0
	while world.running and elapsed < MAX_SIMULATION_SECONDS:
		world._process(STEP_SECONDS)
		elapsed += STEP_SECONDS
		for id: int in world.enemies:
			if not seen.has(id):
				seen[id] = true
				result["alarm_spawned" if world.enemies[id]["kind"] == world.ledger.alarm_enemy_kind(1) else "orc_spawned"] += 1
		if use_rally and not result["rally_used"] and not world.arrows.is_empty():
			result["rally_used"] = world.activate_rally()
			assert_false(world.activate_rally(), "Rally is limited to unavailable during cooldown")
	result["elapsed_sim_seconds"] = snappedf(elapsed, 0.01)
	result["phase"] = state.phase
	result["castle_hp"] = state.castle_hp
	result["failure_reason"] = state.failure_reason
	result["gold"] = state.gold
	result["remaining_enemies"] = world.remaining_enemies()
	result["running"] = world.running
	assert_false(world.running, "The real wave must reach a terminal state within the simulation limit")
	print("DEFENSE_SIM_RESULT " + JSON.stringify(result))
	return result


func test_single_starter_tower_with_alarm_can_destroy_castle() -> void:
	var result: Dictionary = _simulate_route("single_alarm_no_rally", true, false, false)
	assert_eq(result["phase"], StateScript.Phase.FAILED)
	assert_eq(result["castle_hp"], 0)
	assert_eq(result["failure_reason"], "castle_destroyed")
	assert_gt(result["damage_events"], 0)
	assert_eq(result["completed_events"], 0)
	assert_eq(result["orc_spawned"], 6)
	assert_eq(result["alarm_spawned"], 1)
	assert_false(result["rally_used"])


func test_second_tower_without_alarm_completes_real_wave() -> void:
	var result: Dictionary = _simulate_route("double_safe_no_rally", false, true, false)
	assert_eq(result["phase"], StateScript.Phase.PREPARATION)
	assert_gt(result["castle_hp"], 0)
	assert_eq(result["completed_events"], 1)
	assert_eq(result["remaining_enemies"], 0)
	assert_eq(result["orc_spawned"], 6)
	assert_eq(result["alarm_spawned"], 0)
	assert_eq(result["gold"], 20)


func test_second_tower_alarm_and_rally_complete_real_wave() -> void:
	var result: Dictionary = _simulate_route("double_alarm_rally", true, true, true)
	assert_eq(result["phase"], StateScript.Phase.PREPARATION)
	assert_gt(result["castle_hp"], 0)
	assert_eq(result["completed_events"], 1)
	assert_eq(result["remaining_enemies"], 0)
	assert_eq(result["orc_spawned"], 6)
	assert_eq(result["alarm_spawned"], 1)
	assert_true(result["rally_used"])
	assert_eq(result["gold"], 40)


func test_single_tower_safe_route_and_affordable_upgrade_are_choices() -> void:
	var safe: Dictionary = _simulate_route("single_safe_no_rally", false, false, false)
	assert_eq(safe["phase"], StateScript.Phase.PREPARATION)
	assert_gt(safe["castle_hp"], 0)
	assert_eq(safe["gold"], 45)
	var upgraded: Dictionary = _simulate_route("double_alarm_upgrade_rally", true, true, true, true)
	assert_eq(upgraded["phase"], StateScript.Phase.PREPARATION)
	assert_eq(upgraded["gold"], 5)


func test_real_arrow_hits_once_and_consumes_projectile() -> void:
	var world: WorldScript = _world()
	world.start_wave(false, [1, 0])
	world._spawn_enemy()
	world.enemies[1]["pos"] = Vector2(400, 330)
	var health_before: int = world.enemies[1]["hp"]
	world._update_towers(0.0)
	assert_eq(world.arrows.size(), 1)
	assert_eq(world.arrows[0]["damage"], 8)
	assert_almost_eq(world.tower_clocks[0], 0.9, 0.001)
	world._update_arrows(1.0)
	assert_eq(world.enemies[1]["hp"], health_before - 8)
	assert_eq(world.arrows.size(), 0)
	world._update_arrows(1.0)
	assert_eq(world.enemies[1]["hp"], health_before - 8)
	assert_eq(world.ledger.alive.size(), 1)


func test_level_two_and_rally_preserve_attack_values() -> void:
	var world: WorldScript = _world()
	world.start_wave(false, [2, 0])
	world._spawn_enemy()
	world.enemies[1]["pos"] = Vector2(400, 330)
	assert_true(world.activate_rally())
	assert_almost_eq(world.rally_seconds, 4.0, 0.001)
	world._update_towers(0.0)
	assert_eq(world.arrows[0]["damage"], 10)
	assert_almost_eq(world.tower_clocks[0], 0.75 * 0.67, 0.001)


func test_enemy_arrival_deals_real_castle_damage() -> void:
	var world: WorldScript = _world()
	var state: StateScript = _defense_state(false, false)
	var result: Dictionary = {"damage_events": 0, "total_damage": 0, "completed_events": 0}
	_connect_castle(world, state, result)
	world.start_wave(false, state.tower_levels)
	world._spawn_enemy()
	world.enemies[1]["pos"] = Vector2(710, 330)
	world.enemies[1]["arrived"] = true
	world.enemies[1]["clock"] = 0.29
	world._set_enemy_action(world.enemies[1], "attack", true)
	world.enemies[1]["action_elapsed"] = 0.29
	world._update_enemies(STEP_SECONDS)
	assert_eq(result["damage_events"], 1)
	assert_eq(result["total_damage"], 10)
	assert_eq(state.castle_hp, 90)


func test_castle_failure_precedes_same_frame_last_arrow_and_completion() -> void:
	var world: WorldScript = _world()
	var state: StateScript = _defense_state(false, false)
	var result: Dictionary = {"damage_events": 0, "total_damage": 0, "completed_events": 0}
	_connect_castle(world, state, result)
	world.start_wave(false, state.tower_levels)
	world._spawn_enemy()
	world.ledger.pending.clear()
	state.castle_hp = 10
	world.enemies[1]["pos"] = Vector2(710, 330)
	world.enemies[1]["arrived"] = true
	world.enemies[1]["clock"] = 0.29
	world._set_enemy_action(world.enemies[1], "attack", true)
	world.enemies[1]["action_elapsed"] = 0.29
	world.enemies[1]["hp"] = 8
	world.arrows.append({"pos": Vector2(710, 312), "target": 1, "damage": 8})
	world._process(STEP_SECONDS)
	assert_eq(state.phase, StateScript.Phase.FAILED)
	assert_eq(state.castle_hp, 0)
	assert_false(world.running)
	assert_true(world.enemies.has(1), "A fatal castle event stops same-frame arrows")
	assert_eq(result["completed_events"], 0)
	assert_false(state.finish_defense())
	world._process(1.0)
	assert_eq(result["damage_events"], 1)
	assert_eq(result["completed_events"], 0)


func test_defense_configuration_is_editable_and_instance_isolated() -> void:
	var world: WorldScript = _world()
	assert_not_null(world.get("balance"), "Enemy and tower values must live in an editable resource")
	if world.get("balance") == null:
		return
	var other: WorldScript = _world()
	assert_ne(world.balance, other.balance)
	assert_eq(world.balance.orc_health, 48)
	assert_almost_eq(world.balance.orc_speed, 45.0, 0.001)
	assert_almost_eq(world.balance.spawn_interval, 3.0, 0.001)
	world.balance.orc_health = 56
	world.start_wave(false, [1, 0])
	world._spawn_enemy()
	other.start_wave(false, [1, 0])
	other._spawn_enemy()
	assert_eq(world.enemies[1]["hp"], 56)
	assert_eq(other.enemies[1]["hp"], 48)
