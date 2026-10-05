class_name McpTransportBase
extends RefCounted




# ==============================================================================

# ==============================================================================




signal message_received(message: Dictionary, context: Variant)



signal server_error(error: String)


signal server_started()


signal server_stopped()


# ==============================================================================

# ==============================================================================



func start() -> bool:
	push_error("McpTransportBase.start() must be overridden")
	return false


func stop() -> void:
	push_error("McpTransportBase.stop() must be overridden")



func is_running() -> bool:
	push_error("McpTransportBase.is_running() must be overridden")
	return false


# ==============================================================================

# ==============================================================================



func set_port(port: int) -> void:
	push_error("McpTransportBase.set_port() is not implemented")



func set_auth_manager(manager: RefCounted) -> void:
	push_error("McpTransportBase.set_auth_manager() is not implemented")




func send_response(response: Dictionary, context: Variant) -> void:
	push_error("McpTransportBase.send_response() is not implemented")



func send_raw_message(message: Dictionary) -> void:
	push_error("McpTransportBase.send_raw_message() is not implemented")
