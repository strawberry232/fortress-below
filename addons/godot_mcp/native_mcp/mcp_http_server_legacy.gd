class_name McpHttpServer
extends McpTransportBase





# ==============================================================================

# - message_received(message: Dictionary, context: Variant)
# - server_error(error: String)
# - server_started()
# - server_stopped()
# ==============================================================================


# ==============================================================================

# ==============================================================================


const MAX_REQUEST_SIZE: int = 1024 * 1024


const REQUEST_TIMEOUT: float = 30.0


const AUTH_HEADER: String = "authorization"


const AUTH_SCHEME: String = "Bearer"


# ==============================================================================

# ==============================================================================


var _tcp_server: TCPServer = null


var _port: int = 9080


var _active: bool = false


var _thread: Thread = null


var _connections: Array[StreamPeerTCP] = []


var _sse_connections: Dictionary = {}  # peer -> session_id


var _auth_manager: McpAuthManager = null


var _sessions: Dictionary = {}  # session_id -> session_data


var _allow_remote: bool = false
var _cors_origin: String = "*"



var _log_callback: Callable = Callable()


# ==============================================================================

# ==============================================================================



func set_port(port: int) -> void:
	if _active:
		push_error("Cannot change port while server is running")
		return
	_port = port



func set_log_callback(callback: Callable) -> void:
	_log_callback = callback



func set_auth_manager(manager: RefCounted) -> void:
	_auth_manager = manager as McpAuthManager



func start() -> bool:
	var conflict_info: String = _check_port_conflict(_port)
	if not conflict_info.is_empty():
		var error_msg: String = "Port " + str(_port) + " is already in use! " + conflict_info + " Please change the port in MCP settings or close the conflicting application."
		server_error.emit(error_msg)
		if _log_callback.is_valid():
			_log_callback.call("ERROR", error_msg)
		push_error(error_msg)
		return false
	
	_tcp_server = TCPServer.new()
	
	var error: Error = _tcp_server.listen(_port)
	if error != OK:
		var error_msg: String = "Failed to listen on port " + str(_port) + ": " + str(error)
		server_error.emit(error_msg)
		if _log_callback.is_valid():
			_log_callback.call("ERROR", error_msg)
		return false
	
	_active = true
	_thread = Thread.new()
	_thread.start(_http_server_loop)
	
	server_started.emit()
	if _log_callback.is_valid():
		_log_callback.call("INFO", "Server started on port " + str(_port))
	
	return true

func _check_port_conflict(port: int) -> String:
	var os_name: String = OS.get_name()
	if os_name == "Windows":
		return _check_port_conflict_windows(port)
	elif os_name == "Linux" or os_name == "FreeBSD":
		return _check_port_conflict_linux(port)
	elif os_name == "macOS":
		return _check_port_conflict_macos(port)
	return ""

func _check_port_conflict_windows(port: int) -> String:
	var output: Array = []
	var exit_code: int = OS.execute("netstat", ["-ano"], output)
	if exit_code != OK or output.is_empty():
		return ""
	var port_str: String = ":" + str(port) + " "
	var lines: PackedStringArray = output[0].split("\n")
	for line in lines:
		var stripped: String = line.strip_edges()
		if stripped.find(port_str) >= 0 and stripped.find("LISTENING") >= 0:
			var parts: PackedStringArray = stripped.split(" ", false)
			var pid: String = ""
			if parts.size() >= 5:
				pid = parts[parts.size() - 1]
			if pid.is_empty() or not pid.is_valid_int():
				continue
			var proc_output: Array = []
			var proc_exit: int = OS.execute("tasklist", ["/FI", "PID eq " + pid, "/FO", "CSV", "/NH"], proc_output)
			if proc_exit == OK and not proc_output.is_empty():
				var proc_line: String = proc_output[0].strip_edges().replace("\"", "")
				if proc_line.find("INFO:") >= 0:
					return "(PID " + pid + ")"
				var proc_parts: PackedStringArray = proc_line.split(",")
				if proc_parts.size() >= 2:
					var proc_name: String = proc_parts[0]
					return "(PID " + pid + ", process: " + proc_name + ")"
			return "(PID " + pid + ")"
	return ""

func _check_port_conflict_linux(port: int) -> String:
	var output: Array = []
	var exit_code: int = OS.execute("ss", ["-tlnp"], output)
	if exit_code != OK or output.is_empty():
		exit_code = OS.execute("netstat", ["-tlnp"], output)
		if exit_code != OK or output.is_empty():
			return ""
	var port_str: String = ":" + str(port)
	var lines: PackedStringArray = output[0].split("\n")
	for line in lines:
		var stripped: String = line.strip_edges()
		if stripped.find(port_str) >= 0 and stripped.find("LISTEN") >= 0:
			var pid_start: int = stripped.find("pid=")
			if pid_start >= 0:
				var pid_section: String = stripped.substr(pid_start + 4)
				var pid_end: int = pid_section.find(",")
				if pid_end < 0:
					pid_end = pid_section.find(")")
				var pid: String = pid_section.substr(0, pid_end) if pid_end >= 0 else pid_section
				if pid.is_valid_int():
					return _resolve_process_name_linux(pid)
			return ""
	return ""

func _check_port_conflict_macos(port: int) -> String:
	var output: Array = []
	var exit_code: int = OS.execute("lsof", ["-i", ":" + str(port), "-sTCP:LISTEN", "-P", "-n"], output)
	if exit_code != OK or output.is_empty():
		return ""
	var lines: PackedStringArray = output[0].split("\n")
	if lines.size() >= 2:
		var parts: PackedStringArray = lines[1].strip_edges().split(" ", false)
		if parts.size() >= 2:
			var proc_name: String = parts[0]
			var pid: String = parts[1]
			if pid.is_valid_int():
				return "(PID " + pid + ", process: " + proc_name + ")"
			return "(PID " + pid + ")"
	return ""

func _resolve_process_name_linux(pid: String) -> String:
	var proc_output: Array = []
	var proc_exit: int = OS.execute("ps", ["-p", pid, "-o", "comm=", "--no-headers"], proc_output)
	if proc_exit == OK and not proc_output.is_empty():
		var proc_name: String = proc_output[0].strip_edges()
		if not proc_name.is_empty():
			return "(PID " + pid + ", process: " + proc_name + ")"
	return "(PID " + pid + ")"


func stop() -> void:
	_active = false
	
	
	if _tcp_server:
		_tcp_server.stop()
		_tcp_server = null
	
	
	if _thread and _thread.is_alive():
		_thread.wait_to_finish()
	_thread = null
	
	
	for peer in _connections:
		if peer and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host()
	
	_connections.clear()
	
	server_stopped.emit()
	if _log_callback.is_valid():
		_log_callback.call("INFO", "Server stopped")



func is_running() -> bool:
	return _active and _tcp_server != null and _tcp_server.is_listening()


# ==============================================================================

# ==============================================================================


func _http_server_loop() -> void:
	if _log_callback.is_valid():
		_log_callback.call("INFO", "Server loop started")
	
	var last_keepalive: int = Time.get_ticks_msec()
	
	while _active:
		if not _tcp_server:
			break
		
		
		var peer: StreamPeerTCP = null
		if _tcp_server.is_connection_available():
			peer = _tcp_server.take_connection()
		if peer:
			_connections.append(peer)
			if _log_callback.is_valid():
				_log_callback.call("INFO", "New connection: " + str(peer.get_status()))
		
		
		var disconnected: Array[StreamPeerTCP] = []
		var current_connections: Array[StreamPeerTCP] = _connections.duplicate()
		
		for p in current_connections:
			if not _active:
				break
			if p.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				disconnected.append(p)
				if _sse_connections.has(p):
					_close_sse_connection(p)
				continue
			
			if p.get_available_bytes() > 0:
				_handle_http_request(p)
		
		
		for d in disconnected:
			_connections.erase(d)
		
		
		var current_time: int = Time.get_ticks_msec()
		if current_time - last_keepalive > 30000:
			_send_sse_keepalive()
			last_keepalive = current_time
		
		
		OS.delay_msec(2)
	
	
	_cleanup_all_sse_connections()
	
	if _log_callback.is_valid():
		_log_callback.call("INFO", "Server loop stopped")


func _send_sse_keepalive() -> void:
	var disconnected_peers: Array[StreamPeerTCP] = []
	
	for peer in _sse_connections.keys():
		var message: String = ": keepalive\r\n\r\n"
		var error: Error = peer.put_data(message.to_utf8_buffer())
		
		if error != OK:
			if _log_callback.is_valid():
				_log_callback.call("WARN", "Failed to send keepalive, closing connection")
			disconnected_peers.append(peer)
	
	
	for peer in disconnected_peers:
		_close_sse_connection(peer)


func _cleanup_all_sse_connections() -> void:
	var peers: Array = _sse_connections.keys()
	for peer in peers:
		_close_sse_connection(peer)
	
	_sse_connections.clear()
	_sessions.clear()
	
	if _log_callback.is_valid():
		_log_callback.call("INFO", "All SSE connections cleaned up")



func _handle_http_request(peer: StreamPeerTCP) -> void:
	var request: String = ""
	var start_time: int = Time.get_ticks_msec()
	var headers_complete: bool = false
	var content_length: int = -1
	
	while true:
		var available: int = peer.get_available_bytes()
		if available > 0:
			var chunk: String = peer.get_utf8_string(available)
			request += chunk
		
		if request.length() > MAX_REQUEST_SIZE:
			_send_http_error(peer, 413, "Request too large. Maximum size is " + str(MAX_REQUEST_SIZE / 1024) + "KB")
			return
		
		var current_time: int = Time.get_ticks_msec()
		if current_time - start_time > REQUEST_TIMEOUT * 1000:
			_send_http_error(peer, 408, "Request timeout. Please ensure the request is sent completely within " + str(REQUEST_TIMEOUT) + " seconds.")
			return
		
		if not headers_complete:
			if request.contains("\r\n\r\n"):
				headers_complete = true
				var header_end: int = request.find("\r\n\r\n")
				var header_section: String = request.substr(0, header_end)
				var header_lines: PackedStringArray = header_section.split("\r\n")
				for line in header_lines:
					var lower_line: String = line.to_lower()
					if lower_line.begins_with("content-length:"):
						var cl_str: String = line.substr(15).strip_edges()
						content_length = cl_str.to_int()
						break
			else:
				OS.delay_msec(1)
				continue
		
		if headers_complete:
			var header_end: int = request.find("\r\n\r\n")
			var body: String = request.substr(header_end + 4)
			var body_received: int = body.to_utf8_buffer().size()
			
			if content_length >= 0:
				if body_received >= content_length:
					break
				else:
					OS.delay_msec(1)
					continue
			else:
				break
	
	if request.is_empty():
		return
	
	
	var parsed: Dictionary = _parse_http_request(request)
	
	
	if _auth_manager and not _auth_manager.validate_request(parsed["headers"]):
		_send_http_error(peer, 401, "Unauthorized. Please provide a valid Bearer token in the Authorization header.")
		return
	
	
	match parsed["method"]:
		"POST":
			_handle_post_request(peer, parsed)
		"GET":
			_handle_get_request(peer, parsed)
		"OPTIONS":
			_handle_options_request(peer, parsed)
		_:
			_send_http_error(peer, 405, "Method not allowed. Only POST, GET, and OPTIONS are supported.")




func _parse_http_request(raw: String) -> Dictionary:
	var lines: PackedStringArray = raw.split("\r\n")
	var request_line: PackedStringArray = lines[0].split(" ")
	
	var method: String = request_line[0]
	var path: String = request_line[1]
	var version: String = request_line[2] if request_line.size() > 2 else "HTTP/1.1"
	
	
	var headers: Dictionary = {}
	var body_start: int = -1
	
	for i in range(1, lines.size()):
		if lines[i].is_empty():
			body_start = i + 1
			break
		
		var colon_pos: int = lines[i].find(":")
		if colon_pos > 0:
			var header_name: String = lines[i].left(colon_pos).to_lower()
			var header_value: String = lines[i].substr(colon_pos + 1).strip_edges()
			headers[header_name] = header_value
	
	
	var body: String = ""
	if body_start != -1 and body_start < lines.size():
		var body_parts: PackedStringArray = []
		for i in range(body_start, lines.size()):
			body_parts.append(lines[i])
		body = "\r\n".join(body_parts)
	
	return {
		"method": method,
		"path": path,
		"version": version,
		"headers": headers,
		"body": body
	}




func _handle_post_request(peer: StreamPeerTCP, parsed: Dictionary) -> void:
	
	if parsed["path"] != "/mcp" and parsed["path"] != "/":
		_send_http_error(peer, 404, "Not found. Please use path '/mcp' for MCP requests.")
		return
	
	var content_type: String = parsed["headers"].get("content-type", "")
	var body: String = parsed["body"]
	
	if not body.is_empty() and not content_type.contains("application/json"):
		_send_http_error(peer, 415, "Unsupported media type. Please use 'Content-Type: application/json'.")
		return
	
	if body.is_empty():
		_send_http_error(peer, 400, "Empty request body")
		return
	
	var json: JSON = JSON.new()
	var parse_error: Error = json.parse(body)
	
	if parse_error != OK:
		_send_http_error(peer, 400, "Invalid JSON: " + json.get_error_message())
		return
	
	var message: Dictionary = json.get_data()
	
	var is_notification: bool = not message.has("id")
	
	call_deferred("_emit_message_received", message, peer)
	
	if is_notification:
		_send_http_accepted(peer)




func _handle_get_request(peer: StreamPeerTCP, parsed: Dictionary) -> void:
	
	if parsed["headers"].get("accept", "") == "text/event-stream":
		_handle_sse_request(peer, parsed)
		return
	
	
	var info: Dictionary = {
		"name": "Godot MCP Native",
		"version": "1.0.0",
		"transport": "http",
		"protocol": "MCP 2025-03-26",
		"endpoints": {
			"mcp": "/mcp (POST)",
			"sse": "/mcp (GET, SSE)"
		}
	}
	
	_send_http_response(peer, info)




func _handle_options_request(peer: StreamPeerTCP, parsed: Dictionary) -> void:
	var response: String = "HTTP/1.1 204 No Content\r\n"
	response += "Access-Control-Allow-Origin: *\r\n"
	response += "Access-Control-Allow-Methods: POST, GET, OPTIONS\r\n"
	response += "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"
	response += "Access-Control-Max-Age: 86400\r\n"
	response += "\r\n"
	
	peer.put_data(response.to_utf8_buffer())
	peer.disconnect_from_host()




func _handle_sse_request(peer: StreamPeerTCP, parsed: Dictionary) -> void:
	
	if _auth_manager and not _auth_manager.validate_request(parsed["headers"]):
		_send_http_error(peer, 401, "Unauthorized")
		return
	
	
	var session_id: String = _generate_session_id()
	
	
	var response_header: String = "HTTP/1.1 200 OK\r\n"
	response_header += "Content-Type: text/event-stream\r\n"
	response_header += "Cache-Control: no-cache\r\n"
	response_header += "Connection: keep-alive\r\n"
	response_header += "Access-Control-Allow-Origin: " + _cors_origin + "\r\n"
	response_header += "\r\n"
	
	peer.put_data(response_header.to_utf8_buffer())
	
	
	_send_sse_event(peer, "connected", {"session_id": session_id})
	
	
	_sse_connections[peer] = session_id
	_sessions[session_id] = {
		"peer": peer,
		"created_at": Time.get_time_dict_from_system()
	}
	
	if _log_callback.is_valid():
		_log_callback.call("INFO", "SSE connection established: " + session_id)



func send_raw_message(message: Dictionary) -> void:
	var disconnected_peers: Array[StreamPeerTCP] = []
	for peer in _sse_connections.keys():
		_send_sse_event(peer, "message", message)
		if not _sse_connections.has(peer):
			disconnected_peers.append(peer)
	if _log_callback.is_valid():
		_log_callback.call("DEBUG", "Raw message broadcast to " + str(_sse_connections.size()) + " SSE connections")





func _send_sse_event(peer: StreamPeerTCP, event: String, data: Dictionary) -> void:
	var message: String = "event: " + event + "\r\n"
	message += "data: " + JSON.stringify(data) + "\r\n"
	message += "\r\n"
	
	var error: Error = peer.put_data(message.to_utf8_buffer())
	if error != OK:
		if _log_callback.is_valid():
			_log_callback.call("ERROR", "Failed to send SSE event: " + str(error))
		_close_sse_connection(peer)



func _close_sse_connection(peer: StreamPeerTCP) -> void:
	if _sse_connections.has(peer):
		var session_id: String = _sse_connections[peer]
		_sse_connections.erase(peer)
		_sessions.erase(session_id)
		if _log_callback.is_valid():
			_log_callback.call("INFO", "SSE connection closed: " + session_id)
	
	peer.disconnect_from_host()



func _generate_session_id() -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	
	var chars: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var session_id: String = ""
	
	for i in range(32):
		var idx: int = rng.randi() % chars.length()
		session_id += chars[idx]
	
	return session_id




func set_remote_config(allow_remote: bool, cors_origin: String = "*") -> void:
	_allow_remote = allow_remote
	_cors_origin = cors_origin
	
	if _log_callback.is_valid():
		_log_callback.call("INFO", "Remote access config: allow_remote=" + str(allow_remote) + ", cors=" + cors_origin)


# ==============================================================================

# ==============================================================================




func _emit_message_received(message: Dictionary, peer: StreamPeerTCP) -> void:
	message_received.emit(message, peer as Variant)


# ==============================================================================

# ==============================================================================




func send_response(response: Dictionary, context: Variant) -> void:
	var peer: StreamPeerTCP = context as StreamPeerTCP
	if not peer:
		if _log_callback.is_valid():
			_log_callback.call("ERROR", "Cannot send response: invalid peer context")
		return
	_send_http_response(peer, response)




func _send_http_response(peer: StreamPeerTCP, data: Dictionary) -> void:
	var json_string: String = JSON.stringify(data)
	var json_bytes: PackedByteArray = json_string.to_utf8_buffer()
	
	var http_response: String = "HTTP/1.1 200 OK\r\n"
	http_response += "Content-Type: application/json; charset=utf-8\r\n"
	http_response += "Content-Length: " + str(json_bytes.size()) + "\r\n"
	http_response += "Access-Control-Allow-Origin: *\r\n"
	http_response += "\r\n"
	
	var header_bytes: PackedByteArray = http_response.to_utf8_buffer()
	var full_response: PackedByteArray = header_bytes + json_bytes
	
	var error: Error = peer.put_data(full_response)
	if error != OK:
		server_error.emit("Failed to send HTTP response: " + str(error))
		if _log_callback.is_valid():
			_log_callback.call("ERROR", "Failed to send response: " + str(error))
	
	peer.disconnect_from_host()





func _send_http_accepted(peer: StreamPeerTCP) -> void:
	var response: String = "HTTP/1.1 202 Accepted\r\n"
	response += "Content-Length: 0\r\n"
	response += "Access-Control-Allow-Origin: *\r\n"
	response += "\r\n"
	peer.put_data(response.to_utf8_buffer())
	peer.disconnect_from_host()

func _send_http_error(peer: StreamPeerTCP, status_code: int, message: String) -> void:
	var status_text: String = ""
	match status_code:
		400: status_text = "Bad Request"
		401: status_text = "Unauthorized"
		404: status_text = "Not Found"
		405: status_text = "Method Not Allowed"
		408: status_text = "Request Timeout"
		413: status_text = "Request Too Large"
		415: status_text = "Unsupported Media Type"
		500: status_text = "Internal Server Error"
		501: status_text = "Not Implemented"
		_: status_text = "Error"
	
	var response_header: String = "HTTP/1.1 " + str(status_code) + " " + status_text + "\r\n"
	response_header += "Content-Type: text/plain; charset=utf-8\r\n"
	response_header += "Content-Length: " + str(message.to_utf8_buffer().size()) + "\r\n"
	response_header += "Access-Control-Allow-Origin: *\r\n"
	response_header += "\r\n"
	
	peer.put_data(response_header.to_utf8_buffer() + message.to_utf8_buffer())
	peer.disconnect_from_host()
	
	if _log_callback.is_valid():
		_log_callback.call("WARN", "Error response sent: " + str(status_code) + " " + message)
