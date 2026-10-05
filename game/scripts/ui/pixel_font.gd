extends RefCounted

const SOURCE_PATH: String = "res://game/assets/fonts/fusion_pixel_12px_zh_hans.ttf"
const RUNTIME_PATH: String = "res://game/assets/fonts/optimized/fortress_pixel_12px_zh_hans.ttf"
const BASE_SIZE: int = 12


static func create() -> Font:
	var pixel_font: FontFile = _configured_font(RUNTIME_PATH)
	if pixel_font == null:
		return null
	pixel_font.resource_name = "Fusion Pixel 12px Simplified Chinese"
	return pixel_font


static func create_counter_font() -> Font:
	return create()


static func font_size(requested: int) -> int:
	return maxi(24, roundi((requested as float) / BASE_SIZE) * BASE_SIZE)


static func _configured_font(path: String) -> FontFile:
	var source: FontFile = load(path) as FontFile
	if source == null:
		push_error("The bundled pixel font could not be loaded: " + path)
		return null
	var pixel_font: FontFile = source.duplicate() as FontFile
	pixel_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	pixel_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	pixel_font.hinting = TextServer.HINTING_NONE
	pixel_font.oversampling = 1.0
	pixel_font.allow_system_fallback = false
	pixel_font.fallbacks = []
	return pixel_font
