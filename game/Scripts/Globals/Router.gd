extends Node

signal page_changed(page_name: String)

const PAGES := {
	"splash": preload("res://Scenes/Pages/Splash.tscn"),
	"login": preload("res://Scenes/Pages/Login.tscn"),
	"signup": preload("res://Scenes/Pages/Signup.tscn"),
	"main": preload("res://Scenes/Pages/Main.tscn"),
	"profile": preload("res://Scenes/Pages/Profile.tscn"),
	"settings": preload("res://Scenes/Pages/Settings.tscn"),
}

# Sider hvor vi viser kortet
const PAGES_WITH_MAP: PackedStringArray = ["main"]

# Sider hvor navigationsbaren skal skjules
const PAGES_WITHOUT_NAVBAR: PackedStringArray = ["splash", "login", "signup"]

var _stack: Array[String] = []
var meta: Dictionary = {}
var _page_container: Control
var _map: Node3D
var _map_parent: Node
var _navbar: Control

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

	for child in _page_container.get_children():
		child.queue_free()

	# Instance ny side
	var scene: PackedScene = PAGES[page_name]
	var instance := scene.instantiate()
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
