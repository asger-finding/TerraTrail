extends Control

const ITEM_SCENE := preload("res://scenes/components/FavouriteItem.tscn")

@onready var close_button: Button = %CloseButton
@onready var list_container: VBoxContainer = %FavList
@onready var status_label: Label = %FavStatus

var _waypoints: Array = []

func _ready() -> void:
	add_to_group("favourites_menu")
	visible = false
	close_button.pressed.connect(close)

func open() -> void:
	visible = true
	_show_loading()
	var http := Backend.request_favourites()
	http.request_completed.connect(_on_favourites_response.bind(http))

func close() -> void:
	visible = false

func _show_loading() -> void:
	_clear_list()
	status_label.text = "Henter..."

func _on_favourites_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status_label.text = "Kunne ikke hente favoritter"
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		status_label.text = "Ugyldigt svar fra server"
		return
	_waypoints = json.data.get("waypoints", [])
	_populate()

func _populate() -> void:
	_clear_list()
	if _waypoints.is_empty():
		status_label.text = "Ingen favoritter endnu"
		return
	status_label.text = "Favoritter"
	for wp: Dictionary in _waypoints:
		var item := ITEM_SCENE.instantiate()
		list_container.add_child(item)
		item.populate(wp)
		item.row_pressed.connect(_on_row_pressed)

func _clear_list() -> void:
	for child in list_container.get_children():
		child.queue_free()

func _on_row_pressed(wp: Dictionary) -> void:
	var popup := get_tree().get_first_node_in_group("waypoint_popup")
	if popup == null:
		return
	popup.closed.connect(_on_popup_closed, CONNECT_ONE_SHOT)
	visible = false
	popup.open(wp)

func _on_popup_closed() -> void:
	visible = true
