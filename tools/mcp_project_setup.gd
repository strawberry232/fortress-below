extends RefCounted


func configure(settings_template_path: String = "res://config/mcp_settings.cfg",
		destination_path: String = "user://mcp_settings.cfg") -> Error:
	if not FileAccess.file_exists(settings_template_path):
		return ERR_FILE_NOT_FOUND
	var template: ConfigFile = ConfigFile.new()
	if template.load(settings_template_path) != OK or not _is_valid_template(template):
		return ERR_INVALID_DATA
	var port: int = template.get_value("settings", "http_port")
	if FileAccess.file_exists(destination_path):
		var existing: ConfigFile = ConfigFile.new()
		if existing.load(destination_path) != OK or not _is_compatible(existing, port):
			return ERR_ALREADY_IN_USE
		return OK
	var generated: ConfigFile = ConfigFile.new()
	generated.set_value("meta", "version", 1)
	generated.set_value("settings", "transport_mode", "http")
	generated.set_value("settings", "http_port", port)
	generated.set_value("settings", "auto_start", true)
	generated.set_value("settings", "allow_remote", false)
	generated.set_value("settings", "auth_enabled", false)
	generated.set_value("settings", "auth_token", "")
	return generated.save(destination_path)


func _is_valid_template(config: ConfigFile) -> bool:
	var version: Variant = _read_value(config, "meta", "version")
	if typeof(version) != TYPE_INT or version != 1:
		return false
	var transport: Variant = _read_value(config, "settings", "transport_mode")
	if typeof(transport) != TYPE_STRING or transport != "http":
		return false
	var port: Variant = _read_value(config, "settings", "http_port")
	if typeof(port) != TYPE_INT or port < 1024 or port > 65535:
		return false
	var auto_start: Variant = _read_value(config, "settings", "auto_start")
	if typeof(auto_start) != TYPE_BOOL or not auto_start:
		return false
	var allow_remote: Variant = _read_value(config, "settings", "allow_remote")
	return typeof(allow_remote) == TYPE_BOOL and not allow_remote


func _read_value(config: ConfigFile, section: String, key: String) -> Variant:
	if not config.has_section_key(section, key):
		return null
	return config.get_value(section, key)


func _is_compatible(config: ConfigFile, port: int) -> bool:
	if not _is_valid_template(config):
		return false
	if config.get_value("settings", "http_port") != port:
		return false
	var auth_enabled: Variant = config.get_value("settings", "auth_enabled", false)
	return typeof(auth_enabled) == TYPE_BOOL and not auth_enabled
