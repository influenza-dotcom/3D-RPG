extends GutTest
## The CACHE-MIGRATION contract for a weapon-bench REFIT (Ammo.rekey_weapon / ScopeIn.rekey_weapon /
## Weapon.migrate_weapon_state). GUT unit suite.
##
## WHY THIS FILE EXISTS: a refit does not edit a WeaponData in place, it swaps `Item.weapon` for a freshly
## folded NEW resource. Every runtime cache keyed by the RESOURCE INSTANCE therefore sees a stranger. The
## expensive one is Ammo: `_on_weapon_changed` falls through to `set_to_max_ammo()` for an unknown weapon,
## so an unmigrated refit hands the player a FREE FULL MAGAZINE — a repeatable infinite-reload exploit you
## can farm by fitting and pulling the same part. Every assertion below is that exploit's fence.
##
## Ammo / ScopeIn / Weapon are all built off-tree via `.new()` WITHOUT add_child, per CLAUDE.md: Ammo._ready
## null-derefs an unset `inventory` and ScopeIn._process polls the global Input, so neither may enter the
## tree bare (the same convention as test_ammo_reserve.gd / test_combat_data.gd). The private caches
## (`_ammo_per_weapon`, `_bg_reloads`, `_wheel_zoom_fov`) are hand-set: they are the whole subject of the
## contract, and reaching them through a real swap would need the full weapon.tscn rig in the tree.


## A bare WeaponData with just the magazine size that matters to Ammo.
func _gun(max_ammo: int) -> WeaponData:
	var w := WeaponData.new()
	w.max_ammo = max_ammo
	return w


## A WeaponData that authors a usable wheel-zoom range, so has_variable_scope_zoom() is true and
## ScopeIn._clamp_wheel_zoom has real ends to clamp into (both > 0, max > min — see WeaponData).
func _scoped(min_fov: float, max_fov: float) -> WeaponData:
	var w := WeaponData.new()
	w.scoped_zoom_fov_min = min_fov
	w.scoped_zoom_fov_max = max_fov
	return w


func test_rekey_moves_the_bank_and_erases_the_old_key() -> void:
	var ammo := Ammo.new()
	var old := _gun(10)
	var fresh := _gun(10)
	ammo.current_weapon = null  # neither block is the drawn gun: the holstered/banked path
	ammo._ammo_per_weapon[old] = 4
	ammo.rekey_weapon(old, fresh)
	assert_false(ammo._ammo_per_weapon.has(old),
		"the OLD WeaponData key is erased — one leaked key per fit would live for the rig's lifetime")
	assert_true(ammo._ammo_per_weapon.has(fresh),
		"the refitted block is banked under its own identity")
	assert_eq(int(ammo._ammo_per_weapon[fresh]), 4,
		"the banked clip rides across unchanged (4 rounds in, 4 rounds out)")

	# A weapon the rig has never banked (never drawn since the level loaded) seeds the NEW magazine size,
	# which is exactly the first-sight fill _on_weapon_changed would have done for it anyway.
	var unseen := _gun(10)
	var unseen_fresh := _gun(8)
	ammo.rekey_weapon(unseen, unseen_fresh)
	assert_eq(int(ammo._ammo_per_weapon[unseen_fresh]), 8,
		"an unbanked weapon seeds the new max_ammo — no worse than the fill it would have got on first draw")
	ammo.free()
	old = null
	fresh = null
	unseen = null
	unseen_fresh = null


func test_rekey_clamps_down_never_up() -> void:
	# ⭐THE EXPLOIT FENCE. Fitting an extended magazine must not chamber the extra rounds for free.
	var ammo := Ammo.new()
	var old := _gun(20)
	var bigger := _gun(30)
	ammo.current_weapon = old
	ammo.current_ammo = 6
	ammo.rekey_weapon(old, bigger)
	assert_eq(int(ammo._ammo_per_weapon[bigger]), 6,
		"a BIGGER magazine arrives with the rounds you already had — fitting one is never a free reload")
	ammo.free()

	# The other direction is a real clamp: a magazine part that shrinks the clip cannot leave more rounds
	# chambered than the new block can physically hold (Ammo.consume_ammo would happily spend them).
	var ammo2 := Ammo.new()
	var wide := _gun(20)
	var narrow := _gun(12)
	ammo2.current_weapon = wide
	ammo2.current_ammo = 18
	ammo2.rekey_weapon(wide, narrow)
	assert_eq(int(ammo2._ammo_per_weapon[narrow]), 12,
		"a SMALLER magazine spills the overflow — the bank clamps to the new max_ammo")
	ammo2.free()
	old = null
	bigger = null
	wide = null
	narrow = null


func test_rekey_nulls_current_weapon_for_the_live_gun_so_weapon_changed_reads_the_seed() -> void:
	var ammo := Ammo.new()
	var old := _gun(10)
	var fresh := _gun(10)
	ammo.current_weapon = old
	ammo.current_ammo = 3
	ammo.rekey_weapon(old, fresh)
	assert_null(ammo.current_weapon,
		"the live gun's pointer is dropped: the imminent weapon_changed must not re-bank a dead object")

	# The equip that follows a refit fires weapon_changed. With current_weapon nulled, _on_weapon_changed
	# skips its re-bank (which would stomp the seed we just wrote with the OLD block's count under the NEW
	# key) and finds the pre-seeded entry, so no set_to_max_ammo() fallback ever runs.
	ammo._on_weapon_changed(fresh)
	assert_eq(ammo.current_ammo, 3,
		"the refitted gun comes back with the clip it had — NOT a free full magazine")
	assert_eq(ammo.current_weapon, fresh,
		"and the live pointer lands on the refitted block")
	ammo.free()
	old = null
	fresh = null


func test_rekey_migrates_a_HOLSTERED_weapon() -> void:
	# ⭐The canonical orphan is HOLSTERED, which is why migration is unconditional rather than gated on
	# "is it drawn": Attack starts a BACKGROUND reload (attack.gd:643) precisely when you swap AWAY from a
	# reloading gun, so the weapon most likely to be carrying live state is the one not in your hands.
	var ammo := Ammo.new()
	var drawn := _gun(10)
	var holstered := _gun(10)
	var fresh := _gun(10)
	ammo.current_weapon = drawn
	ammo.current_ammo = 9
	ammo._ammo_per_weapon[holstered] = 2
	ammo._bg_reloads[holstered] = 1.25
	ammo.rekey_weapon(holstered, fresh)
	assert_eq(int(ammo._ammo_per_weapon[fresh]), 2,
		"a holstered weapon's banked clip migrates even though it is not the live gun")
	assert_true(ammo._bg_reloads.has(fresh),
		"and so does its in-flight background reload")
	assert_eq(ammo.current_weapon, drawn,
		"the gun actually in hand is untouched by someone else's refit")
	assert_eq(ammo.current_ammo, 9,
		"and so is its live round count")
	ammo.free()
	drawn = null
	holstered = null
	fresh = null


func test_rekey_moves_an_in_flight_background_reload() -> void:
	var ammo := Ammo.new()
	var old := _gun(10)
	var fresh := _gun(10)
	ammo.current_weapon = null
	ammo._ammo_per_weapon[old] = 0
	ammo._bg_reloads[old] = 2.5
	ammo.rekey_weapon(old, fresh)
	assert_false(ammo._bg_reloads.has(old),
		"the old key goes: _process walks _bg_reloads, and a stale entry would refill a weapon nobody holds")
	assert_almost_eq(float(ammo._bg_reloads[fresh]), 2.5, 0.0001,
		"the REMAINING seconds ride across untouched — a refit is not a reason to restart the reload")
	assert_true(ammo.is_background_reloading(fresh),
		"and the public query agrees the refitted block is still reloading")
	ammo.free()
	old = null
	fresh = null


## ⭐REGRESSION — the SECOND-STAGE sweep, and why it cannot just be another rekey_weapon.
## Attack converts an in-progress FOREGROUND reload into a background one for the OUTGOING weapon
## (attack.gd:643) from INSIDE the equip chain — i.e. after the refit has already pre-seeded and retired the
## old block. So refitting mid-reload landed a live background reload on a key nothing would ever read again,
## and its completion silently spent a spare clip out of the backpack into that dead key.
## The two asserts that matter are the pair: the reload MOVES, and the clip is NOT re-banked.
func test_rekey_background_reload_moves_the_reload_without_touching_the_clip() -> void:
	var ammo := Ammo.new()
	var old := _gun(10)
	var fresh := _gun(10)
	# The state as it stands one instruction after WeaponBench._refit's equip_item returns: the pre-seed already
	# happened and erased `old`, the equip landed so current_weapon is the NEW block, and Attack has just
	# registered the handed-over reload against the block we retired.
	ammo._ammo_per_weapon[fresh] = 3
	ammo.current_weapon = fresh
	ammo._bg_reloads[old] = 2.5
	ammo.rekey_background_reload(old, fresh)
	assert_false(ammo._bg_reloads.has(old), "the orphaned key goes — nothing will ever read it again")
	assert_almost_eq(float(ammo._bg_reloads[fresh]), 2.5, 0.0001,
		"and the remaining seconds land on the gun the player is actually holding")
	assert_eq(ammo._ammo_per_weapon[fresh], 3,
		"⭐THE WHOLE POINT: the clip is UNTOUCHED. A second rekey_weapon here would miss the erased `old` key, "
		+ "fall back to new.max_ammo and mint a full magazine — the exploit the first call exists to prevent")
	ammo.free()
	old = null
	fresh = null


## The sweep is a no-op on every path that did not hand a reload over — which is most of them, including
## Attack's mid-swap queue branch (it returns before it can start one).
func test_rekey_background_reload_is_a_noop_with_nothing_in_flight() -> void:
	var ammo := Ammo.new()
	var old := _gun(10)
	var fresh := _gun(10)
	ammo._ammo_per_weapon[fresh] = 7
	ammo.rekey_background_reload(old, fresh)
	assert_true(ammo._bg_reloads.is_empty(), "no reload to move, so none is invented")
	assert_eq(ammo._ammo_per_weapon[fresh], 7, "and the clip is still untouched")
	ammo.rekey_background_reload(null, fresh)
	ammo.rekey_background_reload(old, null)
	ammo.rekey_background_reload(fresh, fresh)
	assert_true(ammo._bg_reloads.is_empty(), "null and same-object calls are inert, like every other rekey")
	ammo.free()
	old = null
	fresh = null


func test_scope_rekey_carries_and_reclamps_the_dial() -> void:
	var scope := ScopeIn.new()
	var old := _scoped(5.0, 40.0)
	var narrowed := _scoped(5.0, 20.0)
	scope._wheel_zoom_fov[old] = 35.0
	scope.rekey_weapon(old, narrowed)
	assert_false(scope._wheel_zoom_fov.has(old),
		"the dial leaves the old block behind")
	assert_almost_eq(float(scope._wheel_zoom_fov[narrowed]), 20.0, 0.001,
		"a sight part that NARROWS the zoom range pulls an out-of-range dial in to the new maximum")
	# current_wheel_zoom_fov returns a stored dial VERBATIM (only step_wheel_zoom re-clamps), which is
	# exactly why the re-clamp has to happen here — otherwise scope-in would ease to an illegal FOV.
	assert_almost_eq(scope.current_wheel_zoom_fov(narrowed), 20.0, 0.001,
		"and the value the scope actually reads back is the clamped one")

	# An in-range dial is carried across untouched: the player chose a real optic setting.
	var wide := _scoped(5.0, 40.0)
	var same_range := _scoped(5.0, 40.0)
	scope._wheel_zoom_fov[wide] = 15.0
	scope.rekey_weapon(wide, same_range)
	assert_almost_eq(float(scope._wheel_zoom_fov[same_range]), 15.0, 0.001,
		"a dial already inside the new range survives the refit verbatim")
	scope.free()
	old = null
	narrowed = null
	wide = null
	same_range = null


func test_scope_rekey_drops_the_dial_when_the_new_block_has_no_variable_zoom() -> void:
	var scope := ScopeIn.new()
	var old := _scoped(5.0, 40.0)
	var plain := WeaponData.new()  # scoped_zoom_fov_min/max left at 0 -> has_variable_scope_zoom() is false
	scope._wheel_zoom_fov[old] = 22.0
	scope.rekey_weapon(old, plain)
	assert_false(scope._wheel_zoom_fov.has(old),
		"the old key is erased regardless of what the new block can do")
	assert_false(scope._wheel_zoom_fov.has(plain),
		"pulling the scope off drops the dial — scoped_target_fov never consults it for a fixed optic")
	assert_eq(scope._wheel_zoom_fov.size(), 0,
		"and nothing else is left in the cache")

	# A weapon that was never dialed has nothing to carry, so the rekey is a strict no-op (the guard also
	# stops a blank entry being invented for a gun the player never touched the wheel on).
	var undialed := _scoped(5.0, 40.0)
	var refit := _scoped(5.0, 40.0)
	scope.rekey_weapon(undialed, refit)
	assert_eq(scope._wheel_zoom_fov.size(), 0,
		"an undialed weapon seeds no entry — current_wheel_zoom_fov still computes the resting zoom LIVE")
	scope.free()
	old = null
	plain = null
	undialed = null
	refit = null


func test_weapon_migrate_weapon_state_fans_out_to_both_and_is_a_noop_for_the_same_object() -> void:
	# The fan-out is the point: the bench calls exactly ONE method, so a future WeaponData-keyed cache is
	# one line here rather than a line at every refit site (and a caller cannot do three of the four steps).
	var ws := Weapon.new()
	var ammo := Ammo.new()
	var scope := ScopeIn.new()
	ws.ammo = ammo
	ws.scope_in = scope
	var old := _scoped(5.0, 40.0)
	old.max_ammo = 12
	var fresh := _scoped(5.0, 40.0)
	fresh.max_ammo = 12
	ammo.current_weapon = old
	ammo.current_ammo = 7
	scope._wheel_zoom_fov[old] = 18.0

	ws.migrate_weapon_state(old, fresh)
	assert_eq(int(ammo._ammo_per_weapon[fresh]), 7,
		"one call hands the clip over")
	assert_null(ammo.current_weapon,
		"one call also drops the live pointer, so the equip that follows reads the seed")
	assert_almost_eq(float(scope._wheel_zoom_fov[fresh]), 18.0, 0.001,
		"the SAME call hands the scope dial over — the two halves can never be done separately")

	# Same object in both slots: nothing to migrate, and re-running must not invent a bank entry (the
	# bench's remove path can legitimately produce an identical-looking block).
	ammo._ammo_per_weapon.clear()
	scope._wheel_zoom_fov.clear()
	ws.migrate_weapon_state(fresh, fresh)
	assert_eq(ammo._ammo_per_weapon.size(), 0,
		"migrating a weapon onto itself banks nothing")
	assert_eq(scope._wheel_zoom_fov.size(), 0,
		"and dials nothing")

	# An unwired rig (an AI wielder with no ScopeIn, or a bare test rig) must not crash — both children are
	# null-guarded, and GUT fails the run on any engine error, so simply reaching the next line is the pin.
	var bare := Weapon.new()
	bare.migrate_weapon_state(old, fresh)
	pass_test("migrate_weapon_state tolerates a rig with no ammo / scope_in child")
	bare.free()

	ws.free()
	ammo.free()
	scope.free()
	old = null
	fresh = null
