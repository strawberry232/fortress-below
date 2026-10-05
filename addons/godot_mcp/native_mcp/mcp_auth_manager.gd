class_name McpAuthManager
extends RefCounted




# ==============================================================================

# ==============================================================================


var _token: String = ""


var _enabled: bool = true


# ==============================================================================

# ==============================================================================


const HEADER_NAME: String = "authorization"


const SCHEME: String = "Bearer"


# ==============================================================================

# ==============================================================================



func set_token(token: String) -> void:
	if token.length() < 16:
		push_error("Auth token must be at least 16 characters long")
		return
	_token = token



func set_enabled(enabled: bool) -> void:
	_enabled = enabled




func validate_request(headers: Dictionary) -> bool:
	
	if not _enabled:
		return true
	
	
	if not headers.has(HEADER_NAME):
		return false  
	
	var auth_header: String = headers[HEADER_NAME]
	
	
	if not auth_header.begins_with(SCHEME + " "):
		return false  
	
	
	var token: String = auth_header.substr(SCHEME.length() + 1)
	
	var result: bool = true
	var max_len: int = maxi(token.length(), _token.length())
	
	for i in range(max_len):
		var token_char: String = token[i] if i < token.length() else ""
		var stored_char: String = _token[i] if i < _token.length() else ""
		if token_char != stored_char:
			result = false
	
	if token.length() != _token.length():
		result = false
	
	return result



func get_www_authenticate_header() -> String:
	return SCHEME + ' realm="Godot MCP Native", error="invalid_token"'




static func generate_token(length: int = 32) -> String:
	var chars: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
	var token: String = ""
	
	for i in range(length):
		var idx: int = randi() % chars.length()
		token += chars[idx]
	
	return token
