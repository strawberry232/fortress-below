extends CharacterBody2D
class_name FortressPlayer

signal health_changed(current: int, maximum: int)
signal died
signal shot_requested(origin: Vector2, direction: int)
signal feedback_requested(event: String, at: Vector2)

const HEALTH_SCRIPT: Script = preload("res://game/scripts/combat/fortress_health.gd")
const HIT_SCRIPT: Script = preload("res://game/scripts/combat/fortress_hit_resolver.gd")
const ANIMATION_SCRIPT: Script = preload("res://game/scripts/combat/fortress_animation_library.gd")
const INPUT_BUFFER_SECONDS: float = 0.14

var health: RefCounted = HEALTH_SCRIPT.new()
var facing: int = 1
var speed: float = 170.0
var sword_damage: int = 25
var arrow_damage: int = 15
var _sprite: AnimatedSprite2D
var _hit_resolver: RefCounted = HIT_SCRIPT.new()
var _incoming_hits: RefCounted = HIT_SCRIPT.new()
var _attack: String = ""
var _attack_elapsed: float = 0.0
var _cooldown: float = 0.0
var _hurt_left: float = 0.0
var _attack_serial: int = 0
var _attack_id: String = ""
var _arrow_released: bool = false
var _buffered_attack: String = ""
var _buffered_facing: int = 0
var _buffer_seconds: float = 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 13.0
	shape_node.shape = shape
	shape_node.position = Vector2(0.0, -12.0)
	add_child(shape_node)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = ANIMATION_SCRIPT.character_frames("tiny_rpg", "soldier", Vector2i(100, 100), {
		"idle": ["idle", 6, 10.0], "walk": ["walk", 8, 10.0],
		"attack": ["attack", 6, 10.0], "bow": ["bow", 9, 10.0],
		"hurt": ["hurt", 4, 10.0], "death": ["death", 4, 10.0, [1.0, 1.0, 1.0, 6.0]]
	})
	_sprite.scale = Vector2(3.0, 3.0)
	_sprite.position = Vector2(0.0, -30.0)
	add_child(_sprite)
	_sprite.play("idle")
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	health.reset(100)
	queue_redraw()


func _physics_process(delta: float) -> void:
	delta = maxf(0.0, delta)
	_buffer_seconds = maxf(0.0, _buffer_seconds - delta)
	if _buffer_seconds <= 0.0:
		clear_input_buffer()
	health.tick(delta)
	_cooldown = maxf(0.0, _cooldown - delta)
	_hurt_left = maxf(0.0, _hurt_left - delta)
	if not health.is_alive():
		clear_input_buffer()
		velocity = Vector2.ZERO
		return
	var movement: Vector2 = Input.get_vector("fb_move_left", "fb_move_right", "fb_move_up", "fb_move_down")
	if _attack.is_empty():
		if movement.x != 0.0:
			facing = 1 if movement.x > 0.0 else -1
	if Input.is_action_just_pressed("fb_sword"):
		queue_attack("attack", _input_facing())
	elif Input.is_action_just_pressed("fb_bow"):
		queue_attack("bow", _input_facing())
	_consume_buffered_attack()
	velocity = movement * speed * (0.4 if not _attack.is_empty() else 1.0)
	move_and_slide()
	if not _attack.is_empty():
		_attack_elapsed += delta
		if _attack == "attack" and _attack_elapsed >= 0.3 and _attack_elapsed <= 0.5:
			_resolve_sword_hits()
		elif _attack == "bow" and _attack_elapsed >= 0.7 and not _arrow_released:
			_arrow_released = true
			feedback_requested.emit("bow", global_position + Vector2(facing * 25.0, -32.0))
			shot_requested.emit(global_position + Vector2(facing * 25.0, -32.0), facing)
		var duration: float = 0.6 if _attack == "attack" else 0.9
		if _attack_elapsed >= duration:
			_hit_resolver.clear_attack(_attack_id)
			_attack = ""
			_consume_buffered_attack()
	_sprite.flip_h = facing < 0
	if _hurt_left > 0.0:
		_sprite.play("hurt")
	elif not _attack.is_empty():
		_sprite.play(_attack)
	else:
		_sprite.play("walk" if movement.length_squared() > 0.01 else "idle")
	_sprite.modulate = Color(1.0, 0.6, 0.6, 0.8) if health.protection_left > 0.0 else Color.WHITE
	queue_redraw()


func _input_facing() -> int:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mouse_delta: float = get_global_mouse_position().x - global_position.x
		if absf(mouse_delta) > 15.0:
			return 1 if mouse_delta > 0.0 else -1
	return facing


func queue_attack(kind: String, aimed_facing: int = 0) -> bool:
	if kind not in ["attack", "bow"] or aimed_facing not in [-1, 0, 1]:
		return false
	if not is_inside_tree() or get_tree().paused or not can_process() or not health.is_alive() or _hurt_left > 0.0:
		return false
	_buffered_attack = kind
	_buffered_facing = aimed_facing if aimed_facing != 0 else facing
	_buffer_seconds = INPUT_BUFFER_SECONDS
	_consume_buffered_attack()
	return true


func _consume_buffered_attack() -> void:
	if _buffered_attack.is_empty() or _buffer_seconds <= 0.0 or not _attack.is_empty() or _cooldown > 0.00001 or _hurt_left > 0.0:
		return
	var kind: String = _buffered_attack
	var aimed_facing: int = _buffered_facing
	clear_input_buffer()
	facing = aimed_facing
	_start_attack(kind)


func clear_input_buffer() -> void:
	_buffered_attack = ""
	_buffered_facing = 0
	_buffer_seconds = 0.0


func _notification(what: int) -> void:
	if what in [NOTIFICATION_PAUSED, NOTIFICATION_DISABLED, NOTIFICATION_EXIT_TREE, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		clear_input_buffer()


func _draw() -> void:
	draw_rect(Rect2(-14, -3, 28, 6), Color(0.02, 0.015, 0.025, 0.3))
	if _attack.is_empty() or not health.is_alive():
		return
	var release: float = 0.7 if _attack == "bow" else 0.3
	var progress: float = clampf(_attack_elapsed / release, 0.0, 1.0)
	draw_rect(Rect2(-14, 8, 28, 4), Color(0.07, 0.08, 0.12, 0.9))
	var color: Color = Color(0.52, 0.83, 0.89) if _attack == "bow" else Color(0.97, 0.78, 0.38)
	draw_rect(Rect2(-12, 9, floorf(progress * 24.0), 2), color)


func _start_attack(kind: String) -> void:
	if _cooldown > 0.0 or not _attack.is_empty() or _hurt_left > 0.0:
		return
	if Input.is_action_just_pressed("fb_sword") or Input.is_action_just_pressed("fb_bow"):
		var mouse_delta: float = get_global_mouse_position().x - global_position.x
		if absf(mouse_delta) > 15.0 and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
			facing = 1 if mouse_delta > 0.0 else -1
	_attack = kind
	_attack_elapsed = 0.0
	_arrow_released = false
	_attack_serial += 1
	_attack_id = "sword-%d-%d" % [get_instance_id(), _attack_serial]
	_cooldown = 0.6 if kind == "attack" else 0.9
	_sprite.play(kind)
	_sprite.frame = 0
	if kind == "attack":
		feedback_requested.emit("sword", global_position + Vector2(facing * 43.0, -23.0))


func _resolve_sword_hits() -> void:
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(88.0, 56.0)
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = rectangle
	query.transform = Transform2D(0.0, global_position + Vector2(facing * 43.0, -23.0))
	query.collision_mask = 4
	query.collide_with_areas = true
	for result: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 12):
		var target: Object = result["collider"]
		if target is Area2D and target.get_parent().has_method("receive_damage"):
			target = target.get_parent()
		if not target is Node2D or not target.has_method("receive_damage"):
			continue
		var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position + Vector2(0.0, -12.0), target.global_position + Vector2(0.0, -12.0), 1)
		if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		if _hit_resolver.register_hit(_attack_id, target.get_instance_id()):
			if target.call("receive_damage", sword_damage, _attack_id):
				feedback_requested.emit("sword_hit", target.global_position + Vector2(0.0, -24.0))


func receive_damage(amount: int, incoming_attack_id: String = "") -> bool:
	if not health.is_alive() or amount <= 0 or health.protection_left > 0.00001:
		return false
	if not incoming_attack_id.is_empty() and not _incoming_hits.register_hit(incoming_attack_id, get_instance_id()):
		return false
	if not health.apply_damage(amount):
		return false
	_hurt_left = 0.4
	clear_input_buffer()
	_hit_resolver.clear_attack(_attack_id)
	_attack = ""
	if health.is_alive():
		feedback_requested.emit("player_hurt", global_position + Vector2(0.0, -24.0))
	return true


func heal(amount: int) -> int:
	return health.heal(amount)


func _on_health_changed(current: int, maximum: int) -> void:
	health_changed.emit(current, maximum)


func _on_died() -> void:
	clear_input_buffer()
	_attack = ""
	_sprite.play("death")
	feedback_requested.emit("player_death", global_position + Vector2(0.0, -24.0))
	died.emit()
