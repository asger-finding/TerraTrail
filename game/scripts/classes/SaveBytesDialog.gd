class_name SaveBytesDialog

# Åbner en native gem-dialog og skriver de medsendte bytes til den valgte sti.
static func open(parent: Node, bytes: PackedByteArray, filename: String) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.png", "PNG-billede")
	dialog.current_file = filename
	dialog.use_native_dialog = true
	dialog.file_selected.connect(func(path: String) -> void:
		dialog.queue_free()
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(bytes)
	)
	dialog.canceled.connect(dialog.queue_free)
	parent.add_child(dialog)
	dialog.popup_centered_ratio(0.7)
