extends "res://addons/gut/test.gd"

func after_each() -> void:
	get_tree().paused = false
	for index: int in range(4):
		await get_tree().process_frame

func _game() -> Node:
	var game: Node = load("res://game/scenes/main.tscn").instantiate()
	add_child_autofree(game)
	return game

func test_preparation_has_six_enabled_build_actions_and_no_wood_hud() -> void:
	var game: Node = _game()
	game.start_campaign()
	for slot: int in range(6):
		assert_null(game.screen.find_child("TowerAction" + str(slot), true, false))
		assert_true(game.fortress._select_tower_at(game.fortress.tower_points[slot]))
		assert_eq(game.modal_kind, "tower")
		assert_eq(game.selected_slot, slot)
		assert_not_null(game.modal.find_child("TowerConfirm", true, false))
		game._close_modal()
	var font: Font = game.game_theme.default_font
	assert_true(font is FontFile, "The user-supplied pixel font must be the actual theme font")
	assert_true(game.hud_labels[1].text.contains("1 / 6"))
	assert_eq(game.hud_labels[1].text, TranslationServer.translate("UI_TOWERS_BUILT") + " 1 / 6")
	var backdrop: Panel = game.screen.find_child("CostBackdrop", true, false)
	assert_not_null(backdrop, "Ground texture must not reduce the readability of construction prices")
	if backdrop != null:
		assert_gte(backdrop.position.y, 640.0)
		assert_lte(backdrop.position.y + backdrop.size.y, 708.0, "Prices keep a safe margin above the screen edge")

func test_sixth_tower_button_spends_only_gold_and_ui_tracks_built_count() -> void:
	var game: Node = _game()
	game.start_campaign()
	game.state.gold = 25
	game._open_tower_modal(5)
	var button: Button = game.modal.find_child("TowerConfirm", true, false)
	assert_not_null(button)
	if button == null:
		return
	button.pressed.emit()
	assert_eq(game.state.gold, 0)
	assert_eq(game.state.tower_levels, [1, 0, 0, 0, 0, 1])
	assert_true(game.hud_labels[1].text.contains("2 / 6"))
	game._tower_action(-1)
	game._tower_action(6)
	assert_eq(game.state.gold, 0)
	assert_eq(game.state.tower_levels[5], 1)

func test_seal_prompt_and_wave_queue_match_for_every_round_and_reward_is_not_hardcoded() -> void:
	var game: Node = _game()
	var ledger_script: GDScript = load("res://game/scripts/defense/wave_ledger.gd")
	var catalog: GDScript = load("res://game/data/monsters/monster_catalog.gd")
	game.start_campaign()
	assert_true(ledger_script.has_method("alarm_enemy_kind"))
	if not ledger_script.has_method("alarm_enemy_kind") or catalog == null:
		return
	for round_number: int in range(1, 4):
		game.state.phase = game.state.Phase.PREPARATION
		game.state.round_index = round_number
		game.state.balance.sealed_chest_gold = 23
		game.enter_dungeon()
		game._open_sealed_modal()
		var description: Label = game.modal.find_child("SealedDescription", true, false)
		assert_not_null(description)
		var kind: String = ledger_script.alarm_enemy_kind(round_number)
		var definition: Dictionary = catalog.get_definition(kind)
		if description != null:
			assert_true(description.text.contains("23"))
			assert_true(description.text.contains(TranslationServer.translate(definition["name_key"])))
		var ordinary: RefCounted = ledger_script.new()
		var alarm: RefCounted = ledger_script.new()
		ordinary.begin_wave(false, round_number)
		alarm.begin_wave(true, round_number)
		assert_eq(alarm.pending.size() - ordinary.pending.size(), ledger_script.alarm_enemy_count(round_number))
		assert_eq(alarm.pending.back(), kind)
		game._close_modal()

func _check_text_fits(label: Label, context: String) -> void:
	var font_size: int = label.get_theme_font_size("font_size")
	assert_gte(font_size, 24, context + " readable minimum font size")
	assert_eq(font_size % 12, 0, context + " integer pixel scaling")
	assert_lte(label.get_minimum_size().y, label.size.y, context + " text height fits its rectangle")
	for line: String in label.text.split("\n"):
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			assert_lte(label.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, label.size.x, context + " text width fits its rectangle")

func _check_hud_labels_fit(game: Node, context: String) -> void:
	for label: Label in game.hud_labels:
		var font: Font = label.get_theme_font("font")
		var font_size: int = label.get_theme_font_size("font_size")
		assert_lte(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, 164.0, context + " actual text fits the fixed HUD width")
		assert_eq(label.get_line_count(), 1, context + " actual HUD text stays on one line")
		assert_lte(label.position.y + label.size.y, 85.0, context + " actual HUD stays above the health bar")

func test_local_twelve_pixel_font_keeps_six_tower_controls_and_header_readable() -> void:
	var game: Node = _game()
	game.start_campaign()
	await get_tree().process_frame
	assert_eq(game.game_theme.default_font.resource_name, "Fusion Pixel 12px Simplified Chinese")
	for slot: int in range(6):
		game._open_tower_modal(slot)
		await get_tree().process_frame
		for label: Label in game.modal.find_children("*", "Label", true, false):
			_check_text_fits(label, "Tower popup " + str(slot))
		var button: Button = game.modal.find_child("TowerConfirm", true, false)
		assert_eq(button.get_theme_font_size("font_size"), 24)
		game._close_modal()
		await get_tree().process_frame
	_check_text_fits(game.message_label, "Preparation message")
	assert_eq(game.message_label.get_line_count(), 2)
	assert_lte(game.message_label.position.y + game.message_label.size.y, 238.0)
	for label: Label in game.hud_labels:
		_check_text_fits(label, "Header " + label.text)
		assert_eq(label.get_line_count(), 1)
		assert_eq(label.get_theme_font("font").resource_name, "Fusion Pixel 12px Simplified Chinese")
	_check_hud_labels_fit(game, "Preparation")
	assert_eq(game.sound_button.get_theme_font_size("font_size"), 24)
	assert_lte(game.sound_button.position.x + game.sound_button.size.x, 1152.0)
	for label: Label in game.screen.find_children("*", "Label", true, false):
		_check_text_fits(label, "Preparation label " + label.text)
	game.state.phase = game.state.Phase.SETTLEMENT
	game._render_phase(game.state.phase)
	await get_tree().process_frame
	_check_text_fits(game.message_label, "Settlement message")
	assert_eq(game.message_label.get_line_count(), 2)
	assert_lte(game.message_label.position.y + game.message_label.size.y, 238.0)
	game.state.gold = 999
	var built_levels: Array[int] = [2, 2, 2, 2, 2, 2]
	game.state.tower_levels = built_levels
	game.state.round_index = 3
	game._refresh_hud()
	await get_tree().process_frame
	_check_hud_labels_fit(game, "Settlement with six towers and three-digit gold")

func test_twelve_pixel_help_content_and_dungeon_footer_do_not_overlap_actions() -> void:
	var game: Node = _game()
	game.start_campaign()
	game._open_controls()
	await get_tree().process_frame
	var labels: Array[Node] = game.modal.find_children("*", "Label", true, false)
	assert_eq(labels.size(), 3)
	if labels.size() == 3:
		var first: Label = labels[1]
		var second: Label = labels[2]
		_check_text_fits(first, "Dungeon controls")
		_check_text_fits(second, "Defense controls")
		assert_lte(first.position.y + first.size.y, second.position.y)
		assert_lte(second.position.y + second.size.y, 411.0)
	game._close_modal()
	game.enter_dungeon()
	await get_tree().process_frame
	_check_text_fits(game.message_label, "Dungeon footer")
	assert_lte(game.message_label.position.y + game.message_label.size.y, 700.0)
	_check_hud_labels_fit(game, "Dungeon before finding a key or seal")
	game.state.alarm = true
	game._refresh_hud()
	await get_tree().process_frame
	assert_eq(game.hud_labels[3].get_line_count(), 1, "Active seal reinforcement status stays above the health bar")
	assert_lte(game.hud_labels[3].position.y + game.hud_labels[3].size.y, 85.0)
	game.state.has_goal_key = true
	game.state.bag_gold = 45
	game._refresh_hud()
	await get_tree().process_frame
	_check_hud_labels_fit(game, "Dungeon with key, loot, and seal reinforcement")
	game.state.phase = game.state.Phase.DEFENSE
	game.state.round_index = 3
	game._render_phase(game.state.phase)
	game.fortress.start_wave(true, game.state.tower_levels, 3)
	game._refresh_hud()
	await get_tree().process_frame
	_check_hud_labels_fit(game, "Defense with two-digit enemy count")
	_check_text_fits(game.message_label, "Defense help")
	assert_lte(game.message_label.position.y + game.message_label.size.y, game.rally_button.position.y)
