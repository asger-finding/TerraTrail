extends Node

const BASE_URL := "http://localhost:3000"

var _http: HTTPRequest

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)

func signup(username: String, password: String) -> Dictionary:
	var url := BASE_URL + "/api/auth/register"
	var body := JSON.stringify({"username": username, "password": password})
	return await _post(url, body)

func login(username: String, password: String) -> Dictionary:
	var url := BASE_URL + "/api/auth/login"
	var body := JSON.stringify({"username": username, "password": password})
	return await _post(url, body)

func auth_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % PlayerState.token
	])

func request_tiles(bbox: String, zoom: int) -> HTTPRequest:
	var url := "%s/api/tiles?bbox=%s&zoom=%d" % [BASE_URL, bbox, zoom]
	var http := HTTPRequest.new()
	add_child(http)
	http.request(url, auth_headers())
	return http

func request_route(from: String, to: String, origin_lon: float, origin_lat: float) -> HTTPRequest:
	var url := "%s/api/route?from=%s&to=%s&origin=%s,%s" % [
		BASE_URL, from, to, str(origin_lon), str(origin_lat)
	]
	var http := HTTPRequest.new()
	add_child(http)
	http.request(url, auth_headers())
	return http

func _post(url: String, body: String) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)

	var promise := Promise.new()
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, response_body: PackedByteArray) -> void:
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			promise.set_result({"ok": false, "error": "Forbindelsesfejl"})
			return
		var json := JSON.new()
		if json.parse(response_body.get_string_from_utf8()) != OK:
			promise.set_result({"ok": false, "error": "Ugyldigt svar fra server"})
			return
		var data: Dictionary = json.data
		if code >= 400:
			promise.set_result({"ok": false, "error": data.get("error", "Ukendt fejl")})
			return
		promise.set_result({"ok": true, "data": data})
	)

	http.request(url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body)
	return await promise.async()
