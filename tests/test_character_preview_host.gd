extends GutTest

## The character-preview HOST (scripts/ui/character_preview_host.gd) — the duck-typed stand-in BodyModelSwap
## parents under on the creation screen's turntable. The swap poses its limbs off its PARENT through
## HostMethodHelper.try_call_bool (is_holding_gun / is_on_floor / has_sensed_foe / is_fists_out / is_climbing)
## and duck-typed reads (`velocity`, `hp`), so the contract pinned here is exactly that surface, read exactly the
## way the swap reads it: a grounded, motionless, alive actor whose ONLY variable is `holding`, which
## character_preview.gd flips with host.set(&"holding", show_gun) when a weapon is mounted.
##
## A bare Node3D — .new() + free(); nothing here touches a transform or the tree. No BodyModelSwap is built
## (its _ready is the model pipeline); this is the host's half of the seam, tested on its own.

const PATH := "res://scripts/ui/character_preview_host.gd"


func _host() -> Node3D:
	return load(PATH).new()


func test_has_no_class_name() -> void:
	# A private preview helper, path-preloaded by character_preview.gd — deliberately off the global class cache.
	var script: Script = load(PATH)
	assert_eq(script.get_global_name(), StringName(""), "character_preview_host.gd must not register a class_name")

func test_defaults_are_a_standing_unarmed_actor() -> void:
	var h := _host()
	assert_false(h.holding, "nothing mounted at rest")
	assert_eq(h.velocity, Vector3.ZERO, "a preview actor never moves — no walk-swing")
	assert_true(h.is_on_floor(), "always grounded — no airborne flail")
	assert_false(h.is_holding_gun(), "arms rest by the side until a weapon is mounted")
	h.free()

func test_is_holding_gun_tracks_the_holding_flag() -> void:
	var h := _host()
	h.holding = true
	assert_true(h.is_holding_gun(), "holding=true raises the arms into the two-handed hold")
	h.holding = false
	assert_false(h.is_holding_gun(), "and drops them again when the weapon is unmounted")
	h.free()

func test_the_preview_sets_holding_duck_typed_through_object_set() -> void:
	# character_preview._mount_weapon does `host.set(&"holding", show_gun)` on an Object-typed handle.
	var h := _host()
	(h as Object).set(&"holding", true)
	assert_true(h.is_holding_gun(), "a duck-typed set(&\"holding\") reaches the flag")
	(h as Object).set(&"holding", false)
	assert_false(h.is_holding_gun(), "and clears it")
	h.free()

func test_reads_through_host_method_helper_match_what_the_swap_expects() -> void:
	# The swap's own accessor, defaults included: is_on_floor defaults TRUE (no method -> not airborne) and
	# is_holding_gun defaults FALSE; the host must answer both explicitly, and leave the rest to the defaults.
	var h := _host()
	assert_false(HostMethodHelper.try_call_bool(h, &"is_holding_gun"), "unarmed at rest through the helper")
	h.holding = true
	assert_true(HostMethodHelper.try_call_bool(h, &"is_holding_gun"), "armed through the helper")
	assert_true(HostMethodHelper.try_call_bool(h, &"is_on_floor", true), "grounded through the helper")
	assert_false(HostMethodHelper.try_call_bool(h, &"has_sensed_foe", false), "no foe method -> the helper's default (arms not raised)")
	assert_false(HostMethodHelper.try_call_bool(h, &"is_fists_out"), "no fists method -> default false")
	assert_false(HostMethodHelper.try_call_bool(h, &"is_climbing"), "no climbing method -> default false")
	h.free()

func test_absent_reads_are_absent_on_purpose() -> void:
	# `hp` must read NULL (BodyModelSwap treats null hp as ALIVE so the idle breathing runs); the fields the swap
	# never needs on a preview actor must not exist, so a future addition is a deliberate choice, not drift.
	var h := _host()
	assert_null(h.get(&"hp"), "no hp -> reads as alive")
	for absent in [&"has_sensed_foe", &"is_fists_out", &"is_climbing", &"aim_distance"]:
		assert_false(h.has_method(absent), "'%s' is deliberately absent — HostMethodHelper falls back to a safe default" % absent)
	assert_false(h.get(&"aim_distance") != null, "no aim_distance property")
	h.free()

func test_velocity_reads_as_a_vector3_the_gait_can_measure() -> void:
	# _animate_limbs does `host.get(&"velocity")` and takes its length — it must be a Vector3, and zero.
	var h := _host()
	var v: Variant = h.get(&"velocity")
	assert_true(v is Vector3, "velocity is a Vector3 (the swap measures its length)")
	assert_true((v as Vector3).is_zero_approx(), "and zero, so the walk cycle never starts")
	h.free()

func test_is_a_node3d_so_the_turntable_can_spin_it() -> void:
	# The host IS the turntable root (the swap and the weapon hand anchor hang off it and rotate together).
	var h := _host()
	assert_true(h is Node3D, "the host must be a Node3D — character_preview rotates it and parents the swap under it")
	h.free()
