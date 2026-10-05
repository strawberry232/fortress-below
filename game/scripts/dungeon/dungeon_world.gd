extends Node2D
class_name FortressDungeon

signal loot_collected(amount: int)
signal goal_key_collected
signal sealed_chest_requested
signal exit_requested
signal failed(reason: String)
signal health_changed(current: int, maximum: int)
signal message_requested(key: String)
signal feedback_requested(event: String, at: Vector2)

const PLAYER_SCRIPT: Script = preload("res://game/scripts/combat/fortress_player.gd")
const ENEMY_SCRIPT: Script = preload("res://game/scripts/combat/fortress_skeleton.gd")
const ARROW_SCRIPT: Script = preload("res://game/scripts/combat/fortress_projectile.gd")
const ENEMY_PROJECTILE_SCRIPT: Script = preload("res://game/scripts/combat/fortress_enemy_projectile.gd")
const LAYOUT_SCRIPT: Script = preload("res://game/data/dungeons/dungeon_layouts.gd")
const STATIC_MAP_SCRIPT: Script = preload("res://game/scripts/world/static_map_layer.gd")
const MAP_DETAILS: Script = preload("res://game/scripts/world/map_details.gd")
const MAP_SIZE: Vector2 = Vector2(1024.0, 480.0)
const CELL_SIZE: int = 32
const ORDINARY_CHEST_POSITION: Vector2 = Vector2(224.0, 144.0)
const SEALED_CHEST_POSITION: Vector2 = Vector2(416.0, 112.0)
const KEY_POSITION: Vector2 = Vector2(880.0, 144.0)
const STAIRS_POSITION: Vector2 = Vector2(144.0, 88.0)
const POTION_POSITION: Vector2 = Vector2(544.0, 352.0)
const SPIKE_PERIOD: float = 3.0
const SPIKE_RAISED_AT: float = 2.0
const SPIKE_HIT_COOLDOWN: float = 0.7
const SPIKE_PROTECTION_RETRY: float = 0.08
const CHEST_FRAME_TIME: float = 0.12
const SEALED_CHEST_TINT: Color = Color(1.0, 0.63, 0.78)

var player: CharacterBody2D
var ordinary_chest_position: Vector2 = ORDINARY_CHEST_POSITION
var sealed_chest_position: Vector2 = SEALED_CHEST_POSITION
var key_position: Vector2 = KEY_POSITION
var stairs_position: Vector2 = STAIRS_POSITION
var _content: Node2D
var _gate: StaticBody2D
var _gates: Array[StaticBody2D] = []
var _layout: Dictionary = LAYOUT_SCRIPT.get_layout(0)
var _navigation: AStarGrid2D
var _enemies: Array[CharacterBody2D] = []
var _middle_guardians: int = 2
var _reward_guardians: int = 1
var _reward_guard_defeated: bool = false
var _ordinary_open: bool = false
var _sealed_open: bool = false
var _ordinary_opened_at: float = -1.0
var _sealed_opened_at: float = -1.0
var _chest_frames: Dictionary = {}
var _torch_frames: Array[Texture2D] = []
var _key_taken: bool = false
var _potion_taken: bool = false
var _potions_taken: Dictionary = {}
var _run_failed: bool = false
var _clock: float = 0.0
var _run_generation: int = 0
var _spike_hit_times: Dictionary = {}
var _textures: Dictionary = {}
var _spikes: Array[Vector2] = [Vector2(544.0, 256.0), Vector2(800.0, 320.0)]
var _tileset: Texture2D
var _static_map: Node2D
var _floor_regions: Array[Rect2] = []
var _walkable_cells: PackedByteArray = PackedByteArray()
var _floor_grid_aligned: bool = false
var _environment_details: Array[Dictionary] = []


func _init() -> void:
	_rebuild_floor_cache()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_static_map = STATIC_MAP_SCRIPT.new()
	_static_map.name = "StaticMap"
	_static_map.renderer = _draw_static_map
	add_child(_static_map)
	move_child(_static_map, 0)
	_tileset = load("res://game/assets/dungeon/tileset.png")
	for name: String in ["chest", "chest_open", "key", "potion", "spikes_idle", "spikes_active"]:
		_textures[name] = load("res://game/assets/dungeon/%s.png" % name)
	for family: String in ["mini_chest", "chest"]:
		var closed: Array[Texture2D] = []
		var opened: Array[Texture2D] = []
		for index: int in range(1, 5):
			closed.append(load("res://game/assets/dungeon/items/%s/%s_%d.png" % [family, family, index]))
			opened.append(load("res://game/assets/dungeon/items/%s/%s_open_%d.png" % [family, family, index]))
		_chest_frames[family] = {"closed": closed, "open": opened}
	for index: int in range(1, 5):
		_torch_frames.append(load("res://game/assets/dungeon/items/torch/torch_%d.png" % index))
	reset_run()


func reset_run(level_index: int = 0) -> void:
	_run_generation += 1
	if is_instance_valid(_content):
		remove_child(_content)
		_content.queue_free()
	_content = Node2D.new()
	_content.y_sort_enabled = true
	add_child(_content)
	_enemies.clear()
	_gates.clear()
	_layout = LAYOUT_SCRIPT.get_layout(level_index)
	_environment_details = MAP_DETAILS.dungeon_details(_layout)
	_rebuild_floor_cache()
	ordinary_chest_position = _layout["ordinary_chest"]
	sealed_chest_position = _layout["sealed_chest"]
	key_position = _layout["key"]
	stairs_position = _layout["stairs"]
	_spikes.assign(_layout["spikes"])
	_middle_guardians = _layout["guardians"].size()
	_reward_guardians = 1
	_reward_guard_defeated = false
	_ordinary_open = false
	_sealed_open = false
	_ordinary_opened_at = -1.0
	_sealed_opened_at = -1.0
	_key_taken = false
	_potion_taken = false
	_potions_taken.clear()
	_run_failed = false
	_clock = 0.0
	_spike_hit_times.clear()
	_build_collisions()
	_build_navigation()
	player = PLAYER_SCRIPT.new()
	player.position = _layout["player_start"]
	player.health_changed.connect(_on_player_health_changed)
	player.died.connect(_on_player_died)
	player.shot_requested.connect(_on_shot_requested)
	player.feedback_requested.connect(_on_actor_feedback)
	_content.add_child(player)
	for guardian_index: int in range(_layout["guardians"].size()):
		_spawn_enemy(_layout["guardians"][guardian_index], true, _layout["guardian_kinds"][guardian_index])
	_spawn_enemy(_layout["reward_guard"], false, _layout["reward_kind"])
	if is_instance_valid(_static_map):
		_static_map.invalidate()
	queue_redraw()


func _spawn_enemy(location: Vector2, unlocks_gate: bool, kind: String = "skeleton", slime_fragment: bool = false, fatal_attack_id: String = "") -> CharacterBody2D:
	var enemy: CharacterBody2D = ENEMY_SCRIPT.new()
	if slime_fragment:
		enemy.configure_slime_fragment(fatal_attack_id)
	else:
		enemy.configure_kind(kind)
	enemy.position = location
	enemy.target = player
	enemy.chase_point_provider = get_chase_point
	if _layout["index"] == 2 and kind == "skeleton":
		enemy.maximum_health = 50
	enemy.feedback_requested.connect(_on_actor_feedback)
	enemy.defeated.connect(_on_enemy_defeated.bind(enemy, unlocks_gate, _run_generation))
	enemy.ranged_shot_requested.connect(_on_enemy_shot_requested.bind(enemy, _run_generation))
	_content.add_child(enemy)
	_enemies.append(enemy)
	return enemy


func _on_enemy_defeated(enemy: CharacterBody2D, unlocks_gate: bool, generation: int) -> void:
	if _run_failed or is_queued_for_deletion() or generation != _run_generation or not is_instance_valid(enemy):
		return
	if enemy.is_queued_for_deletion() or enemy.get_parent() != _content or enemy.health.is_alive() or enemy.get_meta("defeat_processed", false):
		return
	enemy.set_meta("defeat_processed", true)
	if enemy.monster_kind == "slime" and enemy.slime_generation == 0:
		if unlocks_gate:
			_middle_guardians += 2
		else:
			_reward_guardians += 2
		_spawn_slime_fragments.call_deferred(enemy.position, unlocks_gate, generation, enemy.last_damage_attack_id)
	if unlocks_gate:
		_on_middle_guardian_defeated()
	else:
		_on_reward_guardian_defeated()


func _spawn_slime_fragments(origin: Vector2, unlocks_gate: bool, generation: int, fatal_attack_id: String = "") -> void:
	if _run_failed or is_queued_for_deletion() or generation != _run_generation or not is_instance_valid(player) or not player.health.is_alive():
		return
	var locations: Array[Vector2] = _find_fragment_positions(origin)
	for location: Vector2 in locations:
		_spawn_enemy(location, unlocks_gate, "slime", true, fatal_attack_id)
	for missing: int in range(2 - locations.size()):
		if unlocks_gate:
			_on_middle_guardian_defeated()
		else:
			_on_reward_guardian_defeated()


func _fragment_floor_is_clear(point: Vector2) -> bool:
	if not is_walkable(point):
		return false
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 12.0
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, to_global(point + Vector2(0.0, -12.0)))
	query.collision_mask = 1
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _fragment_position_is_clear(point: Vector2) -> bool:
	if not _fragment_floor_is_clear(point):
		return false
	var cell: Vector2i = Vector2i(floori(point.x / CELL_SIZE), floori(point.y / CELL_SIZE))
	return _navigation.is_in_boundsv(cell) and not _navigation.is_point_solid(cell)


func _find_fragment_anchor(origin: Vector2) -> Vector2:
	if _fragment_position_is_clear(origin):
		return origin
	var closest: Vector2 = Vector2.INF
	var closest_distance: float = 96.0 * 96.0
	for row: int in range(15):
		for column: int in range(32):
			var cell: Vector2i = Vector2i(column, row)
			if _navigation.is_point_solid(cell):
				continue
			var candidate: Vector2 = _navigation.get_point_position(cell)
			var distance: float = origin.distance_squared_to(candidate)
			if distance >= closest_distance or not _fragment_position_is_clear(candidate):
				continue
			var steps: int = maxi(1, ceili(origin.distance_to(candidate) / 6.0))
			var clear: bool = true
			for step: int in range(steps + 1):
				if not _fragment_floor_is_clear(origin.lerp(candidate, step / (steps as float))):
					clear = false
					break
			if clear:
				closest = candidate
				closest_distance = distance
	return closest


func _find_fragment_positions(origin: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var anchor: Vector2 = _find_fragment_anchor(origin)
	if anchor == Vector2.INF:
		return result
	var candidates: Array[Vector2] = []
	for offset: Vector2 in [Vector2(-24, 0), Vector2(24, 0), Vector2(0, -24), Vector2(0, 24), Vector2(-24, -24), Vector2(24, 24)]:
		candidates.append(origin + offset)
	var first: Vector2i = Vector2i(floori(anchor.x / CELL_SIZE), floori(anchor.y / CELL_SIZE))
	if _navigation.is_in_boundsv(first) and not _navigation.is_point_solid(first):
		var visited: Dictionary = {first: true}
		var open_cells: Array[Vector2i] = [first]
		while not open_cells.is_empty():
			var cell: Vector2i = open_cells.pop_front()
			candidates.append(_navigation.get_point_position(cell))
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next: Vector2i = cell + offset
				if visited.has(next) or not _navigation.is_in_boundsv(next) or _navigation.is_point_solid(next):
					continue
				visited[next] = true
				open_cells.append(next)
	for candidate: Vector2 in candidates:
		if not _fragment_position_is_clear(candidate) or get_navigation_path(anchor, candidate).is_empty():
			continue
		if not result.is_empty() and result[0].distance_to(candidate) < 28.0:
			continue
		result.append(candidate)
		if result.size() == 2:
			break
	return result


func _rebuild_floor_cache() -> void:
	_floor_regions.assign(_layout.get("rooms", []))
	_floor_regions.append_array(_layout.get("corridors", []))
	_walkable_cells.resize(32 * 15)
	_walkable_cells.fill(0)
	_floor_grid_aligned = true
	var bounds: Rect2 = Rect2(Vector2.ZERO, MAP_SIZE)
	for region: Rect2 in _floor_regions:
		if not bounds.encloses(region):
			_floor_grid_aligned = false
		for edge: float in [region.position.x, region.position.y, region.end.x, region.end.y]:
			if fposmod(edge, CELL_SIZE) != 0.0:
				_floor_grid_aligned = false
		for row: int in range(maxi(0, floori(region.position.y / CELL_SIZE)), mini(15, ceili(region.end.y / CELL_SIZE))):
			for column: int in range(maxi(0, floori(region.position.x / CELL_SIZE)), mini(32, ceili(region.end.x / CELL_SIZE))):
				var center: Vector2 = Vector2(column, row) * CELL_SIZE + Vector2(16, 16)
				if region.has_point(center):
					_walkable_cells[row * 32 + column] = 1


func is_walkable(point: Vector2) -> bool:
	if not point.is_finite():
		return false
	if _floor_grid_aligned:
		if not Rect2(Vector2.ZERO, MAP_SIZE).has_point(point):
			return false
		var cell: Vector2i = Vector2i(floori(point.x / CELL_SIZE), floori(point.y / CELL_SIZE))
		return _walkable_cells[cell.y * 32 + cell.x] != 0
	for room: Rect2 in _floor_regions:
		if room.has_point(point):
			return true
	return false


func _build_collisions() -> void:
	for row: int in range(15):
		for column: int in range(32):
			var center: Vector2 = Vector2(column * CELL_SIZE + 16.0, row * CELL_SIZE + 16.0)
			if not is_walkable(center):
				_make_wall(center, Vector2(32.0, 32.0))
	for gate_rectangle: Rect2 in _layout["gates"]:
		_gates.append(_make_wall(gate_rectangle.get_center(), gate_rectangle.size))
	_gate = _gates[0]


func _build_navigation() -> void:
	_navigation = AStarGrid2D.new()
	_navigation.region = Rect2i(0, 0, 32, 15)
	_navigation.cell_size = Vector2(32.0, 32.0)
	_navigation.offset = Vector2(16.0, 28.0)
	_navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_navigation.update()
	for row: int in range(15):
		for column: int in range(32):
			var cell: Vector2i = Vector2i(column, row)
			var floor_point: Vector2 = Vector2(cell) * 32.0 + Vector2(16.0, 28.0)
			var blocked: bool = not is_walkable(floor_point)
			if _middle_guardians > 0:
				for gate_rectangle: Rect2 in _layout["gates"]:
					if gate_rectangle.intersects(Rect2(Vector2(cell) * 32.0, Vector2(32.0, 32.0))):
						blocked = true
			_navigation.set_point_solid(cell, blocked)


func _make_wall(center: Vector2, size: Vector2) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	_content.add_child(body)
	return body


func get_chase_point(enemy_global: Vector2, player_global: Vector2) -> Vector2:
	var enemy_local: Vector2 = to_local(enemy_global)
	var player_local: Vector2 = to_local(player_global)
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(enemy_global + Vector2(0.0, -12.0), player_global + Vector2(0.0, -12.0), 1)
	if get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
		return player_global
	var path: PackedVector2Array = get_navigation_path(enemy_local, player_local)
	if path.size() > 1:
		return to_global(path[1])
	return enemy_global


func get_navigation_path(from_local: Vector2, to_local_point: Vector2) -> PackedVector2Array:
	var first: Vector2i = Vector2i(floori(from_local.x / 32.0), floori(from_local.y / 32.0))
	var last: Vector2i = Vector2i(floori(to_local_point.x / 32.0), floori(to_local_point.y / 32.0))
	if not _navigation.is_in_boundsv(first) or not _navigation.is_in_boundsv(last):
		return PackedVector2Array()
	if _navigation.is_point_solid(first) or _navigation.is_point_solid(last):
		return PackedVector2Array()
	return _navigation.get_point_path(first, last)


func get_level_info() -> Dictionary:
	return _layout.duplicate(true)


func get_environment_details() -> Array[Dictionary]:
	return _environment_details.duplicate(true)


func get_interaction_hint(location: Vector2) -> Dictionary:
	if _run_failed or not is_walkable(location) or not is_instance_valid(player) or not player.health.is_alive():
		return {}
	if location.distance_to(ordinary_chest_position) < 58.0 and not _ordinary_open:
		return {"key": "UI_INTERACT_CHEST", "actionable": true}
	if location.distance_to(sealed_chest_position) < 58.0 and not _sealed_open:
		return {"key": "UI_INTERACT_SEALED_CHEST", "actionable": true}
	if location.distance_to(key_position) < 58.0 and not _key_taken:
		return {"key": "UI_INTERACT_KEY" if _reward_guard_defeated else "UI_MSG_DEFEAT_GUARD", "actionable": _reward_guard_defeated}
	if location.distance_to(stairs_position) < 58.0:
		return {"key": "UI_INTERACT_STAIRS" if _key_taken else "UI_KEY_REQUIRED", "actionable": _key_taken}
	for index: int in range(_layout["potions"].size()):
		if not _potions_taken.has(index) and location.distance_to(_layout["potions"][index]) < 48.0:
			return {"key": "UI_INTERACT_POTION" if player.health.current < player.health.maximum else "UI_MSG_HEALTH_FULL", "actionable": player.health.current < player.health.maximum}
	return {}


func _physics_process(delta: float) -> void:
	if _run_failed or not is_instance_valid(player):
		return
	_clock += maxf(delta, 0.0)
	if Input.is_action_just_pressed("fb_interact"):
		_handle_interaction_at(player.position)
	_update_spike_damage()
	queue_redraw()


func _spike_phase(index: int) -> float:
	return fposmod(_clock + index * 0.65, SPIKE_PERIOD)


func is_spike_active(index: int) -> bool:
	return index >= 0 and index < _spikes.size() and _spike_phase(index) >= SPIKE_RAISED_AT


func get_spike_visual(index: int) -> Dictionary:
	if index < 0 or index >= _spikes.size():
		return {}
	var active: bool = is_spike_active(index)
	var warning: bool = _spike_phase(index) >= 1.5 and not active
	return {"active": active, "texture": _textures["spikes_idle" if active else "spikes_active"],
		"destination": Rect2(_spikes[index] - Vector2(24, 24), Vector2(48, 48)),
		"tint": Color(1.0, 0.6, 0.55) if warning else Color.WHITE}


func _update_spike_damage() -> void:
	var player_id: int = player.get_instance_id()
	for index: int in range(_spikes.size()):
		if not player.health.is_alive():
			break
		if not is_spike_active(index) or player.position.distance_to(_spikes[index]) >= 28.0:
			continue
		var trap_hits: Dictionary = _spike_hit_times.get(index, {})
		var next_hit: float = trap_hits.get(player_id, -1.0)
		if _clock + 0.00001 < next_hit:
			continue
		var accepted: bool = player.receive_damage(20)
		trap_hits[player_id] = _clock + (SPIKE_HIT_COOLDOWN if accepted else SPIKE_PROTECTION_RETRY)
		_spike_hit_times[index] = trap_hits


func _handle_interaction_at(location: Vector2) -> void:
	if _run_failed or not is_walkable(location):
		return
	if location.distance_to(ordinary_chest_position) < 58.0 and not _ordinary_open:
		_ordinary_open = true
		_ordinary_opened_at = _clock
		loot_collected.emit(25)
		feedback_requested.emit("chest", to_global(ordinary_chest_position))
		message_requested.emit("UI_MSG_LOOT_FOUND")
	elif location.distance_to(sealed_chest_position) < 58.0 and not _sealed_open:
		sealed_chest_requested.emit()
	elif location.distance_to(key_position) < 58.0 and not _key_taken:
		if not _reward_guard_defeated:
			message_requested.emit("UI_MSG_DEFEAT_GUARD")
		else:
			_key_taken = true
			goal_key_collected.emit()
			feedback_requested.emit("key", to_global(key_position))
			message_requested.emit("UI_MSG_KEY_FOUND")
	elif location.distance_to(stairs_position) < 58.0:
		exit_requested.emit()
	else:
		var potion_found: bool = false
		for index: int in range(_layout["potions"].size()):
			var potion_position: Vector2 = _layout["potions"][index]
			if location.distance_to(potion_position) < 48.0 and not _potions_taken.has(index):
				potion_found = true
				if player.heal(30) > 0:
					_potions_taken[index] = true
					_potion_taken = _potions_taken.has(0)
					feedback_requested.emit("heal", player.global_position + Vector2(0.0, -24.0))
					message_requested.emit("UI_MSG_HEALED")
				else:
					message_requested.emit("UI_MSG_HEALTH_FULL")
				break
		if not potion_found:
			message_requested.emit("UI_MSG_NOTHING_NEARBY")
	queue_redraw()


func confirm_sealed_chest() -> void:
	if _sealed_open or _run_failed:
		return
	_sealed_open = true
	_sealed_opened_at = _clock
	feedback_requested.emit("chest", to_global(sealed_chest_position))
	message_requested.emit("UI_MSG_SEAL_OPENED")
	queue_redraw()


func get_player_health() -> int:
	return player.health.current if is_instance_valid(player) else 100


func _on_player_health_changed(current: int, maximum: int) -> void:
	health_changed.emit(current, maximum)


func _on_player_died() -> void:
	if _run_failed:
		return
	_run_failed = true
	failed.emit("player_defeated")


func _on_shot_requested(origin: Vector2, direction: int) -> void:
	var arrow: Node2D = ARROW_SCRIPT.new()
	arrow.position = _content.to_local(origin)
	arrow.velocity = Vector2(direction * 520.0, 0.0)
	arrow.source_body = player
	arrow.damage = 15
	_content.add_child(arrow)


func _on_enemy_shot_requested(origin: Vector2, direction: Vector2, damage: int, attack_id: String, source_body: CharacterBody2D, generation: int) -> void:
	if _run_failed or generation != _run_generation or not is_instance_valid(player) or not player.health.is_alive():
		return
	if not is_instance_valid(source_body) or source_body.is_queued_for_deletion() or source_body.get_parent() != _content or not source_body.health.is_alive():
		return
	if direction.is_zero_approx() or damage <= 0:
		return
	var projectile: Node2D = ENEMY_PROJECTILE_SCRIPT.new()
	projectile.position = _content.to_local(origin)
	projectile.velocity = direction.normalized() * 190.0
	projectile.damage = damage
	projectile.attack_id = attack_id
	projectile.source_body = source_body
	_content.add_child(projectile)


func _on_middle_guardian_defeated() -> void:
	if _run_failed or _middle_guardians <= 0:
		return
	_middle_guardians = maxi(0, _middle_guardians - 1)
	if _middle_guardians == 0:
		for gate_body: StaticBody2D in _gates:
			gate_body.set_deferred("collision_layer", 0)
		_build_navigation()
		feedback_requested.emit("gate", to_global(_layout["gates"][0].get_center()))
		message_requested.emit("UI_MSG_GATE_OPENED")
	queue_redraw()


func _on_reward_guardian_defeated() -> void:
	if _run_failed or _reward_guardians <= 0:
		return
	_reward_guardians -= 1
	if _reward_guardians == 0:
		_reward_guard_defeated = true
		message_requested.emit("UI_MSG_KEY_READY")
	queue_redraw()


func _on_actor_feedback(event: String, at: Vector2) -> void:
	feedback_requested.emit(event, at)


func _draw_icon(name: String, location: Vector2, size: float = 48.0, tint: Color = Color.WHITE) -> void:
	if _textures.has(name):
		draw_texture_rect(_textures[name], Rect2(location - Vector2(size, size) * 0.5, Vector2(size, size)), false, tint)


func get_chest_visual(kind: String) -> Dictionary:
	if kind != "ordinary" and kind != "sealed":
		return {}
	var family: String = "mini_chest" if kind == "ordinary" else "chest"
	var opened: bool = _ordinary_open if kind == "ordinary" else _sealed_open
	var opened_at: float = _ordinary_opened_at if kind == "ordinary" else _sealed_opened_at
	var location: Vector2 = ordinary_chest_position if kind == "ordinary" else sealed_chest_position
	var frame: int = floori(maxf(0.0, _clock) / 0.15) % 4
	var state: String = "closed"
	if opened:
		var elapsed: float = maxf(0.0, _clock - opened_at)
		frame = mini(3, floori(elapsed / CHEST_FRAME_TIME))
		state = "opening" if elapsed < CHEST_FRAME_TIME * 4.0 else "opened"
	var textures: Array = _chest_frames[family]["open" if opened else "closed"]
	var dangerous: bool = kind == "sealed" and not opened
	return {"family": family, "state": state, "frame": frame, "texture": textures[frame], "destination": Rect2(location - Vector2(24, 24), Vector2(48, 48)),
		"dangerous": dangerous, "tint": SEALED_CHEST_TINT if kind == "sealed" else Color.WHITE,
		"indicator": "exclamation" if dangerous else "", "seal": false, "warning_key": ""}


func get_gate_visual(gate: Rect2, opened: bool = false) -> Dictionary:
	if gate.size.x <= 0.0 or gate.size.y <= 0.0:
		return {}
	var vertical: bool = gate.size.y > gate.size.x
	var length: float = gate.size.y if vertical else gate.size.x
	var size: Vector2 = Vector2(32.0, length) if vertical else Vector2(length, 32.0)
	var source: Rect2 = Rect2(112 if opened else 96, 64, 16, 32) if vertical else Rect2(96, 96 if opened else 48, 32, 16)
	var panels: Array[Dictionary] = []
	if opened:
		var stub: float = minf(16.0, length * 0.2)
		if vertical:
			panels.append({"destination": Rect2(-16, -length * 0.5, 32, stub), "source": Rect2(source.position, Vector2(16, 8))})
			panels.append({"destination": Rect2(-16, length * 0.5 - stub, 32, stub), "source": Rect2(source.position + Vector2(0, 24), Vector2(16, 8))})
		else:
			panels.append({"destination": Rect2(-length * 0.5, -16, stub, 32), "source": Rect2(source.position, Vector2(8, 16))})
			panels.append({"destination": Rect2(length * 0.5 - stub, -16, stub, 32), "source": Rect2(source.position + Vector2(24, 0), Vector2(8, 16))})
	else:
		panels.append({"destination": Rect2(-size * 0.5, size), "source": source})
	return {"axis": "vertical" if vertical else "horizontal", "center": gate.get_center(), "rotation": 0.0,
		"destination": Rect2(-size * 0.5, size), "bounds": Rect2(gate.get_center() - size * 0.5, size), "source": source, "opened": opened, "panels": panels}


func get_gate_visuals() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for gate: Rect2 in _layout["gates"]:
		result.append(get_gate_visual(gate, _middle_guardians == 0))
	return result


func get_exit_visual() -> Dictionary:
	var wall_position: Vector2 = _layout["exit_wall"]
	return {"source": Rect2(144, 48, 16, 16), "destination": Rect2(wall_position - Vector2(16, 16), Vector2(32, 32)),
		"direction": "up", "model": "wall_ladder", "wall_position": wall_position, "interaction_position": stairs_position}


func get_map_tile_visual(cell: Vector2i) -> Dictionary:
	if cell.x < 0 or cell.y < 0 or cell.x >= 32 or cell.y >= 15:
		return {}
	var destination: Rect2 = Rect2(Vector2(cell) * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE))
	var center: Vector2 = destination.get_center()
	var variant: int = (cell.x * 7 + cell.y * 3) % 4
	var source: Rect2 = Rect2(16 + variant * 16, 16, 16, 16)
	if is_walkable(center):
		return {"kind": "floor", "source": source, "destination": destination}
	if is_walkable(center + Vector2(0, CELL_SIZE)):
		source = Rect2(16 + variant * 16, 0, 16, 16)
	elif is_walkable(center - Vector2(0, CELL_SIZE)):
		source = Rect2(16 + variant * 16, 64, 16, 16)
	elif is_walkable(center + Vector2(CELL_SIZE, 0)):
		source = Rect2(0, 16, 16, 16)
	elif is_walkable(center - Vector2(CELL_SIZE, 0)):
		source = Rect2(80, 16, 16, 16)
	elif is_walkable(center + Vector2(CELL_SIZE, CELL_SIZE)):
		source = Rect2(0, 0, 16, 16)
	elif is_walkable(center + Vector2(-CELL_SIZE, CELL_SIZE)):
		source = Rect2(80, 0, 16, 16)
	elif is_walkable(center + Vector2(CELL_SIZE, -CELL_SIZE)):
		source = Rect2(0, 64, 16, 16)
	elif is_walkable(center + Vector2(-CELL_SIZE, -CELL_SIZE)):
		source = Rect2(80, 64, 16, 16)
	else:
		return {}
	return {"kind": "wall", "source": source, "destination": destination}


func get_torch_visuals() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for room: Rect2 in _layout["rooms"]:
		var location: Vector2 = Vector2(room.position.x + 64.0, room.position.y - 16.0)
		if is_walkable(location) or not is_walkable(location + Vector2(0, CELL_SIZE)):
			continue
		var frame: int = floori(maxf(0.0, _clock) * 8.0 + result.size()) % 4
		result.append({"location": location, "frame": frame, "texture": _torch_frames[frame], "destination": Rect2(location - Vector2(24, 24), Vector2(48, 48)), "glow_clip": room.grow(CELL_SIZE).intersection(Rect2(Vector2.ZERO, MAP_SIZE))})
	return result


func _draw_static_map(canvas: Node2D) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color(0.025, 0.023, 0.04))
	if _tileset == null:
		return
	for row: int in range(15):
		for column: int in range(32):
			var tile: Dictionary = get_map_tile_visual(Vector2i(column, row))
			if not tile.is_empty():
				var tint: Color = [Color(0.68, 0.80, 0.96), Color(0.59, 0.76, 0.96), Color(0.76, 0.68, 0.92)][int(_layout["index"])]
				canvas.draw_texture_rect_region(_tileset, tile["destination"], tile["source"], tint)
				if tile["kind"] == "floor" and (column * 17 + row * 7) % 11 == 0:
					var at: Vector2 = tile["destination"].position
					canvas.draw_rect(Rect2(at + Vector2(10, 4), Vector2(2, 12)), Color(0.025, 0.035, 0.055, 0.32))
					canvas.draw_rect(Rect2(at + Vector2(10, 14), Vector2(8, 2)), Color(0.025, 0.035, 0.055, 0.32))
	for detail: Dictionary in _environment_details:
		MAP_DETAILS.draw_detail(canvas, detail)


func _draw() -> void:
	if _tileset == null:
		return
	for torch: Dictionary in get_torch_visuals():
		MAP_DETAILS.draw_torch_glow(self, torch["location"] + Vector2(0, -6), 0.9 + sin(_clock * 3.0) * 0.06, torch["glow_clip"])
		draw_texture_rect(torch["texture"], torch["destination"], false)
	var exit_visual: Dictionary = get_exit_visual()
	draw_texture_rect_region(_tileset, exit_visual["destination"], exit_visual["source"])
	for kind: String in ["ordinary", "sealed"]:
		var chest: Dictionary = get_chest_visual(kind)
		draw_texture_rect(chest["texture"], chest["destination"], false, chest["tint"])
		if chest["indicator"] == "exclamation":
			var location: Vector2 = chest["destination"].get_center()
			var seal_color: Color = Color(0.93, 0.2, 0.42)
			draw_rect(Rect2(location + Vector2(24, -24), Vector2(14, 20)), Color(0.18, 0.06, 0.13))
			draw_rect(Rect2(location + Vector2(30, -21), Vector2(3, 10)), seal_color)
			draw_rect(Rect2(location + Vector2(30, -8), Vector2(3, 3)), seal_color)
	if not _key_taken:
		_draw_icon("key", key_position)
	for index: int in range(_layout["potions"].size()):
		if not _potions_taken.has(index):
			_draw_icon("potion", _layout["potions"][index])
	for gate: Dictionary in get_gate_visuals():
		draw_set_transform(gate["center"], gate["rotation"])
		for panel: Dictionary in gate["panels"]:
			draw_texture_rect_region(_tileset, panel["destination"], panel["source"])
		draw_set_transform(Vector2.ZERO)
	for index: int in range(_spikes.size()):
		var visual: Dictionary = get_spike_visual(index)
		draw_texture_rect(visual["texture"], visual["destination"], false, visual["tint"])
