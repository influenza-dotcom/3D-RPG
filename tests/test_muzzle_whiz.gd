extends GutTest

## MuzzleWhiz (scripts/effects/muzzle_whiz.gd, no class_name) is the positional bullet whiz/crack under the rig
## muzzle (scenes/player/view_model.tscn Sketchfab_Scene/PlayerMuzzle/MuzzleWhiz), fired by Attack.flash_muzzle
## via _on_flash_muzzle. Its contract: prefer the equipped weapon's whiz_sound, else keep the stream assigned in
## the scene; pitch every shot randomly inside GameSettings.audio.muzzle_whiz_pitch_min..max so repeats never
## sound identical; then play. Pinned with an in-tree instance (play() wants the tree; the audio driver is a dummy
## headless) fed a bare Inventory + WeaponData, plus the scene wiring the smoke test does not cover (script path,
## blank in-scene inventory).

const SCRIPT_PATH := "res://scripts/effects/muzzle_whiz.gd"
const VIEW_MODEL_PATH := "res://scenes/player/view_model.tscn"


func _make_whiz() -> AudioStreamPlayer3D:
	var whiz: AudioStreamPlayer3D = load(SCRIPT_PATH).new()
	add_child_autofree(whiz)
	return whiz


func _make_inventory(weapon: WeaponData) -> Inventory:
	var inv := Inventory.new()
	inv.equipped_weapon = weapon
	add_child_autofree(inv)
	return inv


# --- surface --------------------------------------------------------------------------------------------------

func test_surface_and_defaults() -> void:
	var whiz := _make_whiz()
	assert_true(whiz is AudioStreamPlayer3D, "the whiz is a POSITIONAL player (it sits at the muzzle)")
	assert_true(whiz.has_method("_on_flash_muzzle"), "_on_flash_muzzle is the handler Attack.flash_muzzle connects to")
	assert_true("inventory" in whiz, "the inventory export exists (wired in code by Player._enter_tree)")
	assert_null(whiz.inventory, "inventory defaults null (leave blank in-scene)")


# --- stream selection -----------------------------------------------------------------------------------------

func test_no_inventory_keeps_the_scene_stream() -> void:
	var whiz := _make_whiz()
	var scene_stream := AudioStreamWAV.new()
	whiz.stream = scene_stream
	whiz._on_flash_muzzle()
	assert_eq(whiz.stream, scene_stream, "with no inventory wired the scene-assigned stream is what plays")


func test_no_equipped_weapon_keeps_the_scene_stream() -> void:
	var whiz := _make_whiz()
	var scene_stream := AudioStreamWAV.new()
	whiz.stream = scene_stream
	whiz.inventory = _make_inventory(null)
	whiz._on_flash_muzzle()
	assert_eq(whiz.stream, scene_stream, "an inventory with nothing equipped falls back to the scene stream")


func test_weapon_without_whiz_sound_keeps_the_scene_stream() -> void:
	var whiz := _make_whiz()
	var scene_stream := AudioStreamWAV.new()
	whiz.stream = scene_stream
	var weapon := WeaponData.new()
	weapon.whiz_sound = null
	whiz.inventory = _make_inventory(weapon)
	whiz._on_flash_muzzle()
	assert_eq(whiz.stream, scene_stream, "a weapon with no whiz_sound authored keeps the scene fallback")
	weapon = null


func test_weapon_whiz_sound_replaces_the_stream() -> void:
	var whiz := _make_whiz()
	var scene_stream := AudioStreamWAV.new()
	whiz.stream = scene_stream
	var custom := AudioStreamWAV.new()
	var weapon := WeaponData.new()
	weapon.whiz_sound = custom
	whiz.inventory = _make_inventory(weapon)
	whiz._on_flash_muzzle()
	assert_eq(whiz.stream, custom, "the equipped weapon's own whiz_sound wins over the scene stream")
	assert_ne(whiz.stream, scene_stream, "the scene fallback is replaced, not layered")
	weapon = null


func test_swapping_weapons_retargets_the_stream_per_shot() -> void:
	var whiz := _make_whiz()
	var a := AudioStreamWAV.new()
	var b := AudioStreamWAV.new()
	var wa := WeaponData.new()
	wa.whiz_sound = a
	var wb := WeaponData.new()
	wb.whiz_sound = b
	var inv := _make_inventory(wa)
	whiz.inventory = inv
	whiz._on_flash_muzzle()
	assert_eq(whiz.stream, a, "first shot: weapon A's whiz")
	inv.equip(wb)
	whiz._on_flash_muzzle()
	assert_eq(whiz.stream, b, "the stream is re-read on EVERY shot, so a swap takes effect on the next round")
	wa = null
	wb = null


# --- pitch --------------------------------------------------------------------------------------------------------

func test_pitch_lands_inside_the_audio_settings_range_on_every_shot() -> void:
	var whiz := _make_whiz()
	whiz.stream = AudioStreamWAV.new()
	var lo: float = GameSettings.audio.muzzle_whiz_pitch_min
	var hi: float = GameSettings.audio.muzzle_whiz_pitch_max
	assert_lt(lo, hi, "the authored range must be non-empty for the randomisation to mean anything")
	for i in 32:
		whiz._on_flash_muzzle()
		assert_gte(whiz.pitch_scale, lo, "shot %d: pitch never drops below muzzle_whiz_pitch_min" % i)
		assert_lte(whiz.pitch_scale, hi, "shot %d: pitch never exceeds muzzle_whiz_pitch_max" % i)


# --- scene wiring --------------------------------------------------------------------------------------------------

func test_view_model_scene_parents_the_whiz_under_the_rig_muzzle_with_a_blank_inventory() -> void:
	var packed: PackedScene = load(VIEW_MODEL_PATH)
	assert_not_null(packed, "view_model.tscn must load")
	if packed == null:
		return
	var vm := packed.instantiate()   # bare, never add_child: the rig's other children run real _ready work
	if vm == null:
		pending("view_model.tscn instantiated null (editor reimport transient) - rerun")
		return
	var whiz := vm.get_node_or_null("Sketchfab_Scene/PlayerMuzzle/MuzzleWhiz")
	assert_not_null(whiz, "MuzzleWhiz must sit under Sketchfab_Scene/PlayerMuzzle so it rides the muzzle snap (MuzzleRig.align_to) and GunMesh.setup finds it by name")
	if whiz != null:
		assert_true(whiz is AudioStreamPlayer3D, "the scene node is an AudioStreamPlayer3D")
		var script: Script = whiz.get_script()
		assert_not_null(script, "the scene node carries the whiz script")
		if script != null:
			assert_eq(script.resource_path, SCRIPT_PATH, "the scene node runs muzzle_whiz.gd")
		assert_null(whiz.get("inventory"), "inventory is left blank in-scene (Player._enter_tree wires it in code)")
		assert_not_null(whiz.get("stream"), "the scene assigns a fallback whiz stream for weapons without their own")
	vm.free()
