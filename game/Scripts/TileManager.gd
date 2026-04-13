extends Node3D

const MAT_GROUND := preload("res://Materials/Ground.tres")
const MAT_LANDCOVER := preload("res://Materials/Landcover.tres")
const MAT_WATER := preload("res://Materials/Water.tres")
const MAT_ROADS := preload("res://Materials/Roads.tres")
const MAT_BUILDINGS := preload("res://Materials/Buildings.tres")
const SHADER_OUTLINE := preload("res://Shaders/Outline.gdshader")
const SHADER_DISTANCE_FADE := preload("res://Shaders/DistanceFade.gdshader")

const LOAD_RADIUS: int = 2   # Hvor mange tiles der skal loades om spiller
const UNLOAD_RADIUS: int = 3 # Hvornår tiles skal frigøres igen
const DEFAULT_ZOOM: int = 14

const LAYER_NAMES: PackedStringArray = ["ground", "landcover", "water", "roads", "buildings"]

# Indlæste tiles: key "x_y_z" er en array af MeshInstance3D nodes
var _loaded_tiles: Dictionary = {}
# Tiles i fetch-køen eller der bliver bygget
var _pending_tiles: Dictionary = {}
# Nuværende tile som spilleren er på
var _player_tile: Vector3i = Vector3i.ZERO

var main_camera: Camera3D
var sub_camera: Camera3D
var _dir_light: DirectionalLight3D
var _player: Node3D

func _ready() -> void:
	main_camera = get_node("../../../Camera3D")
	sub_camera = get_node("../SubCamera")
	_dir_light = get_node_or_null("../DirectionalLight3D")
	_setup_outline()
	_setup_distance_fade()

	_player = get_node_or_null("../Player")
	if _player and _player.has_signal("position_changed"):
		_player.position_changed.connect(_on_player_moved)

	if PlayerState.is_authenticated():
		_on_authenticated()
	else:
		PlayerState.authenticated.connect(_on_authenticated, CONNECT_ONE_SHOT)

func _on_authenticated() -> void:
	if not Coordinates.is_origin_set():
		push_warning("TileManager: origin not set yet")
		return
	_player_tile = Coordinates.lon_lat_to_tile(
		Coordinates.world_origin_lon, Coordinates.world_origin_lat, DEFAULT_ZOOM
	)
	_update_tiles()

func _on_player_moved(lon: float, lat: float) -> void:
	var new_tile: Vector3i = Coordinates.lon_lat_to_tile(lon, lat, _desired_zoom())
	if new_tile != _player_tile:
		_player_tile = new_tile
		_update_tiles()

func _process(_delta: float) -> void:
	if main_camera and sub_camera:
		sub_camera.global_transform = main_camera.global_transform
	if _dir_light and Coordinates.is_origin_set():
		_dir_light.global_position.x = Coordinates.player_world_pos.x
		_dir_light.global_position.z = Coordinates.player_world_pos.z

func _update_tiles() -> void:
	var zoom := _desired_zoom()
	var desired: Dictionary = {}

	for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dy in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var tx := _player_tile.x + dx
			var ty := _player_tile.y + dy
			var key := "%d_%d_%d" % [tx, ty, zoom]
			desired[key] = Vector3i(tx, ty, zoom)

	for key: String in desired:
		if key not in _loaded_tiles and key not in _pending_tiles:
			var coord: Vector3i = desired[key]
			_request_tile(coord.x, coord.y, coord.z, key)

	var to_unload: Array[String] = []
	for key: String in _loaded_tiles:
		if key not in desired:
			var parts := key.split("_")
			var tx := int(parts[0])
			var ty := int(parts[1])
			var dist := maxi(absi(tx - _player_tile.x), absi(ty - _player_tile.y))
			if dist > UNLOAD_RADIUS:
				to_unload.append(key)

	for key: String in to_unload:
		_unload_tile(key)

func _request_tile(tx: int, ty: int, tz: int, key: String) -> void:
	_pending_tiles[key] = true
	var http := Backend.request_tile(
		tx, ty, tz, Coordinates.world_origin_lon, Coordinates.world_origin_lat
	)
	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()

			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				_pending_tiles.erase(key)
				return

			if key in _loaded_tiles:
				_pending_tiles.erase(key)
				return

			# Offload decode + mesh building to worker thread
			WorkerThreadPool.add_task(_decode_and_build.bind(body, key))
	)

# Kører på en worker thread (multi-threading) fordi eller lagger
# hele spillet når nye tiles indlæses (tager op imod 1500 ms selv med localhost server)
# 
# msgpack, mesh building kører på worker thread
# MeshInstance3D nodes tilføes på main thread
func _decode_and_build(body: PackedByteArray, key: String) -> void:
	var decoded: Dictionary = MessagePack.decode(body)
	if decoded.status != null:
		call_deferred("_pending_tiles_erase", key)
		return
	var parsed: Dictionary = decoded.value
	var tile: Dictionary = parsed.get("tile", {})
	if tile.is_empty():
		call_deferred("_pending_tiles_erase", key)
		return

	var origin: Dictionary = tile.get("origin", {})
	var offset := Vector3(origin.get("x", 0.0), 0.0, origin.get("y", 0.0))

	var built: Array[Dictionary] = []
	for layer_name: String in LAYER_NAMES:
		var mesh_data := _build_layer_mesh(tile, layer_name)
		if mesh_data.is_empty():
			continue
		built.append({"mesh": mesh_data, "layer": layer_name, "offset": offset})

	call_deferred("_add_built_meshes", built, key)

func _pending_tiles_erase(key: String) -> void:
	_pending_tiles.erase(key)

# Bygger ArrayMesh fra de rå array
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

# Deferred til main thread
func _add_built_meshes(built: Array[Dictionary], key: String) -> void:
	_pending_tiles.erase(key)

	if key in _loaded_tiles:
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
		mi.name = "%s_%s" % [layer_name, key]
		add_child(mi)
		meshes.append(mi)

	_loaded_tiles[key] = meshes

func _unload_tile(key: String) -> void:
	var meshes: Array = _loaded_tiles.get(key, [])
	for mi: MeshInstance3D in meshes:
		mi.queue_free()
	_loaded_tiles.erase(key)

# stub, vil senere returnere zoom baseret på kamera-højde
func _desired_zoom() -> int:
	return DEFAULT_ZOOM

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
