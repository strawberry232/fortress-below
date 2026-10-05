extends SceneTree

const WorldScript = preload("res://game/scripts/defense/fortress_world.gd")
const STEP_SECONDS: float = 1.0 / 60.0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var all_feasible: bool = true
	var rows: Array[Dictionary] = []
	var cases: Array[Dictionary] = [
		{"round": 1, "levels": [1, 1, 0, 0, 0, 0], "hp": 100},
		{"round": 2, "levels": [1, 1, 0, 0, 0, 0], "hp": 65},
		{"round": 3, "levels": [2, 1, 0, 0, 0, 0], "hp": 65},
		{"round": 3, "levels": [1, 1, 1, 1, 1, 1], "hp": 65}
	]
	for scenario: Dictionary in cases:
		for alarm: bool in [false, true]:
			var levels: Array[int] = []
			levels.assign(scenario["levels"])
			var feasible: bool = false
			for timing: String in ["none", "first_arrow", "three_in_range", "first_castle_hit"]:
				var result: Dictionary = _simulate(scenario["round"], levels, timing, alarm, scenario["hp"])
				rows.append(result)
				print("DEFENSE_ECONOMY_RESULT " + JSON.stringify(result))
				feasible = feasible or result["completed_events"] == 1 and result["hp"] > 0
			all_feasible = all_feasible and feasible
	var output_directory: String = "res://docs/verification/v14"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	var report: FileAccess = FileAccess.open(output_directory.path_join("defense-economy.json"), FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"all_feasible": all_feasible, "cases": rows}, "\t"))
		report.close()
	else:
		all_feasible = false
	print("DEFENSE_ECONOMY_SUMMARY " + JSON.stringify({"all_feasible": all_feasible, "case_count": rows.size()}))
	for index: int in range(4):
		await process_frame
	quit(0 if all_feasible else 1)

func _simulate(round_value: int, levels: Array[int], timing: String, alarm: bool, initial_hp: int) -> Dictionary:
	var world: WorldScript = WorldScript.new()
	world.set_process(false)
	root.add_child(world)
	var result: Dictionary = {"round": round_value, "levels": levels, "initial_hp": initial_hp, "hp": initial_hp, "alarm": alarm, "rally_timing": timing, "rally_used": false, "rally_at": -1.0, "damage_events": 0, "total_damage": 0, "completed_events": 0}
	world.castle_damaged.connect(func(amount: int) -> void:
		result["damage_events"] += 1
		result["total_damage"] += amount
		result["hp"] = maxi(0, result["hp"] - amount)
		if result["hp"] == 0:
			world.running = false
	)
	world.wave_completed.connect(func() -> void: result["completed_events"] += 1)
	world.start_wave(alarm, levels, round_value)
	var elapsed: float = 0.0
	while world.running and elapsed < 120.0:
		world._process(STEP_SECONDS)
		elapsed += STEP_SECONDS
		if result["rally_used"] or timing == "none" or not world.running:
			continue
		var should_rally: bool = timing == "first_arrow" and not world.arrows.is_empty()
		if timing == "first_castle_hit":
			should_rally = result["damage_events"] > 0
		elif timing == "three_in_range":
			var in_range: int = 0
			for id: int in world.enemies:
				var position_on_road: Vector2 = world.enemies[id]["pos"]
				if position_on_road.distance_to(world.tower_points[0]) < world.balance.tower_range or position_on_road.distance_to(world.tower_points[1]) < world.balance.tower_range:
					in_range += 1
			should_rally = in_range >= 3
		if should_rally:
			result["rally_used"] = world.activate_rally()
			result["rally_at"] = snappedf(elapsed, 0.01)
	result["elapsed_sim_seconds"] = snappedf(elapsed, 0.01)
	result["running"] = world.running
	result["remaining_enemies"] = world.remaining_enemies()
	result["spawned"] = world.next_id - 1
	world.queue_free()
	return result
