extends "res://addons/gut/test.gd"

const RUN_SCRIPT_PATH: String = "res://game/scripts/state/run_state.gd"
const BALANCE_PATH: String = "res://game/data/balance/campaign_balance.tres"
const TITLE: int = 0
const PREPARATION: int = 1
const DUNGEON: int = 2
const SETTLEMENT: int = 3
const DEFENSE: int = 4
const COMPLETE: int = 5
const FAILED: int = 6

var _run: Variant = null


func before_each() -> void:
	var run_script: GDScript = load(RUN_SCRIPT_PATH) as GDScript
	assert_not_null(run_script, "The run state implementation must exist")
	if run_script != null:
		_run = run_script.new()


func after_each() -> void:
	_run = null


func _start_run() -> void:
	_run.new_run()


func _enter_settlement(gold_amount: int = 25) -> void:
	_start_run()
	assert_true(_run.begin_dungeon())
	assert_true(_run.collect_gold(gold_amount))
	assert_true(_run.take_goal_key())
	assert_true(_run.settle_loot())


func _enter_defense() -> void:
	_enter_settlement()
	assert_true(_run.start_defense())


func _snapshot() -> Dictionary:
	return {
		"phase": _run.phase,
		"gold": _run.gold,
		"castle_hp": _run.castle_hp,
		"tower_levels": _run.tower_levels.duplicate(),
		"bag_gold": _run.bag_gold,
		"has_goal_key": _run.has_goal_key,
		"alarm": _run.alarm,
		"failure_reason": _run.failure_reason
	}


func test_new_run_applies_initial_checkpoint_once_and_enters_preparation() -> void:
	assert_eq(_run.phase, TITLE)
	_start_run()
	assert_eq(_run.phase, PREPARATION)
	assert_eq(_run.gold, 20)
	assert_eq(_run.castle_hp, 100)
	assert_eq(_run.tower_levels, [1, 0, 0, 0, 0, 0])
	assert_eq(_run.bag_gold, 0)
	assert_false(_run.has_goal_key)
	assert_false(_run.alarm)
	assert_eq(_run.failure_reason, "")


func test_phase_and_changed_signals_support_the_hud() -> void:
	watch_signals(_run)
	_start_run()
	assert_signal_emitted_with_parameters(_run, "phase_changed", [PREPARATION])
	assert_signal_emit_count(_run, "changed", 1)
	assert_true(_run.begin_dungeon())
	assert_signal_emitted_with_parameters(_run, "phase_changed", [DUNGEON])
	assert_signal_emit_count(_run, "changed", 2)
	assert_false(_run.begin_dungeon())
	assert_signal_emit_count(_run, "changed", 2, "Rejected transitions must not notify changes")


func test_dungeon_can_begin_only_from_preparation() -> void:
	assert_false(_run.begin_dungeon())
	_start_run()
	assert_true(_run.begin_dungeon())
	var before: Dictionary = _snapshot()
	assert_false(_run.begin_dungeon())
	assert_eq(_snapshot(), before)


func test_gold_collection_changes_only_the_dungeon_bag() -> void:
	_start_run()
	assert_false(_run.collect_gold(10))
	assert_true(_run.begin_dungeon())
	assert_true(_run.collect_gold(25))
	assert_eq(_run.bag_gold, 25)
	assert_eq(_run.gold, 20)
	assert_false(_run.alarm, "Ordinary loot must not raise an alarm")
	var before: Dictionary = _snapshot()
	assert_false(_run.collect_gold(0))
	assert_false(_run.collect_gold(-1))
	assert_eq(_snapshot(), before)


func test_goal_key_can_be_taken_once_only_in_dungeon() -> void:
	_start_run()
	assert_false(_run.take_goal_key())
	assert_true(_run.begin_dungeon())
	assert_true(_run.take_goal_key())
	var before: Dictionary = _snapshot()
	assert_false(_run.take_goal_key())
	assert_eq(_snapshot(), before)


func test_sealed_chest_rewards_once_and_sets_alarm() -> void:
	_start_run()
	assert_false(_run.open_sealed_chest())
	assert_true(_run.begin_dungeon())
	assert_true(_run.open_sealed_chest())
	assert_eq(_run.bag_gold, 20)
	assert_eq(_run.gold, 20)
	assert_true(_run.alarm)
	var before: Dictionary = _snapshot()
	assert_false(_run.open_sealed_chest())
	assert_eq(_snapshot(), before)


func test_loot_requires_the_goal_key_and_settles_once() -> void:
	_start_run()
	assert_true(_run.begin_dungeon())
	assert_true(_run.collect_gold(25))
	var before: Dictionary = _snapshot()
	assert_false(_run.settle_loot())
	assert_eq(_snapshot(), before, "A missing key must leave the bank and bag unchanged")
	assert_true(_run.take_goal_key())
	assert_true(_run.settle_loot())
	assert_eq(_run.phase, SETTLEMENT)
	assert_eq(_run.gold, 45)
	assert_eq(_run.bag_gold, 0)
	before = _snapshot()
	assert_false(_run.settle_loot())
	assert_eq(_snapshot(), before, "Repeated exit callbacks must not settle twice")


func test_alarm_survives_settlement_and_is_cleared_only_after_success() -> void:
	_start_run()
	assert_true(_run.begin_dungeon())
	assert_true(_run.open_sealed_chest())
	assert_true(_run.take_goal_key())
	assert_true(_run.settle_loot())
	assert_eq(_run.gold, 40)
	assert_true(_run.alarm)
	assert_true(_run.start_defense())
	assert_true(_run.alarm, "The wave controller must be able to read this round's alarm")
	assert_true(_run.finish_defense())
	assert_false(_run.alarm)


func test_building_at_exact_cost_updates_the_requested_empty_slot() -> void:
	_start_run()
	_run.gold = 25
	assert_true(_run.build_tower(1))
	assert_eq(_run.gold, 0)
	assert_eq(_run.tower_levels, [1, 1, 0, 0, 0, 0])
	var before: Dictionary = _snapshot()
	assert_false(_run.build_tower(1))
	assert_eq(_snapshot(), before)


func test_building_rejects_invalid_slots_and_occupied_slots() -> void:
	_start_run()
	_run.gold = 100
	var before: Dictionary = _snapshot()
	for slot: int in [-1, 0, 6, 7]:
		assert_false(_run.build_tower(slot))
		assert_eq(_snapshot(), before)


func test_building_rejects_a_shortage_of_gold_atomically() -> void:
	for budget: int in [24, 0, -1]:
		_start_run()
		_run.gold = budget
		var before: Dictionary = _snapshot()
		assert_false(_run.build_tower(1))
		assert_eq(_snapshot(), before)


func test_upgrading_at_exact_cost_reaches_level_two_only_once() -> void:
	_start_run()
	_run.gold = 35
	assert_true(_run.upgrade_tower(0))
	assert_eq(_run.gold, 0)
	assert_eq(_run.tower_levels, [2, 0, 0, 0, 0, 0])
	_run.gold = 100
	var before: Dictionary = _snapshot()
	assert_false(_run.upgrade_tower(0))
	assert_false(_run.upgrade_tower(1))
	assert_false(_run.upgrade_tower(-1))
	assert_false(_run.upgrade_tower(2))
	assert_eq(_snapshot(), before)


func test_upgrade_rejects_gold_shortage_without_partial_charge() -> void:
	for budget: int in [34, 0, -1]:
		_start_run()
		_run.gold = budget
		var before: Dictionary = _snapshot()
		assert_false(_run.upgrade_tower(0))
		assert_eq(_snapshot(), before)


func test_repair_charges_once_and_clamps_to_maximum_hp() -> void:
	_start_run()
	_run.castle_hp = 65
	_run.gold = 20
	assert_true(_run.repair_castle())
	assert_eq(_run.gold, 0)
	assert_eq(_run.castle_hp, 100)
	_start_run()
	_run.castle_hp = 90
	assert_true(_run.repair_castle())
	assert_eq(_run.castle_hp, 100)
	assert_eq(_run.gold, 0)


func test_repair_rejects_full_hp_and_gold_shortages() -> void:
	_start_run()
	var before: Dictionary = _snapshot()
	assert_false(_run.repair_castle())
	assert_eq(_snapshot(), before)
	for budget: int in [19, 0, -1]:
		_run.castle_hp = 60
		_run.gold = budget
		before = _snapshot()
		assert_false(_run.repair_castle())
		assert_eq(_snapshot(), before)


func test_construction_and_repair_are_allowed_in_settlement() -> void:
	_enter_settlement(100)
	assert_true(_run.build_tower(1))
	assert_true(_run.upgrade_tower(0))
	_run.gold = 20
	_run.castle_hp = 65
	assert_true(_run.repair_castle())
	assert_eq(_run.tower_levels, [2, 1, 0, 0, 0, 0])
	assert_eq(_run.phase, SETTLEMENT)


func test_construction_is_blocked_in_every_other_phase() -> void:
	for value: int in [TITLE, DUNGEON, DEFENSE, COMPLETE, FAILED]:
		_start_run()
		_run.phase = value
		_run.gold = 100
		_run.castle_hp = 60
		var before: Dictionary = _snapshot()
		assert_false(_run.build_tower(1))
		assert_false(_run.upgrade_tower(0))
		assert_false(_run.repair_castle())
		assert_eq(_snapshot(), before)


func test_defense_can_start_only_after_keyed_loot_settlement() -> void:
	_start_run()
	assert_false(_run.start_defense())
	assert_true(_run.begin_dungeon())
	assert_false(_run.start_defense())
	assert_true(_run.take_goal_key())
	assert_true(_run.settle_loot())
	assert_true(_run.start_defense())
	var before: Dictionary = _snapshot()
	assert_false(_run.start_defense())
	assert_eq(_snapshot(), before)


func test_castle_damage_is_valid_only_during_defense() -> void:
	_start_run()
	var before: Dictionary = _snapshot()
	_run.damage_castle(20)
	assert_eq(_snapshot(), before)
	_enter_defense()
	_run.damage_castle(20)
	assert_eq(_run.castle_hp, 80)
	assert_eq(_run.phase, DEFENSE)
	before = _snapshot()
	_run.damage_castle(0)
	_run.damage_castle(-50)
	assert_eq(_snapshot(), before)


func test_castle_destruction_fails_before_any_success_callback() -> void:
	_enter_defense()
	_run.damage_castle(1000)
	assert_eq(_run.castle_hp, 0)
	assert_eq(_run.phase, FAILED)
	assert_eq(_run.failure_reason, "castle_destroyed")
	var before: Dictionary = _snapshot()
	assert_false(_run.finish_defense())
	_run.damage_castle(10)
	_run.fail("late_failure")
	assert_eq(_snapshot(), before, "A terminal failure must ignore late callbacks")


func test_third_success_enters_campaign_complete_and_ignores_late_events() -> void:
	_start_run()
	assert_false(_run.finish_defense())
	_enter_defense()
	_run.round_index = 3
	_run.completed_rounds = 2
	assert_true(_run.finish_defense())
	assert_eq(_run.phase, COMPLETE)
	var before: Dictionary = _snapshot()
	assert_false(_run.finish_defense())
	_run.fail("late_failure")
	_run.damage_castle(100)
	assert_false(_run.retry_round())
	assert_eq(_snapshot(), before)


func test_failure_and_retry_restore_the_round_checkpoint_without_regranting() -> void:
	_start_run()
	var checkpoint: Dictionary = _snapshot()
	assert_true(_run.begin_dungeon())
	assert_true(_run.collect_gold(25))
	assert_true(_run.open_sealed_chest())
	assert_true(_run.take_goal_key())
	assert_true(_run.settle_loot())
	assert_true(_run.build_tower(1))
	assert_eq(_run.tower_levels, [1, 1, 0, 0, 0, 0])
	_run.fail("player_defeated")
	assert_eq(_run.phase, FAILED)
	assert_true(_run.retry_round())
	assert_eq(_snapshot(), checkpoint, "Retry must undo income, construction, key, and alarm")
	assert_false(_run.retry_round())
	assert_eq(_snapshot(), checkpoint, "Retry must not grant free gold")
	assert_true(_run.begin_dungeon())
	assert_true(_run.open_sealed_chest(), "The restarted round may claim its reset chest")
	assert_eq(_run.bag_gold, 20, "Loot from the abandoned attempt must not accumulate")


func test_retry_after_castle_failure_restores_hp_and_detached_tower_snapshot() -> void:
	_enter_settlement(100)
	assert_true(_run.upgrade_tower(0))
	assert_true(_run.start_defense())
	_run.damage_castle(100)
	assert_true(_run.retry_round())
	assert_eq(_run.castle_hp, 100)
	assert_eq(_run.tower_levels, [1, 0, 0, 0, 0, 0])
	assert_eq(_run.gold, 20)


func test_new_run_discards_all_previous_terminal_and_chest_state() -> void:
	_start_run()
	assert_true(_run.begin_dungeon())
	assert_true(_run.open_sealed_chest())
	_run.fail("expedition_abandoned")
	_start_run()
	assert_eq(_run.phase, PREPARATION)
	assert_eq(_run.gold, 20)
	assert_eq(_run.failure_reason, "")
	assert_true(_run.begin_dungeon())
	assert_true(_run.open_sealed_chest())


func test_demo_balance_resource_is_used_and_independent_per_run() -> void:
	var balance: Resource = load(BALANCE_PATH) as Resource
	assert_not_null(balance)
	assert_eq(balance.get("mode"), "expedition")
	assert_eq(balance.get("round_limit"), 3)
	assert_eq(balance.get("castle_repair_floor"), 65)
	assert_eq(_run.balance.resource_path, "", "Runs should own editable copies of the shared balance")
	_run.balance.initial_gold = 55
	_start_run()
	assert_eq(_run.gold, 55)
	var another: Variant = load(RUN_SCRIPT_PATH).new()
	another.new_run()
	assert_eq(another.gold, 20)


func test_invalid_prices_do_not_mint_resources_or_mutate_towers() -> void:
	_start_run()
	_run.gold = 100
	_run.balance.build_gold_cost = -1
	var before: Dictionary = _snapshot()
	assert_false(_run.build_tower(1))
	assert_eq(_snapshot(), before)
	_run.balance.upgrade_gold_cost = -1
	assert_false(_run.upgrade_tower(0))
	assert_eq(_snapshot(), before)
	_run.castle_hp = 65
	_run.balance.repair_amount = -1
	before = _snapshot()
	assert_false(_run.repair_castle())
	assert_eq(_snapshot(), before)


func test_round_repair_floor_preserves_health_above_the_guarantee() -> void:
	for initial_hp: int in [1, 65, 90, 100]:
		_run.balance.castle_start_hp = initial_hp
		_start_run()
		assert_eq(_run.castle_hp, maxi(initial_hp, 65))
		var checkpoint: Dictionary = _snapshot()
		_run.fail("expedition_abandoned")
		assert_true(_run.retry_round())
		assert_eq(_snapshot(), checkpoint, "Retry must restore the saved checkpoint")


func test_resource_overflow_is_rejected_without_losing_loot_or_setting_alarm() -> void:
	_start_run()
	assert_true(_run.begin_dungeon())
	assert_true(_run.collect_gold(9223372036854775807))
	var before: Dictionary = _snapshot()
	assert_false(_run.collect_gold(1))
	assert_false(_run.open_sealed_chest())
	assert_eq(_snapshot(), before)
	assert_true(_run.take_goal_key())
	before = _snapshot()
	assert_false(_run.settle_loot(), "The bank must not wrap into a negative value")
	assert_eq(_snapshot(), before)


func test_title_ignores_failure_and_empty_active_reason_has_a_safe_default() -> void:
	var before: Dictionary = _snapshot()
	_run.fail("late_failure")
	assert_eq(_snapshot(), before)
	_start_run()
	_run.fail("")
	assert_eq(_run.phase, FAILED)
	assert_eq(_run.failure_reason, "round_failed")
	assert_true(_run.retry_round())
	assert_eq(_run.failure_reason, "")


func test_return_to_title_clears_failure_without_changing_or_regranting_resources() -> void:
	_enter_settlement(100)
	assert_true(_run.build_tower(1))
	_run.fail("expedition_abandoned")
	var expected: Dictionary = _snapshot()
	expected["phase"] = TITLE
	expected["failure_reason"] = ""
	watch_signals(_run)
	_run.return_to_title()
	assert_eq(_snapshot(), expected)
	assert_signal_emitted_with_parameters(_run, "phase_changed", [TITLE])
	assert_signal_emit_count(_run, "changed", 1)
	assert_false(_run.retry_round(), "Returning to the menu must leave the failed stage")
	_run.fail("late_failure")
	_run.return_to_title()
	assert_eq(_snapshot(), expected)
	assert_signal_emit_count(_run, "changed", 1, "Repeated menu requests are idempotent")


func test_return_to_title_blocks_pending_dungeon_settlement_and_new_game_starts_clean() -> void:
	_start_run()
	assert_true(_run.begin_dungeon())
	assert_true(_run.collect_gold(25))
	assert_true(_run.take_goal_key())
	var expected: Dictionary = _snapshot()
	expected["phase"] = TITLE
	_run.return_to_title()
	assert_eq(_snapshot(), expected)
	assert_false(_run.settle_loot(), "A late staircase event must not leave the main menu")
	assert_eq(_snapshot(), expected)
	_start_run()
	assert_eq(_run.phase, PREPARATION)
	assert_eq(_run.gold, 20)
	assert_eq(_run.bag_gold, 0)
