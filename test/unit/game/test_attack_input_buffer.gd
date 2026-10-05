extends "res://addons/gut/test.gd"

const PLAYER: Script = preload("res://game/scripts/combat/fortress_player.gd")

func before_each() -> void:
	get_tree().paused = false
	for action: String in ["fb_move_left", "fb_move_right", "fb_move_up", "fb_move_down", "fb_sword", "fb_bow"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		Input.action_release(action)

func after_each() -> void:
	get_tree().paused = false
	for action: String in ["fb_sword", "fb_bow"]:
		Input.action_release(action)

func _player() -> Node:
	var player: Node = PLAYER.new()
	add_child_autofree(player)
	player.set_physics_process(false)
	return player

func _supported(player: Node) -> bool:
	assert_true(player.has_method("queue_attack"), "Busy attack input has a bounded buffer")
	return player.has_method("queue_attack")

func test_late_input_starts_once_after_recovery_without_changing_hit_windows() -> void:
	var player: Node = _player()
	if not _supported(player):
		return
	assert_true(player.queue_attack("attack"))
	player._physics_process(0.49)
	assert_true(player.queue_attack("bow", -1))
	player._physics_process(0.11)
	player._physics_process(0.01)
	assert_eq(player._attack, "bow")
	assert_eq(player.facing, -1)
	assert_eq(player._attack_serial, 2)
	watch_signals(player)
	player._physics_process(0.65)
	assert_signal_emit_count(player, "shot_requested", 0, "Bow release remains at the original 0.7 seconds")
	player._physics_process(0.06)
	assert_signal_emit_count(player, "shot_requested", 1)
	player._physics_process(0.3)
	player._physics_process(0.2)
	assert_eq(player._attack_serial, 2, "A single queued press never repeats itself")

func test_early_input_expires_and_invalid_inputs_do_not_replace_the_queue() -> void:
	var player: Node = _player()
	if not _supported(player):
		return
	player.queue_attack("attack")
	player.queue_attack("bow")
	assert_false(player.queue_attack("invalid"))
	player._physics_process(0.5)
	player._physics_process(0.2)
	assert_eq(player._attack_serial, 1)
	assert_eq(player._attack, "")
	assert_false(player.queue_attack("bow", 4), "Only left, right, or inherited facing is valid")

func test_damage_pause_and_world_deactivation_discard_pending_input() -> void:
	var player: Node = _player()
	if not _supported(player):
		return
	player.queue_attack("attack")
	player._physics_process(0.5)
	player.queue_attack("bow")
	assert_true(player.receive_damage(10, "buffer-cancel"))
	player._physics_process(0.5)
	assert_eq(player._attack_serial, 1)
	assert_eq(player._attack, "")
	player.queue_attack("attack")
	player._physics_process(0.5)
	player.queue_attack("bow")
	get_tree().paused = true
	get_tree().paused = false
	player._physics_process(0.11)
	player._physics_process(0.01)
	assert_eq(player._attack_serial, 2)
	player.queue_attack("attack")
	player._physics_process(0.5)
	player.queue_attack("bow")
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player._physics_process(0.11)
	player._physics_process(0.01)
	assert_eq(player._attack_serial, 3)

func test_dead_or_paused_player_rejects_requests() -> void:
	var player: Node = _player()
	if not _supported(player):
		return
	get_tree().paused = true
	assert_false(player.queue_attack("attack"))
	get_tree().paused = false
	player.receive_damage(1000, "buffer-death")
	assert_false(player.queue_attack("bow"))
