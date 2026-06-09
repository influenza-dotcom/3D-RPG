extends GutTest

## is_infinite_ammo (Wave 0) — the explicit "clip never depletes" flag that replaces the fragile INT_MIN
## two's-complement overflow sentinel melee/fists used to carry as max_ammo. Pure off-tree checks: the flag
## default, the authored .tres, and Ammo.consume_ammo() behaviour (Ammo.new() with no _ready — consume_ammo
## touches only current_weapon + current_ammo).


func test_weapon_data_is_infinite_ammo_defaults_false() -> void:
	var w := WeaponData.new()
	assert_false(w.is_infinite_ammo, "real guns deplete by default — is_infinite_ammo is opt-in (melee/fists)")
	w = null


func test_melee_and_fists_use_the_flag_not_int_min() -> void:
	var melee: WeaponData = load("res://resources/weapons/melee.tres")
	assert_true(melee.is_infinite_ammo, "melee carries the explicit is_infinite_ammo flag")
	assert_gt(melee.max_ammo, 0, "melee.max_ammo is a sane positive — no more the INT_MIN overflow sentinel")
	var fists: WeaponData = load("res://resources/weapons/fists.tres")
	assert_true(fists.is_infinite_ammo, "fists carry is_infinite_ammo")
	assert_gt(fists.max_ammo, 0, "fists.max_ammo is sane")


func test_infinite_ammo_clip_never_depletes() -> void:
	var a := Ammo.new()
	var inf := WeaponData.new()
	inf.is_infinite_ammo = true
	inf.max_ammo = 1
	a.current_weapon = inf
	a.current_ammo = 1
	assert_true(a.consume_ammo(), "an infinite-ammo weapon always has a shot")
	assert_true(a.consume_ammo(), "...and keeps firing")
	assert_eq(a.current_ammo, 1, "infinite-ammo consume does NOT decrement the clip (no overflow needed)")
	a.free()
	inf = null


func test_finite_ammo_clip_decrements_and_dries() -> void:
	var a := Ammo.new()
	var w := WeaponData.new()
	w.max_ammo = 1
	a.current_weapon = w
	a.current_ammo = 1
	assert_true(a.consume_ammo(), "a finite weapon fires while it has a round")
	assert_eq(a.current_ammo, 0, "a finite weapon decrements the clip")
	assert_false(a.consume_ammo(), "an empty finite weapon dry-fires (consume returns false)")
	a.free()
	w = null
