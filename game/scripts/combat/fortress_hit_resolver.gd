extends RefCounted
class_name FortressHitResolver

var _hits: Dictionary = {}


func register_hit(attack_id: String, target_id: int) -> bool:
	if attack_id.is_empty() or target_id < 0:
		return false
	if not _hits.has(attack_id):
		_hits[attack_id] = {}
	var targets: Dictionary = _hits[attack_id]
	if targets.has(target_id):
		return false
	targets[target_id] = true
	return true


func clear_attack(attack_id: String) -> void:
	_hits.erase(attack_id)
