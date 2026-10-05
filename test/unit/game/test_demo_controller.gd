extends "res://addons/gut/test.gd"

var original_auto_accept_quit: bool = true

func before_each() -> void:
	original_auto_accept_quit = get_tree().auto_accept_quit

func after_each() -> void:
	get_tree().paused = false
	for index: int in range(4):
		await get_tree().process_frame
	get_tree().auto_accept_quit = original_auto_accept_quit

func _create_demo() -> Node:
	var scene: PackedScene = load("res://game/scenes/main.tscn")
	var demo: Node = scene.instantiate()
	add_child_autofree(demo)
	return demo

func test_demo_scene_connects_chinese_menu_and_full_cycle() -> void:
	var demo: Node = _create_demo()
	await get_tree().process_frame
	assert_true(demo.has_method("start_campaign"), "The real demo controller exists")
	if not demo.has_method("start_campaign"):
		return
	var start_button: Button = demo.find_child("StartCampaign", true, false)
	assert_not_null(start_button)
	if start_button == null:
		return
	assert_eq(start_button.text, TranslationServer.translate("UI_START_CAMPAIGN"))
	start_button.pressed.emit()
	assert_eq(demo.state.phase, demo.state.Phase.PREPARATION)
	demo.enter_dungeon()
	assert_eq(demo.state.phase, demo.state.Phase.DUNGEON)
	demo.dungeon.exit_requested.emit()
	assert_eq(demo.state.phase, demo.state.Phase.DUNGEON)
	demo.dungeon.loot_collected.emit(25)
	demo.dungeon.goal_key_collected.emit()
	demo.dungeon.exit_requested.emit()
	assert_eq(demo.state.phase, demo.state.Phase.SETTLEMENT)
	assert_eq(demo.state.gold, 45)
	demo.begin_defense()
	assert_eq(demo.state.phase, demo.state.Phase.DEFENSE)
	assert_true(demo.fortress.running)
	demo.fortress.castle_damaged.emit(100)
	assert_eq(demo.state.phase, demo.state.Phase.FAILED)
	demo.retry_round()
	assert_eq(demo.state.phase, demo.state.Phase.PREPARATION)
	assert_eq(demo.state.gold, 20)
	assert_eq(demo.state.castle_hp, 100)

func test_sealed_box_confirmation_controls_world_processing() -> void:
	var demo: Node = _create_demo()
	await get_tree().process_frame
	if not demo.has_method("start_campaign"):
		assert_true(false, "The real demo controller exists")
		return
	demo.start_campaign()
	demo.enter_dungeon()
	demo.dungeon.sealed_chest_requested.emit()
	assert_true(demo.modal.visible)
	assert_eq(demo.dungeon.process_mode, Node.PROCESS_MODE_DISABLED)
	demo.accept_sealed_chest()
	assert_false(is_instance_valid(demo.modal) and demo.modal.visible)
	assert_true(demo.state.alarm)
	assert_eq(demo.state.bag_gold, 20)
	assert_eq(demo.dungeon.process_mode, Node.PROCESS_MODE_PAUSABLE)

func test_failure_dialogs_omit_retry_explanations_and_keep_retry_working() -> void:
	var demo: Node = _create_demo()
	await get_tree().process_frame
	for reason: String in ["player_defeated", "castle_destroyed", "expedition_abandoned"]:
		demo.start_campaign()
		demo.enter_dungeon()
		demo.state.fail(reason)
		var messages: Array[String] = []
		for node: Node in demo.screen.find_children("*", "Label", true, false):
			var label: Label = node as Label
			if label.is_visible_in_tree() and not label.text.is_empty():
				messages.append(label.text)
		assert_eq(messages.size(), 2, "Failure dialogs contain only the title and failure reason: " + reason)
		assert_has(messages, TranslationServer.translate("UI_FAILURE_TITLE"))
		assert_has(messages, TranslationServer.translate("UI_FAILURE_" + reason.to_upper()))
		var retry_button: Button = null
		var menu_button: Button = null
		for node: Node in demo.screen.find_children("*", "Button", true, false):
			var button: Button = node as Button
			if button.text == TranslationServer.translate("UI_RETRY_ROUND"):
				retry_button = button
			elif button.text == TranslationServer.translate("UI_MAIN_MENU"):
				menu_button = button
		assert_not_null(retry_button, "Retry remains available without explanatory copy")
		assert_not_null(menu_button, "The main menu action remains available")
		if retry_button == null:
			continue
		retry_button.pressed.emit()
		assert_eq(demo.state.phase, demo.state.Phase.PREPARATION)
		assert_eq(demo.state.gold, 20)
		assert_eq(demo.state.castle_hp, 100)

func test_campaign_completion_keeps_its_replay_notice() -> void:
	var demo: Node = _create_demo()
	await get_tree().process_frame
	demo.start_campaign()
	for round_number: int in range(3):
		demo.enter_dungeon()
		demo.dungeon.goal_key_collected.emit()
		demo.dungeon.exit_requested.emit()
		demo.begin_defense()
		demo.fortress.wave_completed.emit()
	assert_eq(demo.state.phase, demo.state.Phase.COMPLETE)
	var found_notice: bool = false
	for node: Node in demo.screen.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label.is_visible_in_tree() and label.text == TranslationServer.translate("UI_CAMPAIGN_REPLAY_NOTICE"):
			found_notice = true
	assert_true(found_notice, "Removing failure copy preserves the separate campaign completion message")

func test_controls_return_to_pause_and_menu_changes_model_phase() -> void:
	var demo: Node = _create_demo()
	await get_tree().process_frame
	demo.start_campaign()
	demo.enter_dungeon()
	demo._open_pause()
	assert_true(get_tree().paused)
	demo._open_controls()
	assert_true(get_tree().paused)
	demo._close_modal()
	assert_true(get_tree().paused)
	assert_eq(demo.modal_kind, "pause")
	demo._show_main_menu()
	assert_false(get_tree().paused)
	assert_eq(demo.state.phase, demo.state.Phase.TITLE)

func test_controller_handles_window_close_and_restores_global_quit_policy_on_removal() -> void:
	get_tree().auto_accept_quit = true
	var demo: Node = _create_demo()
	assert_false(get_tree().auto_accept_quit, "Window close must use the controller's orderly audio shutdown")
	remove_child(demo)
	assert_true(get_tree().auto_accept_quit, "Removing the scene restores the surrounding application's quit policy")

func test_controller_preserves_an_existing_manual_window_close_policy() -> void:
	get_tree().auto_accept_quit = false
	var demo: Node = _create_demo()
	assert_false(get_tree().auto_accept_quit)
	remove_child(demo)
	assert_false(get_tree().auto_accept_quit)
