



class_name MCPTypes
extends RefCounted

# ============================================================================

# ============================================================================


const JSONRPC_VERSION: String = "2.0"


const PROTOCOL_VERSION: String = "2025-11-25"


const METHOD_INITIALIZE: String = "initialize"
const METHOD_NOTIFICATIONS_INITIALIZED: String = "notifications/initialized"
const METHOD_TOOLS_LIST: String = "tools/list"
const METHOD_TOOLS_CALL: String = "tools/call"
const METHOD_RESOURCES_LIST: String = "resources/list"
const METHOD_RESOURCES_READ: String = "resources/read"
const METHOD_RESOURCES_SUBSCRIBE: String = "resources/subscribe"
const METHOD_PROMPTS_LIST: String = "prompts/list"
const METHOD_PROMPTS_GET: String = "prompts/get"


const ERROR_PARSE_ERROR: int = -32700
const ERROR_INVALID_REQUEST: int = -32600
const ERROR_METHOD_NOT_FOUND: int = -32601
const ERROR_INVALID_PARAMS: int = -32602
const ERROR_INTERNAL_ERROR: int = -32603


const ERROR_TOOL_NOT_FOUND: int = -32001
const ERROR_RESOURCE_NOT_FOUND: int = -32002
const ERROR_EXECUTION_FAILED: int = -32003


enum SecurityLevel {
	PERMISSIVE,  
	STRICT       
}


enum LogLevel {
	ERROR,  
	WARN,   
	INFO,   
	DEBUG   
}

# ============================================================================

# ============================================================================

class MCPTool:
	var name: String = ""
	var description: String = ""
	var input_schema: Dictionary = {}
	var output_schema: Dictionary = {}
	var annotations: Dictionary = {}
	var callable: Callable = Callable()
	var enabled: bool = true
	var category: String = "core"
	var group: String = ""
	
	
	func to_dict() -> Dictionary:
		var result: Dictionary = {
			"name": name,
			"description": description,
			"inputSchema": input_schema,
			"x_category": category,
			"x_group": group
		}
		
		if not output_schema.is_empty():
			result["outputSchema"] = output_schema
		
		if not annotations.is_empty():
			result["annotations"] = annotations
		
		return result
	
	
	func is_valid() -> bool:
		if name.is_empty():
			return false
		if description.is_empty():
			return false
		if not callable.is_valid():
			return false
		return true
	
	
	static func create_annotations(read_only: bool = false, 
								   destructive: bool = false,
								   idempotent: bool = false,
								   open_world: bool = false) -> Dictionary:
		return {
			"readOnlyHint": read_only,
			"destructiveHint": destructive,
			"idempotentHint": idempotent,
			"openWorldHint": open_world
		}

# ============================================================================

# ============================================================================

class MCPResource:
	var uri: String = ""
	var name: String = ""
	var description: String = ""  
	var mime_type: String = "application/octet-stream"
	var load_callable: Callable = Callable()
	
	
	func to_dict() -> Dictionary:
		var result: Dictionary = {
			"uri": uri,
			"name": name,
			"mimeType": mime_type
		}
		
		
		if not description.is_empty():
			result["description"] = description
		
		return result
	
	
	func is_valid() -> bool:
		if uri.is_empty():
			return false
		if name.is_empty():
			return false
		if not load_callable.is_valid():
			return false
		return true

# ============================================================================

# ============================================================================

class MCPPrompt:
	var name: String = ""
	var description: String = ""
	var arguments: Array[Dictionary] = []  # [{name, description, required}]
	
	func to_dict() -> Dictionary:
		return {
			"name": name,
			"description": description,
			"arguments": arguments
		}
	
	func is_valid() -> bool:
		return not name.is_empty()

# ============================================================================

# ============================================================================




static func normalize_jsonrpc_id(id: Variant) -> Variant:
	if typeof(id) == TYPE_FLOAT:
		var integer_id: int = int(id)
		if is_equal_approx(id, float(integer_id)):
			return integer_id
	
	return id


static func create_response(id: Variant, result: Variant) -> Dictionary:
	return {
		"jsonrpc": JSONRPC_VERSION,
		"id": normalize_jsonrpc_id(id),
		"result": result
	}


static func create_error_response(id: Variant, code: int, message: String, data: Variant = null) -> Dictionary:
	var error: Dictionary = {
		"code": code,
		"message": message
	}
	
	if data != null:
		error["data"] = data
	
	return {
		"jsonrpc": JSONRPC_VERSION,
		"id": normalize_jsonrpc_id(id),
		"error": error
	}


static func create_capabilities(tools_changed: bool = true,
								resources_subscribe: bool = true,
								resources_changed: bool = true,
								prompts_changed: bool = true) -> Dictionary:
	var capabilities: Dictionary = {}
	
	if tools_changed:
		capabilities["tools"] = {"listChanged": true}
	
	if resources_subscribe or resources_changed:
		var resources_cap: Dictionary = {}
		if resources_subscribe:
			resources_cap["subscribe"] = true
		if resources_changed:
			resources_cap["listChanged"] = true
		capabilities["resources"] = resources_cap
	
	if prompts_changed:
		capabilities["prompts"] = {"listChanged": true}
	
	return capabilities


static func is_path_safe(path: String) -> bool:
	
	var allowed_prefixes: Array[String] = ["res://", "user://"]
	var is_allowed: bool = false
	
	for prefix in allowed_prefixes:
		if path.begins_with(prefix):
			is_allowed = true
			break
	
	if not is_allowed:
		return false
	
	
	var blocked_patterns: Array[String] = ["..", "~", "$", "|", ";", "`", "&&", "||"]
	for pattern in blocked_patterns:
		if path.contains(pattern):
			return false
	
	
	if path.length() > 4096:
		return false
	
	return true


static func sanitize_path(path: String) -> String:
	var sanitized: String = path.replace("..", "").replace("~", "")
	
	if not sanitized.begins_with("res://") and not sanitized.begins_with("user://"):
		sanitized = "res://" + sanitized.lstrip("/")
	
	return sanitized


static func generate_id() -> String:
	return "mcp_" + str(Time.get_unix_time_from_system()) + "_" + str(randi())

# ============================================================================

# ============================================================================

class MCPLogger:
	var level: int = LogLevel.INFO
	var prefix: String = "[MCP]"
	var _log_callback: Callable = Callable()
	
	func set_log_callback(callback: Callable) -> void:
		_log_callback = callback
	
	func error(message: String) -> void:
		if level >= LogLevel.ERROR:
			if _log_callback.is_valid():
				_log_callback.call("ERROR", prefix + "[ERROR] " + message)
	
	func warn(message: String) -> void:
		if level >= LogLevel.WARN:
			if _log_callback.is_valid():
				_log_callback.call("WARN", prefix + "[WARN] " + message)
	
	func info(message: String) -> void:
		if level >= LogLevel.INFO:
			if _log_callback.is_valid():
				_log_callback.call("INFO", prefix + "[INFO] " + message)
	
	func debug(message: String) -> void:
		if level >= LogLevel.DEBUG:
			if _log_callback.is_valid():
				_log_callback.call("DEBUG", prefix + "[DEBUG] " + message)
