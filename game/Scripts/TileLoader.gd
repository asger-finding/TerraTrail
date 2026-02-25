extends Node3D

const MAT_GROUND := preload("res://Materials/Ground.tres")
const MAT_LANDCOVER := preload("res://Materials/Landcover.tres")
const MAT_WATER := preload("res://Materials/Water.tres")
const MAT_ROADS := preload("res://Materials/Roads.tres")
const MAT_BUILDINGS := preload("res://Materials/Buildings.tres")
const SHADER_OUTLINE := preload("res://Shaders/Outline.gdshader")
const SHADER_DISTANCE_FADE := preload("res://Shaders/DistanceFade.gdshader")

var main_camera: Camera3D
var sub_camera: Camera3D

func _ready() -> void:
	main_camera = get_node("../../../Camera3D")
	sub_camera = get_node("../SubCamera")
	_setup_outline()
	_setup_distance_fade()

	if PlayerState.is_authenticated():
		_load_tiles()
	else:
		PlayerState.authenticated.connect(_load_tiles, CONNECT_ONE_SHOT)

func _load_tiles() -> void:
	var http := Backend.request_tiles("12.490756,55.740783,12.595335,55.787135", 14)
	http.request_completed.connect(_on_request_completed)
	print("Requesting tiles ...")

func _process(_delta: float) -> void:
	if main_camera and sub_camera:
		sub_camera.global_transform = main_camera.global_transform

func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_error("Tile request failed: result=%d code=%d" % [result, code])
		return

	var decoded: Dictionary = MessagePack.decode(body)
	if decoded.status != null:
		push_error("Failed to decode msgpack: %s" % str(decoded.status))
		return
	var parsed: Dictionary = decoded.value

	var tiles: Array = parsed.get("tiles", [])
	print("Received %d tiles" % tiles.size())

	for tile: Dictionary in tiles:
		var origin: Dictionary = tile["origin"]
		var offset := Vector3(origin["x"], 0.0, origin["y"])

		_add_layer_mesh(tile, "ground", offset, MAT_GROUND)
		_add_layer_mesh(tile, "landcover", offset, MAT_LANDCOVER)
		_add_layer_mesh(tile, "water", offset, MAT_WATER)
		_add_layer_mesh(tile, "roads", offset, MAT_ROADS)
		_add_layer_mesh(tile, "buildings", offset, MAT_BUILDINGS)

	var resp_origin: Dictionary = parsed.get("origin", {})
	var route_path := get_node("../RoutePath") as Node3D
	if route_path and route_path.has_method("request_route"):
		route_path.request_route(resp_origin.get("lon", 0.0), resp_origin.get("lat", 0.0))

func _add_layer_mesh(tile: Dictionary, layer_name: String, offset: Vector3, mat: Material) -> void:
	var layer: Dictionary = tile.get(layer_name, {})
	var verts_flat: Array = layer.get("vertices", [])
	var indices_flat: Array = layer.get("indices", [])
	var normals_flat: Array = layer.get("normals", [])

	if verts_flat.is_empty() or indices_flat.is_empty():
		return

	var vert_count := verts_flat.size() / 3
	var tri_count := indices_flat.size() / 3

	var vertices := PackedVector3Array()
	vertices.resize(vert_count)
	for i in vert_count:
		vertices[i] = Vector3(
			float(verts_flat[i * 3]),
			float(verts_flat[i * 3 + 1]),
			float(verts_flat[i * 3 + 2])
		)

	var normals := PackedVector3Array()
	normals.resize(vert_count)
	for i in vert_count:
		normals[i] = Vector3(
			float(normals_flat[i * 3]),
			float(normals_flat[i * 3 + 1]),
			float(normals_flat[i * 3 + 2])
		)

	var indices := PackedInt32Array()
	indices.resize(indices_flat.size())
	for i in indices_flat.size():
		indices[i] = int(indices_flat[i])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	arr_mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.mesh = arr_mesh
	mi.position = offset
	mi.name = "%s_%d_%d" % [layer_name, tile["x"], tile["y"]]
	add_child(mi)

	print("| %s: %d verts, %d tris" % [mi.name, vert_count, tri_count])

func _setup_outline() -> void:
	_add_postprocess_quad(SHADER_OUTLINE, 126)

func _setup_distance_fade() -> void:
	_add_postprocess_quad(SHADER_DISTANCE_FADE, 127)

func _add_postprocess_quad(shader: Shader, priority: int) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = priority

	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)

	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.extra_cull_margin = 16384.0
	add_child(mi)
