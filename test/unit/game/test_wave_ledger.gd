extends "res://addons/gut/test.gd"

const LedgerScript = preload("res://game/scripts/defense/wave_ledger.gd")

func test_alarm_adds_exactly_one_catalog_enemy() -> void:
	var ledger: RefCounted = LedgerScript.new()
	ledger.begin_wave(false)
	assert_eq(ledger.pending.size(), 6)
	ledger.begin_wave(true)
	assert_eq(ledger.pending.size(), 7)
	assert_eq(ledger.pending.count(ledger.alarm_enemy_kind(1)), 1)

func test_empty_alive_between_spawns_is_not_complete() -> void:
	var ledger: RefCounted = LedgerScript.new()
	ledger.begin_wave(false)
	assert_false(ledger.is_complete())
	assert_eq(ledger.spawn_next(1), "orc")
	assert_true(ledger.mark_dead(1))
	assert_false(ledger.is_complete())

func test_complete_requires_all_spawns_and_deaths() -> void:
	var ledger: RefCounted = LedgerScript.new()
	ledger.begin_wave(false)
	for id: int in range(1, 7):
		assert_eq(ledger.spawn_next(id), "orc")
	assert_false(ledger.is_complete())
	for id: int in range(1, 7):
		assert_true(ledger.mark_dead(id))
	assert_true(ledger.is_complete())
	assert_false(ledger.mark_dead(6))

func test_duplicate_invalid_spawn_does_not_consume_queue() -> void:
	var ledger: RefCounted = LedgerScript.new()
	ledger.begin_wave(false)
	assert_eq(ledger.spawn_next(0), "")
	assert_eq(ledger.pending.size(), 6)
	assert_eq(ledger.spawn_next(1), "orc")
	assert_eq(ledger.spawn_next(1), "")
	assert_eq(ledger.pending.size(), 5)

func test_rally_once_and_new_wave_reset() -> void:
	var ledger: RefCounted = LedgerScript.new()
	ledger.begin_wave(false)
	assert_true(ledger.claim_rally())
	assert_false(ledger.claim_rally())
	ledger.begin_wave(true)
	assert_true(ledger.claim_rally())
	assert_eq(ledger.alive.size(), 0)

func test_three_round_counts_and_alarm_extra_remain_distinct() -> void:
	var ledger: RefCounted = LedgerScript.new()
	assert_true(ledger.has_method("reset"), "Round-aware ledgers support clean retries")
	if not ledger.has_method("reset"):
		return
	for round_index: int in range(1, 4):
		ledger.begin_wave(false, round_index)
		assert_eq(ledger.pending.size(), 4 + round_index * 2)
		var normal_kind_count: int = ledger.pending.count(ledger.alarm_enemy_kind(round_index))
		ledger.begin_wave(true, round_index)
		assert_eq(ledger.pending.size(), 5 + round_index * 2)
		assert_eq(ledger.pending.count(ledger.alarm_enemy_kind(round_index)), normal_kind_count + 1)

func test_reset_clears_failed_wave_and_does_not_complete_empty_queue() -> void:
	var ledger: RefCounted = LedgerScript.new()
	assert_true(ledger.has_method("reset"))
	if not ledger.has_method("reset"):
		return
	ledger.begin_wave(true)
	ledger.spawn_next(1)
	ledger.claim_rally()
	ledger.reset()
	assert_eq(ledger.pending.size(), 0)
	assert_eq(ledger.alive.size(), 0)
	assert_false(ledger.rally_used)
	assert_false(ledger.is_complete())
	assert_false(ledger.claim_rally())
