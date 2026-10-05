extends "res://addons/gut/test.gd"

const ENEMY: Script = preload("res://game/scripts/combat/fortress_skeleton.gd")
const DUNGEON: Script = preload("res://game/scripts/dungeon/dungeon_world.gd")
const CATALOG: Script = preload("res://game/data/monsters/monster_catalog.gd")

func _vampire() -> CharacterBody2D:
	var enemy: CharacterBody2D = ENEMY.new()
	enemy.configure_kind("vampire")
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	watch_signals(enemy)
	return enemy

func test_first_vampire_defeat_keeps_guardian_and_original_ash_animation() -> void:
	var enemy: CharacterBody2D = _vampire()
	assert_true(enemy.receive_damage(1000, "first-fatal"))
	assert_false(enemy.health.is_alive())
	assert_signal_not_emitted(enemy, "defeated", "First life cannot unlock a guardian gate")
	assert_not_null(enemy.get("revival"), "A two-life vampire needs an explicit revival state")
	if enemy.get("revival") == null:
		return
	assert_true(enemy.revival.pending)
	assert_eq(enemy.revival.lives_left, 1)
	enemy._physics_process(1.4)
	assert_eq(enemy._sprite.animation, &"death")
	assert_eq(enemy._sprite.frame, 13, "Death leaves the original final ash heap visible")
	enemy._physics_process(2.99)
	assert_eq(enemy._sprite.frame, 13, "The corpse remains throughout the three-second rest")
	assert_false(enemy.health.is_alive())
	assert_false(enemy.is_queued_for_deletion())

func test_reverse_death_reassembles_then_restores_full_second_life() -> void:
	var enemy: CharacterBody2D = _vampire()
	enemy.receive_damage(1000, "first-fatal")
	assert_not_null(enemy.get("revival"))
	if enemy.get("revival") == null:
		return
	enemy._physics_process(4.4)
	assert_eq(enemy._sprite.frame, 13, "Reassembly starts from the original ash frame")
	enemy._physics_process(0.7)
	assert_lte(enemy._sprite.frame, 7)
	assert_gte(enemy._sprite.frame, 5)
	assert_false(enemy.health.is_alive(), "An assembling vampire cannot act yet")
	enemy._physics_process(0.7)
	assert_eq(enemy.health.current, 120)
	assert_false(enemy.revival.pending)
	assert_eq(enemy.revival.lives_left, 1)
	assert_eq(enemy._sprite.animation, &"idle")
	assert_eq(enemy._attack_elapsed, -1.0)
	assert_gt(enemy._cooldown, 0.0, "Reanimation gives a visible safe response interval")
	assert_signal_not_emitted(enemy, "defeated")
	await get_tree().process_frame
	assert_eq(enemy.collision_layer, 4)
	assert_eq(enemy.collision_mask, 1)
	assert_eq(enemy._hurt_area.collision_layer, 4)

func test_ash_is_not_damageable_and_second_death_is_final_once() -> void:
	var enemy: CharacterBody2D = _vampire()
	enemy.receive_damage(1000, "first-fatal")
	assert_not_null(enemy.get("revival"))
	if enemy.get("revival") == null:
		return
	assert_false(enemy.receive_damage(1000, "corpse-hit"))
	assert_false(enemy.receive_damage(0, "invalid"))
	assert_false(enemy.receive_damage(-2, "invalid-negative"))
	enemy._physics_process(5.8)
	enemy.health.tick(0.4)
	assert_false(enemy.receive_damage(1000, "first-fatal"), "The old fatal identity cannot consume the restored life")
	assert_true(enemy.receive_damage(1000, "second-fatal"))
	assert_signal_emit_count(enemy, "defeated", 1)
	assert_false(enemy.revival.pending)
	assert_false(enemy.receive_damage(1000, "third-hit"))
	assert_signal_emit_count(enemy, "defeated", 1)
	enemy._physics_process(1.59)
	assert_false(enemy.is_queued_for_deletion(), "Final corpse retains its complete original death animation")
	enemy._physics_process(0.02)
	assert_true(enemy.is_queued_for_deletion())

func test_non_vampire_still_has_one_life_and_normal_death() -> void:
	var enemy: CharacterBody2D = ENEMY.new()
	enemy.configure_kind("skeleton")
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	watch_signals(enemy)
	enemy.receive_damage(1000, "single-life")
	assert_signal_emit_count(enemy, "defeated", 1)
	assert_not_null(enemy.get("revival"))
	if enemy.get("revival") != null:
		assert_false(enemy.revival.pending)
		assert_eq(enemy.revival.lives_left, 1)

func test_first_reward_guardian_death_never_unlocks_key_but_second_does() -> void:
	var world: Node2D = DUNGEON.new()
	add_child_autofree(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.reset_run(2)
	var vampire: CharacterBody2D
	for enemy: CharacterBody2D in world._enemies:
		if enemy.monster_kind == "vampire":
			vampire = enemy
	assert_not_null(vampire)
	if vampire == null:
		return
	vampire.receive_damage(1000, "reward-life-one")
	assert_false(world._reward_guard_defeated)
	assert_not_null(vampire.get("revival"))
	if vampire.get("revival") == null:
		return
	vampire._physics_process(5.8)
	vampire.health.tick(0.4)
	vampire.receive_damage(1000, "reward-life-two")
	assert_true(world._reward_guard_defeated)

func test_pause_and_hidden_dungeon_freeze_pending_revival() -> void:
	var world: Node2D = DUNGEON.new()
	add_child_autofree(world)
	world.reset_run(2)
	var vampire: CharacterBody2D
	for enemy: CharacterBody2D in world._enemies:
		if enemy.monster_kind == "vampire":
			vampire = enemy
	assert_not_null(vampire.get("revival"))
	if vampire.get("revival") == null:
		return
	vampire.receive_damage(1000, "pause-fatal")
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var elapsed: float = vampire.revival.elapsed
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(vampire.revival.elapsed, elapsed)
	world.visible = false
	await get_tree().physics_frame
	assert_eq(vampire.revival.elapsed, elapsed)
	world.reset_run(0)
	await get_tree().process_frame
	assert_false(is_instance_valid(vampire), "A retry frees old pending corpses before their second lives")

func test_revival_sampling_clamps_invalid_time_and_completes_only_once() -> void:
	var enemy: CharacterBody2D = _vampire()
	assert_not_null(enemy.get("revival"))
	if enemy.get("revival") == null:
		return
	var lifecycle: RefCounted = enemy.revival
	assert_almost_eq(lifecycle.total_duration(), 5.8, 0.0001)
	assert_false(lifecycle.advance(100.0), "An active first life cannot spontaneously revive")
	assert_true(lifecycle.begin_defeat())
	assert_false(lifecycle.begin_defeat(), "Duplicate first-death handling cannot consume or restart another life")
	assert_false(lifecycle.advance(-1.0))
	assert_eq(lifecycle.elapsed, 0.0)
	assert_eq(lifecycle.sample()["frame"], 0)
	assert_false(lifecycle.advance(1.4))
	assert_eq(lifecycle.sample()["frame"], 13)
	assert_eq(lifecycle.sample()["phase"], "ashes")
	assert_false(lifecycle.advance(3.0))
	assert_eq(lifecycle.sample()["frame"], 13)
	assert_eq(lifecycle.sample()["phase"], "reforming")
	assert_true(lifecycle.advance(1.4))
	assert_false(lifecycle.advance(100.0), "The completed state produces exactly one restore event")
	assert_false(lifecycle.begin_defeat(), "Only two lives are allowed")
