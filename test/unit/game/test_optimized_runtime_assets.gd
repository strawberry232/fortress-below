extends "res://addons/gut/test.gd"

const AUDIO: Script = preload("res://game/scripts/ui/demo_audio.gd")
const PIXEL_FONT: Script = preload("res://game/scripts/ui/pixel_font.gd")


func test_runtime_music_uses_compact_looping_vorbis_without_changing_duration() -> void:
	assert_true(AUDIO.REGULAR_PATH.ends_with(".ogg"))
	assert_true(AUDIO.BATTLE_PATH.ends_with(".ogg"))
	for path: String in [AUDIO.REGULAR_PATH, AUDIO.BATTLE_PATH]:
		var sound: Node = AUDIO.new()
		var compact: AudioStream = sound.call("_looping_music", path)
		assert_true(compact is AudioStreamOggVorbis, "Long music uses the compressed Vorbis stream")
		if compact is AudioStreamOggVorbis:
			assert_true(compact.loop)
			assert_eq(compact.loop_offset, 0.0)
			var original: AudioStream = load(path.replace("/optimized/", "/").replace(".ogg", ".wav"))
			assert_almost_eq(compact.get_length(), original.get_length(), 0.005)
		sound.free()


func test_loop_adapter_supports_original_wav_without_mutating_the_cached_source() -> void:
	var sound: Node = AUDIO.new()
	var path: String = "res://game/assets/audio/sfx/sword.wav"
	var source: AudioStreamWAV = load(path)
	var original_mode: int = source.loop_mode
	var original_end: int = source.loop_end
	var loop: AudioStream = sound.call("_looping_music", path)
	assert_true(loop is AudioStreamWAV)
	assert_ne(loop, source)
	if loop is AudioStreamWAV:
		assert_eq(loop.loop_mode, AudioStreamWAV.LOOP_FORWARD)
		assert_gt(loop.loop_end, loop.loop_begin)
	assert_eq(source.loop_mode, original_mode)
	assert_eq(source.loop_end, original_end)
	assert_null(sound.call("_looping_music", "res://missing_music.ogg"))
	assert_null(sound.call("_looping_music", "res://game/assets/icons/game_icon.png"))
	sound.free()


func test_compressed_tracks_wrap_at_the_original_loop_boundary() -> void:
	var sound: Node = AUDIO.new()
	add_child_autofree(sound)
	for phase: String in ["title", "defense"]:
		assert_true(sound.set_phase(phase))
		var music: AudioStreamPlayer = sound.get("music_player")
		music.seek(music.stream.get_length() - 0.05)
		await get_tree().create_timer(0.25).timeout
		assert_true(music.playing, "The stream remains active across its end")
		assert_lt(music.get_playback_position(), 0.5, "Vorbis wraps to the start without an extra silent tail")


func test_subset_font_preserves_the_original_pixel_metrics_and_glyph_shapes() -> void:
	var font: Font = PIXEL_FONT.create()
	var source: FontFile = load(PIXEL_FONT.SOURCE_PATH).duplicate()
	source.allow_system_fallback = false
	source.fallbacks = []
	source.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	source.hinting = TextServer.HINTING_NONE
	source.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	source.oversampling = 1.0
	assert_lt(font.data.size(), source.data.size() / 5, "Only runtime glyphs are distributed")
	for codepoint: int in [0x9AB7, 0x9AC5, 0x5438, 0x8840, 0x9B3C, 0x91D1, 0x5E01, 0x0030, 0x0041, 0xFF01]:
		assert_true(font.has_char(codepoint))
		var character: String = String.chr(codepoint)
		for size: int in [12, 24, 36, 60]:
			assert_eq(font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, size), source.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, size))
	assert_eq(font.get_height(24), source.get_height(24))
