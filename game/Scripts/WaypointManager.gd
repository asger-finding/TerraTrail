extends Node3D

const WAYPOINT_SCENE := preload("res://Scenes/Components/Waypoint.tscn")

var _by_tile: Dictionary = {}
var _by_id: Dictionary = {}

func _ready() -> void:
	var tile_manager := get_node("../TileMap")
	tile_manager.tile_loaded.connect(_on_tile_loaded)
	tile_manager.tile_unloaded.connect(_on_tile_unloaded)

func _on_tile_loaded(tx: int, ty: int, tz: int) -> void:
	var top_left := Coordinates.tile_to_lon_lat(tx, ty, tz)
	var bot_right := Coordinates.tile_to_lon_lat(tx + 1, ty + 1, tz)
	var bbox := "%s,%s,%s,%s" % [
		str(top_left.x), str(bot_right.y), str(bot_right.x), str(top_left.y)
	]

	var key := "%d_%d_%d" % [tx, ty, tz]
	var http := Backend.request_waypoints(bbox)
	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				return
			var json := JSON.new()
			if json.parse(body.get_string_from_utf8()) != OK:
				return
			_spawn_waypoints(key, json.data.get("waypoints", []))
	)

func _on_tile_unloaded(tx: int, ty: int, tz: int) -> void:
	var key := "%d_%d_%d" % [tx, ty, tz]
	for instance: Node3D in _by_tile.get(key, []):
		var id := int(instance.get_meta("waypoint_id"))
		_by_id.erase(id)
		instance.queue_free()
	_by_tile.erase(key)

func _spawn_waypoints(tile_key: String, waypoints: Array) -> void:
	var instances: Array[Node3D] = []
	for wp: Dictionary in waypoints:
		var id: int = int(wp["id"])
		if id in _by_id:
			continue
		var instance := WAYPOINT_SCENE.instantiate()
		instance.position = Coordinates.lon_lat_to_world(float(wp["longitude"]), float(wp["latitude"]))
		instance.set_meta("waypoint_id", id)
		add_child(instance)
		_by_id[id] = instance
		instances.append(instance)
	_by_tile[tile_key] = instances
