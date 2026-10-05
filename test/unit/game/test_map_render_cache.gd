extends "res://addons/gut/test.gd"

const DUNGEON: Script = preload("res://game/scripts/dungeon/dungeon_world.gd")
const DEFENSE: Script = preload("res://game/scripts/defense/fortress_world.gd")


func before_each() -> void:
	for action: String in ["fb_move_left", "fb_move_right", "fb_move_up", "fb_move_down", "fb_sword", "fb_bow", "fb_interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func _world(script: Script) -> Node2D:
	var world: Node2D = script.new()
	add_child_autofree(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	return world


func _static_layer(world: Node2D) -> Node2D:
	var layer: Node2D = world.get_node_or_null("StaticMap")
	assert_not_null(layer, "Map commands live in a separate canvas item behind dynamic visuals")
	return layer


func _floor_reference(layout: Dictionary, point: Vector2) -> bool:
	for key: String in ["rooms", "corridors"]:
		for region: Rect2 in layout[key]:
			if region.has_point(point):
				return true
	return false


func test_walkable_occupancy_matches_exact_region_edges_in_all_three_maps() -> void:
	var world: Node2D = _world(DUNGEON)
	assert_true(world.has_method("_rebuild_floor_cache"), "Walkable cells are rebuilt once per layout")
	if not world.has_method("_rebuild_floor_cache"):
		return
	for level: int in range(3):
		world.reset_run(level)
		var layout: Dictionary = world.get_level_info()
		for row: int in range(-1, 16):
			for column: int in range(-1, 33):
				for offset: Vector2 in [Vector2.ZERO, Vector2(0.001, 0.001), Vector2(16, 28), Vector2(31.999, 31.999)]:
					var point: Vector2 = Vector2(column, row) * 32.0 + offset
					assert_eq(world.is_walkable(point), _floor_reference(layout, point), "Cached floor preserves rectangle inclusion and exclusion")
		assert_eq(world._walkable_cells.size(), 480)
		assert_true(world._floor_grid_aligned)
		await get_tree().process_frame


func test_floor_cache_falls_back_for_non_aligned_rectangles_without_rounding_geometry() -> void:
	var world: Node2D = _world(DUNGEON)
	if not world.has_method("_rebuild_floor_cache"):
		assert_true(false, "Exact custom-layout fallback is available")
		return
	world._layout = {"rooms": [Rect2(33.5, 67.0, 21.25, 18.5)], "corridors": []}
	world._rebuild_floor_cache()
	assert_false(world._floor_grid_aligned)
	for point: Vector2 in [Vector2(33.499, 68), Vector2(33.5, 67), Vector2(54.749, 85.499), Vector2(54.75, 80), Vector2(40, 85.5), Vector2(-1, -1)]:
		assert_eq(world.is_walkable(point), _floor_reference(world._layout, point))
	world.reset_run(2)
	assert_true(world._floor_grid_aligned, "Retry discards custom floor regions and rebuilds the real level")
	await get_tree().process_frame


func test_walkable_query_is_available_before_the_world_enters_the_tree() -> void:
	var world: Node2D = DUNGEON.new()
	assert_true(world.is_walkable(Vector2(100, 200)))
	assert_false(world.is_walkable(Vector2.ZERO))
	assert_false(world.is_walkable(Vector2.INF))
	world.free()


func test_near_grid_edges_use_exact_rectangle_membership_instead_of_approximate_alignment() -> void:
	var world: Node2D = _world(DUNGEON)
	world._layout = {"rooms": [Rect2(32.000008, 64, 32, 32)], "corridors": []}
	world._rebuild_floor_cache()
	assert_false(world._floor_grid_aligned, "A small authored edge offset is still meaningful geometry")
	for point: Vector2 in [Vector2(32, 80), Vector2(32.000004, 80), Vector2(32.00001, 80), Vector2(64, 80), Vector2(64.000008, 80), Vector2(64.00002, 80), Vector2(48, 96)]:
		assert_eq(world.is_walkable(point), _floor_reference(world._layout, point))
	world.reset_run(0)
	assert_true(world._floor_grid_aligned)
	await get_tree().process_frame


func test_reset_before_ready_builds_selected_layout_without_requiring_a_static_canvas() -> void:
	var world: Node2D = DUNGEON.new()
	world.reset_run(2)
	assert_eq(world.get_level_info()["index"], 2)
	assert_true(world.is_walkable(Vector2(528, 96)), "The requested third layout is available before entering the tree")
	assert_false(world.is_walkable(Vector2(528, 144)), "The third layout's room boundary stays intact")
	assert_gt(world.get_navigation_path(world.player.position, world.stairs_position).size(), 0)
	assert_null(world.get_node_or_null("StaticMap"), "Canvas initialization remains in ready")
	add_child_autofree(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	assert_not_null(world.get_node_or_null("StaticMap"))
	assert_eq(world.get_level_info()["index"], 0, "Ready preserves the original default run initialization")
	await get_tree().process_frame


func test_dungeon_static_map_is_retained_while_chests_torches_doors_and_spikes_advance() -> void:
	var world: Node2D = _world(DUNGEON)
	var layer: Node2D = _static_layer(world)
	if layer == null:
		return
	assert_true(layer.show_behind_parent)
	assert_eq(layer.get_index(), 0)
	await get_tree().process_frame
	await get_tree().process_frame
	var revision: int = layer.revision
	var redraws: int = layer.redraw_count
	assert_gt(redraws, 0, "The static map produces real canvas commands")
	var closed_frame: int = world.get_chest_visual("ordinary")["frame"]
	world._physics_process(0.18)
	assert_ne(world.get_chest_visual("ordinary")["frame"], closed_frame)
	assert_eq(world.get_torch_visuals()[0]["frame"], 1)
	world._handle_interaction_at(world.ordinary_chest_position)
	world.confirm_sealed_chest()
	world._physics_process(0.25)
	assert_eq(world.get_chest_visual("ordinary")["frame"], 2)
	assert_eq(world.get_chest_visual("sealed")["frame"], 2)
	world._clock = 2.2
	assert_true(world.get_spike_visual(0)["active"])
	while world._middle_guardians > 0:
		world._on_middle_guardian_defeated()
	assert_true(world.get_gate_visuals()[0]["opened"])
	world.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(layer.revision, revision, "Dynamic gameplay does not invalidate floor and wall commands")
	assert_eq(layer.redraw_count, redraws, "Redrawing animation never rebuilds the 480-cell static map")


func test_reset_reuses_static_canvas_and_rebuilds_geometry_for_every_level_and_retry() -> void:
	var world: Node2D = _world(DUNGEON)
	var layer: Node2D = _static_layer(world)
	if layer == null:
		return
	for level: int in [1, 2, 0, 0]:
		var revision: int = layer.revision
		world.reset_run(level)
		assert_eq(world.get_node("StaticMap"), layer)
		assert_eq(layer.revision, revision + 1)
		assert_eq(world.get_level_info()["index"], level)
		assert_false(world.get_gate_visuals()[0]["opened"])
		assert_eq(world.get_chest_visual("ordinary")["state"], "closed")
		assert_true(world.is_walkable(world.player.position))
		assert_gt(world.get_navigation_path(world.player.position, world.stairs_position).size(), 0)
		assert_eq(layer.get_index(), 0)
		await get_tree().process_frame


func test_defense_background_stays_cached_during_animation_selection_and_building() -> void:
	var world: Node2D = _world(DEFENSE)
	var layer: Node2D = _static_layer(world)
	if layer == null:
		return
	assert_true(layer.show_behind_parent)
	await get_tree().process_frame
	await get_tree().process_frame
	var revision: int = layer.revision
	var redraws: int = layer.redraw_count
	assert_gt(redraws, 0)
	var levels: Array[int] = [1, 1, 0, 0, 0, 0]
	world.prepare(levels)
	world.tower_selection_enabled = true
	world._select_tower_at(world.tower_points[0])
	world._process(0.3)
	assert_eq(world.get_tower_layers(0)[0]["source"].position.x, 256.0)
	assert_eq(world.selected_tower, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(layer.revision, revision)
	assert_eq(layer.redraw_count, redraws, "Grass, both roads, and trees are not rebuilt for tower animation")
	var initial_routes: Array[Dictionary] = world.get_route_preview()
	for round_number: int in range(1, 4):
		world.set_round_preview(round_number)
		assert_eq(world.get_route_preview(), initial_routes)
		world.start_wave(false, levels, round_number)
		assert_eq(world.get_route_preview(), initial_routes)
		world.prepare(levels)
		await get_tree().process_frame


func test_static_layer_handles_missing_renderer_and_explicit_invalidation() -> void:
	var helper_path: String = "res://game/scripts/world/static_map_layer.gd"
	assert_true(ResourceLoader.exists(helper_path))
	if not ResourceLoader.exists(helper_path):
		return
	var helper: Script = load(helper_path)
	var layer: Node2D = helper.new()
	add_child_autofree(layer)
	layer.invalidate()
	assert_eq(layer.revision, 1)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(layer.redraw_count, 0, "Missing render callbacks safely produce an empty canvas")
