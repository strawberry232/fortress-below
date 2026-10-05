extends SceneTree

const BOLT_SCRIPT: Script = preload("res://game/scripts/combat/fortress_enemy_projectile.gd")
const ENEMY_SCRIPT: Script = preload("res://game/scripts/combat/fortress_skeleton.gd")


func _initialize() -> void:
	_capture.call_deferred()


func _vector(value: Vector2) -> Array[float]:
	return [value.x, value.y]


func _rect(value: Rect2) -> Array[float]:
	return [value.position.x, value.position.y, value.size.x, value.size.y]


func _animation(sprite: AnimatedSprite2D, animation: String) -> Dictionary:
	var frames: SpriteFrames = sprite.sprite_frames
	var result: Dictionary = {
		"animation": animation,
		"loop": frames.get_animation_loop(animation),
		"fps": frames.get_animation_speed(animation),
		"frame_count": frames.get_frame_count(animation),
		"scale": _vector(sprite.scale),
		"offset": _vector(sprite.position),
		"nearest": sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"frames": []
	}
	for index: int in range(frames.get_frame_count(animation)):
		var atlas: AtlasTexture = frames.get_frame_texture(animation, index) as AtlasTexture
		result["frames"].append({
			"index": index,
			"region": _rect(atlas.region),
			"source": atlas.atlas.resource_path,
			"source_size": _vector(atlas.atlas.get_size())
		})
	return result


func _capture() -> void:
	var output_path: String = "res://docs/verification/v15/runtime-blue-fx.json"
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(arguments.size() - 1):
		if arguments[index] == "--output":
			output_path = arguments[index + 1]
	var world: Node2D = Node2D.new()
	root.add_child(world)
	var bolt: Node2D = BOLT_SCRIPT.new()
	world.add_child(bolt)
	bolt.set_physics_process(false)
	var flight: AnimatedSprite2D = bolt.get_node("BoltSprite") as AnimatedSprite2D
	var payload: Dictionary = {
		"runtime_capture": true,
		"engine": Engine.get_version_info()["string"],
		"project_root": ProjectSettings.globalize_path("res://"),
		"bolt_pausable": bolt.process_mode == Node.PROCESS_MODE_INHERIT,
		"bolt_inherits_dungeon_lifecycle": bolt.process_mode == Node.PROCESS_MODE_INHERIT,
		"bolt": _animation(flight, "flight")
	}
	bolt._spawn_impact()
	var impact: AnimatedSprite2D = world.get_node("SkullImpact") as AnimatedSprite2D
	payload["impact"] = _animation(impact, "impact")
	var skull: CharacterBody2D = ENEMY_SCRIPT.new()
	skull.configure_kind("skull")
	world.add_child(skull)
	skull.set_physics_process(false)
	var cast: Sprite2D = skull._cast_sprite
	var cast_frames: Array[Dictionary] = []
	for index: int in range(8):
		skull._attack_elapsed = (index + 0.5) * skull.SKULL_CHARGE_TIME / 8.0
		skull._update_cast_visual()
		cast_frames.append({"index": index, "region": _rect(cast.region_rect), "visible": cast.visible})
	payload["cast"] = {
		"source": cast.texture.resource_path,
		"source_size": _vector(cast.texture.get_size()),
		"region_enabled": cast.region_enabled,
		"nearest_inherited": skull.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"scale": _vector(cast.scale),
		"offset": _vector(cast.position),
		"duration": skull.SKULL_CHARGE_TIME,
		"frame_count": cast_frames.size(),
		"loop": false,
		"frames": cast_frames
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path).get_base_dir())
	var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Unable to write runtime blue FX capture")
		world.queue_free()
		quit(1)
		return
	file.store_string(JSON.stringify(payload, "  ") + "\n")
	file.close()
	print("V15_BLUE_FX_CAPTURE " + JSON.stringify({"output": output_path, "frame_counts": [8, 4, 8]}))
	world.queue_free()
	await process_frame
	quit(0)
