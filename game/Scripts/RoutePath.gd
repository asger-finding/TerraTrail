extends Node3D

const ROUTE_FROM := "12.495449,55.750314"
const ROUTE_TO := "12.526932,55.778280"
const ROUTE_WIDTH := 3.0
const ROUTE_Y_OFFSET := 0.5

const MAT_PATH := preload("res://Materials/Path.tres")
const MAT_PATH_GLOW := preload("res://Materials/PathGlow.tres")

func request_route(origin_lon: float, origin_lat: float) -> void:
	var http := Backend.request_route(ROUTE_FROM, ROUTE_TO, origin_lon, origin_lat)
	http.request_completed.connect(_on_route_completed)
	print("Requesting route ...")

func _on_route_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_error("Route request failed: result=%d code=%d" % [result, code])
		return

	var decoded: Dictionary = MessagePack.decode(body)
	if decoded.status != null:
		push_error("Failed to decode route msgpack: %s" % str(decoded.status))
		return
	var parsed: Dictionary = decoded.value

	var points_flat: Array = parsed.get("points", [])
	if points_flat.is_empty():
		push_warning("Route has no points")
		return

	print("Route: %d points, %.0fm" % [points_flat.size() / 3, parsed.get("distance", 0.0)])
	_build_route_mesh(points_flat)

func _build_route_mesh(points_flat: Array) -> void:
	var point_count := points_flat.size() / 3
	if point_count < 2:
		return

	var points := PackedVector3Array()
	points.resize(point_count)
	for i in point_count:
		points[i] = Vector3(
			float(points_flat[i * 3]),
			float(points_flat[i * 3 + 1]) + ROUTE_Y_OFFSET,
			float(points_flat[i * 3 + 2])
		)

	var glow_mesh := _build_ribbon(points, ROUTE_WIDTH * 2.0, -1)
	glow_mesh.surface_set_material(0, MAT_PATH_GLOW)
	var glow_mi := MeshInstance3D.new()
	glow_mi.mesh = glow_mesh
	glow_mi.name = "route_glow"
	add_child(glow_mi)

	var route_mesh := _build_ribbon(points, ROUTE_WIDTH, 0.0)
	route_mesh.surface_set_material(0, MAT_PATH)
	var mi := MeshInstance3D.new()
	mi.mesh = route_mesh
	mi.name = "route"
	add_child(mi)

	print("Route mesh: %d points" % point_count)

func _build_ribbon(points: PackedVector3Array, half_width: float, y_offset: float) -> ArrayMesh:
	var point_count := points.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(point_count * 2)
	normals.resize(point_count * 2)
	var up := Vector3(0, 1, 0)

	for i in point_count:
		var perp: Vector3
		if i == 0:
			var seg := (points[1] - points[0])
			seg.y = 0.0
			seg = seg.normalized()
			perp = Vector3(-seg.z, 0.0, seg.x) * half_width
		elif i == point_count - 1:
			var seg := (points[i] - points[i - 1])
			seg.y = 0.0
			seg = seg.normalized()
			perp = Vector3(-seg.z, 0.0, seg.x) * half_width
		else:
			var d0 := (points[i] - points[i - 1])
			d0.y = 0.0
			d0 = d0.normalized()
			var d1 := (points[i + 1] - points[i])
			d1.y = 0.0
			d1 = d1.normalized()
			var tangent := (d0 + d1).normalized()
			var miter := Vector3(-tangent.z, 0.0, tangent.x)
			var cos_half := absf(miter.dot(Vector3(-d1.z, 0.0, d1.x)))
			perp = miter * (half_width / maxf(cos_half, 0.5))

		var p := points[i] + Vector3(0, y_offset, 0)
		vertices[i * 2] = p + perp
		vertices[i * 2 + 1] = p - perp
		normals[i * 2] = up
		normals[i * 2 + 1] = up

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	return arr_mesh
