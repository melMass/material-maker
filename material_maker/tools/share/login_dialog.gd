extends WindowDialog


signal return_status(status)


func _ready():
	yield(get_tree(), "idle_frame")
	_on_MarginContainer_minimum_size_changed()

func _on_LoginButton_pressed():
	emit_signal("return_status", "ok")

func _on_LoginDialog_popup_hide() -> void:
	emit_signal("return_status", "cancel")

func ask(user : String, password : String) -> String:
	mm_globals.main_window.add_dialog(self)
	if user != "":
		$MarginContainer/VBoxContainer/UserName.text = user
		$MarginContainer/VBoxContainer/SaveUser.pressed = true
	if password != "":
		$MarginContainer/VBoxContainer/Password.text = password
		$MarginContainer/VBoxContainer/SavePassword.pressed = true
	popup_centered()
	var result = yield(self, "return_status")
	queue_free()
	if result == "ok":
		return {
			user=$MarginContainer/VBoxContainer/UserName.text,
			save_user=$MarginContainer/VBoxContainer/SaveUser.pressed,
			password=$MarginContainer/VBoxContainer/Password.text,
			save_password=$MarginContainer/VBoxContainer/SavePassword.pressed
		}
	return {}

func _on_MarginContainer_minimum_size_changed():
	rect_size = $MarginContainer.get_minimum_size()

func _on_RegisterButton_pressed():
	OS.shell_open(MMPaths.WEBSITE_ADDRESS+"/register")
