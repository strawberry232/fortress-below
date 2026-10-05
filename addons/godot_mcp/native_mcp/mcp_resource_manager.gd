# mcp_resource_manager.gd





class_name MCPResourceManager
extends RefCounted


signal resource_registered(uri: String, name: String)
signal resource_read(uri: String, result: Dictionary)


const JSONRPC_VERSION := "2.0"


var _resources: Dictionary = {}


var _log_callback: Callable = Callable()


func set_log_callback(callback: Callable) -> void:
	_log_callback = callback

# ===========================================

# ===========================================


func register_resource(uri: String, name: String, mime_type: String, load_callable: Callable) -> void:
	if _resources.has(uri):
		if _log_callback.is_valid():
			_log_callback.call("WARN", "Resource already exists; replacing: " + uri)

	_resources[uri] = {
		"name": name,
		"mimeType": mime_type,
		"load": load_callable
	}

	resource_registered.emit(uri, name)
	if _log_callback.is_valid():
		_log_callback.call("INFO", "Registered resource: " + uri + " (" + name + ")")


func unregister_resource(uri: String) -> bool:
	if _resources.has(uri):
		_resources.erase(uri)
		if _log_callback.is_valid():
			_log_callback.call("INFO", "Unregistered resource: " + uri)
		return true
	return false


func list_resources() -> Array:
	var resource_list: Array = []

	for uri in _resources.keys():
		var resource_info: Dictionary = _resources[uri]
		resource_list.append({
			"uri": uri,
			"name": resource_info["name"],
			"mimeType": resource_info["mimeType"]
		})

	return resource_list

# ===========================================

# ===========================================


func read_resource(uri: String, params: Dictionary = {}) -> Dictionary:
	if not _resources.has(uri):
		return _error_response(null, -32602, "Resource not found: " + uri)

	var resource_info: Dictionary = _resources[uri]
	var load_callable: Callable = resource_info.get("load", Callable())

	if not load_callable.is_valid():
		return _error_response(null, -32603, "Resource load function not available")

	var result: Dictionary = load_callable.call(params)

	if result.has("error"):
		return _error_response(null, -32603, result.get("error"))

	return result

# ===========================================

# ===========================================


static func _success_response(id: Variant, result: Variant) -> Dictionary:
	return {
		"jsonrpc": "2.0",
		"id": id,
		"result": result
	}


static func _error_response(id: Variant, code: int, message: String) -> Dictionary:
	return {
		"jsonrpc": "2.0",
		"id": id,
		"error": {
			"code": code,
			"message": message
		}
	}

# ===========================================

# ===========================================


func get_resource_count() -> int:
	return _resources.size()


func print_resources() -> void:
	if not _log_callback.is_valid():
		return
	_log_callback.call("INFO", "Registered resources:")
	for uri in _resources.keys():
		var info: Dictionary = _resources[uri]
		_log_callback.call("INFO", "  - " + uri + " (" + info["name"] + ")")
	_log_callback.call("INFO", "  Total: " + str(_resources.size()) + " resources")
