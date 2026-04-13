extends Camera3D

@export var follow_distance: float = 200.0
@export var follow_height: float = 150.0
@export var follow_speed: float = 3.0
@export var min_distance: float = 100.0
@export var max_distance: float = 1500.0
@export var zoom_step: float = 1.2

func handle_zoom(zoom_in: bool) -> void:
	if zoom_in:
		follow_distance = clamp(follow_distance / zoom_step, min_distance, max_distance)
	else:
		follow_distance = clamp(follow_distance * zoom_step, min_distance, max_distance)

func _process(delta: float) -> void:
	if not Coordinates.is_origin_set():
		return

	Coordinates.camera_distance = follow_distance

	var target_pos: Vector3 = Coordinates.player_world_pos
	var heading_rad: float = Coordinates.player_heading_rad
	var back := Vector3(sin(heading_rad), 0.0, cos(heading_rad)) * follow_distance
	var height := follow_height * (follow_distance / 200.0)
	var desired: Vector3 = target_pos + back + Vector3(0.0, height, 0.0)
	global_position = global_position.lerp(desired, follow_speed * delta)
	look_at(target_pos, Vector3.UP)
