extends Node3D

@export var rotation_speed: float = 8.0
@export var max_pitch_deg: float = 45.0
@export var reference_distance: float = 250.0
@export var max_vertical: float = 1125.0
@export var max_scale: float = 3.0

func _on_click_area_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print(get_meta("waypoint_id", -1))

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	var to_cam := camera.global_position - global_position
	var horizontal := Vector2(to_cam.x, to_cam.z)
	if horizontal.length_squared() < 0.001:
		return

	var target_y := atan2(to_cam.x, to_cam.z)
	rotation.y = lerp_angle(rotation.y, target_y, rotation_speed * delta)

	var full_pitch: float = atan2(to_cam.y, horizontal.length())
	var max_pitch: float = deg_to_rad(max_pitch_deg)
	var target_x: float = clamp(-full_pitch * 0.5, -max_pitch, max_pitch)
	rotation.x = lerp_angle(rotation.x, target_x, rotation_speed * delta)

	# Skaler ud fra kameraets højde over waypointet
	var vertical: float = maxf(to_cam.y, 0.0)
	var t: float = smoothstep(reference_distance, max_vertical, vertical)
	var s: float = 1.0 + t * (max_scale - 1.0)
	scale = Vector3(s, s, s)
