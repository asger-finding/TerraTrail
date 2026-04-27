extends Node3D

signal tile_loaded(coord: Vector3i)
signal tile_unloaded(coord: Vector3i)

const MAT_GROUND := preload("res://materials/Ground.tres")
const MAT_LANDCOVER := preload("res://materials/Landcover.tres")
const MAT_WATER := preload("res://materials/Water.tres")
const MAT_ROADS := preload("res://materials/Roads.tres")
const MAT_BUILDINGS := preload("res://materials/Buildings.tres")
const SHADER_OUTLINE := preload("res://shaders/Outline.gdshader")
const SHADER_DISTANCE_FADE := preload("res://shaders/DistanceFade.gdshader")

const LOAD_RADIUS: int = 2
const UNLOAD_RADIUS: int = 3
const FINE_ZOOM: int = 14
const ZOOM_DEBOUNCE: float = 1.0

const LAYER_NAMES: PackedStringArray = ["ground", "landcover", "water", "roads", "buildings"]

var _loaded_tiles: Dictionary = {}
var _pending_tiles: Dictionary = {}
var _player_tile: Vector3i = Vector3i.ZERO
var _pending_zoom: int = -1
var _pending_zoom_time: float = 0.0
var _fade_material: ShaderMaterial

func _ready() -> void:
	add_to_group("tile_manager")
	_setup_outline()
	_setup_distance_fade()

	if PlayerState.is_authenticated():
		_on_authenticated()
	else:
		PlayerState.authenticated.connect(_on_authenticated, CONNECT_ONE_SHOT)

func is_idle() -> bool:
	return _pending_tiles.is_empty() and not _loaded_tiles.is_empty()

func loaded_count() -> int:
	return _loaded_tiles.size()

func pending_count() -> int:
	return _pending_tiles.size()

func _on_authenticated() -> void:
	if not Coordinates.is_origin_set():
		Coordinates.origin_set.connect(_on_origin_ready, CONNECT_ONE_SHOT)
		return
	_start_loading()

func _on_origin_ready() -> void:
	if PlayerState.is_authenticated():
		_start_loading()

func _start_loading() -> void:
	_player_tile = Coordinates.lon_lat_to_tile(Coordinates.player_lon, Coordinates.player_lat, _desired_zoom())
	_update_tiles()

func _process(_delta: float) -> void:
	if _fade_material:
		_fade_material.set_shader_parameter(
			"player_pos",
			Vector2(Coordinates.player_world_pos.x, Coordinates.player_world_pos.z)
		)

	if not Coordinates.is_origin_set():
		return

	var z := _desired_zoom()
	var new_tile := Coordinates.lon_lat_to_tile(Coordinates.player_lon, Coordinates.player_lat, z)
	if new_tile == _player_tile:
		_pending_zoom = -1
		return

	# Zoom-skift med debounce så vi ikke fetcher mellemliggende niveauer
	if new_tile.z != _player_tile.z:
		var now := Time.get_ticks_msec() / 1000.0
		if new_tile.z != _pending_zoom:
			_pending_zoom = new_tile.z
			_pending_zoom_time = now
			return
		if now - _pending_zoom_time < ZOOM_DEBOUNCE:
			return
		_pending_zoom = -1

	_player_tile = new_tile
	_update_tiles()

func _update_tiles() -> void:
	var zoom := _desired_zoom()
	var desired: Dictionary = {}

	for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dy in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var coord := Vector3i(_player_tile.x + dx, _player_tile.y + dy, zoom)
			desired[coord] = true

	# Hent manglende tiles som ikke allerede er fuldt dækket af højere-zoom
	for coord: Vector3i in desired:
		if coord in _loaded_tiles or coord in _pending_tiles:
			continue
		if _is_fully_covered(coord):
			continue
		_request_tile(coord)

	# Frigør tiles hvis afstand (i deres eget zoom) er for stor
	var to_unload: Array[Vector3i] = []
	for coord: Vector3i in _loaded_tiles:
		var p_at_z: Vector3i = Coordinates.lon_lat_to_tile(Coordinates.player_lon, Coordinates.player_lat, coord.z)
		var dist := maxi(absi(coord.x - p_at_z.x), absi(coord.y - p_at_z.y))
		if dist > UNLOAD_RADIUS:
			to_unload.append(coord)
	for coord: Vector3i in to_unload:
		_unload_tile(coord)

func _request_tile(coord: Vector3i) -> void:
	_pending_tiles[coord] = true
	var http := Backend.request_tile(coord.x, coord.y, coord.z, Coordinates.world_origin_lon, Coordinates.world_origin_lat)
	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				_pending_tiles.erase(coord)
				return
			WorkerThreadPool.add_task(_decode_and_build.bind(body, coord))
	)

# Kører msgpack-dekodning og mesh-opbygning på worker thread.
# Main thread tilføjer kun MeshInstance3D noderne til scenen.
func _decode_and_build(body: PackedByteArray, coord: Vector3i) -> void:
	var decoded: Dictionary = MessagePack.decode(body)
	if decoded.status != null:
		call_deferred("_pending_tiles_erase", coord)
		return
	var parsed: Dictionary = decoded.value
	var tile: Dictionary = parsed.get("tile", {})
	if tile.is_empty():
		call_deferred("_pending_tiles_erase", coord)
		return

	var origin: Dictionary = tile.get("origin", {})
	var offset := Vector3(origin.get("x", 0.0), 0.0, origin.get("y", 0.0))

	var built: Array[Dictionary] = []
	for layer_name: String in LAYER_NAMES:
		var mesh_data := _build_layer_mesh(tile, layer_name)
		if mesh_data.is_empty():
			continue
		built.append({"mesh": mesh_data, "layer": layer_name, "offset": offset})

	call_deferred("_add_built_meshes", built, coord)

func _pending_tiles_erase(coord: Vector3i) -> void:
	_pending_tiles.erase(coord)

func _build_layer_mesh(tile: Dictionary, layer_name: String) -> Dictionary:
	var layer: Dictionary = tile.get(layer_name, {})
	var verts_flat: Array = layer.get("vertices", [])
	var indices_flat: Array = layer.get("indices", [])
	var normals_flat: Array = layer.get("normals", [])

	if verts_flat.is_empty() or indices_flat.is_empty():
		return {}

	var vert_count := verts_flat.size() / 3

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

	return {"arr_mesh": arr_mesh, "layer_name": layer_name}

func _add_built_meshes(built: Array[Dictionary], coord: Vector3i) -> void:
	_pending_tiles.erase(coord)

	if coord in _loaded_tiles:
		return

	var meshes: Array[MeshInstance3D] = []
	for entry: Dictionary in built:
		var data: Dictionary = entry["mesh"]
		var arr_mesh: ArrayMesh = data["arr_mesh"]
		var layer_name: String = data["layer_name"]
		var offset: Vector3 = entry["offset"]

		var mat: Material
		match layer_name:
			"ground": mat = MAT_GROUND
			"landcover": mat = MAT_LANDCOVER
			"water": mat = MAT_WATER
			"roads": mat = MAT_ROADS
			"buildings": mat = MAT_BUILDINGS

		arr_mesh.surface_set_material(0, mat)

		var mi := MeshInstance3D.new()
		mi.mesh = arr_mesh
		mi.position = offset
		mi.name = "%s_%d_%d_%d" % [layer_name, coord.x, coord.y, coord.z]
		add_child(mi)
		meshes.append(mi)

	_loaded_tiles[coord] = meshes
	tile_loaded.emit(coord)
	_unload_redundant_ancestors(coord)

func _unload_tile(coord: Vector3i) -> void:
	for mi: MeshInstance3D in _loaded_tiles.get(coord, []):
		mi.queue_free()
	_loaded_tiles.erase(coord)
	tile_unloaded.emit(coord)

# Frigør lavere-zoom parent-tiles der nu er fuldt dækket
func _unload_redundant_ancestors(coord: Vector3i) -> void:
	for ancestor_z in range(coord.z - 1, -1, -1):
		var k := coord.z - ancestor_z
		var ancestor := Vector3i(coord.x >> k, coord.y >> k, ancestor_z)
		if ancestor in _loaded_tiles and _is_fully_covered(ancestor):
			_unload_tile(ancestor)

func _is_fully_covered(coord: Vector3i) -> bool:
	var cells: Dictionary = {}
	for other: Vector3i in _loaded_tiles:
		if other.z <= coord.z:
			continue
		var k_des := other.z - coord.z
		if (other.x >> k_des) != coord.x or (other.y >> k_des) != coord.y:
			continue
		var k_fine := FINE_ZOOM - other.z
		var size := 1 << k_fine
		var ox := (other.x - (coord.x << k_des)) << k_fine
		var oy := (other.y - (coord.y << k_des)) << k_fine
		for fx in size:
			for fy in size:
				cells[Vector2i(ox + fx, oy + fy)] = true
	return cells.size() >= (1 << ((FINE_ZOOM - coord.z) * 2))

func _desired_zoom() -> int:
	var d := Coordinates.camera_distance
	if d < 350.0: return 14
	if d < 700.0: return 13
	if d < 1100.0: return 12
	return 11

func _setup_outline() -> void:
	_add_postprocessing(SHADER_OUTLINE, 126)

func _setup_distance_fade() -> void:
	_fade_material = _add_postprocessing(SHADER_DISTANCE_FADE, 127)

func _add_postprocessing(shader: Shader, priority: int) -> ShaderMaterial:
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
	return mat
