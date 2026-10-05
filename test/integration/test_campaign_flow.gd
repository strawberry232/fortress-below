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
var start_ticks: int = 0
var feedback_counts: Dictionary = {}
var observed_routes: Dictionary = {}
var observed_enemy_kinds: Dictionary = {}
var route_trace_ok: bool = true
var route_samples: int = 0
var bow_damage_observed: bool = false

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
	start_ticks = Time.get_ticks_msec()
	call_deferred("_run")

func _run() -> void:
	Engine.time_scale = 4.0
	game = MAIN_SCENE.instantiate() as ControllerScript
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame
	game.dungeon.feedback_requested.connect(_record_feedback)
	game.fortress.feedback_requested.connect(_record_feedback)
	_check(game.state.phase == game.state.Phase.TITLE, "The real expanded scene opens its title menu")
	_check(TranslationServer.get_locale() == "zh_CN", "The expanded player interface defaults to Chinese")
	var music: AudioStreamPlayer = game.audio.get("music_player")
	_check(music.playing and game.audio.get("current_track").ends_with("goblins_den.ogg"), "The title plays the real regular music")
	await _capture("campaign_menu")
	var title_stream: AudioStream = music.stream
	var title_position: float = music.get_playback_position()
	if not await _click_button("UI_SOUND_ON", "SoundToggle"):
		_finish()
		return
	_check(game.audio.get_muted() and music.volume_db <= -70.0, "The real sound button mutes the playing music")
	_check(music.playing and music.stream == title_stream and music.get_playback_position() >= title_position, "Muting preserves the actual music stream and playback cursor")
	await _capture("sound_muted")
	await _click_button("UI_SOUND_OFF", "SoundToggle")
	_check(not game.audio.get_muted() and music.volume_db > -70.0, "The real sound button restores audio")
	await _click_button("UI_CONTROLS")
	await _capture("controls")
	await _click_button("UI_BACK")
	if not await _click_button("UI_START_CAMPAIGN", "StartCampaign"):
		_finish()
		return
	if not _check(game.state.phase == game.state.Phase.PREPARATION and game.state.balance.round_limit == 3, "The real StartCampaign button starts the three-round adventure"):
		_finish()
		return
	_check(game.state.gold == 20 and game.state.tower_levels == [1, 0, 0, 0, 0, 0], "The campaign begins with twenty gold, one built tower, and six available slots")
	for round_number: int in range(1, 4):
		if not await _run_round(round_number):
			_finish()
			return
	_check(game.state.phase == game.state.Phase.COMPLETE and game.state.completed_rounds == 3 and game.state.round_index == 3, "The third actual victory is the terminal three-round completion")
	_check(game.state.tower_levels == [2, 2, 1, 1, 0, 0] and game.state.gold == 10, "Campaign completion retains four paid towers, two upgrades, and ten gold after all actual loot settlements")
	_check(bow_damage_observed, "At least one real K bow shot applies actual projectile damage")
	_check(route_trace_ok and route_samples > 0, "Spawned later-round enemies remain on each bent route segment")
	_check(observed_enemy_kinds.size() == 3, "All three waves record actual enemy types including their distinct seal reinforcements")
	_check(feedback_counts.get("sword_hit", 0) > 0 and feedback_counts.get("bow", 0) > 0 and feedback_counts.get("build", 0) >= 5, "Real battle, three new buildings, and two upgrades emit routed feedback")
	await _capture("campaign_complete")
	_finish()

func _run_round(round_number: int) -> bool:
	if not _check(game.state.phase == game.state.Phase.PREPARATION and game.state.round_index == round_number, "The next real preparation has round index " + str(round_number)):
		return false
	await _capture("round_%d_preparation" % round_number)
	var preparation_gold: int = game.state.gold
	await create_timer(0.35).timeout
	_check(game.state.gold == preparation_gold, "Waiting in preparation cannot issue resource income in round " + str(round_number))
	_check(game.fortress.find_children("*", "AnimatedSprite2D", true, false).is_empty() and game.fortress.get_tree_visuals().size() == 3, "No lumber worker is present and all three decorative trees remain in round " + str(round_number))
	await _capture("round_%d_gold_ui" % round_number)
	var checkpoint: Dictionary = _checkpoint()
	await _click_button("UI_ENTER_DUNGEON")
	if not _check(game.state.phase == game.state.Phase.DUNGEON, "The actual enter button selects dungeon " + str(round_number)):
		return false
	var info: Dictionary = game.dungeon.get_level_info()
	_check(info["index"] == round_number - 1 and game.dungeon.ordinary_chest_position == info["ordinary_chest"], "The selected authored layout supplies dynamic interaction positions")
	_check(game.audio.get("current_track").ends_with("goblins_den.ogg"), "Dungeon phase selects the regular local music")
	await _capture("round_%d_dungeon" % round_number)
	var route: PackedVector2Array = game.dungeon.get_navigation_path(info["player_start"], info["ordinary_chest"])
	_check(route.size() >= 2, "The selected dungeon has a real navigation route from entrance to the ordinary chest")
	_check(game.dungeon.get_navigation_path(info["player_start"], info["key"]).is_empty(), "Closed guardian gates prevent navigation to the target key")
	if round_number == 1:
		await _walk_navigation_edge(route)
		if not await _real_bow_damage():
			return false
	await _interact_at(game.dungeon.ordinary_chest_position)
	_check(game.state.bag_gold == 25 and game.state.gold == checkpoint["gold"], "The ordinary chest changes only carried loot in round " + str(round_number))
	if round_number == 1:
		if not await _verify_pause_and_effects():
			return false
	await _interact_at(game.dungeon.sealed_chest_position)
	if not _check(game.modal_kind == "sealed", "Real E opens the sealed chest modal in round " + str(round_number)):
		return false
	await _capture("round_%d_sealed" % round_number)
	_check_seal_description(round_number)
	await _click_button("UI_SEALED_ACCEPT")
	_check(game.state.bag_gold == 45 and game.state.alarm, "The accepted seal adds twenty actual loot and alarm")
	if round_number == 2:
		if not await _fail_and_retry_second_round(checkpoint):
			return false
		await _click_button("UI_ENTER_DUNGEON")
		await _interact_at(game.dungeon.ordinary_chest_position)
		await _interact_at(game.dungeon.sealed_chest_position)
		await _click_button("UI_SEALED_ACCEPT")
	_observe_slime_children()
	var enemies: Array = game.dungeon.get("_enemies").duplicate()
	var priorities: Dictionary = {"skull": 0, "skeleton": 1, "armored_skeleton": 2, "slime": 3, "vampire": 4}
	enemies.sort_custom(func(a: CharacterBody2D, b: CharacterBody2D) -> bool: return priorities.get(a.monster_kind, 5) < priorities.get(b.monster_kind, 5))
	_check(enemies.size() == round_number + 2, "The selected dungeon actually instantiates its authored source-pack guardians")
	var dungeon_types: Dictionary = {}
	for value: Variant in enemies:
		if is_instance_valid(value):
			dungeon_types[value.monster_kind] = true
	_check(not dungeon_types.has("torch") and not dungeon_types.has("orc") and dungeon_types.has("slime") and dungeon_types.size() == round_number + 2, "The selected dungeon introduces a real additional monster type without goblins or Orcs")
	for value: Variant in enemies:
		if not is_instance_valid(value):
			_check(true, "An earlier real sweep already defeated this guardian")
			continue
		if not await _defeat_with_sword(value as CharacterBody2D):
			return false
	if not await _clear_slime_fragments():
		return false
	_check(game.dungeon.get("_middle_guardians") == 0 and game.dungeon.get("_reward_guard_defeated"), "Actual sword defeats unlock all reward gates in round " + str(round_number))
	var key_path: PackedVector2Array = game.dungeon.get_navigation_path(game.dungeon.stairs_position, game.dungeon.key_position)
	_check(not key_path.is_empty(), "Cleared guardian gates create an actual navigation route to the target key")
	await _interact_at(game.dungeon.key_position)
	_check(game.state.has_goal_key, "Real E takes the now-unlocked target key")
	await _interact_at(game.dungeon.stairs_position)
	if not _check(game.state.phase == game.state.Phase.SETTLEMENT and game.state.gold == checkpoint["gold"] + 45 and game.state.bag_gold == 0, "Real stairs deposit exactly the successful current-round loot"):
		return false
	await _capture("round_%d_settlement" % round_number)
	if round_number == 1:
		await _click_button("UI_BUILD_TOWER")
		await _click_button("UI_UPGRADE_TOWER")
		_check(game.state.tower_levels == [2, 1, 0, 0, 0, 0] and game.state.gold == 5, "Actual gold-only build and upgrade buttons buy the planned first-round defenses")
	elif round_number == 2:
		await _click_button("UI_UPGRADE_TOWER")
		_check(game.state.tower_levels == [2, 2, 0, 0, 0, 0] and game.state.gold == 15, "The second real upgrade keeps the earlier tower and uses only current-round gold")
	else:
		_check(game.state.tower_levels == [2, 2, 0, 0, 0, 0] and game.state.gold == 60, "The third round retains both paid tower upgrades and cumulative gold")
		await _click_button("UI_BUILD_TOWER", "TowerAction2")
		await _click_button("UI_BUILD_TOWER", "TowerAction3")
		_check(game.state.tower_levels == [2, 2, 1, 1, 0, 0] and game.state.gold == 10, "Real pointers build the newly available third and fourth towers for fifty gold")
	await _click_button("UI_START_DEFENSE")
	if not _check(game.state.phase == game.state.Phase.DEFENSE and game.fortress.round_index == round_number, "The real defense button starts the selected wave"):
		return false
	_check(game.audio.get("current_track").ends_with("goblins_dance.ogg"), "Defending switches to the real battle music")
	var expected_count: int = game.fortress.balance.wave_enemy_counts[round_number - 1] + 1
	_check(game.fortress.remaining_enemies() == expected_count, "The selected round includes its authored enemy count plus the seal alarm")
	var deadline: int = Time.get_ticks_msec() + 15000
	while game.fortress.arrows.is_empty() and game.state.phase == game.state.Phase.DEFENSE and Time.get_ticks_msec() < deadline:
		_observe_defense(round_number)
		await process_frame
	if not _check(not game.fortress.arrows.is_empty(), "A real tower fires an actual projectile before Rally"):
		return false
	_check_archer_layers()
	await _capture("round_%d_tower_closeup" % round_number)
	await _capture("round_%d_%s" % [round_number, "double_routes" if round_number > 1 else "defense"])
	await _click_button("UI_RALLY")
	_check(game.fortress.ledger.rally_used, "The actual Rally button activates the cooldown skill")
	var rally_reused: bool = false
	deadline = Time.get_ticks_msec() + 30000
	while game.state.phase == game.state.Phase.DEFENSE and Time.get_ticks_msec() < deadline:
		_observe_defense(round_number)
		if not rally_reused and game.fortress.ledger.rally_cooldown_left <= 0 and is_instance_valid(game.rally_button):
			game._process(0)
			await _click_button("UI_RALLY", "RallySkill")
			rally_reused = game.fortress.ledger.rally_cooldown_left > 0
			await _capture("round_%d_rally_reused" % round_number)
		await process_frame
	_check(rally_reused, "Cooldown completion permits a second actual Rally use in round " + str(round_number))
	var expected_phase: int = game.state.Phase.COMPLETE if round_number == 3 else game.state.Phase.PREPARATION
	if not _check(game.state.phase == expected_phase and game.state.castle_hp > 0, "Actual tower arrows defeat the complete wave in round " + str(round_number)):
		return false
	_check(game.state.completed_rounds == round_number, "Real victory advances completed-round progress exactly once")
	_check_wave_types(round_number, expected_count)
	if round_number > 1:
		var routes_seen: Dictionary = observed_routes.get(round_number, {})
		_check(routes_seen.has("upper") and routes_seen.has("lower"), "Both authored bent roads actually spawn moving enemies in round " + str(round_number))
	_check(game.audio.get("current_track").ends_with("goblins_den.ogg"), "Leaving defense restores the regular track")
	return true

func _checkpoint() -> Dictionary:
	return {"gold": game.state.gold, "castle_hp": game.state.castle_hp, "levels": game.state.tower_levels.duplicate(), "round": game.state.round_index, "completed": game.state.completed_rounds}

func _fail_and_retry_second_round(checkpoint: Dictionary) -> bool:
	var target: CharacterBody2D = game.dungeon.get("_enemies")[0]
	game.dungeon.player.position = _attack_position(target, 44.0)
	game.dungeon.player.velocity = Vector2.ZERO
	var deadline: int = Time.get_ticks_msec() + 14000
	while game.state.phase == game.state.Phase.DUNGEON and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _check(game.state.phase == game.state.Phase.FAILED and game.state.failure_reason == "player_defeated", "Actual second-round source-pack skeleton attacks kill the soldier and open failure"):
		return false
	await _capture("round_2_failed")
	await _click_button("UI_RETRY_ROUND")
	var restored: Dictionary = _checkpoint()
	_check(restored == checkpoint and game.player_health == 100, "Actual retry restores only the second-round checkpoint, preserving the first victory and tower upgrades")
	_check(game.state.completed_rounds == 1 and game.state.round_index == 2 and game.state.bag_gold == 0 and not game.state.alarm, "Retry discards failed carried loot and alarm without replaying round one")
	await create_timer(2.1).timeout
	_check(_checkpoint() == checkpoint and game.fortress.find_children("*", "AnimatedSprite2D", true, false).is_empty(), "Second-round retry cannot duplicate gold or restore the removed lumber worker")
	await _capture("round_2_retry")
	return game.state.phase == game.state.Phase.PREPARATION

func _walk_navigation_edge(path: PackedVector2Array) -> void:
	if path.size() < 2:
		return
	game.dungeon.player.position = path[0]
	var from: Vector2 = game.dungeon.player.position
	var direction: Vector2 = path[1] - from
	var action: String = ("fb_move_right" if direction.x > 0 else "fb_move_left") if absf(direction.x) > absf(direction.y) else ("fb_move_down" if direction.y > 0 else "fb_move_up")
	Input.action_press(action)
	var deadline: int = Time.get_ticks_msec() + 2000
	while game.dungeon.player.position.distance_to(path[1]) > 15.0 and Time.get_ticks_msec() < deadline:
		await physics_frame
	Input.action_release(action)
	await physics_frame
	_check(game.dungeon.player.position.distance_to(from) >= 16 and game.dungeon.player.position.distance_to(path[1]) < 22, "Real WASD movement follows an actual authored navigation edge")

func _attack_position(enemy: CharacterBody2D, distance: float) -> Vector2:
	for side: float in [1.0, -1.0]:
		var candidate: Vector2 = enemy.position + Vector2(side * distance, 0)
		if not game.dungeon.is_walkable(candidate) or not game.dungeon.is_walkable(candidate + Vector2(0, -24)):
			continue
		var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(game.dungeon.to_global(candidate) + Vector2(0, -32), enemy.global_position + Vector2(0, -32), 1)
		if game.dungeon.get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			return candidate
	return enemy.position - Vector2(distance, 0)

func _face_enemy(enemy: CharacterBody2D) -> void:
	await _tap_action("fb_move_right" if enemy.position.x > game.dungeon.player.position.x else "fb_move_left")

func _real_bow_damage() -> bool:
	var enemy: CharacterBody2D = game.dungeon.get("_enemies")[0]
	var initial: int = _total_enemy_health()
	for attempt: int in range(3):
		game.dungeon.player.position = _attack_position(enemy, 180.0)
		await _face_enemy(enemy)
		await _tap_action("fb_bow")
		if attempt == 0:
			await create_timer(0.45).timeout
			await _capture("bow_attack")
			await create_timer(0.55).timeout
		else:
			await create_timer(1.05).timeout
		if _total_enemy_health() <= initial - 15:
			bow_damage_observed = true
			break
	return _check(bow_damage_observed and feedback_counts.get("bow", 0) > 0, "Real K releases an arrow and applies at least fifteen damage to a source-pack skeleton")

func _total_enemy_health() -> int:
	var total: int = 0
	for value: Variant in game.dungeon.get("_enemies"):
		if not is_instance_valid(value):
			continue
		var enemy: CharacterBody2D = value as CharacterBody2D
		if is_instance_valid(enemy):
			total += enemy.health.current
	return total

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
		return _check(false, "A required authored guardian disappeared before combat")
	if enemy.monster_kind == "vampire":
		if not await _clear_slime_fragments():
			return false
		return await _defeat_two_life_vampire_with_bow(enemy)
	var initial: int = enemy.health.current
	for attempt: int in range(18):
		if not is_instance_valid(enemy) or not enemy.health.is_alive():
			if is_instance_valid(enemy) and enemy.revival.pending:
				_check(not game.dungeon._reward_guard_defeated, "The first vampire life cannot release the key")
				await _capture("round_%d_vampire_ashes" % game.state.round_index)
				game.dungeon.player.position = game.dungeon.stairs_position
				await create_timer(6.2).timeout
				if not _check(is_instance_valid(enemy) and enemy.health.is_alive() and enemy.revival.lives_left == 1, "The real vampire reassembles before combat resumes"):
					return false
			else:
				break
		if game.dungeon.get_player_health() <= 60:
			await _use_real_potion()
		var stance: Vector2 = _sword_position(enemy) - enemy.position
		game.dungeon.player.position = enemy.position + stance
		if game.dungeon.player.get("_hurt_left") > 0.0:
			await create_timer(0.45).timeout
		await _face_enemy(enemy)
		if not is_instance_valid(enemy) or not enemy.health.is_alive():
			break
		game.dungeon.player.position = enemy.position + stance
		await _tap_action("fb_sword")
		var dodge_action: String = ""
		for side: float in [1.0, -1.0]:
			var escape: Vector2 = game.dungeon.player.position + Vector2(0, side * 40.0)
			if game.dungeon.is_walkable(escape) and game.dungeon.is_walkable(escape + Vector2(0, -24)):
				dodge_action = "fb_move_down" if side > 0 else "fb_move_up"
				break
		if not dodge_action.is_empty():
			Input.action_press(dodge_action)
		await create_timer(0.48).timeout
		if not dodge_action.is_empty():
			Input.action_release(dodge_action)
		await create_timer(0.24).timeout
		if game.state.phase != game.state.Phase.DUNGEON:
			break
	return _check(not is_instance_valid(enemy) or (not enemy.health.is_alive() and not enemy.revival.pending), "Actual J sword actions finally defeat an authored guardian with initial HP " + str(initial))

func _defeat_two_life_vampire_with_bow(enemy: CharacterBody2D) -> bool:
	var revival_observed: bool = false
	for attempt: int in range(26):
		if not is_instance_valid(enemy):
			break
		if not enemy.health.is_alive():
			if not enemy.revival.pending:
				break
			_check(not game.dungeon._reward_guard_defeated, "The first vampire life cannot release the key")
			await _capture("round_%d_vampire_ashes" % game.state.round_index)
			game.dungeon.player.position = game.dungeon.stairs_position
			await create_timer(6.2).timeout
			if not _check(is_instance_valid(enemy) and enemy.health.current == 120 and enemy.revival.lives_left == 1, "The actual vampire returns with its full second life"):
				return false
			revival_observed = true
		var stance: Vector2 = Vector2.ZERO
		var stance_found: bool = false
		for distance: float in [340.0, 300.0, 260.0]:
			for offset_y: float in [16.0, 0.0, -16.0]:
				for side: float in [-1.0, 1.0]:
					var candidate: Vector2 = enemy.position + Vector2(side * distance, offset_y)
					if not game.dungeon.is_walkable(candidate) or not game.dungeon.is_walkable(candidate - Vector2(0, 26)):
						continue
					var origin: Vector2 = game.dungeon.to_global(candidate + Vector2(-side * 25.0, -32))
					var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin, Vector2(enemy.global_position.x, origin.y), 1)
					if game.dungeon.get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
						stance = candidate
						stance_found = true
						break
				if stance_found:
					break
			if stance_found:
				break
		if not _check(stance_found, "Ranged vampire stance fits the floor and its actual horizontal arrow clears walls"):
			return false
		game.dungeon.player.position = stance
		await _face_enemy(enemy)
		game.dungeon.player.position = stance
		await _tap_action("fb_bow")
		await create_timer(1.5).timeout
		print("VAMPIRE_BOW_FIXTURE " + JSON.stringify({"shot": attempt, "health": enemy.health.current if is_instance_valid(enemy) else 0, "player": game.dungeon.player.position, "enemy": enemy.position if is_instance_valid(enemy) else Vector2.ZERO}))
		if game.state.phase != game.state.Phase.DUNGEON:
			break
	return _check(revival_observed and (not is_instance_valid(enemy) or (not enemy.health.is_alive() and not enemy.revival.pending)), "Real K projectile attacks defeat both complete vampire lives from a clear ranged stance")


func _sword_position(enemy: CharacterBody2D) -> Vector2:
	var best: Vector2 = enemy.position - Vector2(92, 0)
	var score: float = -1.0
	for side: float in [1.0, -1.0]:
		for vertical: float in [0.0, 20.0, -20.0]:
			var candidate: Vector2 = enemy.position + Vector2(side * 92.0, vertical)
			if not game.dungeon.is_walkable(candidate + Vector2(0, -26)) or not game.dungeon.is_walkable(candidate + Vector2(side * 14, -12)):
				continue
			var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(game.dungeon.to_global(candidate) + Vector2(0, -12), enemy.global_position + Vector2(0, -12), 1)
			if not game.dungeon.get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
				continue
			var nearest: float = 10000.0
			for value: Variant in game.dungeon.get("_enemies"):
				if not is_instance_valid(value):
					continue
				var other: CharacterBody2D = value as CharacterBody2D
				if is_instance_valid(other) and other != enemy and other.health.is_alive():
					nearest = minf(nearest, candidate.distance_to(other.position))
			if nearest > score:
				score = nearest
				best = candidate
	return best

func _use_real_potion() -> void:
	var info: Dictionary = game.dungeon.get_level_info()
	var taken: Dictionary = game.dungeon.get("_potions_taken")
	for index: int in range(info["potions"].size()):
		if not taken.has(index):
			var before: int = game.dungeon.get_player_health()
			await _interact_at(info["potions"][index])
			_check(game.dungeon.get_player_health() > before, "Real E drinks an available potion to support the edge-of-range sword strategy")
			break

func _verify_pause_and_effects() -> bool:
	var music: AudioStreamPlayer = game.audio.get("music_player")
	_check(game.effects.get_child_count() > 0 and feedback_counts.get("chest", 0) > 0, "Actual chest interaction creates a transient original-atlas effect")
	await _click_button("UI_PAUSE")
	var position_before: float = music.get_playback_position()
	await create_timer(0.3, true).timeout
	_check(paused and music.stream_paused and absf(music.get_playback_position() - position_before) < 0.03, "The real pause button freezes the actual music playback cursor")
	await _click_button("UI_CONTROLS")
	await _capture("pause_controls")
	await _click_button("UI_BACK")
	_check(paused and game.modal_kind == "pause" and music.stream_paused, "Returning from controls preserves the paused game and music")
	await _click_button("UI_RESUME")
	_check(not paused and not music.stream_paused, "Actual resume restores game and audio playback")
	game.dungeon.player.position = game.dungeon.stairs_position
	await create_timer(1.3).timeout
	await process_frame
	return _check(game.effects.get_child_count() == 0, "Actual chest effects finish and free all sprite nodes after resume")

func _record_feedback(event: String, _at: Vector2) -> void:
	feedback_counts[event] = feedback_counts.get(event, 0) + 1

func _observe_defense(round_number: int) -> void:
	var seen: Dictionary = observed_routes.get(round_number, {})
	var kinds: Dictionary = observed_enemy_kinds.get(round_number, {})
	for id: int in game.fortress.enemies:
		var enemy: Dictionary = game.fortress.enemies[id]
		seen[enemy["route_id"]] = true
		kinds[id] = enemy["kind"]
		var points: PackedVector2Array = enemy["points"]
		var waypoint: int = enemy["waypoint"]
		if round_number > 1 and waypoint > 0 and waypoint < points.size():
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(enemy["pos"], points[waypoint - 1], points[waypoint])
			route_trace_ok = route_trace_ok and closest.distance_to(enemy["pos"]) < 1.5
			route_samples += 1
	observed_routes[round_number] = seen
	observed_enemy_kinds[round_number] = kinds

func _check_seal_description(round_number: int) -> void:
	var expected_kind: String = ["armored_skeleton", "vampire", "vampire"][round_number - 1]
	var definition: Dictionary = MonsterCatalog.get_definition(expected_kind)
	var expected: String = "1 " + TranslationServer.translate(definition["name_key"])
	var label: Label = game.modal.find_child("SealedDescription", true, false) as Label
	_check(WaveLedger.alarm_enemy_kind(round_number) == expected_kind and WaveLedger.alarm_enemy_count(round_number) == 1, "The wave contract defines the correct single seal reinforcement in round " + str(round_number))
	_check(label != null and label.text.contains(expected), "The actual confirmation text matches the promised reinforcement count and type in round " + str(round_number))

func _check_wave_types(round_number: int, expected_count: int) -> void:
	var kinds: Dictionary = observed_enemy_kinds.get(round_number, {})
	_check(kinds.size() == expected_count and game.fortress.next_id == expected_count + 1, "The running world spawned exactly the promised total in round " + str(round_number))
	_check(kinds.get(expected_count, "") == WaveLedger.alarm_enemy_kind(round_number), "The last spawned enemy matches the actual sealed-chest modal type in round " + str(round_number))
	var expected: Dictionary = {}
	var pattern: Array = WaveLedger.ROUND_PATTERNS[round_number - 1]
	for index: int in range(expected_count - 1):
		var kind: String = pattern[index % pattern.size()]
		expected[kind] = expected.get(kind, 0) + 1
	var alarm_kind: String = WaveLedger.alarm_enemy_kind(round_number)
	expected[alarm_kind] = expected.get(alarm_kind, 0) + 1
	var actual: Dictionary = {}
	for kind: String in kinds.values():
		actual[kind] = actual.get(kind, 0) + 1
	_check(actual == expected, "Every actual spawned normal and alarm monster matches the complete authored mixture in round " + str(round_number))

func _check_archer_layers() -> void:
	var bow_texture: Texture2D = game.fortress.textures.get("soldier_bow") as Texture2D
	if not _check(bow_texture != null and bow_texture.resource_path == "res://game/assets/tiny_rpg/soldier_bow.png" and bow_texture.get_size() == Vector2(900, 100), "Actual tower archers use the original nine-frame Tiny RPG Soldier bow PNG"):
		return
	var bow_image: Image = bow_texture.get_image()
	var release_visible: bool = false
	for slot: int in range(game.fortress.tower_levels.size()):
		if game.fortress.tower_levels[slot] == 0:
			continue
		var layers: Array = game.fortress.get_tower_layers(slot)
		if not _check(layers.size() == 3 and layers[0]["texture_key"] == "wood_tower" and layers[1]["texture_key"] == "soldier_bow" and layers[2]["texture_key"] == "wood_tower", "Actual tower drawing places the bow-holding Soldier behind the front battlement"):
			continue
		var source: Rect2 = layers[1]["source"]
		var destination: Rect2 = layers[1]["destination"]
		var frame: int = int(source.position.x / 100.0)
		_check(source.size == Vector2(100, 100) and source.position.y == 0 and frame in [0, 7, 8], "Actual Soldier atlas uses only neutral bow, release, or recovery original frames")
		_check(Vector2(absf(destination.size.x), destination.size.y) == Vector2(300, 300), "The actual 100-pixel Soldier canvas uses the requested three-times display scale")
		var used: Rect2i = bow_image.get_region(Rect2i(source)).get_used_rect()
		_check(used.end.y == 60, "The selected original Soldier frame has its measured opaque foot boundary at pixel sixty")
		var foot: Vector2 = destination.position + Vector2(150, 180)
		var tower_position: Vector2 = layers[0]["destination"].position
		var platform: Vector2 = tower_position + Vector2(128, 75)
		_check(foot.is_equal_approx(platform), "The actual Soldier foot boundary sits on the tower platform for either facing")
		var facing: float = -1.0 if destination.size.x < 0.0 else 1.0
		_check(game.fortress.get_archer_muzzle(slot).is_equal_approx(foot + Vector2(facing * 24, -30)), "Actual tower arrows start at the scaled original bow plane above the platform")
		var front: Rect2 = layers[2]["destination"]
		_check(front.position.y <= foot.y and destination.position.y + used.position.y * 3.0 < front.position.y, "The real foreground tower wall masks the larger Soldier feet while leaving the helmet visible")
		release_visible = release_visible or frame == 7
	_check(release_visible and not game.fortress.arrows.is_empty(), "An immediate actual tower projectile appears with the original Soldier release frame")
	for kind: String in MonsterCatalog.TYPES:
		var frames: SpriteFrames = MonsterCatalog.create_frames(kind)
		var valid: bool = true
		for action: String in MonsterCatalog.ACTIONS:
			valid = valid and frames.has_animation(action) and frames.get_frame_count(action) > 1
		_check(valid, "The running defense uses the complete source action profile: " + kind)
	if game.state.round_index > 1:
		var routes: Array = game.fortress.get_route_preview()
		_check(routes.size() == 2, "Later rounds use two actual route previews")
		for route: Dictionary in routes:
			var points: PackedVector2Array = route["points"]
			var bends: int = 0
			for index: int in range(1, points.size() - 1):
				if absf((points[index] - points[index - 1]).cross(points[index + 1] - points[index])) > 0.01:
					bends += 1
			_check(bends >= 2, "The authored " + route["id"] + " road has actual bends")

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

func _click_button(key: String, expected_name: String = "") -> bool:
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
	if not _check(button != null and not button.disabled, "An enabled actual button exists for " + key):
		return false
	var center: Vector2 = button.get_global_rect().get_center()
	var clicked: Array[bool] = [false]
	button.pressed.connect(func() -> void: clicked[0] = true, CONNECT_ONE_SHOT)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = center
		event.global_position = center
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame
	await process_frame
	return _check(clicked[0], "An actual pointer click emits the pressed signal for " + key)

func _find_button(node: Node, text: String, expected_name: String) -> Button:
	if node is Button:
		var button: Button = node as Button
		if button.text == text and (expected_name.is_empty() or button.name == expected_name):
			return button
	for child: Node in node.get_children():
		var found: Button = _find_button(child, text, expected_name)
		if found != null:
			return found
	return null

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
	_check_bounds(name)
	_check_translation_keys(name)
	if game.modal_kind == "controls":
		_check_controls_back_clear()
	if capture_dir.is_empty():
		return
	if DisplayServer.get_name() == "headless":
		_check(false, "Capture requires the actual graphical renderer")
		return
	if not _check(DirAccess.make_dir_recursive_absolute(capture_dir) == OK, "The screenshot directory is writable"):
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	_check(screenshot != null and not screenshot.is_empty() and screenshot.save_png(capture_dir.path_join(name + ".png")) == OK, "Saved actual viewport: " + name)

func _check_bounds(name: String) -> void:
	var viewport: Rect2 = root.get_visible_rect()
	if viewport.size.x < 1:
		viewport = Rect2(0, 0, 1280, 720)
	var overflow: PackedStringArray = []
	for node: Node in game.screen.find_children("*", "Control", true, false):
		var control: Control = node as Control
		if not control.is_visible_in_tree() or not (control is Label or control is Button):
			continue
		if not viewport.encloses(control.get_global_rect()):
			overflow.append(str(control.name) + " " + str(control.get_global_rect()))
	_check(overflow.is_empty(), "Actual visible Label and Button bounds fit the viewport: " + name)
	if not overflow.is_empty():
		print("CONTROL_OVERFLOW=" + JSON.stringify({"capture": name, "viewport": str(viewport), "controls": overflow}))

func _check_translation_keys(name: String) -> void:
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
	_check(unresolved.is_empty(), "Actual player text has no exposed translation keys: " + name)
	if not unresolved.is_empty():
		print("UNTRANSLATED_KEYS=" + JSON.stringify({"capture": name, "text": unresolved}))

func _check_controls_back_clear() -> void:
	var back: Button = _find_button(game.modal, TranslationServer.translate("UI_BACK"), "")
	if not _check(back != null, "The real controls modal contains its Back button"):
		return
	var overlap: PackedStringArray = []
	for node: Node in game.modal.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label.get_global_rect().intersects(back.get_global_rect()):
			overlap.append(label.text)
	_check(overlap.is_empty(), "Actual controls labels do not cover the Back button")
	if not overlap.is_empty():
		print("CONTROLS_OVERLAP=" + JSON.stringify(overlap))

func _finish() -> void:
	for action: String in ["fb_move_left", "fb_move_right", "fb_move_up", "fb_move_down", "fb_sword", "fb_bow", "fb_interact"]:
		Input.action_release(action)
	paused = false
	Engine.time_scale = 1
	var report: Dictionary = {"validation": "scripted campaign integration; player repositioning; real GUI/input/combat/economy/projectiles", "checks": checks, "failures": failures, "elapsed_real_seconds": (Time.get_ticks_msec() - start_ticks) / 1000.0, "test_time_scale": 4, "bow_damage_observed": bow_damage_observed, "observed_routes": observed_routes, "observed_enemy_kinds": observed_enemy_kinds, "route_trace_ok": route_trace_ok, "route_samples": route_samples, "feedback_counts": feedback_counts, "completed_rounds": game.state.completed_rounds, "round_index": game.state.round_index, "final_gold": game.state.gold}
	print("CAMPAIGN_FLOW_RESULT=" + JSON.stringify(report))
	if not capture_dir.is_empty():
		var file: FileAccess = FileAccess.open(capture_dir.path_join("campaign-result.json"), FileAccess.WRITE)
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
