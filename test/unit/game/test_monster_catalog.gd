extends "res://addons/gut/test.gd"

const CATALOG_PATH: String = "res://game/data/monsters/monster_catalog.gd"
const ENEMY_SCRIPT: Script = preload("res://game/scripts/combat/fortress_skeleton.gd")
const DUNGEON_SCRIPT: Script = preload("res://game/scripts/dungeon/dungeon_world.gd")
const PLAYER_SCRIPT: Script = preload("res://game/scripts/combat/fortress_player.gd")
const TYPES: Array[String] = ["skeleton", "armored_skeleton", "skull", "vampire", "orc", "slime"]


func before_each() -> void:
	for action: String in ["fb_move_left", "fb_move_right", "fb_move_up", "fb_move_down", "fb_sword", "fb_bow", "fb_interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func test_catalog_has_six_source_types_and_rejects_unknown_ids() -> void:
	var catalog: Script = load(CATALOG_PATH)
	assert_eq(catalog.TYPES, TYPES)
	assert_eq(catalog.get_definition("missing"), {})
	assert_eq(catalog.sample("skeleton", "missing", 0), {})
	for kind: String in TYPES:
		var definition: Dictionary = catalog.get_definition(kind)
		assert_eq(definition["id"], kind)
		assert_gt(definition["health"], 0)
		assert_gt(definition["speed"], 0.0)
		assert_gt(definition["damage"], 0)
		assert_true(definition["name_key"].begins_with("UI_MONSTER_"))
		for action: String in catalog.ACTIONS:
			var sampled: Dictionary = catalog.sample(kind, action, 0)
			var texture: Texture2D = load(sampled["path"])
			assert_not_null(texture)
			assert_eq(sampled["source"].size, Vector2(definition["frame_size"]))
			assert_gt(catalog.action_duration(kind, action), 0.0)
		definition["animations"].clear()
		assert_eq(catalog.get_definition(kind)["animations"].size(), 5, "Callers cannot mutate shared definitions")

func test_source_actions_have_stable_feet_and_complete_death_feedback() -> void:
	var catalog: Script = load(CATALOG_PATH)
	for kind: String in TYPES:
		var actor: CharacterBody2D = ENEMY_SCRIPT.new()
		assert_true(actor.configure_kind(kind))
		add_child_autofree(actor)
		actor.set_physics_process(false)
		assert_false(actor.configure_kind("skull"))
		assert_eq(actor.monster_kind, kind)
		assert_eq(actor._sprite.sprite_frames.get_animation_names(), PackedStringArray(["attack", "death", "hurt", "idle", "walk"]))
		assert_eq(actor._sprite.scale, Vector2.ONE * catalog.get_definition(kind)["display_scale"])
		var at: Vector2 = actor._sprite.position
		actor.facing = -1
		actor._physics_process(0.016)
		assert_eq(actor._sprite.position, at)
		watch_signals(actor)
		assert_true(actor.receive_damage(1, "first"))
		assert_false(actor.receive_damage(1, "protected"))
		assert_eq(actor._sprite.animation, &"hurt")
		actor.health.tick(0.2)
		assert_true(actor.receive_damage(1000, "fatal"))
		assert_false(actor.receive_damage(1000, "duplicate"))
		if kind == "vampire":
			assert_signal_not_emitted(actor, "defeated", "The first vampire death remains part of its authored two-life encounter")
			actor._physics_process(actor.revival.total_duration())
			assert_eq(actor.health.current, 120)
			actor.health.tick(0.4)
			assert_true(actor.receive_damage(1000, "second-fatal"))
		assert_signal_emit_count(actor, "defeated", 1)
		assert_eq(actor._sprite.animation, &"death")
		assert_true(actor._sprite.is_playing())
		actor._physics_process(0.2)
		assert_false(actor.is_queued_for_deletion())
		assert_gt(actor._sprite.modulate.a, 0.0)
	var invalid: CharacterBody2D = ENEMY_SCRIPT.new()
	assert_false(invalid.configure_kind("missing"))
	invalid.free()

func test_each_dungeon_round_adds_a_type_and_contains_no_goblin_or_orc() -> void:
	var dungeon: Node2D = DUNGEON_SCRIPT.new()
	add_child_autofree(dungeon)
	dungeon.process_mode = Node.PROCESS_MODE_DISABLED
	for round_index: int in range(3):
		dungeon.reset_run(round_index)
		await get_tree().process_frame
		var found: Dictionary = {}
		for enemy: CharacterBody2D in dungeon._enemies:
			assert_true("monster_kind" in enemy)
			if not "monster_kind" in enemy:
				continue
			assert_true(enemy.monster_kind in TYPES and enemy.monster_kind != "orc")
			found[enemy.monster_kind] = true
		assert_eq(found.size(), round_index + 3, "Authored encounters introduce exactly one additional real monster per round")
		assert_true(found.has("skeleton"))
		assert_true(found.has("skull"))
		assert_eq(dungeon._enemies.size(), dungeon.get_level_info()["guardians"].size() + 1)


func test_type_profiles_change_combat_and_keep_explicit_health_overrides() -> void:
	var enemy: CharacterBody2D = ENEMY_SCRIPT.new()
	if not enemy.has_method("configure_kind"):
		assert_true(false, "Source monsters need configurable combat profiles")
		enemy.free()
		return
	var skeleton: CharacterBody2D = ENEMY_SCRIPT.new()
	var armored: CharacterBody2D = ENEMY_SCRIPT.new()
	var skull: CharacterBody2D = ENEMY_SCRIPT.new()
	var vampire: CharacterBody2D = ENEMY_SCRIPT.new()
	armored.configure_kind("armored_skeleton")
	skull.configure_kind("skull")
	vampire.configure_kind("vampire")
	vampire.maximum_health = 90
	for actor: CharacterBody2D in [skeleton, armored, skull, vampire]:
		add_child_autofree(actor)
		actor.set_physics_process(false)
	assert_gt(armored.health.maximum, skeleton.health.maximum)
	assert_lt(armored.speed, skeleton.speed)
	assert_lt(skull.health.maximum, skeleton.health.maximum)
	assert_gt(skull.speed, skeleton.speed)
	assert_gt(vampire.attack_damage, skeleton.attack_damage)
	assert_eq(vampire.health.maximum, 90)
	enemy.free()


func test_each_melee_monster_telegraphs_then_applies_its_profile_damage_once() -> void:
	for kind: String in ["skeleton", "armored_skeleton", "orc", "slime"]:
		var world: Node2D = Node2D.new()
		add_child_autofree(world)
		var player: CharacterBody2D = PLAYER_SCRIPT.new()
		player.position = Vector2(160, 300)
		world.add_child(player)
		player.set_physics_process(false)
		var actor: CharacterBody2D = ENEMY_SCRIPT.new()
		actor.configure_kind(kind)
		actor.position = Vector2(100, 300)
		actor.target = player
		world.add_child(actor)
		actor.set_physics_process(false)
		await get_tree().physics_frame
		await get_tree().physics_frame
		actor._physics_process(0.016)
		assert_eq(actor._attack_elapsed, 0.0)
		var first_window: Vector2 = load(CATALOG_PATH).attack_windows(kind)[0]
		actor._physics_process(first_window.x - 0.02)
		assert_eq(player.health.current, 100, "The telegraph gives time to move before damage")
		actor._physics_process(0.03)
		assert_eq(player.health.current, 100 - actor.attack_damage)
		player.health.tick(1.0)
		actor._physics_process(0.03)
		assert_eq(player.health.current, 100 - actor.attack_damage, "The same source swing must not hit twice")


func test_dungeon_death_emits_one_death_feedback_and_releases_every_collision() -> void:
	var actor: CharacterBody2D = ENEMY_SCRIPT.new()
	actor.configure_kind("armored_skeleton")
	add_child_autofree(actor)
	actor.set_physics_process(false)
	var events: Array[String] = []
	actor.feedback_requested.connect(func(event: String, _at: Vector2) -> void: events.append(event))
	actor.receive_damage(15, "minor")
	assert_eq(actor._sprite.modulate, Color(1.0, 0.5, 0.5))
	actor.health.tick(0.2)
	actor.receive_damage(1000, "fatal")
	actor.receive_damage(1000, "duplicate")
	assert_eq(events, ["enemy_hurt", "enemy_death"])
	await get_tree().process_frame
	assert_eq(actor.collision_layer, 0)
	assert_eq(actor.collision_mask, 0)
	assert_eq(actor._hurt_area.collision_layer, 0)
	actor._physics_process(actor._death_duration + 0.01)
	assert_true(actor.is_queued_for_deletion())


func test_authored_layout_kinds_match_spawned_actors_without_stale_health_fields() -> void:
	var dungeon: Node2D = DUNGEON_SCRIPT.new()
	add_child_autofree(dungeon)
	dungeon.process_mode = Node.PROCESS_MODE_DISABLED
	for level_index: int in range(3):
		dungeon.reset_run(level_index)
		await get_tree().process_frame
		var layout: Dictionary = dungeon.get_level_info()
		assert_false(layout.has("guardian_health"))
		assert_false(layout.has("reward_health"))
		assert_true(layout.has("guardian_kinds"))
		assert_true(layout.has("reward_kind"))
		if not layout.has("guardian_kinds") or not layout.has("reward_kind"):
			continue
		assert_eq(layout["guardian_kinds"].size(), layout["guardians"].size())
		for index: int in range(layout["guardians"].size()):
			assert_eq(dungeon._enemies[index].monster_kind, layout["guardian_kinds"][index])
		assert_eq(dungeon._enemies.back().monster_kind, layout["reward_kind"])
