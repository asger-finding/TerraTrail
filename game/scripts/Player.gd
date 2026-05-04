extends Node3D

signal position_changed(lon: float, lat: float)

const MOVE_SPEED: float = 0.005   # degrees pr. sekund (WASD)
const MOVE_THRESHOLD: float = 10.0  # meter før position_changed emittes
const COMPASS_LERP_RATE: float = 8.0
const GPS_TIMEOUT: float = 10.0
const HEAD_TURN_MAX_RAD: float = deg_to_rad(60.0)
const BODY_TURN_TRIGGER_RAD: float = HEAD_TURN_MAX_RAD + deg_to_rad(20.0)
const BODY_TURN_RELEASE_RAD: float = deg_to_rad(2.0)
const BODY_LERP_RATE: float = 6.0
const WALK_TIMEOUT: float = 1.5  # sek. uden bevægelse før vi falder tilbage til idle
const ANIM_FADE: float = 0.2
const HEAD_BONE_NAME: String = "neck"
const ANIM_WALK: String = "walk"
const ANIM_IDLE: String = "idle"

@export var compass_offset_deg: float = 0.0

var lon: float = 12.543
var lat: float = 55.764
var heading: float = 0.0  # grader, 0 = nord
var body_yaw: float = 0.0  # rotation.y target, kan halte efter heading

var gps_wait_active: bool = false
var gps_wait_elapsed: float = 0.0
var gps_fix_missing: bool = false

var _last_emitted_pos: Vector3 = Vector3.ZERO
var _use_sensors: bool = false
var _anim_player: AnimationPlayer
var _skeleton: Skeleton3D
var _head_bone_idx: int = -1
var _time_since_move: float = INF
var _current_anim: String = ""
var _body_turning: bool = false

func _ready() -> void:
	add_to_group("player")
	_anim_player = find_child("AnimationPlayer", true, false)
	_skeleton = find_child("Skeleton3D", true, false)
	if _skeleton:
		_head_bone_idx = _skeleton.find_bone(HEAD_BONE_NAME)
	body_yaw = deg_to_rad(-heading)
	_play_anim(ANIM_IDLE)
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
		_time_since_move = 0.0
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
			_time_since_move = 0.0
			position_changed.emit(lon, lat)

	_time_since_move += delta
	_update_anim_state()
	_update_transform(delta)

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

func _update_transform(delta: float = 0.0) -> void:
	position = Coordinates.lon_lat_to_world(lon, lat)
	var compass_yaw: float = deg_to_rad(-heading)
	var yaw_delta: float = wrapf(compass_yaw - body_yaw, -PI, PI)

	if not _body_turning and absf(yaw_delta) > BODY_TURN_TRIGGER_RAD:
		_body_turning = true

	if _body_turning:
		body_yaw = lerp_angle(body_yaw, compass_yaw, BODY_LERP_RATE * delta)
		yaw_delta = wrapf(compass_yaw - body_yaw, -PI, PI)
		if absf(yaw_delta) < BODY_TURN_RELEASE_RAD:
			_body_turning = false

	yaw_delta = clampf(yaw_delta, -HEAD_TURN_MAX_RAD, HEAD_TURN_MAX_RAD)
	rotation.y = body_yaw
	if _skeleton and _head_bone_idx != -1:
		_skeleton.set_bone_pose_rotation(_head_bone_idx, Quaternion(Vector3.UP, yaw_delta))
	Coordinates.player_lon = lon
	Coordinates.player_lat = lat
	Coordinates.player_world_pos = position
	Coordinates.player_heading_rad = compass_yaw

func _update_anim_state() -> void:
	var want := ANIM_WALK if _time_since_move < WALK_TIMEOUT else ANIM_IDLE
	_play_anim(want)

func _play_anim(name: String) -> void:
	if name == _current_anim:
		return
	if _anim_player == null or not _anim_player.has_animation(name):
		return
	_anim_player.play(name, ANIM_FADE)
	_current_anim = name
