extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://game/scenes/main.tscn")

var game: Node
var capture_dir: String = ""
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
	call_deferred("_run")


func _run() -> void:
	if capture_dir.is_empty():
		push_error("Provide --capture-dir for visual regression artifacts.")
		quit(2)
		return
	_check(DirAccess.make_dir_recursive_absolute(capture_dir) == OK, "Capture directory is writable")
	game = MAIN_SCENE.instantiate()
	root.add_child(game)
	current_scene = game
	await _capture("menu")
	game.start_campaign()
	await _capture("preparation")
	game._open_tower_modal(0)
	await _capture("tower_shortfall")
	game._close_modal()
	game.enter_dungeon()
	for level: int in range(3):
		game.state.round_index = level + 1
		game.dungeon.reset_run(level)
		game._render_phase(game.state.Phase.DUNGEON)
		await _capture("dungeon_" + str(level + 1))
	game.dungeon.player.position = game.dungeon.ordinary_chest_position
	await create_timer(0.12).timeout
	_check(game.message_label.text == TranslationServer.translate("UI_INTERACT_CHEST"), "Nearby chest receives the real contextual prompt")
	await _capture("chest_prompt")
	game._open_pause()
	game._open_controls()
	await _capture("pause_controls")
	game._show_main_menu()
	game.start_campaign()
	game.state.castle_hp = 73
	game.state.gold = 10
	game.state.tower_levels.assign([2, 2, 1, 1, 0, 0])
	game.fortress.prepare(game.state.tower_levels)
	game.state.phase = game.state.Phase.COMPLETE
	game._render_phase(game.state.Phase.COMPLETE)
	await _capture("complete")
	var result: Dictionary = {"checks": checks, "failures": failures, "window_size": [root.size.x, root.size.y], "validation": "rendered UI, nearby prompt, screenshot resolution; scripted phase setup"}
	var file: FileAccess = FileAccess.open(capture_dir.path_join("visual-result.json"), FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify(result, "\t"))
	print("POLISH_VISUAL_RESULT=" + JSON.stringify(result))
	quit(0 if failures == 0 else 1)


func _capture(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var viewport: Rect2 = root.get_visible_rect()
	for node: Node in game.screen.find_children("*", "Control", true, false):
		var control: Control = node as Control
		if not control.is_visible_in_tree() or (not control is Label and not control is Button):
			continue
		var bounds: Rect2 = control.get_global_rect()
		_check(viewport.grow(1).encloses(bounds), "Visible control fits viewport: " + label + "/" + str(control.name))
		if control is Label:
			var text_label: Label = control as Label
			_check(not text_label.text.begins_with("UI_"), "Label has translated text: " + str(control.name))
	var screenshot: Image = root.get_texture().get_image()
	_check(screenshot.get_size() == root.size, "Screenshot matches requested window resolution")
	_check(screenshot.save_png(capture_dir.path_join(label + ".png")) == OK, "Screenshot saved: " + label)


func _check(passed: bool, description: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error(description)
