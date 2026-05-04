extends PanelContainer

@onready var image: TextureRect = %Image

var _waypoint_id: int = -1

func populate(wp: Dictionary) -> void:
	_waypoint_id = int(wp.get("id", -1))
	tooltip_text = String(wp.get("title", ""))
	if _waypoint_id < 0:
		return
	var http := Backend.request_waypoint_image(_waypoint_id)
	http.request_completed.connect(_on_image_response.bind(http))

func _on_image_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		return
	if not is_instance_valid(image):
		return
	var img := Image.new()
	if img.load_webp_from_buffer(body) != OK:
		return
	image.texture = ImageTexture.create_from_image(img)
