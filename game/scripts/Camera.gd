extends Camera3D

enum Mode { FOLLOW, FREE }

@export var follow_distance: float = 200.0
@export var follow_height: float = 150.0
@export var follow_speed: float = 4.0
@export var min_distance: float = 100.0
@export var max_distance: float = 1500.0
@export var zoom_step: float = 1.2
@export var max_pan_distance: float = 2000.0
@export var elastic_rate: float = 8.0

var mode: Mode = Mode.FOLLOW
var pivot: Vector3 = Vector3.ZERO
var free_yaw: float = 0.0
var top_down: bool = false
var is_dragging: bool = false
var _snap_next: bool = false
var _rebound_to_player: bool = false

func _ready() -> void:
	add_to_group("main_camera")
	near = 10.0
	far = 20000.0

func handle_zoom(zoom_in: bool) -> void:
	if zoom_in:
		follow_distance = clamp(follow_distance / zoom_step, min_distance, max_distance)
	else:
		follow_distance = clamp(follow_distance * zoom_step, min_distance, max_distance)

func reset_to_player() -> void:
	mode = Mode.FOLLOW
	free_yaw = 0.0
	_snap_next = true
	_rebound_to_player = false

func rebound_to_player() -> void:
	# Snap tilbage til spilleren (bruges ved korte drag under threshold)
	if mode == Mode.FREE:
		_rebound_to_player = true

func toggle_top_down() -> void:
	top_down = not top_down

func reset_north() -> void:
	_ensure_free_mode()
	var diff := wrapf(-free_yaw, -PI, PI)
	var target := free_yaw + diff
	var tween := create_tween()
	tween.tween_property(self, "free_yaw", target, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func pan_world(world_delta: Vector3) -> void:
	_ensure_free_mode()
	_rebound_to_player = false
	# Et drag flytter kameraet mindre, jo længere det er uden for grænsen
	var from_player := pivot - Coordinates.player_world_pos
	var overshoot := from_player.length() - max_pan_distance
	if overshoot > 0.0:
		var resistance := 1.0 / (1.0 + overshoot / max_pan_distance)
		pivot += world_delta * resistance
	else:
		pivot += world_delta

func rotate_yaw(delta: float) -> void:
	_ensure_free_mode()
	_rebound_to_player = false
	free_yaw += delta

func _ensure_free_mode() -> void:
	if mode == Mode.FREE:
		return
	pivot = Coordinates.player_world_pos
	free_yaw = Coordinates.player_heading_rad
	mode = Mode.FREE

func get_view_yaw() -> float:
	return free_yaw if mode == Mode.FREE else Coordinates.player_heading_rad

func _process(delta: float) -> void:
	if not Coordinates.is_origin_set():
		return

	Coordinates.camera_distance = follow_distance

	# Spring kun tilbage når brugeren ikke aktivt drager
	if mode == Mode.FREE and not is_dragging:
		if _rebound_to_player:
			pivot = pivot.lerp(Coordinates.player_world_pos, elastic_rate * delta)
			if pivot.distance_squared_to(Coordinates.player_world_pos) < 1.0:
				mode = Mode.FOLLOW
				free_yaw = 0.0
				_rebound_to_player = false
		else:
			var from_player := pivot - Coordinates.player_world_pos
			var dist := from_player.length()
			if dist > max_pan_distance:
				var clamped := Coordinates.player_world_pos + from_player.normalized() * max_pan_distance
				pivot = pivot.lerp(clamped, elastic_rate * delta)

	var target: Vector3 = pivot if mode == Mode.FREE else Coordinates.player_world_pos
	var yaw: float = free_yaw if mode == Mode.FREE else Coordinates.player_heading_rad

	var desired: Vector3
	if top_down:
		desired = target + Vector3(0.0, follow_distance, 0.0)
	else:
		var back := Vector3(sin(yaw), 0.0, cos(yaw)) * follow_distance
		var height := follow_height * (follow_distance / 200.0)
		desired = target + back + Vector3(0.0, height, 0.0)

	if _snap_next:
		global_position = desired
		_snap_next = false
	else:
		global_position = global_position.lerp(desired, follow_speed * delta)

	if top_down:
		# Top-down "up" roterer med yaw så skærm-orientering matcher 3D-mode
		look_at(target, Vector3(-sin(yaw), 0.0, -cos(yaw)))
	else:
		look_at(target, Vector3.UP)

	Coordinates.top_down = top_down
	Coordinates.view_yaw = yaw
