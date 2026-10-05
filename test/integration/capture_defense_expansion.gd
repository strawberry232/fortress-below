extends SceneTree

const WorldScript = preload("res://game/scripts/defense/fortress_world.gd")
const OUTPUT_DIRECTORY: String = "res://docs/verification/monster-update/defense-screenshots"
var failures: int = 0
var checks: int = 0
var screenshots: Array[String] = []
var game: Node

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1280, 720)
	game = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_campaign()
	game.set_process(false)
	game.audio.set_muted(true)
	var world: WorldScript = game.fortress
	world.set_process(false)
	world.feedback_requested.disconnect(game._on_feedback)
	_capture_phase(game.state.Phase.PREPARATION, 2, [1, 1, 1, 1, 1, 1], false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIRECTORY))
	await _save("six-tower-preparation.png")
	_check(game.hud_labels[1].text.contains("6 / 6"), "The actual Chinese HUD matches all six built towers")
	_check(game.game_theme.default_font.data == FileAccess.get_file_as_bytes("res://game/assets/fonts/fusion_pixel_12px_zh_hans.ttf"), "The real main scene uses the provided 12px Simplified Chinese font")
	_check(world.get_child_count() == 0, "No worker nodes are present")
	_check(world.get_tree_visuals().size() == 3, "Three original tree models remain")
	for slot: int in range(world.tower_points.size()):
		_check_foreground(world, slot)
	for entrance: Dictionary in world.get_road_visuals()["entrances"]:
		_check_entry_letter(world, entrance["position"])
	_capture_phase(game.state.Phase.DEFENSE, 1, [1, 1, 0, 0, 0, 0], true)
	world.start_wave(true, game.state.tower_levels, 1)
	for step: int in range(630):
		world._process(1.0 / 60.0)
	await _save("early-goblin-wave.png")
	_capture_phase(game.state.Phase.DEFENSE, 2, [1, 1, 0, 0, 0, 0], true)
	world.start_wave(true, game.state.tower_levels, 2)
	for step: int in range(980):
		world._process(1.0 / 60.0)
	await _save("dual-road-dungeon-monsters.png")
	_capture_phase(game.state.Phase.DEFENSE, 3, [1, 1, 1, 1, 1, 1], false)
	world.start_wave(false, game.state.tower_levels, 3)
	world.ledger.pending.clear()
	for kind: String in ["skeleton", "armored_skeleton", "skull", "vampire"]:
		world.ledger.pending.append(kind)
	for index: int in range(4):
		world._spawn_enemy()
		world.enemies[index + 1]["pos"] = Vector2(156 + index * 150, 330)
	world.running = false
	world.queue_redraw()
	await _save("four-monster-lineup.png")
	_capture_phase(game.state.Phase.PREPARATION, 3, [1, 0, 0, 0, 0, 0], false)
	var tower_origin: Vector2 = world.tower_points[0] - Vector2(64, 224)
	var platform: Vector2 = tower_origin + Vector2(64, 106)
	world.scale = Vector2(3, 3)
	world.position = Vector2(640, 400) - platform * 3.0
	for facing: bool in [false, true]:
		world.archer_facing_left[0] = facing
		world.archer_shoot_seconds[0] = 0.0
		world.queue_redraw()
		await _save("archer-idle-%s.png" % ("left" if facing else "right"))
		_check_foreground(world, 0)
		var helmet: Color = world.textures["soldier_bow"].get_image().get_pixel(50, 43)
		var head_at: Vector2 = platform + Vector2(-1.5 if facing else 1.5, -49.5)
		var image: Image = root.get_texture().get_image()
		var pixel: Vector2i = Vector2i(world.to_global(head_at).floor())
		_check(image.get_pixelv(pixel).is_equal_approx(helmet), "Bow soldier helmet remains above the platform when mirrored")
		world.archer_shoot_seconds[0] = world.balance.archer_shoot_duration
		world.queue_redraw()
		await _save("archer-release-%s.png" % ("left" if facing else "right"))
		_check_foreground(world, 0)
		world.archer_shoot_seconds[0] = world.balance.archer_shoot_duration - 0.1
		world.queue_redraw()
		await _save("archer-recovery-%s.png" % ("left" if facing else "right"))
		_check_foreground(world, 0)
	var report: Dictionary = {"failures": failures, "checks": checks, "screenshots": screenshots, "directory": ProjectSettings.globalize_path(OUTPUT_DIRECTORY)}
	var output: FileAccess = FileAccess.open(OUTPUT_DIRECTORY.path_join("capture-result.json"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	else:
		failures += 1
	print("DEFENSE_CAPTURE_RESULT " + JSON.stringify(report))
	game.audio.stop_all()
	game.queue_free()
	for index: int in range(4):
		await process_frame
	await create_timer(0.1, true, false, true).timeout
	quit(0 if failures == 0 else 1)

func _capture_phase(phase: int, round_index: int, levels: Array[int], alarm: bool) -> void:
	game.state.phase = phase
	game.state.round_index = round_index
	game.state.tower_levels.assign(levels)
	game.state.alarm = alarm
	game._render_phase(phase)

func _check_foreground(world: WorldScript, slot: int) -> void:
	var tower_pixel: Color = world.textures["tower"].get_image().get_pixel(64, 106)
	var local_at: Vector2 = world.tower_points[slot] - Vector2(64, 224) + Vector2(64.5, 106.5)
	var pixel: Vector2i = Vector2i(world.to_global(local_at).floor())
	_check(root.get_texture().get_image().get_pixelv(pixel).is_equal_approx(tower_pixel), "Tower front battlement masks the three-times-scale archer feet")

func _check_entry_letter(world: WorldScript, at: Vector2) -> void:
	var image: Image = root.get_texture().get_image()
	var upper: Vector2i = Vector2i(world.to_global(at - Vector2(14, 10)).floor())
	var min_y: int = 1000
	var max_y: int = -1
	for y: int in range(21):
		for x: int in range(28):
			var color: Color = image.get_pixelv(upper + Vector2i(x, y))
			if absf(color.r - 1.0) < 0.01 and absf(color.g - 0.87) < 0.01 and absf(color.b - 0.55) < 0.01:
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	_check(max_y - min_y + 1 >= 8, "Pixel-font road letters remain at least eight visible pixels high")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _save(filename: String) -> void:
	game._refresh_hud()
	await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(OUTPUT_DIRECTORY.path_join(filename))
	_check(result == OK, "Defense screenshot saves successfully")
	if result == OK:
		screenshots.append(filename)
