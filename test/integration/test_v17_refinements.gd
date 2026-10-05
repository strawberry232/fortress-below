extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://game/scenes/main.tscn")
const CATALOG: Script = preload("res://game/data/monsters/monster_catalog.gd")

var game: Node2D
var capture_dir: String = "res://docs/verification/v17/visual-gl"
var checks: Array[Dictionary] = []
var failures: int = 0
var started_ticks: int = 0

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
	started_ticks = Time.get_ticks_msec()
	call_deferred("_run")

func _run() -> void:
	Engine.time_scale = 1.0
	game = MAIN_SCENE.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame
	await _firepower_case()
	await _map_case(0, true)
	await _map_case(1, true)
	await _dungeon_vampire_case()
	await _map_case(2, false)
	await _defense_vampire_case()
	var report: Dictionary = {
		"checks": checks, "failures": failures, "renderer": DisplayServer.get_name(),
		"time_scale": Engine.time_scale, "elapsed_seconds": (Time.get_ticks_msec() - started_ticks) / 1000.0,
		"fixtures": "Selected authored actors and player positions; other dungeon actors frozen; the dungeon vampire's first life set to 25 HP after capturing its default 120 HP. Isolated tower-defense vampire receives a lethal fixture arrow. Real J/E input, mouse UI, original frame playback, physics, clocks and pause at time_scale=1; no health reset or revival time skipping."
	}
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var file: FileAccess = FileAccess.open(capture_dir.path_join("refinements-result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print("V17_REFINEMENTS_RESULT=" + JSON.stringify(report))
	game.audio.stop_all()
	current_scene = null
	game.queue_free()
	game = null
	await process_frame
	await process_frame
	await create_timer(0.1, true, false, true).timeout
	quit(0 if failures == 0 else 1)

func _fresh_dungeon(index: int) -> void:
	game.start_campaign()
	game.state.round_index = index + 1
	game.enter_dungeon()
	await physics_frame
	await physics_frame
	for actor: CharacterBody2D in game.dungeon._enemies:
		actor.set_physics_process(false)
	game.dungeon.player.velocity = Vector2.ZERO

func _enemy(kind: String) -> CharacterBody2D:
	for actor: CharacterBody2D in game.dungeon._enemies:
		if actor.monster_kind == kind and actor.health.is_alive():
			return actor
	return null

func _until(predicate: Callable, timeout: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await physics_frame
	return predicate.call()

func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await physics_frame
		await physics_frame

func _click(button: Button) -> bool:
	if not _check(is_instance_valid(button) and not button.disabled, "The requested real GUI button is available"):
		return false
	var point: Vector2 = button.get_global_rect().get_center()
	print("GUI_CLICK=" + JSON.stringify({"text": button.text, "point": str(point), "phase": game.state.phase, "modal": game.modal_kind, "paused": paused}))
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	print("GUI_CLICK_RESULT=" + JSON.stringify({"phase": game.state.phase, "modal": game.modal_kind, "paused": paused}))
	return true

func _click_text(key: String) -> bool:
	for button: Button in game.interface.find_children("*", "Button", true, false):
		if button.text == TranslationServer.translate(key) and button.is_visible_in_tree():
			return await _click(button)
	return _check(false, "Missing real translated button: " + key)

func _firepower_case() -> void:
	game.start_campaign()
	game.state.phase = game.state.Phase.DEFENSE
	game._render_phase(game.state.phase)
	game.fortress.start_wave(false, game.state.tower_levels, 1)
	game.fortress.set_process(false)
	game.fortress.ledger.pending.assign(["orc", "orc"])
	game.fortress._spawn_enemy()
	game.fortress.spawn_clock = 100.0
	game.fortress.enemies[1]["pos"] = Vector2(420, 245)
	game.fortress.enemies[1]["waypoint"] = 2
	game.fortress.tower_clocks[0] = 0.15
	var shots: Array[int] = []
	var record_shot: Callable = func(event: String, _at: Vector2) -> void:
		if event == "tower_shot":
			shots.append(Time.get_ticks_msec())
	game.fortress.feedback_requested.connect(record_shot)
	var gold: int = game.state.gold
	game._process(0.0)
	_check(game.rally_button.text == TranslationServer.translate("UI_RALLY"), "The real skill button displays the firepower name")
	_check(await _click(game.rally_button), "A real mouse click activates firepower")
	_check(game.fortress.rally_seconds == 4.0 and game.fortress.ledger.rally_cooldown_left == 12.0, "Firepower starts with its actual four-second duration and twelve-second cooldown")
	_check(game.state.gold == gold, "Firepower spends no gold")
	game.fortress.set_process(true)
	await create_timer(0.14).timeout
	game._process(0.0)
	_check(game.rally_button.disabled and game.rally_button.text == TranslationServer.translate("UI_RALLY_ACTIVE"), "The real GUI identifies active firepower and blocks cooldown reuse")
	var warm: bool = false
	for sprite: AnimatedSprite2D in game.effects.get_children():
		var texture: AtlasTexture = sprite.sprite_frames.get_frame_texture("effect", 0) as AtlasTexture
		if texture.atlas.resource_path.ends_with("/fx/burst.png") and texture.region.position.y == 0.0:
			warm = true
	_check(warm, "Constructed archers show the existing warm burst row instead of green healing")
	await _capture("firepower_active_warm")
	_check(await _until(func() -> bool: return shots.size() >= 3, 2.0), "The actual running tower emits at least three accelerated arrows")
	if shots.size() >= 3:
		var interval: float = (shots[2] - shots[1]) / 1000.0
		_check(interval >= 0.58 and interval <= 0.67, "Real accelerated arrow emission uses approximately 0.603 seconds per shot")
	await _key(KEY_ESCAPE)
	var duration: float = game.fortress.rally_seconds
	var cooldown: float = game.fortress.ledger.rally_cooldown_left
	await create_timer(0.25, true, false, true).timeout
	_check(paused and game.fortress.rally_seconds == duration and game.fortress.ledger.rally_cooldown_left == cooldown, "Actual pause freezes firepower duration and cooldown")
	await _click_text("UI_RESUME")
	_check(await _until(func() -> bool: return game.fortress.rally_seconds == 0.0, 3.5), "Firepower ends naturally after its real four-second active clock")
	_check(game.fortress.ledger.rally_cooldown_left > 7.0 and game.fortress.ledger.rally_cooldown_left < 8.2, "Active duration expiry retains the expected cooldown")
	await _capture("firepower_cooldown")
	game.fortress.set_process(false)
	game.fortress.feedback_requested.disconnect(record_shot)
	game.fortress.set_process(true)

func _map_case(index: int, fresh: bool) -> void:
	if fresh:
		await _fresh_dungeon(index)
	var world: Node2D = game.dungeon
	var exit_visual: Dictionary = world.get_exit_visual()
	_check(exit_visual["model"] == "wall_ladder" and exit_visual["source"] == Rect2(144, 48, 16, 16), "Map %d uses the authentic north-wall ladder tile" % (index + 1))
	_check(not world.is_walkable(exit_visual["wall_position"]) and world.is_walkable(exit_visual["interaction_position"]), "Map %d separates the solid ladder wall and reachable floor interaction" % (index + 1))
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(world.to_global(world.stairs_position + Vector2(0, -12)), world.to_global(exit_visual["wall_position"]), 1)
	_check(not world.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(), "Map %d retains an actual physical supporting wall" % (index + 1))
	await _capture("map_%d_wall_ladder" % (index + 1))
	world.player.position = world.stairs_position
	await _key(KEY_E)
	_check(game.state.phase == game.state.Phase.DUNGEON and not game.state.has_goal_key, "Map %d rejects real E at the wall ladder before taking the key" % (index + 1))
	await _capture("map_%d_wall_ladder_locked" % (index + 1))
	var sealed: Dictionary = world.get_chest_visual("sealed")
	var tint: Color = sealed["tint"]
	_check(sealed["indicator"] == "exclamation" and sealed["warning_key"] == "" and not sealed["seal"] and tint != Color.WHITE, "Map %d sealed chest keeps red and its exclamation with no crossed seal or text" % (index + 1))
	world.player.position = world.sealed_chest_position - Vector2(42, 0)
	await _capture("map_%d_sealed_before" % (index + 1))
	await _key(KEY_E)
	_check(game.modal_kind == "sealed" and world.process_mode == Node.PROCESS_MODE_DISABLED, "Map %d real E opens the unchanged side-effect confirmation and freezes dungeon actors" % (index + 1))
	_check(await _click_text("UI_SEALED_ACCEPT"), "Map %d real mouse confirmation opens the sealed chest" % (index + 1))
	var seen: Dictionary = {}
	_check(await _until(func() -> bool: return world.get_chest_visual("sealed")["state"] == "opening", 0.3), "Map %d begins its original opening animation" % (index + 1))
	while world.get_chest_visual("sealed")["state"] == "opening":
		var visual: Dictionary = world.get_chest_visual("sealed")
		seen[visual["frame"]] = true
		_check(visual["tint"] == tint and visual["warning_key"] == "" and not visual["seal"], "Opening frame keeps the same red tint and no overlay")
		if visual["frame"] == 2 and not seen.has("captured"):
			seen["captured"] = true
			await _capture("map_%d_sealed_opening" % (index + 1))
		await physics_frame
	for frame: int in range(4):
		_check(seen.has(frame), "Map %d renders original opening frame %d" % [index + 1, frame])
	sealed = world.get_chest_visual("sealed")
	_check(sealed["state"] == "opened" and sealed["frame"] == 3 and sealed["tint"] == tint, "Map %d completed chest remains the same red instead of turning white" % (index + 1))
	_check(game.state.alarm and game.state.bag_gold == game.state.balance.sealed_chest_gold, "Map %d real confirmation retains its actual reinforcement alarm and reward" % (index + 1))
	await create_timer(0.45).timeout
	await _capture("map_%d_sealed_after" % (index + 1))
	if fresh:
		var guard: CharacterBody2D = _enemy("skull")
		if _check(guard != null, "The real map reward guardian exists"):
			guard.target = null
			guard.set_physics_process(true)
			world.player.position = guard.position - Vector2(45, 0)
			world.player.facing = 1
			for strike: int in range(4):
				if not is_instance_valid(guard) or not guard.health.is_alive():
					break
				await _key(KEY_J)
				await create_timer(0.66).timeout
	_check(world._reward_guard_defeated, "Map %d real final guardian defeat permits key pickup" % (index + 1))
	world.player.position = world.key_position
	await _key(KEY_E)
	_check(game.state.has_goal_key and world._key_taken, "Map %d real E collects the actual key after the guardian" % (index + 1))
	world.player.position = world.stairs_position
	await _capture("map_%d_wall_ladder_ready" % (index + 1))
	await _key(KEY_E)
	_check(game.state.phase == game.state.Phase.SETTLEMENT and game.state.bag_gold == 0, "Map %d real E in front of the wall ladder returns and settles carried loot" % (index + 1))

func _dungeon_vampire_case() -> void:
	await _fresh_dungeon(2)
	var vampire: CharacterBody2D = _enemy("vampire")
	if not _check(vampire != null, "The third authored dungeon contains its elite vampire"):
		return
	vampire.position = game.dungeon._layout["reward_guard"]
	vampire.target = null
	vampire.set_physics_process(true)
	game.dungeon.player.position = vampire.position - Vector2(45, 0)
	game.dungeon.player.facing = 1
	var identity: int = vampire.get_instance_id()
	var defeated: Array[bool] = []
	vampire.defeated.connect(func() -> void: defeated.append(true))
	_check(vampire.health.current == 120 and vampire.revival.lives_left == 2, "The dungeon vampire begins with two lives and its full elite health")
	await _capture("dungeon_vampire_before")
	vampire.health.current = 25
	await _key(KEY_J)
	_check(await _until(func() -> bool: return vampire.revival.pending, 1.0), "An actual J sword strike triggers the first-life defeat")
	_check(not vampire.health.is_alive() and defeated.is_empty() and not game.dungeon._reward_guard_defeated, "The first life keeps the guardian obligation instead of unlocking the key")
	_check(vampire.revival.lives_left == 1, "First defeat consumes exactly one vampire life")
	await _capture("dungeon_vampire_dying")
	_check(await _until(func() -> bool: return vampire.revival.sample()["phase"] == "ashes", 1.7), "The source fourteen-frame death finishes into its actual ash pile")
	_check(vampire._sprite.frame == 13 and not vampire.is_queued_for_deletion(), "The final original ash frame remains on the dungeon floor")
	await _capture("dungeon_vampire_ashes")
	await _key(KEY_ESCAPE)
	var elapsed: float = vampire.revival.elapsed
	await create_timer(0.3, true, false, true).timeout
	_check(paused and vampire.revival.elapsed == elapsed and vampire._sprite.frame == 13, "A real pause freezes the pending vampire and ash frame")
	await _click_text("UI_RESUME")
	_check(await _until(func() -> bool: return vampire.revival.elapsed >= 4.92, 3.7), "Three full ash seconds elapse before reverse source playback progresses")
	_check(vampire.revival.sample()["phase"] == "reforming" and vampire._sprite.frame > 0 and vampire._sprite.frame < 13 and not vampire.health.is_alive(), "Reverse death frames visibly rebuild the body while it remains harmless")
	await _capture("dungeon_vampire_reforming")
	_check(await _until(func() -> bool: return not vampire.revival.pending, 1.3), "The actual reverse animation completes without fixture health reset")
	_check(vampire.get_instance_id() == identity and vampire.health.current == 120 and vampire.revival.lives_left == 1, "The same authored vampire revives once at its full 120 health")
	_check(defeated.is_empty() and not game.dungeon._reward_guard_defeated and vampire._sprite.animation == &"idle", "The revived guardian still blocks the key and visibly returns to idle")
	await _capture("dungeon_vampire_revived")
	await create_timer(0.4).timeout
	for strike: int in range(6):
		if not vampire.health.is_alive():
			break
		await _key(KEY_J)
		await create_timer(0.66).timeout
	_check(not vampire.health.is_alive() and defeated.size() == 1 and not vampire.revival.pending, "New real sword strikes consume the second life and emit exactly one final defeat")
	_check(game.dungeon._reward_guard_defeated and game.dungeon._reward_guardians == 0, "The actual second defeat finally releases the reward guardian")
	await _capture("dungeon_vampire_final_death")
	_check(await _until(func() -> bool: return not is_instance_id_valid(identity), 2.0), "The complete final death cleans up without a third life")

func _defense_vampire_case() -> void:
	game.start_campaign()
	game.state.phase = game.state.Phase.DEFENSE
	game._render_phase(game.state.phase)
	var world: Node2D = game.fortress
	var levels: Array[int] = [0, 0, 0, 0, 0, 0]
	world.start_wave(false, levels, 3)
	world.set_process(false)
	world.ledger.pending.assign(["vampire"])
	world._spawn_enemy()
	var id: int = 1
	var enemy: Dictionary = world.enemies[id]
	enemy["pos"] = Vector2(200, 245)
	enemy["waypoint"] = 1
	enemy["traveled"] = 184.0
	enemy["progress"] = enemy["traveled"] / enemy["path_length"]
	_check(enemy["hp"] == 110 and enemy["revival"].lives_left == 2, "The defense elite begins at 110 health with two lives")
	await _capture("defense_vampire_before")
	var completed: Array[bool] = []
	world.wave_completed.connect(func() -> void: completed.append(true))
	world.arrows.append({"pos": enemy["pos"] - Vector2(80, 18), "target": id, "damage": 111})
	world.set_process(true)
	_check(await _until(func() -> bool: return enemy["revival"].pending, 1.0), "A real traveling tower-defense arrow triggers the first defeat")
	var stopped_at: Vector2 = enemy["pos"]
	_check(world.enemies.has(id) and world.ledger.alive.has(id) and world.remaining_enemies() == 1 and not world.ledger.is_complete(), "Temporary defense ashes retain the same identity and living wave obligation")
	_check(enemy["hp"] == 0 and world.corpses.is_empty(), "Temporary ashes use the original enemy rather than a final corpse")
	_check(await _until(func() -> bool: return enemy["revival"].sample()["phase"] == "ashes", 1.7), "The defense vampire also retains the original final ash frame")
	await _capture("defense_vampire_ashes")
	await _key(KEY_ESCAPE)
	var elapsed: float = enemy["revival"].elapsed
	await create_timer(0.3, true, false, true).timeout
	_check(paused and enemy["revival"].elapsed == elapsed and enemy["pos"] == stopped_at, "Actual pause freezes defense ashes and their route position")
	await _click_text("UI_RESUME")
	_check(await _until(func() -> bool: return enemy["revival"].elapsed >= 4.92, 3.7), "The defense corpse waits three ash seconds and begins source-frame reassembly")
	var visual: Dictionary = world.get_enemy_visual(enemy)
	_check(visual["sample"]["phase"] == "reforming" and visual["sample"]["frame"] > 0 and visual["sample"]["frame"] < 13 and not visual["show_health_bar"], "Defense reverse frames are visible and remain untargetable")
	await _capture("defense_vampire_reforming")
	_check(await _until(func() -> bool: return not enemy["revival"].pending, 1.3), "Defense resurrection completes naturally without skipping its clock")
	_check(world.enemies.has(id) and enemy["hp"] == 110 and enemy["max_hp"] == 110 and enemy["revival"].lives_left == 1, "The same defense identity regains a full second 110-health life")
	_check(world.ledger.alive.has(id) and completed.is_empty() and enemy["pos"].distance_to(stopped_at) < 2.0, "The wave remains unfinished and the route position is preserved on resurrection")
	await _capture("defense_vampire_revived")
	await create_timer(0.4).timeout
	world.arrows.append({"pos": enemy["pos"] - Vector2(80, 18), "target": id, "damage": 111})
	_check(await _until(func() -> bool: return not world.enemies.has(id), 1.0), "A later actual traveling arrow causes the final second defeat")
	_check(not world.ledger.alive.has(id) and world.ledger.is_complete() and world.corpses.size() == 1 and completed.is_empty(), "Only final defeat clears the ledger and waits for its complete death animation")
	await _capture("defense_vampire_final_death")
	_check(await _until(func() -> bool: return completed.size() == 1, 2.0), "The real wave finishes once after the final vampire death animation")
	_check(not world.running and world.enemies.is_empty(), "No third vampire life remains after actual completion")

func _capture(name: String) -> void:
	if not _check(DisplayServer.get_name() != "headless", "Graphical GL viewport is active for " + name):
		return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var previous: bool = paused
	paused = true
	await process_frame
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	_check(screenshot != null and screenshot.save_png(capture_dir.path_join(name + ".png")) == OK, "Saved original-render viewport " + name)
	paused = previous

func _check(condition: bool, description: String) -> bool:
	checks.append({"description": description, "passed": condition})
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)
	return condition
