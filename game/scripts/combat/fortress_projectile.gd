extends Node2D
class_name FortressProjectile

var velocity: Vector2 = Vector2(520.0, 0.0)
var damage: int = 15
var attack_id: String = ""
var consumed: bool = false
var lifetime: float = 2.3
var source_body: PhysicsBody2D
var _sprite: Sprite2D


func _ready() -> void:
	if attack_id.is_empty():
		attack_id = "arrow-%d" % get_instance_id()
	_sprite = Sprite2D.new()
	_sprite.texture = load("res://game/assets/tiny_rpg/arrow.png")
	_sprite.scale = Vector2(2.0, 2.0)
	_sprite.flip_h = velocity.x < 0.0
	add_child(_sprite)


func _physics_process(delta: float) -> void:
	if consumed:
		return
	lifetime -= maxf(0.0, delta)
	if lifetime <= 0.0:
		_consume()
		return
	var next_point: Vector2 = global_position + velocity * delta
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, next_point, 5)
	query.collide_with_areas = true
	if is_instance_valid(source_body):
		query.exclude = [source_body.get_rid()]
	var result: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		global_position = result["position"]
		var body: Object = result["collider"]
		if body is Area2D and body.get_parent().has_method("receive_damage"):
			body = body.get_parent()
		if body.has_method("receive_damage"):
			body.call("receive_damage", damage, attack_id)
		_consume()
		return
	global_position = next_point


func _consume() -> void:
	consumed = true
	set_physics_process(false)
	if is_instance_valid(_sprite):
		_sprite.visible = false
	queue_free()
