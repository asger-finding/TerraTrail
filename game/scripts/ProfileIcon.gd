extends TextureButton

func _ready() -> void:
	refresh()

func refresh() -> void:
	var http := Backend.request_profile_picture()
	http.request_completed.connect(_on_response.bind(http))

func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	
	var img := Image.new()
	if img.load_webp_from_buffer(body) != OK:
		return
	texture_normal = ImageTexture.create_from_image(img)
