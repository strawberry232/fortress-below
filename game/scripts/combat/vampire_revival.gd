extends RefCounted
class_name FortressVampireRevival

const CATALOG: Script = preload("res://game/data/monsters/monster_catalog.gd")
const ASH_DURATION: float = 3.0

var lives_left: int = 1
var pending: bool = false
var elapsed: float = 0.0
var death_duration: float = 0.0
var _kind: String = ""

func reset(kind: String) -> void:
	_kind = kind
	lives_left = 2 if kind == "vampire" else 1
	pending = false
	elapsed = 0.0
	death_duration = CATALOG.action_duration(kind, "death")

func begin_defeat() -> bool:
	if _kind != "vampire" or pending or lives_left <= 1:
		return false
	lives_left -= 1
	pending = true
	elapsed = 0.0
	return true

func total_duration() -> float:
	return death_duration * 2.0 + ASH_DURATION

func advance(delta: float) -> bool:
	if not pending:
		return false
	elapsed = minf(total_duration(), elapsed + maxf(0.0, delta))
	if elapsed + 0.00001 < total_duration():
		return false
	pending = false
	return true

func sample() -> Dictionary:
	if _kind != "vampire" or death_duration <= 0.0:
		return {}
	var phase: String = "dying"
	var animation_time: float = elapsed
	if elapsed + 0.00001 >= death_duration + ASH_DURATION:
		phase = "reforming"
		animation_time = maxf(0.0, death_duration - (elapsed - death_duration - ASH_DURATION) - 0.00001)
	elif elapsed + 0.00001 >= death_duration:
		phase = "ashes"
		animation_time = death_duration
	var result: Dictionary = CATALOG.sample(_kind, "death", animation_time)
	result["phase"] = phase
	return result
