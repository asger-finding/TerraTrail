extends Button

signal row_pressed(waypoint: Dictionary)

const STAR_FILLED := preload("res://assets/ui/star_filled.svg")
const STAR_EMPTY := preload("res://assets/ui/star.svg")

@onready var title_label: Label = %RowTitle
@onready var stars_container: HBoxContainer = %RowStars

var _waypoint: Dictionary

func _ready() -> void:
	pressed.connect(_on_pressed)
	if not _waypoint.is_empty():
		_render()

func populate(wp: Dictionary) -> void:
	_waypoint = wp
	if is_node_ready():
		_render()

func _render() -> void:
	title_label.text = String(_waypoint.get("title", ""))
	var difficulty: int = int(_waypoint.get("difficulty", 1))
	var stars := stars_container.get_children()
	for i in stars.size():
		if stars[i] is TextureRect:
			(stars[i] as TextureRect).texture = STAR_FILLED if i < difficulty else STAR_EMPTY

func _on_pressed() -> void:
	row_pressed.emit(_waypoint)
