extends "res://addons/gut/test.gd"

const AudioScript = preload("res://game/scripts/ui/demo_audio.gd")

func after_each() -> void:
	get_tree().paused = false
	await get_tree().process_frame

func _create_audio() -> Node:
	var sound: Node = AudioScript.new()
	add_child_autofree(sound)
	return sound

func _require_api(sound: Node) -> bool:
	var ready: bool = sound.has_method("play_event") and sound.has_method("set_phase") and sound.has_method("set_muted")
	assert_true(ready, "Audio supports named real-asset feedback, phase music, and mute")
	return ready

func _playback_reference(player: AudioStreamPlayer) -> WeakRef:
	var playback: AudioStreamPlayback = player.get_stream_playback()
	return weakref(playback)

func test_real_music_loops_and_matching_phases_keep_the_same_playback() -> void:
	var sound: Node = _create_audio()
	if not _require_api(sound):
		return
	sound.set_phase("title")
	var music: AudioStreamPlayer = sound.get("music_player")
	var regular: AudioStreamOggVorbis = music.stream as AudioStreamOggVorbis
	assert_not_null(regular, "The music player loads the compact derivative of the adopted music")
	if regular == null:
		return
	assert_gt(regular.get_length(), 50.0)
	assert_true(regular.loop)
	assert_eq(regular.loop_offset, 0.0)
	assert_true(music.playing)
	await get_tree().create_timer(0.15).timeout
	var position_before: float = music.get_playback_position()
	sound.set_phase("dungeon")
	assert_same(music.stream, regular, "Entering the dungeon keeps the regular track instance")
	assert_gte(music.get_playback_position(), position_before, "Matching phases preserve the playback cursor")
	sound.set_phase("defense")
	var battle: AudioStreamOggVorbis = music.stream as AudioStreamOggVorbis
	assert_ne(battle, regular)
	assert_gt(battle.get_length(), 50.0)
	assert_true(battle.loop)
	sound.set_phase("defense")
	assert_same(music.stream, battle, "Repeated phase updates do not restart the track")
	var playing_before: bool = music.playing
	assert_false(sound.set_phase("unknown_phase"))
	assert_same(music.stream, battle)
	assert_eq(music.playing, playing_before)

func test_overlapping_feedback_uses_separate_voices_and_saturation_does_not_steal() -> void:
	var sound: Node = _create_audio()
	if not _require_api(sound):
		return
	assert_true(sound.play_event("sword"))
	assert_true(sound.play_event("sword_hit"))
	var voices: Array = sound.get("voices")
	var first: AudioStreamPlayer = voices[0]
	var second: AudioStreamPlayer = voices[1]
	assert_true(first.playing and second.playing)
	assert_ne(first.stream, second.stream)
	assert_true(first.stream.resource_path.ends_with("sword.wav"), "The sword sound uses a local WAV, not a synthesized tone")
	for index: int in range(voices.size() - 2):
		assert_true(sound.play_event("sword"))
	var original: AudioStream = first.stream
	assert_false(sound.play_event("enemy_death"), "A full voice pool declines a new event without replacing an active sound")
	assert_same(first.stream, original)
	assert_false(sound.play_event("unknown_event"))
	assert_eq(sound.get_child_count(), voices.size() + 1, "Feedback never allocates extra player nodes")

func test_mute_preserves_music_phase_and_suppresses_new_effects() -> void:
	var sound: Node = _create_audio()
	if not _require_api(sound):
		return
	sound.set_phase("preparation")
	var music: AudioStreamPlayer = sound.get("music_player")
	var track: AudioStream = music.stream
	var volume_before: float = music.volume_db
	assert_true(sound.play_event("chest"))
	sound.set_muted(true)
	assert_true(sound.get_muted())
	assert_same(music.stream, track)
	assert_true(music.playing, "Muting keeps the phase track in place")
	assert_lte(music.volume_db, -70.0)
	assert_false(sound.play_event("sword"))
	for value: Variant in sound.get("voices"):
		var voice: AudioStreamPlayer = value
		assert_false(voice.playing, "Muting stops all existing effects")
	sound.set_muted(false)
	assert_false(sound.get_muted())
	assert_eq(music.volume_db, volume_before)
	assert_same(music.stream, track)
	assert_true(sound.play_event("sword"))

func test_pause_freezes_streams_and_unpause_restores_them() -> void:
	var sound: Node = _create_audio()
	if not _require_api(sound):
		return
	sound.set_phase("dungeon")
	sound.play_event("sword")
	var music: AudioStreamPlayer = sound.get("music_player")
	var voice: AudioStreamPlayer = sound.get("voices")[0]
	get_tree().paused = true
	await get_tree().process_frame
	assert_true(music.stream_paused)
	assert_true(voice.stream_paused)
	var position_before: float = music.get_playback_position()
	await get_tree().create_timer(0.15, true).timeout
	assert_almost_eq(music.get_playback_position(), position_before, 0.025, "The paused music cursor stays frozen")
	assert_false(sound.play_event("sword_hit"))
	get_tree().paused = false
	await get_tree().process_frame
	assert_false(music.stream_paused)
	assert_false(voice.stream_paused)

func test_every_world_event_has_an_available_local_stream() -> void:
	var sound: Node = _create_audio()
	if not _require_api(sound):
		return
	var events: Array[String] = ["sword", "sword_hit", "bow", "player_hurt", "player_death", "enemy_hurt", "enemy_death", "chest", "key", "heal", "gate", "tower_shot", "enemy_hit", "castle_hit", "supply", "build", "rally"]
	var mapping: Dictionary = sound.get("event_paths")
	for event: String in events:
		assert_true(mapping.has(event), "World event has a sound mapping: " + event)
		if mapping.has(event):
			var stream: AudioStream = load(mapping[event])
			assert_not_null(stream)
			if stream != null:
				assert_gt(stream.get_length(), 0.0)
	assert_lt(sound.get("music_volume_db"), sound.get("sfx_volume_db"), "Music remains quieter than feedback")
	sound.ping(880.0)
	assert_true(sound.get("voices")[0].playing, "The old ping API uses a local sample")

func test_stop_all_releases_active_player_streams_and_is_idempotent() -> void:
	var sound: Node = _create_audio()
	assert_true(sound.has_method("stop_all"))
	if not sound.has_method("stop_all"):
		return
	assert_true(sound.set_phase("title"))
	assert_true(sound.play_event("sword"))
	assert_true(sound.play_event("rally"))
	var music: AudioStreamPlayer = sound.get("music_player")
	var playback: WeakRef = _playback_reference(music)
	sound.call("stop_all")
	sound.call("stop_all")
	assert_false(music.playing)
	assert_null(music.stream, "Stopping must detach the looping music from its player")
	assert_eq(sound.get("current_track"), "")
	for value: Variant in sound.get("voices"):
		var voice: AudioStreamPlayer = value
		assert_false(voice.playing)
		assert_null(voice.stream, "Stopped feedback players cannot retain an assigned stream")
	# Audio retirement runs on the mixer thread; wait for its actual state.
	var retirement_deadline: int = Time.get_ticks_msec() + 2000
	while playback.get_ref() != null and Time.get_ticks_msec() < retirement_deadline:
		await get_tree().create_timer(0.02, true, false, true).timeout
	assert_null(playback.get_ref(), "The audio server retires the detached looping playback asynchronously")
	assert_true(sound.set_phase("title"), "Stopping does not discard the reusable phase configuration")
	assert_true(music.playing)
	assert_true(sound.play_event("sword"))

func test_stop_all_while_paused_does_not_restart_streams_on_resume() -> void:
	var sound: Node = _create_audio()
	assert_true(sound.has_method("stop_all"))
	if not sound.has_method("stop_all"):
		return
	sound.set_phase("defense")
	sound.play_event("bow")
	get_tree().paused = true
	await get_tree().process_frame
	sound.call("stop_all")
	get_tree().paused = false
	await get_tree().process_frame
	var music: AudioStreamPlayer = sound.get("music_player")
	assert_false(music.playing)
	assert_null(music.stream)
	assert_eq(sound.get("current_track"), "")
	for value: Variant in sound.get("voices"):
		var voice: AudioStreamPlayer = value
		assert_false(voice.playing)
		assert_null(voice.stream)

func test_exit_tree_detaches_music_and_feedback_streams() -> void:
	var sound: Node = _create_audio()
	sound.set_phase("title")
	sound.play_event("sword")
	var music: AudioStreamPlayer = sound.get("music_player")
	var voice: AudioStreamPlayer = sound.get("voices")[0]
	remove_child(sound)
	assert_null(music.stream, "Removing audio from the tree releases the looping stream")
	assert_null(voice.stream)
	assert_eq(sound.get("current_track"), "")
