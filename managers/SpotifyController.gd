extends Node
## SpotifyController (autoload) — the live NETWORK layer for the optional Spotify radio. Owns the OAuth
## session (PKCE link via the system browser + a localhost loopback redirect), single-flight token refresh,
## and the playback commands (play a playlist / pause / resume / stop) that the in-world Radio drives while a
## Premium account is linked. ALL the fiddly PURE logic (PKCE, URL/body building, redirect parse, refresh
## timing) lives in SpotifyAuth and is unit-tested; this node only adds the I/O (HTTPRequest + TCPServer) and
## the session state, plus the multi-radio "owner token" so two radios never fight over one account.
##
## Config (client_id, scopes, ports, margins) comes from GameSettings.radio. The long-lived refresh token is
## stored via Settings; the SHORT-LIVED access token stays in memory only and is NEVER persisted. PROCESS_MODE_
## ALWAYS so the loopback capture keeps polling even while a pausing Options menu drives the link flow.
##
## VERIFICATION NOTE: real OAuth + playback need the network, a real Premium account, and your Spotify dev-app
## client_id, so they are MANUAL-PLAYTEST territory. The unit-testable pieces are SpotifyAuth (its own tests)
## and the owner-token arbitration here (test_spotify_controller.gd). No class_name: it's reached as the
## autoload `SpotifyController`.

signal account_linked(display_name: String)
signal account_unlinked()
signal playback_error(message: String)
signal now_playing_changed(title: String, artist: String)  ## current track for NowPlayingHud; ("","") = nothing playing
signal _refresh_done()  ## internal: concurrent ensure_token() callers await this for single-flight refresh

const API_BASE := "https://api.spotify.com/v1"

var _auth := SpotifyAuth.new()
var _access_token: String = ""        ## SHORT-LIVED — memory only, NEVER persisted
var _token_expiry_unix: float = 0.0
var _product: String = ""             ## "premium" / "free" — cached from /me, re-read per play attempt
var _display_name: String = ""
var _account_id: String = ""           ## Spotify user id from /me (captured at link, persisted via Settings)

# OAuth-in-flight state
var _verifier: String = ""
var _expected_state: String = ""
var _redirect_uri: String = ""
var _server: TCPServer = null
var _peer: StreamPeerTCP = null
var _req: String = ""
var _auth_in_flight: bool = false

var _refresh_in_flight: bool = false  # single-flight guard for ensure_token()
var _owner: int = 0                   # instance id of the Radio that currently drives external playback

# Now-playing readout — polled while a radio owns playback (M4)
var _np_title: String = ""
var _np_artist: String = ""
var _np_poll_t: float = 0.0
var _np_in_flight: bool = false

func _ready() -> void:
	# Keep the loopback poll + any in-flight command alive even while a pausing Options menu drives the link.
	process_mode = Node.PROCESS_MODE_ALWAYS

# ---------------------------------------------------------------------------
# State predicates
# ---------------------------------------------------------------------------

func is_linked() -> bool:
	return Settings.spotify_is_linked()

func is_premium() -> bool:
	return _product == "premium"

## True when the radio may use Spotify: config valid + opted in + an account linked. Premium is re-checked
## per play attempt (it can change mid-session), so it is deliberately NOT gated here.
func can_use_spotify() -> bool:
	return GameSettings.radio.validate() and Settings.spotify_enabled and is_linked()

# ---------------------------------------------------------------------------
# Multi-radio owner token (PURE — unit-tested). Only the owning Radio's commands take effect, so two radios
# in one level never hijack each other's playback.
# ---------------------------------------------------------------------------

func acquire(radio: Object) -> bool:
	if not is_instance_valid(radio):
		return false
	if _owner == 0 or _owner == radio.get_instance_id():
		_owner = radio.get_instance_id()
		return true
	return false

func owns(radio: Object) -> bool:
	return is_instance_valid(radio) and _owner == radio.get_instance_id()

func release(radio: Object) -> void:
	if owns(radio):
		_owner = 0

# ---------------------------------------------------------------------------
# OAuth (PKCE) link flow  [network — manual playtest]
# ---------------------------------------------------------------------------

## Begin linking: generate PKCE, bind a loopback redirect server, open the system browser to Spotify's consent.
func start_auth() -> void:
	if _auth_in_flight:
		return
	if not GameSettings.radio.validate():
		playback_error.emit("Spotify isn't configured — set a client_id on RadioSettings.")
		return
	if DisplayServer.get_name() == "headless":
		return
	_verifier = _auth.make_verifier()
	_expected_state = _auth.make_verifier()  # a second random string doubles as the CSRF state token
	var port := _bind_redirect_server()
	if port < 0:
		playback_error.emit("Couldn't open a local port for Spotify login.")
		return
	_auth_in_flight = true
	_redirect_uri = _auth.redirect_uri_for(port)
	var challenge := _auth.challenge_for(_verifier)
	OS.shell_open(_auth.authorize_url(GameSettings.radio.client_id, _redirect_uri, GameSettings.radio.scopes, challenge, _expected_state))

## Bind the loopback TCP server to the first free port in the configured range. Returns the port, or -1.
func _bind_redirect_server() -> int:
	var s := TCPServer.new()
	for port in range(GameSettings.radio.redirect_port_min, GameSettings.radio.redirect_port_max + 1):
		if s.listen(port, "127.0.0.1") == OK:
			_server = s
			return port
	return -1

func _process(delta: float) -> void:
	_poll_now_playing(delta)
	if _server == null:
		return
	if _peer == null:
		if not _server.is_connection_available():
			return
		_peer = _server.take_connection()
		_req = ""
	_peer.poll()
	var avail := _peer.get_available_bytes()
	if avail > 0:
		var got: Array = _peer.get_data(avail)
		if got[0] == OK:
			_req += (got[1] as PackedByteArray).get_string_from_utf8()
	# The first CRLF terminates the request line — all we need. (Or the peer closed early.)
	if _req.contains("\r\n") or _peer.get_status() == StreamPeerTCP.STATUS_NONE:
		_finish_redirect()

## Reply to the browser, tear down the loopback server, then validate state + exchange the code.
func _finish_redirect() -> void:
	var line: String = _req.split("\r\n")[0] if _req.contains("\r\n") else _req
	var parsed := _auth.parse_redirect_request(line)
	if _peer != null:
		var page := "Spotify linked — you can return to the game."
		_peer.put_data(("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [page.length(), page]).to_utf8_buffer())
		_peer.disconnect_from_host()
		_peer = null
	if _server != null:
		_server.stop()
		_server = null
	_auth_in_flight = false
	if parsed["error"] != "" or parsed["code"] == "" or parsed["state"] != _expected_state:
		playback_error.emit("Spotify login was cancelled or failed.")
		return
	_exchange_code(parsed["code"])

## Exchange the auth code for tokens, fetch the profile, persist the refresh token + account, announce linked.
func _exchange_code(code: String) -> void:
	var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded"])
	var body := _auth.token_exchange_body(GameSettings.radio.client_id, code, _verifier, _redirect_uri)
	var resp := await _http(HTTPClient.METHOD_POST, SpotifyAuth.TOKEN_URL, headers, body)
	if int(resp["code"]) != 200:
		playback_error.emit("Spotify login failed (token exchange).")
		return
	var json: Dictionary = resp["json"]
	_store_tokens(json)
	var refresh := str(json.get("refresh_token", ""))
	await _fetch_profile()
	Settings.set_spotify_account(refresh, _account_id, _display_name)
	# Linking does NOT auto-enable: the Options "Enable Spotify Radio" toggle owns that, so it can't fight the
	# staged checkbox (and a player can link but leave it off).
	account_linked.emit(_display_name)

## Forget the linked account (the Options "Unlink").
func unlink() -> void:
	_access_token = ""
	_token_expiry_unix = 0.0
	_product = ""
	_display_name = ""
	Settings.clear_spotify()
	_clear_now_playing()
	account_unlinked.emit()

# ---------------------------------------------------------------------------
# Tokens  [network — manual playtest]
# ---------------------------------------------------------------------------

func _store_tokens(json: Dictionary) -> void:
	_access_token = str(json.get("access_token", ""))
	_token_expiry_unix = Time.get_unix_time_from_system() + float(json.get("expires_in", 3600))

func _needs_refresh() -> bool:
	if not is_linked():
		return false
	if _access_token.is_empty():
		return true
	return _auth.should_refresh(Time.get_unix_time_from_system(), _token_expiry_unix, GameSettings.radio.token_refresh_margin_s)

## Ensure a fresh access token, refreshing from the stored refresh token if needed. SINGLE-FLIGHT: concurrent
## callers (a combat pause + a now-playing poll + an interact in the same instant) share ONE refresh request
## instead of each rotating the token.
func ensure_token() -> void:
	if not _needs_refresh():
		return
	if _refresh_in_flight:
		await _refresh_done
		return
	_refresh_in_flight = true
	var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded"])
	var body := _auth.token_refresh_body(GameSettings.radio.client_id, Settings.spotify_refresh_token)
	var resp := await _http(HTTPClient.METHOD_POST, SpotifyAuth.TOKEN_URL, headers, body)
	if int(resp["code"]) == 200:
		var json: Dictionary = resp["json"]
		_store_tokens(json)
		# Spotify may ROTATE the refresh token — persist the new one if present.
		var rotated := str(json.get("refresh_token", ""))
		if not rotated.is_empty():
			# Preserve the stored id/name — a refresh may run before any /me fetch, so the in-memory copies
			# can be empty; only the token is being rotated here.
			Settings.set_spotify_account(rotated, Settings.spotify_user_id, Settings.spotify_user_name)
	else:
		# A revoked / invalid refresh token: drop the link so the player is cleanly re-prompted.
		unlink()
		playback_error.emit("Spotify session expired — link again from Options.")
	_refresh_in_flight = false
	_refresh_done.emit()

# ---------------------------------------------------------------------------
# Playback control  [network — manual playtest]
# ---------------------------------------------------------------------------

## Start the designer's URI on the player's active device. Accepts a playlist / album / artist (a "context")
## OR a single track — see _play_body (a track URI is NOT a valid context_uri, the common mistake). After
## playback starts, sets the radio MODE: a single TRACK loops itself; a playlist/album/artist plays IN ORDER
## (shuffle off) and loops the whole context at the end, so the music never just stops mid-explore.
func play_playlist(uri: String) -> void:
	if not await _ready_to_control():
		return
	if not await _player_command(HTTPClient.METHOD_PUT, "/me/player/play", _play_body(uri)):
		return  # play failed (no device / error already surfaced) — don't pile on shuffle/repeat errors too
	# Mode (shuffle off / loop) is BEST-EFFORT (critical=false): playback already started, so a transient
	# failure on these must NOT surface an error or tear the radio down to the fallback — it just means the mode
	# didn't stick. A short beat first lets the device register the fresh playback (issuing the mode in the same
	# instant as play tends to transiently fail with a no-response).
	await get_tree().create_timer(0.4).timeout
	await _player_command(HTTPClient.METHOD_PUT, "/me/player/shuffle?state=false", "", false)
	await _player_command(HTTPClient.METHOD_PUT, "/me/player/repeat?state=" + _repeat_state_for(uri), "", false)

## Build the /me/player/play request body for `uri`. A single TRACK must go in "uris" (Spotify REJECTS a
## track as a context_uri, which silently fails playback); a playlist / album / artist plays as a
## "context_uri". So the designer's Radio.playlist_uri can be ANY of them. Pure + static -> unit-tested.
static func _play_body(uri: String) -> String:
	if uri.begins_with("spotify:track:"):
		return JSON.stringify({"uris": [uri]})
	return JSON.stringify({"context_uri": uri})

## The Spotify repeat mode for a URI: a single TRACK loops itself ("track"); a playlist / album / artist loops
## the whole context in order ("context"). Pure + static -> unit-tested.
static func _repeat_state_for(uri: String) -> String:
	return "track" if uri.begins_with("spotify:track:") else "context"

func pause() -> void:
	if not await _ready_to_control():
		return
	await _player_command(HTTPClient.METHOD_PUT, "/me/player/pause", "")

func resume() -> void:
	if not await _ready_to_control():
		return
	await _player_command(HTTPClient.METHOD_PUT, "/me/player/play", "")

## Stop external playback and drop ownership. Safe to call unconditionally (Radio._exit_tree / app-quit) —
## no-ops when nothing is linked/owned. The Radio gates its own _exit_tree call on owns(self).
func stop() -> void:
	var ok := true
	if is_linked() and is_premium() and not _access_token.is_empty():
		ok = await _player_command(HTTPClient.METHOD_PUT, "/me/player/pause", "")
	# Only drop ownership if the pause actually landed — clearing _owner after a FAILED pause would strand the
	# account playing with no radio able to retry. A still-owning radio re-issues pause on its next duck edge.
	if ok:
		_owner = 0
		_clear_now_playing()  # nothing's playing for us anymore -> blank the readout

## Common precondition for every playback command: opted-in + linked, a fresh token, and a re-checked Premium
## product (it can change mid-session, so we re-fetch /me rather than trust the cached value).
func _ready_to_control() -> bool:
	if not can_use_spotify():
		return false
	await ensure_token()
	if _access_token.is_empty():
		return false
	await _fetch_profile()
	if not is_premium():
		playback_error.emit("Spotify Premium is required to control playback.")
		return false
	return true

## Returns true when the command landed (so stop() only releases ownership on a real pause — a failed pause
## that cleared _owner would strand the account playing with no radio able to retry).
## `critical` (default true): on failure, emit playback_error — which the Radio treats as a FATAL Spotify drop
## (release + fall back to the local track + toast). The shuffle/repeat MODE commands pass false: playback has
## already started, so a transient mode-set failure must NOT alarm the player or tear the radio down; it just
## means the mode (shuffle off / loop) didn't stick this time.
func _player_command(method: int, path: String, body: String, critical: bool = true) -> bool:
	var headers := PackedStringArray(["Authorization: Bearer " + _access_token, "Content-Type: application/json"])
	var resp := await _http(method, API_BASE + path, headers, body)
	var code := int(resp["code"])
	if code == 404:
		if critical:
			playback_error.emit("No active Spotify device — open Spotify on a device, then try again.")
		return false
	if code == 0:
		if critical:
			playback_error.emit("Spotify network error (no response, result %d)." % int(resp.get("result", -1)))
		return false
	if code >= 400:
		if critical:
			playback_error.emit("Spotify playback error (HTTP %d)." % code)
		return false
	return true

# ---------------------------------------------------------------------------
# Profile + HTTP helper  [network — manual playtest]
# ---------------------------------------------------------------------------

func _fetch_profile() -> void:
	if _access_token.is_empty():
		return
	var headers := PackedStringArray(["Authorization: Bearer " + _access_token])
	var resp := await _http(HTTPClient.METHOD_GET, API_BASE + "/me", headers, "")
	if int(resp["code"]) == 200:
		var json: Dictionary = resp["json"]
		_product = str(json.get("product", ""))
		_display_name = str(json.get("display_name", Settings.spotify_user_name))
		_account_id = str(json.get("id", Settings.spotify_user_id))

## One-shot HTTP request via a throwaway HTTPRequest child. Returns { "code": int, "json": Dictionary }.
func _http(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var req := HTTPRequest.new()
	add_child(req)
	if req.request(url, headers, method, body) != OK:
		req.queue_free()
		return {"code": 0, "result": -1, "json": {}}  # request() binding failure (bad URL/state), not an HTTP status
	var res: Array = await req.request_completed  # [result, response_code, headers, body]
	req.queue_free()
	var raw: PackedByteArray = res[3]
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8()) if raw.size() > 0 else null
	var json_obj: Dictionary = {}
	if parsed is Dictionary:
		json_obj = parsed
	# result is the HTTPRequest.Result enum (2=cant_connect, 3=cant_resolve, 4=connection_error,
	# 5=tls_handshake, 6=no_response, 13=timeout) — surfaced so a code-0 transport failure says WHY.
	return {"code": int(res[1]), "result": int(res[0]), "json": json_obj}

# ---------------------------------------------------------------------------
# Now playing  [network — manual playtest; the parser is unit-tested]
# ---------------------------------------------------------------------------

## Polled from _process: while a radio owns playback, refresh the now-playing readout on the configured
## interval. Cheap when idle (early-out with no owner / no token).
func _poll_now_playing(delta: float) -> void:
	if _owner == 0 or _access_token.is_empty():
		return
	_np_poll_t -= delta
	if _np_poll_t > 0.0 or _np_in_flight:
		return
	_np_poll_t = GameSettings.radio.now_playing_poll_interval
	_fetch_now_playing()

func _fetch_now_playing() -> void:
	_np_in_flight = true
	var headers := PackedStringArray(["Authorization: Bearer " + _access_token])
	var resp := await _http(HTTPClient.METHOD_GET, API_BASE + "/me/player/currently-playing", headers, "")
	_np_in_flight = false
	if int(resp["code"]) != 200:
		return  # 204 (nothing playing) / errors: keep the last readout rather than flicker
	var np := _parse_now_playing(resp["json"])
	if np["title"] != _np_title or np["artist"] != _np_artist:
		_np_title = np["title"]
		_np_artist = np["artist"]
		now_playing_changed.emit(_np_title, _np_artist)

## Pull { title, artist } from a /me/player/currently-playing response (item.name + item.artists[0].name).
## Pure (no I/O), so it's unit-tested. Missing / odd shapes -> empty strings (never crashes).
func _parse_now_playing(json: Dictionary) -> Dictionary:
	var item: Variant = json.get("item", {})
	if not (item is Dictionary):
		return {"title": "", "artist": ""}
	var artist := ""
	var artists: Variant = (item as Dictionary).get("artists", [])
	if artists is Array and (artists as Array).size() > 0 and (artists as Array)[0] is Dictionary:
		artist = str(((artists as Array)[0] as Dictionary).get("name", ""))
	return {"title": str((item as Dictionary).get("name", "")), "artist": artist}

## Blank the readout (on stop / unlink) — emit empty so the NowPlayingHud hides.
func _clear_now_playing() -> void:
	if _np_title != "" or _np_artist != "":
		_np_title = ""
		_np_artist = ""
		now_playing_changed.emit("", "")

func _notification(what: int) -> void:
	# App quit: stop the user's external playback so we never leave their account playing after the game dies.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_owner = 0
