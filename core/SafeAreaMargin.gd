extends Control

@export var base_margin: int = 32

func _ready() -> void:
	_apply_safe_area()
	get_tree().root.size_changed.connect(_apply_safe_area)

func _apply_safe_area() -> void:
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	var window_size: Vector2i = DisplayServer.window_get_size()
	if window_size.x <= 0 or window_size.y <= 0:
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	var scale_x: float = viewport_size.x / float(window_size.x)
	var scale_y: float = viewport_size.y / float(window_size.y)

	var left_inset: int = int(safe_area.position.x * scale_x)
	var top_inset: int = int(safe_area.position.y * scale_y)
	var right_inset: int = int((window_size.x - safe_area.end.x) * scale_x)
	var bottom_inset: int = int((window_size.y - safe_area.end.y) * scale_y)

	if is_class("MarginContainer"):
		add_theme_constant_override("margin_left", base_margin + left_inset)
		add_theme_constant_override("margin_top", base_margin + top_inset)
		add_theme_constant_override("margin_right", base_margin + right_inset)
		add_theme_constant_override("margin_bottom", base_margin + bottom_inset)
	else:
		# Para CenterContainer (o cualquier Control en Full Rect)
		offset_left = left_inset
		offset_top = top_inset
		offset_right = -right_inset
		offset_bottom = -bottom_inset
