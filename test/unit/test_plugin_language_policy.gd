extends "res://addons/gut/test.gd"

const ResourceManager = preload("res://addons/godot_mcp/native_mcp/mcp_resource_manager.gd")


func test_plugin_code_uses_english_only() -> void:
	var paths: Array[String] = []
	_collect_code_paths("res://addons/godot_mcp", paths)
	assert_gt(paths.size(), 0, "The plugin must contain source files.")
	for path: String in paths:
		var content: String = FileAccess.get_file_as_string(path)
		assert_false(_contains_han(content), "Plugin source contains Han characters: " + path)


func test_resource_registration_replacement_and_removal_preserve_contract() -> void:
	var manager: ResourceManager = ResourceManager.new()
	var events: Array[Dictionary] = []
	manager.resource_registered.connect(func(uri: String, resource_name: String) -> void:
		events.append({"uri": uri, "name": resource_name})
	)
	manager.register_resource("test://main", "Initial", "application/json", _load_first)
	assert_eq(manager.get_resource_count(), 1)
	assert_eq(manager.list_resources(), [{
		"uri": "test://main", "name": "Initial", "mimeType": "application/json"
	}])
	assert_eq(manager.read_resource("test://main", {"limit": 2}), {
		"generation": 1, "params": {"limit": 2}
	})
	manager.register_resource("test://main", "Replacement", "text/plain", _load_second)
	assert_eq(manager.get_resource_count(), 1, "Replacing a resource must not duplicate it.")
	assert_eq(manager.list_resources(), [{
		"uri": "test://main", "name": "Replacement", "mimeType": "text/plain"
	}])
	assert_eq(manager.read_resource("test://main"), {"generation": 2, "params": {}})
	assert_eq(events, [
		{"uri": "test://main", "name": "Initial"},
		{"uri": "test://main", "name": "Replacement"}
	])
	assert_true(manager.unregister_resource("test://main"))
	assert_eq(manager.get_resource_count(), 0)
	assert_eq(manager.list_resources(), [])
	assert_false(manager.unregister_resource("test://main"))


func test_missing_resource_and_invalid_loader_return_protocol_errors() -> void:
	var manager: ResourceManager = ResourceManager.new()
	var missing: Dictionary = manager.read_resource("test://missing")
	assert_eq(missing.get("jsonrpc"), "2.0")
	assert_true(missing.has("error"))
	assert_eq(missing.get("error", {}).get("code"), -32602)
	manager.register_resource("test://invalid", "Invalid", "application/json", Callable())
	var invalid: Dictionary = manager.read_resource("test://invalid")
	assert_true(invalid.has("error"))
	assert_eq(invalid.get("error", {}).get("code"), -32603)


func test_loader_errors_remain_protocol_errors() -> void:
	var manager: ResourceManager = ResourceManager.new()
	manager.register_resource("test://error", "Error", "application/json", _load_error)
	var result: Dictionary = manager.read_resource("test://error")
	assert_eq(result.get("error", {}).get("code"), -32603)
	assert_eq(result.get("error", {}).get("message"), "Expected loader error")


func _collect_code_paths(directory: String, paths: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		fail_test("Cannot inspect plugin directory: " + directory)
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		var path: String = directory.path_join(entry)
		if dir.current_is_dir():
			if entry != "." and entry != "..":
				_collect_code_paths(path, paths)
		elif entry.get_extension() in ["gd", "cs", "py"]:
			paths.append(path)
		entry = dir.get_next()
	dir.list_dir_end()


func _contains_han(text: String) -> bool:
	for index: int in range(text.length()):
		var code_point: int = text.unicode_at(index)
		if (code_point >= 0x3400 and code_point <= 0x4DBF) \
			or (code_point >= 0x4E00 and code_point <= 0x9FFF) \
			or (code_point >= 0xF900 and code_point <= 0xFAFF) \
			or (code_point >= 0x20000 and code_point <= 0x323AF):
			return true
	return false


func _load_first(params: Dictionary) -> Dictionary:
	return {"generation": 1, "params": params}


func _load_second(params: Dictionary) -> Dictionary:
	return {"generation": 2, "params": params}


func _load_error(_params: Dictionary) -> Dictionary:
	return {"error": "Expected loader error"}
