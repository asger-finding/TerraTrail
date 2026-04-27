extends Node3D

signal position_changed(lon: float, lat: float)

const MOVE_SPEED: float = 0.005   # degrees pr. sekund (WASD)
const MOVE_THRESHOLD: float = 10.0  # meter før position_changed emittes
const COMPASS_LERP_RATE: float = 8.0
const GPS_TIMEOUT: float = 10.0

@export var compass_offset_deg: float = 0.0

var lon: float = 12.543
var lat: float = 55.764
var heading: float = 0.0  # grader, 0 = nord

var gps_wait_active: bool = false
var gps_wait_elapsed: float = 0.0
var gps_fix_missing: bool = false

var _last_emitted_pos: Vector3 = Vector3.ZERO
var _use_sensors: bool = false

func _ready() -> void:
	add_to_group("player")
	_use_sensors = OS.get_name() == "Android"
	if not _use_sensors:
		Coordinates.set_origin(lon, lat)
		_update_transform()
		_last_emitted_pos = position
	else:
		gps_wait_active = true
		gps_fix_missing = true
		_init_gps()

func _init_gps() -> void:
	var granted := OS.get_granted_permissions()
	if "android.permission.ACCESS_FINE_LOCATION" in granted:
		_enable_gps()
		return
	get_tree().on_request_permissions_result.connect(_on_permission_result)
	OS.request_permissions()

func _on_permission_result(perm_name: String, granted: bool) -> void:
	if perm_name == "android.permission.ACCESS_FINE_LOCATION" and granted:
		_enable_gps()

func _enable_gps() -> void:
	if not Engine.has_singleton("PraxisMapperGPSPlugin"):
		push_warning("PraxisMapperGPSPlugin ikke fundet")
		return
	var gps := Engine.get_singleton("PraxisMapperGPSPlugin")
	gps.onLocationUpdates.connect(_on_gps_update)
	gps.StartListening()

func _on_gps_update(data: Dictionary) -> void:
	lon = float(data.get("longitude", lon))
	lat = float(data.get("latitude", lat))
	gps_fix_missing = false
	if not Coordinates.is_origin_set():
		gps_wait_active = false
		Coordinates.set_origin(lon, lat)
		_update_transform()
		_last_emitted_pos = position
		return
	var new_pos: Vector3 = Coordinates.lon_lat_to_world(lon, lat)
	if new_pos.distance_to(_last_emitted_pos) > MOVE_THRESHOLD:
		_last_emitted_pos = new_pos
		position_changed.emit(lon, lat)

func _process(delta: float) -> void:
	if gps_wait_active:
		gps_wait_elapsed += delta
		if gps_wait_elapsed >= GPS_TIMEOUT:
			gps_wait_active = false
			Coordinates.set_origin(lon, lat)
			_update_transform()
			_last_emitted_pos = position

	if _use_sensors:
		var compass: float = _compass_heading()
		if not is_nan(compass):
			heading = rad_to_deg(lerp_angle(deg_to_rad(heading), compass, delta * COMPASS_LERP_RATE))
	else:
		var moved := false
		if Input.is_key_pressed(KEY_W):
			lat += MOVE_SPEED * delta
			moved = true
		if Input.is_key_pressed(KEY_S):
			lat -= MOVE_SPEED * delta
			moved = true
		if Input.is_key_pressed(KEY_A):
			lon -= MOVE_SPEED * delta
			moved = true
		if Input.is_key_pressed(KEY_D):
			lon += MOVE_SPEED * delta
			moved = true

		if moved and position.distance_to(_last_emitted_pos) > MOVE_THRESHOLD:
			_last_emitted_pos = position
			position_changed.emit(lon, lat)

	_update_transform()

# Kompas via Android SensorManager.getRotationMatrix + getOrientation:
# https://developer.android.com/develop/sensors-and-location/sensors/sensors_position
# Returnerer azimuth i radianer (0 = nord, PI/2 = øst).
# Returnerer NAN hvis sensorerne ikke er klar (kan ske)
#
# Input.get_gravity() peger nedad, men formlen forventer en vektor der peger
# opad. Derfor vendes den.
func _compass_heading() -> float:
	var gravity: Vector3 = -Input.get_gravity()
	var magnetic: Vector3 = Input.get_magnetometer()
	if gravity.length_squared() < 0.01 or magnetic.length_squared() < 0.01:
		return NAN

	var h: Vector3 = magnetic.cross(gravity)  # east
	if h.length_squared() < 0.01:
		return NAN
	h = h.normalized()

	var a: Vector3 = gravity.normalized()
	var m: Vector3 = a.cross(h)  # north

	return atan2(h.y, m.y) + deg_to_rad(compass_offset_deg)

func _update_transform() -> void:
	position = Coordinates.lon_lat_to_world(lon, lat)
	rotation.y = deg_to_rad(-heading)
	Coordinates.player_lon = lon
	Coordinates.player_lat = lat
	Coordinates.player_world_pos = position
	Coordinates.player_heading_rad = deg_to_rad(-heading)
