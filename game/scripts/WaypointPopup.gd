extends Control

signal closed(via_start: bool)

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
@onready var image_hint: TextureRect = %ImageHint

var _waypoint_id: int = -1
var _waypoint_lon: float = 0.0
var _waypoint_lat: float = 0.0
var _is_favourited: bool = false
var _stars: Array[TextureRect] = []
var _image_request: HTTPRequest = null

func _ready() -> void:
	add_to_group("waypoint_popup")
	visible = false
	close_button.pressed.connect(close)
	start_button.pressed.connect(_on_start_pressed)
	favourite_button.pressed.connect(_on_favourite_pressed)

	for child: TextureRect in find_child("DifficultyStars", true, false).get_children():
		_stars.append(child)

func open(data: Dictionary, show_start: bool = true) -> void:
	_waypoint_id = int(data["id"])
	_waypoint_lon = float(data["longitude"])
	_waypoint_lat = float(data["latitude"])
	_is_favourited = data["isFavourited"]
	title_label.text = data["title"]
	description_label.text = data["description"]
	completed_badge.visible = data["isCompleted"]
	start_button.visible = show_start
	_update_stars(int(data["difficulty"]))
	_update_favourite_visual()
	_load_image_hint(data["imagePath"])
	visible = true

func close(via_start: bool = false) -> void:
	visible = false
	_cancel_image_request()
	closed.emit(via_start)

func _update_stars(difficulty: int) -> void:
	for i in _stars.size():
		_stars[i].texture = STAR_FILLED if i < difficulty else STAR_EMPTY

func _on_start_pressed() -> void:
	var route_path := get_tree().get_first_node_in_group("route_path")
	route_path.request_route(_waypoint_lon, _waypoint_lat, _waypoint_id)
	close(true)

func _on_favourite_pressed() -> void:
	favourite_button.disabled = true
	var result: Dictionary = await Backend.toggle_favourite(_waypoint_id)
	favourite_button.disabled = false
	if result["ok"]:
		_is_favourited = result["data"]["favourited"]
		_update_favourite_visual()

func _update_favourite_visual() -> void:
	favourite_button.texture_normal = FAV_ACTIVE if _is_favourited else FAV_INACTIVE

func _load_image_hint(image_path: String) -> void:
	_cancel_image_request()
	image_hint.texture = null
	image_hint.visible = false
	if image_path.is_empty() or _waypoint_id < 0:
		return
	_image_request = Backend.request_waypoint_image(_waypoint_id)
	_image_request.request_completed.connect(_on_image_response)

func _cancel_image_request() -> void:
	if _image_request:
		_image_request.queue_free()
		_image_request = null

func _on_image_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_cancel_image_request()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		return
	var img := Image.new()
	if img.load_webp_from_buffer(body) != OK:
		return
	image_hint.texture = ImageTexture.create_from_image(img)
	image_hint.visible = true
