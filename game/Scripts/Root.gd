extends Node

@onready var page_container: Control = %PageContainer
@onready var map: Node3D = %Map
@onready var navbar: Control = %Navbar

func _ready() -> void:
	Router.setup(page_container, map, navbar);
	Router.goto("splash")
