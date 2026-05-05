extends Node3D

const WAYPOINT_SCENE := preload("res://scenes/components/Waypoint.tscn")

@export var tile_manager: Node3D

var _by_tile: Dictionary = {}
var _by_id: Dictionary = {}

var _active_waypoint_id: int = -1

func _ready() -> void:
	tile_manager.tile_loaded.connect(_on_tile_loaded)
	tile_manager.tile_unloaded.connect(_on_tile_unloaded)
	Backend.waypoint_activated.connect(_on_waypoint_activated)

func _on_waypoint_activated(waypoint_id: int) -> void:
	# Hent kun det netop aktiverede waypoint og spawn det direkte, så vi ikke
	# refetcher hele tiles og risikerer at andre instanser blinker.
	if waypoint_id in _by_id:
		return
	var http := Backend.request_waypoint(waypoint_id)
	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				push_error("waypoint fetch failed: result=%d code=%d" % [result, code])
				return
			var json := JSON.new()
			json.parse(body.get_string_from_utf8())
			_spawn_single(json.data["waypoint"])
	)

func _spawn_single(wp: Dictionary) -> void:
	var id: int = int(wp["id"])
	if id in _by_id:
		return
	var instance := WAYPOINT_SCENE.instantiate()
	instance.position = Coordinates.lon_lat_to_world(float(wp["longitude"]), float(wp["latitude"]))
	instance.set_meta("waypoint_id", id)
	instance.set_meta("waypoint_data", wp)
	if _active_waypoint_id != -1 and id != _active_waypoint_id:
		instance.visible = false
	add_child(instance)
	_by_id[id] = instance

func _process(_delta: float) -> void:
	var route_path := get_tree().get_first_node_in_group("route_path")
	if route_path.active_waypoint_id != _active_waypoint_id:
		_active_waypoint_id = route_path.active_waypoint_id
		_refresh_visibility()

func _refresh_visibility() -> void:
	for id: int in _by_id:
		var instance: Node3D = _by_id[id]
		instance.visible = _active_waypoint_id == -1 or id == _active_waypoint_id

func _on_tile_loaded(coord: Vector3i) -> void:
	var top_left := Coordinates.tile_to_lon_lat(coord.x, coord.y, coord.z)
	var bot_right := Coordinates.tile_to_lon_lat(coord.x + 1, coord.y + 1, coord.z)
	var bbox := "%s,%s,%s,%s" % [
		str(top_left.x), str(bot_right.y), str(bot_right.x), str(top_left.y)
	]

	var http := Backend.request_waypoints(bbox)
	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				push_error("waypoint fetch failed: result=%d code=%d" % [result, code])
				return
			var json := JSON.new()
			json.parse(body.get_string_from_utf8())
			_spawn_waypoints(coord, json.data["waypoints"])
	)

func _on_tile_unloaded(coord: Vector3i) -> void:
	for instance: Node3D in _by_tile.get(coord, []):
		var id := int(instance.get_meta("waypoint_id"))
		_by_id.erase(id)
		instance.queue_free()
	_by_tile.erase(coord)

func _spawn_waypoints(coord: Vector3i, waypoints: Array) -> void:
	var instances: Array[Node3D] = []
	for wp: Dictionary in waypoints:
		var id: int = int(wp["id"])
		if id in _by_id:
			continue
		var instance := WAYPOINT_SCENE.instantiate()
		instance.position = Coordinates.lon_lat_to_world(float(wp["longitude"]), float(wp["latitude"]))
		instance.set_meta("waypoint_id", id)
		instance.set_meta("waypoint_data", wp)
		if _active_waypoint_id != -1 and id != _active_waypoint_id:
			instance.visible = false
		add_child(instance)
		_by_id[id] = instance
		instances.append(instance)
	_by_tile[coord] = instances
