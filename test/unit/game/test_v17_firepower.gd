extends "res://addons/gut/test.gd"

const WorldScript = preload("res://game/scripts/defense/fortress_world.gd")
const BalanceScript = preload("res://game/scripts/defense/defense_balance.gd")
const EffectsScript = preload("res://game/scripts/fx/pixel_effects.gd")
const LocaleScript = preload("res://game/scripts/ui/game_locale.gd")
const SKILL_NAME: String = "\u52a0\u5927\u706b\u529b"
const OLD_NAME: String = "\u96c6\u7ed3"

func after_each() -> void:
	get_tree().paused = false
	for index: int in range(4):
		await get_tree().process_frame

func _game() -> Node:
	var game: Node = load("res://game/scenes/main.tscn").instantiate()
	add_child_autofree(game)
	game.start_campaign()
	return game

func _begin_defense(game: Node) -> void:
	game.state.phase = game.state.Phase.DEFENSE
	game._render_phase(game.state.phase)
	game.fortress.start_wave(false, game.state.tower_levels, 1)

func _assert_button_text_fits(button: Button) -> void:
	var font: Font = button.get_theme_font("font")
	var font_size: int = button.get_theme_font_size("font_size")
	assert_eq(font_size, 24)
	assert_lte(font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, button.size.x - 20.0)

func test_player_visible_skill_and_control_text_use_firepower_name() -> void:
	LocaleScript.install()
	assert_eq(TranslationServer.translate("UI_RALLY"), SKILL_NAME)
	for key: String in ["UI_RALLY_READY", "UI_RALLY_ACTIVE", "UI_RALLY_USED", "UI_RALLY_COOLDOWN", "UI_ERR_RALLY_USED", "UI_DEFENSE_HELP", "UI_CONTROLS_DEFENSE", "UI_ROUTE_CLASSIC", "UI_ROUTE_SPLIT"]:
		var text: String = TranslationServer.translate(key)
		assert_false(text.contains(OLD_NAME), key + " must not display the retired skill name")
		assert_true(text.contains(SKILL_NAME), key + " identifies the firepower skill")
	assert_true(TranslationServer.translate("UI_RALLY_DESCRIPTION").contains("50%"))

func test_real_button_reports_active_and_cooldown_without_spending_gold() -> void:
	var game: Node = _game()
	_begin_defense(game)
	game.fortress.set_process(false)
	game._process(0.0)
	assert_eq(game.rally_button.text, SKILL_NAME)
	_assert_button_text_fits(game.rally_button)
	assert_true(game.rally_button.tooltip_text.contains("50%"))
	assert_true(game.rally_button.tooltip_text.contains("4"))
	assert_true(game.rally_button.tooltip_text.contains("12"))
	assert_false(game.rally_button.disabled)
	var gold: int = game.state.gold
	game.rally_button.pressed.emit()
	game._process(0.0)
	assert_eq(game.state.gold, gold)
	assert_eq(game.fortress.rally_seconds, 4.0)
	assert_eq(game.fortress.ledger.rally_cooldown_left, 12.0)
	assert_true(game.rally_button.disabled)
	assert_eq(game.rally_button.text, TranslationServer.translate("UI_RALLY_ACTIVE"))
	_assert_button_text_fits(game.rally_button)
	assert_false(game.fortress.activate_rally())
	game.fortress._process(4.1)
	game._process(0.0)
	assert_eq(game.fortress.rally_seconds, 0.0)
	assert_eq(game.rally_button.text, TranslationServer.translate("UI_RALLY_COOLDOWN") % 8)
	_assert_button_text_fits(game.rally_button)
	game.fortress._process(7.9)
	game._process(0.0)
	assert_false(game.rally_button.disabled)
	assert_eq(game.rally_button.text, SKILL_NAME)
	assert_true(game.fortress.activate_rally())
	assert_eq(game.state.gold, gold)

func test_tooltip_uses_configured_rate_duration_and_cooldown() -> void:
	var game: Node = _game()
	game.fortress.balance.rally_interval_factor = 0.5
	game.fortress.balance.rally_duration = 6.0
	game.fortress.balance.rally_cooldown = 15.0
	_begin_defense(game)
	assert_true(game.rally_button.tooltip_text.contains("100%"))
	assert_true(game.rally_button.tooltip_text.contains("6"))
	assert_true(game.rally_button.tooltip_text.contains("15"))
	assert_eq(game.rally_bar.max_value, 15.0)

func test_firepower_accelerates_all_built_towers_and_preserves_arrow_damage() -> void:
	var world: WorldScript = WorldScript.new()
	add_child_autofree(world)
	world.set_process(false)
	world.start_wave(false, [1, 2, 1, 2, 1, 2])
	world._spawn_enemy()
	world.enemies[1]["pos"] = Vector2(315, 335)
	assert_true(world.activate_rally())
	world._update_towers(0.0)
	assert_eq(world.arrows.size(), 6)
	for slot: int in range(6):
		var interval: float = 0.9 if slot % 2 == 0 else 0.75
		assert_almost_eq(world.tower_clocks[slot], interval * 0.67, 0.0001)
		assert_eq(world.arrows[slot]["damage"], 8 if slot % 2 == 0 else 10)
		assert_almost_eq(interval / world.tower_clocks[slot], 1.492537, 0.001)
	world.rally_seconds = 0.0
	world.tower_clocks.fill(0.0)
	world.arrows.clear()
	world._update_towers(0.0)
	assert_eq(world.arrows.size(), 6)
	for slot: int in range(6):
		assert_almost_eq(world.tower_clocks[slot], 0.9 if slot % 2 == 0 else 0.75, 0.0001)

func test_skill_is_unavailable_outside_defense_and_resets_for_next_wave() -> void:
	var world: WorldScript = WorldScript.new()
	add_child_autofree(world)
	world.set_process(false)
	assert_false(world.activate_rally())
	world.start_wave(false, [1, 0, 0, 0, 0, 0])
	assert_true(world.activate_rally())
	world.prepare([1, 0, 0, 0, 0, 0])
	assert_eq(world.rally_seconds, 0.0)
	assert_eq(world.ledger.rally_cooldown_left, 0.0)
	assert_false(world.activate_rally())
	world.start_wave(false, [1, 0, 0, 0, 0, 0], 2)
	assert_true(world.activate_rally())

func test_real_four_second_tower_firing_emits_more_arrows_on_every_slot() -> void:
	for boosted: bool in [false, true]:
		var world: WorldScript = WorldScript.new()
		add_child_autofree(world)
		world.set_process(false)
		world.start_wave(false, [1, 2, 1, 2, 1, 2])
		world._spawn_enemy()
		world.enemies[1]["pos"] = Vector2(315, 335)
		if boosted:
			assert_true(world.activate_rally())
		world._update_towers(0.0)
		for tick: int in range(400):
			world.rally_seconds = maxf(0.0, world.rally_seconds - 0.01)
			world._update_towers(0.01)
		for slot: int in range(6):
			var count: int = 0
			for arrow: Dictionary in world.arrows:
				if arrow["pos"] == world.get_archer_muzzle(slot):
					count += 1
			assert_eq(count, (7 if slot % 2 == 0 else 8) if boosted else (5 if slot % 2 == 0 else 6), "Each constructed tower emits more arrows during the real four-second buff")
func test_pause_freezes_firepower_duration_and_cooldown_then_resumes() -> void:
	var game: Node = _game()
	_begin_defense(game)
	assert_true(game.fortress.activate_rally())
	game._open_pause()
	var duration: float = game.fortress.rally_seconds
	var cooldown: float = game.fortress.ledger.rally_cooldown_left
	for index: int in range(5):
		await get_tree().process_frame
	assert_eq(game.fortress.rally_seconds, duration)
	assert_eq(game.fortress.ledger.rally_cooldown_left, cooldown)
	assert_true(game.rally_button.disabled)
	game._close_modal()
	for index: int in range(5):
		await get_tree().process_frame
	assert_lt(game.fortress.rally_seconds, duration)
	assert_lt(game.fortress.ledger.rally_cooldown_left, cooldown)

func test_firepower_feedback_uses_existing_burst_instead_of_green_healing() -> void:
	var effects: EffectsScript = EffectsScript.new()
	add_child_autofree(effects)
	var sprite: AnimatedSprite2D = effects.spawn_effect("rally", Vector2(320, 240))
	assert_not_null(sprite)
	if sprite == null:
		return
	var atlas: AtlasTexture = sprite.sprite_frames.get_frame_texture("effect", 0) as AtlasTexture
	assert_true(atlas.atlas.resource_path.ends_with("/fx/burst.png"))
	assert_eq(atlas.region, Rect2(0, 0, 64, 64))
	assert_eq(sprite.global_position, Vector2(320, 240))
	assert_true(sprite.is_playing())

func test_displayed_rate_matches_interval_factor_and_handles_invalid_values() -> void:
	var balance: BalanceScript = BalanceScript.new()
	assert_true(balance.has_method("firepower_boost_percent"))
	if not balance.has_method("firepower_boost_percent"):
		return
	assert_eq(balance.call("firepower_boost_percent"), 50)
	balance.rally_interval_factor = 0.5
	assert_eq(balance.call("firepower_boost_percent"), 100)
	balance.rally_interval_factor = 1.0
	assert_eq(balance.call("firepower_boost_percent"), 0)
	balance.rally_interval_factor = 0.0
	assert_eq(balance.call("firepower_boost_percent"), 900)
	balance.rally_interval_factor = 2.0
	assert_eq(balance.call("firepower_boost_percent"), 0)
