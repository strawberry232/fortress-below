extends SceneTree

const ControllerScript = preload("res://game/scripts/ui/demo_controller.gd")
const MAIN_SCENE: PackedScene = preload("res://game/scenes/main.tscn")
const WaveLedger = preload("res://game/scripts/defense/wave_ledger.gd")
const MonsterCatalog = preload("res://game/data/monsters/monster_catalog.gd")

var game: ControllerScript
var capture_dir: String = ""
var checks: Array[Dictionary] = []
var failures: int = 0
var fragment_births: Dictionary = {}
var observed_alarm_enemy: bool = false
var observed_safe_alarm_enemy: bool = false
var ui_only: bool = false
var start_ticks: int = 0


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
		elif argument == "--ui-only":
			ui_only = true
	start_ticks = Time.get_ticks_msec()
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 4.0
	game = MAIN_SCENE.instantiate() as ControllerScript
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame
	_check(game.state.phase == game.state.Phase.TITLE, "Main scene opens the title menu")
	_check(TranslationServer.get_locale() == "zh_CN", "Chinese is the default player locale")
	await _capture("menu")
	await _click_button("UI_CONTROLS")
	_check(game.modal_kind == "controls" and paused, "The real controls button opens the paused Chinese help modal")
	await _capture("controls")
	await _click_button("UI_BACK")
	_check(game.modal == null and not paused, "The real back button closes help and resumes the title menu")
	await _click_button("UI_START_CAMPAIGN", "StartCampaign")
	if not _check(game.state.phase == game.state.Phase.PREPARATION, "The real StartCampaign button begins preparation"):
		_finish()
		return
	_check_checkpoint("New run")
	await _capture("preparation")
	await _click_button("UI_ENTER_DUNGEON")
	if not _check(game.state.phase == game.state.Phase.DUNGEON, "The preparation button enters the real dungeon"):
		_finish()
		return
	await _capture("dungeon")
	await _click_button("UI_PAUSE")
	_check(game.modal_kind == "pause" and paused, "The actual pause button suspends dungeon play")
	await _click_button("UI_CONTROLS")
	await _capture("pause_controls")
	await _click_button("UI_BACK")
	_check(game.modal_kind == "pause" and paused, "Back from pause controls preserves the pause menu and paused simulation")
	await _click_button("UI_RESUME")
	_check(game.modal == null and not paused, "Resume from the returned pause menu restarts dungeon play")
	if ui_only:
		_finish()
		return
	await _interact_at(game.dungeon.STAIRS_POSITION)
	_check(game.state.phase == game.state.Phase.DUNGEON, "Stairs cannot settle loot before the target key")
	await _interact_at(game.dungeon.ORDINARY_CHEST_POSITION)
	_check(game.state.bag_gold == 25 and game.state.gold == 20, "The ordinary chest adds 25 bag gold without bank settlement")
	await _interact_at(game.dungeon.ORDINARY_CHEST_POSITION)
	_check(game.state.bag_gold == 25 and not game.state.alarm, "Repeated ordinary chest interaction does not duplicate gold or trigger alarm")
	await _interact_at(game.dungeon.SEALED_CHEST_POSITION)
	if not _check(game.modal_kind == "sealed", "E at the sealed chest opens the real confirmation modal"):
		_finish()
		return
	var paused_clock: float = game.dungeon.get("_clock")
	await create_timer(0.3).timeout
	_check(is_equal_approx(paused_clock, game.dungeon.get("_clock")), "Reading the sealed modal suspends dungeon simulation")
	await _capture("sealed")
	_check_seal_description()
	await _click_button("UI_SEALED_ACCEPT")
	_check(game.modal == null and game.state.bag_gold == 45 and game.state.alarm, "The real accept button awards 20 extra gold and activates alarm")
	await _capture("dungeon_alarm")
	await _interact_at(game.dungeon.SEALED_CHEST_POSITION)
	_check(game.state.bag_gold == 45 and game.modal == null, "The accepted sealed chest cannot award twice")
	_observe_slime_children()
	var enemies: Array = game.dungeon.get("_enemies").duplicate()
	_check(enemies.size() == 3, "The dungeon starts with three actual source-pack guardians")
	for value: Variant in enemies:
		if not is_instance_valid(value):
			continue
		var enemy: CharacterBody2D = value as CharacterBody2D
		if not await _defeat_with_sword(enemy):
			_finish()
			return
	if not await _clear_slime_fragments():
		_finish()
		return
	_check(game.dungeon.get("_middle_guardians") == 0, "Sword defeats open the middle room gate")
	_check(game.dungeon.get("_reward_guard_defeated"), "The reward guardian died through actual combat")
	await _interact_at(game.dungeon.KEY_POSITION)
	_check(game.state.has_goal_key, "E collects the target key after the guard is defeated")
	await _interact_at(game.dungeon.STAIRS_POSITION)
	if not _check(game.state.phase == game.state.Phase.SETTLEMENT, "E at the stairs transitions to settlement"):
		_finish()
		return
	_check(game.state.gold == 65 and game.state.bag_gold == 0, "Settlement deposits initial 20 plus ordinary 25 plus sealed 20 exactly once")
	await _click_button("UI_BUILD_TOWER")
	_check(game.state.tower_levels == [1, 1, 0, 0, 0, 0], "The actual construction button builds the second of six tower slots")
	_check(game.state.gold == 40, "Construction spends exactly 25 gold with no wood resource")
	await _click_button("UI_START_DEFENSE")
	if not _check(game.state.phase == game.state.Phase.DEFENSE, "The actual defense button begins the alarm wave"):
		_finish()
		return
	_check(game.fortress.remaining_enemies() == 7, "The alarm adds exactly one armored skeleton to six original Orcs")
	var first_arrow_deadline: int = Time.get_ticks_msec() + 10000
	while game.fortress.arrows.is_empty() and game.state.phase == game.state.Phase.DEFENSE and Time.get_ticks_msec() < first_arrow_deadline:
		await process_frame
	await _capture("defense")
	await _click_button("UI_RALLY")
	_check(game.fortress.ledger.rally_used, "The real rally button activates its once-per-wave ability")
	var defense_deadline: int = Time.get_ticks_msec() + 60000
	while game.state.phase == game.state.Phase.DEFENSE and Time.get_ticks_msec() < defense_deadline:
		for enemy_id: int in game.fortress.enemies:
			if enemy_id == 7 and game.fortress.enemies[enemy_id]["kind"] == WaveLedger.alarm_enemy_kind(1):
				observed_alarm_enemy = true
		await process_frame
	_check(observed_alarm_enemy, "The promised single armored skeleton actually spawns as the seventh enemy")
	_check(game.fortress.next_id == 8, "Exactly seven enemies were spawned")
	if not _check(game.state.phase == game.state.Phase.PREPARATION and game.state.completed_rounds == 1, "Actual projectiles finish the first campaign wave and advance to round two"):
		_finish()
		return
	_check(game.state.castle_hp > 0 and game.fortress.enemies.is_empty(), "Completion keeps the castle alive and clears actual enemies")
	await _capture("complete")
	await _restart_campaign()
	_check_checkpoint("Replay")
	await _click_button("UI_ENTER_DUNGEON")
	await _interact_at(game.dungeon.ORDINARY_CHEST_POSITION)
	await _interact_at(game.dungeon.SEALED_CHEST_POSITION)
	await _click_button("UI_SEALED_DECLINE")
	_check(not game.state.alarm and game.state.bag_gold == 25, "Declining the real sealed modal leaves ordinary loot and no alarm")
	await _interact_at(game.dungeon.SEALED_CHEST_POSITION)
	await _click_button("UI_SEALED_ACCEPT")
	var failure_enemy: CharacterBody2D = game.dungeon.get("_enemies")[0]
	game.dungeon.player.position = failure_enemy.position - Vector2(48.0, 0.0)
	var failure_deadline: int = Time.get_ticks_msec() + 12000
	while game.state.phase == game.state.Phase.DUNGEON and Time.get_ticks_msec() < failure_deadline:
		await process_frame
	_check(game.state.phase == game.state.Phase.FAILED and game.state.failure_reason == "player_defeated", "Real source-pack monster attacks produce the dungeon failure screen")
	await _capture("failed")
	await _click_button("UI_RETRY_ROUND")
	_check(game.state.phase == game.state.Phase.PREPARATION, "The real free-retry button restores preparation")
	_check_checkpoint("Free retry")
	_check(game.state.bag_gold == 0 and not game.state.alarm and not game.state.has_goal_key, "Retry clears failed expedition loot, key, and alarm")
	await _capture("retry")
	await _click_button("UI_ENTER_DUNGEON")
	await _interact_at(game.dungeon.ORDINARY_CHEST_POSITION)
	await _click_button("UI_ABANDON")
	_check(game.state.phase == game.state.Phase.FAILED and game.state.failure_reason == "expedition_abandoned", "The real abandon button fails the expedition")
	await _click_button("UI_RETRY_ROUND")
	_check_checkpoint("Retry after abandon")
	_check(game.state.bag_gold == 0 and not game.state.alarm, "Retry after abandon discards loot and cannot duplicate the checkpoint gold")
	if not await _run_safe_route():
		_finish()
		return
	if not await _run_castle_failure_route():
		_finish()
		return
	_finish()


func _run_castle_failure_route() -> bool:
	await _restart_campaign()
	_check_checkpoint("Replay before castle-failure route")
	await _click_button("UI_ENTER_DUNGEON")
	await _interact_at(game.dungeon.ORDINARY_CHEST_POSITION)
	await _interact_at(game.dungeon.SEALED_CHEST_POSITION)
	await _click_button("UI_SEALED_ACCEPT")
	_observe_slime_children()
	var enemies: Array = game.dungeon.get("_enemies").duplicate()
	for value: Variant in enemies:
		if not is_instance_valid(value):
			continue
		if not await _defeat_with_sword(value as CharacterBody2D):
			return false
	if not await _clear_slime_fragments():
		return false
	await _interact_at(game.dungeon.KEY_POSITION)
	await _interact_at(game.dungeon.STAIRS_POSITION)
	_check(game.state.gold == 65 and game.state.tower_levels == [1, 0, 0, 0, 0, 0] and game.state.alarm, "The real no-build risk route returns 65 gold and deliberately keeps one tower")
	await _click_button("UI_START_DEFENSE")
	await _capture("defense_no_build")
	var deadline: int = Time.get_ticks_msec() + 60000
	while game.state.phase == game.state.Phase.DEFENSE and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _check(game.state.phase == game.state.Phase.FAILED and game.state.failure_reason == "castle_destroyed" and game.state.castle_hp == 0, "Actual enemy attacks destroy the undefended alarm castle without emitted test damage"):
		return false
	_check(not game.fortress.ledger.rally_used, "The no-build failure route deliberately leaves Rally unused")
	await _capture("castle_failed")
	await _click_button("UI_RETRY_ROUND")
	_check_checkpoint("Free retry after actual castle destruction")
	_check(game.state.phase == game.state.Phase.PREPARATION and not game.state.alarm and game.state.bag_gold == 0, "Castle-failure retry clears risk, restored income, and failed-wave state")
	await _capture("retry_castle")
	return true


func _run_safe_route() -> bool:
	await _click_button("UI_ENTER_DUNGEON")
	await _interact_at(game.dungeon.ORDINARY_CHEST_POSITION)
	_check(game.state.bag_gold == 25 and not game.state.alarm, "The safe route collects ordinary gold and leaves the seal untouched")
	_observe_slime_children()
	var enemies: Array = game.dungeon.get("_enemies").duplicate()
	for value: Variant in enemies:
		if not is_instance_valid(value):
			continue
		if not await _defeat_with_sword(value as CharacterBody2D):
			return false
	if not await _clear_slime_fragments():
		return false
	await _interact_at(game.dungeon.KEY_POSITION)
	await _interact_at(game.dungeon.STAIRS_POSITION)
	if not _check(game.state.phase == game.state.Phase.SETTLEMENT and game.state.gold == 45, "Actual safe-route combat and stairs settle 20 plus 25 gold"):
		return false
	await _click_button("UI_BUILD_TOWER")
	_check(game.state.tower_levels == [1, 1, 0, 0, 0, 0] and game.state.gold == 20, "Ordinary loot alone funds the second tower using only gold without opening the seal")
	await _click_button("UI_START_DEFENSE")
	_check(game.fortress.remaining_enemies() == 6 and not game.state.alarm, "The real safe wave starts with six enemies and no alarm")
	var first_arrow_deadline: int = Time.get_ticks_msec() + 10000
	while game.fortress.arrows.is_empty() and game.state.phase == game.state.Phase.DEFENSE and Time.get_ticks_msec() < first_arrow_deadline:
		await process_frame
	await _capture("defense_safe")
	await _click_button("UI_RALLY")
	var deadline: int = Time.get_ticks_msec() + 60000
	while game.state.phase == game.state.Phase.DEFENSE and Time.get_ticks_msec() < deadline:
		for enemy_id: int in game.fortress.enemies:
			if game.fortress.enemies[enemy_id]["kind"] != "orc":
				observed_safe_alarm_enemy = true
		await process_frame
	_check(not observed_safe_alarm_enemy and game.fortress.next_id == 7, "The unopened-seal route actually spawns six original Orcs and no seal reinforcement")
	if not _check(game.state.phase == game.state.Phase.PREPARATION and game.state.completed_rounds == 1 and game.state.castle_hp > 0, "Actual tower projectiles complete the unopened-seal route"):
		return false
	await _capture("complete_safe")
	return true

func _restart_campaign() -> void:
	if game.state.phase == game.state.Phase.COMPLETE:
		await _click_button("UI_REPLAY")
	else:
		game._open_pause()
		await _click_button("UI_MAIN_MENU")
		await _click_button("UI_START_CAMPAIGN", "StartCampaign")


func _observe_slime_children() -> void:
	fragment_births.clear()
	game.dungeon._content.child_entered_tree.connect(_on_new_dungeon_child)

func _on_new_dungeon_child(node: Node) -> void:
	if node is CharacterBody2D and "slime_generation" in node and node.slime_generation == 1:
		fragment_births[node.get_instance_id()] = true
		node.ready.connect(_record_fragment_ready.bind(node), CONNECT_ONE_SHOT)

func _record_fragment_ready(child: CharacterBody2D) -> void:
	_check(child._sprite.scale == Vector2(2, 2) and child.health.maximum == 14, "A real spawned slime child has its smaller original sprite and independent health")

func _clear_slime_fragments() -> bool:
	await physics_frame
	await physics_frame
	if not _check(fragment_births.size() == 2, "The adult slime actually spawned exactly two nonrecursive children during real sword combat"):
		return false
	var fragments: Array[CharacterBody2D] = []
	for value: Variant in game.dungeon.get("_enemies"):
		if is_instance_valid(value) and value.monster_kind == "slime" and value.slime_generation == 1 and value.health.is_alive():
			fragments.append(value)
	if not fragments.is_empty():
		await _capture("slime_children_round_%d" % game.state.round_index)
	for fragment: CharacterBody2D in fragments:
		if is_instance_valid(fragment) and fragment.health.is_alive():
			if not await _defeat_with_sword(fragment):
				return false
	return true

func _defeat_with_sword(enemy: CharacterBody2D) -> bool:
	if not is_instance_valid(enemy):
		return _check(false, "A required source-pack guardian was unexpectedly missing")
	var initial: int = enemy.health.current
	for attempt: int in range(7):
		if not is_instance_valid(enemy) or not enemy.health.is_alive():
			break
		var position: Vector2 = enemy.position - Vector2(92, 0)
		var safest: float = -1.0
		for side: float in [1.0, -1.0]:
			var candidate: Vector2 = enemy.position + Vector2(side * 92, 0)
			if not game.dungeon.is_walkable(candidate + Vector2(0, -26)):
				continue
			var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(game.dungeon.to_global(candidate) + Vector2(0, -12), enemy.global_position + Vector2(0, -12), 1)
			if not game.dungeon.get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
				continue
			var nearest: float = 10000
			for value: Variant in game.dungeon.get("_enemies"):
				if not is_instance_valid(value):
					continue
				var other: CharacterBody2D = value as CharacterBody2D
				if other != enemy and other.health.is_alive():
					nearest = minf(nearest, candidate.distance_to(other.position))
			if nearest > safest:
				safest = nearest
				position = candidate
		var offset: Vector2 = position - enemy.position
		game.dungeon.player.position = position
		if game.dungeon.player.get("_hurt_left") > 0.0:
			await _wait_seconds(0.45)
		await _tap_action("fb_move_right" if offset.x < 0 else "fb_move_left")
		if not is_instance_valid(enemy) or not enemy.health.is_alive():
			break
		game.dungeon.player.position = enemy.position + offset
		await _tap_action("fb_sword")
		await _wait_seconds(0.72)
		if game.state.phase != game.state.Phase.DUNGEON:
			break
	return _check(not is_instance_valid(enemy) or not enemy.health.is_alive(), "Real sword actions defeat a source-pack guardian with initial HP " + str(initial))


func _interact_at(location: Vector2) -> void:
	game.dungeon.player.position = location
	game.dungeon.player.velocity = Vector2.ZERO
	await _tap_action("fb_interact")


func _tap_action(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	Input.action_release(action)
	await physics_frame
	await physics_frame


func _click_button(key: String, expected_name: String = "") -> void:
	if key in ["UI_BUILD_TOWER", "UI_UPGRADE_TOWER"]:
		var slot: int = -1
		if expected_name.begins_with("TowerAction"):
			slot = expected_name.trim_prefix("TowerAction").to_int()
		else:
			for index: int in range(game.state.tower_levels.size()):
				if game.state.tower_levels[index] == (0 if key == "UI_BUILD_TOWER" else 1):
					slot = index
					break
		if slot >= 0:
			var site: Vector2 = game.fortress.to_global(game.fortress.tower_points[slot] - Vector2(0, 10))
			for down: bool in [true, false]:
				var click: InputEventMouseButton = InputEventMouseButton.new()
				click.position = site
				click.global_position = site
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = down
				root.push_input(click, true)
			await process_frame
			await process_frame
			_check(game.modal_kind == "tower" and game.selected_slot == slot, "A real map click opens the correct tower construction popup")
			await _capture("tower_popup_round_%d_slot_%d" % [game.state.round_index, slot + 1])
			expected_name = "TowerConfirm"
	await process_frame
	var button: Button = _find_button(game.screen, TranslationServer.translate(key), expected_name)
	if not _check(button != null and not button.disabled, "An enabled real button exists for " + key):
		return
	var center: Vector2 = button.get_global_rect().get_center()
	var clicked: Array[bool] = [false]
	button.pressed.connect(func() -> void: clicked[0] = true, CONNECT_ONE_SHOT)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	root.push_input(motion, true)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = center
	event.global_position = center
	event.pressed = true
	root.push_input(event, true)
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = center
	event.global_position = center
	event.pressed = false
	root.push_input(event, true)
	await process_frame
	await process_frame
	_check(clicked[0], "The actual pointer click emits the button pressed signal: " + key)


func _find_button(node: Node, text: String, expected_name: String) -> Button:
	if node is Button:
		var button: Button = node as Button
		if button.text == text and (expected_name.is_empty() or button.name == expected_name):
			return button
	for child: Node in node.get_children():
		var result: Button = _find_button(child, text, expected_name)
		if result != null:
			return result
	return null


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _check_checkpoint(prefix: String) -> void:
	_check(game.state.gold == 20 and game.state.castle_hp == 100, prefix + " restores bank 20 and castle HP 100 without supply income")
	_check(game.state.tower_levels == [1, 0, 0, 0, 0, 0] and game.player_health == 100, prefix + " restores one base tower, six available slots, and soldier HP 100")
	_check(game.fortress.find_children("*", "AnimatedSprite2D", true, false).is_empty(), prefix + " contains no lumber worker while tree art remains")
	_check(game.fortress.get_tree_visuals().size() == 3, prefix + " keeps all three original decorative trees")


func _check_seal_description() -> void:
	var kind: String = WaveLedger.alarm_enemy_kind(1)
	var definition: Dictionary = MonsterCatalog.get_definition(kind)
	var expected: String = "1 " + TranslationServer.translate(definition["name_key"])
	var label: Label = game.modal.find_child("SealedDescription", true, false) as Label
	_check(kind == "armored_skeleton" and WaveLedger.alarm_enemy_count(1) == 1, "The first seal promises exactly one armored skeleton")
	_check(label != null and label.text.contains(expected), "The actual sealed-chest modal names the same count and type that the wave will spawn")


func _check(condition: bool, description: String) -> bool:
	checks.append({"description": description, "passed": condition})
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)
	return condition


func _capture(name: String) -> void:
	await process_frame
	_check_label_bounds(name)
	_check_translation_keys(name)
	if game.modal_kind == "controls":
		_check_controls_back_clear()
	if capture_dir.is_empty():
		return
	if DisplayServer.get_name() == "headless":
		_check(false, "Screenshot capture requires a graphical display")
		return
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(capture_dir)
	if not _check(directory_error == OK, "The screenshot directory is writable"):
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var filename: String = capture_dir.path_join(name + ".png")
	_check(image != null and not image.is_empty() and image.save_png(filename) == OK, "Captured actual viewport: " + name)


func _check_label_bounds(phase_name: String) -> void:
	var labels: Array[Node] = game.screen.find_children("*", "Label", true, false)
	var viewport_size: Vector2 = root.get_visible_rect().size
	if viewport_size.x < 1.0 or viewport_size.y < 1.0:
		var configured_width: int = ProjectSettings.get_setting("display/window/size/viewport_width", 1280)
		var configured_height: int = ProjectSettings.get_setting("display/window/size/viewport_height", 720)
		viewport_size = Vector2(configured_width, configured_height)
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, viewport_size)
	var overflow: PackedStringArray = []
	for node: Node in labels:
		var label: Label = node as Label
		if not label.is_visible_in_tree() or label.text.is_empty():
			continue
		var rectangle: Rect2 = label.get_global_rect()
		if not viewport_rect.encloses(rectangle):
			overflow.append(label.text + " " + str(rectangle))
	_check(overflow.is_empty(), "Visible labels stay within the viewport: " + phase_name)
	if not overflow.is_empty():
		print("LABEL_OVERFLOW=" + JSON.stringify({"phase": phase_name, "viewport": str(viewport_rect), "labels": overflow}))


func _check_translation_keys(phase_name: String) -> void:
	var expression: RegEx = RegEx.new()
	expression.compile("\\bUI_[A-Z0-9_]+\\b")
	var unresolved: PackedStringArray = []
	for node: Node in game.screen.find_children("*", "Control", true, false):
		var control: Control = node as Control
		if not control.is_visible_in_tree():
			continue
		var text: String = control.text if control is Label or control is Button else ""
		if expression.search(text) != null:
			unresolved.append(text)
	_check(unresolved.is_empty(), "Visible player text has no untranslated keys: " + phase_name)


func _check_controls_back_clear() -> void:
	var button: Button = _find_button(game.modal, TranslationServer.translate("UI_BACK"), "")
	if not _check(button != null, "The controls modal has a real Back button"):
		return
	var overlap: PackedStringArray = []
	for node: Node in game.modal.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label.get_global_rect().intersects(button.get_global_rect()):
			overlap.append(label.text)
	_check(overlap.is_empty(), "Chinese controls text does not overlap the Back button")
	if not overlap.is_empty():
		print("CONTROLS_BUTTON_OVERLAP=" + JSON.stringify(overlap))


func _finish() -> void:
	for action: String in ["fb_move_right", "fb_sword", "fb_interact"]:
		Input.action_release(action)
	Engine.time_scale = 1.0
	var report: Dictionary = {"validation": "scripted integration; player repositioning; real input/combat/economy", "ui_only": ui_only, "engine_time_scale": 4, "checks": checks, "failures": failures, "elapsed_real_seconds": (Time.get_ticks_msec() - start_ticks) / 1000.0, "observed_alarm_enemy": observed_alarm_enemy, "observed_safe_alarm_enemy": observed_safe_alarm_enemy}
	print("DEMO_FLOW_RESULT=" + JSON.stringify(report))
	if not capture_dir.is_empty():
		var file: FileAccess = FileAccess.open(capture_dir.path_join("integration-result.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
			file.close()
	call_deferred("_dispose_and_quit", 0 if failures == 0 else 1)

func _dispose_and_quit(exit_status: int) -> void:
	game.audio.stop_all()
	current_scene = null
	game.queue_free()
	game = null
	await process_frame
	await process_frame
	await create_timer(0.1, true, false, true).timeout
	quit(exit_status)
