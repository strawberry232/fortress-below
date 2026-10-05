extends Node

const VOICE_COUNT: int = 8
const REGULAR_PATH: String = "res://game/assets/audio/music/optimized/goblins_den.ogg"
const BATTLE_PATH: String = "res://game/assets/audio/music/optimized/goblins_dance.ogg"

var music_player: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var music_volume_db: float = -22.0
var sfx_volume_db: float = -13.0
var current_track: String = ""
var event_paths: Dictionary = {
	"sword": "res://game/assets/audio/sfx/sword.wav",
	"sword_hit": "res://game/assets/audio/sfx/sword_hit.wav",
	"bow": "res://game/assets/audio/sfx/bow.wav",
	"player_hurt": "res://game/assets/audio/sfx/player_hurt.wav",
	"player_death": "res://game/assets/audio/sfx/player_death.wav",
	"enemy_hurt": "res://game/assets/audio/sfx/enemy_hurt.wav",
	"enemy_death": "res://game/assets/audio/sfx/enemy_death.wav",
	"chest": "res://game/assets/audio/sfx/chest.wav",
	"key": "res://game/assets/audio/sfx/chest.wav",
	"heal": "res://game/assets/audio/sfx/heal.wav",
	"gate": "res://game/assets/audio/sfx/gate.mp3",
	"tower_shot": "res://game/assets/audio/sfx/bow.wav",
	"enemy_hit": "res://game/assets/audio/sfx/sword_hit.wav",
	"castle_hit": "res://game/assets/audio/sfx/sword_hit.wav",
	"supply": "res://game/assets/audio/sfx/supply.wav",
	"build": "res://game/assets/audio/sfx/supply.wav",
	"rally": "res://game/assets/audio/sfx/rally.wav"
}
var _event_streams: Dictionary = {}
var _music_streams: Dictionary = {}
var _muted: bool = false
var _frozen: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	music_player = AudioStreamPlayer.new()
	music_player.name = "Music"
	music_player.volume_db = music_volume_db
	add_child(music_player)
	for index: int in range(VOICE_COUNT):
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.name = "FeedbackVoice" + str(index)
		voice.volume_db = sfx_volume_db
		add_child(voice)
		voices.append(voice)
	for event: String in event_paths:
		_event_streams[event] = load(event_paths[event]) as AudioStream
	_music_streams[REGULAR_PATH] = _looping_music(REGULAR_PATH)
	_music_streams[BATTLE_PATH] = _looping_music(BATTLE_PATH)

func _looping_music(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var source: AudioStream = load(path) as AudioStream
	if source == null:
		return null
	if source is AudioStreamOggVorbis:
		var vorbis: AudioStreamOggVorbis = source.duplicate() as AudioStreamOggVorbis
		vorbis.loop = true
		vorbis.loop_offset = 0.0
		return vorbis
	if source is AudioStreamWAV:
		var wave: AudioStreamWAV = source.duplicate() as AudioStreamWAV
		wave.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wave.loop_begin = 0
		wave.loop_end = int(round(wave.get_length() * wave.mix_rate))
		return wave
	return null

func play_event(event: String) -> bool:
	if _muted or _frozen or not is_inside_tree() or get_tree().paused:
		return false
	var stream: AudioStream = _event_streams.get(event) as AudioStream
	if stream == null:
		return false
	for voice: AudioStreamPlayer in voices:
		if not voice.playing:
			voice.stream = stream
			voice.volume_db = sfx_volume_db
			voice.stream_paused = false
			voice.play()
			return true
	return false

func set_phase(phase_name: String) -> bool:
	if not is_instance_valid(music_player):
		return false
	var path: String = ""
	match phase_name.to_lower():
		"title", "menu", "preparation", "dungeon", "settlement", "complete", "failed":
			path = REGULAR_PATH
		"defense":
			path = BATTLE_PATH
		_:
			return false
	if current_track == path and music_player.playing:
		return true
	var stream: AudioStream = _music_streams.get(path) as AudioStream
	if stream == null:
		return false
	current_track = path
	music_player.stream = stream
	music_player.volume_db = -80.0 if _muted else music_volume_db
	music_player.play()
	music_player.stream_paused = _frozen or get_tree().paused
	return true

func set_muted(muted: bool) -> void:
	_muted = muted
	if is_instance_valid(music_player):
		music_player.volume_db = -80.0 if muted else music_volume_db
	if muted:
		for voice: AudioStreamPlayer in voices:
			voice.stop()

func get_muted() -> bool:
	return _muted

func stop_all() -> void:
	if is_instance_valid(music_player):
		music_player.stop()
		music_player.stream = null
	for voice: AudioStreamPlayer in voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	current_track = ""

func _exit_tree() -> void:
	stop_all()
	_event_streams.clear()
	_music_streams.clear()

func ping(_frequency: float = 660.0) -> void:
	play_event("chest")

func _notification(what: int) -> void:
	if what == Node.NOTIFICATION_PAUSED:
		_set_frozen(true)
	elif what == Node.NOTIFICATION_UNPAUSED:
		_set_frozen(false)

func _set_frozen(frozen: bool) -> void:
	_frozen = frozen
	if is_instance_valid(music_player):
		music_player.stream_paused = frozen
	for voice: AudioStreamPlayer in voices:
		voice.stream_paused = frozen
