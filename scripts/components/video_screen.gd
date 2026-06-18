@tool
class_name VideoScreen
extends MeshInstance3D

## Drop-in: turns this mesh's surface into a live VIDEO SCREEN — a TV / security monitor that glows like a real
## display. Three dependency-free sources: WEBCAM (the device camera, via CameraServer), SNAPSHOT (poll a
## still-image URL a few times a second), or MJPEG (a continuous multipart/x-mixed-replace stream, read on a
## background thread). Each frame is pushed onto a generated material as the EMISSION texture, so the picture
## self-lights in the dark and feeds bloom. Drop it on any MeshInstance3D — a QuadMesh for a flat screen, or a TV
## model's screen surface (set surface_index) — pick a source in the inspector, and run.
##
## ONLY point it at feeds you have the right to show: YOUR OWN webcam / camera, a license-clean public live cam,
## or a stream you host. Do NOT display private / unsecured camera feeds you don't own.
##
## SECURITY NOTE: a camera reachable at a bare public IP with no password is visible to the ENTIRE internet (that
## is how feed-scrapers find them). If that camera is yours, consider putting it behind auth / a VPN / a LAN-only
## address — the game can still read it the same way.
##
## For HLS / RTSP / RTMP / video files you'd need an ffmpeg or GDExtension path — out of scope here so this stays a
## single drop-in file. No live preview in-editor (it never opens a camera / the network at edit time); you'll see
## the video when you run the scene.

enum Source { WEBCAM, SNAPSHOT, MJPEG }

@export var source: Source = Source.WEBCAM
## SNAPSHOT / MJPEG only: the feed URL. SNAPSHOT wants a still-image endpoint (often ".../snapshot.jpg") returning
## one JPEG/PNG/WebP per request; MJPEG wants a stream (often ".../video.mjpg", Content-Type
## multipart/x-mixed-replace). Ignored in WEBCAM mode.
@export var url: String = ""
## SNAPSHOT only: frames to fetch per second (MJPEG plays at the stream's own rate). A background TV reads fine at 5–10.
@export_range(0.5, 30.0) var fps: float = 8.0
## WEBCAM only: which camera feed to use when the device exposes more than one (0 = the first).
@export var webcam_feed_index: int = 0
## Which surface of THIS mesh becomes the screen (0 = the only surface on a simple quad; pick the screen surface on a TV model).
@export var surface_index: int = 0
## How brightly the picture glows (emission energy): 1.0 = the video at face value; >1 blooms; 0 = the screen reads as OFF (black).
@export_range(0.0, 8.0) var brightness: float = 1.3
## Flip the picture vertically — toggle if the feed shows upside-down on your screen mesh's UVs.
@export var flip_v: bool = false:
	set(v):
		flip_v = v
		if not Engine.is_editor_hint() and _built:
			_apply_uv()
## Start streaming automatically when the scene runs. Off → call play() yourself (e.g. when the player flips the TV on).
@export var autoplay: bool = true

var _mat := StandardMaterial3D.new()
var _tex: ImageTexture = null
var _http: HTTPRequest = null
var _feed: CameraFeed = null
var _requesting := false
var _accum := 0.0
var _playing := false
var _built := false

# MJPEG background-reader state (the thread decodes JPEGs into _latest; the main thread turns _latest into texture).
var _thread: Thread = null
var _mutex := Mutex.new()
var _latest: Image = null
var _running := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_material()
	set_process(false)
	if autoplay:
		play()


## Begin streaming (idempotent). Pair with stop() to drive a TV power switch.
func play() -> void:
	if _playing:
		return
	_playing = true
	match source:
		Source.WEBCAM:
			_start_webcam()
		Source.SNAPSHOT:
			_start_snapshot()
		Source.MJPEG:
			_start_mjpeg()


## Stop streaming and release the camera / requests / reader thread. Leaves the last frame on the screen.
func stop() -> void:
	_playing = false
	set_process(false)
	_running = false
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()  # the pump checks _running frequently, so this returns promptly
		_thread = null
	if _feed != null:
		_feed.set_active(false)
		_feed = null
	if _http != null:
		_http.cancel_request()
	_requesting = false


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _playing:
		return
	match source:
		Source.SNAPSHOT:
			_tick_snapshot(delta)
		Source.MJPEG:
			_tick_mjpeg()


# --- material -------------------------------------------------------------------------------------------------
func _build_material() -> void:
	# The picture is pure EMISSION (a self-lit screen), so room lighting never dims it and it feeds bloom.
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mat.albedo_color = Color.BLACK
	_mat.emission_enabled = true
	_mat.emission = Color.WHITE
	_mat.emission_energy_multiplier = brightness
	_apply_uv()
	set_surface_override_material(surface_index, _mat)
	_built = true


func _apply_uv() -> void:
	# Flip V in place: UV.y' = 1 - UV.y (scale -1, offset +1), so the picture stays framed, just inverted.
	_mat.uv1_scale = Vector3(1.0, -1.0 if flip_v else 1.0, 1.0)
	_mat.uv1_offset = Vector3(0.0, 1.0 if flip_v else 0.0, 0.0)


# Push a decoded frame onto the screen (main thread only — ImageTexture talks to the renderer).
func _show_image(img: Image) -> void:
	if _tex == null or _tex.get_width() != img.get_width() or _tex.get_height() != img.get_height():
		_tex = ImageTexture.create_from_image(img)
		_mat.emission_texture = _tex
	else:
		_tex.update(img)


# --- WEBCAM ---------------------------------------------------------------------------------------------------
func _start_webcam() -> void:
	if CameraServer.get_feed_count() <= webcam_feed_index:
		push_warning("VideoScreen: no camera feed %d (device exposes %d). Is a webcam connected / permitted on this platform?"
			% [webcam_feed_index, CameraServer.get_feed_count()])
		return
	_feed = CameraServer.get_feed(webcam_feed_index)
	_feed.set_active(true)
	var cam := CameraTexture.new()
	cam.camera_feed_id = _feed.get_id()
	cam.which_feed = CameraServer.FEED_RGBA_IMAGE  # if the picture looks green/garbled, the platform feeds YCbCr (needs a shader)
	_mat.emission_texture = cam


# --- SNAPSHOT (poll a still-image URL) ------------------------------------------------------------------------
func _start_snapshot() -> void:
	if url == "":
		push_warning("VideoScreen: SNAPSHOT source needs a url (a still-image endpoint, often '.../snapshot.jpg').")
		return
	_http = HTTPRequest.new()
	_http.timeout = 5.0
	add_child(_http)
	_http.request_completed.connect(_on_snapshot)
	_accum = 1.0  # fetch the first frame immediately
	set_process(true)


func _tick_snapshot(delta: float) -> void:
	_accum += delta
	if _accum < 1.0 / maxf(fps, 0.1) or _requesting:
		return
	_accum = 0.0
	_requesting = true
	if _http.request(url) != OK:
		_requesting = false


func _on_snapshot(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_requesting = false
	if code != 200 or body.is_empty():
		return  # keep the last good frame on a hiccup
	var img := Image.new()
	var ok := img.load_jpg_from_buffer(body)
	if ok != OK:
		ok = img.load_png_from_buffer(body)
	if ok != OK:
		ok = img.load_webp_from_buffer(body)
	if ok != OK:
		return
	img.convert(Image.FORMAT_RGB8)
	_show_image(img)


# --- MJPEG (multipart stream, read on a background thread) ----------------------------------------------------
func _start_mjpeg() -> void:
	if url == "":
		push_warning("VideoScreen: MJPEG source needs a url (a stream endpoint, often '.../video.mjpg').")
		return
	_running = true
	_thread = Thread.new()
	_thread.start(_mjpeg_pump)
	set_process(true)


func _tick_mjpeg() -> void:
	var img: Image = null
	_mutex.lock()
	if _latest != null:
		img = _latest
		_latest = null
	_mutex.unlock()
	if img != null:
		_show_image(img)


# Background thread: connect, GET, read the multipart body forever, carve out each JPEG frame (FF D8 ... FF D9),
# decode it to an Image, and hand the latest to the main thread. Reconnects with a short backoff on drop / error.
func _mjpeg_pump() -> void:
	var u := _parse_url(url)
	while _running:
		var client := HTTPClient.new()
		var tls = TLSOptions.client() if u["tls"] else null
		if client.connect_to_host(u["host"], u["port"], tls) != OK:
			_backoff()
			continue
		while _running and client.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
			client.poll()
			OS.delay_msec(5)
		if client.get_status() != HTTPClient.STATUS_CONNECTED:
			client.close()
			_backoff()
			continue
		var headers := PackedStringArray(["User-Agent: Godot-VideoScreen", "Accept: */*", "Connection: keep-alive"])
		if client.request(HTTPClient.METHOD_GET, u["path"], headers) != OK:
			client.close()
			_backoff()
			continue
		while _running and client.get_status() == HTTPClient.STATUS_REQUESTING:
			client.poll()
			OS.delay_msec(5)
		if not client.has_response():
			client.close()
			_backoff()
			continue
		var buf := PackedByteArray()
		while _running and client.get_status() == HTTPClient.STATUS_BODY:
			client.poll()
			var chunk := client.read_response_body_chunk()
			if chunk.size() > 0:
				buf.append_array(chunk)
				buf = _carve_frames(buf)
			else:
				OS.delay_msec(2)  # nothing arrived yet — yield instead of busy-spinning
		client.close()
		if _running:
			_backoff()  # the stream dropped; reconnect


# Pull every complete JPEG out of `buf`, decode + publish each, and return the unconsumed tail.
func _carve_frames(buf: PackedByteArray) -> PackedByteArray:
	var soi := _find2(buf, 0xFF, 0xD8, 0)  # JPEG start-of-image
	while soi >= 0:
		var eoi := _find2(buf, 0xFF, 0xD9, soi + 2)  # JPEG end-of-image (never appears in stuffed scan data)
		if eoi < 0:
			return buf.slice(soi)  # frame still arriving; keep from the start marker on
		var img := Image.new()
		if img.load_jpg_from_buffer(buf.slice(soi, eoi + 2)) == OK:
			img.convert(Image.FORMAT_RGB8)
			_mutex.lock()
			_latest = img
			_mutex.unlock()
		buf = buf.slice(eoi + 2)
		soi = _find2(buf, 0xFF, 0xD8, 0)
	# no frame start left — drop accumulated garbage so a bad stream can't grow the buffer without bound
	return PackedByteArray() if buf.size() > 4_000_000 else buf


func _find2(buf: PackedByteArray, b0: int, b1: int, from: int) -> int:
	var n := buf.size() - 1
	var i := from
	while i < n:
		if buf[i] == b0 and buf[i + 1] == b1:
			return i
		i += 1
	return -1


func _parse_url(u: String) -> Dictionary:
	var tls := u.begins_with("https://")
	var rest := u.trim_prefix("https://").trim_prefix("http://")
	var slash := rest.find("/")
	var host_port := rest if slash < 0 else rest.substr(0, slash)
	var path := "/" if slash < 0 else rest.substr(slash)
	var host := host_port
	var port := 443 if tls else 80
	var colon := host_port.find(":")
	if colon >= 0:
		host = host_port.substr(0, colon)
		port = int(host_port.substr(colon + 1))
	return {"host": host, "port": port, "path": path, "tls": tls}


func _backoff() -> void:
	var t := 0
	while _running and t < 1000:
		OS.delay_msec(50)
		t += 50


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		stop()


func _get_configuration_warnings() -> PackedStringArray:
	var w: PackedStringArray = []
	if mesh == null:
		w.append("VideoScreen needs a Mesh (e.g. a QuadMesh) — it draws the video onto this mesh's surface.")
	if source != Source.WEBCAM and url == "":
		w.append("This source needs a url (SNAPSHOT: a still-image endpoint; MJPEG: a '.../video.mjpg' stream).")
	return w
