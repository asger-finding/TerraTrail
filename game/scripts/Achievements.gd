extends Control

const COLUMNS: int = 4
const CELL_SIZE: Vector2 = Vector2(80, 80)
const EXP_PER_LEVEL: int = 50
const WAYPOINT_TILE := preload("res://scenes/components/WaypointTile.tscn")
const LEADERBOARD_ROW := preload("res://scenes/components/LeaderboardRow.tscn")

@onready var username_label: Label = %Username
@onready var exp_bar: ProgressBar = %ExpBar
@onready var exp_bar_label: Label = %ExpBarLabel
@onready var achievement_grid: GridContainer = %AchievementGrid
@onready var completed_grid: GridContainer = %CompletedGrid
@onready var leaderboard_list: VBoxContainer = %LeaderboardList

var _my_username: String = ""

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

func _on_me_response(_result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	var json := JSON.new()
	json.parse(body.get_string_from_utf8())
	var data: Dictionary = json.data
	_my_username = data["username"]
	var exp_value: int = data["exp"]
	var level: int = (exp_value / EXP_PER_LEVEL) + 1
	var into_level: int = exp_value % EXP_PER_LEVEL
	var next_threshold: int = level * EXP_PER_LEVEL
	username_label.text = _my_username
	exp_bar.max_value = EXP_PER_LEVEL
	exp_bar.value = into_level
	exp_bar_label.text = "Level %d (%d/%d exp)" % [level, exp_value, next_threshold]
	_load_leaderboard()

func _load_achievements() -> void:
	var http := Backend.request_achievements()
	http.request_completed.connect(_on_achievements_response.bind(http))

func _on_achievements_response(_result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	var json := JSON.new()
	json.parse(body.get_string_from_utf8())
	for entry: Dictionary in json.data["achievements"]:
		achievement_grid.add_child(_make_achievement_cell(entry))

func _load_completed() -> void:
	var http := Backend.request_completed_waypoints()
	http.request_completed.connect(_on_completed_response.bind(http))

func _on_completed_response(_result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	var json := JSON.new()
	json.parse(body.get_string_from_utf8())
	for wp: Dictionary in json.data["waypoints"]:
		if String(wp["imagePath"]).is_empty():
			continue
		var tile := WAYPOINT_TILE.instantiate()
		completed_grid.add_child(tile)
		tile.populate(wp)

func _make_achievement_cell(entry: Dictionary) -> Control:
	var btn := TextureButton.new()
	btn.custom_minimum_size = CELL_SIZE
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.texture_normal = load("res://assets/achievements/%d.svg" % int(entry["id"]))
	btn.tooltip_text = "%s\n%s" % [entry["title"], entry["description"]]
	btn.pressed.connect(_on_achievement_pressed.bind(entry))
	return btn

func _on_achievement_pressed(entry: Dictionary) -> void:
	var popup := get_tree().get_first_node_in_group("unlocked_achievement_popup")
	popup.open(entry)

func _load_leaderboard() -> void:
	var http := Backend.request_leaderboard()
	http.request_completed.connect(_on_leaderboard_response.bind(http))

func _on_leaderboard_response(_result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	var json := JSON.new()
	json.parse(body.get_string_from_utf8())
	for entry: Dictionary in json.data["entries"]:
		var row := LEADERBOARD_ROW.instantiate()
		leaderboard_list.add_child(row)
		row.populate(int(entry["rank"]), entry["username"], int(entry["exp"]), entry["username"] == _my_username)
