extends RefCounted
class_name FortressDungeonLayouts


static func get_layout(level_index: int) -> Dictionary:
	var index: int = clampi(level_index, 0, 2)
	var layout: Dictionary = {"index": index, "name_key": "UI_DUNGEON_LEVEL_%d" % (index + 1)}
	match index:
		0:
			layout.merge({
				"rooms": [Rect2(32, 64, 256, 352), Rect2(352, 64, 288, 352), Rect2(704, 64, 288, 352)],
				"corridors": [Rect2(288, 224, 64, 64), Rect2(640, 224, 64, 64)],
				"gates": [Rect2(662, 224, 20, 64)],
				"player_start": Vector2(136, 288), "stairs": Vector2(144, 88), "exit_wall": Vector2(144, 48),
				"ordinary_chest": Vector2(224, 144), "sealed_chest": Vector2(416, 112),
				"key": Vector2(880, 144), "potions": [Vector2(544, 352)],
				"spikes": [Vector2(544, 256), Vector2(800, 320)],
				"guardians": [Vector2(448, 256), Vector2(592, 336)],
				"reward_guard": Vector2(832, 256), "guardian_kinds": ["skeleton", "slime"], "reward_kind": "skull"
			})
		1:
			layout.merge({
				"rooms": [Rect2(32, 224, 224, 192), Rect2(320, 64, 320, 288), Rect2(768, 64, 224, 224), Rect2(384, 384, 192, 64)],
				"corridors": [Rect2(192, 128, 64, 160), Rect2(224, 128, 128, 64), Rect2(640, 128, 128, 64), Rect2(448, 352, 64, 64)],
				"gates": [Rect2(694, 128, 20, 64)],
				"player_start": Vector2(112, 352), "stairs": Vector2(48, 248), "exit_wall": Vector2(48, 208),
				"ordinary_chest": Vector2(128, 272), "sealed_chest": Vector2(480, 416),
				"key": Vector2(896, 128), "potions": [Vector2(576, 272), Vector2(208, 384)],
				"spikes": [Vector2(352, 160), Vector2(496, 288), Vector2(864, 224)],
				"guardians": [Vector2(432, 208), Vector2(592, 128), Vector2(480, 288)],
				"reward_guard": Vector2(864, 192), "guardian_kinds": ["skeleton", "armored_skeleton", "slime"], "reward_kind": "skull"
			})
		2:
			layout.merge({
				"rooms": [Rect2(32, 64, 960, 64), Rect2(32, 128, 192, 288), Rect2(32, 352, 960, 64), Rect2(800, 128, 192, 288), Rect2(352, 160, 320, 160)],
				"corridors": [Rect2(224, 224, 128, 64), Rect2(672, 224, 128, 64)],
				"gates": [Rect2(726, 224, 20, 64), Rect2(774, 64, 20, 64), Rect2(774, 352, 20, 64)],
				"player_start": Vector2(112, 272), "stairs": Vector2(144, 88), "exit_wall": Vector2(144, 48),
				"ordinary_chest": Vector2(128, 160), "sealed_chest": Vector2(528, 96),
				"key": Vector2(928, 160), "potions": [Vector2(624, 192), Vector2(128, 384)],
				"spikes": [Vector2(352, 96), Vector2(640, 96), Vector2(480, 384), Vector2(864, 320)],
				"guardians": [Vector2(432, 240), Vector2(576, 272), Vector2(528, 208), Vector2(384, 288)],
				"reward_guard": Vector2(896, 256), "guardian_kinds": ["skeleton", "armored_skeleton", "skull", "slime"], "reward_kind": "vampire"
			})
	return layout
