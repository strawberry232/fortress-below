extends RefCounted


static func field_details(exclusions: Array[Rect2]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: int in range(1, 18):
		for column: int in range(1, 30):
			var seed: int = column * 13 + row * 7
			var point: Vector2 = Vector2(column * 32 - 16, row * 32 + 8)
			var bounds: Rect2 = Rect2(point - Vector2(14, 10), Vector2(28, 22))
			if not _clear(bounds, exclusions):
				continue
			result.append({"position": point, "bounds": bounds, "kind": ["grass", "stones", "flowers"][seed % 3], "theme": "field", "seed": seed})
	return result


static func dungeon_details(layout: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var themes: Array[String] = ["mine", "prison", "sanctum"]
	var level: int = clampi(int(layout.get("index", 0)), 0, 2)
	var landmarks: Array[Vector2] = [layout["player_start"], layout["stairs"], layout["ordinary_chest"], layout["sealed_chest"], layout["key"]]
	for potion: Vector2 in layout["potions"]:
		landmarks.append(potion)
	for spike: Vector2 in layout["spikes"]:
		landmarks.append(spike)
	var exclusions: Array[Rect2] = []
	for corridor: Rect2 in layout["corridors"]:
		exclusions.append(corridor.grow(12))
	for gate: Rect2 in layout["gates"]:
		exclusions.append(gate.grow(24))
	var index: int = 0
	var seen: Dictionary = {}
	for room: Rect2 in layout["rooms"]:
		for point: Vector2 in [room.position + Vector2(32, 32), Vector2(room.end.x - 32, room.position.y + 32), room.end - Vector2(32, 32), Vector2(room.position.x + 32, room.end.y - 32)]:
			if seen.has(point):
				continue
			seen[point] = true
			var bounds: Rect2 = Rect2(point - Vector2(14, 12), Vector2(28, 24))
			if not room.encloses(bounds) or not _clear(bounds, exclusions):
				continue
			var near_landmark: bool = false
			for landmark: Vector2 in landmarks:
				if point.distance_to(landmark) <= 76.0:
					near_landmark = true
			if near_landmark:
				continue
			result.append({"position": point, "bounds": bounds, "kind": "timber" if level == 0 else "chains" if level == 1 else "runes", "theme": themes[level], "seed": index})
			index += 1
	return result


static func _clear(bounds: Rect2, exclusions: Array[Rect2]) -> bool:
	for excluded: Rect2 in exclusions:
		if bounds.intersects(excluded):
			return false
	return true


static func draw_detail(canvas: Node2D, detail: Dictionary) -> void:
	var at: Vector2 = detail["position"]
	var kind: String = detail["kind"]
	canvas.draw_rect(Rect2(at + Vector2(-14, 7), Vector2(28, 4)), Color(0.035, 0.045, 0.04, 0.25))
	match kind:
		"grass", "flowers":
			for index: int in range(5):
				var point: Vector2 = at + Vector2(index * 5 - 12, (index % 2) * 4)
				canvas.draw_rect(Rect2(point + Vector2(0, -6), Vector2(2, 10)), Color(0.23, 0.43, 0.23))
				canvas.draw_rect(Rect2(point + Vector2(-2, -4), Vector2(2, 4)), Color(0.42, 0.59, 0.28))
				if kind == "flowers" and index % 2 == 0:
					canvas.draw_rect(Rect2(point + Vector2(-2, -8), Vector2(6, 4)), Color(0.85, 0.80, 0.52))
		"stones":
			for index: int in range(3):
				var point: Vector2 = at + Vector2(index * 8 - 12, (index % 2) * 4)
				canvas.draw_rect(Rect2(point, Vector2(8, 6)), Color(0.30, 0.36, 0.33))
				canvas.draw_rect(Rect2(point + Vector2(2, 0), Vector2(6, 2)), Color(0.59, 0.61, 0.49))
		"timber":
			for index: int in range(3):
				var point: Vector2 = at + Vector2(-12, index * 6 - 9)
				canvas.draw_rect(Rect2(point, Vector2(24, 6)), Color(0.19, 0.12, 0.12))
				canvas.draw_rect(Rect2(point + Vector2(2, 0), Vector2(20, 2)), Color(0.42, 0.29, 0.23))
			canvas.draw_rect(Rect2(at + Vector2(-8, -10), Vector2(2, 20)), Color(0.13, 0.13, 0.17))
			canvas.draw_rect(Rect2(at + Vector2(6, -10), Vector2(2, 20)), Color(0.13, 0.13, 0.17))
		"chains":
			canvas.draw_rect(Rect2(at + Vector2(-14, -10), Vector2(28, 4)), Color(0.18, 0.20, 0.24))
			for index: int in range(3):
				for link: int in range(4):
					var point: Vector2 = at + Vector2(index * 10 - 12, link * 4 - 6)
					canvas.draw_rect(Rect2(point, Vector2(4, 4)), Color(0.38, 0.40, 0.43), false, 1.0)
		"runes":
			canvas.draw_rect(Rect2(at + Vector2(-12, -10), Vector2(24, 20)), Color(0.19, 0.16, 0.24))
			canvas.draw_rect(Rect2(at + Vector2(-10, -8), Vector2(20, 16)), Color(0.38, 0.28, 0.40), false, 2.0)
			for index: int in range(3):
				canvas.draw_rect(Rect2(at + Vector2(index * 6 - 8, -4), Vector2(2, 8)), Color(0.63, 0.43, 0.53))
				canvas.draw_rect(Rect2(at + Vector2(index * 6 - 8, -4), Vector2(4, 2)), Color(0.63, 0.43, 0.53))


static func torch_glow_shape(at: Vector2, radius: float, clip: Rect2) -> Array[PackedVector2Array]:
	if radius <= 0.0 or clip.size.x <= 0.0 or clip.size.y <= 0.0:
		return []
	var points: PackedVector2Array = PackedVector2Array()
	for corner: int in range(12):
		points.append((at + Vector2.from_angle(corner * TAU / 12.0) * radius).round())
	var boundary: PackedVector2Array = PackedVector2Array([clip.position, Vector2(clip.end.x, clip.position.y), clip.end, Vector2(clip.position.x, clip.end.y)])
	return Geometry2D.intersect_polygons(points, boundary)


static func draw_torch_glow(canvas: Node2D, at: Vector2, strength: float, clip: Rect2) -> void:
	for ring: int in range(5):
		var radius: float = 88.0 - ring * 14.0
		for points: PackedVector2Array in torch_glow_shape(at, radius, clip):
			canvas.draw_colored_polygon(points, Color(1.0, 0.61, 0.27, (0.022 + ring * 0.006) * strength))
