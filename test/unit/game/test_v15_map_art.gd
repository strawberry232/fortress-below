extends "res://addons/gut/test.gd"

const DUNGEON: Script = preload("res://game/scripts/dungeon/dungeon_world.gd")
const DEFENSE: Script = preload("res://game/scripts/defense/fortress_world.gd")

func before_each() -> void:
	for action: String in ["fb_move_left", "fb_move_right", "fb_move_up", "fb_move_down", "fb_sword", "fb_bow", "fb_interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

func _dungeon() -> Node2D:
	var world: Node2D = DUNGEON.new()
	add_child_autofree(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	return world

func test_decorative_trees_fit_inside_map_and_keep_road_clear() -> void:
	var world: Node2D = DEFENSE.new()
	add_child_autofree(world)
	world.set_process(false)
	var bounds: Rect2 = Rect2(0, 0, 960, 576)
	var trees: Array[Dictionary] = world.get_tree_visuals()
	assert_eq(trees.size(), 3, "The original three decorative trees remain")
	for tree: Dictionary in trees:
		var destination: Rect2 = tree["destination"]
		assert_true(bounds.encloses(destination), "Every tree canvas stays inside the field")
		var pixels: Image = world.textures["tree"].get_image().get_region(Rect2i(tree["source"]))
		var opaque: Rect2 = Rect2(pixels.get_used_rect())
		opaque.position += destination.position
		for route: Dictionary in world.get_route_preview():
			var points: PackedVector2Array = route["points"]
			for index: int in range(points.size() - 1):
				var segment: Rect2 = Rect2(points[index], Vector2.ZERO).expand(points[index + 1]).grow(23.0)
				assert_false(opaque.intersects(segment), "The moved tree's visible pixels cannot conceal an attack road")

func test_gate_visual_axis_matches_collision_and_authored_corridor_in_every_level() -> void:
	var world: Node2D = _dungeon()
	assert_true(world.has_method("get_gate_visuals"), "Door rendering exposes its real placement geometry")
	if not world.has_method("get_gate_visuals"):
		return
	for level: int in range(3):
		world.reset_run(level)
		await get_tree().process_frame
		var visuals: Array[Dictionary] = world.call("get_gate_visuals")
		var gates: Array = world.get_level_info()["gates"]
		assert_eq(visuals.size(), gates.size())
		for index: int in range(visuals.size()):
			assert_eq(visuals[index]["center"], gates[index].get_center())
			assert_eq(visuals[index]["axis"], "vertical")
			assert_eq(visuals[index]["rotation"], 0.0, "Dedicated side-facing door art preserves its pixel orientation")
			assert_true(visuals[index]["bounds"].encloses(gates[index]), "The wood spans the full blocked passage")
			assert_eq(visuals[index]["source"], Rect2(96, 64, 16, 32))

func test_gate_renderer_supports_both_axes_and_open_passage_without_rotating_collision() -> void:
	var world: Node2D = _dungeon()
	if not world.has_method("get_gate_visual"):
		assert_true(false, "Both hallway directions need deliberate door geometry")
		return
	var horizontal: Dictionary = world.call("get_gate_visual", Rect2(200, 200, 64, 20), false)
	assert_eq(horizontal["axis"], "horizontal")
	assert_eq(horizontal["rotation"], 0.0)
	assert_eq(horizontal["bounds"].get_center(), Vector2(232, 210))
	assert_eq(horizontal["bounds"].size, Vector2(64, 32))
	var opened: Dictionary = world.call("get_gate_visual", Rect2(200, 200, 20, 64), true)
	assert_eq(opened["source"], Rect2(112, 64, 16, 32))
	assert_eq(horizontal["source"], Rect2(96, 48, 32, 16))
	assert_eq(world.call("get_gate_visual", Rect2(), false), {})

func test_ordinary_and_sealed_chests_use_different_original_models_and_closed_animation() -> void:
	var world: Node2D = _dungeon()
	if not world.has_method("get_chest_visual"):
		assert_true(false, "Two chest families need their own original frame sets")
		return
	var ordinary: Dictionary = world.call("get_chest_visual", "ordinary")
	var sealed: Dictionary = world.call("get_chest_visual", "sealed")
	assert_eq(ordinary["texture"].resource_path, "res://game/assets/dungeon/items/mini_chest/mini_chest_1.png")
	assert_eq(sealed["texture"].resource_path, "res://game/assets/dungeon/items/chest/chest_1.png")
	assert_ne(ordinary["texture"], sealed["texture"])
	assert_eq(ordinary["state"], "closed")
	assert_eq(sealed["state"], "closed")
	world._clock = 0.18
	assert_eq(world.call("get_chest_visual", "ordinary")["frame"], 1)
	assert_eq(world.call("get_chest_visual", "sealed")["frame"], 1)
	assert_eq(world.call("get_chest_visual", "missing"), {})

func test_each_chest_plays_opening_once_holds_last_frame_and_resets_between_runs() -> void:
	var world: Node2D = _dungeon()
	if not world.has_method("get_chest_visual"):
		assert_true(false, "Opening actions need timed frames rather than one static swap")
		return
	watch_signals(world)
	world._clock = 1.0
	world._handle_interaction_at(world.ordinary_chest_position)
	assert_signal_emit_count(world, "loot_collected", 1)
	assert_eq(world.call("get_chest_visual", "ordinary")["state"], "opening")
	assert_eq(world.call("get_chest_visual", "ordinary")["frame"], 0)
	world.confirm_sealed_chest()
	world._clock = 1.25
	for kind: String in ["ordinary", "sealed"]:
		assert_eq(world.call("get_chest_visual", kind)["frame"], 2)
		assert_eq(world.call("get_chest_visual", kind)["state"], "opening")
	world._handle_interaction_at(world.ordinary_chest_position)
	world.confirm_sealed_chest()
	assert_signal_emit_count(world, "loot_collected", 1, "Opening animation never duplicates treasure")
	world._clock = 100.0
	for kind: String in ["ordinary", "sealed"]:
		assert_eq(world.call("get_chest_visual", kind)["frame"], 3)
		assert_eq(world.call("get_chest_visual", kind)["state"], "opened")
	world.reset_run(2)
	await get_tree().process_frame
	assert_eq(world.call("get_chest_visual", "ordinary")["state"], "closed")
	assert_eq(world.call("get_chest_visual", "sealed")["frame"], 0)

func test_exit_is_a_wall_ladder_with_reachable_floor_interaction() -> void:
	var world: Node2D = _dungeon()
	assert_true(world.has_method("get_exit_visual"), "Return-to-surface ladder exposes its attached wall and floor interaction")
	if not world.has_method("get_exit_visual"):
		return
	for level: int in range(3):
		world.reset_run(level)
		await get_tree().process_frame
		var exit_visual: Dictionary = world.call("get_exit_visual")
		assert_eq(exit_visual["source"], Rect2(144, 48, 16, 16))
		assert_eq(exit_visual["direction"], "up")
		assert_eq(exit_visual["interaction_position"], world.stairs_position)
		assert_false(world.is_walkable(exit_visual["destination"].get_center()))
		assert_gt(world.get_navigation_path(world.player.position, world.stairs_position).size(), 0)
		assert_eq(exit_visual["model"], "wall_ladder")

func test_map_draws_original_floor_and_wall_rims_with_empty_exterior() -> void:
	var world: Node2D = _dungeon()
	if not world.has_method("get_map_tile_visual"):
		assert_true(false, "The map should draw deliberate edges and leave distant exterior empty")
		return
	var floor_tile: Dictionary = world.call("get_map_tile_visual", Vector2i(3, 4))
	assert_eq(floor_tile["kind"], "floor")
	assert_true(Rect2(16, 16, 64, 48).encloses(floor_tile["source"]))
	assert_eq(world.call("get_map_tile_visual", Vector2i(0, 8))["source"], Rect2(0, 16, 16, 16))
	assert_eq(world.call("get_map_tile_visual", Vector2i(31, 8))["source"], Rect2(80, 16, 16, 16))
	assert_eq(world.call("get_map_tile_visual", Vector2i(5, 1))["source"].position.y, 0.0)
	assert_eq(world.call("get_map_tile_visual", Vector2i(5, 13))["source"].position.y, 64.0)
	assert_eq(world.call("get_map_tile_visual", Vector2i(31, 14)), {}, "Exterior corners are clear rather than repeated side pillars")
	assert_eq(world.call("get_map_tile_visual", Vector2i(-1, 0)), {})
	assert_eq(world.call("get_map_tile_visual", Vector2i(32, 15)), {})

func test_wall_torches_animate_from_original_four_frames_and_stay_on_wall() -> void:
	var world: Node2D = _dungeon()
	if not world.has_method("get_torch_visuals"):
		assert_true(false, "Reference wall lamps need their real original animation")
		return
	for level: int in range(3):
		world.reset_run(level)
		await get_tree().process_frame
		var torches: Array[Dictionary] = world.call("get_torch_visuals")
		assert_gt(torches.size(), 0)
		for torch: Dictionary in torches:
			assert_false(world.is_walkable(torch["location"]))
			assert_true(world.is_walkable(torch["location"] + Vector2(0, 32)))
			assert_true(torch["texture"].resource_path.begins_with("res://game/assets/dungeon/items/torch/torch_"))
			assert_true(Rect2(Vector2.ZERO, world.MAP_SIZE).encloses(torch["destination"]))
		world._clock = 0.25
		assert_eq(world.call("get_torch_visuals")[0]["frame"], 2)
