extends Control

signal start_pressed(waypoint_id: int)

const STAR_FILLED := preload("res://assets/ui/star_filled.svg")
const STAR_EMPTY := preload("res://assets/ui/star.svg")

@onready var title_label: Label = %Title
@onready var close_button: Button = %CloseButton
@onready var description_label: Label = %Description
@onready var completed_badge: Label = %CompletedBadge
@onready var start_button: Button = %StartButton

var _waypoint_id: int = -1
var _stars: Array[TextureRect] = []

func _ready() -> void:
	add_to_group("waypoint_popup")
	visible = false
	close_button.pressed.connect(close)
	start_button.pressed.connect(_on_start_pressed)

	var stars_node := find_child("Stars", true, false)
	if stars_node:
		for child in stars_node.get_children():
			if child is TextureRect:
				_stars.append(child)

func open(data: Dictionary) -> void:
	_waypoint_id = int(data.get("id", -1))
	title_label.text = String(data.get("title", ""))
	description_label.text = String(data.get("description", ""))
	completed_badge.visible = bool(data.get("isCompleted", false))
	_update_stars(int(data.get("difficulty", 1)))
	visible = true

func close() -> void:
	visible = false

func _update_stars(difficulty: int) -> void:
	for i in _stars.size():
		_stars[i].texture = STAR_FILLED if i < difficulty else STAR_EMPTY

func _on_start_pressed() -> void:
	start_pressed.emit(_waypoint_id)
	close()
