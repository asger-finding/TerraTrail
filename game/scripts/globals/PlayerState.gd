extends Node

signal authenticated

const SAVE_PATH := "user://auth.json"

var token: String = ""
var player_id: int = -1
var username: String = ""
var created: int = 0
var last_login: int = 0

func _ready() -> void:
	_load()

func is_authenticated() -> bool:
	return token != ""

func set_from_response(data: Dictionary) -> void:
	token = data["token"]
	var player: Dictionary = data["player"]
	player_id = int(player["playerId"])
	username = player["username"]
	created = int(player["created"])
	last_login = int(player["lastLogin"])
	_save()
	authenticated.emit()

func clear() -> void:
	token = ""
	player_id = -1
	username = ""
	created = 0
	last_login = 0
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"token": token,
		"player_id": player_id,
		"username": username,
		"created": created,
		"last_login": last_login,
	}))

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data: Dictionary = json.data
	token = data.get("token", "")
	player_id = int(data.get("player_id", -1))
	username = data.get("username", "")
	created = int(data.get("created", 0))
	last_login = int(data.get("last_login", 0))
