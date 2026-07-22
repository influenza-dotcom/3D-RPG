extends SceneTree

## TEMP runtime smoke test for the "draw your own t-shirt" feature — run headless, delete after. Exercises the REAL
## flow (Image/ImageTexture, ConfigFile I/O, the live autoloads) rather than a parse-check: ShirtCanvas paint + PNG
## fidelity, CharacterAppearanceCatalog.shirt_texture, configure_swap's shirt override, and the GameState save/load
## round-trip. Not GUT — a one-off `-s` harness. Prints PASS/FAIL per check and exits non-zero on any failure.

var _pass := 0
var _fail := 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("PASS: ", msg)
	else:
		_fail += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	# 1) ShirtCanvas: paint + PNG round-trip
	var canvas: Node = load("res://scripts/ui/shirt_canvas.gd").new()
	canvas.edit_res = 16
	canvas.apply_res = 64
	get_root().add_child(canvas)  # _ready allocates the buffers...
	if canvas._imgs.is_empty():
		canvas._rebuild_buffers()  # ...but -s _initialize runs before the ROOT is ready, so _ready hasn't fired yet
	_check(not canvas.is_dirty(), "canvas starts not-dirty (blank tee)")
	_check(canvas.applied_texture() != null, "applied texture exists")
	_check(canvas.applied_texture().get_width() == 64, "applied texture upscaled to apply_res")
	canvas.set_paint_color(Color(1, 0, 0))
	canvas.fill_all()
	_check(canvas.is_dirty(), "painting marks dirty")
	var bytes: PackedByteArray = canvas.png_bytes()
	_check(bytes.size() > 0, "png_bytes non-empty")
	var img := Image.new()
	_check(img.load_png_from_buffer(bytes) == OK, "png decodes")
	_check(img.get_pixel(3, 3).is_equal_approx(Color(1, 0, 0)), "painted red round-trips through PNG")
	canvas.reset()
	_check(not canvas.is_dirty(), "reset clears dirty")

	# 2) CharacterAppearanceCatalog.shirt_texture resolver
	var Cat: GDScript = load("res://scripts/player/character_appearance_catalog.gd")
	_check(Cat.shirt_texture({}) == null, "no shirt key -> null")
	var decoded = Cat.shirt_texture({"shirt": bytes})
	_check(decoded != null and decoded is Texture2D, "bytes decode to a Texture2D")
	var img2 := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img2.fill(Color.GREEN)
	var live := ImageTexture.create_from_image(img2)
	_check(Cat.shirt_texture({"shirt": live}) == live, "live texture passes straight through")
	_check(Cat.shirt_texture({"shirt": PackedByteArray()}) == null, "empty bytes -> null")

	# 3) configure_swap shirt override (off-tree swap: setters store, no .glb instanced)
	var cat = Cat.default()
	var swap = load("res://scripts/components/body_model_swap.gd").new()
	cat.configure_swap(swap, {"body": "standard", "skin": Color(0.7, 0.5, 0.3), "shirt": live})
	_check(swap.body_texture == live, "custom shirt becomes body_texture")
	_check(swap.body_color == Color.WHITE, "custom shirt -> body_color WHITE (untinted art)")
	_check(swap.head_color == Color(0.7, 0.5, 0.3), "head still takes the skin tint")
	var swap2 = load("res://scripts/components/body_model_swap.gd").new()
	cat.configure_swap(swap2, {"body": "standard", "skin": Color(0.7, 0.5, 0.3)})
	_check(swap2.body_color == Color(0.7, 0.5, 0.3), "no shirt -> skin still tints body")
	swap.free()
	swap2.free()

	# 4) GameState save/load round-trip of the shirt bytes
	var gs = get_root().get_node_or_null("GameState")
	if gs == null:
		_check(false, "GameState autoload present")
	else:
		var save_path := "user://__verify_shirt.cfg"
		gs.appearance = {"body": "standard", "shirt": bytes}
		_check(gs.save_to_disk(save_path) == OK, "profile with a drawn shirt saves")
		gs.appearance = {}
		_check(gs.load_from_disk(save_path), "profile loads back")
		var got = gs.appearance.get("shirt")
		_check(got is PackedByteArray, "shirt loads back as PackedByteArray")
		_check((got as PackedByteArray) == bytes, "shirt bytes round-trip byte-for-byte")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	canvas.queue_free()
	print("=== SHIRT VERIFY: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
