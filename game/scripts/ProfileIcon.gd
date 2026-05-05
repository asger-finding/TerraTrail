extends PanelContainer

signal pressed

@onready var image: TextureRect = %Image

func _ready() -> void:
	refresh()

func refresh() -> void:
	var http := Backend.request_profile_picture()
	http.request_completed.connect(_on_response.bind(http))

func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		push_error("/api/me/picture failed: result=%d code=%d" % [result, code])
		return
	var img := Image.new()
	if img.load_webp_from_buffer(body) != OK:
		return
	image.texture = ImageTexture.create_from_image(img)

func _on_pressed() -> void:
	pressed.emit()
