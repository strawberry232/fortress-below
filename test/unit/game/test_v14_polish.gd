extends "res://addons/gut/test.gd"

const WorldScript = preload("res://game/scripts/defense/fortress_world.gd")
const LedgerScript = preload("res://game/scripts/defense/wave_ledger.gd")
const Catalog = preload("res://game/data/monsters/monster_catalog.gd")
const Enemy = preload("res://game/scripts/combat/fortress_skeleton.gd")

func after_each() -> void:
	get_tree().paused = false
	for index: int in range(4):
		await get_tree().process_frame

func test_goblins_retired_and_first_wave_uses_original_orcs() -> void:
	var ledger: RefCounted = LedgerScript.new()
	for round_number: int in range(1, 4):
		ledger.begin_wave(true, round_number)
		assert_false(ledger.pending.has("torch"))
		assert_false(ledger.pending.has("tnt"))
		if round_number == 1:
			assert_eq(ledger.pending.count("orc"), 6)
	var world: Node = WorldScript.new()
	add_child_autofree(world)
	world.set_process(false)
	assert_eq(world.get_enemy_definition("torch"), {})
	assert_eq(world.get_enemy_definition("tnt"), {})
	assert_false(world.get_enemy_definition("orc").is_empty())

func test_real_attack_hurt_death_animations_and_slime_profile() -> void:
	var catalog: Script = load("res://game/data/monsters/monster_catalog.gd")
	assert_true(catalog.has_method("create_frames"))
	if not catalog.has_method("create_frames"):
		return
	for kind: String in ["skeleton", "armored_skeleton", "vampire", "orc", "slime"]:
		var frames: SpriteFrames = catalog.call("create_frames", kind)
		for action: String in ["idle", "walk", "attack", "hurt", "death"]:
			assert_true(frames.has_animation(action))
			assert_gt(frames.get_frame_count(action), 1)
			assert_eq(frames.get_animation_loop(action), action in ["idle", "walk"])
		var actor: Node = Enemy.new()
		assert_true(actor.configure_kind(kind))
		add_child_autofree(actor)
		actor.set_physics_process(false)
		assert_true(actor.receive_damage(999))
		assert_eq(actor._sprite.animation, &"death")
		assert_true(actor._sprite.is_playing())
		await get_tree().process_frame
		assert_eq(actor.collision_layer, 0)
		assert_eq(actor._hurt_area.collision_layer, 0)
		assert_false(actor.is_queued_for_deletion())

func test_original_frame_counts_timing_and_corpse_lifecycle() -> void:
	var catalog: Script = load("res://game/data/monsters/monster_catalog.gd")
	for entry: Array in [["skeleton", 17], ["armored_skeleton", 15], ["vampire", 14], ["orc", 4], ["slime", 10]]:
		var frames: SpriteFrames = catalog.create_frames(entry[0])
		assert_eq(frames.get_frame_count("death"), entry[1])
		assert_eq(catalog.sample(entry[0], "death", 100)["frame"], entry[1] - 1, "Non-looping deaths hold their actual last frame")
	assert_eq(catalog.sample("orc", "death", 0.31)["frame"], 3)
	assert_eq(catalog.sample("orc", "death", 0.85)["frame"], 3, "The original 600ms final hold is preserved")
	assert_eq(catalog.sample("orc", "idle", -1)["frame"], 0)
	assert_eq(catalog.sample("orc", "idle", 0.61)["frame"], 0)
	var world: Node = WorldScript.new()
	add_child_autofree(world)
	world.set_process(false)
	var levels: Array[int] = [1, 0]
	world.start_wave(false, levels)
	world.ledger.pending = ["orc"] as Array[String]
	world._spawn_enemy()
	world.enemies[1]["pos"] = Vector2(400, 245)
	world.arrows.append({"pos": Vector2(400, 227), "target": 1, "damage": 999})
	world._update_arrows(0.01)
	assert_eq(world.remaining_enemies(), 0)
	assert_true(world.ledger.is_complete(), "A corpse does not remain an alive blocker or a valid target")
	assert_eq(world.corpses.size(), 1)
	assert_eq(world.corpses[0]["action"], "death")
	watch_signals(world)
	world._process(0.01)
	assert_true(world.running, "The final death animation finishes before switching the screen")
	assert_signal_not_emitted(world, "wave_completed")
	world._update_corpses(0.5)
	assert_eq(world.corpses.size(), 1)
	world._update_corpses(1.0)
	assert_eq(world.corpses.size(), 0)
	world._process(0.01)
	assert_false(world.running)
	assert_signal_emit_count(world, "wave_completed", 1)

func test_all_round_routes_match_and_tower_art_cannot_cover_road() -> void:
	var world: Node = WorldScript.new()
	add_child_autofree(world)
	world.set_process(false)
	var original: Array = world.get_route_preview()
	assert_eq(original.size(), 2)
	for round_number: int in range(1, 4):
		world.set_round_preview(round_number)
		assert_eq(world.get_route_preview(), original)
	assert_true(world.has_method("get_tower_visual_bounds"))
	if not world.has_method("get_tower_visual_bounds"):
		return
	for slot: int in range(6):
		var bounds: Rect2 = world.get_tower_visual_bounds(slot)
		for route: Dictionary in original:
			var points: PackedVector2Array = route["points"]
			for segment: int in range(1, points.size()):
				for index: int in range(101):
					var at: Vector2 = points[segment - 1].lerp(points[segment], index / 100.0)
					assert_false(bounds.grow(world.ROAD_HALF_WIDTH + 4).has_point(at), "All visible tower art stays outside either route")

func test_rally_recovers_after_cooldown_and_resets_each_wave() -> void:
	var ledger: RefCounted = LedgerScript.new()
	assert_true(ledger.has_method("tick"))
	if not ledger.has_method("tick"):
		return
	assert_false(ledger.claim_rally())
	ledger.begin_wave(false)
	assert_true(ledger.claim_rally(12.0))
	assert_false(ledger.claim_rally(12.0))
	ledger.tick(-10.0)
	assert_eq(ledger.rally_cooldown_left, 12.0)
	ledger.tick(11.99)
	assert_false(ledger.claim_rally(12.0))
	ledger.tick(0.02)
	assert_true(ledger.claim_rally(12.0))
	ledger.begin_wave(true)
	assert_true(ledger.claim_rally(12.0))

func test_pause_freezes_rally_and_map_clicks_are_guarded_in_combat() -> void:
	var game: Node = load("res://game/scenes/main.tscn").instantiate()
	add_child_autofree(game)
	game.start_campaign()
	game.state.phase = game.state.Phase.DEFENSE
	game._render_phase(game.state.phase)
	game.fortress.start_wave(false, game.state.tower_levels, 1)
	assert_true(game.fortress.activate_rally())
	assert_false(game.fortress._select_tower_at(game.fortress.tower_points[0]))
	game._open_pause()
	var remaining: float = game.fortress.ledger.rally_cooldown_left
	var active: float = game.fortress.rally_seconds
	for index: int in range(5):
		await get_tree().process_frame
	assert_eq(game.fortress.ledger.rally_cooldown_left, remaining)
	assert_eq(game.fortress.rally_seconds, active)
	game._close_modal()
	for index: int in range(5):
		await get_tree().process_frame
	assert_lt(game.fortress.ledger.rally_cooldown_left, remaining)

func test_map_slot_popup_handles_cancel_gold_build_upgrade_and_phase_guards() -> void:
	var game: Node = load("res://game/scenes/main.tscn").instantiate()
	add_child_autofree(game)
	game.start_campaign()
	assert_true(game.has_method("_open_tower_modal"))
	if not game.has_method("_open_tower_modal"):
		return
	assert_null(game.screen.find_child("TowerAction0", true, false))
	game._open_tower_modal(-1)
	assert_eq(game.modal_kind, "")
	game._open_tower_modal(5)
	assert_eq(game.modal_kind, "tower")
	var button: Button = game.modal.find_child("TowerConfirm", true, false)
	assert_not_null(button)
	assert_true(button.disabled)
	game._close_modal()
	assert_eq(game.state.tower_levels[5], 0)
	game.state.gold = 60
	game._open_tower_modal(5)
	game.modal.find_child("TowerConfirm", true, false).pressed.emit()
	assert_eq(game.state.gold, 35)
	assert_eq(game.state.tower_levels[5], 1)
	game._open_tower_modal(5)
	game.modal.find_child("TowerConfirm", true, false).pressed.emit()
	assert_eq(game.state.gold, 0)
	assert_eq(game.state.tower_levels[5], 2)
	game._open_tower_modal(5)
	assert_true(game.modal.find_child("TowerConfirm", true, false).disabled)
	game._close_modal()
	game.enter_dungeon()
	game._open_tower_modal(1)
	assert_eq(game.modal_kind, "")
