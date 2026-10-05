extends "res://addons/gut/test.gd"

const HEALTH_PATH: String = "res://game/scripts/combat/fortress_health.gd"
const HIT_PATH: String = "res://game/scripts/combat/fortress_hit_resolver.gd"


func _new_health() -> RefCounted:
	assert_true(FileAccess.file_exists(HEALTH_PATH), "The health implementation exists")
	if not FileAccess.file_exists(HEALTH_PATH):
		return null
	var script: Script = load(HEALTH_PATH)
	return script.new()


func test_damage_protection_and_next_attack() -> void:
	var health: RefCounted = _new_health()
	if health == null:
		return
	health.reset(100)
	assert_true(health.apply_damage(15))
	assert_eq(health.current, 85)
	assert_false(health.apply_damage(15))
	health.tick(0.6)
	assert_true(health.apply_damage(15))
	assert_eq(health.current, 70)


func test_death_once_and_invalid_damage() -> void:
	var health: RefCounted = _new_health()
	if health == null:
		return
	health.reset(10)
	watch_signals(health)
	assert_false(health.apply_damage(0))
	assert_false(health.apply_damage(-1))
	assert_true(health.apply_damage(15))
	health.tick(2.0)
	assert_false(health.apply_damage(15))
	assert_eq(health.current, 0)
	assert_signal_emit_count(health, "died", 1)


func test_heal_clamps_and_full_health_does_not_consume() -> void:
	var health: RefCounted = _new_health()
	if health == null:
		return
	health.reset(100)
	assert_eq(health.heal(30), 0)
	health.apply_damage(15)
	assert_eq(health.heal(30), 15)
	assert_eq(health.current, 100)
	assert_eq(health.heal(-5), 0)


func test_attack_deduplicates_each_target_but_allows_next_attack() -> void:
	assert_true(FileAccess.file_exists(HIT_PATH), "The hit resolver implementation exists")
	if not FileAccess.file_exists(HIT_PATH):
		return
	var hit_script: Script = load(HIT_PATH)
	var resolver: RefCounted = hit_script.new()
	assert_true(resolver.register_hit("sword-1", 11))
	assert_false(resolver.register_hit("sword-1", 11))
	assert_true(resolver.register_hit("sword-1", 12))
	assert_true(resolver.register_hit("sword-2", 11))
	assert_false(resolver.register_hit("", 11))
	assert_false(resolver.register_hit("sword-3", -1))
	resolver.clear_attack("sword-1")
	assert_true(resolver.register_hit("sword-1", 11))
