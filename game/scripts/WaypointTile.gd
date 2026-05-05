extends PanelContainer

signal pressed(waypoint: Dictionary)

@onready var image: TextureRect = %Image

var _waypoint: Dictionary

func populate(wp: Dictionary) -> void:
	_waypoint = wp
	tooltip_text = wp["title"]
	var http := Backend.request_waypoint_image(int(wp["id"]))
	http.request_completed.connect(_on_image_response.bind(http))

func _on_pressed() -> void:
	pressed.emit(_waypoint)

func _on_image_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		return
	var img := Image.new()
	if img.load_webp_from_buffer(body) != OK:
		return
	image.texture = ImageTexture.create_from_image(img)
