extends "res://addons/gut/test.gd"

const DUNGEON: Script = preload("res://game/scripts/dungeon/dungeon_world.gd")
const FORTRESS: Script = preload("res://game/scripts/defense/fortress_world.gd")
const DETAILS: Script = preload("res://game/scripts/world/map_details.gd")

func before_each() -> void:
	for action: String in ["fb_move_left", "fb_move_right", "fb_move_up", "fb_move_down", "fb_sword", "fb_bow", "fb_interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

func _world(script: Script) -> Node:
	var world: Node = script.new()
	add_child_autofree(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	return world

func _supported(world: Node) -> bool:
	assert_true(world.has_method("get_environment_details"), "Environment details expose their safe placement")
	return world.has_method("get_environment_details")

func test_field_details_keep_both_roads_all_tower_sites_and_buildings_clear() -> void:
	var world: Node = _world(FORTRESS)
	if not _supported(world):
		return
	var routes: Array[Dictionary] = world.get_route_preview()
	var details: Array[Dictionary] = world.get_environment_details()
	assert_gt(details.size(), 12)
	assert_lt(details.size(), 70, "Decorations preserve broad empty battle space")
	for detail: Dictionary in details:
		var bounds: Rect2 = detail["bounds"]
		assert_true(Rect2(0, 0, 960, 576).encloses(bounds))
		for route: Dictionary in routes:
			var points: PackedVector2Array = route["points"]
			for index: int in range(points.size() - 1):
				assert_false(bounds.intersects(Rect2(points[index], Vector2.ZERO).expand(points[index + 1]).grow(32)))
		for slot: int in range(6):
			assert_false(bounds.intersects(world.get_tower_visual_bounds(slot).grow(8)))
	world.set_round_preview(3)
	assert_eq(world.get_route_preview(), routes)
	assert_eq(world.get_environment_details(), details, "Decoration placement is stable across rounds and retries")

func test_dungeon_themes_keep_interactions_corridors_and_navigation_unchanged() -> void:
	var world: Node = _world(DUNGEON)
	if not _supported(world):
		return
	var themes: Array[String] = []
	for level: int in range(3):
		world.reset_run(level)
		var layout: Dictionary = world.get_level_info()
		var details: Array[Dictionary] = world.get_environment_details()
		assert_gt(details.size(), 1)
		var positions: Dictionary = {}
		themes.append(details[0]["theme"])
		var landmarks: Array[Vector2] = [layout["player_start"], layout["stairs"], layout["ordinary_chest"], layout["sealed_chest"], layout["key"]]
		for potion: Vector2 in layout["potions"]:
			landmarks.append(potion)
		for detail: Dictionary in details:
			var bounds: Rect2 = detail["bounds"]
			assert_false(positions.has(bounds.get_center()), "Small rooms do not duplicate decorations")
			positions[bounds.get_center()] = true
			assert_true(world.is_walkable(bounds.get_center()))
			assert_true(Rect2(Vector2.ZERO, world.MAP_SIZE).encloses(bounds))
			for landmark: Vector2 in landmarks:
				assert_gt(bounds.get_center().distance_to(landmark), 64.0)
			for corridor: Rect2 in layout["corridors"]:
				assert_false(bounds.intersects(corridor.grow(12)))
		world.reset_run(level)
		assert_eq(world.get_environment_details(), details)
		assert_gt(world.get_navigation_path(world.player.position, world.stairs_position).size(), 0)
		await get_tree().process_frame
	assert_eq(themes, ["mine", "prison", "sanctum"])

func test_torch_glow_stays_inside_wall_and_floor_extent() -> void:
	var clip: Rect2 = Rect2(20, 30, 100, 80)
	var polygons: Array[PackedVector2Array] = DETAILS.torch_glow_shape(Vector2(25, 40), 88.0, clip)
	assert_gt(polygons.size(), 0)
	for polygon: PackedVector2Array in polygons:
		for point: Vector2 in polygon:
			assert_gte(point.x, clip.position.x)
			assert_lte(point.x, clip.end.x)
			assert_gte(point.y, clip.position.y)
			assert_lte(point.y, clip.end.y)
	assert_eq(DETAILS.torch_glow_shape(Vector2(-200, -200), 88.0, clip), [])
	assert_eq(DETAILS.torch_glow_shape(Vector2(25, 40), 0.0, clip), [])
	assert_eq(DETAILS.torch_glow_shape(Vector2(25, 40), 88.0, Rect2()), [])

func test_context_prompts_match_real_interactions_and_skip_consumed_objects() -> void:
	var world: Node = _world(DUNGEON)
	assert_true(world.has_method("get_interaction_hint"))
	if not world.has_method("get_interaction_hint"):
		return
	assert_eq(world.get_interaction_hint(Vector2(-10, -10)), {})
	assert_eq(world.get_interaction_hint(world.ordinary_chest_position)["key"], "UI_INTERACT_CHEST")
	world._handle_interaction_at(world.ordinary_chest_position)
	assert_eq(world.get_interaction_hint(world.ordinary_chest_position), {})
	assert_eq(world.get_interaction_hint(world.key_position)["key"], "UI_MSG_DEFEAT_GUARD")
	assert_false(world.get_interaction_hint(world.key_position)["actionable"])
	world._reward_guard_defeated = true
	assert_eq(world.get_interaction_hint(world.key_position)["key"], "UI_INTERACT_KEY")
	world._handle_interaction_at(world.key_position)
	assert_eq(world.get_interaction_hint(world.stairs_position)["key"], "UI_INTERACT_STAIRS")
	world._run_failed = true
	assert_eq(world.get_interaction_hint(world.stairs_position), {})
