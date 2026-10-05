extends Node2D

signal castle_damaged(amount: int)
signal wave_completed
signal tower_selected(slot: int)
signal status_changed
signal feedback_requested(event: String, at: Vector2)

const LedgerScript = preload("res://game/scripts/defense/wave_ledger.gd")
const DefenseBalanceScript = preload("res://game/scripts/defense/defense_balance.gd")
const MonsterCatalog = preload("res://game/data/monsters/monster_catalog.gd")
const VampireRevivalScript = preload("res://game/scripts/combat/vampire_revival.gd")
const PixelFont = preload("res://game/scripts/ui/pixel_font.gd")
const STATIC_MAP_SCRIPT: Script = preload("res://game/scripts/world/static_map_layer.gd")
const MAP_DETAILS: Script = preload("res://game/scripts/world/map_details.gd")
const DEFAULT_BALANCE: Resource = preload("res://game/data/balance/defense_balance.tres")
const ARCHER_FOOT: Vector2 = Vector2(50, 60)
const TOWER_FOOT: Vector2 = Vector2(128, 166)
const ARCHER_PLATFORM: Vector2 = Vector2(128, 75)
const ROAD_SOURCE: Rect2 = Rect2(384, 64, 64, 64)
const ROAD_HALF_WIDTH: float = 19.0
const REVIVE_PROTECTION: float = 0.35
const REVIVE_ATTACK_GRACE: float = 0.4

var balance: DefenseBalanceScript = DEFAULT_BALANCE.duplicate() as DefenseBalanceScript
var ledger: RefCounted = LedgerScript.new()
var tower_levels: Array[int] = [1, 0, 0, 0, 0, 0]
var running: bool = false
var tower_selection_enabled: bool = false
var selected_tower: int = -1
var corpses: Array[Dictionary] = []
var round_index: int = 1
var selected_enemy: int = -1
var next_id: int = 1
var spawn_clock: float = 0.0
var rally_seconds: float = 0.0
var tower_clocks: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var archer_shoot_seconds: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var archer_facing_left: Array[bool] = [false, false, false, false, false, false]
var animation_clock: float = 0.0
var enemies: Dictionary = {}
var arrows: Array[Dictionary] = []
var flashes: Array[Dictionary] = []
var tower_points: Array[Vector2] = [Vector2(480, 210), Vector2(480, 460), Vector2(130, 210), Vector2(305, 210), Vector2(130, 460), Vector2(305, 460)]
var textures: Dictionary = {}
var road_font: Font
var road_font_size: int = 12
var profile_textures: Dictionary = {}
var road_cache_round: int = 0
var road_visual_cache: Dictionary = {}
var _static_map: Node2D
var _environment_details: Array[Dictionary] = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	road_font = PixelFont.create()
	road_font_size = PixelFont.BASE_SIZE
	for key: String in ["tilemap_flat", "castle", "wood_tower", "tree", "explosions"]:
		textures[key] = load("res://game/assets/tiny_swords/" + key + ".png")
	textures["soldier_bow"] = load("res://game/assets/tiny_rpg/soldier_bow.png")
	textures["arrow"] = load("res://game/assets/tiny_rpg/arrow.png")
	var exclusions: Array[Rect2] = [Rect2(640, 80, 300, 272)]
	for slot: int in range(tower_points.size()):
		exclusions.append(get_tower_visual_bounds(slot).grow(8))
	for tree: Dictionary in get_tree_visuals():
		exclusions.append(tree["destination"])
	for route: Dictionary in get_route_preview():
		var points: PackedVector2Array = route["points"]
		for index: int in range(points.size() - 1):
			exclusions.append(Rect2(points[index], Vector2.ZERO).expand(points[index + 1]).grow(32))
	_environment_details = MAP_DETAILS.field_details(exclusions)
	_static_map = STATIC_MAP_SCRIPT.new()
	_static_map.name = "StaticMap"
	_static_map.renderer = _draw_static_map
	add_child(_static_map)
	move_child(_static_map, 0)
	_static_map.invalidate()
	queue_redraw()

func get_road_label_layout(text: String, center: Vector2) -> Dictionary:
	var size: Vector2 = road_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, road_font_size)
	var ascent: float = road_font.get_ascent(road_font_size)
	var descent: float = road_font.get_descent(road_font_size)
	var baseline: Vector2 = Vector2(center.x - size.x * 0.5, center.y + (ascent - descent) * 0.5).round()
	return {"font": road_font, "font_size": road_font_size, "position": baseline, "bounds": Rect2(baseline - Vector2(0, ascent), Vector2(size.x, ascent + descent))}

func _draw_road_label(text: String, center: Vector2, color: Color, canvas: Node2D) -> void:
	var layout: Dictionary = get_road_label_layout(text, center)
	canvas.draw_string(layout["font"], layout["position"], text, HORIZONTAL_ALIGNMENT_LEFT, -1, layout["font_size"], color)

func emit_build_feedback(at: Vector2) -> void:
	feedback_requested.emit("build", at)

func prepare(levels: Array[int]) -> void:
	var incoming_levels: Array[int] = levels.duplicate()
	running = false
	ledger.reset()
	enemies.clear()
	corpses.clear()
	selected_tower = -1
	arrows.clear()
	flashes.clear()
	tower_levels.clear()
	tower_clocks.clear()
	archer_shoot_seconds.clear()
	archer_facing_left.clear()
	for slot: int in range(tower_points.size()):
		tower_levels.append(clampi(incoming_levels[slot], 0, 2) if slot < incoming_levels.size() else 0)
		tower_clocks.append(0.0)
		archer_shoot_seconds.append(0.0)
		archer_facing_left.append(false)
	selected_enemy = -1
	rally_seconds = 0.0
	queue_redraw()

func set_round_preview(value: int) -> void:
	if running:
		return
	_set_round(clampi(value, 1, 3))
	queue_redraw()

func _set_round(value: int) -> void:
	if round_index == value:
		return
	round_index = value
	if is_instance_valid(_static_map):
		_static_map.invalidate()

func get_route_preview() -> Array[Dictionary]:
	return [
		{"id": "upper", "label": "A", "points": PackedVector2Array([Vector2(16, 245), Vector2(635, 245), Vector2(635, 330), Vector2(710, 330)])},
		{"id": "lower", "label": "B", "points": PackedVector2Array([Vector2(16, 505), Vector2(650, 505), Vector2(650, 330), Vector2(710, 330)])}
	]

func get_tower_visual_bounds(slot: int) -> Rect2:
	if slot < 0 or slot >= tower_points.size():
		return Rect2()
	# Union of opaque pixels in all wood frames and both bow facings.
	return Rect2(tower_points[slot] + Vector2(-81, -163), Vector2(162, 168))

func get_building_footprints() -> Array[Rect2]:
	var footprints: Array[Rect2] = []
	for point: Vector2 in tower_points:
		footprints.append(Rect2(point - Vector2(65, 27), Vector2(130, 32)))
	footprints.append(Rect2(684, 285, 256, 32))
	return footprints

func get_tree_visuals() -> Array[Dictionary]:
	var trees: Array[Dictionary] = []
	for point: Vector2 in [Vector2(632, 352), Vector2(746, 352), Vector2(689, 358)]:
		trees.append({"destination": Rect2(point, Vector2(192, 192)), "source": Rect2(0, 0, 192, 192)})
	return trees


func get_environment_details() -> Array[Dictionary]:
	return _environment_details.duplicate(true)

func get_enemy_definition(kind: String) -> Dictionary:
	var definition: Dictionary = MonsterCatalog.get_definition(kind)
	if definition.is_empty():
		return {}
	definition["health"] = balance.get(kind + "_health")
	definition["speed"] = balance.get(kind + "_speed")
	definition["damage"] = balance.get(kind + "_castle_damage")
	definition["health_bar_offset"] = 42.0 if kind == "slime" else 82.0 if kind == "orc" else 62.0
	return definition

func _road_polygons(radius: float) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	for route: Dictionary in get_route_preview():
		var outlines: Array[PackedVector2Array] = Geometry2D.offset_polyline(route["points"], radius, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
		for outline: PackedVector2Array in outlines:
			var merged: bool = false
			for index: int in range(polygons.size()):
				var union: Array[PackedVector2Array] = Geometry2D.merge_polygons(polygons[index], outline)
				if union.size() == 1:
					polygons[index] = union[0]
					merged = true
					break
			if not merged:
				polygons.append(outline)
	return polygons

func get_road_visuals() -> Dictionary:
	if road_cache_round == round_index:
		return road_visual_cache
	var surfaces: Array[PackedVector2Array] = _road_polygons(ROAD_HALF_WIDTH)
	var patches: Array[Dictionary] = []
	var texture_size: Vector2 = textures["tilemap_flat"].get_size()
	for polygon: PackedVector2Array in surfaces:
		var bounds: Rect2 = Rect2(polygon[0], Vector2.ZERO)
		for point: Vector2 in polygon:
			bounds = bounds.expand(point)
		for x: int in range(floori(bounds.position.x / 64.0), ceili(bounds.end.x / 64.0)):
			for y: int in range(floori(bounds.position.y / 64.0), ceili(bounds.end.y / 64.0)):
				var origin: Vector2 = Vector2(x, y) * 64.0
				var cell: PackedVector2Array = PackedVector2Array([origin, origin + Vector2(64, 0), origin + Vector2(64, 64), origin + Vector2(0, 64)])
				for clipped: PackedVector2Array in Geometry2D.intersect_polygons(polygon, cell):
					var uvs: PackedVector2Array = PackedVector2Array()
					for point: Vector2 in clipped:
						uvs.append((ROAD_SOURCE.position + point - origin) / texture_size)
					patches.append({"points": clipped, "uvs": uvs})
	var entrances: Array[Dictionary] = []
	var directions: Array[Dictionary] = []
	for route: Dictionary in get_route_preview():
		var points: PackedVector2Array = route["points"]
		entrances.append({"label": route["label"], "spawn": points[0], "position": points[0] + Vector2(32, -58)})
		for index: int in range(1, points.size()):
			if points[index - 1].distance_to(points[index]) < 150.0:
				continue
			if index > 2:
				continue
			directions.append({"position": points[index - 1].lerp(points[index], 0.5), "direction": (points[index] - points[index - 1]).normalized()})
	road_visual_cache = {"source": ROAD_SOURCE, "surfaces": surfaces, "edges": _road_polygons(ROAD_HALF_WIDTH + 4.0), "patches": patches, "entrances": entrances, "directions": directions}
	road_cache_round = round_index
	return road_visual_cache

func start_wave(alarm: bool, levels: Array[int], value: int = 1) -> void:
	prepare(levels)
	_set_round(clampi(value, 1, 3))
	ledger.begin_wave(alarm, round_index, balance.wave_enemy_counts)
	next_id = 1
	spawn_clock = balance.first_spawn_delay
	running = true
	status_changed.emit()

func activate_rally() -> bool:
	if not running or not ledger.claim_rally(balance.rally_cooldown):
		return false
	rally_seconds = balance.rally_duration
	for slot: int in range(tower_points.size()):
		if tower_levels[slot] > 0:
			feedback_requested.emit("rally", to_global(tower_points[slot] - TOWER_FOOT + ARCHER_PLATFORM))
	status_changed.emit()
	return true

func remaining_enemies() -> int:
	return ledger.pending.size() + enemies.size()

func _select_tower_at(point: Vector2) -> bool:
	if running or not tower_selection_enabled or not visible:
		return false
	for slot: int in range(tower_points.size()):
		var hit: bool = point.distance_to(tower_points[slot] - Vector2(0, 10)) <= 32.0
		if tower_levels[slot] > 0:
			hit = hit or get_tower_visual_bounds(slot).has_point(point)
		if hit:
			selected_tower = slot
			tower_selected.emit(slot)
			queue_redraw()
			return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if _select_tower_at(point):
			get_viewport().set_input_as_handled()
			return
		if running:
			for id: int in enemies:
				if _enemy_is_targetable(enemies[id]) and enemies[id]["pos"].distance_to(point) < 40.0:
					selected_enemy = id
					queue_redraw()
					break
	if running and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		activate_rally()

func _process(delta: float) -> void:
	animation_clock += delta
	_update_corpses(delta)
	for slot: int in range(tower_points.size()):
		archer_shoot_seconds[slot] = maxf(0.0, archer_shoot_seconds[slot] - delta)
	if not running:
		queue_redraw()
		return
	ledger.tick(delta)
	rally_seconds = maxf(0.0, rally_seconds - delta)
	spawn_clock -= delta
	if spawn_clock <= 0.0 and not ledger.pending.is_empty():
		_spawn_enemy()
		spawn_clock = balance.spawn_interval
		if round_index > 1 and balance.later_round_spawn_intervals.size() >= 2:
			spawn_clock = balance.later_round_spawn_intervals[round_index - 2]
	_update_enemies(delta)
	if not running:
		return
	_update_towers(delta)
	_update_arrows(delta)
	for flash: Dictionary in flashes:
		flash["life"] -= delta
	flashes = flashes.filter(func(flash: Dictionary) -> bool: return flash["life"] > 0.0)
	if ledger.is_complete() and corpses.is_empty():
		running = false
		wave_completed.emit()
	status_changed.emit()
	queue_redraw()

func _spawn_enemy() -> void:
	var kind: String = ledger.spawn_next(next_id)
	if kind.is_empty():
		return
	var definition: Dictionary = get_enemy_definition(kind)
	if definition.is_empty():
		ledger.mark_dead(next_id)
		next_id += 1
		return
	var health: int = definition["health"]
	var routes: Array[Dictionary] = get_route_preview()
	var route: Dictionary = routes[(next_id - 1) % routes.size()]
	var points: PackedVector2Array = route["points"].duplicate()
	var length: float = 0.0
	for index: int in range(1, points.size()):
		length += points[index].distance_to(points[index - 1])
	enemies[next_id] = {"pos": points[0], "hp": health, "max_hp": health, "kind": kind, "speed": definition["speed"], "castle_damage": definition["damage"], "health_bar_offset": definition["health_bar_offset"], "clock": 0.0, "animation_clock": 0.0, "action": "walk", "action_elapsed": 0.0, "hurt_left": 0.0, "attack_applied": false, "route_id": route["id"], "points": points, "waypoint": 1, "traveled": 0.0, "path_length": length, "progress": 0.0, "arrived": false, "facing_left": false}
	var revival: RefCounted = VampireRevivalScript.new()
	revival.reset(kind)
	enemies[next_id]["revival"] = revival
	enemies[next_id]["revive_protection_left"] = 0.0
	enemies[next_id]["revive_attack_grace_left"] = 0.0
	next_id += 1

func _update_enemies(delta: float) -> void:
	delta = maxf(0.0, delta)
	for id: int in enemies.keys():
		var enemy: Dictionary = enemies[id]
		var revival: RefCounted = enemy.get("revival") as RefCounted
		if revival != null and revival.pending:
			if revival.advance(delta):
				_complete_enemy_revival(enemy)
			continue
		enemy["revive_protection_left"] = maxf(0.0, enemy.get("revive_protection_left", 0.0) - delta)
		if enemy.get("revive_attack_grace_left", 0.0) > 0.0:
			enemy["revive_attack_grace_left"] = maxf(0.0, enemy["revive_attack_grace_left"] - delta)
			continue
		var pos: Vector2 = enemy["pos"]
		var points: PackedVector2Array = enemy["points"]
		enemy["animation_clock"] += delta
		enemy["action_elapsed"] += delta
		enemy["damage_flash_left"] = maxf(0.0, enemy.get("damage_flash_left", 0.0) - delta)
		if enemy.get("hurt_left", 0.0) > 0.0:
			enemy["hurt_left"] = maxf(0.0, enemy["hurt_left"] - delta)
		enemy["clock"] += delta
		if pos.distance_to(points[points.size() - 1]) < 0.01:
			if not enemy["arrived"]:
				enemy["clock"] = 0.0
				enemy["attack_applied"] = false
				_set_enemy_action(enemy, "attack")
			enemy["arrived"] = true
			enemy["progress"] = 1.0
		if not enemy["arrived"]:
			_set_enemy_action(enemy, "walk")
			var remaining_step: float = maxf(0.0, delta) * enemy["speed"]
			while remaining_step > 0.0 and enemy["waypoint"] < points.size():
				var target: Vector2 = points[enemy["waypoint"]]
				var distance: float = pos.distance_to(target)
				var moved: float = minf(distance, remaining_step)
				enemy["facing_left"] = target.x < pos.x
				pos = pos.move_toward(target, moved)
				enemy["traveled"] += moved
				remaining_step -= moved
				if distance <= moved:
					enemy["waypoint"] += 1
				else:
					break
			enemy["pos"] = pos
			enemy["progress"] = minf(1.0, enemy["traveled"] / maxf(1.0, enemy["path_length"]))
		else:
			var cycle_interval: float = balance.vampire_castle_attack_interval if enemy["kind"] == "vampire" else balance.castle_attack_interval
			if enemy["clock"] >= cycle_interval:
				enemy["clock"] = 0.0
				enemy["attack_applied"] = false
				_set_enemy_action(enemy, "attack", true)
			var duration: float = MonsterCatalog.action_duration(enemy["kind"], "attack")
			_set_enemy_action(enemy, "idle" if enemy["clock"] >= duration else "attack")
			if enemy["action"] == "attack":
				var windows: Array[Vector2] = MonsterCatalog.attack_windows(enemy["kind"])
				var hits: Dictionary = enemy.get("applied_hits", {})
				for index: int in range(windows.size()):
					var elapsed: float = enemy["action_elapsed"]
					if hits.has(index) or elapsed + 0.00001 < windows[index].x or maxf(0.0, elapsed - delta) >= windows[index].y:
						continue
					hits[index] = true
					enemy["applied_hits"] = hits
					enemy["attack_applied"] = true
					if enemy["kind"] == "vampire":
						enemy["hp"] = mini(enemy["max_hp"], enemy["hp"] + maxi(0, balance.vampire_drain_heal))
					flashes.append({"pos": Vector2(746, 314), "life": 0.45})
					feedback_requested.emit("castle_hit", to_global(Vector2(746, 314)))
					castle_damaged.emit(enemy["castle_damage"])
					if not running:
						return

func _complete_enemy_revival(enemy: Dictionary) -> void:
	enemy["hp"] = enemy["max_hp"]
	enemy["clock"] = 0.0
	enemy["animation_clock"] = 0.0
	enemy["hurt_left"] = 0.0
	enemy["damage_flash_left"] = 0.0
	enemy["attack_applied"] = false
	enemy["applied_hits"] = {}
	enemy["revive_protection_left"] = REVIVE_PROTECTION
	enemy["revive_attack_grace_left"] = REVIVE_ATTACK_GRACE
	_set_enemy_action(enemy, "idle" if enemy["arrived"] else "walk", true)

func _set_enemy_action(enemy: Dictionary, action: String, restart: bool = false) -> void:
	if action in ["walk", "idle", "attack"] and enemy.get("hurt_left", 0.0) > 0.0:
		return
	if enemy.get("action", "") != action or restart:
		enemy["action"] = action
		enemy["action_elapsed"] = 0.0
		if action == "attack":
			enemy["applied_hits"] = {}

func _update_corpses(delta: float) -> void:
	for corpse: Dictionary in corpses:
		corpse["action_elapsed"] += maxf(0.0, delta)
	corpses = corpses.filter(func(corpse: Dictionary) -> bool: return corpse["action_elapsed"] < corpse["death_duration"])

func get_archer_muzzle(slot: int) -> Vector2:
	if slot < 0 or slot >= tower_points.size():
		return Vector2.ZERO
	var platform: Vector2 = tower_points[slot] - TOWER_FOOT + ARCHER_PLATFORM
	return platform + Vector2(-8 if archer_facing_left[slot] else 8, -10) * balance.archer_scale

func get_arrow_layer() -> Dictionary:
	var frame_size: Vector2 = textures["arrow"].get_size()
	return {"source": Rect2(Vector2.ZERO, frame_size), "destination": Rect2(-frame_size, frame_size * 2.0)}

func get_tower_layers(slot: int) -> Array[Dictionary]:
	if slot < 0 or slot >= tower_points.size():
		return []
	var tower_position: Vector2 = tower_points[slot] - TOWER_FOOT
	var platform: Vector2 = tower_position + ARCHER_PLATFORM
	var archer_size: Vector2 = Vector2(100, 100) * balance.archer_scale
	var frame: int = 0
	if archer_shoot_seconds[slot] > 0.0:
		var elapsed: float = balance.archer_shoot_duration - archer_shoot_seconds[slot]
		if elapsed < 0.09999:
			frame = 7
		elif elapsed < 0.19999:
			frame = 8
	var destination: Rect2 = Rect2(platform - ARCHER_FOOT * balance.archer_scale, archer_size)
	if archer_facing_left[slot]:
		destination.size.x *= -1
	return [
		{"texture_key": "wood_tower", "destination": Rect2(tower_position, Vector2(256, 192)), "source": Rect2(int(animation_clock * 4.0) % 4 * 256, 0, 256, 192)},
		{"texture_key": "soldier_bow", "destination": destination, "source": Rect2(frame * 100, 0, 100, 100)},
		{"texture_key": "wood_tower", "destination": Rect2(tower_position + Vector2(0, 70), Vector2(256, 122)), "source": Rect2(int(animation_clock * 4.0) % 4 * 256, 70, 256, 122)}
	]

func _update_towers(delta: float) -> void:
	for slot: int in range(tower_points.size()):
		if tower_levels[slot] <= 0:
			continue
		tower_clocks[slot] -= delta
		if tower_clocks[slot] > 0:
			continue
		var target: int = _choose_target(tower_points[slot])
		if target < 0:
			continue
		archer_facing_left[slot] = enemies[target]["pos"].x < tower_points[slot].x
		archer_shoot_seconds[slot] = balance.archer_shoot_duration
		var muzzle: Vector2 = get_archer_muzzle(slot)
		var damage: int = balance.tower_level_one_damage if tower_levels[slot] == 1 else balance.tower_level_two_damage
		var direction: Vector2 = enemies[target]["pos"] - Vector2(0, 18) - muzzle
		arrows.append({"pos": muzzle, "target": target, "damage": damage, "angle": direction.angle()})
		feedback_requested.emit("tower_shot", to_global(muzzle))
		var interval: float = balance.tower_level_one_interval if tower_levels[slot] == 1 else balance.tower_level_two_interval
		tower_clocks[slot] = interval * (balance.rally_interval_factor if rally_seconds > 0.0 else 1.0)

func _choose_target(tower_point: Vector2) -> int:
	if enemies.has(selected_enemy) and _enemy_is_targetable(enemies[selected_enemy]):
		var selected_pos: Vector2 = enemies[selected_enemy]["pos"]
		if selected_pos.distance_to(tower_point) < balance.tower_range:
			return selected_enemy
	var best: int = -1
	var furthest: float = -1.0
	for id: int in enemies:
		if not _enemy_is_targetable(enemies[id]):
			continue
		var pos: Vector2 = enemies[id]["pos"]
		var progress: float = enemies[id].get("progress", 0.0)
		if pos.distance_to(tower_point) < balance.tower_range and progress > furthest:
			best = id
			furthest = progress
	return best

func _enemy_is_targetable(enemy: Dictionary) -> bool:
	if enemy.get("hp", 0) <= 0 or enemy.get("revive_protection_left", 0.0) > 0.00001:
		return false
	var revival: RefCounted = enemy.get("revival") as RefCounted
	return revival == null or not revival.pending

func _update_arrows(delta: float) -> void:
	var retained: Array[Dictionary] = []
	for arrow: Dictionary in arrows:
		var target: int = arrow["target"]
		if not enemies.has(target) or not _enemy_is_targetable(enemies[target]) or arrow.get("damage", 0) <= 0:
			continue
		var pos: Vector2 = arrow["pos"]
		var destination: Vector2 = enemies[target]["pos"] - Vector2(0, 18)
		arrow["angle"] = (destination - pos).angle()
		pos = pos.move_toward(destination, delta * balance.arrow_speed)
		if pos.distance_to(destination) < 9.0:
			feedback_requested.emit("enemy_hit", to_global(destination))
			enemies[target]["hp"] -= arrow["damage"]
			if enemies[target]["arrived"]:
				enemies[target]["damage_flash_left"] = 0.15
			else:
				enemies[target]["hurt_left"] = MonsterCatalog.action_duration(enemies[target]["kind"], "hurt")
				_set_enemy_action(enemies[target], "hurt", true)
			if enemies[target]["hp"] <= 0:
				feedback_requested.emit("enemy_death", to_global(enemies[target]["pos"]))
				var revival: RefCounted = enemies[target].get("revival") as RefCounted
				if revival != null and revival.begin_defeat():
					enemies[target]["hp"] = 0
					enemies[target]["hurt_left"] = 0.0
					enemies[target]["damage_flash_left"] = 0.0
					enemies[target]["clock"] = 0.0
					enemies[target]["attack_applied"] = false
					enemies[target]["applied_hits"] = {}
					_set_enemy_action(enemies[target], "death", true)
					if selected_enemy == target:
						selected_enemy = -1
					continue
				var corpse: Dictionary = enemies[target].duplicate(true)
				_set_enemy_action(corpse, "death", true)
				corpse["death_duration"] = 1.1 if corpse["kind"] == "skull" else MonsterCatalog.action_duration(corpse["kind"], "death") + 0.2
				corpses.append(corpse)
				enemies.erase(target)
				ledger.mark_dead(target)
				if selected_enemy == target:
					selected_enemy = -1
		else:
			arrow["pos"] = pos
			retained.append(arrow)
	arrows = retained.filter(func(arrow: Dictionary) -> bool:
		var target: int = arrow["target"]
		return enemies.has(target) and _enemy_is_targetable(enemies[target])
	)

func get_enemy_visual(enemy: Dictionary) -> Dictionary:
	var revival: RefCounted = enemy.get("revival") as RefCounted
	var pending: bool = revival != null and revival.pending
	var sampled: Dictionary = revival.sample() if pending else MonsterCatalog.sample(enemy.get("kind", ""), enemy.get("action", "walk"), enemy.get("action_elapsed", 0.0))
	return {"sample": sampled, "show_health_bar": not pending and enemy.get("action", "") != "death" and enemy.get("hp", 0) > 0, "lives_left": revival.lives_left if revival != null else 1}

func _draw_enemy(enemy: Dictionary) -> void:
	var pos: Vector2 = enemy["pos"]
	var definition: Dictionary = get_enemy_definition(enemy["kind"])
	if definition.is_empty():
		return
	var destination: Rect2 = Rect2(pos - definition["foot_anchor"] * definition["display_scale"], Vector2(definition["frame_size"]) * definition["display_scale"])
	if enemy["facing_left"]:
		destination.size.x *= -1
	var visual: Dictionary = get_enemy_visual(enemy)
	var sampled: Dictionary = visual["sample"]
	if sampled.is_empty():
		return
	var path: String = sampled["path"]
	if not profile_textures.has(path):
		profile_textures[path] = load(path)
	var modulation: Color = Color.WHITE
	if enemy.get("action", "") == "hurt" or enemy.get("damage_flash_left", 0.0) > 0.0:
		modulation = Color(1.0, 0.65, 0.65)
	if enemy["kind"] == "skull":
		destination.position.y -= sin(enemy["animation_clock"] * 5.0) * 3.0
		if enemy.get("action", "") == "death":
			modulation.a = maxf(0.0, 1.0 - enemy["action_elapsed"] / enemy["death_duration"])
	draw_texture_rect_region(profile_textures[path], destination, sampled["source"], modulation)
	if not visual["show_health_bar"]:
		return
	var ratio: float = (enemy["hp"] as float) / (enemy["max_hp"] as float)
	var bar_at: Vector2 = pos - Vector2(22, enemy["health_bar_offset"])
	draw_rect(Rect2(bar_at, Vector2(44, 5)), Color(0.15, 0.1, 0.1))
	draw_rect(Rect2(bar_at, Vector2(44 * ratio, 5)), Color(0.91, 0.26, 0.2))
	if enemy["kind"] == "vampire":
		for life: int in range(2):
			var color: Color = Color(0.94, 0.28, 0.32) if life < visual["lives_left"] else Color(0.3, 0.2, 0.2)
			draw_rect(Rect2(bar_at + Vector2(life * 8, 8), Vector2(5, 4)), color)

func get_draw_order() -> Array[Dictionary]:
	var actors: Array[Dictionary] = [{"type": "castle", "ground_y": 330.0}]
	for slot: int in range(tower_points.size()):
		if tower_levels[slot] > 0:
			actors.append({"type": "tower", "slot": slot, "ground_y": tower_points[slot].y})
	for id: int in enemies:
		actors.append({"type": "enemy", "id": id, "ground_y": enemies[id]["pos"].y})
	for index: int in range(corpses.size()):
		actors.append({"type": "corpse", "id": index, "ground_y": corpses[index]["pos"].y})
	actors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(a["ground_y"], b["ground_y"]):
			return a["type"] != "enemy" and b["type"] == "enemy"
		return a["ground_y"] < b["ground_y"]
	)
	return actors

func _draw_static_map(canvas: Node2D) -> void:
	if textures.is_empty():
		return
	var tile: Texture2D = textures["tilemap_flat"]
	for x: int in range(15):
		for y: int in range(9):
			var tint: Color = Color(0.85, 0.96, 0.82).lerp(Color(0.94, 0.98, 0.88), ((x * 3 + y * 7) % 5) / 5.0)
			canvas.draw_texture_rect_region(tile, Rect2(x * 64, y * 64, 64, 64), Rect2(64, 64, 64, 64), tint)
	_draw_roads(tile, canvas)
	for detail: Dictionary in _environment_details:
		MAP_DETAILS.draw_detail(canvas, detail)
	for tree: Dictionary in get_tree_visuals():
		canvas.draw_texture_rect_region(textures["tree"], tree["destination"], tree["source"])

func _draw() -> void:
	if textures.is_empty():
		return
	for slot: int in range(tower_points.size()):
		var foot: Vector2 = tower_points[slot]
		if tower_levels[slot] <= 0:
			var center: Vector2 = foot - Vector2(0, 10)
			draw_circle(center, 28, Color(0.16, 0.24, 0.16, 0.65))
			draw_arc(center, 28, 0, TAU, 32, Color(0.92, 0.82, 0.48, 0.9), 3.0)
			var digit: String = str(slot + 1)
			var width: float = road_font.get_string_size(digit, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
			draw_string(road_font, (center + Vector2(-width * 0.5, 8)).round(), digit, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 0.94, 0.77))
	if selected_tower >= 0 and selected_tower < tower_points.size():
		draw_circle(tower_points[selected_tower], balance.tower_range, Color(0.25, 0.55, 0.85, 0.08))
		draw_arc(tower_points[selected_tower], balance.tower_range, 0, TAU, 96, Color(0.25, 0.55, 0.85, 0.45), 2.0)
	for actor: Dictionary in get_draw_order():
		if actor["type"] == "castle":
			draw_texture(textures["castle"], Vector2(640, 80))
		elif actor["type"] == "tower":
			var slot: int = actor["slot"]
			for layer: Dictionary in get_tower_layers(slot):
				draw_texture_rect_region(textures[layer["texture_key"]], layer["destination"], layer["source"])
			if tower_levels[slot] == 2:
				draw_circle(tower_points[slot] - Vector2(0, 155), 8.0, Color(1.0, 0.78, 0.22))
		elif actor["type"] == "corpse":
			_draw_enemy(corpses[actor["id"]])
		else:
			var id: int = actor["id"]
			_draw_enemy(enemies[id])
			if id == selected_enemy:
				draw_arc(enemies[id]["pos"], 28, 0, TAU, 32, Color(1, 0.88, 0.34), 3)
	for arrow: Dictionary in arrows:
		var point: Vector2 = arrow["pos"]
		draw_set_transform(point, arrow.get("angle", 0.0))
		var layer: Dictionary = get_arrow_layer()
		draw_texture_rect_region(textures["arrow"], layer["destination"], layer["source"])
		draw_set_transform(Vector2.ZERO)
	for flash: Dictionary in flashes:
		var frame: int = clampi(int((0.45 - flash["life"]) * 20.0), 0, 8)
		draw_texture_rect_region(textures["explosions"], Rect2(flash["pos"] - Vector2(96, 96), Vector2(192, 192)), Rect2(frame * 192, 0, 192, 192))

func _draw_roads(tile: Texture2D, canvas: Node2D) -> void:
	var visuals: Dictionary = get_road_visuals()
	for edge: PackedVector2Array in visuals["edges"]:
		canvas.draw_colored_polygon(edge, Color(0.35, 0.43, 0.21, 0.8))
		var closed: PackedVector2Array = edge.duplicate()
		closed.append(edge[0])
		canvas.draw_polyline(closed, Color(0.59, 0.61, 0.29, 0.65), 2.0)
	for surface: PackedVector2Array in visuals["surfaces"]:
		var closed: PackedVector2Array = surface.duplicate()
		closed.append(surface[0])
		canvas.draw_polyline(closed, Color(0.44, 0.36, 0.20), 3.0)
	for patch: Dictionary in visuals["patches"]:
		canvas.draw_polygon(patch["points"], PackedColorArray([Color(0.76, 0.66, 0.48)]), patch["uvs"], tile)
	for cue: Dictionary in visuals["directions"]:
		var at: Vector2 = cue["position"]
		var direction: Vector2 = cue["direction"]
		var normal: Vector2 = direction.orthogonal()
		canvas.draw_polyline(PackedVector2Array([at - direction * 4.0 - normal * 5.0, at + direction * 3.0, at - direction * 4.0 + normal * 5.0]), Color(0.34, 0.29, 0.18, 0.65), 2.0)
	for entrance: Dictionary in visuals["entrances"]:
		var at: Vector2 = entrance["position"]
		canvas.draw_line(at + Vector2(0, 8), at + Vector2(0, 24), Color(0.30, 0.22, 0.14), 5.0)
		canvas.draw_rect(Rect2(at - Vector2(16, 12), Vector2(32, 25)), Color(0.23, 0.20, 0.12))
		canvas.draw_rect(Rect2(at - Vector2(14, 10), Vector2(28, 21)), Color(0.47, 0.34, 0.18))
		_draw_road_label(entrance["label"], at, Color(1.0, 0.87, 0.55), canvas)

