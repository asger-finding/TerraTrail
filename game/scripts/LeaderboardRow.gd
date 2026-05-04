extends PanelContainer

@onready var rank_label: Label = %Rank
@onready var username_label: Label = %Username
@onready var exp_label: Label = %Exp

func populate(rank: int, username: String, exp_value: int, is_me: bool) -> void:
	rank_label.text = "%d." % rank
	username_label.text = username
	exp_label.text = "%d exp" % exp_value
	if is_me:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color.BLACK
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_right = 6
		sb.corner_radius_bottom_left = 6
		sb.content_margin_left = 6.0
		sb.content_margin_top = 4.0
		sb.content_margin_right = 6.0
		sb.content_margin_bottom = 4.0
		add_theme_stylebox_override("panel", sb)
