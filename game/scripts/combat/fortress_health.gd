extends RefCounted
class_name FortressHealth

signal health_changed(current: int, maximum: int)
signal died

var maximum: int = 100
var current: int = 100
var protection_duration: float = 0.6
var protection_left: float = 0.0
var _death_emitted: bool = false


func reset(maximum_health: int = 100) -> void:
	maximum = maxi(1, maximum_health)
	current = maximum
	protection_left = 0.0
	_death_emitted = false
	health_changed.emit(current, maximum)


func tick(delta: float) -> void:
	protection_left = maxf(0.0, protection_left - maxf(delta, 0.0))


func apply_damage(amount: int) -> bool:
	if amount <= 0 or current <= 0 or protection_left > 0.00001:
		return false
	current = maxi(0, current - amount)
	protection_left = protection_duration
	health_changed.emit(current, maximum)
	if current == 0 and not _death_emitted:
		_death_emitted = true
		died.emit()
	return true


func heal(amount: int) -> int:
	if amount <= 0 or current <= 0 or current == maximum:
		return 0
	var restored: int = mini(amount, maximum - current)
	current += restored
	health_changed.emit(current, maximum)
	return restored


func is_alive() -> bool:
	return current > 0
