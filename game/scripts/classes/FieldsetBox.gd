@tool
class_name FieldsetBox extends Container

@export var title: String = "":
	set(value):
		title = value
		if _label != null:
			_label.text = value
			update_minimum_size()
			queue_redraw()
@export var border_color: Color = Color.BLACK:
	set(value):
		border_color = value
		if _label != null:
			_label.add_theme_color_override("font_color", value)
			queue_redraw()
@export var border_width: float = 2.0:
	set(value):
		border_width = value
		queue_redraw()
@export var title_inset_left: float = 16.0:
	set(value):
		title_inset_left = value
		queue_sort()
		queue_redraw()
@export var title_padding: float = 6.0:
	set(value):
		title_padding = value
		queue_sort()
		queue_redraw()
@export var content_padding: float = 12.0:
	set(value):
		content_padding = value
		update_minimum_size()
		queue_sort()

var _label: Label

func _ready() -> void:
	_label = Label.new()
	_label.text = title
	_label.add_theme_color_override("font_color", border_color)
	add_child(_label, false, Node.INTERNAL_MODE_FRONT)
	queue_sort()
	queue_redraw()

func _get_minimum_size() -> Vector2:
	var label_size := _label_size()
	var content_min := Vector2.ZERO
	for child: Node in get_children():
		if child is Control:
			content_min = content_min.max((child as Control).get_combined_minimum_size())
	var w := maxf(content_min.x + content_padding * 2, title_inset_left + label_size.x + title_padding * 2 + content_padding)
	var h := label_size.y / 2.0 + content_padding + content_min.y + content_padding
	return Vector2(w, h)

func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var label_size := _label_size()
		if _label != null:
			_label.position = Vector2(title_inset_left + title_padding, 0)
			_label.size = label_size
		var content_top := label_size.y / 2.0 + content_padding
		var rect := Rect2(
			content_padding, content_top,
			size.x - content_padding * 2,
			size.y - content_top - content_padding
		)
		for child: Node in get_children():
			if child is Control:
				fit_child_in_rect(child as Control, rect)
		queue_redraw()

func _label_size() -> Vector2:
	if _label == null:
		return Vector2.ZERO
	return _label.get_combined_minimum_size()

func _draw() -> void:
	if _label == null:
		return
	var label_size := _label_size()
	var box_top := label_size.y / 2.0
	var box_bottom := size.y
	var box_left := 0.0
	var box_right := size.x
	var gap_start := title_inset_left
	var gap_end := title_inset_left + label_size.x + title_padding * 2.0

	# Top edge (split around the title)
	draw_line(Vector2(box_left, box_top), Vector2(gap_start, box_top), border_color, border_width, true)
	draw_line(Vector2(gap_end, box_top), Vector2(box_right, box_top), border_color, border_width, true)
	# Right
	draw_line(Vector2(box_right, box_top), Vector2(box_right, box_bottom), border_color, border_width, true)
	# Bottom
	draw_line(Vector2(box_right, box_bottom), Vector2(box_left, box_bottom), border_color, border_width, true)
	# Left
	draw_line(Vector2(box_left, box_bottom), Vector2(box_left, box_top), border_color, border_width, true)
