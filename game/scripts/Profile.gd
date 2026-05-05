extends Control

const COLUMNS: int = 4
const EXP_PER_LEVEL: int = 50
const WAYPOINT_TILE := preload("res://scenes/components/WaypointTile.tscn")

@onready var username_label: Label = %Username
@onready var exp_bar: ProgressBar = %ExpBar
@onready var exp_bar_label: Label = %ExpBarLabel
@onready var grid: GridContainer = %MyWaypointsGrid
@onready var profile_icon: TextureButton = %ProfileIcon
@onready var username_input: LineEdit = %UsernameInput
@onready var password_input: LineEdit = %PasswordInput
@onready var current_password_input: LineEdit = %CurrentPasswordInput
@onready var status_label: Label = %StatusLabel

var _my_username: String = ""

func _ready() -> void:
	grid.columns = COLUMNS
	username_label.text = ""
	exp_bar.value = 0
	_load_me()
	_load_my_waypoints()

func _load_me() -> void:
	var http := Backend.request_me()
	http.request_completed.connect(_on_me_response.bind(http))

func _on_me_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_error("/api/me failed: result=%d code=%d" % [result, code])
		return
	var json := JSON.new()
	json.parse(body.get_string_from_utf8())
	var data: Dictionary = json.data
	_my_username = data["username"]
	var exp_value: int = data["exp"]
	var level: int = (exp_value / EXP_PER_LEVEL) + 1
	var into_level: int = exp_value % EXP_PER_LEVEL
	var next_threshold: int = level * EXP_PER_LEVEL
	username_label.text = _my_username
	username_input.text = _my_username
	exp_bar.max_value = EXP_PER_LEVEL
	exp_bar.value = into_level
	exp_bar_label.text = "Level %d (%d/%d exp)" % [level, exp_value, next_threshold]

func _load_my_waypoints() -> void:
	var http := Backend.request_my_waypoints()
	http.request_completed.connect(_on_my_waypoints_response.bind(http))

func _on_my_waypoints_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_error("/api/waypoints/mine failed: result=%d code=%d" % [result, code])
		return
	var json := JSON.new()
	json.parse(body.get_string_from_utf8())
	for wp: Dictionary in json.data["waypoints"]:
		var tile := WAYPOINT_TILE.instantiate()
		grid.add_child(tile)
		tile.populate(wp)
		tile.pressed.connect(_on_waypoint_tile_pressed)

func _on_waypoint_tile_pressed(wp: Dictionary) -> void:
	var popup := get_tree().get_first_node_in_group("waypoint_popup")
	popup.open(wp, false)

func _on_save_pressed() -> void:
	var new_username := username_input.text.strip_edges()
	var new_password := password_input.text
	var current_password := current_password_input.text

	if new_username == _my_username:
		new_username = ""

	if new_username.is_empty() and new_password.is_empty():
		status_label.text = "Ingen ændringer"
		return
	if current_password.is_empty():
		status_label.text = "Nuværende password er påkrævet"
		return

	status_label.text = "Gemmer..."
	var result: Dictionary = await Backend.update_credentials(current_password, new_username, new_password)
	if not result["ok"]:
		status_label.text = result["error"]
		return

	if not new_username.is_empty():
		_my_username = new_username
		username_label.text = new_username
	password_input.text = ""
	current_password_input.text = ""
	status_label.text = "Ændringer gemt"

func _on_logout_pressed() -> void:
	await Backend.logout()
	PlayerState.clear()
	Router.goto("splash")

func _on_profile_icon_pressed() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.png,*.jpg,*.jpeg,*.webp", "Billeder")
	dialog.use_native_dialog = true
	dialog.file_selected.connect(_on_picture_selected.bind(dialog))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.7)

func _on_picture_selected(picked_path: String, dialog: FileDialog) -> void:
	dialog.queue_free()
	var f := FileAccess.open(picked_path, FileAccess.READ)
	var bytes := f.get_buffer(f.get_length())
	var result: Dictionary = await Backend.upload_profile_picture(bytes)
	if not result["ok"]:
		push_error("Profilbillede upload fejlede: %s" % result["error"])
		return
	profile_icon.refresh()
