extends Node3D

func _process(_delta: float) -> void:
	if not Coordinates.is_origin_set():
		return
	global_position.x = Coordinates.player_world_pos.x
	global_position.z = Coordinates.player_world_pos.z
