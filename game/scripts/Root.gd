extends Node

@onready var page_container: Control = %PageContainer
@onready var map: Node3D = %Map
@onready var navbar: Control = %Navbar

func _ready() -> void:
	Router.setup(page_container, map, navbar)
	if PlayerState.is_authenticated():
		Router.goto("waypoints")
	else:
		Router.goto("splash")
