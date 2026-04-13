extends Camera3D

@export var follow_distance: float = 200.0
@export var follow_height: float = 150.0
@export var follow_speed: float = 3.0

func _process(delta: float) -> void:
	if not Coordinates.is_origin_set():
		return

	var target_pos: Vector3 = Coordinates.player_world_pos
	var heading_rad: float = Coordinates.player_heading_rad
	# Position behind the player: opposite of their forward direction
	var back := Vector3(sin(heading_rad), 0.0, cos(heading_rad)) * follow_distance
	var desired: Vector3 = target_pos + back + Vector3(0.0, follow_height, 0.0)
	global_position = global_position.lerp(desired, follow_speed * delta)
	look_at(target_pos, Vector3.UP)
