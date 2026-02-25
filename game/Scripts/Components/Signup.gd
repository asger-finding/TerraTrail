extends VBoxContainer

@onready var username_input: LineEdit = %UsernameInput
@onready var password_input: LineEdit = %PasswordInput
@onready var submit_button: Button = %RegisterButton

func _on_submit_signup_button_button_up() -> void:
	var username := username_input.text.strip_edges()
	var password := password_input.text

	if username.is_empty() or password.is_empty():
		push_warning("Username og password er påkrævet")
		return

	if password.length() < 8:
		push_warning("Password skal være mindst 8 tegn")
		return

	submit_button.disabled = true
	var result: Dictionary = await Backend.signup(username, password)
	submit_button.disabled = false

	if not result["ok"]:
		push_warning("Signup fejl: %s" % result["error"])
		return

	PlayerState.set_from_response(result["data"])
	visible = false
