extends TextureButton

func _on_pressed() -> void:
	Router.push("create_waypoint")
