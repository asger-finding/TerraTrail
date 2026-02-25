extends Node

signal authenticated

var token: String = ""
var player_id: int = -1
var username: String = ""
var created: int = 0
var last_login: int = 0

func is_authenticated() -> bool:
	return token != ""

func set_from_response(data: Dictionary) -> void:
	token = data["token"]
	var player: Dictionary = data["player"]
	player_id = int(player["playerId"])
	username = player["username"]
	created = int(player["created"])
	last_login = int(player["lastLogin"])
	print("Authenticated as %s (id %d)" % [username, player_id])
	authenticated.emit()

func clear() -> void:
	token = ""
	player_id = -1
	username = ""
	created = 0
	last_login = 0
