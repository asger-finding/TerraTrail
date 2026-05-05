extends Control

signal closed(via_start: bool)

const STAR_FILLED := preload("res://assets/ui/star_filled.svg")
const STAR_EMPTY := preload("res://assets/ui/star.svg")
const FAV_ACTIVE := preload("res://assets/ui/favourites_active.webp")
const FAV_INACTIVE := preload("res://assets/ui/favourites.webp")

@onready var title_label: Label = %Title
@onready var close_button: Button = %CloseButton
@onready var description_label: Label = %Description
@onready var completed_badge: TextureRect = %CompletedBadge
@onready var actions_row: HBoxContainer = %ActionsRow
@onready var scan_row: HBoxContainer = %ScanRow
@onready var scan_button: Button = %ScanButton
@onready var start_button: Button = %StartButton
@onready var favourite_button: TextureButton = %FavouriteButton
@onready var image_hint: TextureButton = %ImageHint

var _waypoint_id: int = -1
var _waypoint_lon: float = 0.0
var _waypoint_lat: float = 0.0
var _is_favourited: bool = false
var _stars: Array[TextureRect] = []
var _image_request: HTTPRequest = null
var _qr_bytes: PackedByteArray

func _ready() -> void:
	add_to_group("waypoint_popup")
	visible = false
	close_button.pressed.connect(close)
	start_button.pressed.connect(_on_start_pressed)
	favourite_button.pressed.connect(_on_favourite_pressed)
	image_hint.pressed.connect(_on_image_hint_pressed)
	scan_button.pressed.connect(_on_scan_pressed)

	for child: TextureRect in find_child("DifficultyStars", true, false).get_children():
		if child.name.begins_with("Star"):
			_stars.append(child)

func open(data: Dictionary, show_actions: bool = true) -> void:
	_waypoint_id = int(data["id"])
	_waypoint_lon = float(data["longitude"])
	_waypoint_lat = float(data["latitude"])
	_is_favourited = data["isFavourited"]
	title_label.text = data["title"]
	description_label.text = data["description"]
	completed_badge.visible = data["isCompleted"]
	var is_owner: bool = int(data["creatorId"]) == PlayerState.player_id
	actions_row.visible = show_actions and data["activated"] and not is_owner and not data["isCompleted"]
	scan_row.visible = not data["activated"]
	_update_stars(int(data["difficulty"]))
	_update_favourite_visual()
	if data["activated"]:
		_load_image_hint(data["imagePath"])
	else:
		_load_qr()
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

func _on_scan_pressed() -> void:
	close()
	Router.push("scanner")

func _on_favourite_pressed() -> void:
	favourite_button.disabled = true
	var result: Dictionary = await Backend.toggle_favourite(_waypoint_id)
	favourite_button.disabled = false
	if result["ok"]:
		_is_favourited = result["data"]["isFavourited"]
		_update_favourite_visual()
		Backend.waypoint_favourited.emit(_waypoint_id, _is_favourited)

func _update_favourite_visual() -> void:
	favourite_button.texture_normal = FAV_ACTIVE if _is_favourited else FAV_INACTIVE

func _load_image_hint(image_path: String) -> void:
	_cancel_image_request()
	image_hint.texture_normal = null
	image_hint.visible = false
	_qr_bytes = PackedByteArray()
	if image_path.is_empty():
		return
	_image_request = Backend.request_waypoint_image(_waypoint_id)
	_image_request.request_completed.connect(_on_image_response)

func _load_qr() -> void:
	_cancel_image_request()
	image_hint.texture_normal = null
	image_hint.visible = true
	_qr_bytes = PackedByteArray()
	_image_request = Backend.request_waypoint_qr(_waypoint_id)
	_image_request.request_completed.connect(_on_qr_response)

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
	image_hint.texture_normal = ImageTexture.create_from_image(img)
	image_hint.visible = true

func _on_qr_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_cancel_image_request()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		return
	var img := Image.new()
	if img.load_png_from_buffer(body) != OK:
		return
	_qr_bytes = body
	image_hint.texture_normal = ImageTexture.create_from_image(img)

func _on_image_hint_pressed() -> void:
	if _qr_bytes.is_empty():
		return
	SaveBytesDialog.open(self, _qr_bytes, "waypoint-qr.png")
