extends GutTest

## Combat data + simple components — GUT unit suite.
##
## COVERS (all by-construction; no Godot to run them, so every assert targets a
## verified field/method/signal signature read straight from source):
##   - WeaponData SOURCE defaults via WeaponData.new() (NOT a .tres): the exact
##     numeric/float/int default VALUES (effective_range, damage, multipliers,
##     projectile, explosion, pellet, knockback, shake, hitstop, launch fields)
##     and the bool defaults (spawns_casing, has_muzzle_flash, has_laser_sight,
##     auto_fire, single_air_dash, launch_on_scoped_attack, use_hitscan,
##     is_spray_paint). These are the design defaults a freshly-authored weapon
##     inherits — distinct from test_smoke.gd (which only checks the TYPES of
##     these flags on existing .tres) and test_weapon_data_completeness.gd
##     (which only checks field presence/type on .tres, never source defaults).
##   - WeaponData.is_spray_paint + paint_colors: the graffiti-mode opt-in flag
##     (default false) and the 6-colour cycle array. Uncovered anywhere else.
##   - spray_paint.tres wiring: it opts into is_spray_paint, drops the laser
##     sight, carries max_ammo 0, and (not overriding paint_colors) keeps a
##     non-empty colour cycle. A new .tres no existing test references.
##   - InteractableData defaults via InteractableData.new(): max_hp, mass,
##     destroy_screen_shake, spawns_destroy_decal. Zero prior coverage (the
##     smoke test only text-greps Interactable.gd).
##   - Inventory: equipped_weapon default (null) and the post-equip STATE that
##     equip() leaves behind (the single source of truth is updated).
##   - Ammo.consume_ammo() pure clip math: success decrements, empty returns
##     false without going negative, and the exact-empty boundary; plus the
##     ammo_cost / current_ammo defaults.
##   - Reload.reload_weapon() emits the `reload` signal.
##
## DELIBERATELY SKIPS (and why):
##   - Inventory.equip() emitting weapon_changed on change / staying silent on a
##     re-equip — ALREADY covered by test_smoke.gd::test_inventory_equip_* (we
##     only add the resulting equipped_weapon STATE + the null default here).
##   - WeaponData behaviour-toggle TYPES on .tres and melee identity — already in
##     test_smoke.gd; .tres field presence/type — in test_weapon_data_completeness.gd.
##   - Ammo._ready / _on_weapon_changed / set_to_max_ammo / reload — _ready
##     null-derefs its (unset) inventory, so the node can never be add_child'd
##     bare; the swap/bank/restore + INT_MIN "infinite clip" logic is integration
##     territory needing a wired Inventory, left to a dedicated Ammo test.
##   - Reload._unhandled_input — engine-driven input routing, not pure logic; the
##     payload it forwards is covered by calling reload_weapon() directly.
##   - Object-typed exports (projectile_scene, meshes, materials, AudioStreams) —
##     null by default with no side-effect-free invariant worth asserting.
##
## Conventions match test_smoke.gd: `extends GutTest`, `func test_*() -> void`,
## class_name globals (WeaponData/InteractableData/Inventory/Ammo/Reload) used
## directly. Resources & the no-_ready Inventory/Ammo/Reload are instantiated with
## .new() and torn down with .free() WITHOUT add_child, so no _ready/_unhandled_input
## ever fires against a bare tree. add_child_autofree is used only for the one
## Inventory case that mirrors the existing, proven-safe smoke-test setup.

const PISTOL = preload("res://resources/weapons/pistol.tres")
const SHOTGUN = preload("res://resources/weapons/shotgun.tres")
const SPRAY_PAINT = preload("res://resources/weapons/spray_paint.tres")


# ---------------------------------------------------------------------------
# WeaponData — source numeric/int/float defaults (WeaponData.new(), NOT a .tres).
# Asserting the exact default VALUES documents what a freshly-authored weapon
# inherits before any .tres override. (Resource: no _init/_ready/autoload, so
# .new()/.free() is fully safe and needs no add_child.)
# ---------------------------------------------------------------------------

func test_weapon_data_default_ranges_and_damage() -> void:
	var w := WeaponData.new()
	assert_eq(typeof(w.effective_range), TYPE_FLOAT,
		"effective_range must be a float — attack.gd lerps/compares it as a distance")
	assert_eq(w.effective_range, 20.0,
		"Default effective_range is 20.0m; a new weapon should reach mid-range out of the box")
	assert_eq(typeof(w.damage), TYPE_FLOAT,
		"damage is declared 'float = 1.0', so WeaponData.new().damage is a FLOAT (NOT int, despite int-looking .tres literals)")
	assert_eq(w.damage, 1.0,
		"Default damage is 1.0 — the unit baseline each .tres scales from")
	assert_eq(w.headshot_multiplier, 2.0,
		"Default headshot_multiplier is 2.0 (a clean headshot doubles damage)")
	assert_eq(w.sneak_attack_multiplier, 2.0,
		"Default sneak_attack_multiplier is 2.0; stacked with headshot a stealth headshot is 4x")
	w = null


# A weapon imposes no movement penalty out of the box: move_speed_multiplier is
# the wielder's speed factor WHILE THIS WEAPON IS DRAWN; only a heavier .tres
# lowers it below 1.0 (FNV-style), so the source default must be exactly 1.0.
func test_weapon_data_move_speed_multiplier_defaults_to_one() -> void:
	var w := WeaponData.new()
	assert_eq(typeof(w.move_speed_multiplier), TYPE_FLOAT,
		"move_speed_multiplier must be a float — it scales the wielder's move speed while the weapon is drawn")
	assert_eq(w.move_speed_multiplier, 1.0,
		"Default move_speed_multiplier is 1.0 — a fresh weapon slows the holder not at all; only a heavier .tres sets it lower")
	w = null


func test_weapon_data_default_projectile_fields() -> void:
	var w := WeaponData.new()
	assert_eq(typeof(w.projectile_life_time), TYPE_FLOAT,
		"projectile_life_time is a float (seconds before a stray projectile self-frees)")
	assert_eq(w.projectile_life_time, 10.0,
		"Default projectile_life_time is 10.0s so missed shots don't linger forever")
	assert_eq(typeof(w.projectile_speed), TYPE_FLOAT,
		"projectile_speed is a float (m/s launch speed)")
	assert_eq(w.projectile_speed, 80.0,
		"Default projectile_speed is 80.0 m/s — the baseline bullet velocity")
	assert_eq(typeof(w.bullet_gravity_scale), TYPE_FLOAT,
		"bullet_gravity_scale is a float (per-projectile gravity multiplier)")
	assert_eq(w.bullet_gravity_scale, 0.1,
		"Default bullet_gravity_scale is 0.1 — a slight drop, not full gravity")
	assert_eq(typeof(w.launch_angle), TYPE_FLOAT,
		"launch_angle is a float (upward firing tilt in radians)")
	assert_eq(w.launch_angle, 0.0,
		"Default launch_angle is 0.0 — ordinary guns fire straight, no lob")
	w = null


func test_weapon_data_default_ammo_is_int_ten() -> void:
	var w := WeaponData.new()
	assert_eq(typeof(w.max_ammo), TYPE_INT,
		"max_ammo must be an int — Ammo tracks whole rounds and compares clip counts as ints")
	assert_eq(w.max_ammo, 10,
		"Default max_ammo is 10 — a sane starting clip size for a new weapon")
	w = null


func test_weapon_data_default_explosion_fields() -> void:
	var w := WeaponData.new()
	assert_eq(typeof(w.max_explosion_force), TYPE_FLOAT,
		"max_explosion_force is a float (impulse applied to bodies at ground zero)")
	assert_eq(w.max_explosion_force, 20.0,
		"Default max_explosion_force is 20.0 — the baseline blast shove")
	assert_eq(typeof(w.explosion_radius), TYPE_FLOAT,
		"explosion_radius is a float (metres of blast falloff)")
	assert_eq(w.explosion_radius, 4.0,
		"Default explosion_radius is 4.0m so a default weapon's blast has reach")
	w = null


func test_weapon_data_default_pellet_fields() -> void:
	var w := WeaponData.new()
	assert_eq(typeof(w.pellet_count), TYPE_INT,
		"pellet_count must be an int — you can't fire a fractional pellet")
	assert_eq(w.pellet_count, 1,
		"Default pellet_count is 1 — a single bullet per shot unless a shotgun overrides it")
	assert_eq(typeof(w.pellet_spread), TYPE_FLOAT,
		"pellet_spread is a float (cone half-angle for multi-pellet fire)")
	assert_eq(w.pellet_spread, 0.1,
		"Default pellet_spread is 0.1 — a tight default cone")
	w = null


func test_weapon_data_default_timing_fields() -> void:
	var w := WeaponData.new()
	assert_eq(typeof(w.reload_time), TYPE_FLOAT,
		"reload_time is a float (seconds the Reload Timer waits)")
	assert_eq(w.reload_time, 1.5,
		"Default reload_time is 1.5s — the baseline reload duration")
	assert_eq(typeof(w.attack_speed), TYPE_FLOAT,
		"attack_speed is a float (seconds between shots / the fire cooldown)")
	assert_eq(w.attack_speed, 0.1,
		"Default attack_speed is 0.1s — a brisk default fire rate")
	assert_eq(typeof(w.attack_windup), TYPE_FLOAT,
		"attack_windup is a float (delay between click and the hit landing)")
	assert_eq(w.attack_windup, 0.0,
		"Default attack_windup is 0.0 — ranged weapons hit instantly; only melee winds up")
	w = null


func test_weapon_data_default_knockback_fields() -> void:
	var w := WeaponData.new()
	assert_eq(typeof(w.self_knockback), TYPE_FLOAT,
		"self_knockback is a float (recoil shove applied back to the shooter)")
	assert_eq(w.self_knockback, 0.0,
		"Default self_knockback is 0.0 — firing doesn't push the player by default")
	assert_eq(typeof(w.enemy_knockback), TYPE_FLOAT,
		"enemy_knockback is a float (horizontal shove applied to a hit enemy)")
	assert_eq(w.enemy_knockback, 5.0,
		"Default enemy_knockback is 5.0 — hits visibly shove enemies by default")
	assert_eq(typeof(w.enemy_lift), TYPE_FLOAT,
		"enemy_lift is a float (upward pop applied to a hit enemy)")
	assert_eq(w.enemy_lift, 0.0,
		"Default enemy_lift is 0.0 — only launcher-style weapons pop enemies up")
	w = null


func test_weapon_data_default_shake_fields() -> void:
	var w := WeaponData.new()
	assert_eq(typeof(w.screen_shake_amount), TYPE_FLOAT,
		"screen_shake_amount is a float (per-shot camera trauma)")
	assert_eq(w.screen_shake_amount, 0.3,
		"Default screen_shake_amount is 0.3 — a moderate per-shot kick")
	assert_eq(typeof(w.launch_screen_shake), TYPE_FLOAT,
		"launch_screen_shake is a float (the bigger one-shot shake for a scoped-attack launch)")
	assert_eq(w.launch_screen_shake, 0.6,
		"Default launch_screen_shake is 0.6 — a dash/launch kicks harder than a normal shot")
	w = null


func test_weapon_data_default_hitstop_fields() -> void:
	var w := WeaponData.new()
	assert_eq(typeof(w.hitstop_duration), TYPE_FLOAT,
		"hitstop_duration is a float (real-time freeze hold on an enemy hit)")
	assert_eq(w.hitstop_duration, 0.005,
		"Default hitstop_duration is 0.005s — a tiny per-hit freeze for punch without stutter")
	assert_eq(typeof(w.hitstop_recovery), TYPE_FLOAT,
		"hitstop_recovery is a float (seconds to ease back to full speed after the freeze)")
	assert_eq(w.hitstop_recovery, 0.2,
		"Default hitstop_recovery is 0.2s — the freeze eases out, it doesn't snap back")
	w = null


func test_weapon_data_default_scope_fields() -> void:
	var w := WeaponData.new()
	assert_eq(typeof(w.scoped_fov_override), TYPE_FLOAT,
		"scoped_fov_override is a float — ScopeIn assigns it to camera.fov as the ADS zoom target")
	assert_eq(w.scoped_fov_override, 0.0,
		"Default scoped_fov_override is 0.0, the sentinel meaning fall back to the global GameSettings.camera.scoped_fov (only > 0.0 picks a per-weapon scope FOV)")
	assert_eq(typeof(w.disable_dof_while_scoped), TYPE_BOOL,
		"disable_dof_while_scoped must be a bool — CameraEffects.set_scope_dof branches on it to turn far-blur off")
	assert_false(w.disable_dof_while_scoped,
		"disable_dof_while_scoped defaults false — scoping merely lessens DoF; only a scope weapon (e.g. the sniper) turns it off")
	w = null


func test_weapon_data_default_launch_fields() -> void:
	var w := WeaponData.new()
	assert_eq(typeof(w.launch_force), TYPE_FLOAT,
		"launch_force is a float (forward impulse of a scoped-attack dash)")
	assert_eq(w.launch_force, 15.0,
		"Default launch_force is 15.0 — the baseline dash power for launch-on-scope weapons")
	assert_eq(typeof(w.launch_upward), TYPE_FLOAT,
		"launch_upward is a float (vertical component of the dash launch)")
	assert_eq(w.launch_upward, 4.0,
		"Default launch_upward is 4.0 — a dash also lifts you, not just shoves forward")
	w = null


# ---------------------------------------------------------------------------
# WeaponData — source boolean defaults (WeaponData.new()). test_smoke.gd only
# asserts these are bool-TYPED on .tres instances; here we pin the source DEFAULT
# VALUE a fresh weapon inherits.
# ---------------------------------------------------------------------------

func test_weapon_data_default_bool_flags() -> void:
	var w := WeaponData.new()
	assert_true(w.spawns_casing,
		"spawns_casing defaults true — a stock weapon ejects shell casings unless told not to")
	assert_true(w.has_muzzle_flash,
		"has_muzzle_flash defaults true — a stock weapon shows a flash on fire")
	assert_true(w.has_laser_sight,
		"has_laser_sight defaults true — a stock weapon shows its laser sight")
	assert_true(w.auto_fire,
		"auto_fire defaults true — hold-to-fire is the default; semi-auto weapons opt out")
	assert_false(w.auto_reload,
		"auto_reload defaults false — only weapons that opt in reload themselves when a shot runs the clip dry")
	assert_false(w.single_air_dash,
		"single_air_dash defaults false — only dash weapons cap to one launch per airtime")
	assert_false(w.launch_on_scoped_attack,
		"launch_on_scoped_attack defaults false — scoped fire is a normal attack unless opted in")
	assert_false(w.use_hitscan,
		"use_hitscan defaults false — weapons spawn projectiles unless explicitly hitscan")
	w = null


# ---------------------------------------------------------------------------
# WeaponData.is_spray_paint + paint_colors — the graffiti-mode opt-in, uncovered
# elsewhere. A plain weapon must NOT be spray-paint or normal guns stop damaging.
# ---------------------------------------------------------------------------

func test_weapon_data_is_spray_paint_defaults_false() -> void:
	var w := WeaponData.new()
	assert_eq(typeof(w.is_spray_paint), TYPE_BOOL,
		"is_spray_paint must be a bool — attack.gd branches on it to deal damage vs. spray paint")
	assert_false(w.is_spray_paint,
		"is_spray_paint defaults false so an ordinary weapon deals damage, not graffiti")
	w = null


func test_weapon_data_paint_colors_default_six_colours() -> void:
	var w := WeaponData.new()
	assert_eq(typeof(w.paint_colors), TYPE_ARRAY,
		"paint_colors must be an Array — the spray cycles through it one entry per splat")
	assert_eq(w.paint_colors.size(), 6,
		"The source default ships 6 tag colours so spray paint varies splat-to-splat out of the box")
	assert_true(w.paint_colors[0] is Color,
		"paint_colors entries must be Color values for the decal tint to apply")
	w = null


# ---------------------------------------------------------------------------
# spray_paint.tres — load-bearing resource wiring (a new .tres no other test
# touches). It must actually opt into graffiti mode and keep a usable colour cycle.
# ---------------------------------------------------------------------------

func test_spray_paint_tres_is_graffiti_weapon() -> void:
	assert_true(SPRAY_PAINT is WeaponData,
		"spray_paint.tres must load as a WeaponData so the gun rig can equip it")
	assert_true(SPRAY_PAINT.is_spray_paint,
		"spray_paint.tres must set is_spray_paint=true or it would deal damage instead of painting")
	assert_false(SPRAY_PAINT.has_laser_sight,
		"A spray can has no laser sight — spray_paint.tres turns has_laser_sight off")
	assert_eq(SPRAY_PAINT.max_ammo, 0,
		"spray_paint.tres uses max_ammo=0 (the spray isn't a round-counted clip weapon)")
	assert_true(SPRAY_PAINT.paint_colors.size() >= 1,
		"spray_paint.tres doesn't override paint_colors, so it inherits the defaults — needs >=1 colour to cycle")


# ---------------------------------------------------------------------------
# InteractableData — source defaults (Resource, no _init/_ready/autoload). Zero
# prior coverage; the smoke test only text-greps Interactable.gd.
# ---------------------------------------------------------------------------

func test_interactable_data_numeric_defaults() -> void:
	var d := InteractableData.new()
	assert_eq(typeof(d.max_hp), TYPE_INT,
		"max_hp must be an int — Interactable subtracts whole damage points from it")
	assert_eq(d.max_hp, 5,
		"Default max_hp is 5 — a stock prop takes a few hits before breaking")
	assert_eq(typeof(d.mass), TYPE_FLOAT,
		"mass must be a float — it feeds the RigidBody physics that toss the prop")
	assert_eq(d.mass, 1.0,
		"Default mass is 1.0 — the neutral physics weight for a generic prop")
	assert_eq(typeof(d.destroy_screen_shake), TYPE_FLOAT,
		"destroy_screen_shake must be a float — it injects camera trauma when the prop breaks")
	assert_eq(d.destroy_screen_shake, 0.35,
		"Default destroy_screen_shake is 0.35 — breaking a prop gives a noticeable kick")
	d = null


func test_interactable_data_spawns_destroy_decal_defaults_true() -> void:
	var d := InteractableData.new()
	assert_eq(typeof(d.spawns_destroy_decal), TYPE_BOOL,
		"spawns_destroy_decal must be a bool — Interactable branches on it when destroyed")
	assert_true(d.spawns_destroy_decal,
		"Defaults true so solid props leave a scorch/blast decal; gibs override it to false")
	d = null


# is_gib gates the confetti-+-party-horn burst that ONLY gore gibs get when the
# player shoots one out of the air. A fresh prop (the template a crate/barrel
# inherits) must default false so ordinary props can never qualify for confetti —
# only a gore-gib .tres flips it true.
func test_interactable_data_is_gib_defaults_false() -> void:
	var d := InteractableData.new()
	assert_eq(typeof(d.is_gib), TYPE_BOOL,
		"is_gib must be a bool — Interactable branches on it to pick confetti vs. the usual gore puff")
	assert_false(d.is_gib,
		"is_gib defaults false so crates/barrels never burst into confetti; only a gore-gib .tres opts in")
	d = null


# ---------------------------------------------------------------------------
# Inventory — equipped_weapon default + the post-equip STATE. The signal emit /
# no-op behaviour is already covered by test_smoke.gd, so we only assert the
# resulting source-of-truth value here (not the signal).
# ---------------------------------------------------------------------------

func test_inventory_equipped_weapon_defaults_null() -> void:
	# Inventory extends Node but defines no _ready/_init, so .new()/.free() is safe
	# without entering the tree.
	# NOTE: assert_null is NOT used in the existing suite (test_smoke.gd only uses
	# assert_not_null), so per the project's GUT conventions we express the null
	# check via the confirmed assert_true helper instead.
	var inv := Inventory.new()
	assert_true(inv.equipped_weapon == null,
		"A fresh Inventory holds no weapon until equip() runs — the rig must not assume one exists")
	inv.free()


func test_inventory_equip_updates_equipped_weapon_state() -> void:
	# add_child_autofree is safe here (no _ready), mirroring the proven smoke-test setup.
	var inv := Inventory.new()
	add_child_autofree(inv)
	inv.equipped_weapon = PISTOL
	inv.equip(SHOTGUN)
	assert_eq(inv.equipped_weapon, SHOTGUN,
		"Equipping a different weapon must update equipped_weapon — it's the single source of truth every listener reads")


# ---------------------------------------------------------------------------
# Ammo — pure clip math via Ammo.new() WITHOUT add_child. Ammo._ready connects to
# (and reads) its unset `inventory`, which would null-deref and crash the runner,
# so we never add it to the tree; consume_ammo() touches no node refs.
# ---------------------------------------------------------------------------

func test_ammo_consume_success_decrements() -> void:
	var a := Ammo.new()
	a.current_ammo = 5
	a.ammo_cost = 1
	assert_true(a.consume_ammo(),
		"A clip with rounds must report success so attack.gd is allowed to fire")
	assert_eq(a.current_ammo, 4,
		"A successful consume must burn exactly one round (ammo_cost) from the clip")
	a.free()


func test_ammo_consume_empty_returns_false_and_holds() -> void:
	var a := Ammo.new()
	a.current_ammo = 0
	a.ammo_cost = 1
	assert_false(a.consume_ammo(),
		"An empty clip must return false so attack.gd plays the dry-fire click instead of firing")
	assert_eq(a.current_ammo, 0,
		"A failed consume must not mutate the clip — current_ammo must never go negative (the >=0 guard)")
	a.free()


func test_ammo_consume_exact_empty_boundary() -> void:
	var a := Ammo.new()
	a.current_ammo = 1
	a.ammo_cost = 1
	assert_true(a.consume_ammo(),
		"The last round in the clip must still fire (1 - 1 >= 0)")
	assert_eq(a.current_ammo, 0,
		"Firing the last round must leave the clip at exactly 0")
	assert_false(a.consume_ammo(),
		"The shot that empties the clip succeeds; the very next shot on an empty clip must fail")
	a.free()


func test_ammo_default_cost_and_starting_clip() -> void:
	var a := Ammo.new()
	assert_eq(a.ammo_cost, 1,
		"ammo_cost defaults to 1 — one round burned per trigger pull unless a weapon raises it")
	assert_eq(a.current_ammo, 0,
		"current_ammo starts at 0 — the clip is empty until set_to_max_ammo() fills it on equip")
	a.free()


func test_ammo_background_reload_tracks_and_clears_per_weapon() -> void:
	var a := Ammo.new()
	var w := WeaponData.new()
	assert_false(a.is_background_reloading(w),
		"a weapon isn't background-reloading until one is started")
	a.start_background_reload(w, 2.0)
	assert_true(a.is_background_reloading(w),
		"start_background_reload registers the outgoing weapon as topping up in the background")
	a.cancel_background_reload(w)
	assert_false(a.is_background_reloading(w),
		"cancel_background_reload drops it (e.g. when the player foreground-reloads that gun)")
	a.free()


# ---------------------------------------------------------------------------
# Reload — the input adapter's pure payload. Reload extends Node3D with an
# _unhandled_input that the ENGINE only calls on real input, so calling
# reload_weapon() directly (without add_child) exercises the logic safely.
# ---------------------------------------------------------------------------

func test_reload_weapon_emits_reload_signal() -> void:
	var r := Reload.new()
	watch_signals(r)
	r.reload_weapon()
	assert_signal_emitted(r, "reload",
		"reload_weapon() must emit `reload` so attack.gd can decide whether a reload is allowed")
	r.free()
