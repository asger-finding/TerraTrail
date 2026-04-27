extends Camera3D

@export var target: Camera3D

func _process(_delta: float) -> void:
	if target:
		global_transform = target.global_transform
		near = target.near
		far = target.far
