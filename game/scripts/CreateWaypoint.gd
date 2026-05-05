extends Control

const STAR_FILLED := preload("res://assets/ui/star_filled.svg")
const STAR_EMPTY := preload("res://assets/ui/star.svg")

@onready var form_view: VBoxContainer = %FormView
@onready var qr_view: VBoxContainer = %QrView
@onready var title_input: LineEdit = %TitleInput
@onready var desc_input: TextEdit = %DescInput
@onready var star1: TextureButton = %Star1
@onready var star2: TextureButton = %Star2
@onready var star3: TextureButton = %Star3
@onready var submit_button: Button = %SubmitButton
@onready var status_label: Label = %StatusLabel
@onready var qr_image: TextureButton = %QrImage

var _difficulty: int = 1
var _qr_bytes: PackedByteArray

func _ready() -> void:
	_update_stars()
	status_label.text = ""

func _on_star_pressed(value: int) -> void:
	_difficulty = value
	_update_stars()

func _update_stars() -> void:
	star1.texture_normal = STAR_FILLED if _difficulty >= 1 else STAR_EMPTY
	star2.texture_normal = STAR_FILLED if _difficulty >= 2 else STAR_EMPTY
	star3.texture_normal = STAR_FILLED if _difficulty >= 3 else STAR_EMPTY

func _on_submit_pressed() -> void:
	var t := title_input.text.strip_edges()
	var d := desc_input.text.strip_edges()
	if t.is_empty() or d.is_empty():
		status_label.text = "Udfyld titel og beskrivelse"
		return

	submit_button.disabled = true
	status_label.text = "Opretter..."
	var result: Dictionary = await Backend.create_waypoint(t, d, _difficulty)
	submit_button.disabled = false
	if not result["ok"]:
		status_label.text = result["error"]
		return

	var waypoint_id: int = int(result["data"]["waypoint"]["id"])
	_show_qr(waypoint_id)

func _show_qr(waypoint_id: int) -> void:
	form_view.visible = false
	qr_view.visible = true
	var http := Backend.request_waypoint_qr(waypoint_id)
	http.request_completed.connect(_on_qr_response.bind(http))

func _on_qr_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_error("/api/waypoints/:id/qr fejl: result=%d code=%d" % [result, code])
		return
	var img := Image.new()
	var err := img.load_png_from_buffer(body)
	if err != OK:
		push_error("PNG decode fejl: %d" % err)
		return
	_qr_bytes = body
	qr_image.texture_normal = ImageTexture.create_from_image(img)

func _on_back_pressed() -> void:
	Router.back()

func _on_done_pressed() -> void:
	Router.goto("profile")

func _on_qr_pressed() -> void:
	if _qr_bytes.is_empty():
		return
	SaveBytesDialog.open(self, _qr_bytes, "waypoint-qr.png")
