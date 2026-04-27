extends SubViewportContainer

const METERS_PER_PIXEL_FACTOR: float = 0.25
const DRAG_THRESHOLD_PX: float = 100.0

@export var main_camera: Camera3D

var _touches: Dictionary = {}
var _touch_starts: Dictionary = {}
var _max_drag_dist: float = 0.0
var _gesture_started_in_follow: bool = false
var _prev_pinch_dist: float = 0.0
var _prev_pinch_angle: float = 0.0

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			main_camera.handle_zoom(true)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			main_camera.handle_zoom(false)
			return

	if event is InputEventScreenTouch:
		if event.pressed:
			if _touches.is_empty():
				_gesture_started_in_follow = main_camera.mode == main_camera.Mode.FOLLOW
			_touches[event.index] = event.position
			_touch_starts[event.index] = event.position
			if _touches.size() == 2:
				_capture_pinch_baseline()
		else:
			_touches.erase(event.index)
			_touch_starts.erase(event.index)
			if _touches.size() < 2:
				_prev_pinch_dist = 0.0
				_prev_pinch_angle = 0.0
			if _touches.is_empty():
				main_camera.is_dragging = false
				# Korte drag under tærsklen -> elastisk tilbage, men kun
				# hvis vi startede i FOLLOW (ellers bevares eksisterende pan)
				if _gesture_started_in_follow and _max_drag_dist < DRAG_THRESHOLD_PX:
					main_camera.rebound_to_player()
				_max_drag_dist = 0.0
		return

	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			var start: Vector2 = _touch_starts.get(event.index, event.position)
			_max_drag_dist = maxf(_max_drag_dist, event.position.distance_to(start))
			main_camera.is_dragging = true
			main_camera.pan_world(_screen_to_world(event.relative))
		elif _touches.size() == 2:
			# Med to fingre låser vi pinch/rotate fast med det samme
			_max_drag_dist = DRAG_THRESHOLD_PX
			main_camera.is_dragging = true
			_handle_pinch_rotate()

func _capture_pinch_baseline() -> void:
	var positions := _touches.values()
	var a: Vector2 = positions[0]
	var b: Vector2 = positions[1]
	_prev_pinch_dist = a.distance_to(b)
	_prev_pinch_angle = (b - a).angle()

func _handle_pinch_rotate() -> void:
	var positions := _touches.values()
	var a: Vector2 = positions[0]
	var b: Vector2 = positions[1]
	var dist := a.distance_to(b)
	var angle := (b - a).angle()

	if _prev_pinch_dist > 0.0:
		var ratio := _prev_pinch_dist / dist
		main_camera.follow_distance = clamp(
			main_camera.follow_distance * ratio,
			main_camera.min_distance,
			main_camera.max_distance
		)
		var delta_angle := angle - _prev_pinch_angle
		if absf(delta_angle) > 0.001:
			main_camera.rotate_yaw(delta_angle)

	_prev_pinch_dist = dist
	_prev_pinch_angle = angle

func _screen_to_world(screen_delta: Vector2) -> Vector3:
	# Skærm-delta -> lokalt verden-delta (Godot -Z = nord, +X = øst)
	var scale: float = main_camera.follow_distance / 200.0
	var local: Vector3 = Vector3(-screen_delta.x, 0.0, -screen_delta.y) * scale * METERS_PER_PIXEL_FACTOR

	# Rotér om Y efter kameraets view yaw (Godot konvention)
	var yaw: float = main_camera.get_view_yaw()
	var cos_y := cos(yaw)
	var sin_y := sin(yaw)
	return Vector3(
		local.x * cos_y + local.z * sin_y,
		0.0,
		-local.x * sin_y + local.z * cos_y
	)
