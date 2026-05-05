extends Control

const SCAN_INTERVAL: float = 0.25

@onready var camera_view: TextureRect = %CameraView
@onready var status_label: Label = %StatusLabel
@onready var native_camera: Node = %NativeCamera
@onready var qr: Node = %QR

var _scan_accumulator: float = 0.0
var _busy: bool = false
var _camera_texture: ImageTexture

func _ready() -> void:
	native_camera.frame_available.connect(_on_frame)
	native_camera.camera_permission_granted.connect(_on_permission_granted)
	native_camera.camera_permission_denied.connect(_on_permission_denied)
	qr.qr_detected.connect(_on_qr_detected)
	qr.qr_scan_failed.connect(_on_qr_scan_failed)

	if "android.permission.CAMERA" in OS.get_granted_permissions():
		_on_permission_granted()
		return
	status_label.text = "Anmoder om kameraadgang..."
	native_camera.request_camera_permission()

func _process(delta: float) -> void:
	_scan_accumulator += delta

func _on_permission_granted() -> void:
	var cams: Array = native_camera.get_all_cameras()
	if cams.is_empty():
		status_label.text = "Intet kamera fundet"
		return
	var req := FeedRequest.new().set_camera_id(cams[0].get_camera_id()).set_width(640).set_height(480).set_frames_to_skip(0)
	native_camera.start(req)
	status_label.text = "Hold kameraet over QR-koden"

func _on_permission_denied() -> void:
	status_label.text = "Kameraadgang afvist"

func _on_frame(frame) -> void:
	var image: Image = frame.get_image()
	if _camera_texture == null:
		_camera_texture = ImageTexture.create_from_image(image)
		camera_view.texture = _camera_texture
	else:
		_camera_texture.update(image)
	if _busy:
		return
	if _scan_accumulator < SCAN_INTERVAL:
		return
	_scan_accumulator = 0.0
	qr.scan_qr_image(image)

func _on_qr_scan_failed(_error) -> void:
	pass

func _on_qr_detected(data: String) -> void:
	if _busy:
		return
	_busy = true

	var trimmed := data.strip_edges()

	status_label.text = "Verificerer ..."
	_stop_camera()

	var result: Dictionary = await Backend.scan_waypoint(trimmed)
	if not result["ok"]:
		status_label.text = "Fejl: %s" % result["error"]
		await get_tree().create_timer(1.5).timeout
		Router.back()
		return

	var data_dict: Dictionary = result["data"]
	if "pending" in data_dict:
		status_label.text = "Tag et hint-billede"
		await get_tree().create_timer(1.0).timeout
		Router.push("image_hint_camera", {
			"waypoint_id": int(data_dict["waypointId"]),
			"lat": Coordinates.player_lat,
			"lon": Coordinates.player_lon
		})
		return

	status_label.text = "Fundet!"
	var route_path := get_tree().get_first_node_in_group("route_path")
	if route_path:
		route_path.clear_route()
	await get_tree().create_timer(1.0).timeout
	Router.back()

func _on_cancel_button_button_up() -> void:
	_stop_camera()
	Router.back()

func _stop_camera() -> void:
	native_camera.stop()
