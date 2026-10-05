extends RefCounted

const CSV_PATH: String = "res://docs/localization/game.zh.csv"
const DEFAULT_LOCALE: String = "zh_CN"

static var _installed_translation: Translation


static func install() -> void:
	var file: FileAccess = FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		push_error("Unable to open the game translation CSV.")
		return
	var header: PackedStringArray = file.get_csv_line()
	if header != PackedStringArray(["keys", DEFAULT_LOCALE]):
		file.close()
		push_error("The game translation CSV has an invalid header.")
		return
	var translation: Translation = Translation.new()
	translation.set_locale(DEFAULT_LOCALE)
	while not file.eof_reached():
		var fields: PackedStringArray = file.get_csv_line()
		if fields.size() < 2 or fields[0].is_empty():
			continue
		translation.add_message(fields[0], fields[1])
	file.close()
	if _installed_translation != null:
		TranslationServer.remove_translation(_installed_translation)
	TranslationServer.add_translation(translation)
	_installed_translation = translation
	TranslationServer.set_locale(DEFAULT_LOCALE)
