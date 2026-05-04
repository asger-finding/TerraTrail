extends Control

signal closed

const STAR_FILLED := preload("res://assets/ui/star_filled.svg")
const STAR_EMPTY := preload("res://assets/ui/star.svg")
const FAV_ACTIVE := preload("res://assets/ui/favourites_active.webp")
const FAV_INACTIVE := preload("res://assets/ui/favourites.webp")

@onready var title_label: Label = %Title
@onready var close_button: Button = %CloseButton
@onready var description_label: Label = %Description
@onready var completed_badge: Label = %CompletedBadge
@onready var start_button: Button = %StartButton
@onready var favourite_button: TextureButton = %FavouriteButton

var _waypoint_id: int = -1
var _waypoint_lon: float = 0.0
var _waypoint_lat: float = 0.0
var _is_favourited: bool = false
var _stars: Array[TextureRect] = []

func _ready() -> void:
	add_to_group("waypoint_popup")
	visible = false
	close_button.pressed.connect(close)
	start_button.pressed.connect(_on_start_pressed)
	favourite_button.pressed.connect(_on_favourite_pressed)

	var stars_node := find_child("DifficultyStars", true, false)
	if stars_node:
		for child in stars_node.get_children():
			if child is TextureRect:
				_stars.append(child)

func open(data: Dictionary) -> void:
	_waypoint_id = int(data.get("id", -1))
	_waypoint_lon = float(data.get("longitude", 0.0))
	_waypoint_lat = float(data.get("latitude", 0.0))
	_is_favourited = bool(data.get("isFavourited", false))
	title_label.text = String(data.get("title", ""))
	description_label.text = String(data.get("description", ""))
	completed_badge.visible = bool(data.get("isCompleted", false))
	_update_stars(int(data.get("difficulty", 1)))
	_update_favourite_visual()
	visible = true

func close() -> void:
	visible = false
	closed.emit()

func _update_stars(difficulty: int) -> void:
	for i in _stars.size():
		_stars[i].texture = STAR_FILLED if i < difficulty else STAR_EMPTY

func _on_start_pressed() -> void:
	var route_path := get_tree().get_first_node_in_group("route_path")
	if route_path:
		route_path.request_route(_waypoint_lon, _waypoint_lat, _waypoint_id)
	close()

func _on_favourite_pressed() -> void:
	if _waypoint_id < 0:
		return
	favourite_button.disabled = true
	var result: Dictionary = await Backend.toggle_favourite(_waypoint_id)
	favourite_button.disabled = false
	if result.get("ok", false):
		_is_favourited = bool(result.get("data", {}).get("favourited", false))
		_update_favourite_visual()

func _update_favourite_visual() -> void:
	favourite_button.texture_normal = FAV_ACTIVE if _is_favourited else FAV_INACTIVE
