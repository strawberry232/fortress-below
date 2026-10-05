extends SceneTree

const MAIN: PackedScene = preload("res://game/scenes/main.tscn")
const BOLT: Script = preload("res://game/scripts/combat/fortress_enemy_projectile.gd")

var game: Node2D
var capture_dir: String = "res://docs/verification/v15/behavior-gl"
var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
	call_deferred("_run")

func _run() -> void:
	Engine.time_scale = 1.0
	game = MAIN.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_campaign()
	await _capture("compact_preparation")
	game.enter_dungeon()
	await physics_frame
	await _slime_case()
	await _real_sword_split_case()
	await _armored_combo_case()
	await _skull_hit_case()
	await _skull_dodge_case()
	await _vampire_case()
	await _spike_case()
	await _map_art_case()
	var report: Dictionary = {"checks": checks, "failures": failures, "renderer": DisplayServer.get_name(), "fixtures": "Isolated authored actors and selected player positions; real physics, animations, collision, input and render at time_scale=1"}
	var file: FileAccess = FileAccess.open(capture_dir.path_join("behavior-result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print("BEHAVIOR_RESULT=" + JSON.stringify(report))
	current_scene = null
	game.audio.stop_all()
	game.queue_free()
	game = null
	await process_frame
	await process_frame
	await create_timer(0.1, true, false, true).timeout
	quit(0 if failures == 0 else 1)

func _fresh(index: int) -> void:
	game.state.round_index = index + 1
	game.dungeon.reset_run(index)
	game._render_phase(game.state.Phase.DUNGEON)
	await physics_frame
	await physics_frame
	for actor: CharacterBody2D in game.dungeon._enemies:
		actor.set_physics_process(false)
	game.dungeon.player.velocity = Vector2.ZERO

func _enemy(kind: String) -> CharacterBody2D:
	for actor: CharacterBody2D in game.dungeon._enemies:
		if actor.monster_kind == kind:
			return actor
	return null

func _live_bolt() -> Node2D:
	for child: Node in game.dungeon._content.get_children():
		if child.get_script() == BOLT and not child.is_queued_for_deletion():
			return child
	return null

func _until(predicate: Callable, timeout: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await physics_frame
	return predicate.call()

func _slime_case() -> void:
	await _fresh(0)
	var slime: CharacterBody2D = _enemy("slime")
	game.dungeon.player.position = slime.position - Vector2(110, 0)
	_check(slime._sprite.scale == Vector2(4, 4), "Adult slime is visibly enlarged without changing original pixels")
	await _capture("adult_slime")
	var guards: int = game.dungeon._middle_guardians
	slime.receive_damage(1000, "fixture-split")
	await process_frame
	var children: Array[CharacterBody2D] = []
	for actor: CharacterBody2D in game.dungeon._enemies:
		if actor.slime_generation == 1:
			children.append(actor)
	_check(children.size() == 2, "One defeated slime visibly creates exactly two children")
	_check(game.dungeon._middle_guardians == guards + 1, "Gate count reserves both small guardians before releasing the adult")
	for child: CharacterBody2D in children:
		child.set_physics_process(false)
		_check(child._sprite.scale == Vector2(2, 2) and child.health.maximum == 14, "Children use smaller original full animations and independent health")
	await _capture("slime_split")
	_check(slime._sprite.animation == &"death", "The adult keeps its complete death animation beside the children")

func _skull_hit_case() -> void:
	await _fresh(0)
	var skull: CharacterBody2D = _enemy("skull")
	game.dungeon.player.position = skull.position - Vector2(112, 0)
	skull.set_physics_process(true)
	_check(await _until(func() -> bool: return skull._attack_elapsed >= 0.16, 1.0), "Real ghost physics begins its visible ranged charge")
	_check(skull._cast_sprite.visible and game.dungeon.get_player_health() == 100, "Blue charge is visible before damage")
	await _capture("skull_charge")
	_check(await _until(func() -> bool: return _live_bolt() != null, 1.0), "The ghost launches an actual blue animated projectile")
	await _capture("skull_projectile")
	_check(await _until(func() -> bool: return game.dungeon.get_player_health() == 90, 1.5), "The swept hostile projectile collision applies ten actual player damage")
	skull.set_physics_process(false)
	_check(game.dungeon.get_player_health() == 90, "The single bolt does not double-hit its player")

func _real_sword_split_case() -> void:
	await _fresh(0)
	var adult: CharacterBody2D = _enemy("slime")
	adult.position = Vector2(480, 352)
	adult.health.current = 25
	game.dungeon.player.position = adult.position - Vector2(45, 0)
	game.dungeon.player.facing = 1
	await physics_frame
	await _tap("fb_sword")
	_check(await _until(func() -> bool: return not adult.health.is_alive(), 1.0), "An actual J swing lands the adult slime's fatal hit")
	await create_timer(0.21).timeout
	var children: Array[CharacterBody2D] = []
	for actor: CharacterBody2D in game.dungeon._enemies:
		if actor.slime_generation == 1:
			actor.set_physics_process(false)
			children.append(actor)
	_check(children.size() == 2, "The real fatal sword spawns exactly two children")
	for child: CharacterBody2D in children:
		_check(child.health.current == 14, "Every child survives the fatal sword's remaining active frames")
	await _capture("real_sword_both_children_alive")
	await create_timer(0.4).timeout
	for child: CharacterBody2D in children:
		child.health.tick(0.4)
	await _tap("fb_sword")
	await create_timer(0.5).timeout
	var remaining: int = 0
	for child: CharacterBody2D in children:
		if is_instance_valid(child) and child.health.is_alive():
			remaining += 1
	_check(remaining < 2, "A later real J swing damages the now-vulnerable children normally")

func _armored_combo_case() -> void:
	await _fresh(1)
	var actor: CharacterBody2D = _enemy("armored_skeleton")
	game.dungeon.player.position = actor.position - Vector2(60, 0)
	actor.set_physics_process(true)
	_check(await _until(func() -> bool: return actor._attack_elapsed >= 0.3, 1.0), "An actual armored combo starts with its source preparation frames")
	_check(game.dungeon.get_player_health() == 100, "There is no damage before the first visible sword slash")
	_check(await _until(func() -> bool: return game.dungeon.get_player_health() == 82, 0.8), "The first visible armored slash applies eighteen damage")
	await _capture("armored_first_swing")
	_check(await _until(func() -> bool: return game.dungeon.get_player_health() == 64, 1.0), "The second visible armored slash independently applies eighteen damage")
	await _capture("armored_second_swing")
	actor.set_physics_process(false)
	await create_timer(0.3).timeout
	_check(game.dungeon.get_player_health() == 64, "No swing repeatedly applies damage during recovery")

func _skull_dodge_case() -> void:
	await _fresh(0)
	var skull: CharacterBody2D = _enemy("skull")
	game.dungeon.player.position = skull.position - Vector2(112, 0)
	skull.set_physics_process(true)
	_check(await _until(func() -> bool: return _live_bolt() != null, 1.0), "A second isolated ghost attack emits its real projectile")
	skull.set_physics_process(false)
	Input.action_press("fb_move_down")
	await create_timer(0.24).timeout
	Input.action_release("fb_move_down")
	await physics_frame
	await _capture("skull_bolt_dodge")
	_check(game.dungeon.get_player_health() == 100, "Real movement can dodge the locked blue projectile direction")
	_check(await _until(func() -> bool: return game.dungeon._content.find_child("SkullImpact*", false, false) != null, 1.5), "The missed bolt stops at the real dungeon wall and plays blue impact")
	await _capture("skull_wall_impact")
	await create_timer(0.5).timeout
	_check(_live_bolt() == null and game.dungeon._content.find_child("SkullImpact*", false, false) == null, "The consumed bolt and nonlooping impact both clean up")

func _vampire_case() -> void:
	await _fresh(2)
	var vampire: CharacterBody2D = _enemy("vampire")
	game.dungeon.player.position = vampire.position - Vector2(120, 0)
	var start: Vector2 = vampire.position
	vampire.set_physics_process(true)
	_check(await _until(func() -> bool: return vampire._attack_elapsed >= 0.15, 1.0), "A vampire starts its original animation from beyond melee reach")
	_check(vampire.position.distance_to(start) < 1.0 and game.dungeon.get_player_health() == 100, "The vampire's windup stays stationary and permits dodging")
	await _capture("vampire_windup")
	_check(await _until(func() -> bool: return vampire._attack_elapsed >= 0.65, 1.0), "Vampire flight reaches its original airborne frames")
	_check(vampire.position.distance_to(start) > 40.0 and vampire._sprite.animation == &"attack", "The source flight animation now has real forward motion")
	await _capture("vampire_lunge")
	_check(await _until(func() -> bool: return game.dungeon.get_player_health() == 74, 1.0), "The elite lunge applies exactly twenty-six actual damage")
	await create_timer(0.4).timeout
	_check(game.dungeon.get_player_health() == 74, "Continuous flight and landing cannot hit the same player twice")
	vampire.set_physics_process(false)

func _spike_case() -> void:
	await _fresh(0)
	game.dungeon._clock = 2.02
	game.dungeon.player.position = game.dungeon._spikes[0] - Vector2(54, 0)
	_check(game.dungeon.is_spike_active(0) and game.dungeon.get_player_health() == 100, "Spikes have already risen while the player stands outside them")
	Input.action_press("fb_move_right")
	await create_timer(0.22).timeout
	Input.action_release("fb_move_right")
	await physics_frame
	_check(game.dungeon.get_player_health() == 80, "Walking onto already raised spikes causes real contact damage")
	await _capture("raised_spike_late_entry")
	_check(await _until(func() -> bool: return game.dungeon.get_player_health() == 60, 0.85), "Standing on the same raised interval hurts again after the trap cooldown")
	_check(game.dungeon.is_spike_active(0), "Both damages occur before the spikes retract")
	game.dungeon.player.position -= Vector2(80, 0)

func _map_art_case() -> void:
	for index: int in range(3):
		game.state.has_goal_key = false
		game.state.bag_gold = 0
		game.state.alarm = false
		game.state._sealed_chest_opened = false
		await _fresh(index)
		await _capture("map_%d_closed" % (index + 1))
		var screenshot: Image = root.get_texture().get_image()
		for marker: Vector2 in [game.dungeon.key_position, game.dungeon.sealed_chest_position, game.dungeon.stairs_position, game.dungeon._spikes[0]]:
			var at: Vector2 = game.dungeon.to_global(marker + Vector2(31, 0))
			var pixel: Color = screenshot.get_pixelv(Vector2i(at))
			_check(pixel.r < 0.45 and pixel.g < 0.4, "Original map pixels replace the colored circle at " + str(marker))
		game.dungeon.player.position = game.dungeon.ordinary_chest_position
		await _tap("fb_interact")
		await create_timer(0.19).timeout
		_check(game.dungeon.get_chest_visual("ordinary")["state"] == "opening", "Real E plays the small ordinary chest opening sequence")
		await _capture("map_%d_small_chest_opening" % (index + 1))
		game.dungeon.player.position = game.dungeon.sealed_chest_position
		await _tap("fb_interact")
		_check(game.modal_kind == "sealed", "The larger sealed chest still requires its real decision modal")
		await _accept_seal()
		await create_timer(0.19).timeout
		_check(game.dungeon.get_chest_visual("sealed")["state"] == "opening", "Real confirmation plays the distinct sealed chest opening sequence")
		await _capture("map_%d_large_chest_opening" % (index + 1))
		for actor: CharacterBody2D in game.dungeon._enemies.duplicate():
			actor.receive_damage(1000, "map-fixture-clear")
		await process_frame
		for actor: CharacterBody2D in game.dungeon._enemies:
			actor.set_physics_process(false)
			if actor.revival.pending:
				actor.set_physics_process(true)
				game.dungeon.player.position = game.dungeon.stairs_position
				_check(await _until(func() -> bool: return actor.health.is_alive(), 6.5), "The map fixture waits for the real second vampire life before clearing its guardian")
				actor.set_physics_process(false)
				actor.health.tick(0.4)
			if actor.health.is_alive():
				actor.health.tick(0.26)
				actor.receive_damage(1000, "map-fixture-child-clear")
		await create_timer(0.5).timeout
		_check(game.dungeon._middle_guardians == 0, "All doors switch to their opened art after clearing real guardian counts")
		game.dungeon.player.position = game.dungeon.key_position
		await _tap("fb_interact")
		_check(game.state.has_goal_key and game.dungeon.get_exit_visual()["direction"] == "up", "Taking the actual key activates the upward return indicator")
		await _capture("map_%d_opened" % (index + 1))

func _tap(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	Input.action_release(action)
	await physics_frame
	await physics_frame

func _accept_seal() -> void:
	var button: Button
	for child: Button in game.modal.find_children("*", "Button", true, false):
		if child.text == TranslationServer.translate("UI_SEALED_ACCEPT"):
			button = child
	if not _check(button != null, "The real seal-confirmation button exists"):
		return
	var center: Vector2 = button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.position = center
		click.global_position = center
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		root.push_input(click, true)
	await process_frame
	await process_frame

func _capture(name: String) -> void:
	_check(DisplayServer.get_name() != "headless", "Visual behavior proof uses a graphical renderer")
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var previous: bool = paused
	paused = true
	await process_frame
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	_check(screenshot != null and screenshot.save_png(capture_dir.path_join(name + ".png")) == OK, "Saved real GL viewport: " + name)
	paused = previous

func _check(condition: bool, description: String) -> bool:
	checks.append({"description": description, "passed": condition})
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)
	return condition
