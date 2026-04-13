extends Node3D

signal position_changed(lon: float, lat: float)

# Desktop mock position
var mock_lon: float = 12.543
var mock_lat: float = 55.764
var mock_heading: float = 0.0

# Movement speed in degrees per second (desktop mock)
const MOCK_MOVE_SPEED: float = 0.0005
const MOCK_ROTATE_SPEED: float = 90.0

# Minimum distance in meters before emitting position_changed
const MOVE_THRESHOLD: float = 10.0
var _last_emitted_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	Coordinates.set_origin(mock_lon, mock_lat)
	_update_transform()
	_last_emitted_pos = position

func _process(delta: float) -> void:
	# Desktop mock movement
	var moved := false

	if Input.is_key_pressed(KEY_W):
		mock_lat += MOCK_MOVE_SPEED * delta * 10.0
		moved = true
	if Input.is_key_pressed(KEY_S):
		mock_lat -= MOCK_MOVE_SPEED * delta * 10.0
		moved = true
	if Input.is_key_pressed(KEY_A):
		mock_lon -= MOCK_MOVE_SPEED * delta * 10.0
		moved = true
	if Input.is_key_pressed(KEY_D):
		mock_lon += MOCK_MOVE_SPEED * delta * 10.0
		moved = true

	if Input.is_key_pressed(KEY_Q):
		mock_heading -= MOCK_ROTATE_SPEED * delta
	if Input.is_key_pressed(KEY_E):
		mock_heading += MOCK_ROTATE_SPEED * delta

	_update_transform()

	if moved and position.distance_to(_last_emitted_pos) > MOVE_THRESHOLD:
		_last_emitted_pos = position
		position_changed.emit(mock_lon, mock_lat)

func _update_transform() -> void:
	position = Coordinates.lon_lat_to_world(mock_lon, mock_lat)
	rotation.y = deg_to_rad(-mock_heading)
	Coordinates.player_world_pos = position
	Coordinates.player_heading_rad = deg_to_rad(-mock_heading)
