extends "res://addons/gut/test.gd"

const SETUP_SCRIPT_PATH: String = "res://tools/mcp_project_setup.gd"
const SETTINGS_MANAGER_PATH: String = "res://addons/godot_mcp/native_mcp/settings_manager.gd"
const TEMPLATE_PATH: String = "res://config/mcp_settings.cfg"
const TOKEN_SENTINEL: String = "test-only-token-must-never-be-copied"

var _setup: Variant = null
var _template_path: String = ""
var _destination_path: String = ""
var _temporary_paths: Array[String] = []
var _path_counter: int = 0


func before_each() -> void:
	_temporary_paths.clear()
	_template_path = _new_path("template")
	_destination_path = _new_path("destination")
	var setup_script: GDScript = load(SETUP_SCRIPT_PATH) as GDScript
	assert_not_null(setup_script, "The project setup script must exist")
	if setup_script != null:
		_setup = setup_script.new()
	_save_template(_valid_template())


func after_each() -> void:
	_setup = null
	for path: String in _temporary_paths:
		if FileAccess.file_exists(path):
			assert_eq(DirAccess.remove_absolute(path), OK, "Temporary test files must be removed")
	_temporary_paths.clear()


func _new_path(label: String) -> String:
	_path_counter += 1
	var path: String = "user://test_mcp_project_setup_%s_%s_%s.cfg" % [
		get_instance_id(), _path_counter, label
	]
	_temporary_paths.append(path)
	return path


func _valid_template(port: int = 9081) -> ConfigFile:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("meta", "version", 1)
	config.set_value("settings", "transport_mode", "http")
	config.set_value("settings", "http_port", port)
	config.set_value("settings", "auto_start", true)
	config.set_value("settings", "allow_remote", false)
	config.set_value("settings", "auth_enabled", false)
	config.set_value("settings", "auth_token", "")
	return config


func _save_template(config: ConfigFile) -> void:
	assert_eq(config.save(_template_path), OK, "The template fixture must be saved")


func _write_text(path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "The fixture must be writable")
	if file != null:
		file.store_string(content)
		file.close()


func _load_destination() -> ConfigFile:
	var config: ConfigFile = ConfigFile.new()
	assert_eq(config.load(_destination_path), OK, "The saved settings must be a valid ConfigFile")
	return config


func _assert_rejected_template(config: ConfigFile, message: String) -> void:
	_save_template(config)
	assert_eq(_setup.configure(_template_path, _destination_path), ERR_INVALID_DATA, message)
	assert_false(FileAccess.file_exists(_destination_path), "Invalid templates must not create settings")


func test_first_run_saves_local_http_configuration() -> void:
	assert_false(FileAccess.file_exists(_destination_path), "The destination must start absent")
	assert_eq(_setup.configure(_template_path, _destination_path), OK, "Valid setup must succeed")
	var saved: ConfigFile = _load_destination()
	assert_eq(saved.get_value("meta", "version"), 1, "The storage version must be supported")
	assert_eq(saved.get_value("settings", "transport_mode"), "http", "HTTP must be configured")
	assert_eq(saved.get_value("settings", "http_port"), 9081, "The requested port must be stored")
	assert_eq(typeof(saved.get_value("settings", "http_port")), TYPE_INT, "The port must stay an integer")
	assert_eq(saved.get_value("settings", "auto_start"), true, "The editor server must start automatically")
	assert_eq(saved.get_value("settings", "allow_remote"), false, "Remote connections must stay disabled")
	assert_eq(saved.get_value("settings", "auth_enabled"), false, "Local startup must not require a copied token")
	assert_eq(saved.get_value("settings", "auth_token"), "", "The generated settings must have no credential")


func test_generated_settings_are_readable_by_plugin_settings_manager() -> void:
	assert_eq(_setup.configure(_template_path, _destination_path), OK)
	var settings_script: GDScript = load(SETTINGS_MANAGER_PATH) as GDScript
	assert_not_null(settings_script, "The plugin settings manager must be available")
	if settings_script == null:
		return
	var manager: Variant = settings_script.new()
	manager.config_file_name = _destination_path.trim_prefix("user://")
	var settings: Dictionary = manager.load_settings()
	assert_eq(settings["transport_mode"], "http", "The plugin must use the generated transport")
	assert_eq(settings["http_port"], 9081, "The plugin must use the generated port")
	assert_eq(settings["auto_start"], true, "The plugin must use the generated startup setting")
	assert_eq(settings["allow_remote"], false, "The plugin must bind locally")
	assert_eq(settings["auth_enabled"], false, "Authentication must not block local startup")
	assert_eq(settings["auth_token"], "", "The plugin must receive no copied token")
	assert_true(settings.has("language"), "The plugin must fill unrelated default settings")


func test_checked_in_template_configures_an_isolated_destination() -> void:
	var template: ConfigFile = ConfigFile.new()
	assert_eq(template.load(TEMPLATE_PATH), OK, "The project must ship its configuration template")
	assert_eq(template.get_value("meta", "version", 0), 1)
	assert_eq(template.get_value("settings", "transport_mode", ""), "http")
	assert_eq(template.get_value("settings", "auto_start", false), true)
	assert_eq(template.get_value("settings", "allow_remote", true), false)
	assert_eq(template.get_value("settings", "auth_token", ""), "", "The project template must contain no token")
	assert_eq(_setup.configure(TEMPLATE_PATH, _destination_path), OK)
	var saved: ConfigFile = _load_destination()
	assert_eq(saved.get_value("settings", "http_port"), template.get_value("settings", "http_port"))


func test_repeated_setup_preserves_the_existing_file_byte_for_byte() -> void:
	assert_eq(_setup.configure(_template_path, _destination_path), OK)
	var existing: String = FileAccess.get_file_as_string(_destination_path)
	existing += "\n; Existing user notes must be preserved.\n"
	_write_text(_destination_path, existing)
	assert_eq(_setup.configure(_template_path, _destination_path), OK, "Repeated setup must succeed")
	assert_eq(FileAccess.get_file_as_string(_destination_path), existing, "Repeated setup must not rewrite the file")


func test_compatible_existing_settings_preserve_user_preferences_and_disabled_token() -> void:
	var config: ConfigFile = _valid_template()
	config.set_value("settings", "language", "en")
	config.set_value("settings", "log_level", 3)
	config.set_value("settings", "auth_token", TOKEN_SENTINEL)
	assert_eq(config.save(_destination_path), OK)
	var existing: String = FileAccess.get_file_as_string(_destination_path)
	assert_eq(_setup.configure(_template_path, _destination_path), OK)
	assert_eq(FileAccess.get_file_as_string(_destination_path), existing, "Compatible user settings must be preserved")


func test_conflicting_connection_settings_are_preserved() -> void:
	var conflicts: Dictionary = {
		"transport_mode": "stdio",
		"http_port": 9082,
		"auto_start": false,
		"allow_remote": true,
		"auth_enabled": true
	}
	for key: String in conflicts:
		var config: ConfigFile = _valid_template()
		config.set_value("settings", key, conflicts[key])
		assert_eq(config.save(_destination_path), OK)
		var existing: String = FileAccess.get_file_as_string(_destination_path)
		assert_eq(_setup.configure(_template_path, _destination_path), ERR_ALREADY_IN_USE, "Conflicting %s must be reported" % key)
		assert_eq(FileAccess.get_file_as_string(_destination_path), existing, "Conflicting %s must not be overwritten" % key)


func test_incomplete_existing_configuration_is_preserved() -> void:
	var config: ConfigFile = _valid_template()
	config.erase_section_key("settings", "http_port")
	assert_eq(config.save(_destination_path), OK)
	var existing: String = FileAccess.get_file_as_string(_destination_path)
	assert_eq(_setup.configure(_template_path, _destination_path), ERR_ALREADY_IN_USE)
	assert_eq(FileAccess.get_file_as_string(_destination_path), existing, "Incomplete existing settings must be preserved")


func test_malformed_existing_configuration_is_preserved() -> void:
	var existing: String = "[settings]\nhttp_port = @invalid\n"
	_write_text(_destination_path, existing)
	assert_eq(_setup.configure(_template_path, _destination_path), ERR_ALREADY_IN_USE)
	assert_eq(FileAccess.get_file_as_string(_destination_path), existing, "Malformed existing settings must be preserved")
	_mark_expected_config_parse_errors()


func test_missing_template_returns_file_not_found_without_writing() -> void:
	var missing_path: String = _new_path("missing_template")
	assert_eq(_setup.configure(missing_path, _destination_path), ERR_FILE_NOT_FOUND)
	assert_false(FileAccess.file_exists(_destination_path), "Missing templates must not create settings")


func test_malformed_template_returns_invalid_data_without_writing() -> void:
	_write_text(_template_path, "[settings]\nhttp_port = @invalid\n")
	assert_eq(_setup.configure(_template_path, _destination_path), ERR_INVALID_DATA)
	assert_false(FileAccess.file_exists(_destination_path), "Malformed templates must not create settings")
	_mark_expected_config_parse_errors()


func _mark_expected_config_parse_errors() -> void:
	for error: Variant in get_errors():
		if error.contains_text("ConfigFile") or error.contains_text("Parse error"):
			error.handled = true


func test_missing_version_is_rejected() -> void:
	var config: ConfigFile = _valid_template()
	config.erase_section("meta")
	_assert_rejected_template(config, "A template without a version must be rejected")


func test_unsupported_or_non_integer_versions_are_rejected() -> void:
	var versions: Array[Variant] = [0, 2, "1", 1.0, true, null]
	for version: Variant in versions:
		var config: ConfigFile = _valid_template()
		config.set_value("meta", "version", version)
		_assert_rejected_template(config, "Invalid version %s must be rejected" % str(version))


func test_missing_required_settings_are_rejected() -> void:
	var required: Array[String] = ["transport_mode", "http_port", "auto_start", "allow_remote"]
	for key: String in required:
		var config: ConfigFile = _valid_template()
		config.erase_section_key("settings", key)
		_assert_rejected_template(config, "Missing %s must be rejected" % key)


func test_missing_settings_section_is_rejected() -> void:
	var config: ConfigFile = _valid_template()
	config.erase_section("settings")
	_assert_rejected_template(config, "A template without connection settings must be rejected")


func test_non_http_transport_is_rejected() -> void:
	var modes: Array[Variant] = ["stdio", "", "HTTP", true, 1, null]
	for mode: Variant in modes:
		var config: ConfigFile = _valid_template()
		config.set_value("settings", "transport_mode", mode)
		_assert_rejected_template(config, "Invalid transport %s must be rejected" % str(mode))


func test_port_bounds_are_inclusive() -> void:
	var ports: Array[int] = [1024, 65535]
	for port: int in ports:
		_save_template(_valid_template(port))
		var destination: String = _new_path("boundary_%s" % port)
		assert_eq(_setup.configure(_template_path, destination), OK, "Boundary port %s must be accepted" % port)
		var saved: ConfigFile = ConfigFile.new()
		assert_eq(saved.load(destination), OK)
		assert_eq(saved.get_value("settings", "http_port"), port)


func test_out_of_range_or_non_integer_ports_are_rejected() -> void:
	var ports: Array[Variant] = [-1, 0, 1023, 65536, "9081", 9081.0, true, null]
	for port: Variant in ports:
		var config: ConfigFile = _valid_template()
		config.set_value("settings", "http_port", port)
		_assert_rejected_template(config, "Invalid port %s must be rejected" % str(port))


func test_auto_start_requires_boolean_true() -> void:
	var values: Array[Variant] = [false, "true", 1, null]
	for value: Variant in values:
		var config: ConfigFile = _valid_template()
		config.set_value("settings", "auto_start", value)
		_assert_rejected_template(config, "Invalid auto_start %s must be rejected" % str(value))


func test_allow_remote_requires_boolean_false() -> void:
	var values: Array[Variant] = [true, "false", 0, null]
	for value: Variant in values:
		var config: ConfigFile = _valid_template()
		config.set_value("settings", "allow_remote", value)
		_assert_rejected_template(config, "Invalid allow_remote %s must be rejected" % str(value))


func test_unwritable_destination_returns_the_actual_save_error() -> void:
	var destination: String = _new_path("missing_parent").trim_suffix(".cfg") + "/settings.cfg"
	_temporary_paths.append(destination)
	var expected: Error = _valid_template().save(destination)
	assert_ne(expected, OK, "A missing parent directory must make the fixture path unwritable")
	assert_eq(_setup.configure(_template_path, destination), expected, "The underlying save error must be returned")
	assert_false(FileAccess.file_exists(destination), "Failed writes must not leave a settings file")


func test_template_tokens_and_unrelated_secrets_are_never_copied() -> void:
	var config: ConfigFile = _valid_template()
	config.set_value("meta", "private_key", TOKEN_SENTINEL)
	config.set_value("settings", "auth_token", TOKEN_SENTINEL)
	config.set_value("settings", "private_key", TOKEN_SENTINEL)
	config.set_value("secrets", "token", TOKEN_SENTINEL)
	_save_template(config)
	assert_eq(_setup.configure(_template_path, _destination_path), OK)
	var saved: ConfigFile = _load_destination()
	assert_eq(saved.get_section_keys("meta").size(), 1, "Only the supported storage version may be copied")
	assert_eq(saved.get_section_keys("settings").size(), 6, "Only the approved startup settings may be written")
	assert_eq(saved.get_value("settings", "auth_token"), "", "Template credentials must be discarded")
	assert_false(saved.has_section_key("settings", "private_key"), "Unknown sensitive fields must not be copied")
	assert_false(saved.has_section("secrets"), "Unrelated secret sections must not be copied")
	assert_false(FileAccess.get_file_as_string(_destination_path).contains(TOKEN_SENTINEL), "No template secret may appear in the output")
