extends "res://addons/gut/test.gd"

const DUNGEON: Script = preload("res://game/scripts/dungeon/dungeon_world.gd")
const ENEMY: Script = preload("res://game/scripts/combat/fortress_skeleton.gd")
const PLAYER: Script = preload("res://game/scripts/combat/fortress_player.gd")
const BOLT: Script = preload("res://game/scripts/combat/fortress_enemy_projectile.gd")
const DEFENSE: Script = preload("res://game/scripts/defense/fortress_world.gd")

class HitBody extends StaticBody2D:
	var hits: int = 0
	func receive_damage(_amount: int, _identity: String) -> bool:
		hits += 1
		return true

func before_each() -> void:
	for action: String in ["fb_move_left", "fb_move_right", "fb_move_up", "fb_move_down", "fb_sword", "fb_bow", "fb_interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

func _dungeon() -> Node2D:
	var world: Node2D = DUNGEON.new()
	add_child_autofree(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	return world

func _sync() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

func test_real_fatal_sword_cannot_kill_new_children_with_the_same_swing() -> void:
	var world: Node2D = _dungeon()
	world.process_mode = Node.PROCESS_MODE_INHERIT
	world.set_physics_process(false)
	world.player.set_physics_process(false)
	for actor: CharacterBody2D in world._enemies:
		actor.set_physics_process(false)
	var adult: CharacterBody2D
	for enemy: CharacterBody2D in world._enemies:
		if enemy.monster_kind == "slime":
			adult = enemy
	assert_not_null(adult)
	adult.position = Vector2(200, 240)
	adult.health.current = 25
	world.player.position = Vector2(155, 240)
	world.player.facing = 1
	await _sync()
	world.player._start_attack("attack")
	world.player._resolve_sword_hits()
	assert_false(adult.health.is_alive())
	await get_tree().process_frame
	await _sync()
	var babies: Array[CharacterBody2D] = []
	for enemy: CharacterBody2D in world._enemies:
		if is_instance_valid(enemy) and enemy.monster_kind == "slime" and enemy.slime_generation == 1:
			enemy.set_physics_process(false)
			babies.append(enemy)
	assert_eq(babies.size(), 2)
	for baby: CharacterBody2D in babies:
		baby.health.tick(0.3)
	for repeat: int in range(4):
		world.player._resolve_sword_hits()
	for baby: CharacterBody2D in babies:
		assert_eq(baby.health.current, 14, "Both children survive every repeated query belonging to the fatal sword")
	world.player._attack = ""
	world.player._cooldown = 0.0
	world.player._start_attack("attack")
	world.player._resolve_sword_hits()
	var defeated: int = 0
	for baby: CharacterBody2D in babies:
		if not baby.health.is_alive():
			defeated += 1
	assert_gt(defeated, 0, "A later distinct sword attack damages children normally")

func test_birth_grace_protects_children_but_expires_and_rejects_invalid_damage() -> void:
	var baby: CharacterBody2D = ENEMY.new()
	baby.configure_slime_fragment()
	add_child_autofree(baby)
	baby.set_physics_process(false)
	assert_false(baby.receive_damage(25, "new-shot"))
	assert_eq(baby.health.current, 14)
	baby.health.tick(0.24)
	assert_false(baby.receive_damage(25, "other-shot"))
	baby.health.tick(0.02)
	assert_false(baby.receive_damage(0, "zero"))
	assert_false(baby.receive_damage(-1, "negative"))
	assert_true(baby.receive_damage(25, "fresh-sword"))
	assert_false(baby.health.is_alive())

func test_adult_slime_and_vampire_have_separate_elite_dungeon_stats() -> void:
	for kind: String in ["slime", "vampire"]:
		var enemy: CharacterBody2D = ENEMY.new()
		enemy.configure_kind(kind)
		add_child_autofree(enemy)
		enemy.set_physics_process(false)
		assert_eq(enemy.health.maximum, 45 if kind == "slime" else 120)
		if kind == "vampire":
			assert_eq(enemy.attack_damage, 26)
			assert_eq(enemy.speed, 92.0)
	var defense: Node2D = DEFENSE.new()
	add_child_autofree(defense)
	defense.set_process(false)
	var elite: Dictionary = defense.get_enemy_definition("vampire")
	assert_eq(elite["health"], 110)
	assert_eq(elite["speed"], 58.0)
	assert_eq(elite["damage"], 20)
	assert_eq(defense.get_enemy_definition("orc")["health"], 48, "Early defense orcs retain their existing balance")

func test_vampire_wider_swept_lunge_hits_but_still_allows_side_dodging() -> void:
	var player: CharacterBody2D = PLAYER.new()
	player.position = Vector2(160, 241)
	add_child_autofree(player)
	player.set_physics_process(false)
	var enemy: CharacterBody2D = ENEMY.new()
	enemy.configure_kind("vampire")
	enemy.position = Vector2(100, 200)
	enemy.target = player
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	await _sync()
	enemy._attack_elapsed = 0.4
	enemy._attack_direction = Vector2.RIGHT
	enemy._physics_process(0.4)
	assert_eq(player.health.current, 74, "A target 41px off the flight line is within the new 44px range")
	enemy._physics_process(0.2)
	assert_eq(player.health.current, 74, "A lunge remains a single hit")
	player.health.reset()
	player.position = Vector2(300, 247)
	enemy.position = Vector2(244, 200)
	enemy._attack_applied = false
	enemy._attack_elapsed = 0.4
	enemy._physics_process(0.4)
	assert_eq(player.health.current, 100, "Moving beyond the 44px radius remains a valid dodge")

func test_vampire_flight_resists_stagger_but_windup_remains_interruptible() -> void:
	var enemy: CharacterBody2D = ENEMY.new()
	enemy.configure_kind("vampire")
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	enemy._attack_elapsed = 0.6
	assert_true(enemy.receive_damage(25, "flight-hit"))
	assert_eq(enemy.health.current, 95)
	assert_almost_eq(enemy._attack_elapsed, 0.6, 0.001)
	assert_eq(enemy._hurt_left, 0.0, "The elite cannot be permanently staggered during flight")
	enemy.health.tick(0.2)
	enemy._attack_elapsed = 0.2
	assert_true(enemy.receive_damage(25, "windup-hit"))
	assert_eq(enemy._attack_elapsed, -1.0)
	assert_gt(enemy._hurt_left, 0.0)
	enemy.health.tick(0.2)
	enemy._attack_elapsed = 0.6
	enemy.receive_damage(1000, "fatal-flight")
	assert_eq(enemy._attack_elapsed, -1.0, "Fatal damage always interrupts elite flight")

func _body(parent: Node2D, location: Vector2, wall: bool = false) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new() if wall else HitBody.new()
	body.position = location
	body.collision_layer = 1 if wall else 2
	body.collision_mask = 0
	var collision: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(10, 10)
	collision.shape = rectangle
	body.add_child(collision)
	parent.add_child(body)
	return body

func test_enlarged_fireball_hits_with_its_edge_and_still_stops_at_nearer_walls() -> void:
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	var edge_target: StaticBody2D = _body(world, Vector2(100, 216))
	var bolt: Node2D = BOLT.new()
	bolt.position = Vector2(20, 200)
	bolt.velocity = Vector2(1000, 0)
	world.add_child(bolt)
	bolt.set_physics_process(false)
	await _sync()
	bolt._physics_process(0.2)
	assert_eq(edge_target.hits, 1, "The enlarged 12px fireball radius hits beyond the old center ray")
	assert_true(bolt.consumed)
	assert_eq(bolt._sprite.scale, Vector2(1.2, 1.2))
	var blocked_target: StaticBody2D = _body(world, Vector2(350, 216))
	_body(world, Vector2(290, 200), true)
	var second: Node2D = BOLT.new()
	second.position = Vector2(230, 200)
	second.velocity = Vector2(1000, 0)
	world.add_child(second)
	second.set_physics_process(false)
	await _sync()
	second._physics_process(0.2)
	assert_true(second.consumed)
	assert_eq(blocked_target.hits, 0, "Growing the projectile does not permit shooting through a wall")

func test_fireball_initial_overlap_and_near_miss_are_resolved_consistently() -> void:
	var world: Node2D = Node2D.new()
	add_child_autofree(world)
	var overlapping: StaticBody2D = _body(world, Vector2(20, 210))
	var bolt: Node2D = BOLT.new()
	bolt.position = Vector2(20, 200)
	world.add_child(bolt)
	bolt.set_physics_process(false)
	await _sync()
	bolt._physics_process(0.01)
	assert_true(bolt.consumed)
	assert_eq(overlapping.hits, 1)
	var distant: StaticBody2D = _body(world, Vector2(140, 240))
	var miss: Node2D = BOLT.new()
	miss.position = Vector2(80, 200)
	miss.velocity = Vector2(1000, 0)
	world.add_child(miss)
	miss.set_physics_process(false)
	await _sync()
	miss._physics_process(0.1)
	assert_false(miss.consumed)
	assert_eq(distant.hits, 0)

func test_open_door_panels_leave_a_visible_central_gap_for_both_axes() -> void:
	var world: Node2D = _dungeon()
	for gate: Rect2 in [Rect2(300, 160, 16, 96), Rect2(300, 160, 96, 16)]:
		var closed: Dictionary = world.get_gate_visual(gate, false)
		var opened: Dictionary = world.get_gate_visual(gate, true)
		assert_true(opened.has("panels"))
		if not opened.has("panels"):
			continue
		assert_eq(closed["panels"].size(), 1)
		assert_eq(opened["panels"].size(), 2)
		for panel: Dictionary in opened["panels"]:
			assert_false(panel["destination"].has_point(Vector2.ZERO), "An opened door never covers the corridor center")
			assert_true(opened["destination"].encloses(panel["destination"]))
		assert_eq(opened["center"], gate.get_center(), "The drawing still follows the collision gate center")

func test_spike_picture_and_damage_use_the_actual_raised_source_image() -> void:
	var world: Node2D = _dungeon()
	assert_true(world.has_method("get_spike_visual"))
	if not world.has_method("get_spike_visual"):
		return
	for time: float in [0.0, 1.5, 1.999, 2.0, 2.3, 2.999, 3.0]:
		world._clock = time
		var visual: Dictionary = world.get_spike_visual(0)
		assert_eq(visual["active"], world.is_spike_active(0))
		assert_eq(visual["texture"].resource_path, "res://game/assets/dungeon/spikes_idle.png" if visual["active"] else "res://game/assets/dungeon/spikes_active.png", "Source filenames are misleading: idle is raised and active is retracted")
	assert_eq(world.get_spike_visual(-1), {})
	assert_eq(world.get_spike_visual(world._spikes.size()), {})

func test_sealed_chest_warning_is_distinct_before_open_and_clears_afterward() -> void:
	var world: Node2D = _dungeon()
	var ordinary: Dictionary = world.get_chest_visual("ordinary")
	var sealed: Dictionary = world.get_chest_visual("sealed")
	assert_false(ordinary.get("dangerous", true))
	assert_true(sealed.get("dangerous", false))
	assert_ne(sealed.get("tint", Color.WHITE), Color.WHITE)
	assert_eq(sealed.get("warning_key", ""), "")
	assert_eq(sealed.get("indicator", ""), "exclamation")
	world.confirm_sealed_chest()
	assert_false(world.get_chest_visual("sealed").get("dangerous", true))
	assert_eq(world.get_chest_visual("sealed").get("tint", Color.WHITE), sealed["tint"])
	assert_eq(world.get_chest_visual("sealed").get("warning_key", ""), "")
	world.reset_run()
	assert_true(world.get_chest_visual("sealed").get("dangerous", false))

func test_only_campaign_remains_in_menu_state_and_replay() -> void:
	var scene: PackedScene = load("res://game/scenes/main.tscn")
	var game: Node2D = scene.instantiate()
	add_child_autofree(game)
	await get_tree().process_frame
	assert_null(game.find_child("StartDemo", true, false))
	assert_not_null(game.find_child("StartCampaign", true, false))
	assert_false(game.has_method("start_demo"))
	assert_false(game.state.has_method("start_demo"))
	assert_eq(game.state.balance.round_limit, 3)
	game.start_campaign()
	assert_eq(game.state.balance.round_limit, 3)
	game.state.phase = game.state.Phase.COMPLETE
	game._render_phase(game.state.phase)
	game.start_campaign()
	assert_eq(game.state.round_index, 1)
	assert_eq(game.state.balance.round_limit, 3)

func test_armored_skeleton_two_visual_swings_have_distinct_retriable_hit_windows() -> void:
	var player: CharacterBody2D = PLAYER.new()
	player.position = Vector2(160, 300)
	add_child_autofree(player)
	player.set_physics_process(false)
	var enemy: CharacterBody2D = ENEMY.new()
	enemy.configure_kind("armored_skeleton")
	enemy.position = Vector2(100, 300)
	enemy.target = player
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	await _sync()
	enemy._physics_process(0.0)
	enemy._physics_process(0.49)
	assert_eq(player.health.current, 100, "The first strike must wait for source slash frame six")
	enemy._physics_process(0.01)
	assert_eq(player.health.current, 100 - enemy.attack_damage)
	player.health.tick(0.5)
	enemy._physics_process(0.5)
	assert_eq(player.health.current, 100 - enemy.attack_damage, "Normal player protection applies at the beginning of the second swing")
	player.health.tick(0.11)
	enemy._physics_process(0.11)
	assert_eq(player.health.current, 100 - 2 * enemy.attack_damage, "The second source swing retries while active after player protection ends")
	player.health.tick(1.0)
	enemy._physics_process(0.1)
	assert_eq(player.health.current, 100 - 2 * enemy.attack_damage, "Each swing applies at most one accepted hit")

func test_rejected_damage_identity_can_hit_after_protection_expires() -> void:
	var player: CharacterBody2D = PLAYER.new()
	add_child_autofree(player)
	player.set_physics_process(false)
	assert_true(player.receive_damage(10, "first-swing"))
	assert_false(player.receive_damage(10, "second-swing"))
	player.health.tick(0.61)
	assert_true(player.receive_damage(10, "second-swing"), "Rejected damage must not consume this swing's identity")
	player.health.tick(0.61)
	assert_false(player.receive_damage(10, "second-swing"), "A successful swing remains deduplicated")

func test_second_armored_swing_can_hit_after_dodging_the_first() -> void:
	var player: CharacterBody2D = PLAYER.new()
	player.position = Vector2(160, 390)
	add_child_autofree(player)
	player.set_physics_process(false)
	var enemy: CharacterBody2D = ENEMY.new()
	enemy.configure_kind("armored_skeleton")
	enemy.position = Vector2(100, 300)
	enemy.target = player
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	enemy._attack_elapsed = 0.0
	enemy._physics_process(0.55)
	assert_eq(player.health.current, 100)
	player.position = Vector2(160, 300)
	await _sync()
	enemy._physics_process(0.5)
	assert_eq(player.health.current, 100 - enemy.attack_damage, "The second swing is independent of whether the first missed")
	enemy.health.tick(0.2)
	enemy.receive_damage(1, "interrupt-combo")
	player.health.tick(0.7)
	enemy._physics_process(0.1)
	assert_eq(player.health.current, 100 - enemy.attack_damage, "Interrupted combos cannot deliver leftover damage")

func test_castle_attacks_follow_two_armored_swings_and_pause_while_hurt() -> void:
	var world: Node2D = DEFENSE.new()
	add_child_autofree(world)
	world.set_process(false)
	var levels: Array[int] = [1, 0, 0, 0, 0, 0]
	world.start_wave(false, levels, 2)
	world.ledger.pending.assign(["armored_skeleton"])
	world._spawn_enemy()
	var id: int = world.enemies.keys()[0]
	var actor: Dictionary = world.enemies[id]
	var points: PackedVector2Array = actor["points"]
	actor["pos"] = points[points.size() - 1]
	var hits: Array[int] = []
	world.castle_damaged.connect(func(amount: int) -> void: hits.append(amount))
	world._update_enemies(0.0)
	world._update_enemies(0.49)
	assert_eq(hits.size(), 0)
	world._update_enemies(0.02)
	assert_eq(hits.size(), 1)
	world._update_enemies(0.52)
	assert_eq(hits.size(), 2, "Both original armored sword swings damage the castle")
	world._update_enemies(0.1)
	assert_eq(hits.size(), 2)
	actor["hurt_left"] = 0.4
	world._set_enemy_action(actor, "hurt", true)
	world._update_enemies(0.1)
	assert_eq(hits.size(), 2, "A hurt animation never silently deals an attack hit")

func test_melee_windows_read_original_frame_durations() -> void:
	var catalog: Script = load("res://game/data/monsters/monster_catalog.gd")
	assert_eq(catalog.attack_windows("skeleton").size(), 1)
	assert_almost_eq(catalog.attack_windows("skeleton")[0].x, 0.6, 0.0001)
	assert_eq(catalog.attack_windows("armored_skeleton").size(), 2)
	assert_almost_eq(catalog.attack_windows("armored_skeleton")[0].x, 0.5, 0.0001)
	assert_almost_eq(catalog.attack_windows("armored_skeleton")[1].x, 1.0, 0.0001)
	assert_eq(catalog.attack_windows("missing"), [])

func test_defense_elite_drains_only_on_actual_castle_hits_and_keeps_attack_under_arrows() -> void:
	var world: Node2D = DEFENSE.new()
	add_child_autofree(world)
	world.set_process(false)
	var levels: Array[int] = [1, 0, 0, 0, 0, 0]
	world.start_wave(false, levels, 3)
	world.ledger.pending.assign(["vampire"])
	world._spawn_enemy()
	var actor: Dictionary = world.enemies[1]
	actor["pos"] = actor["points"][-1]
	actor["hp"] = 80
	world._update_enemies(0.0)
	world._update_enemies(0.39)
	assert_eq(actor["hp"], 80, "Preparing an attack grants no healing")
	world._update_enemies(0.02)
	assert_eq(actor["hp"], 86, "An actual castle strike heals exactly six elite health")
	actor["hp"] = 108
	world._set_enemy_action(actor, "attack", true)
	actor["clock"] = 0.0
	world._update_enemies(0.41)
	assert_eq(actor["hp"], 110, "Life drain never exceeds maximum health")
	world.arrows.append({"pos": actor["pos"] - Vector2(0, 18), "target": 1, "damage": 8})
	world._update_arrows(0.01)
	assert_eq(actor["hp"], 102)
	assert_eq(actor["action"], "attack", "Arrows flash an attacking elite without replacing its attack animation")
	assert_eq(actor["hurt_left"], 0.0)
	assert_true("vampire_castle_attack_interval" in world.balance)
	if "vampire_castle_attack_interval" in world.balance:
		assert_eq(world.balance.vampire_castle_attack_interval, 1.8)
