extends "res://addons/gut/test.gd"

func after_each() -> void:
	get_tree().paused = false
	for index: int in range(3):
		await get_tree().process_frame

func _game() -> Node:
	var game: Node = load("res://game/scenes/main.tscn").instantiate()
	add_child_autofree(game)
	return game

func test_first_preparation_points_to_loot_and_later_preparation_to_building() -> void:
	var game: Node = _game()
	game.start_campaign()
	assert_eq(game.message_label.text, TranslationServer.translate("UI_FIRST_EXPEDITION_HINT"))
	assert_eq(game.state.gold, 20)
	assert_eq(game.state.balance.build_gold_cost, 25)
	game.state.gold = 45
	game._render_phase(game.state.Phase.PREPARATION)
	assert_eq(game.message_label.text, TranslationServer.translate("UI_MAP_BUILD_HELP"))

func test_health_bar_belongs_to_the_actual_health_stat_and_footer_has_safe_margin() -> void:
	var game: Node = _game()
	game.start_campaign()
	var owner: Label = game.hud_labels[2]
	assert_eq(game.health_bar.position.x, owner.position.x)
	assert_lte(game.health_bar.size.x, owner.size.x)
	var footer: Panel = game.screen.find_child("CostBackdrop", true, false)
	assert_lte(footer.position.y + footer.size.y, 708.0)
	game.enter_dungeon()
	owner = game.hud_labels[0]
	assert_eq(game.health_bar.position.x, owner.position.x)
	assert_lte(game.health_bar.size.x, owner.size.x)

func test_tower_comparison_explains_rate_damage_and_shortfall_without_spending() -> void:
	var game: Node = _game()
	game.start_campaign()
	game._open_tower_modal(0)
	var comparison: Label = game.modal.find_child("TowerComparison", true, false)
	assert_not_null(comparison)
	if comparison != null:
		assert_true(comparison.text.contains("8"))
		assert_true(comparison.text.contains("10"))
		assert_true(comparison.text.contains("1.1"))
		assert_true(comparison.text.contains("1.3"))
	var shortfall: Label = game.modal.find_child("TowerShortfall", true, false)
	assert_not_null(shortfall)
	if shortfall != null:
		assert_true(shortfall.text.contains("15"))
	game._close_modal()
	assert_eq(game.state.gold, 20)
	assert_eq(game.state.tower_levels[0], 1)

func test_success_summary_displays_real_castle_gold_and_buildings() -> void:
	var game: Node = _game()
	game.start_campaign()
	game.state.castle_hp = 73
	game.state.gold = 10
	game.state.tower_levels.assign([2, 2, 1, 1, 0, 0])
	game._render_phase(game.state.Phase.COMPLETE)
	var summary: Label = game.screen.find_child("RunSummary", true, false)
	assert_not_null(summary)
	if summary != null:
		assert_true(summary.text.contains("73"))
		assert_true(summary.text.contains("10"))
		assert_true(summary.text.contains("4 / 6"))
		var notices: Array[Node] = game.screen.find_children("*", "Label", true, false)
		var found_notice: bool = false
		for node: Node in notices:
			var notice: Label = node as Label
			if notice.text == TranslationServer.translate("UI_CAMPAIGN_REPLAY_NOTICE"):
				found_notice = true
				assert_gte(notice.position.y, summary.position.y + summary.size.y)
				assert_lte(notice.position.y + notice.size.y, 454.0)
		assert_true(found_notice, "The real run summary leaves room for the replay reset notice")
