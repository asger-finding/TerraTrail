extends Node
# Spejler backend/src/services/coordinates.ts for samme beregninger

const EARTH_RADIUS: float = 6_371_000.0
const DEG2RAD: float = PI / 180.0

var world_origin_lon: float = 0.0
var world_origin_lat: float = 0.0
var player_world_pos: Vector3 = Vector3.ZERO
var player_heading_rad: float = 0.0
var camera_distance: float = 200.0

var _origin_set: bool = false
var _origin_lat_rad: float = 0.0
var _cos_origin_lat: float = 1.0

func is_origin_set() -> bool:
	return _origin_set

func set_origin(lon: float, lat: float) -> void:
	world_origin_lon = lon
	world_origin_lat = lat
	_origin_lat_rad = lat * DEG2RAD
	_cos_origin_lat = cos(_origin_lat_rad)
	_origin_set = true

# Ækvirktangulær projektion: højd./bred. til Vector3 i Godot Y-op
# x = øst, z = -nord (Godot -Z = fremad/nord).
func lon_lat_to_world(lon: float, lat: float) -> Vector3:
	var x := (lon - world_origin_lon) * DEG2RAD * EARTH_RADIUS * _cos_origin_lat
	var z := -(lat - world_origin_lat) * DEG2RAD * EARTH_RADIUS
	return Vector3(x, 0.0, z)

# Convert lon/lat til XYZ tile-koordinater ved et givet zoom-niveaue.
func lon_lat_to_tile(lon: float, lat: float, zoom: int) -> Vector3i:
	var n := 1 << zoom
	var tx := int(((lon + 180.0) / 360.0) * n)
	var lat_rad := lat * DEG2RAD
	var ty := int(((1.0 - log(tan(lat_rad) + 1.0 / cos(lat_rad)) / PI) / 2.0) * n)
	return Vector3i(tx, ty, zoom)

# Returner top-left  (højd., bred.) af en tile.
func tile_to_lon_lat(tx: int, ty: int, zoom: int) -> Vector2:
	var n := float(1 << zoom)
	var lon := (tx / n) * 360.0 - 180.0
	var lat_rad := atan(sinh(PI * (1.0 - 2.0 * ty / n)))
	var lat := lat_rad / DEG2RAD
	return Vector2(lon, lat)
