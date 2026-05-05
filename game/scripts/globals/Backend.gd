extends Node

const BASE_URL := "http://localhost:3000"

var _http: HTTPRequest

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)

func signup(username: String, password: String) -> Dictionary:
	var url := BASE_URL + "/api/auth/signup"
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

func _watch_unauth(http: HTTPRequest) -> void:
	http.request_completed.connect(func(_result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		if code == 401 and PlayerState.is_authenticated():
			PlayerState.clear()
			Router.goto("splash")
	)

func _authed_get(path: String) -> HTTPRequest:
	var http := HTTPRequest.new()
	add_child(http)
	_watch_unauth(http)
	http.request(BASE_URL + path, auth_headers())
	return http

func request_tiles(bbox: String, zoom: int) -> HTTPRequest:
	return _authed_get("/api/tiles?bbox=%s&zoom=%d" % [bbox, zoom])

func request_tile(x: int, y: int, z: int) -> HTTPRequest:
	return _authed_get("/api/tile?x=%d&y=%d&z=%d" % [x, y, z])

func request_waypoints(bbox: String) -> HTTPRequest:
	return _authed_get("/api/waypoints?bbox=%s" % bbox)

func request_favourites() -> HTTPRequest:
	return _authed_get("/api/waypoints/favourites")

func request_completed_waypoints() -> HTTPRequest:
	return _authed_get("/api/waypoints/completed")

func request_achievements() -> HTTPRequest:
	return _authed_get("/api/achievements")

func request_me() -> HTTPRequest:
	return _authed_get("/api/me")

func request_leaderboard() -> HTTPRequest:
	return _authed_get("/api/leaderboard")

func request_waypoint_image(waypoint_id: int) -> HTTPRequest:
	return _authed_get("/api/waypoints/%d/image" % waypoint_id)

func request_my_waypoints() -> HTTPRequest:
	return _authed_get("/api/waypoints/mine")

func request_profile_picture() -> HTTPRequest:
	return _authed_get("/api/me/picture")

func upload_profile_picture(bytes: PackedByteArray) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	_watch_unauth(http)
	var headers := PackedStringArray([
		"Content-Type: application/octet-stream",
		"Authorization: Bearer %s" % PlayerState.token
	])
	var promise := Promise.new()
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			promise.set_result({"ok": false, "error": "Forbindelsesfejl"})
			return
		if code >= 400:
			promise.set_result({"ok": false, "error": "Upload fejlede (%d)" % code})
			return
		promise.set_result({"ok": true})
	)
	http.request_raw(BASE_URL + "/api/me/picture", headers, HTTPClient.METHOD_POST, bytes)
	return await promise.async()

func complete_waypoint(qr_secret: String) -> Dictionary:
	var url := BASE_URL + "/api/waypoints/complete"
	var body := JSON.stringify({"qrSecret": qr_secret})
	return await _post(url, body, auth_headers())

func toggle_favourite(waypoint_id: int) -> Dictionary:
	var url := "%s/api/waypoints/%d/favourite" % [BASE_URL, waypoint_id]
	return await _post(url, "", auth_headers())

func update_credentials(current_password: String, new_username: String, new_password: String) -> Dictionary:
	var url := BASE_URL + "/api/me"
	var payload: Dictionary = {"currentPassword": current_password}
	if not new_username.is_empty():
		payload["newUsername"] = new_username
	if not new_password.is_empty():
		payload["newPassword"] = new_password
	return await _post(url, JSON.stringify(payload), auth_headers(), HTTPClient.METHOD_PATCH)

func logout() -> Dictionary:
	var url := BASE_URL + "/api/auth/logout"
	return await _post(url, "", auth_headers())

func request_route(from: String, to: String, origin_lon: float, origin_lat: float) -> HTTPRequest:
	return _authed_get("/api/route?from=%s&to=%s&origin=%s,%s" % [
		from, to, str(origin_lon), str(origin_lat)
	])

func _post(url: String, body: String, headers: PackedStringArray = PackedStringArray(), method: int = HTTPClient.METHOD_POST) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)

	if headers.is_empty():
		headers = PackedStringArray(["Content-Type: application/json"])

	for header: String in headers:
		if header.begins_with("Authorization:"):
			_watch_unauth(http)
			break

	var promise := Promise.new()
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, response_body: PackedByteArray) -> void:
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			promise.set_result({"ok": false, "error": "Forbindelsesfejl"})
			return
		# 204 No Content -> tom body, ingen JSON at parse
		if code == 204:
			promise.set_result({"ok": true, "data": {}})
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

	http.request(url, headers, method, body)
	return await promise.async()
