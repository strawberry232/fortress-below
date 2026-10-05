extends SceneTree

const ControllerScript = preload("res://game/scripts/ui/demo_controller.gd")
const MAIN_SCENE: PackedScene = preload("res://game/scenes/main.tscn")

var game: ControllerScript
var exit_path: String = "button"
var checks: int = 0
var failures: int = 0
var result_written: bool = false

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--exit-path="):
			exit_path = argument.trim_prefix("--exit-path=")
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	game = MAIN_SCENE.instantiate() as ControllerScript
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame
	_check(not auto_accept_quit, "The real scene owns window close cleanup")
	_check(game.audio.get("music_player").playing, "A real WAV music playback is active before exit")
	_check(game.audio.play_event("sword"), "A real effect is active before exit")
	if exit_path == "window":
		_click_button("UI_START")
		await process_frame
		_click_button("UI_PAUSE")
		await process_frame
		_check(paused and game.modal_kind == "pause", "The actual pause button freezes the scene before WM_CLOSE")
		print("EXIT_WINDOW_READY " + JSON.stringify({"pid": OS.get_process_id()}))
	elif exit_path == "button":
		_click_button("UI_QUIT")
	else:
		_check(false, "Unknown exit path")
		quit(1)
		return
	var limit: int = Time.get_ticks_msec() + 10000
	while not game.get("_quitting") and Time.get_ticks_msec() < limit:
		await process_frame
	if not game.get("_quitting"):
		_check(false, "The requested real exit did not start")
		quit(1)
		return
	_check(not paused, "Orderly exit unpauses the tree")
	_check(not game.fortress.running, "No wave remains active during exit")
	_check(game.fortress.process_mode == Node.PROCESS_MODE_DISABLED and game.dungeon.process_mode == Node.PROCESS_MODE_DISABLED, "Both gameplay worlds are frozen before exit")
	_check(game.interface.process_mode == Node.PROCESS_MODE_DISABLED, "Further GUI actions are disabled during exit")
	_check(not game.audio.get("music_player").playing and game.audio.get("music_player").stream == null, "The looping player is stopped and detached before engine shutdown")
	_check(game.audio.get("current_track") == "", "The audio phase marker is cleared")
	for value: Variant in game.audio.get("voices"):
		var voice: AudioStreamPlayer = value
		_check(not voice.playing and voice.stream == null, "Every real effect player is stopped and detached")
	game.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check(game.get("_quitting"), "A duplicate close request shares the in-progress exit")
	result_written = true
	print("EXIT_CLEANUP_RESULT " + JSON.stringify({"path": exit_path, "checks": checks, "failures": failures}))

func _click_button(key: String) -> void:
	var button: Button = _find_button(game.screen, TranslationServer.translate(key))
	if not _check(button != null and not button.disabled, "The actual requested button exists: " + key):
		return
	var pressed: Array[bool] = [false]
	button.pressed.connect(func() -> void: pressed[0] = true, CONNECT_ONE_SHOT)
	var center: Vector2 = button.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	root.push_input(motion, true)
	for down: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = center
		event.global_position = center
		event.pressed = down
		root.push_input(event, true)
	_check(pressed[0], "A real pointer click emitted the requested button signal")

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_button(child, text)
		if found != null:
			return found
	return null

func _check(condition: bool, description: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
	return condition
