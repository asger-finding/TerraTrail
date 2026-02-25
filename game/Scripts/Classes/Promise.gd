class_name Promise
extends RefCounted

var _result = null
var _is_resolved: bool = false

func set_result(result) -> void:
	_result = result
	_is_resolved = true

func async():
	while not _is_resolved:
		await Engine.get_main_loop().process_frame
	return _result
