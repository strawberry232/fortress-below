extends "res://addons/gut/test.gd"

const FONT_SCRIPT_PATH: String = "res://game/scripts/ui/pixel_font.gd"


func _make_font() -> Font:
	assert_true(FileAccess.file_exists(FONT_SCRIPT_PATH), "The user font helper exists")
	if not FileAccess.file_exists(FONT_SCRIPT_PATH):
		return null
	var helper: GDScript = load(FONT_SCRIPT_PATH)
	return helper.create()


func test_local_simplified_chinese_pixel_font_is_primary_without_fallback() -> void:
	var font: Font = _make_font()
	if font == null:
		return
	assert_true(font is FontFile)
	assert_eq(font.resource_name, "Fusion Pixel 12px Simplified Chinese")
	assert_true(font.data == FileAccess.get_file_as_bytes("res://game/assets/fonts/optimized/fortress_pixel_12px_zh_hans.ttf"), "Primary font bytes match the verified subset of the user's local original")
	assert_eq(font.antialiasing, TextServer.FONT_ANTIALIASING_NONE)
	assert_eq(font.subpixel_positioning, TextServer.SUBPIXEL_POSITIONING_DISABLED)
	assert_eq(font.fallbacks.size(), 0)
	assert_false(font.allow_system_fallback)


func test_current_chinese_ui_and_new_monster_names_have_real_glyphs() -> void:
	var font: Font = _make_font()
	if font == null:
		return
	var file: FileAccess = FileAccess.open("res://docs/localization/game.zh.csv", FileAccess.READ)
	assert_not_null(file)
	if file == null:
		return
	file.get_csv_line()
	var checked: Dictionary = {}
	while not file.eof_reached():
		var fields: PackedStringArray = file.get_csv_line()
		if fields.size() < 2:
			continue
		for character_index: int in range(fields[1].length()):
			var codepoint: int = fields[1].unicode_at(character_index)
			if codepoint <= 32 or checked.has(codepoint):
				continue
			checked[codepoint] = true
			assert_true(font.has_char(codepoint), "Localized glyph U+%04X is available" % codepoint)
	# Additional labels are stored as code points to keep code files ASCII-only.
	var new_codepoints: Array[int] = [0x9AB7, 0x9AC5, 0x91CD, 0x7532, 0x6D6E, 0x7A7A, 0x9B54, 0x9885, 0x5438, 0x8840, 0x9B3C, 0x54E5, 0x5E03, 0x6797, 0x70B8, 0x5F39, 0x91D1, 0x5E01, 0x5F13, 0x7BAD, 0x5854, 0x5C01, 0x5370, 0x589E, 0x63F4]
	for codepoint: int in new_codepoints:
		assert_true(font.has_char(codepoint), "New monster and economy glyph U+%04X is available" % codepoint)
	for slot: int in range(1, 7):
		assert_gt(font.get_string_size("%d A/B" % slot, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x, 0.0)


func test_font_instances_do_not_mutate_shared_fallback_lists() -> void:
	var first: Font = _make_font()
	var second: Font = _make_font()
	if first == null or second == null:
		return
	assert_ne(first.get_instance_id(), second.get_instance_id())
	first.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	assert_eq(second.antialiasing, TextServer.FONT_ANTIALIASING_NONE)
	assert_eq(second.fallbacks.size(), 0)
	assert_true(second.has_char(0x9AB7))


func test_pixel_font_keeps_latin_controls_and_counter_text_readable() -> void:
	var font: Font = _make_font()
	if font == null:
		return
	for codepoint: int in range(33, 127):
		assert_true(font.has_char(codepoint), "Control and numeric ASCII glyph U+%04X is available" % codepoint)
	assert_gt(font.get_string_size("WASD J K E 0123456789", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x, 0.0)
	assert_gt(font.get_height(24), 0.0)
	assert_eq(font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x, 12.0)
	assert_eq(font.get_string_size(String.chr(0x9AB7), HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x, 24.0)


func test_source_fonts_do_not_claim_chinese_coverage_they_lack() -> void:
	var helper: GDScript = load(FONT_SCRIPT_PATH)
	assert_eq(helper.BASE_SIZE, 12)
	var raw_font: FontFile = load("res://game/assets/fonts/tiny_unicode.ttf").duplicate()
	raw_font.allow_system_fallback = false
	raw_font.fallbacks = []
	assert_true(raw_font.has_char(0x0031))
	assert_false(raw_font.has_char(0x9AB7), "The supplied font cannot render the skeleton Han label alone")
	assert_false(raw_font.has_char(0x5E01), "The supplied font cannot render the currency Han label alone")

func test_pixel_font_size_snaps_to_integer_twelve_pixel_steps() -> void:
	var helper: GDScript = load(FONT_SCRIPT_PATH)
	assert_true(helper.has_method("font_size"))
	if not helper.has_method("font_size"):
		return
	for requested: int in [-12, 0, 14, 16, 17, 18, 20, 24, 29, 30, 44, 58]:
		var actual: int = helper.font_size(requested)
		assert_gte(actual, 24)
		assert_eq(actual % 12, 0)
		assert_eq(helper.font_size(actual), actual)
	assert_eq(helper.font_size(20), 24)
	assert_eq(helper.font_size(30), 36)
	assert_eq(helper.font_size(58), 60)

func test_hud_counter_font_uses_the_same_local_chinese_pixel_font() -> void:
	var helper: GDScript = load(FONT_SCRIPT_PATH)
	assert_true(helper.has_method("create_counter_font"))
	if not helper.has_method("create_counter_font"):
		return
	var counter: Font = helper.create_counter_font()
	assert_eq(counter.resource_name, "Fusion Pixel 12px Simplified Chinese")
	assert_true(counter.data == FileAccess.get_file_as_bytes("res://game/assets/fonts/optimized/fortress_pixel_12px_zh_hans.ttf"))
	assert_eq(counter.fallbacks.size(), 0)
	assert_true(counter.has_char(0x9AB7))
	assert_false(counter.allow_system_fallback)
