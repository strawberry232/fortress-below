extends "res://addons/gut/test.gd"

const StateScript = preload("res://game/scripts/state/run_state.gd")

func _state() -> RefCounted:
	var state: RefCounted = StateScript.new()
	state.start_campaign()
	return state

func _has_property(value: Object, property_name: String) -> bool:
	for entry: Dictionary in value.get_property_list():
		if entry["name"] == property_name:
			return true
	return false

func test_run_and_balance_have_no_wood_resource_or_prices() -> void:
	var state: RefCounted = _state()
	assert_false(_has_property(state, "wood"))
	for name: String in ["initial_wood", "wood_per_round", "build_wood_cost", "upgrade_wood_cost", "repair_wood_cost"]:
		assert_false(_has_property(state.balance, name), "Removed price: " + name)

func test_six_tower_slots_are_independent_and_buildable_at_exact_gold_cost() -> void:
	var state: RefCounted = _state()
	assert_eq(state.tower_levels, [1, 0, 0, 0, 0, 0])
	for slot: int in range(1, 6):
		state.gold = 25
		assert_true(state.build_tower(slot), "Build slot " + str(slot + 1))
		assert_eq(state.gold, 0)
	assert_eq(state.tower_levels, [1, 1, 1, 1, 1, 1])
	state.gold = 35
	assert_true(state.upgrade_tower(5))
	assert_eq(state.gold, 0)
	assert_eq(state.tower_levels, [1, 1, 1, 1, 1, 2])

func test_invalid_or_short_gold_transactions_leave_all_resources_unchanged() -> void:
	var state: RefCounted = _state()
	state.gold = 24
	var levels: Array = state.tower_levels.duplicate()
	for slot: int in [-1, 0, 1, 5, 6, 100]:
		assert_false(state.build_tower(slot))
		assert_eq(state.gold, 24)
		assert_eq(state.tower_levels, levels)
	state.gold = 34
	assert_false(state.upgrade_tower(0))
	assert_eq(state.gold, 34)
	state.castle_hp = 50
	state.gold = 19
	assert_false(state.repair_castle())
	assert_eq(state.gold, 19)
	assert_eq(state.castle_hp, 50)

func test_paid_repair_uses_only_gold_and_does_not_require_any_other_resource() -> void:
	var state: RefCounted = _state()
	state.castle_hp = 65
	state.gold = 20
	assert_true(state.repair_castle())
	assert_eq(state.gold, 0)
	assert_eq(state.castle_hp, 100)

func test_later_round_and_retry_keep_won_towers_without_granting_free_gold() -> void:
	var state: RefCounted = _state()
	assert_true(state.begin_dungeon())
	assert_true(state.collect_gold(25))
	assert_true(state.take_goal_key())
	assert_true(state.settle_loot())
	assert_true(state.build_tower(5))
	assert_true(state.start_defense())
	assert_true(state.finish_defense())
	assert_eq(state.round_index, 2)
	assert_eq(state.gold, 20)
	assert_eq(state.tower_levels, [1, 0, 0, 0, 0, 1])
	assert_true(state.begin_dungeon())
	assert_true(state.open_sealed_chest())
	state.fail("player_defeated")
	assert_true(state.retry_round())
	assert_eq(state.gold, 20)
	assert_eq(state.tower_levels, [1, 0, 0, 0, 0, 1])
	assert_eq(state.bag_gold, 0)
	assert_false(state.alarm)

func test_zero_or_negative_prices_cannot_create_free_buildings_or_refunds() -> void:
	var state: RefCounted = _state()
	state.gold = 100
	for price: int in [0, -1]:
		state.balance.build_gold_cost = price
		state.balance.upgrade_gold_cost = price
		state.balance.repair_gold_cost = price
		state.castle_hp = 65
		assert_false(state.build_tower(5))
		assert_false(state.upgrade_tower(0))
		assert_false(state.repair_castle())
		assert_eq(state.gold, 100)
		assert_eq(state.castle_hp, 65)
