extends "res://addons/gut/test.gd"


func after_each() -> void:
	get_tree().paused = false
	for index: int in range(4):
		await get_tree().process_frame


func _game() -> Node:
	var scene: PackedScene = load("res://game/scenes/main.tscn")
	var game: Node = scene.instantiate()
	add_child_autofree(game)
	return game


func test_menu_primary_campaign_button_begins_three_rounds() -> void:
	var game: Node = _game()
	await get_tree().process_frame
	var campaign: Button = game.find_child("StartCampaign", true, false)
	assert_not_null(campaign, "The primary menu starts the user's chosen continuous adventure")
	if campaign == null:
		return
	campaign.pressed.emit()
	assert_eq(game.state.balance.round_limit, 3)
	assert_eq(game.state.round_index, 1)
	assert_eq(game.state.phase, game.state.Phase.PREPARATION)
	assert_eq(game.fortress.round_index, 1)


func test_round_header_and_level_follow_preserved_campaign_progress() -> void:
	var game: Node = _game()
	await get_tree().process_frame
	game.state.start_campaign()
	assert_true(game.state.begin_dungeon())
	assert_true(game.state.take_goal_key())
	assert_true(game.state.settle_loot())
	assert_true(game.state.start_defense())
	assert_true(game.state.finish_defense())
	assert_true(game.hud_labels[3].text.contains("2 / 3"), "The header must show the actual second round")
	assert_eq(game.fortress.round_index, 2)
	game.enter_dungeon()
	assert_eq(game.dungeon.get_level_info()["index"], 1)
	assert_eq(game.state.round_index, 2)


func test_sound_toggle_mutes_music_and_effects_and_survives_pause_menu() -> void:
	var game: Node = _game()
	await get_tree().process_frame
	var toggle: Button = game.find_child("SoundToggle", true, false)
	assert_not_null(toggle, "The game offers an accessible music and sound control")
	if toggle == null:
		return
	assert_false(game.audio.get_muted())
	toggle.pressed.emit()
	assert_true(game.audio.get_muted())
	game.start_campaign()
	game.enter_dungeon()
	game._open_pause()
	game._open_controls()
	game._close_modal()
	assert_true(get_tree().paused)
	assert_true(game.audio.get_muted())
	game._close_modal()
	assert_false(get_tree().paused)


func test_ui_adopts_the_supplied_medieval_atlas_and_icons() -> void:
	var game: Node = _game()
	await get_tree().process_frame
	var style: StyleBox = game.game_theme.get_stylebox("normal", "Button")
	assert_true(style is StyleBoxTexture)
	if not style is StyleBoxTexture:
		return
	var texture: Texture2D = style.texture
	assert_eq(texture.resource_path, "res://game/assets/tiny_swords_ui/button.png", "Tiny Swords provides the actual button texture")
	if texture is AtlasTexture:
		assert_eq(texture.atlas.resource_path, "res://game/assets/medieval_ui/sheet.png")
	var icons: Array[Node] = game.find_children("HudIcon*", "TextureRect", true, false)
	game.start_campaign()
	icons = game.find_children("HudIcon*", "TextureRect", true, false)
	assert_gte(icons.size(), 4, "Resource labels have clear supplied icons")


func test_construction_updates_six_slots_and_preserves_current_round_preview() -> void:
	var game: Node = _game()
	await get_tree().process_frame
	game.start_campaign()
	game.state.gold = 100
	game._tower_action(0)
	assert_eq(game.state.tower_levels, [2, 0, 0, 0, 0, 0])
	assert_eq(game.state.gold, 65)
	game._tower_action(5)
	assert_eq(game.state.tower_levels, [2, 0, 0, 0, 0, 1])
	assert_eq(game.state.gold, 40)
	assert_eq(game.fortress.round_index, 1)
	assert_eq(game.fortress.tower_levels, game.state.tower_levels)
	assert_null(game.fortress.find_child("Worker", true, false))
