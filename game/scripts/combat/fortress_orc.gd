extends CharacterBody2D
class_name FortressOrc

signal defeated
signal feedback_requested(event: String, at: Vector2)

const HEALTH_SCRIPT: Script = preload("res://game/scripts/combat/fortress_health.gd")
const ANIMATION_SCRIPT: Script = preload("res://game/scripts/combat/fortress_animation_library.gd")

var target: Node2D
var chase_point_provider: Callable
var health: RefCounted = HEALTH_SCRIPT.new()
var speed: float = 65.0
var maximum_health: int = 40
var facing: int = 1
var _sprite: AnimatedSprite2D
var _hurt_area: Area2D
var _attack_elapsed: float = -1.0
var _attack_serial: int = 0
var _attack_applied: bool = false
var _cooldown: float = 0.0
var _hurt_left: float = 0.0
var _death_left: float = 1.1


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 12.0
	shape_node.shape = shape
	shape_node.position = Vector2(0.0, -12.0)
	add_child(shape_node)
	_hurt_area = Area2D.new()
	_hurt_area.collision_layer = 4
	_hurt_area.collision_mask = 0
	var hurt_shape_node: CollisionShape2D = CollisionShape2D.new()
	var hurt_shape: RectangleShape2D = RectangleShape2D.new()
	hurt_shape.size = Vector2(38.0, 52.0)
	hurt_shape_node.shape = hurt_shape
	hurt_shape_node.position = Vector2(0.0, -27.0)
	_hurt_area.add_child(hurt_shape_node)
	add_child(_hurt_area)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = ANIMATION_SCRIPT.character_frames("tiny_rpg", "orc", Vector2i(100, 100), {
		"idle": ["idle", 6, 10.0], "walk": ["walk", 8, 10.0],
		"attack": ["attack", 6, 10.0], "hurt": ["hurt", 4, 10.0], "death": ["death", 4, 10.0, [1.0, 1.0, 1.0, 6.0]]
	})
	_sprite.scale = Vector2(3.0, 3.0)
	_sprite.position = Vector2(0.0, -30.0)
	add_child(_sprite)
	_sprite.play("idle")
	health.protection_duration = 0.1
	health.died.connect(_on_died)
	health.reset(maximum_health)


func _physics_process(delta: float) -> void:
	health.tick(delta)
	_cooldown = maxf(0.0, _cooldown - delta)
	_hurt_left = maxf(0.0, _hurt_left - delta)
	if not health.is_alive():
		_death_left -= delta
		if _death_left <= 0.0:
			queue_free()
		return
	if not is_instance_valid(target) or not target.health.is_alive():
		return
	if _hurt_left > 0.0:
		velocity = Vector2.ZERO
		_sprite.play("hurt")
		_sprite.modulate = Color(1.0, 0.5, 0.5)
		queue_redraw()
		return
	var to_player: Vector2 = target.global_position - global_position
	if _attack_elapsed >= 0.0:
		_attack_elapsed += delta
		velocity = Vector2.ZERO
		if _attack_elapsed >= 0.3 and not _attack_applied:
			_attack_applied = true
			var hit_box: Rect2 = Rect2(global_position + Vector2(0.0 if facing > 0 else -85.0, -48.0), Vector2(85.0, 70.0))
			var attack_ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position + Vector2(0.0, -12.0), target.global_position + Vector2(0.0, -12.0), 1)
			if hit_box.has_point(target.global_position + Vector2(0.0, -12.0)) and get_world_2d().direct_space_state.intersect_ray(attack_ray).is_empty():
				target.call("receive_damage", 15, "orc-%d-%d" % [get_instance_id(), _attack_serial])
		if _attack_elapsed >= 0.6:
			_attack_elapsed = -1.0
	elif to_player.length() <= 76.0 and absf(to_player.y) <= 38.0 and _cooldown <= 0.0:
		facing = 1 if to_player.x >= 0.0 else -1
		_attack_elapsed = 0.0
		_attack_serial += 1
		_attack_applied = false
		_cooldown = 1.3
		_sprite.play("attack")
		_sprite.frame = 0
	elif to_player.length() <= 380.0:
		var chase_point: Vector2 = target.global_position
		if chase_point_provider.is_valid():
			chase_point = chase_point_provider.call(global_position, target.global_position)
		var movement: Vector2 = chase_point - global_position
		velocity = movement.normalized() * speed if movement.length() > 5.0 else Vector2.ZERO
		if absf(velocity.x) > 1.0:
			facing = 1 if velocity.x > 0.0 else -1
	else:
		velocity = Vector2.ZERO
	if not is_inside_tree() or not can_process() or is_queued_for_deletion():
		return
	if not is_instance_valid(target) or not target.health.is_alive():
		return
	move_and_slide()
	_sprite.flip_h = facing < 0
	if _hurt_left > 0.0:
		_sprite.play("hurt")
	elif _attack_elapsed >= 0.0:
		_sprite.play("attack")
	else:
		_sprite.play("walk" if velocity.length_squared() > 1.0 else "idle")
	_sprite.modulate = Color(1.0, 0.5, 0.5) if _hurt_left > 0.0 else Color.WHITE
	queue_redraw()


func receive_damage(amount: int, _attack_id: String = "") -> bool:
	if not health.apply_damage(amount):
		return false
	_hurt_left = 0.4
	_attack_elapsed = -1.0
	velocity = Vector2.ZERO
	if health.is_alive():
		feedback_requested.emit("enemy_hurt", global_position + Vector2(0.0, -24.0))
	return true


func is_alive() -> bool:
	return health.is_alive()


func _on_died() -> void:
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	_hurt_area.set_deferred("collision_layer", 0)
	_sprite.play("death")
	feedback_requested.emit("enemy_death", global_position + Vector2(0.0, -24.0))
	defeated.emit()
	queue_redraw()


func _draw() -> void:
	if health.is_alive():
		draw_rect(Rect2(-20.0, -62.0, 40.0, 4.0), Color(0.13, 0.09, 0.18))
		draw_rect(Rect2(-20.0, -62.0, 40.0 * health.current / health.maximum, 4.0), Color(0.75, 0.3, 0.33))
		if _attack_elapsed >= 0.0 and _attack_elapsed < 0.3:
			var attack_rect: Rect2 = Rect2(Vector2(0.0 if facing > 0 else -85.0, -48.0), Vector2(85.0, 70.0))
			draw_rect(attack_rect, Color(1.0, 0.3, 0.13, 0.16))
			draw_rect(attack_rect, Color(1.0, 0.5, 0.2, 0.65), false, 2.0)

