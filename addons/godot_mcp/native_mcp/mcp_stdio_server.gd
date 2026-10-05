class_name McpStdioServer
extends McpTransportBase





# ==============================================================================

# ==============================================================================


var _active: bool = false


var _thread: Thread = null


var _mutex: Mutex = Mutex.new()


var _message_queue: Array[Dictionary] = []


var _response_queue: Array[Dictionary] = []


var _log_callback: Callable = Callable()


func set_log_callback(callback: Callable) -> void:
	_log_callback = callback


# ==============================================================================

# ==============================================================================



func start() -> bool:
	_active = true
	
	
	ProjectSettings.set_setting("application/run/flush_stdout_on_print", true)
	
	_thread = Thread.new()
	_thread.start(_stdin_listen_loop)
	
	server_started.emit()
	if _log_callback.is_valid():
		_log_callback.call("INFO", "Server started")
	
	return true


func stop() -> void:
	if not _active:
		return
	
	_active = false
	
	
	if _thread and _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null
	
	
	_mutex.lock()
	_message_queue.clear()
	_response_queue.clear()
	_mutex.unlock()
	
	server_stopped.emit()
	if _log_callback.is_valid():
		_log_callback.call("INFO", "Server stopped")



func is_running() -> bool:
	return _active


# ==============================================================================

# ==============================================================================


func _stdin_listen_loop() -> void:
	if _log_callback.is_valid():
		_log_callback.call("DEBUG", "Listen loop started")
	
	while _active:
		
		var input: String = OS.read_string_from_stdin()
		
		if not input.is_empty():
			
			_parse_and_queue_message(input)
		
		
		OS.delay_msec(10)
	
	if _log_callback.is_valid():
		_log_callback.call("DEBUG", "Listen loop stopped")



func _parse_and_queue_message(raw_input: String) -> void:
	var lines: PackedStringArray = raw_input.split("\n")
	
	for line in lines:
		if line.is_empty():
			continue
		
		var json: JSON = JSON.new()
		var parse_result: Error = json.parse(line)
		
		if parse_result != OK:
			if _log_callback.is_valid():
				_log_callback.call("ERROR", "JSON parse error: " + json.get_error_message())
			call_deferred("_emit_error", null, MCPTypes.ERROR_PARSE_ERROR, "Failed to parse JSON input", line)
			continue
		
		var message: Dictionary = json.get_data()
		
		
		_mutex.lock()
		_message_queue.append(message)
		_mutex.unlock()
		
		
		call_deferred("_process_next_message")
	
	
	call_deferred("_process_response_queue")


func _process_next_message() -> void:
	_mutex.lock()
	
	if _message_queue.is_empty():
		_mutex.unlock()
		return
	
	var message: Dictionary = _message_queue.pop_front()
	
	_mutex.unlock()
	
	
	message_received.emit(message, null)  


func _process_response_queue() -> void:
	_mutex.lock()
	
	if _response_queue.is_empty():
		_mutex.unlock()
		return
	
	var response: Dictionary = _response_queue.pop_front()
	
	_mutex.unlock()
	
	
	_send_response(response)



func _send_response(response: Dictionary) -> void:
	var json_string: String = JSON.stringify(response)
	
	if _log_callback.is_valid():
		_log_callback.call("DEBUG", "Sending response: " + json_string)
	
	
	print(json_string)






func _send_error(id: Variant, code: int, message: String, data: Variant = null) -> void:
	var error_response: Dictionary = MCPTypes.create_error_response(id, code, message, data)
	_send_response(error_response)



func send_raw_message(message: Dictionary) -> void:
	var json_string: String = JSON.stringify(message)
	if _log_callback.is_valid():
		_log_callback.call("DEBUG", "Sending raw message: " + json_string)
	print(json_string)



func queue_response(response: Dictionary) -> void:
	_mutex.lock()
	_response_queue.append(response)
	_mutex.unlock()
	
	call_deferred("_process_response_queue")


func _emit_error(id: Variant, code: int, message: String, data: Variant = null) -> void:
	server_error.emit("JSON parse error: " + message)
