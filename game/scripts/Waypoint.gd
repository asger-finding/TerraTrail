extends Node3D

@export var rotation_speed: float = 8.0
@export var max_pitch_deg: float = 45.0
@export var reference_distance: float = 250.0
@export var max_vertical: float = 1125.0
@export var max_scale: float = 3.0
@export var top_down_lift: float = 30.0

var _materials: Array[BaseMaterial3D] = []
var _mesh_instances: Array[MeshInstance3D] = []
var _last_top_down: bool = false

func _ready() -> void:
	_collect_meshes(self)

func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		_mesh_instances.append(mi)
		var mesh := mi.mesh
		if mesh:
			for i in mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat is BaseMaterial3D:
					var dup := mat.duplicate() as BaseMaterial3D
					mi.set_surface_override_material(i, dup)
					_materials.append(dup)
	for child in node.get_children():
		_collect_meshes(child)

func _apply_top_down(enabled: bool) -> void:
	for mat in _materials:
		mat.no_depth_test = enabled
		mat.render_priority = 127 if enabled else 0
	for mi in _mesh_instances:
		mi.sorting_offset = -100000.0 if enabled else 0.0

func _on_click_area_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print(get_meta("waypoint_id", -1))

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	if Coordinates.top_down != _last_top_down:
		_apply_top_down(Coordinates.top_down)
		_last_top_down = Coordinates.top_down

	var to_cam := camera.global_position - global_position

	var target_y: float
	var target_x: float

	if Coordinates.top_down:
		# Læg waypoint fladt på jorden, roteret så top peger mod skærm-op
		target_y = Coordinates.view_yaw
		target_x = -PI / 2.0
	else:
		var horizontal := Vector2(to_cam.x, to_cam.z)
		if horizontal.length_squared() < 0.001:
			return
		target_y = atan2(to_cam.x, to_cam.z)
		var full_pitch: float = atan2(to_cam.y, horizontal.length())
		var max_pitch: float = deg_to_rad(max_pitch_deg)
		target_x = clamp(-full_pitch * 0.5, -max_pitch, max_pitch)

	rotation.y = lerp_angle(rotation.y, target_y, rotation_speed * delta)
	rotation.x = lerp_angle(rotation.x, target_x, rotation_speed * delta)

	var target_lift: float = top_down_lift if Coordinates.top_down else 22.2
	position.y = lerp(position.y, target_lift, rotation_speed * delta)

	# Skaler ud fra kameraets højde over waypointet
	var vertical: float = maxf(to_cam.y, 0.0)
	var t: float = smoothstep(reference_distance, max_vertical, vertical)
	var s: float = 1.0 + t * (max_scale - 1.0)
	scale = Vector3(s, s, s)
