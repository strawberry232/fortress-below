extends "res://addons/gut/test.gd"

const SCRIPT_PATH: String = "res://game/scripts/combat/fortress_enemy_projectile.gd"
const PLAYER_SCRIPT: Script = preload("res://game/scripts/combat/fortress_player.gd")

class TargetBody extends StaticBody2D:
	var hits: int = 0
	var last_damage: int = 0
	var last_attack_id: String = ""
	var accept_damage: bool = true

	func receive_damage(amount: int, incoming_id: String) -> bool:
		hits += 1
		last_damage = amount
		last_attack_id = incoming_id
		return accept_damage


func after_each() -> void:
	get_tree().paused = false
	await get_tree().process_frame


func _make_world() -> Node2D:
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	return world


func _body(parent: Node2D, x_position: float, layer: int, accepts_hits: bool = true) -> StaticBody2D:
	var body: StaticBody2D = TargetBody.new() if accepts_hits else StaticBody2D.new()
	body.position = Vector2(x_position, 200.0)
	body.collision_layer = layer
	body.collision_mask = 0
	var collision: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(10.0, 24.0)
	collision.shape = rectangle
	body.add_child(collision)
	parent.add_child(body)
	return body


func _bolt(parent: Node2D, x_position: float = 20.0) -> Node2D:
	assert_true(FileAccess.file_exists(SCRIPT_PATH), "The hostile projectile module must exist")
	if not FileAccess.file_exists(SCRIPT_PATH):
		return null
	var script: Script = load(SCRIPT_PATH)
	var bolt: Node2D = script.new()
	bolt.position = Vector2(x_position, 200.0)
	bolt.velocity = Vector2(1000.0, 0.0)
	bolt.attack_id = "skull-bolt-test"
	parent.add_child(bolt)
	bolt.set_physics_process(false)
	return bolt


func _sync_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func test_nearest_wall_blocks_a_fast_projectile_before_player() -> void:
	var world: Node2D = _make_world()
	_body(world, 75.0, 1, false)
	var player: StaticBody2D = _body(world, 150.0, 2)
	var bolt: Node2D = _bolt(world)
	if bolt == null:
		return
	await _sync_physics()
	bolt._physics_process(0.2)
	assert_true(bolt.consumed)
	assert_eq(player.hits, 0, "The sweep must stop at the nearer solid wall")
	assert_almost_eq(bolt.global_position.x, 58.0, 1.2, "The conservative shape sweep stops before the circle's front reaches the wall")


func test_player_receives_one_hit_with_original_attack_identity() -> void:
	var world: Node2D = _make_world()
	var player: StaticBody2D = _body(world, 100.0, 2)
	var bolt: Node2D = _bolt(world)
	if bolt == null:
		return
	var impacts: Array[Vector2] = []
	bolt.impact_requested.connect(func(at: Vector2) -> void: impacts.append(at))
	await _sync_physics()
	bolt._physics_process(0.2)
	bolt._physics_process(0.2)
	assert_eq(player.hits, 1)
	assert_eq(player.last_damage, 10)
	assert_eq(player.last_attack_id, "skull-bolt-test")
	assert_true(bolt.consumed)
	assert_eq(impacts.size(), 1, "A consumed bolt cannot emit a second impact")


func test_friendly_enemy_layer_and_source_body_are_excluded() -> void:
	var world: Node2D = _make_world()
	var source: StaticBody2D = _body(world, 40.0, 1)
	var enemy: StaticBody2D = _body(world, 65.0, 4)
	var player: StaticBody2D = _body(world, 100.0, 2)
	var bolt: Node2D = _bolt(world)
	if bolt == null:
		return
	bolt.source_body = source
	await _sync_physics()
	bolt._physics_process(0.2)
	assert_eq(source.hits, 0)
	assert_eq(enemy.hits, 0, "Enemy layer four is outside the hostile projectile mask")
	assert_eq(player.hits, 1)
	assert_true(bolt.consumed)


func test_unhandled_player_layer_body_consumes_projectile_safely() -> void:
	var world: Node2D = _make_world()
	_body(world, 70.0, 2, false)
	var farther_player: StaticBody2D = _body(world, 120.0, 2)
	var bolt: Node2D = _bolt(world)
	if bolt == null:
		return
	await _sync_physics()
	bolt._physics_process(0.2)
	assert_true(bolt.consumed)
	assert_eq(farther_player.hits, 0)


func test_invulnerable_or_dead_target_still_consumes_one_projectile() -> void:
	var world: Node2D = _make_world()
	var player: StaticBody2D = _body(world, 100.0, 2)
	player.accept_damage = false
	var bolt: Node2D = _bolt(world)
	if bolt == null:
		return
	await _sync_physics()
	bolt._physics_process(0.2)
	bolt._physics_process(0.2)
	assert_eq(player.hits, 1)
	assert_true(bolt.consumed, "A rejected damage call must not leave a repeating hitbox")


func test_real_player_protection_and_dead_state_are_respected() -> void:
	var world: Node2D = _make_world()
	var player: CharacterBody2D = PLAYER_SCRIPT.new()
	player.position = Vector2(100.0, 212.0)
	world.add_child(player)
	player.set_physics_process(false)
	player.receive_damage(5, "earlier-hit")
	var first: Node2D = _bolt(world)
	if first == null:
		return
	await _sync_physics()
	first._physics_process(0.2)
	assert_true(first.consumed)
	assert_eq(player.health.current, 95, "A hit during protection must not remove health")
	player.health.tick(2.0)
	player.receive_damage(1000, "fatal-before-bolt")
	var second: Node2D = _bolt(world)
	await _sync_physics()
	second._physics_process(0.2)
	assert_true(second.consumed)
	assert_eq(player.health.current, 0, "A dead player never receives additional damage")


func test_negative_delta_is_ignored_and_lifetime_expires_without_impact() -> void:
	var world: Node2D = _make_world()
	var player: StaticBody2D = _body(world, 100.0, 2)
	var bolt: Node2D = _bolt(world)
	if bolt == null:
		return
	var initial_time: float = bolt.lifetime
	var impacts: Array[Vector2] = []
	bolt.impact_requested.connect(func(at: Vector2) -> void: impacts.append(at))
	bolt._physics_process(-1.0)
	assert_eq(bolt.position, Vector2(20.0, 200.0))
	assert_eq(bolt.lifetime, initial_time)
	bolt._physics_process(0.0)
	assert_eq(bolt.position, Vector2(20.0, 200.0))
	bolt.lifetime = 0.1
	await _sync_physics()
	bolt._physics_process(0.2)
	assert_true(bolt.consumed)
	assert_eq(player.hits, 0)
	assert_eq(impacts.size(), 0, "Expiry silently removes the projectile")


func test_freed_source_is_safe_and_zero_velocity_does_not_reverse_motion() -> void:
	var world: Node2D = _make_world()
	var source: StaticBody2D = _body(world, 50.0, 4)
	var bolt: Node2D = _bolt(world)
	if bolt == null:
		return
	bolt.source_body = source
	source.free()
	bolt.velocity = Vector2.ZERO
	await _sync_physics()
	bolt._physics_process(0.1)
	assert_eq(bolt.position, Vector2(20.0, 200.0))
	assert_false(bolt.consumed)
	bolt.velocity = Vector2(100.0, -100.0)
	bolt._physics_process(0.1)
	assert_eq(bolt.position, Vector2(30.0, 190.0))


func test_original_blue_fire_atlas_loops_only_visible_flight_frames() -> void:
	var world: Node2D = _make_world()
	var bolt: Node2D = _bolt(world)
	if bolt == null:
		return
	var sprite: AnimatedSprite2D = bolt.get_node_or_null("BoltSprite") as AnimatedSprite2D
	assert_not_null(sprite)
	if sprite == null:
		return
	assert_eq(sprite.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(bolt.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_true(sprite.sprite_frames.get_animation_loop("flight"))
	assert_eq(sprite.sprite_frames.get_frame_count("flight"), 4)
	for index: int in range(4):
		var atlas: AtlasTexture = sprite.sprite_frames.get_frame_texture("flight", index) as AtlasTexture
		assert_not_null(atlas)
		assert_eq(atlas.region, Rect2((index + 1) * 64, 128, 64, 64))
		assert_eq(atlas.atlas.resource_path, "res://game/assets/fx/skull_bolt.png")
	assert_eq(sprite.rotation, 0.0)
	assert_true(sprite.is_playing())


func test_blue_impact_runs_once_and_cleans_up_after_wall_hit() -> void:
	var world: Node2D = _make_world()
	_body(world, 100.0, 1, false)
	var bolt: Node2D = _bolt(world)
	if bolt == null:
		return
	await _sync_physics()
	bolt._physics_process(0.2)
	var impact: AnimatedSprite2D = world.get_node_or_null("SkullImpact") as AnimatedSprite2D
	assert_not_null(impact)
	if impact == null:
		return
	assert_eq(impact.global_position, bolt.global_position)
	assert_false(impact.sprite_frames.get_animation_loop("impact"))
	assert_eq(impact.sprite_frames.get_frame_count("impact"), 8)
	var atlas: AtlasTexture = impact.sprite_frames.get_frame_texture("impact", 0) as AtlasTexture
	assert_eq(atlas.region, Rect2(0, 128, 64, 64))
	assert_eq(atlas.atlas.resource_path, "res://game/assets/fx/skull_impact.png")
	await wait_seconds(0.7)
	assert_false(is_instance_valid(impact), "The non-looping impact must release its node")


func test_projectile_spawned_inside_wall_is_consumed_before_hitting_player() -> void:
	var world: Node2D = _make_world()
	_body(world, 20.0, 1, false)
	var player: StaticBody2D = _body(world, 100.0, 2)
	var bolt: Node2D = _bolt(world)
	if bolt == null:
		return
	await _sync_physics()
	bolt._physics_process(0.2)
	assert_true(bolt.consumed)
	assert_eq(player.hits, 0, "A projectile cannot escape through a wall containing its muzzle")


func test_real_pause_freezes_motion_lifetime_and_animation_until_resume() -> void:
	var world: Node2D = _make_world()
	var bolt: Node2D = _bolt(world)
	if bolt == null:
		return
	bolt.velocity = Vector2(190.0, 0.0)
	bolt.lifetime = 10.0
	bolt.set_physics_process(true)
	await get_tree().create_timer(0.1).timeout
	assert_gt(bolt.position.x, 20.0)
	get_tree().paused = true
	var before_position: Vector2 = bolt.position
	var before_lifetime: float = bolt.lifetime
	var sprite: AnimatedSprite2D = bolt.get_node("BoltSprite") as AnimatedSprite2D
	var before_frame: int = sprite.frame
	var before_progress: float = sprite.frame_progress
	await get_tree().create_timer(0.2, true).timeout
	var paused_position: Vector2 = bolt.position
	var paused_lifetime: float = bolt.lifetime
	var paused_frame: int = sprite.frame
	var paused_progress: float = sprite.frame_progress
	get_tree().paused = false
	assert_eq(paused_position, before_position)
	assert_eq(paused_lifetime, before_lifetime)
	assert_eq(paused_frame, before_frame)
	assert_eq(paused_progress, before_progress)
	await get_tree().create_timer(0.1).timeout
	assert_gt(bolt.position.x, before_position.x)
	assert_lt(bolt.lifetime, before_lifetime)


func test_disabled_dungeon_parent_freezes_projectile_and_impact_until_reenabled() -> void:
	var world: Node2D = _make_world()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	var player: StaticBody2D = _body(world, 60.0, 2)
	var bolt: Node2D = _bolt(world)
	if bolt == null:
		return
	bolt.velocity = Vector2(190.0, 0.0)
	bolt.lifetime = 10.0
	bolt._spawn_impact()
	var impact: AnimatedSprite2D = world.get_node("SkullImpact") as AnimatedSprite2D
	bolt.set_physics_process(true)
	await get_tree().create_timer(0.05).timeout
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var before_position: Vector2 = bolt.position
	var before_lifetime: float = bolt.lifetime
	var before_hits: int = player.hits
	var before_frame: int = impact.frame
	var before_progress: float = impact.frame_progress
	await get_tree().create_timer(0.15, true).timeout
	var bolt_still_exists: bool = is_instance_valid(bolt)
	assert_true(bolt_still_exists, "A disabled dungeon cannot let a bolt hit the old player and free itself")
	assert_eq(player.hits, before_hits, "A hidden, disabled dungeon must never damage its player")
	if bolt_still_exists:
		assert_eq(bolt.position, before_position)
		assert_eq(bolt.lifetime, before_lifetime)
		assert_false(bolt.can_process())
	assert_true(is_instance_valid(impact))
	if is_instance_valid(impact):
		assert_eq(impact.frame, before_frame)
		assert_eq(impact.frame_progress, before_progress)
		assert_false(impact.can_process())
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	if bolt_still_exists:
		assert_true(bolt.can_process())
		await get_tree().create_timer(0.25).timeout
		assert_eq(player.hits, before_hits + 1, "Reenabled content resumes its remaining projectile travel")
