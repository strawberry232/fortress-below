extends "res://addons/gut/test.gd"


func after_each() -> void:
	get_tree().paused = false
	for index: int in range(4):
		await get_tree().process_frame


func _game() -> Node:
	var game: Node = load("res://game/scenes/main.tscn").instantiate()
	add_child_autofree(game)
	game.start_campaign()
	game.fortress.set_process(false)
	return game


func test_unchanged_hud_reuses_formatted_snapshot_and_repairs_visible_properties() -> void:
	var game: Node = _game()
	assert_true("_hud_cache" in game, "HUD formatting must be cached across unchanged defense frames")
	if not "_hud_cache" in game:
		return
	var snapshot: Array = game.get("_hud_cache")
	for index: int in range(10):
		game._refresh_hud()
	assert_true(is_same(snapshot, game.get("_hud_cache")))
	game.hud_labels[0].text = "stale"
	game.health_bar.value = 1.0
	game._refresh_hud()
	assert_eq(game.hud_labels[0].text, TranslationServer.translate("UI_BANK_GOLD") + " " + str(game.state.gold))
	assert_eq(game.health_bar.value, 100.0)
	game.state.gold = 55
	game._refresh_hud()
	assert_eq(game.hud_labels[0].text, TranslationServer.translate("UI_BANK_GOLD") + " 55")
	assert_false(is_same(snapshot, game.get("_hud_cache")))


func test_phase_changes_health_loot_key_and_enemy_count_invalidate_hud() -> void:
	var game: Node = _game()
	game.enter_dungeon()
	game.dungeon.process_mode = Node.PROCESS_MODE_DISABLED
	game._health_changed(73, 100)
	game.state.collect_gold(25)
	game.state.take_goal_key()
	game._refresh_hud()
	assert_eq(game.hud_labels[0].text, TranslationServer.translate("UI_PLAYER_HP") + " 73")
	assert_eq(game.hud_labels[1].text, TranslationServer.translate("UI_BAG_GOLD") + " 25")
	assert_eq(game.hud_labels[2].text, TranslationServer.translate("UI_KEY_READY"))
	assert_eq(game.health_bar.value, 73.0)
	game._exit_dungeon()
	game.begin_defense()
	game.fortress.set_process(false)
	game._process(0.0)
	assert_eq(game.hud_labels[0].text, TranslationServer.translate("UI_BANK_GOLD") + " 45")
	game.fortress.ledger.pending.clear()
	game.fortress.ledger.alive.clear()
	game._process(0.0)
	assert_eq(game.hud_labels[3].text, TranslationServer.translate("UI_ENEMIES") + " 0")
	game.state.damage_castle(13)
	assert_eq(game.health_bar.value, 87.0)


func test_cached_skill_updates_seconds_progress_and_preserves_pause_dialogs() -> void:
	var game: Node = _game()
	game.state.phase = game.state.Phase.DEFENSE
	game._render_phase(game.state.phase)
	game.fortress.start_wave(false, game.state.tower_levels, 1)
	game.fortress.set_process(false)
	assert_true(game.fortress.activate_rally())
	game._process(0.0)
	assert_eq(game.rally_button.text, TranslationServer.translate("UI_RALLY_ACTIVE"))
	assert_true(game.rally_button.disabled)
	game.fortress.rally_seconds = 0.0
	game.fortress.ledger.rally_cooldown_left = 7.9
	game._process(0.0)
	assert_eq(game.rally_button.text, TranslationServer.translate("UI_RALLY_COOLDOWN") % 8)
	assert_almost_eq(game.rally_bar.value, 4.1, 0.000001)
	game.fortress.ledger.rally_cooldown_left = 7.8
	game._process(0.0)
	assert_eq(game.rally_button.text, TranslationServer.translate("UI_RALLY_COOLDOWN") % 8)
	assert_almost_eq(game.rally_bar.value, 4.2, 0.000001)
	game._open_pause()
	for index: int in range(3):
		await get_tree().process_frame
	assert_eq(game.fortress.ledger.rally_cooldown_left, 7.8)
	game._open_controls()
	game._close_modal()
	assert_true(get_tree().paused)
	assert_eq(game.modal_kind, "pause")
	game._close_modal()
	game.fortress.ledger.rally_cooldown_left = 0.0
	game._process(0.0)
	assert_eq(game.rally_button.text, TranslationServer.translate("UI_RALLY"))
	assert_false(game.rally_button.disabled)
