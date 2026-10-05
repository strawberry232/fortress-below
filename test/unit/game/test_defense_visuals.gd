extends "res://addons/gut/test.gd"

const WorldScript = preload("res://game/scripts/defense/fortress_world.gd")

func after_each() -> void:
	for index: int in range(4):
		await get_tree().process_frame

func _world() -> WorldScript:
	var world: WorldScript = WorldScript.new()
	world.set_process(false)
	add_child_autofree(world)
	return world

func _visuals(world: WorldScript) -> Dictionary:
	assert_true(world.has_method("get_road_visuals"))
	if not world.has_method("get_road_visuals"):
		return {}
	return world.call("get_road_visuals")

func _on_surface(point: Vector2, polygons: Array) -> bool:
	for polygon: PackedVector2Array in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false

func test_native_twelve_pixel_road_font_fits_signs_and_centers_build_slot_digits() -> void:
	var world: WorldScript = _world()
	assert_eq(world.get("road_font_size"), 12, "The supplied 12px bitmap font must render at a native integer scale")
	assert_true(world.has_method("get_road_label_layout"))
	if not world.has_method("get_road_label_layout"):
		return
	var center: Vector2 = Vector2(48, 58)
	var sign_interior: Rect2 = Rect2(center - Vector2(14, 10), Vector2(28, 21))
	for text: String in ["A", "B", "I", "1", "2", "3", "4", "5", "6", "!"]:
		var layout: Dictionary = world.call("get_road_label_layout", text, center)
		assert_eq(layout["font_size"], 12)
		assert_eq(layout["font"], world.road_font, "Repeated drawing reuses the same cached font")
		assert_eq(layout["position"], layout["position"].round(), "Native pixel glyphs stay on integer pixel boundaries")
		var bounds: Rect2 = layout["bounds"]
		assert_gt(bounds.size.x, 0.0)
		assert_gt(bounds.size.y, 0.0)
		assert_true(sign_interior.encloses(bounds), "Route and slot labels fit the wooden sign with no clipping")
		assert_almost_eq(bounds.get_center().x, center.x, 0.51)
		assert_almost_eq(bounds.get_center().y, center.y, 0.51)
	var empty: Dictionary = world.call("get_road_label_layout", "", center)
	assert_eq(empty["bounds"].size.x, 0.0)
	assert_eq(empty["font"], world.road_font)

func test_tower_uses_original_bow_pose_at_integer_scale_and_no_old_archer() -> void:
	var world: WorldScript = _world()
	assert_eq(world.balance.archer_scale, 3.0)
	assert_false(world.textures.has("archer"))
	assert_true(world.textures.has("soldier_bow"))
	if not world.textures.has("soldier_bow"):
		return
	var texture: Texture2D = world.textures["soldier_bow"]
	assert_eq(texture.resource_path, "res://game/assets/tiny_rpg/soldier_bow.png")
	assert_eq(texture.get_size(), Vector2(900, 100))
	var layers: Array = world.get_tower_layers(0)
	assert_eq(layers[1]["texture_key"], "soldier_bow")
	assert_eq(layers[1]["source"], Rect2(0, 0, 100, 100))
	assert_eq(layers[1]["destination"].size, Vector2(300, 300))
	world.animation_clock = 7.3
	assert_eq(world.get_tower_layers(0)[1]["source"], layers[1]["source"], "Held bow idle must not replay the attack or wield a sword")

func test_immediate_arrow_starts_on_release_frame_then_recovers_without_delaying_attack() -> void:
	var world: WorldScript = _world()
	world.start_wave(false, [1, 0])
	world._spawn_enemy()
	world.enemies[1]["pos"] = Vector2(400, 330)
	world._update_towers(0.0)
	assert_eq(world.arrows.size(), 1, "Projectile remains immediate")
	assert_eq(world.get_tower_layers(0)[1]["source"], Rect2(700, 0, 100, 100))
	assert_almost_eq(world.tower_clocks[0], 0.9, 0.0001)
	world.archer_shoot_seconds[0] = world.balance.archer_shoot_duration - 0.1
	assert_eq(world.get_tower_layers(0)[1]["source"], Rect2(800, 0, 100, 100))
	world.archer_shoot_seconds[0] = world.balance.archer_shoot_duration - 0.2
	assert_eq(world.get_tower_layers(0)[1]["source"], Rect2(0, 0, 100, 100))
	assert_eq(world.arrows.size(), 1, "Visual recovery cannot create extra arrows")

func test_tower_arrow_uses_matching_original_projectile_and_centered_integer_scale() -> void:
	var world: WorldScript = _world()
	var arrow: Texture2D = world.textures["arrow"]
	assert_eq(arrow.resource_path, "res://game/assets/tiny_rpg/arrow.png")
	assert_true(world.has_method("get_arrow_layer"))
	if not world.has_method("get_arrow_layer"):
		return
	var layer: Dictionary = world.call("get_arrow_layer")
	assert_eq(layer["source"], Rect2(Vector2.ZERO, arrow.get_size()))
	assert_eq(layer["destination"].size, arrow.get_size() * 2.0)
	assert_eq(layer["destination"].get_center(), Vector2.ZERO)

func test_soldier_bow_feet_and_release_muzzle_remain_anchored_when_mirrored() -> void:
	var world: WorldScript = _world()
	for slot: int in range(world.tower_points.size()):
		var platform: Vector2 = world.tower_points[slot] - Vector2(128, 166) + Vector2(128, 75)
		world.archer_shoot_seconds[slot] = world.balance.archer_shoot_duration
		for facing: bool in [false, true]:
			world.archer_facing_left[slot] = facing
			var layers: Array = world.get_tower_layers(slot)
			var destination: Rect2 = layers[1]["destination"]
			assert_eq(destination.position + Vector2(150, 180), platform)
			assert_eq(destination.size.x, -300.0 if facing else 300.0)
			assert_eq(world.get_archer_muzzle(slot), platform + Vector2(-24 if facing else 24, -30))
			assert_eq(layers[2]["source"], Rect2(0, 70, 256, 122))

func test_textured_roads_cover_preserved_waypoints_and_merge_without_surface_gaps() -> void:
	var world: WorldScript = _world()
	for round_value: int in range(1, 4):
		world.set_round_preview(round_value)
		var visuals: Dictionary = _visuals(world)
		if visuals.is_empty():
			return
		assert_eq(visuals["source"], Rect2(384, 64, 64, 64))
		assert_eq(visuals["surfaces"].size(), 1, "Intersecting roads share one continuous surface")
		assert_gt(visuals["patches"].size(), 0)
		for route: Dictionary in world.get_route_preview():
			var points: PackedVector2Array = route["points"]
			for index: int in range(1, points.size()):
				assert_true(_on_surface(points[index - 1], visuals["surfaces"]))
				assert_true(_on_surface(points[index - 1].lerp(points[index], 0.5), visuals["surfaces"]))
		assert_true(_on_surface(Vector2(710, 330), visuals["surfaces"]))
		for patch: Dictionary in visuals["patches"]:
			assert_eq(patch["points"].size(), patch["uvs"].size())
			for uv: Vector2 in patch["uvs"]:
				assert_between(uv.x, 384.0 / 640.0 - 0.0001, 448.0 / 640.0 + 0.0001)
				assert_between(uv.y, 64.0 / 256.0 - 0.0001, 128.0 / 256.0 + 0.0001)
	world.set_round_preview(2)
	assert_eq(world.get_route_preview()[0]["points"], PackedVector2Array([Vector2(16, 245), Vector2(635, 245), Vector2(635, 330), Vector2(710, 330)]))
	assert_eq(world.get_route_preview()[1]["points"], PackedVector2Array([Vector2(16, 505), Vector2(650, 505), Vector2(650, 330), Vector2(710, 330)]))

func test_entry_signs_stay_outside_traffic_and_direction_cues_do_not_stack_at_merge() -> void:
	var world: WorldScript = _world()
	world.set_round_preview(2)
	var visuals: Dictionary = _visuals(world)
	if visuals.is_empty():
		return
	assert_eq(visuals["entrances"].size(), 2)
	assert_eq(visuals["entrances"][0]["label"], "A")
	assert_eq(visuals["entrances"][1]["label"], "B")
	for entrance: Dictionary in visuals["entrances"]:
		assert_false(_on_surface(entrance["position"], visuals["surfaces"]))
		assert_gte(entrance["position"].distance_to(entrance["spawn"]), 50.0)
	assert_between(visuals["directions"].size(), 1, 5)
	for index: int in range(visuals["directions"].size()):
		for other: int in range(index):
			assert_gte(visuals["directions"][index]["position"].distance_to(visuals["directions"][other]["position"]), 60.0)
