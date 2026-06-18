@tool
class_name VideoScreen
extends MeshInstance3D

## Drop-in: turns this mesh's surface into a live VIDEO SCREEN — a TV / security monitor that glows like a real
## display. Two clean, dependency-free sources: WEBCAM (the device camera, via CameraServer) or SNAPSHOT (poll a
## still-image URL a few times a second). Each frame is pushed onto a generated material as the EMISSION texture,
## so the picture self-lights in the dark and plays into bloom. Drop it on any MeshInstance3D — a QuadMesh for a
## flat screen, or a TV model's screen surface (set surface_index) — pick a source in the inspector, and run.
##
## ONLY point it at feeds you have the right to show: YOUR OWN webcam, a license-clean public live cam, or a
## stream you host yourself. Do NOT display private / unsecured camera feeds (e.g. random IP cams) in your game.
##
## SCOPE: WEBCAM needs no URL (zero networking). SNAPSHOT wants a still-image endpoint (often ".../snapshot.jpg")
## returning JPEG / PNG / WebP. True MJPEG / HLS / RTSP streams need an ffmpeg or GDExtension path — deliberately
## out of scope here so this stays a single drop-in file with no plugins. No live preview in-editor (it never
## opens a camera / the network at edit time); you'll see the video when you run the scene.

enum Source { WEBCAM, SNAPSHOT }

@export var source: Source = Source.WEBCAM
## SNAPSHOT only: the still-image URL to poll (e.g. a camera's ".../snapshot.jpg"). Ignored in WEBCAM mode.
@export var snapshot_url: String = ""
## SNAPSHOT only: frames to fetch per second. A background TV reads fine at 5–10; higher = smoother but more bandwidth.
@export_range(0.5, 30.0) var fps: float = 8.0
## WEBCAM only: which camera feed to use when the device exposes more than one (0 = the first).
@export var webcam_feed_index: int = 0
## Which surface of THIS mesh becomes the screen (0 = the only surface on a simple quad; pick the screen surface on a TV model).
@export var surface_index: int = 0
## How brightly the picture glows (emission energy): 1.0 = the video at face value; >1 blooms like a bright screen; 0 = the screen reads as OFF (black).
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


## Stop streaming and release the camera / requests. Leaves the last frame on the screen.
func stop() -> void:
	_playing = false
	set_process(false)
	if _feed != null:
		_feed.set_active(false)
		_feed = null
	if _http != null:
		_http.cancel_request()
	_requesting = false


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


func _set_screen_texture(t: Texture2D) -> void:
	_mat.emission_texture = t


# --- WEBCAM ----------------------------------------------------------------------------------------------------
func _start_webcam() -> void:
	if CameraServer.get_feed_count() <= webcam_feed_index:
		push_warning("VideoScreen: no camera feed %d (device exposes %d). Is a webcam connected / permitted on this platform?"
			% [webcam_feed_index, CameraServer.get_feed_count()])
		return
	_feed = CameraServer.get_feed(webcam_feed_index)
	_feed.set_active(true)
	var cam := CameraTexture.new()
	cam.camera_feed_id = _feed.get_id()
	cam.which_feed = CameraServer.FEED_RGBA_IMAGE  # if the picture looks green/garbled, the platform feeds YCbCr (needs a shader) — see notes
	_set_screen_texture(cam)


# --- SNAPSHOT (poll a still-image URL) -------------------------------------------------------------------------
func _start_snapshot() -> void:
	if snapshot_url == "":
		push_warning("VideoScreen: SNAPSHOT source needs a snapshot_url (a still-image endpoint, often '.../snapshot.jpg').")
		return
	_http = HTTPRequest.new()
	_http.timeout = 5.0
	add_child(_http)
	_http.request_completed.connect(_on_frame)
	_accum = 1.0  # fetch the first frame immediately
	set_process(true)


func _process(delta: float) -> void:
	# Snapshot polling only; webcam updates itself via CameraTexture.
	_accum += delta
	if _accum < 1.0 / maxf(fps, 0.1) or _requesting:
		return
	_accum = 0.0
	_requesting = true
	if _http.request(snapshot_url) != OK:
		_requesting = false


func _on_frame(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
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
	img.convert(Image.FORMAT_RGB8)  # a stable format so ImageTexture.update() never mismatches frame to frame
	if _tex == null or _tex.get_width() != img.get_width() or _tex.get_height() != img.get_height():
		_tex = ImageTexture.create_from_image(img)
		_set_screen_texture(_tex)
	else:
		_tex.update(img)


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		stop()


func _get_configuration_warnings() -> PackedStringArray:
	var w: PackedStringArray = []
	if mesh == null:
		w.append("VideoScreen needs a Mesh (e.g. a QuadMesh) — it draws the video onto this mesh's surface.")
	if source == Source.SNAPSHOT and snapshot_url == "":
		w.append("SNAPSHOT source needs a snapshot_url (a still-image endpoint, often '.../snapshot.jpg').")
	return w
