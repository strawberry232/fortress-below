extends "res://addons/gut/test.gd"

const ENEMY: Script = preload("res://game/scripts/combat/fortress_skeleton.gd")
const PLAYER: Script = preload("res://game/scripts/combat/fortress_player.gd")

func before_each() -> void:
	for action: String in ["fb_move_left", "fb_move_right", "fb_move_up", "fb_move_down", "fb_sword", "fb_bow", "fb_interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

func _pair(kind: String, distance: float = 180.0) -> Array[CharacterBody2D]:
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	var player: CharacterBody2D = PLAYER.new()
	player.position = Vector2(100.0 + distance, 300.0)
	world.add_child(player)
	player.set_physics_process(false)
	var enemy: CharacterBody2D = ENEMY.new()
	enemy.configure_kind(kind)
	enemy.position = Vector2(100.0, 300.0)
	enemy.target = player
	world.add_child(enemy)
	enemy.set_physics_process(false)
	return [enemy, player]

func _wall(parent: Node, x: float) -> void:
	var wall: StaticBody2D = StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = Vector2(x, 285.0)
	var collider: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(20.0, 180.0)
	collider.shape = rectangle
	wall.add_child(collider)
	parent.add_child(wall)

func test_adult_slime_is_larger_and_fragments_have_half_scale_and_health() -> void:
	var adult: CharacterBody2D = ENEMY.new()
	adult.configure_kind("slime")
	add_child_autofree(adult)
	adult.set_physics_process(false)
	assert_eq(adult._sprite.scale, Vector2(4.0, 4.0))
	var child: CharacterBody2D = ENEMY.new()
	assert_true(child.has_method("configure_slime_fragment"), "Fragments need explicit pre-ready configuration")
	if not child.has_method("configure_slime_fragment"):
		child.free()
		return
	assert_true(child.call("configure_slime_fragment"))
	assert_false(child.call("configure_slime_fragment"), "A configured child cannot become another generation")
	add_child_autofree(child)
	child.set_physics_process(false)
	assert_eq(child.monster_kind, "slime")
	assert_eq(child.get("slime_generation"), 1)
	assert_eq(child._sprite.scale, Vector2(2.0, 2.0))
	assert_eq(child.health.maximum, 14)
	assert_eq(child.attack_damage, 6)
	assert_false(child.call("configure_slime_fragment"), "Ready actors cannot change geometry")
	assert_lt(child._hurt_area.get_child(0).shape.size.x, adult._hurt_area.get_child(0).shape.size.x)

func test_vampire_telegraphs_then_lunges_and_recovers_for_source_duration() -> void:
	var pair: Array[CharacterBody2D] = _pair("vampire", 180.0)
	var enemy: CharacterBody2D = pair[0]
	await get_tree().physics_frame
	enemy._physics_process(0.016)
	assert_eq(enemy._attack_elapsed, 0.0, "A vampire can initiate a leap beyond melee range")
	var start: Vector2 = enemy.position
	enemy._physics_process(0.3)
	assert_eq(enemy.position, start, "Windup provides a visible dodge window")
	assert_eq(pair[1].health.current, 100)
	enemy._physics_process(0.15)
	assert_gt(enemy.position.x, start.x, "Existing flight frames now actually move the actor")
	for index: int in range(10):
		enemy._physics_process(0.08)
	assert_gt(enemy.position.x - start.x, 100.0)
	assert_gt(enemy._attack_elapsed, 0.0, "Landing recovery is retained")
	assert_eq(enemy._sprite.animation, &"attack")
	enemy._physics_process(0.4)
	assert_eq(enemy._attack_elapsed, -1.0)

func test_vampire_direction_is_locked_and_active_frames_hit_only_once() -> void:
	var pair: Array[CharacterBody2D] = _pair("vampire", 100.0)
	var enemy: CharacterBody2D = pair[0]
	await get_tree().physics_frame
	enemy._physics_process(0.016)
	for index: int in range(14):
		enemy._physics_process(0.08)
		pair[1].health.tick(0.08)
	assert_eq(pair[1].health.current, 74, "A single elite lunge deals one configured hit")
	var at: float = enemy.position.x
	pair[1].position = Vector2(20.0, 300.0)
	enemy._physics_process(0.04)
	assert_gte(enemy.position.x, at, "The leap cannot home behind the vampire")
	assert_eq(enemy.facing, 1)

func test_vampire_leap_respects_walls_and_hurt_cancels_it() -> void:
	var pair: Array[CharacterBody2D] = _pair("vampire", 180.0)
	var enemy: CharacterBody2D = pair[0]
	await get_tree().physics_frame
	enemy._physics_process(0.016)
	_wall(enemy.get_parent(), 165.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for index: int in range(14):
		enemy._physics_process(0.08)
	assert_lt(enemy.position.x, 144.0, "The forward lunge stops before the wall")
	assert_eq(pair[1].health.current, 100, "The target behind a wall cannot take a lunge hit")
	enemy._attack_elapsed = 0.2
	assert_true(enemy.receive_damage(1, "interrupt"))
	var stopped: Vector2 = enemy.position
	enemy._physics_process(0.1)
	assert_eq(enemy.position, stopped)
	assert_eq(enemy._attack_elapsed, -1.0)
	assert_eq(enemy._sprite.animation, &"hurt")

func test_vampire_lunge_does_not_pass_a_close_target_before_damage_window() -> void:
	var pair: Array[CharacterBody2D] = _pair("vampire", 40.0)
	await get_tree().physics_frame
	pair[0]._physics_process(0.016)
	for index: int in range(14):
		pair[0]._physics_process(0.08)
		pair[1].health.tick(0.08)
	assert_eq(pair[1].health.current, 74, "A close target intersected during flight receives exactly one elite lunge hit")

func test_skull_moves_fast_and_detects_targets_beyond_old_range() -> void:
	var pair: Array[CharacterBody2D] = _pair("skull", 500.0)
	assert_gte(pair[0].speed, 110.0)
	await get_tree().physics_frame
	pair[0]._physics_process(0.016)
	assert_gt(pair[0].velocity.x, 0.0, "Wide sensing acquires a target beyond 380px")
	pair[1].position = Vector2(1000.0, 300.0)
	pair[0]._physics_process(0.016)
	assert_eq(pair[0].velocity, Vector2.ZERO, "Sensing still has a finite limit")

func test_skull_uses_one_aimed_ranged_shot_after_charge_without_melee_damage() -> void:
	var pair: Array[CharacterBody2D] = _pair("skull", 240.0)
	var skull: CharacterBody2D = pair[0]
	assert_true(skull.has_signal("ranged_shot_requested"), "Skull attacks create a dodgeable projectile")
	if not skull.has_signal("ranged_shot_requested"):
		return
	watch_signals(skull)
	await get_tree().physics_frame
	skull._physics_process(0.016)
	assert_eq(skull._attack_elapsed, 0.0)
	skull._physics_process(0.2)
	assert_signal_not_emitted(skull, "ranged_shot_requested")
	skull._physics_process(0.25)
	assert_signal_emit_count(skull, "ranged_shot_requested", 1)
	assert_eq(pair[1].health.current, 100, "A skull cannot deal instantaneous ranged damage")
	skull._physics_process(0.3)
	assert_signal_emit_count(skull, "ranged_shot_requested", 1)
	var arguments: Array = get_signal_parameters(skull, "ranged_shot_requested")
	assert_eq(arguments[0], skull.global_position + Vector2(0.0, -12.0))
	assert_eq(arguments[1], Vector2.RIGHT)
	assert_eq(arguments[2], 10)
	assert_false(String(arguments[3]).is_empty())

func test_skull_cannot_cast_through_wall_and_hurt_interrupts_charge() -> void:
	var pair: Array[CharacterBody2D] = _pair("skull", 240.0)
	var skull: CharacterBody2D = pair[0]
	if not skull.has_signal("ranged_shot_requested"):
		assert_true(false, "Skull projectile signal is required")
		return
	watch_signals(skull)
	_wall(skull.get_parent(), 180.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	skull._physics_process(0.016)
	skull._physics_process(0.6)
	assert_signal_not_emitted(skull, "ranged_shot_requested")
	var clear_pair: Array[CharacterBody2D] = _pair("skull", 240.0)
	var clear_skull: CharacterBody2D = clear_pair[0]
	watch_signals(clear_skull)
	await get_tree().physics_frame
	clear_skull._physics_process(0.016)
	clear_skull.receive_damage(1, "cancel-cast")
	clear_skull._physics_process(0.5)
	assert_signal_not_emitted(clear_skull, "ranged_shot_requested")
	clear_pair[1].receive_damage(1000, "dead-target")
	clear_skull._physics_process(0.5)
	assert_signal_not_emitted(clear_skull, "ranged_shot_requested")
