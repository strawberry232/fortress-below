extends RefCounted

var pending: Array[String] = []
var alive: Dictionary = {}
var rally_used: bool = false
var rally_cooldown_left: float = 0.0
var initialized: bool = false

const ROUND_PATTERNS: Array[Array] = [
	["orc"],
	["skeleton", "skull", "skeleton", "armored_skeleton"],
	["skeleton", "armored_skeleton", "skull", "vampire"]
]
const ALARM_KINDS: Array[String] = ["armored_skeleton", "vampire", "vampire"]

static func alarm_enemy_kind(round_index: int) -> String:
	return ALARM_KINDS[clampi(round_index - 1, 0, ALARM_KINDS.size() - 1)]

static func alarm_enemy_count(_round_index: int) -> int:
	return 1

func reset() -> void:
	pending.clear()
	alive.clear()
	rally_used = false
	rally_cooldown_left = 0.0
	initialized = false

func begin_wave(alarm: bool, round_index: int = 1, wave_sizes: Array[int] = [6, 8, 10]) -> void:
	reset()
	initialized = true
	var round_slot: int = clampi(round_index - 1, 0, 2)
	var count: int = wave_sizes[round_slot] if wave_sizes.size() >= 3 else 6 + round_slot * 2
	for index: int in range(maxi(1, count)):
		var pattern: Array = ROUND_PATTERNS[round_slot]
		pending.append(pattern[index % pattern.size()])
	if alarm:
		pending.append(alarm_enemy_kind(round_index))

func spawn_next(enemy_id: int) -> String:
	if enemy_id <= 0 or alive.has(enemy_id) or pending.is_empty():
		return ""
	var kind: String = pending.pop_front()
	alive[enemy_id] = true
	return kind

func mark_dead(enemy_id: int) -> bool:
	if not alive.has(enemy_id):
		return false
	alive.erase(enemy_id)
	return true

func is_complete() -> bool:
	return initialized and pending.is_empty() and alive.is_empty()

func tick(delta: float) -> void:
	rally_cooldown_left = maxf(0.0, rally_cooldown_left - maxf(0.0, delta))

func claim_rally(cooldown: float = 12.0) -> bool:
	if not initialized or rally_cooldown_left > 0.0 or cooldown <= 0.0:
		return false
	rally_used = true
	rally_cooldown_left = cooldown
	return true
