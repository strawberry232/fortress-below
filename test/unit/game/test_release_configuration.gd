extends "res://addons/gut/test.gd"

const LocaleScript = preload("res://game/scripts/ui/game_locale.gd")


func test_project_name_matches_the_chinese_game_title() -> void:
	LocaleScript.install()
	assert_eq(ProjectSettings.get_setting("application/config/name"), TranslationServer.translate("UI_TITLE"), "The default window title matches the player-facing game name")


func test_windows_export_keeps_the_raw_locale_and_animation_data() -> void:
	var preset: ConfigFile = ConfigFile.new()
	var status: Error = preset.load("res://export_presets.cfg")
	assert_eq(status, OK, "A reproducible Windows export preset exists")
	if status != OK:
		return
	assert_eq(preset.get_value("preset.0", "platform", ""), "Windows Desktop")
	assert_eq(preset.get_value("preset.0.options", "binary_format/architecture", ""), "x86_64")
	var includes: PackedStringArray = str(preset.get_value("preset.0", "include_filter", "")).split(",", false)
	for path: String in ["docs/localization/game.zh.csv", "game/data/monsters/animation_profiles.json"]:
		assert_true(FileAccess.file_exists("res://" + path))
		assert_has(includes, path, "Raw runtime data must remain in the exported PCK")
	var locale_import: ConfigFile = ConfigFile.new()
	assert_eq(locale_import.load("res://docs/localization/game.zh.csv.import"), OK)
	assert_eq(locale_import.get_value("remap", "importer", ""), "keep", "The CSV reader requires the original file in exported games")
	var exclusions: String = preset.get_value("preset.0", "exclude_filter", "")
	assert_true(exclusions.contains("test/*"), "Unit and integration tests stay outside the playable build")
	assert_true(exclusions.contains("docs/verification/*"), "Development captures stay outside the playable build")
	assert_true(FileAccess.file_exists("res://game/assets/icons/game_icon.png"), "The release icon exists")
