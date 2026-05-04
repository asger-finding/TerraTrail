extends Control

@onready var title_label: Label = %Title
@onready var description_label: Label = %Description
@onready var close_button: Button = %CloseButton

func _ready() -> void:
	add_to_group("unlocked_achievement_popup")
	visible = false
	close_button.pressed.connect(close)

func open(achievement: Dictionary) -> void:
	title_label.text = String(achievement.get("title", ""))
	description_label.text = String(achievement.get("description", ""))
	visible = true

func close() -> void:
	visible = false
