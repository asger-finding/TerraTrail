extends Control

@onready var camera_view: TextureRect = %CameraView
@onready var status_label: Label = %StatusLabel
@onready var trigger_button: TextureButton = %TriggerButton
@onready var native_camera: Node = %NativeCamera

var _waypoint_id: int
var _lat: float
var _lon: float
var _camera_texture: ImageTexture
var _last_image: Image
var _busy: bool = false

func _ready() -> void:
	_waypoint_id = int(Router.meta["waypoint_id"])
	_lat = float(Router.meta["lat"])
	_lon = float(Router.meta["lon"])
	native_camera.frame_available.connect(_on_frame)
	native_camera.camera_permission_granted.connect(_on_permission_granted)
	native_camera.camera_permission_denied.connect(_on_permission_denied)

	if "android.permission.CAMERA" in OS.get_granted_permissions():
		_on_permission_granted()
		return
	status_label.text = "Anmoder om kameraadgang..."
	native_camera.request_camera_permission()

func _on_permission_granted() -> void:
	var cams: Array = native_camera.get_all_cameras()
	if cams.is_empty():
		status_label.text = "Intet kamera fundet"
		return
	var req := FeedRequest.new().set_camera_id(cams[0].get_camera_id()).set_width(1280).set_height(720).set_frames_to_skip(0)
	native_camera.start(req)
	status_label.text = ""

func _on_permission_denied() -> void:
	status_label.text = "Kameraadgang afvist"

func _on_frame(frame) -> void:
	_last_image = frame.get_image()
	if _camera_texture == null:
		_camera_texture = ImageTexture.create_from_image(_last_image)
		camera_view.texture = _camera_texture
	else:
		_camera_texture.update(_last_image)

func _on_trigger_pressed() -> void:
	if _busy or _last_image == null:
		return
	_busy = true
	trigger_button.disabled = true
	status_label.text = "Uploader..."
	_stop_camera()

	var bytes := _last_image.save_jpg_to_buffer(0.85)
	var result: Dictionary = await Backend.upload_waypoint_image(_waypoint_id, bytes, _lat, _lon)
	if not result["ok"]:
		status_label.text = "Fejl: %s" % result["error"]
		await get_tree().create_timer(1.5).timeout
		Router.goto("profile")
		return
	Backend.waypoint_activated.emit(_waypoint_id)
	Router.goto("profile")

func _stop_camera() -> void:
	native_camera.stop()
