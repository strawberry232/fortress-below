extends Node2D

signal impact_requested(at: Vector2)

const FRAME_SIZE: int = 64
const BLUE_ROW: int = 2
const HIT_RADIUS: float = 12.0
const DISPLAY_SCALE: float = 1.2
const BOLT_TEXTURE: Texture2D = preload("res://game/assets/fx/skull_bolt.png")
const IMPACT_TEXTURE: Texture2D = preload("res://game/assets/fx/skull_impact.png")

var velocity: Vector2 = Vector2(190.0, 0.0)
var damage: int = 10
var attack_id: String = ""
var source_body: PhysicsBody2D
var consumed: bool = false
var lifetime: float = 3.5
var _sprite: AnimatedSprite2D

static var _flight_frames: SpriteFrames
static var _impact_frames: SpriteFrames


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if attack_id.is_empty():
		attack_id = "skull-bolt-%d" % get_instance_id()
	if _flight_frames == null:
		_flight_frames = _make_frames(BOLT_TEXTURE, "flight", 1, 4, true, 12.0)
	if _impact_frames == null:
		_impact_frames = _make_frames(IMPACT_TEXTURE, "impact", 0, 8, false, 20.0)
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "BoltSprite"
	_sprite.sprite_frames = _flight_frames
	_sprite.scale = Vector2.ONE * DISPLAY_SCALE
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_update_facing()
	_sprite.play("flight")


static func _make_frames(texture: Texture2D, animation: String, first_frame: int, frame_count: int, loops: bool, fps: float) -> SpriteFrames:
	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation(animation)
	frames.set_animation_loop(animation, loops)
	frames.set_animation_speed(animation, fps)
	for index: int in range(first_frame, first_frame + frame_count):
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(index * FRAME_SIZE, BLUE_ROW * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
		frames.add_frame(animation, atlas)
	return frames


func _physics_process(delta: float) -> void:
	if consumed or delta <= 0.0 or not is_inside_tree():
		return
	lifetime = maxf(0.0, lifetime - delta)
	if lifetime <= 0.0:
		_consume(false)
		return
	_update_facing()
	if velocity.is_zero_approx():
		return
	var movement: Vector2 = velocity * delta
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = HIT_RADIUS
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 3
	query.transform = Transform2D(0.0, global_position)
	if is_instance_valid(source_body):
		query.exclude = [source_body.get_rid()]
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var result: Dictionary = space.get_rest_info(query)
	if not result.is_empty():
		_apply_collision(result)
		return
	query.motion = movement
	var fractions: PackedFloat32Array = space.cast_motion(query)
	if fractions.size() < 2 or fractions[0] >= 1.0:
		global_position += movement
		return
	var origin: Vector2 = global_position
	global_position += movement * fractions[0]
	query.motion = Vector2.ZERO
	query.transform.origin = origin + movement * fractions[1] + movement.normalized() * 0.1
	result = space.get_rest_info(query)
	_apply_collision(result)


func _apply_collision(result: Dictionary) -> void:
	var receiver: Object = instance_from_id(result.get("collider_id", 0))
	if is_instance_valid(receiver) and receiver.has_method("receive_damage"):
		receiver.call("receive_damage", damage, attack_id)
	_consume(true)


func _update_facing() -> void:
	if not is_instance_valid(_sprite):
		return
	var direction: Vector2 = velocity.normalized() if not velocity.is_zero_approx() else Vector2.RIGHT
	_sprite.rotation = direction.angle()
	_sprite.position = -direction * 18.0


func _consume(show_impact: bool) -> void:
	if consumed:
		return
	consumed = true
	set_physics_process(false)
	if is_instance_valid(_sprite):
		_sprite.visible = false
	if show_impact:
		_spawn_impact()
		impact_requested.emit(global_position)
	queue_free()


func _spawn_impact() -> void:
	var parent: Node = get_parent()
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var impact: AnimatedSprite2D = AnimatedSprite2D.new()
	impact.name = "SkullImpact"
	impact.sprite_frames = _impact_frames
	impact.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	impact.process_mode = Node.PROCESS_MODE_INHERIT
	impact.scale = Vector2.ONE * DISPLAY_SCALE
	impact.z_index = 50
	parent.add_child(impact)
	impact.global_position = global_position
	impact.global_rotation = velocity.angle()
	impact.animation_finished.connect(impact.queue_free, CONNECT_ONE_SHOT)
	impact.play("impact")
