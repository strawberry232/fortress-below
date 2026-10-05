extends CharacterBody2D
class_name FortressSkeleton

signal defeated
signal feedback_requested(event: String, at: Vector2)
signal ranged_shot_requested(origin: Vector2, direction: Vector2, damage: int, attack_id: String)

const HEALTH_SCRIPT: Script = preload("res://game/scripts/combat/fortress_health.gd")
const CATALOG_SCRIPT: Script = preload("res://game/data/monsters/monster_catalog.gd")
const REVIVAL_SCRIPT: Script = preload("res://game/scripts/combat/vampire_revival.gd")
const DEATH_DURATION: float = 1.1
const VAMPIRE_WINDUP: float = 0.4
const VAMPIRE_FLIGHT_END: float = 1.2
const VAMPIRE_HIT_START: float = 0.4
const VAMPIRE_LUNGE_SPEED: float = 240.0
const VAMPIRE_HIT_RADIUS: float = 44.0
const FRAGMENT_BIRTH_GRACE: float = 0.25
const SKULL_SENSING_RADIUS: float = 640.0
const SKULL_CAST_RANGE: float = 320.0
const SKULL_CHARGE_TIME: float = 0.4

var target: Node2D
var chase_point_provider: Callable
var health: RefCounted = HEALTH_SCRIPT.new()
var revival: RefCounted = REVIVAL_SCRIPT.new()
var _first_life_fatal_id: String = ""
var monster_kind: String = "skeleton"
var slime_generation: int = 0
var last_damage_attack_id: String = ""
var _inherited_attack_id: String = ""
var _attack_hits: Dictionary = {}
var speed: float = 65.0
var attack_damage: int = 15
var maximum_health: int = 0
var facing: int = 1
var _sprite: AnimatedSprite2D
var _hurt_area: Area2D
var _attack_elapsed: float = -1.0
var _attack_serial: int = 0
var _attack_applied: bool = false
var _cooldown: float = 0.0
var _hurt_left: float = 0.0
var _death_left: float = DEATH_DURATION
var _death_duration: float = DEATH_DURATION
var _health_bar_y: float = -62.0
var _attack_direction: Vector2 = Vector2.RIGHT
var _lunge_blocked: bool = false
var _cast_sprite: Sprite2D


func configure_kind(kind: String) -> bool:
	if is_node_ready() or CATALOG_SCRIPT.get_definition(kind).is_empty():
		return false
	monster_kind = kind
	return true


func configure_slime_fragment(fatal_attack_id: String = "") -> bool:
	if is_node_ready() or slime_generation != 0:
		return false
	monster_kind = "slime"
	slime_generation = 1
	maximum_health = 14
	_inherited_attack_id = fatal_attack_id
	return true


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var definition: Dictionary = CATALOG_SCRIPT.get_definition(monster_kind)
	if definition.is_empty():
		monster_kind = "skeleton"
		definition = CATALOG_SCRIPT.get_definition(monster_kind)
	speed = definition["speed"]
	attack_damage = definition["damage"]
	if monster_kind == "slime" and slime_generation == 1:
		speed = 65.0
		attack_damage = 6
	if maximum_health <= 0:
		maximum_health = definition["health"]
	revival.reset(monster_kind)
	collision_layer = 4
	collision_mask = 1
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 8.0 if slime_generation == 1 else 12.0
	shape_node.shape = shape
	shape_node.position = Vector2(0.0, -shape.radius)
	add_child(shape_node)
	_hurt_area = Area2D.new()
	_hurt_area.collision_layer = 4
	_hurt_area.collision_mask = 0
	var hurt_shape_node: CollisionShape2D = CollisionShape2D.new()
	var hurt_shape: RectangleShape2D = RectangleShape2D.new()
	hurt_shape.size = Vector2(38.0, 52.0)
	if monster_kind == "slime":
		hurt_shape.size = Vector2(28.0, 24.0) if slime_generation == 1 else Vector2(52.0, 42.0)
	hurt_shape_node.shape = hurt_shape
	hurt_shape_node.position = Vector2(0.0, -hurt_shape.size.y * 0.5)
	_hurt_area.add_child(hurt_shape_node)
	add_child(_hurt_area)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = CATALOG_SCRIPT.create_frames(monster_kind)
	var display_scale: float = definition["display_scale"]
	if monster_kind == "slime" and slime_generation == 1:
		display_scale = 2.0
	_sprite.scale = Vector2.ONE * display_scale
	_sprite.position = (Vector2(definition["frame_size"]) * 0.5 - definition["foot_anchor"]) * display_scale
	add_child(_sprite)
	_sprite.play("idle")
	_death_duration = CATALOG_SCRIPT.action_duration(monster_kind, "death") + 0.2
	if monster_kind == "skull":
		_death_duration = DEATH_DURATION
	_death_left = _death_duration
	_health_bar_y = (-30.0 if slime_generation == 1 else -54.0) if monster_kind == "slime" else -82.0 if monster_kind == "orc" else -62.0
	if monster_kind == "skull" and ResourceLoader.exists("res://game/assets/fx/skull_cast.png"):
		_cast_sprite = Sprite2D.new()
		_cast_sprite.texture = load("res://game/assets/fx/skull_cast.png")
		_cast_sprite.region_enabled = true
		_cast_sprite.position = Vector2(0.0, -24.0)
		_cast_sprite.visible = false
		add_child(_cast_sprite)
	health.protection_duration = 0.1
	health.died.connect(_on_died)
	health.reset(maximum_health)
	if slime_generation == 1:
		health.protection_left = FRAGMENT_BIRTH_GRACE
		_cooldown = FRAGMENT_BIRTH_GRACE


func _physics_process(delta: float) -> void:
	health.tick(delta)
	_cooldown = maxf(0.0, _cooldown - delta)
	_hurt_left = maxf(0.0, _hurt_left - delta)
	_sprite.flip_h = facing < 0
	if not health.is_alive():
		_update_cast_visual()
		if revival.pending:
			if revival.advance(delta):
				_restore_vampire_life()
			else:
				_sprite.stop()
				_sprite.animation = &"death"
				_sprite.set_frame_and_progress(revival.sample()["frame"], 0.0)
			queue_redraw()
			return
		_death_left = maxf(0.0, _death_left - delta)
		if monster_kind == "skull":
			_sprite.modulate = Color(0.8, 0.75, 0.8, _death_left / _death_duration)
		if _death_left <= 0.0:
			queue_free()
		return
	_sprite.modulate = Color(1.0, 0.5, 0.5) if _hurt_left > 0.0 else Color.WHITE
	if _hurt_left > 0.0:
		velocity = Vector2.ZERO
		_sprite.play("hurt")
		_update_cast_visual()
		queue_redraw()
		return
	if not is_instance_valid(target) or not target.health.is_alive():
		_attack_elapsed = -1.0
		velocity = Vector2.ZERO
		_sprite.play("idle")
		_update_cast_visual()
		return
	var to_player: Vector2 = target.global_position - global_position
	if _attack_elapsed >= 0.0:
		var previous_elapsed: float = _attack_elapsed
		_attack_elapsed += delta
		velocity = Vector2.ZERO
		if monster_kind == "vampire":
			_advance_vampire_attack(previous_elapsed)
		elif monster_kind == "skull":
			if _attack_elapsed >= SKULL_CHARGE_TIME and not _attack_applied:
				_attack_applied = true
				if _has_clear_target_line():
					ranged_shot_requested.emit(global_position + Vector2(0.0, -12.0), _attack_direction, attack_damage, "skull-%d-%d" % [get_instance_id(), _attack_serial])
		else:
			_advance_melee_attack(previous_elapsed)
		var duration: float = 0.8 if monster_kind == "skull" else maxf(0.6, CATALOG_SCRIPT.action_duration(monster_kind, "attack"))
		if _attack_elapsed >= duration:
			_attack_elapsed = -1.0
	elif _can_start_attack(to_player) and _cooldown <= 0.0:
		facing = 1 if to_player.x >= 0.0 else -1
		_attack_elapsed = 0.0
		_attack_serial += 1
		_attack_applied = false
		_attack_hits.clear()
		_attack_direction = to_player.normalized() if to_player.length() > 0.01 else Vector2(facing, 0.0)
		_lunge_blocked = false
		_cooldown = 2.2 if monster_kind == "skull" else 2.0 if monster_kind == "vampire" else maxf(1.3, CATALOG_SCRIPT.action_duration(monster_kind, "attack") + 0.4)
	elif to_player.length() <= (SKULL_SENSING_RADIUS if monster_kind == "skull" else 380.0):
		var chase_point: Vector2 = target.global_position
		if chase_point_provider.is_valid():
			chase_point = chase_point_provider.call(global_position, target.global_position)
		var movement: Vector2 = chase_point - global_position
		velocity = movement.normalized() * speed if movement.length() > 5.0 else Vector2.ZERO
		if monster_kind == "skull" and _has_clear_target_line() and to_player.length() < 280.0:
			velocity = Vector2.ZERO
		if absf(velocity.x) > 1.0:
			facing = 1 if velocity.x > 0.0 else -1
	else:
		velocity = Vector2.ZERO
	if not is_inside_tree() or not can_process() or is_queued_for_deletion():
		return
	if not is_instance_valid(target) or not target.health.is_alive():
		return
	if monster_kind != "vampire" or _attack_elapsed < 0.0:
		move_and_slide()
	_sprite.flip_h = facing < 0
	_sprite.play("attack" if _attack_elapsed >= 0.0 else "walk" if velocity.length() > 1.0 else "idle")
	_update_cast_visual()
	queue_redraw()


func receive_damage(amount: int, incoming_attack_id: String = "") -> bool:
	if not _first_life_fatal_id.is_empty() and incoming_attack_id == _first_life_fatal_id:
		return false
	if not _inherited_attack_id.is_empty() and incoming_attack_id == _inherited_attack_id:
		return false
	var previous_identity: String = last_damage_attack_id
	last_damage_attack_id = incoming_attack_id
	var airborne: bool = monster_kind == "vampire" and _attack_elapsed >= VAMPIRE_WINDUP and _attack_elapsed < VAMPIRE_FLIGHT_END
	if not health.apply_damage(amount):
		last_damage_attack_id = previous_identity
		return false
	if not health.is_alive():
		return true
	if airborne and health.is_alive():
		_sprite.modulate = Color(1.0, 0.5, 0.5)
		feedback_requested.emit("enemy_hurt", global_position + Vector2(0.0, -24.0))
		return true
	_hurt_left = CATALOG_SCRIPT.action_duration(monster_kind, "hurt")
	_attack_elapsed = -1.0
	_update_cast_visual()
	velocity = Vector2.ZERO
	if health.is_alive():
		_sprite.play("hurt")
		_sprite.set_frame_and_progress(0, 0.0)
		_sprite.modulate = Color(1.0, 0.5, 0.5)
		feedback_requested.emit("enemy_hurt", global_position + Vector2(0.0, -24.0))
	return true


func is_alive() -> bool:
	return health.is_alive()


func _on_died() -> void:
	_attack_elapsed = -1.0
	_attack_hits.clear()
	_attack_applied = false
	_hurt_left = 0.0
	_update_cast_visual()
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	_hurt_area.set_deferred("collision_layer", 0)
	velocity = Vector2.ZERO
	_sprite.play("death")
	_sprite.modulate = Color.WHITE
	feedback_requested.emit("enemy_death", global_position + Vector2(0.0, -24.0))
	if revival.begin_defeat():
		_first_life_fatal_id = last_damage_attack_id
	else:
		defeated.emit()
	queue_redraw()


func _restore_vampire_life() -> void:
	health.reset(maximum_health)
	health.protection_left = 0.35
	_cooldown = 0.4
	_hurt_left = 0.0
	_attack_elapsed = -1.0
	_attack_hits.clear()
	_attack_applied = false
	_lunge_blocked = false
	_death_left = _death_duration
	velocity = Vector2.ZERO
	set_deferred("collision_layer", 4)
	set_deferred("collision_mask", 1)
	_hurt_area.set_deferred("collision_layer", 4)
	_sprite.play("idle")
	_sprite.set_frame_and_progress(0, 0.0)
	_sprite.modulate = Color.WHITE


func _draw() -> void:
	if health.is_alive():
		draw_rect(Rect2(-20.0, _health_bar_y, 40.0, 4.0), Color(0.13, 0.09, 0.18))
		draw_rect(Rect2(-20.0, _health_bar_y, 40.0 * health.current / health.maximum, 4.0), Color(0.75, 0.3, 0.33))
		if monster_kind == "vampire":
			for index: int in range(2):
				draw_rect(Rect2(-20.0 + index * 8.0, _health_bar_y - 7.0, 5.0, 4.0), Color(0.85, 0.23, 0.34) if index < revival.lives_left else Color(0.24, 0.15, 0.2))
		if monster_kind == "vampire" and _attack_elapsed >= 0.0 and _attack_elapsed < VAMPIRE_WINDUP:
			draw_line(Vector2.ZERO, _attack_direction * (VAMPIRE_LUNGE_SPEED * 0.8), Color(0.9, 0.2, 0.25, 0.22), VAMPIRE_HIT_RADIUS * 2.0)
		elif monster_kind != "skull" and _melee_windup_active():
			var attack_rect: Rect2 = Rect2(Vector2(0.0 if facing > 0 else -85.0, -48.0), Vector2(85.0, 70.0))
			draw_rect(attack_rect, Color(1.0, 0.3, 0.13, 0.16))
			draw_rect(attack_rect, Color(1.0, 0.5, 0.2, 0.65), false, 2.0)


func _melee_windup_active() -> bool:
	if _attack_elapsed < 0.0:
		return false
	var windows: Array[Vector2] = CATALOG_SCRIPT.attack_windows(monster_kind)
	for index: int in range(windows.size()):
		var previous_end: float = windows[index - 1].y if index > 0 else 0.0
		if _attack_elapsed >= previous_end and _attack_elapsed < windows[index].x:
			return true
	return false


func _can_start_attack(to_player: Vector2) -> bool:
	if monster_kind == "skull":
		return to_player.length() <= SKULL_CAST_RANGE and _has_clear_target_line()
	if monster_kind == "vampire":
		return to_player.length() <= 210.0 and _has_clear_target_line()
	return to_player.length() <= 76.0 and absf(to_player.y) <= 38.0


func _has_clear_target_line() -> bool:
	if not is_instance_valid(target) or not target.health.is_alive():
		return false
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position + Vector2(0.0, -12.0), target.global_position + Vector2(0.0, -12.0), 1)
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


func _advance_vampire_attack(previous_elapsed: float) -> void:
	var movement_time: float = maxf(0.0, minf(_attack_elapsed, VAMPIRE_FLIGHT_END) - maxf(previous_elapsed, VAMPIRE_WINDUP))
	var old_position: Vector2 = global_position
	if movement_time > 0.0 and not _lunge_blocked:
		velocity = _attack_direction * VAMPIRE_LUNGE_SPEED
		var collision: KinematicCollision2D = move_and_collide(velocity * movement_time)
		if collision != null:
			_lunge_blocked = true
			velocity = Vector2.ZERO
	if _attack_applied or _attack_elapsed < VAMPIRE_HIT_START or previous_elapsed > VAMPIRE_FLIGHT_END:
		return
	var damage_from: Vector2 = old_position
	if previous_elapsed < VAMPIRE_HIT_START and movement_time > 0.0:
		var early_time: float = maxf(0.0, VAMPIRE_HIT_START - maxf(previous_elapsed, VAMPIRE_WINDUP))
		damage_from = old_position + _attack_direction * minf(early_time * VAMPIRE_LUNGE_SPEED, old_position.distance_to(global_position))
	var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(target.global_position, damage_from, global_position)
	if nearest.distance_to(target.global_position) <= VAMPIRE_HIT_RADIUS and _has_clear_target_line():
		_attack_applied = true
		target.call("receive_damage", attack_damage, "vampire-%d-%d" % [get_instance_id(), _attack_serial])


func _advance_melee_attack(previous_elapsed: float) -> void:
	var windows: Array[Vector2] = CATALOG_SCRIPT.attack_windows(monster_kind)
	for index: int in range(windows.size()):
		var interval: Vector2 = windows[index]
		if _attack_hits.has(index) or _attack_elapsed + 0.00001 < interval.x or previous_elapsed >= interval.y:
			continue
		if not is_instance_valid(target) or not target.health.is_alive():
			return
		var hit_box: Rect2 = Rect2(global_position + Vector2(0.0 if facing > 0 else -85.0, -48.0), Vector2(85.0, 70.0))
		if not hit_box.has_point(target.global_position + Vector2(0.0, -12.0)) or not _has_clear_target_line():
			continue
		var identity: String = "%s-%d-%d-swing-%d" % [monster_kind, get_instance_id(), _attack_serial, index]
		if target.call("receive_damage", attack_damage, identity):
			_attack_hits[index] = true
			_attack_applied = true


func _update_cast_visual() -> void:
	if not is_instance_valid(_cast_sprite):
		return
	_cast_sprite.visible = health.is_alive() and _attack_elapsed >= 0.0 and _attack_elapsed < SKULL_CHARGE_TIME
	if _cast_sprite.visible:
		var frame: int = mini(7, floori(_attack_elapsed / SKULL_CHARGE_TIME * 8.0))
		_cast_sprite.region_rect = Rect2(frame * 64, 128, 64, 64)
