extends SceneTree

const ProjectSetup = preload("res://tools/mcp_project_setup.gd")


func _initialize() -> void:
	var setup: RefCounted = ProjectSetup.new()
	var result: Error = setup.call("configure")
	if result != OK:
		printerr("MCP setup failed: ", error_string(result))
		quit(1)
		return
	print("MCP settings ready: ", ProjectSettings.globalize_path("user://mcp_settings.cfg"))
	quit(0)
