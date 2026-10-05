class_name FortressRunState
extends RefCounted

signal changed
signal phase_changed(value: int)

enum Phase { TITLE, PREPARATION, DUNGEON, SETTLEMENT, DEFENSE, COMPLETE, FAILED }

const CAMPAIGN_BALANCE: Resource = preload("res://game/data/balance/campaign_balance.tres")

var phase: Phase = Phase.TITLE
var gold: int = 0
var castle_hp: int = 0
var tower_levels: Array[int] = [0, 0, 0, 0, 0, 0]
var bag_gold: int = 0
var has_goal_key: bool = false
var alarm: bool = false
var failure_reason: String = ""
var round_index: int = 1
var completed_rounds: int = 0
var balance: FortressDemoBalance = CAMPAIGN_BALANCE.duplicate() as FortressDemoBalance

var _round_checkpoint: Dictionary = {}
var _sealed_chest_opened: bool = false


func new_run() -> void:
	round_index = 1
	completed_rounds = 0
	gold = balance.initial_gold
	castle_hp = clampi(balance.castle_start_hp, balance.castle_repair_floor, balance.castle_max_hp)
	tower_levels = balance.initial_tower_levels.duplicate()
	_reset_dungeon_state()
	_save_checkpoint()
	_set_phase(Phase.PREPARATION)


func start_campaign() -> void:
	balance = CAMPAIGN_BALANCE.duplicate() as FortressDemoBalance
	new_run()


func _save_checkpoint() -> void:
	_round_checkpoint = {
		"gold": gold,
		"castle_hp": castle_hp,
		"tower_levels": tower_levels.duplicate(),
		"round_index": round_index,
		"completed_rounds": completed_rounds
	}


func begin_dungeon() -> bool:
	if phase != Phase.PREPARATION:
		return false
	_set_phase(Phase.DUNGEON)
	return true


func collect_gold(amount: int) -> bool:
	if phase != Phase.DUNGEON or amount <= 0:
		return false
	var next_bag: int = bag_gold + amount
	if next_bag < bag_gold:
		return false
	bag_gold = next_bag
	changed.emit()
	return true


func take_goal_key() -> bool:
	if phase != Phase.DUNGEON or has_goal_key:
		return false
	has_goal_key = true
	changed.emit()
	return true


func open_sealed_chest() -> bool:
	if phase != Phase.DUNGEON or _sealed_chest_opened or balance.sealed_chest_gold <= 0:
		return false
	var next_bag: int = bag_gold + balance.sealed_chest_gold
	if next_bag < bag_gold:
		return false
	bag_gold = next_bag
	_sealed_chest_opened = true
	alarm = true
	changed.emit()
	return true


func settle_loot() -> bool:
	if phase != Phase.DUNGEON or not has_goal_key:
		return false
	var next_gold: int = gold + bag_gold
	if bag_gold < 0 or next_gold < gold:
		return false
	gold = next_gold
	bag_gold = 0
	_set_phase(Phase.SETTLEMENT)
	return true


func build_tower(slot: int) -> bool:
	if not _can_construct() or not _is_valid_slot(slot) or tower_levels[slot] != 0:
		return false
	if not _spend(balance.build_gold_cost):
		return false
	tower_levels[slot] = 1
	changed.emit()
	return true


func upgrade_tower(slot: int) -> bool:
	if not _can_construct() or not _is_valid_slot(slot):
		return false
	if tower_levels[slot] <= 0 or tower_levels[slot] >= balance.tower_max_level:
		return false
	if not _spend(balance.upgrade_gold_cost):
		return false
	tower_levels[slot] += 1
	changed.emit()
	return true


func repair_castle() -> bool:
	if not _can_construct() or castle_hp <= 0 or castle_hp >= balance.castle_max_hp:
		return false
	if balance.repair_amount <= 0 or not _spend(balance.repair_gold_cost):
		return false
	castle_hp = mini(balance.castle_max_hp, castle_hp + balance.repair_amount)
	changed.emit()
	return true


func start_defense() -> bool:
	if phase != Phase.SETTLEMENT or not has_goal_key or castle_hp <= 0:
		return false
	_set_phase(Phase.DEFENSE)
	return true


func damage_castle(amount: int) -> void:
	if phase != Phase.DEFENSE or amount <= 0:
		return
	castle_hp = maxi(0, castle_hp - amount)
	if castle_hp == 0:
		fail("castle_destroyed")
	else:
		changed.emit()


func finish_defense() -> bool:
	if phase != Phase.DEFENSE or castle_hp <= 0:
		return false
	alarm = false
	completed_rounds += 1
	if round_index >= clampi(balance.round_limit, 1, 3):
		_set_phase(Phase.COMPLETE)
	else:
		round_index += 1
		castle_hp = maxi(castle_hp, balance.castle_repair_floor)
		_reset_dungeon_state()
		_save_checkpoint()
		_set_phase(Phase.PREPARATION)
	return true


func fail(reason: String) -> void:
	if phase == Phase.TITLE or phase == Phase.COMPLETE or phase == Phase.FAILED:
		return
	failure_reason = reason if not reason.is_empty() else "round_failed"
	_set_phase(Phase.FAILED)


func retry_round() -> bool:
	if phase != Phase.FAILED or _round_checkpoint.is_empty():
		return false
	gold = _round_checkpoint["gold"]
	castle_hp = _round_checkpoint["castle_hp"]
	tower_levels = _round_checkpoint["tower_levels"].duplicate()
	round_index = _round_checkpoint["round_index"]
	completed_rounds = _round_checkpoint["completed_rounds"]
	_reset_dungeon_state()
	_set_phase(Phase.PREPARATION)
	return true


func return_to_title() -> void:
	if phase == Phase.TITLE and failure_reason.is_empty():
		return
	failure_reason = ""
	_set_phase(Phase.TITLE)


func _reset_dungeon_state() -> void:
	bag_gold = 0
	has_goal_key = false
	alarm = false
	failure_reason = ""
	_sealed_chest_opened = false


func _can_construct() -> bool:
	return phase == Phase.PREPARATION or phase == Phase.SETTLEMENT


func _is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < tower_levels.size()


func _spend(gold_cost: int) -> bool:
	if gold_cost <= 0 or gold < gold_cost:
		return false
	gold -= gold_cost
	return true


func _set_phase(value: Phase) -> void:
	if phase != value:
		phase = value
		phase_changed.emit(phase)
	changed.emit()
