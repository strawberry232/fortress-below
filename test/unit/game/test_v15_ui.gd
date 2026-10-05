extends "res://addons/gut/test.gd"

func after_each() -> void:
	get_tree().paused = false
	for index: int in range(4):
		await get_tree().process_frame

func _game() -> Node:
	var game: Node = load("res://game/scenes/main.tscn").instantiate()
	add_child_autofree(game)
	return game

func _text(codepoints: Array[int]) -> String:
	var result: String = ""
	for codepoint: int in codepoints:
		result += String.chr(codepoint)
	return result

func _compact(value: String) -> String:
	return value.replace("\n", "").replace(" ", "").replace(String.chr(0xB7), "")

func _assert_no_redundant_copy(parent: Node) -> void:
	var retired: Array[String] = [
		_text([0x4E09, 0x8F6E, 0x53CC, 0x8DEF, 0x4E0D, 0x53D8, 0x5EFA, 0x8BBE, 0x8DE8, 0x8F6E, 0x4FDD, 0x7559]),
		_text([0x516D, 0x5904, 0x5854, 0x4F4D, 0x53EF, 0x5EFA, 0x8BBE]),
		_text([0x5E26, 0x8D22, 0x5B9D, 0x5F52, 0x6765]),
		_text([0x4E09, 0x5C42, 0x5730, 0x7262, 0x516D, 0x5904, 0x5854, 0x4F4D, 0x591A, 0x79CD, 0x602A, 0x7269]),
		_text([0x4E09, 0x8F6E, 0x8DEF, 0x7EBF, 0x4E0D, 0x53D8])
	]
	for label: Label in parent.find_children("*", "Label", true, false):
		for fragment: String in retired:
			assert_false(_compact(label.text).contains(fragment), "Redundant promotional or inheritance copy is absent")

func _find_button(parent: Node, key: String) -> Button:
	for button: Button in parent.find_children("*", "Button", true, false):
		if button.text == TranslationServer.translate(key):
			return button
	return null

func test_title_and_pause_show_actions_without_marketing_copy() -> void:
	var game: Node = _game()
	_assert_no_redundant_copy(game.screen)
	assert_not_null(_find_button(game.screen, "UI_START_CAMPAIGN"))
	assert_null(game.find_child("StartDemo", true, false))
	assert_not_null(_find_button(game.screen, "UI_CONTROLS"))
	assert_not_null(_find_button(game.screen, "UI_QUIT"))
	game.start_campaign()
	game._open_pause()
	_assert_no_redundant_copy(game.modal)
	assert_not_null(_find_button(game.modal, "UI_RESUME"))
	assert_not_null(_find_button(game.modal, "UI_CONTROLS"))
	assert_not_null(_find_button(game.modal, "UI_MAIN_MENU"))

func test_preparation_and_settlement_have_one_actionable_map_hint() -> void:
	var game: Node = _game()
	game.start_campaign()
	for phase: int in [game.state.Phase.PREPARATION, game.state.Phase.SETTLEMENT]:
		game.state.phase = phase
		game._render_phase(phase)
		await get_tree().process_frame
		_assert_no_redundant_copy(game.screen)
		var hint_key: String = "UI_FIRST_EXPEDITION_HINT" if phase == game.state.Phase.PREPARATION else "UI_MAP_BUILD_HELP"
		assert_eq(game.message_label.text, TranslationServer.translate(hint_key))
		var count: int = 0
		for label: Label in game.screen.find_children("*", "Label", true, false):
			if label.text == TranslationServer.translate(hint_key):
				count += 1
		assert_eq(count, 1, "The construction cue is shown once")
		assert_null(game.screen.find_child("TowerSummary", true, false))
		assert_null(game.screen.find_child("TowerAction0", true, false))
		var repair: Button = _find_button(game.screen, "UI_REPAIR_CASTLE")
		var action: Button = _find_button(game.screen, "UI_ENTER_DUNGEON" if phase == game.state.Phase.PREPARATION else "UI_START_DEFENSE")
		assert_not_null(repair)
		assert_not_null(action)
		if repair != null and action != null:
			assert_gte(repair.position.y, game.message_label.position.y + game.message_label.size.y)
			assert_gte(action.position.y, repair.position.y + repair.size.y)
			assert_lte(action.position.y + action.size.y, 720.0)
			for button: Button in [repair, action]:
				assert_gte(button.get_theme_font_size("font_size"), 24)
				assert_lte(button.get_minimum_size().x, button.size.x, "Localized action fits the compact sidebar")
				assert_lte(button.get_minimum_size().y, button.size.y, "Action does not overlap prices or borders")
		assert_eq(game.message_label.get_theme_font_size("font_size"), 24)
		assert_eq(game.message_label.get_line_count(), 2)
		assert_lte(game.message_label.get_minimum_size().y, game.message_label.size.y)
		var cost: Panel = game.screen.find_child("CostBackdrop", true, false)
		assert_not_null(cost)
		var cost_visible: bool = false
		for label: Label in game.screen.find_children("*", "Label", true, false):
			if label.text.contains(TranslationServer.translate("UI_BUILD_COST")) and label.text.contains(TranslationServer.translate("UI_UPGRADE_COST")):
				cost_visible = true
		assert_true(cost_visible, "Construction and upgrade prices remain visible")

func test_controls_keep_inputs_and_cooldown_without_inheritance_reminder() -> void:
	var game: Node = _game()
	game.start_campaign()
	game._open_pause()
	game._open_controls()
	await get_tree().process_frame
	_assert_no_redundant_copy(game.modal)
	var input_text: String = ""
	for label: Label in game.modal.find_children("*", "Label", true, false):
		input_text += label.text
		assert_gte(label.get_theme_font_size("font_size"), 24)
		assert_lte(label.get_minimum_size().y, label.size.y)
	assert_true(input_text.contains("WASD"))
	assert_true(input_text.contains("J"))
	assert_true(input_text.contains("K"))
	assert_true(input_text.contains("E"))
	assert_true(input_text.contains("4"))
	assert_true(input_text.contains("12"))
	assert_not_null(_find_button(game.modal, "UI_BACK"))
	game._close_modal()
	assert_eq(game.modal_kind, "pause")
	assert_true(get_tree().paused)

func test_map_popup_remains_available_and_cancel_does_not_spend() -> void:
	var game: Node = _game()
	game.start_campaign()
	var original_gold: int = game.state.gold
	assert_true(game.fortress._select_tower_at(game.fortress.tower_points[5]))
	assert_eq(game.modal_kind, "tower")
	var confirm: Button = game.modal.find_child("TowerConfirm", true, false)
	var cancel: Button = game.modal.find_child("TowerCancel", true, false)
	assert_not_null(confirm)
	assert_not_null(cancel)
	if confirm != null and cancel != null:
		assert_eq(confirm.text, TranslationServer.translate("UI_BUILD_TOWER"))
		assert_true(confirm.disabled, "An unaffordable tower cannot be built")
		cancel.pressed.emit()
	assert_eq(game.state.gold, original_gold)
	assert_eq(game.state.tower_levels[5], 0)
	assert_eq(game.modal_kind, "")
