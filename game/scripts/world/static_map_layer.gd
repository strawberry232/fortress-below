extends Node2D

var renderer: Callable
var revision: int = 0
var redraw_count: int = 0


func _init() -> void:
	show_behind_parent = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func invalidate() -> void:
	revision += 1
	queue_redraw()


func _draw() -> void:
	redraw_count += 1
	if renderer.is_valid():
		renderer.call(self)
