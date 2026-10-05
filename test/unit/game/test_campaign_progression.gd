extends "res://addons/gut/test.gd"

const StateScript = preload("res://game/scripts/state/run_state.gd")


func _campaign() -> RefCounted:
	var state: RefCounted = StateScript.new()
	assert_true(state.has_method("start_campaign"), "The expanded game must provide a three-round campaign")
	if not state.has_method("start_campaign"):
		return null
	state.start_campaign()
	return state


func _finish_round(state: RefCounted, alarm: bool = false) -> void:
	assert_true(state.begin_dungeon())
	assert_true(state.collect_gold(25))
	if alarm:
		assert_true(state.open_sealed_chest())
	assert_true(state.take_goal_key())
	assert_true(state.settle_loot())
	assert_true(state.start_defense())
	assert_true(state.finish_defense())


func test_campaign_starts_with_a_single_initial_checkpoint() -> void:
	var state: RefCounted = _campaign()
	if state == null:
		return
	assert_eq(state.round_index, 1)
	assert_eq(state.completed_rounds, 0)
	assert_eq(state.balance.round_limit, 3)
	assert_eq(state.gold, 20)
	assert_eq(state.tower_levels, [1, 0, 0, 0, 0, 0])
	assert_eq(state.phase, StateScript.Phase.PREPARATION)


func test_success_preserves_paid_towers_and_income_and_advances_next_round_once() -> void:
	var state: RefCounted = _campaign()
	if state == null:
		return
	assert_true(state.begin_dungeon())
	assert_true(state.collect_gold(25))
	assert_true(state.open_sealed_chest())
	assert_true(state.take_goal_key())
	assert_true(state.settle_loot())
	assert_true(state.build_tower(1))
	assert_true(state.start_defense())
	state.damage_castle(10)
	assert_true(state.finish_defense())
	assert_eq(state.phase, StateScript.Phase.PREPARATION)
	assert_eq(state.round_index, 2)
	assert_eq(state.completed_rounds, 1)
	assert_eq(state.gold, 40)
	assert_eq(state.castle_hp, 90)
	assert_eq(state.tower_levels, [1, 1, 0, 0, 0, 0])
	assert_false(state.has_goal_key)
	assert_false(state.alarm)
	assert_eq(state.bag_gold, 0)
	assert_false(state.finish_defense(), "A duplicate wave completion cannot advance another round")
	assert_eq(state.round_index, 2)


func test_later_round_failure_restores_only_the_current_round_checkpoint() -> void:
	var state: RefCounted = _campaign()
	if state == null:
		return
	_finish_round(state)
	assert_eq(state.gold, 45)
	assert_true(state.build_tower(1))
	assert_true(state.begin_dungeon())
	assert_true(state.open_sealed_chest())
	state.fail("player_defeated")
	assert_true(state.retry_round())
	assert_eq(state.round_index, 2)
	assert_eq(state.completed_rounds, 1)
	assert_eq(state.gold, 45)
	assert_eq(state.tower_levels, [1, 0, 0, 0, 0, 0])
	assert_false(state.alarm)
	assert_eq(state.bag_gold, 0)
	assert_false(state.retry_round())


func test_third_success_is_terminal_and_replay_resets_all_campaign_progress() -> void:
	var state: RefCounted = _campaign()
	if state == null:
		return
	_finish_round(state)
	_finish_round(state)
	assert_eq(state.phase, StateScript.Phase.PREPARATION)
	assert_eq(state.round_index, 3)
	_finish_round(state)
	assert_eq(state.phase, StateScript.Phase.COMPLETE)
	assert_eq(state.completed_rounds, 3)
	assert_eq(state.gold, 95)
	assert_false(state.finish_defense())
	assert_false(state.retry_round())
	assert_false(state.begin_dungeon())
	state.start_campaign()
	assert_eq(state.round_index, 1)
	assert_eq(state.completed_rounds, 0)
	assert_eq(state.gold, 20)


func test_minimum_repair_applies_once_before_next_checkpoint_and_does_not_mint_gold() -> void:
	var state: RefCounted = _campaign()
	if state == null:
		return
	assert_true(state.begin_dungeon())
	assert_true(state.take_goal_key())
	assert_true(state.settle_loot())
	assert_true(state.start_defense())
	state.damage_castle(99)
	assert_true(state.finish_defense())
	assert_eq(state.castle_hp, 65)
	assert_eq(state.gold, 20)
	state.fail("expedition_abandoned")
	assert_true(state.retry_round())
	assert_eq(state.castle_hp, 65)
	assert_eq(state.gold, 20)


func test_restart_after_returning_to_title_still_uses_three_rounds() -> void:
	var state: RefCounted = _campaign()
	if state == null:
		return
	state.return_to_title()
	state.start_campaign()
	assert_eq(state.balance.round_limit, 3)
	assert_eq(state.round_index, 1)
	_finish_round(state)
	assert_eq(state.phase, StateScript.Phase.PREPARATION)
	assert_eq(state.completed_rounds, 1)
	assert_eq(state.round_index, 2)
