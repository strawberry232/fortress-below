extends Node2D
class_name PlayerFx

const FRAME_SIZE: int = 64
const TEXTURES: Dictionary = {
	"hit": preload("res://game/assets/fx/hit.png"),
	"arrow_hit": preload("res://game/assets/fx/arrow_hit.png"),
	"heal": preload("res://game/assets/fx/heal.png"),
	"burst": preload("res://game/assets/fx/burst.png"),
	"firepower": preload("res://game/assets/fx/burst.png")
}
const ALIASES: Dictionary = {
	"sword": "hit", "sword_hit": "hit", "player_hurt": "hit",
	"enemy_hurt": "hit", "enemy_hit": "hit", "hit": "hit",
	"bow": "arrow_hit", "tower_shot": "arrow_hit", "arrow_hit": "arrow_hit",
	"heal": "heal", "chest": "heal", "key": "heal", "gate": "heal",
	"rally": "firepower", "firepower": "firepower",
	"castle_hit": "burst", "enemy_death": "burst", "player_death": "burst",
	"build": "burst", "supply": "burst", "burst": "burst"
}

var max_effects: int = 24
var _frames: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for kind: String in TEXTURES:
		_frames[kind] = _make_frames(kind)

func _make_frames(kind: String) -> SpriteFrames:
	var texture: Texture2D = TEXTURES[kind] as Texture2D
	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("effect")
	frames.set_animation_loop("effect", false)
	frames.set_animation_speed("effect", 20.0)
	var row: int = 0 if kind == "firepower" else 6 if kind == "heal" else 5
	var count: int = texture.get_width() / FRAME_SIZE
	for index: int in range(count):
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(index * FRAME_SIZE, row * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
		frames.add_frame("effect", atlas)
	return frames

func spawn_effect(kind: String, at: Vector2) -> AnimatedSprite2D:
	if not is_inside_tree() or get_tree().paused or get_child_count() >= max_effects:
		return null
	var source_kind: String = ALIASES.get(kind, "")
	var frames: SpriteFrames = _frames.get(source_kind) as SpriteFrames
	if frames == null:
		return null
	var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = 50
	if source_kind == "firepower":
		sprite.scale = Vector2.ONE
	elif source_kind == "burst":
		sprite.scale = Vector2.ONE * (1.4 if kind == "castle_hit" else 0.8)
	elif source_kind == "heal":
		sprite.scale = Vector2.ONE * (0.7 if kind in ["key", "chest", "gate"] else 1.0)
	else:
		sprite.scale = Vector2.ONE * 0.8
	add_child(sprite)
	sprite.global_position = at
	sprite.animation_finished.connect(sprite.queue_free, CONNECT_ONE_SHOT)
	sprite.play("effect")
	return sprite

func clear() -> void:
	for child: Node in get_children():
		child.queue_free()
