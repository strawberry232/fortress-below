extends "res://addons/gut/test.gd"

const DUNGEON_SCRIPT: Script = preload("res://game/scripts/dungeon/dungeon_world.gd")


func before_each() -> void:
	for action: String in ["fb_move_left", "fb_move_right", "fb_move_up", "fb_move_down", "fb_sword", "fb_bow", "fb_interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func _new_world() -> Node2D:
	var dungeon: Node2D = DUNGEON_SCRIPT.new()
	add_child_autofree(dungeon)
	dungeon.process_mode = Node.PROCESS_MODE_DISABLED
	return dungeon


func _adult_slime(dungeon: Node2D) -> CharacterBody2D:
	for enemy: CharacterBody2D in dungeon._enemies:
		if enemy.monster_kind == "slime" and (not "slime_generation" in enemy or enemy.slime_generation == 0):
			return enemy
	return null


func _living_slimes(dungeon: Node2D) -> Array[CharacterBody2D]:
	var result: Array[CharacterBody2D] = []
	for enemy: CharacterBody2D in dungeon._enemies:
		if is_instance_valid(enemy) and enemy.monster_kind == "slime" and enemy.health.is_alive():
			result.append(enemy)
	return result


func test_raised_spikes_hurt_late_entry_and_reentry_after_cooldown() -> void:
	var dungeon: Node2D = _new_world()
	var location: Vector2 = dungeon._spikes[0]
	dungeon.player.position = location + Vector2(40.0, 0.0)
	dungeon._clock = 2.1
	dungeon._physics_process(0.0)
	assert_eq(dungeon.get_player_health(), 100)
	dungeon.player.position = location
	dungeon._physics_process(0.0)
	assert_eq(dungeon.get_player_health(), 80, "Entering an already raised trap causes damage")
	for tick: int in range(10):
		dungeon._physics_process(0.01)
	assert_eq(dungeon.get_player_health(), 80, "Standing on spikes does not damage every physics frame")
	dungeon.player.position = location + Vector2(40.0, 0.0)
	dungeon.player.health.tick(0.75)
	dungeon._clock = 2.9
	dungeon._physics_process(0.0)
	dungeon.player.position = location
	dungeon._physics_process(0.0)
	assert_eq(dungeon.get_player_health(), 60, "Reentry after trap cooldown remains hazardous in the same raised interval")


func test_player_invulnerability_does_not_consume_the_rest_of_a_spike_cycle() -> void:
	var dungeon: Node2D = _new_world()
	assert_true(dungeon.player.receive_damage(10, "unrelated-enemy-hit"))
	dungeon.player.position = dungeon._spikes[0]
	dungeon._clock = 2.05
	dungeon._physics_process(0.0)
	assert_eq(dungeon.get_player_health(), 90, "A recent enemy hit grants normal player protection")
	dungeon.player.health.tick(0.65)
	dungeon._clock = 2.7
	dungeon._physics_process(0.0)
	assert_eq(dungeon.get_player_health(), 70, "Raised spikes hurt when protection expires without requiring another extension")


func test_each_spike_has_its_own_damage_cooldown() -> void:
	var dungeon: Node2D = _new_world()
	dungeon.player.health.protection_duration = 0.0
	dungeon.player.position = dungeon._spikes[0]
	dungeon._clock = 2.05
	dungeon._physics_process(0.0)
	assert_eq(dungeon.get_player_health(), 80)
	dungeon.player.position = dungeon._spikes[1]
	dungeon._clock = 2.2
	dungeon._physics_process(0.0)
	assert_eq(dungeon.get_player_health(), 60, "Another raised trap does not inherit the first trap's cooldown")
	dungeon.player.position = dungeon._spikes[0]
	dungeon._clock = 2.21
	dungeon._physics_process(0.0)
	assert_eq(dungeon.get_player_health(), 60, "Returning too soon to the first trap remains protected by that trap's cooldown")


func test_spike_phase_boundaries_match_visuals_and_reset_clears_damage_cooldowns() -> void:
	var dungeon: Node2D = _new_world()
	assert_true(dungeon.has_method("is_spike_active"), "Drawing and damage share one active-phase function")
	if not dungeon.has_method("is_spike_active"):
		return
	for time: float in [0.0, 1.5, 1.999]:
		dungeon._clock = time
		assert_false(dungeon.is_spike_active(0))
	for time: float in [2.0, 2.3, 2.999]:
		dungeon._clock = time
		assert_true(dungeon.is_spike_active(0))
	dungeon._clock = 3.0
	assert_false(dungeon.is_spike_active(0))
	assert_false(dungeon.is_spike_active(-1))
	assert_false(dungeon.is_spike_active(dungeon._spikes.size()))
	dungeon._clock = 1.35
	assert_true(dungeon.is_spike_active(1), "The second trap has its documented staggered phase")
	dungeon.player.position = dungeon._spikes[0]
	dungeon._clock = 2.1
	dungeon._physics_process(0.0)
	assert_eq(dungeon.get_player_health(), 80)
	dungeon.reset_run()
	await get_tree().process_frame
	dungeon.player.position = dungeon._spikes[0]
	dungeon._clock = 2.1
	dungeon._physics_process(0.0)
	assert_eq(dungeon.get_player_health(), 80, "Retry starts with fresh trap cooldowns and full health")


func test_guardian_slime_splits_once_and_gate_waits_for_both_fragments() -> void:
	var dungeon: Node2D = _new_world()
	watch_signals(dungeon)
	var adult: CharacterBody2D = _adult_slime(dungeon)
	assert_not_null(adult)
	assert_true(adult.receive_damage(1000, "adult-fatal"))
	await get_tree().process_frame
	var fragments: Array[CharacterBody2D] = _living_slimes(dungeon)
	assert_eq(fragments.size(), 2, "A defeated adult produces exactly two living fragments")
	if fragments.size() != 2:
		return
	assert_eq(dungeon._middle_guardians, 3, "The surviving skeleton and both fragments remain guardians")
	assert_false(adult.receive_damage(1000, "adult-duplicate"))
	adult.defeated.emit()
	await get_tree().process_frame
	assert_eq(_living_slimes(dungeon).size(), 2, "Repeated corpse signals cannot split again")
	assert_eq(dungeon._middle_guardians, 3)
	dungeon._enemies[0].receive_damage(1000, "other-guardian")
	fragments[0].health.tick(0.26)
	fragments[0].receive_damage(1000, "first-fragment")
	assert_eq(dungeon._middle_guardians, 1)
	assert_signal_emit_count(dungeon, "message_requested", 0)
	assert_true(dungeon.get_navigation_path(dungeon.player.position, dungeon.key_position).is_empty())
	fragments[1].health.tick(0.26)
	fragments[1].receive_damage(1000, "second-fragment")
	await get_tree().process_frame
	assert_eq(dungeon._middle_guardians, 0)
	assert_signal_emitted_with_parameters(dungeon, "message_requested", ["UI_MSG_GATE_OPENED"])
	assert_gt(dungeon.get_navigation_path(dungeon.player.position, dungeon.key_position).size(), 0)
	assert_eq(_living_slimes(dungeon).size(), 0, "Fragments never split recursively")


func test_fragment_positions_fit_clear_reachable_floor_in_every_level() -> void:
	var dungeon: Node2D = _new_world()
	for level_index: int in range(3):
		dungeon.reset_run(level_index)
		await get_tree().process_frame
		var adult: CharacterBody2D = _adult_slime(dungeon)
		var origin: Vector2 = adult.position
		adult.receive_damage(1000, "split-level-%d" % level_index)
		await get_tree().process_frame
		var fragments: Array[CharacterBody2D] = _living_slimes(dungeon)
		assert_eq(fragments.size(), 2)
		if fragments.size() != 2:
			continue
		assert_gte(fragments[0].position.distance_to(fragments[1].position), 24.0)
		for fragment: CharacterBody2D in fragments:
			assert_eq(fragment.slime_generation, 1)
			assert_eq(fragment.health.maximum, 14)
			assert_eq(fragment.attack_damage, 6)
			assert_eq(fragment._sprite.scale, Vector2(2.0, 2.0))
			for offset: Vector2 in [Vector2(0, -12), Vector2(-12, -12), Vector2(12, -12), Vector2(0, -24), Vector2.ZERO]:
				assert_true(dungeon.is_walkable(fragment.position + offset), "The complete foot collider remains on floor")
			for gate: Rect2 in dungeon.get_level_info()["gates"]:
				assert_false(gate.intersects(Rect2(fragment.position + Vector2(-12, -24), Vector2(24, 24))))
			assert_gt(dungeon.get_navigation_path(origin, fragment.position).size(), 0, "The child is reachable without crossing a locked gate")


func test_reset_and_failure_cannot_spawn_or_unlock_from_old_slime_signals() -> void:
	var dungeon: Node2D = _new_world()
	var adult: CharacterBody2D = _adult_slime(dungeon)
	adult.receive_damage(1000, "pending-split")
	dungeon.reset_run(1)
	await get_tree().process_frame
	assert_eq(dungeon._enemies.size(), dungeon.get_level_info()["guardians"].size() + 1)
	assert_eq(dungeon._middle_guardians, dungeon.get_level_info()["guardians"].size())
	assert_eq(_living_slimes(dungeon).size(), 1, "A previous run's deferred fragments do not leak into retry")
	adult = _adult_slime(dungeon)
	dungeon.player.receive_damage(1000, "run-failure")
	adult.receive_damage(1000, "after-player-failure")
	await get_tree().process_frame
	assert_eq(_living_slimes(dungeon).size(), 0)
	assert_eq(dungeon._middle_guardians, dungeon.get_level_info()["guardians"].size(), "Late defeat signals cannot advance a failed run")
	dungeon.reset_run(2)
	await get_tree().process_frame
	adult = _adult_slime(dungeon)
	adult.receive_damage(1000, "split-before-failure")
	dungeon.player.receive_damage(1000, "failure-before-deferred-spawn")
	await get_tree().process_frame
	assert_eq(_living_slimes(dungeon).size(), 0, "Deferred children are discarded if the player dies before they enter the scene")
	assert_false(dungeon._reward_guard_defeated)


func test_old_run_guard_death_before_queued_free_does_not_advance_retry() -> void:
	var dungeon: Node2D = _new_world()
	var old_guard: CharacterBody2D = _adult_slime(dungeon)
	dungeon.reset_run(1)
	watch_signals(dungeon)
	old_guard.receive_damage(1000, "detached-run-defeat")
	await get_tree().process_frame
	assert_eq(dungeon._enemies.size(), dungeon.get_level_info()["guardians"].size() + 1)
	assert_eq(dungeon._middle_guardians, dungeon.get_level_info()["guardians"].size())
	assert_eq(_living_slimes(dungeon).size(), 1)
	assert_signal_emit_count(dungeon, "message_requested", 0)


func test_slime_beside_closed_gate_splits_on_the_reachable_guardian_side() -> void:
	var dungeon: Node2D = _new_world()
	for level_index: int in range(3):
		dungeon.reset_run(level_index)
		await get_tree().process_frame
		var gate: Rect2 = dungeon.get_level_info()["gates"][0]
		var adult: CharacterBody2D = _adult_slime(dungeon)
		adult.position = gate.position + Vector2(-13.0, 44.0)
		assert_true(dungeon.get_navigation_path(adult.position, dungeon.player.position).is_empty(), "The conservative navigation cell beside a physical gate is blocked")
		adult.receive_damage(1000, "near-gate-%d" % level_index)
		await get_tree().process_frame
		var fragments: Array[CharacterBody2D] = _living_slimes(dungeon)
		assert_eq(fragments.size(), 2, "A physically legal position beside a closed gate still yields both children")
		for fragment: CharacterBody2D in fragments:
			assert_lt(fragment.position.x, gate.position.x)
			assert_gt(dungeon.get_navigation_path(dungeon.player.position, fragment.position).size(), 0, "Children cannot be stranded behind their own gate")


func test_reward_slime_requires_its_two_fragments_before_key_unlock() -> void:
	var dungeon: Node2D = _new_world()
	for enemy: CharacterBody2D in dungeon._enemies:
		enemy.set_physics_process(false)
	var reward: CharacterBody2D = dungeon._enemies.back()
	assert_true(reward.has_method("configure_slime_fragment"), "The shared actor implements nonrecursive fragment setup")
	if not reward.has_method("configure_slime_fragment"):
		return
	var old_parent: Node = reward.get_parent()
	old_parent.remove_child(reward)
	reward.queue_free()
	dungeon._enemies.erase(reward)
	dungeon._spawn_enemy(dungeon.get_level_info()["reward_guard"], false, "slime")
	var adult: CharacterBody2D = dungeon._enemies.back()
	adult.receive_damage(1000, "reward-adult")
	await get_tree().process_frame
	assert_false(dungeon._reward_guard_defeated)
	var fragments: Array[CharacterBody2D] = _living_slimes(dungeon)
	var reward_fragments: Array[CharacterBody2D] = []
	for fragment: CharacterBody2D in fragments:
		if fragment.slime_generation == 1:
			reward_fragments.append(fragment)
	assert_eq(reward_fragments.size(), 2)
	if reward_fragments.size() != 2:
		return
	reward_fragments[0].health.tick(0.26)
	reward_fragments[0].receive_damage(1000, "reward-first")
	assert_false(dungeon._reward_guard_defeated)
	reward_fragments[1].health.tick(0.26)
	reward_fragments[1].receive_damage(1000, "reward-second")
	assert_true(dungeon._reward_guard_defeated)


func test_enemy_projectiles_keep_world_origin_and_reject_stale_or_failed_shots() -> void:
	var dungeon: Node2D = _new_world()
	var source: CharacterBody2D = dungeon._enemies.back()
	assert_true(source.has_signal("ranged_shot_requested"))
	if not source.has_signal("ranged_shot_requested"):
		return
	var origin: Vector2 = source.global_position + Vector2(-16, -12)
	var before: int = dungeon._content.get_child_count()
	source.ranged_shot_requested.emit(origin, Vector2.LEFT, 12, "ghost-shot")
	assert_eq(dungeon._content.get_child_count(), before + 1)
	var projectile: Node2D = dungeon._content.get_child(dungeon._content.get_child_count() - 1)
	assert_eq(projectile.position, dungeon._content.to_local(origin), "An already offset global shot origin is not shifted twice")
	assert_eq(projectile.velocity, Vector2(-190.0, 0.0))
	assert_eq(projectile.damage, 12)
	assert_eq(projectile.attack_id, "ghost-shot")
	assert_eq(projectile.source_body, source)
	before = dungeon._content.get_child_count()
	dungeon._on_enemy_shot_requested(origin, Vector2.RIGHT, 12, "stale", source, dungeon._run_generation - 1)
	source.ranged_shot_requested.emit(origin, Vector2.ZERO, 12, "no-direction")
	source.ranged_shot_requested.emit(origin, Vector2.RIGHT, 0, "no-damage")
	assert_eq(dungeon._content.get_child_count(), before)
	dungeon.player.receive_damage(1000, "failure")
	source.ranged_shot_requested.emit(origin, Vector2.RIGHT, 12, "late-shot")
	assert_eq(dungeon._content.get_child_count(), before)
