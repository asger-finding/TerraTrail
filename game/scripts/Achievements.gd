extends Control

const COLUMNS: int = 4
const CELL_SIZE: Vector2 = Vector2(80, 80)
const EXP_PER_LEVEL: int = 50
const WAYPOINT_TILE := preload("res://scenes/components/WaypointTile.tscn")

@onready var username_label: Label = %Username
@onready var exp_bar: ProgressBar = %ExpBar
@onready var exp_bar_label: Label = %ExpBarLabel
@onready var achievement_grid: GridContainer = %AchievementGrid
@onready var completed_grid: GridContainer = %CompletedGrid

func _ready() -> void:
	achievement_grid.columns = COLUMNS
	completed_grid.columns = COLUMNS
	username_label.text = ""
	exp_bar.value = 0
	_load_me()
	_load_achievements()
	_load_completed()

func _load_me() -> void:
	var http := Backend.request_me()
	http.request_completed.connect(_on_me_response.bind(http))

func _on_me_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	var data: Dictionary = json.data
	var username := String(data.get("username", ""))
	var exp_value: int = int(data.get("exp", 0))
	var level: int = (exp_value / EXP_PER_LEVEL) + 1
	var into_level: int = exp_value % EXP_PER_LEVEL
	var next_threshold: int = level * EXP_PER_LEVEL
	username_label.text = username
	exp_bar.max_value = EXP_PER_LEVEL
	exp_bar.value = into_level
	exp_bar_label.text = "Level %d (%d/%d exp)" % [level, exp_value, next_threshold]

func _load_achievements() -> void:
	var http := Backend.request_achievements()
	http.request_completed.connect(_on_achievements_response.bind(http))

func _on_achievements_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	var list: Array = json.data.get("achievements", [])
	for entry: Dictionary in list:
		achievement_grid.add_child(_make_achievement_cell(entry))

func _load_completed() -> void:
	var http := Backend.request_completed_waypoints()
	http.request_completed.connect(_on_completed_response.bind(http))

func _on_completed_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	var list: Array = json.data.get("waypoints", [])
	for wp: Dictionary in list:
		if String(wp.get("imagePath", "")).is_empty():
			continue
		var tile := WAYPOINT_TILE.instantiate()
		completed_grid.add_child(tile)
		tile.populate(wp)

func _make_achievement_cell(entry: Dictionary) -> Control:
	var btn := TextureButton.new()
	btn.custom_minimum_size = CELL_SIZE
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.texture_normal = load("res://assets/achievements/%d.svg" % int(entry.get("id", 0)))
	btn.tooltip_text = "%s\n%s" % [String(entry.get("title", "")), String(entry.get("description", ""))]
	btn.pressed.connect(_on_achievement_pressed.bind(entry))
	return btn

func _on_achievement_pressed(entry: Dictionary) -> void:
	var popup := get_tree().get_first_node_in_group("unlocked_achievement_popup")
	if popup:
		popup.open(entry)
