extends "res://addons/gut/test.gd"

const PROJECTILE_PATH: String = "res://game/scripts/combat/fortress_projectile.gd"

class TargetBody extends StaticBody2D:
	var hits: int = 0
	func receive_damage(_amount: int, _attack_id: String) -> bool:
		hits += 1
		return true


func _collision_body(parent: Node2D, x_position: float, is_target: bool) -> StaticBody2D:
	var body: StaticBody2D = TargetBody.new() if is_target else StaticBody2D.new()
	body.position = Vector2(x_position, 200.0)
	body.collision_layer = 4 if is_target else 1
	body.collision_mask = 0
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(20.0, 30.0)
	shape_node.shape = shape
	body.add_child(shape_node)
	parent.add_child(body)
	return body


func test_wall_blocks_arrow_before_target_in_real_physics_world() -> void:
	assert_true(FileAccess.file_exists(PROJECTILE_PATH))
	if not FileAccess.file_exists(PROJECTILE_PATH):
		return
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	_collision_body(world, 100.0, false)
	var target: StaticBody2D = _collision_body(world, 160.0, true)
	var projectile_script: Script = load(PROJECTILE_PATH)
	var arrow: Node2D = projectile_script.new()
	arrow.position = Vector2(20.0, 200.0)
	arrow.velocity = Vector2(1000.0, 0.0)
	world.add_child(arrow)
	arrow.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	arrow._physics_process(0.2)
	assert_eq(target.hits, 0, "The nearer wall receives the ray before the enemy")
	assert_true(arrow.consumed)


func test_arrow_hits_target_once_and_is_consumed() -> void:
	assert_true(FileAccess.file_exists(PROJECTILE_PATH))
	if not FileAccess.file_exists(PROJECTILE_PATH):
		return
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	var target: StaticBody2D = _collision_body(world, 100.0, true)
	var projectile_script: Script = load(PROJECTILE_PATH)
	var arrow: Node2D = projectile_script.new()
	arrow.position = Vector2(20.0, 200.0)
	arrow.velocity = Vector2(1000.0, 0.0)
	world.add_child(arrow)
	arrow.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	arrow._physics_process(0.2)
	arrow._physics_process(0.2)
	assert_eq(target.hits, 1)
	assert_true(arrow.consumed)


func test_arrow_at_bow_height_hits_skeleton_torso_above_foot_collision() -> void:
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	var enemy_script: Script = load("res://game/scripts/combat/fortress_skeleton.gd")
	var enemy: CharacterBody2D = enemy_script.new()
	enemy.position = Vector2(160.0, 300.0)
	world.add_child(enemy)
	enemy.set_physics_process(false)
	var projectile_script: Script = load(PROJECTILE_PATH)
	var arrow: Node2D = projectile_script.new()
	arrow.position = Vector2(20.0, 268.0)
	arrow.velocity = Vector2(1000.0, 0.0)
	world.add_child(arrow)
	arrow.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	arrow._physics_process(0.2)
	assert_eq(enemy.health.current, 25, "Visual torso hits must not miss because movement uses a foot collider")
