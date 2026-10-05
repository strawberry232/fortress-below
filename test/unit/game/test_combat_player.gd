extends "res://addons/gut/test.gd"

const PLAYER_SCRIPT: Script = preload("res://game/scripts/combat/fortress_player.gd")
const ENEMY_SCRIPT: Script = preload("res://game/scripts/combat/fortress_skeleton.gd")


func before_each() -> void:
	for action: String in ["fb_move_left", "fb_move_right", "fb_move_up", "fb_move_down", "fb_sword", "fb_bow", "fb_interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func test_sword_active_frames_hit_once_then_next_swing_can_kill() -> void:
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	var player: CharacterBody2D = PLAYER_SCRIPT.new()
	player.position = Vector2(100.0, 300.0)
	world.add_child(player)
	player.set_physics_process(false)
	var enemy: CharacterBody2D = ENEMY_SCRIPT.new()
	enemy.position = Vector2(160.0, 300.0)
	world.add_child(enemy)
	enemy.set_physics_process(false)
	watch_signals(enemy)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player._start_attack("attack")
	player._resolve_sword_hits()
	enemy.health.tick(0.2)
	player._resolve_sword_hits()
	assert_eq(enemy.health.current, 15, "Multiple active frames and both hurtbox/foot results are one sword hit")
	player._physics_process(0.7)
	player._start_attack("attack")
	player._resolve_sword_hits()
	assert_eq(enemy.health.current, 0, "A later swing has a new attack identity")
	assert_signal_emit_count(enemy, "defeated", 1)


func test_sword_does_not_damage_enemy_behind_wall() -> void:
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	var player: CharacterBody2D = PLAYER_SCRIPT.new()
	player.position = Vector2(100.0, 300.0)
	world.add_child(player)
	player.set_physics_process(false)
	var enemy: CharacterBody2D = ENEMY_SCRIPT.new()
	enemy.position = Vector2(160.0, 300.0)
	world.add_child(enemy)
	enemy.set_physics_process(false)
	var wall: StaticBody2D = StaticBody2D.new()
	wall.position = Vector2(130.0, 280.0)
	wall.collision_layer = 1
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(8.0, 60.0)
	shape_node.shape = rectangle
	wall.add_child(shape_node)
	world.add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player._start_attack("attack")
	player._resolve_sword_hits()
	assert_eq(enemy.health.current, 40)


func test_animation_foot_anchor_does_not_move_when_facing_changes() -> void:
	var player: CharacterBody2D = PLAYER_SCRIPT.new()
	add_child_autofree(player)
	player.set_physics_process(false)
	var before: Vector2 = player.get_child(0).position
	var sprite_before: Vector2 = player._sprite.position
	player.facing = -1
	player._physics_process(0.016)
	assert_eq(player.get_child(0).position, before)
	assert_eq(player._sprite.position, sprite_before)
	assert_true(player._sprite.flip_h)


func test_killing_attack_can_disable_world_without_using_removed_physics_body() -> void:
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	var player: CharacterBody2D = PLAYER_SCRIPT.new()
	player.position = Vector2(160.0, 300.0)
	world.add_child(player)
	player.set_physics_process(false)
	player.health.reset(15)
	player.died.connect(func() -> void: world.process_mode = Node.PROCESS_MODE_DISABLED)
	var enemy: CharacterBody2D = ENEMY_SCRIPT.new()
	enemy.position = Vector2(100.0, 300.0)
	enemy.target = player
	world.add_child(enemy)
	enemy.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	enemy._physics_process(0.016)
	enemy._physics_process(0.61)
	assert_eq(player.health.current, 0)
	assert_eq(world.process_mode, Node.PROCESS_MODE_DISABLED)


func test_skeleton_attack_cannot_cross_closed_gate_but_can_hit_after_it_opens() -> void:
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	var player: CharacterBody2D = PLAYER_SCRIPT.new()
	player.position = Vector2(620.0, 268.0)
	world.add_child(player)
	player.set_physics_process(false)
	var enemy: CharacterBody2D = ENEMY_SCRIPT.new()
	enemy.position = Vector2(694.0, 268.0)
	enemy.target = player
	world.add_child(enemy)
	enemy.set_physics_process(false)
	var gate: StaticBody2D = StaticBody2D.new()
	gate.position = Vector2(672.0, 256.0)
	gate.collision_layer = 1
	gate.collision_mask = 0
	var gate_shape: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(20.0, 64.0)
	gate_shape.shape = rectangle
	gate.add_child(gate_shape)
	world.add_child(gate)
	await get_tree().physics_frame
	await get_tree().physics_frame
	enemy._physics_process(0.016)
	enemy._physics_process(0.61)
	assert_eq(player.health.current, 100, "The closed reward-room gate must block the skeleton's sword")
	gate.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	enemy._physics_process(0.8)
	enemy._physics_process(0.016)
	enemy._physics_process(0.61)
	assert_eq(player.health.current, 85, "The same attack range can hit when the gate is gone")
