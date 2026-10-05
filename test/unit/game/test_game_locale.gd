extends "res://addons/gut/test.gd"

func test_chinese_locale_installs_and_is_idempotent() -> void:
	var path: String = "res://game/scripts/ui/game_locale.gd"
	assert_true(FileAccess.file_exists(path), "The localization implementation exists")
	if not FileAccess.file_exists(path):
		return
	var locale_script: GDScript = load(path)
	locale_script.install()
	assert_eq(TranslationServer.get_locale(), "zh_CN")
	var title: String = TranslationServer.translate("UI_TITLE")
	assert_ne(title, "UI_TITLE")
	assert_gt(title.length(), 0)
	var locales_before: PackedStringArray = TranslationServer.get_loaded_locales()
	locale_script.install()
	assert_eq(TranslationServer.get_loaded_locales(), locales_before)
	assert_eq(TranslationServer.translate("UI_TITLE"), title)

func test_locale_csv_has_unique_nonempty_translation_entries() -> void:
	var file: FileAccess = FileAccess.open("res://docs/localization/game.zh.csv", FileAccess.READ)
	assert_not_null(file)
	if file == null:
		return
	var header: PackedStringArray = file.get_csv_line()
	assert_eq(header, PackedStringArray(["keys", "zh_CN"]))
	var keys: Dictionary = {}
	while not file.eof_reached():
		var fields: PackedStringArray = file.get_csv_line()
		if fields.size() < 2:
			continue
		assert_false(keys.has(fields[0]), "Translation keys are unique")
		assert_true(fields[0].begins_with("UI_"))
		assert_gt(fields[1].length(), 0)
		keys[fields[0]] = true
	assert_true(keys.has("UI_START_CAMPAIGN"))
	assert_true(keys.has("UI_SEALED_DESCRIPTION"))

