extends Button
class_name PressOffsetButton

@export var press_offset: float = 6.0

var _base_y: float = 0.0

func _ready() -> void:
	_base_y = position.y
	var style := get_theme_stylebox("normal").duplicate()
	style.skew.x = randf_range(-0.1, 0.3)
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", style)
	var pressed_style := get_theme_stylebox("pressed").duplicate()
	pressed_style.skew.x = style.skew.x
	add_theme_stylebox_override("pressed", pressed_style)

func _process(_delta: float) -> void:
	position.y = _base_y + (press_offset if get_draw_mode() == DRAW_PRESSED else 0.0)
