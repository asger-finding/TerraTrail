extends Node

signal page_changed(page_name: String)

const PAGES := {
	"splash": preload("res://scenes/pages/Splash.tscn"),
	"login": preload("res://scenes/pages/Login.tscn"),
	"signup": preload("res://scenes/pages/Signup.tscn"),
	"waypoints": preload("res://scenes/pages/Waypoints.tscn"),
	"profile": preload("res://scenes/pages/Profile.tscn"),
	"achievements": preload("res://scenes/pages/Achievements.tscn"),
	"scanner": preload("res://scenes/pages/Scanner.tscn"),
}

# Sider hvor vi viser kortet
const PAGES_WITH_MAP: PackedStringArray = ["waypoints"]

# Sider hvor navigationsbaren skal skjules
const PAGES_WITHOUT_NAVBAR: PackedStringArray = ["splash", "login", "signup", "scanner"]

# Sider hvis instans beholdes i hukommelsen mellem besøg
const PAGES_RETAINED: PackedStringArray = ["waypoints"]

var _stack: Array[String] = []
var meta: Dictionary = {}
var _page_container: Control
var _map: Node3D
var _map_parent: Node
var _navbar: Control
var _pages: Dictionary = {}

func setup(page_container: Control, map: Node3D, navbar: Control) -> void:
	_page_container = page_container
	_map = map
	_map_parent = map.get_parent()
	_navbar = navbar
	# Start with map removed from tree
	_map_parent.remove_child(_map)

func current() -> String:
	return _stack.back() if _stack.size() > 0 else ""

func goto(page_name: String, page_meta: Dictionary = {}) -> void:
	_stack.clear()
	_show(page_name, page_meta)

func push(page_name: String, page_meta: Dictionary = {}) -> void:
	_show(page_name, page_meta)

func back() -> void:
	if _stack.size() <= 1:
		return
	_stack.pop_back()
	var previous: String = _stack.pop_back()
	_show(previous)

func _show(page_name: String, page_meta: Dictionary = {}) -> void:
	meta = page_meta
	assert(page_name in PAGES, "Unknown page: %s" % page_name)

	# Frigør ikke-retained sider; detach retained sider så de kan genbruges
	for child: Node in _page_container.get_children():
		if child in _pages.values():
			_page_container.remove_child(child)
		else:
			child.queue_free()

	# Genbrug cached instans hvis siden er retained og allerede besøgt
	var instance: Node = _pages.get(page_name)
	if instance == null:
		var scene: PackedScene = PAGES[page_name]
		instance = scene.instantiate()
		if page_name in PAGES_RETAINED:
			_pages[page_name] = instance
	_page_container.add_child(instance)

	_stack.append(page_name)

	# Tilføj/fjern kortet fra scenetræet
	var show_map := page_name in PAGES_WITH_MAP
	var map_in_tree := _map.is_inside_tree()
	if show_map and not map_in_tree:
		_map_parent.add_child(_map)
		_map_parent.move_child(_map, 0)
	elif not show_map and map_in_tree:
		_map_parent.remove_child(_map)

	_navbar.visible = page_name not in PAGES_WITHOUT_NAVBAR

	page_changed.emit(page_name)
