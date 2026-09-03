extends GutTest

## Combat data + simple components — GUT unit suite.
##
## COVERS (all by-construction; no Godot to run them, so every assert targets a
## verified field/method/signal signature read straight from source):
##   - WeaponData SOURCE defaults via WeaponData.new() (NOT a .tres): the exact
##     numeric/float/int default VALUES (effective_range, damage, multipliers,
##     projectile, explosion, pellet, knockback, shake, hitstop) and the bool
##     defaults (spawns_casing, has_muzzle_flash, has_laser_sight, auto_fire,
##     use_hitscan, is_spray_paint). These are the design defaults a freshly-authored weapon
##     inherits — distinct from test_smoke.gd (which only checks the TYPES of
##     these flags on existing .tres) and test_weapon_data_completeness.gd
##     (which only checks field presence/type on .tres, never source defaults).
##   - WeaponData.is_spray_paint + paint_colors: the graffiti-mode opt-in flag
##     (default false) and the 6-colour cycle array. Uncovered anywhere else.
##   - spray_paint.tres wiring: it opts into is_spray_paint, drops the laser
##     sight, carries max_ammo 0, and (not overriding paint_colors) keeps a
##     non-empty colour cycle. A new .tres no existing test references.
##   - ThrowableData defaults via ThrowableData.new(): max_hp, mass,
##     destroy_screen_shake, spawns_destroy_decal. Zero prior coverage (the
##     smoke test only text-greps Throwable.gd).
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
## class_name globals (WeaponData/ThrowableData/Inventory/Ammo/Reload) used
## directly. Resources & the no-_ready Inventory/Ammo/Reload are instantiated with
## .new() and torn down with .free() WITHOUT add_child, so no _ready/_unhandled_input
## ever fires against a bare tree. add_child_autofree is used only for the one
## Inventory case that mirrors the existing, proven-safe smoke-test setup.

const PISTOL = preload("res://resources/weapons/pistol.tres")
const SHOTGUN = preload("res://resources/weapons/shotgun.tres")
const SPRAY_PAINT = preload("res://resources/weapons/spray_paint.tres")
## Folder swept by the shipped-weapon stamina guards below (the test_calibers.gd idiom): a derived price is only
## as safe as the WORST .tres on disk, so the guards validate every one instead of the three preloaded here.
const WEAPONS_DIR := "res://resources/weapons/"
const ModelResource = preload("res://scripts/components/model_resource.gd")

func _property(obj: Object, prop_name: String) -> Dictionary:
	for p in obj.get_property_list():
		if p.get("name", "") == prop_name:
			return p
	return {}


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


func test_weapon_data_stamina_cost_mult_defaults_to_one() -> void:
	var w := WeaponData.new()
	assert_eq(typeof(w.stamina_cost_mult), TYPE_FLOAT,
		"stamina_cost_mult must be a float — it scales the global per-shot stamina cost for this weapon")
	assert_eq(w.stamina_cost_mult, 1.0,
		"Default stamina_cost_mult is 1.0 — a fresh gun costs exactly the global stamina_shot_cost per shot; a fast-cadence .tres authors it DOWN and a heavy one UP")
	w = null


# ---------------------------------------------------------------------------
# Shipped-weapon guards for the DERIVED per-shot stamina price. The price is
# stamina_shot_cost x WeaponData.stamina_effort() x stamina_cost_mult, clamped
# to stamina_shot_drain_ceiling x stamina_sprint_drain x attack_speed. Because
# power and cadence are authored on separate knobs, a rebalance can quietly
# invert the design or rail a weapon against its clamp with nothing else going
# red, so the whole folder is swept (the test_calibers.gd idiom).
#
# SCOPE NOTE: the drain figures in the first two guards are the RAW held-trigger
# rate. They do NOT model the regen a weapon earns back between its own shots -
# that is stamina_regen_delay_after_shot's job and it is the subject of
# test_no_shipped_weapon_regenerates_between_its_own_shots below, which is where
# the real inter-shot interval (cooldown OR reload) is worked out.
# ---------------------------------------------------------------------------

## The shipped price of one shot from `w`, mirroring Attack._shot_stamina_cost() exactly.
func _shot_cost_for(w: WeaponData) -> float:
	var mv: PlayerMovementSettings = GameSettings.player_movement
	var raw := mv.stamina_shot_cost * w.stamina_effort() * w.stamina_cost_mult
	return maxf(minf(raw, _shot_cost_ceiling_for(w)), 0.0)


## The cadence clamp for `w` - the most a single shot may ever cost, whatever its power.
func _shot_cost_ceiling_for(w: WeaponData) -> float:
	var mv: PlayerMovementSettings = GameSettings.player_movement
	return mv.stamina_shot_drain_ceiling * mv.stamina_sprint_drain * maxf(w.attack_speed, 0.05)


## Every shipped weapon that actually pays the ranged shot cost (melee pays stamina_melee_attack_cost; a spray
## blob returns before the spend), as {path: WeaponData}.
func _priced_ranged_weapons() -> Dictionary:
	var out := {}
	var dir := DirAccess.open(WEAPONS_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		var w := load(WEAPONS_DIR.path_join(f)) as WeaponData
		if w == null or w.is_melee or w.is_spray_paint:
			continue
		out[f] = w
	return out


func test_shipped_weapons_sustained_fire_stamina_stays_under_the_sprint_drain() -> void:
	var weapons := _priced_ranged_weapons()
	assert_gt(weapons.size(), 0, "expected at least one ranged weapon to validate")
	var sprint_drain: float = GameSettings.player_movement.stamina_sprint_drain
	for f in weapons:
		var w: WeaponData = weapons[f]
		assert_gte(w.stamina_cost_mult, 0.0,
			"weapon '%s' has a NEGATIVE stamina_cost_mult - firing must never pay stamina back" % f)
		var per_second := _shot_cost_for(w) / maxf(w.attack_speed, 0.05)
		assert_lt(per_second, sprint_drain,
			"weapon '%s' drains %.1f stamina/sec on a held trigger, at or above the %.1f/sec sprint drain - lower its damage or its stamina_cost_mult, or shooting costs more than running" % [f, per_second, sprint_drain])


func test_no_shipped_weapon_is_railed_against_its_cadence_clamp() -> void:
	# The clamp's failure mode is SILENT CHEAPENING, not an inversion: once a weapon's derived price exceeds
	# stamina_shot_drain_ceiling x sprint_drain x attack_speed, the clamp discards the derived value, so making
	# the weapon MORE powerful (or faster) stops raising its cost and every other test here stays green. Nothing
	# shipped may sit on that rail, so the day someone raises the launcher's damage the suite says so.
	var weapons := _priced_ranged_weapons()
	assert_gt(weapons.size(), 0, "expected at least one ranged weapon to validate")
	var mv: PlayerMovementSettings = GameSettings.player_movement
	for f in weapons:
		var w: WeaponData = weapons[f]
		var raw := mv.stamina_shot_cost * w.stamina_effort() * w.stamina_cost_mult
		var ceiling := _shot_cost_ceiling_for(w)
		assert_lt(raw, ceiling,
			"weapon '%s' wants %.2f stamina/shot but is clamped to %.2f - its price has stopped tracking its power, so raise stamina_shot_drain_ceiling or slow the weapon down" % [f, raw, ceiling])


func test_the_grenade_launcher_is_the_most_expensive_shot_in_the_game() -> void:
	# The design the per-shot cost exists to express: a powerful weapon costs more to fire than a weak one.
	# rock_weapon.tres IS the grenade launcher (view_model grenade_launcher.tscn, caliber &"grenades") - the
	# filename is legacy. Its lead comes from stamina_effort(): 4.0 direct damage plus a 4.0 blast payload, so
	# twice the shotgun's 4.0 and eight times the pistol's 1.0.
	var weapons := _priced_ranged_weapons()
	assert_true(weapons.has("rock_weapon.tres"),
		"rock_weapon.tres (the grenade launcher) must be on the roster for this guard to mean anything")
	var launcher: float = _shot_cost_for(weapons["rock_weapon.tres"])
	var runner_up := 0.0
	var runner_up_name := ""
	for f in weapons:
		if f == "rock_weapon.tres":
			continue
		var c := _shot_cost_for(weapons[f])
		if c > runner_up:
			runner_up = c
			runner_up_name = f
	assert_gt(launcher, runner_up,
		"the grenade launcher (%.2f/shot) must cost more than every other weapon - '%s' is at %.2f" % [launcher, runner_up_name, runner_up])
	# A margin, not just a win: assert_gt alone passes on a 0.001 lead, which would not read as "powerful" in play.
	assert_gte(launcher / maxf(runner_up, 0.001), 1.5,
		"the grenade launcher only leads '%s' by %.2fx (%.2f vs %.2f) - a retune has narrowed it to where the two feel identically priced" % [runner_up_name, launcher / maxf(runner_up, 0.001), launcher, runner_up])


## The regen hold a shot from `w` arms, mirroring Attack._shot_regen_hold(). `emptied` selects the shot that
## used the last round in the magazine, which cannot be followed until the weapon reloads.
func _shot_regen_hold_for(w: WeaponData, emptied: bool) -> float:
	var base: float = GameSettings.player_movement.stamina_regen_delay_after_shot
	var gap := w.attack_speed
	if emptied and not w.is_infinite_ammo:
		gap = maxf(gap, GameSettings.weapon_general.auto_reload_delay + w.reload_time)
	return maxf(base, gap)


## The real gap before `w` can fire again. ⭐ attack_speed is only the COOLDOWN: a shot that empties the clip
## waits out the reload instead, which for a 1-round magazine (sniper_wep.tres) is EVERY shot.
func _inter_shot_gap_for(w: WeaponData, emptied: bool) -> float:
	var gap := w.attack_speed
	if emptied and not w.is_infinite_ammo:
		gap = maxf(gap, GameSettings.weapon_general.auto_reload_delay + w.reload_time)
	return gap


func test_no_shipped_weapon_regenerates_between_its_own_shots() -> void:
	# THE rule that decides whether shooting can deplete you at all, and the one no cost guard can catch. Every
	# spend re-floors a regen hold; a SHOT arms Attack._shot_regen_hold(). If that hold is SHORTER than the gap
	# before the weapon can fire again, it regenerates between its own shots and can never run the pool down
	# however much a shot costs. The pistol did exactly that at the old 0.35s movement delay: it earned
	# stamina_regen_idle x (0.44 - 0.35) = 2.16 standing still against a 1.80 cost, so firing was free.
	#
	# ⭐ Both cases are checked, because the interval is NOT just attack_speed. A shot that empties the magazine
	# waits out the reload, and for a 1-round magazine that is every shot: sniper_wep.tres cycles every 0.668s on
	# paper but really fires once per 3.5s, which a cadence-only guard reads as "no refund" while the pool climbs.
	var weapons := _priced_ranged_weapons()
	assert_gt(weapons.size(), 0, "expected at least one ranged weapon to validate")
	var mv: PlayerMovementSettings = GameSettings.player_movement
	assert_gt(mv.stamina_regen_delay_after_shot, mv.stamina_regen_delay_after_spend,
		"a shot must hold recovery LONGER than a movement verb, or firing regenerates as fast as it costs")
	for f in weapons:
		var w: WeaponData = weapons[f]
		for emptied in [false, true]:
			var gap := _inter_shot_gap_for(w, emptied)
			var hold := _shot_regen_hold_for(w, emptied)
			var refund: float = mv.stamina_regen_idle * maxf(gap - hold, 0.0)
			assert_almost_eq(refund, 0.0, 0.001,
				"weapon '%s' (%s shot) waits %.2fs before it can fire again but only holds recovery for %.2fs - it regenerates %.2f between its own shots, so no cost can ever deplete the pool with it" % [f, "clip-emptying" if emptied else "mid-clip", gap, hold, refund])


func test_sustained_fire_actually_drains_the_pool_for_every_weapon() -> void:
	# The player-facing consequence of the rule above, asserted as a real budget: holding the trigger on ANY
	# shipped weapon must empty a full pool in finite time, standing perfectly still (the most forgiving tier,
	# stamina_regen_idle). Before the shot hold existed the pistol's answer here was "never", and before the hold
	# accounted for reload time the sniper's was "never" too - it gained 45.75 a shot.
	var weapons := _priced_ranged_weapons()
	assert_gt(weapons.size(), 0, "expected at least one ranged weapon to validate")
	var mv: PlayerMovementSettings = GameSettings.player_movement
	for f in weapons:
		var w: WeaponData = weapons[f]
		var cost := _shot_cost_for(w)
		for emptied in [false, true]:
			var refund: float = mv.stamina_regen_idle * maxf(_inter_shot_gap_for(w, emptied) - _shot_regen_hold_for(w, emptied), 0.0)
			assert_gt(cost - refund, 0.0,
				"weapon '%s' nets %.2f stamina per %s shot standing still - firing it can never deplete the pool" % [f, cost - refund, "clip-emptying" if emptied else "mid-clip"])


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
	assert_eq(typeof(w.npc_projectile_speed_mult), TYPE_FLOAT,
		"npc_projectile_speed_mult is declared 'float = 1.0' so int-looking .tres literals still parse float")
	assert_eq(w.npc_projectile_speed_mult, 1.0,
		"Default npc_projectile_speed_mult is 1.0 — NPC rounds fly at the authored projectile_speed unless a .tres slows them for dodgeability")
	w = null


## THE "enemies never hitscan" flight-range ratchet (2026-08-25). Every ranged AI shot is a LIVE round
## (ShotResolver.ai_fires_live_projectile) whose damage exists only while the projectile does — so each
## shipped gun's AI-speed flight distance (projectile_speed x npc_projectile_speed_mult x life_time) must
## cover the farthest point its OWN trigger pulls at (effective_range + the fire_grace_range band, per
## NpcCombat.attempt_fire_range). The sniper shipped exactly this bug: 100 x 5.0 = 500m flight vs a 508m
## attempt band, so max-range bolts despawned 8m short — masked back when hitscan covered in-range damage.
## effective_range-0 lobs (the rock) get no band and ground ballistically, so they're skipped like melee/spray.
func test_shipped_ai_rounds_outfly_the_attempt_band() -> void:
	var grace: float = (load("res://resources/tuning/NpcAiSettings.tres") as NpcAiSettings).fire_grace_range
	var weapons := _priced_ranged_weapons()
	assert_gt(weapons.size(), 0, "expected at least one ranged weapon to validate")
	for f in weapons:
		var w: WeaponData = weapons[f]
		if w.projectile_scene == null or w.effective_range <= 0.0:
			continue  # no live rounds / no band — nothing to outfly
		var flight := w.projectile_speed * w.npc_projectile_speed_mult * w.projectile_life_time
		var attempt := w.effective_range + maxf(grace, 0.0)
		assert_gte(flight, attempt,
			"weapon '%s': AI rounds fly %.0fm (speed %.0f x npc mult %.2f x life %.1fs) but its trigger pulls out to %.0fm (effective_range %.0f + %.0fm grace band) — max-range shots would despawn mid-air; raise projectile_life_time or npc_projectile_speed_mult" \
			% [f, flight, w.projectile_speed, w.npc_projectile_speed_mult, w.projectile_life_time, attempt, w.effective_range, grace])


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
	# (launch_screen_shake is gone with the rest of the scoped-attack launch — the dash's trauma is
	# AirDash.screen_shake now, pinned in tests/test_upgrades.gd.)
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


func test_weapon_data_has_no_launch_fields() -> void:
	# The scoped-attack launch is GONE from the weapon. This used to pin launch_force / launch_upward defaults;
	# it now pins their ABSENCE, so nobody re-adds a "this gun can fling the player" knob by reflex. The dash's
	# real tuning is AirDash's (tests/test_upgrades.gd).
	var w := WeaponData.new()
	for dead in [&"launch_force", &"launch_upward", &"launch_on_scoped_attack", &"single_air_dash",
			&"launch_screen_shake"]:
		assert_eq(w.get(dead), null,
			"WeaponData.%s must stay removed — the air dash belongs to the AirDash ability, not to a weapon" % dead)
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
	# (single_air_dash / launch_on_scoped_attack are gone: a weapon no longer launches the player at all. The
	# air dash is its own key on the AirDash ability, whose defaults are pinned in tests/test_upgrades.gd.)
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
# ThrowableData — source defaults (Resource, no _init/_ready/autoload). Zero
# prior coverage; the smoke test only text-greps Throwable.gd.
# ---------------------------------------------------------------------------

func test_throwable_data_identity_defaults() -> void:
	var d := ThrowableData.new()
	assert_eq(typeof(d.display_name), TYPE_STRING,
		"display_name must be a String so Throwable can build a hover prompt without type coercion.")
	assert_eq(d.display_name, "",
		"Default display_name is blank so old props keep the generic 'Pick Up' prompt.")
	d = null


func test_throwable_data_mesh_accepts_scene_or_mesh() -> void:
	var d := ThrowableData.new()
	var prop := _property(d, "mesh")
	assert_false(prop.is_empty(), "ThrowableData exposes mesh as the prop's model slot")
	assert_eq(prop.get("hint", -1), PROPERTY_HINT_RESOURCE_TYPE,
		"ThrowableData.mesh uses a resource-type hint")
	assert_eq(prop.get("hint_string", ""), ModelResource.HINT,
		"ThrowableData.mesh accepts .glb/.gltf/.blend PackedScene imports and .obj Mesh imports")
	d = null


func test_throwable_data_audio_defaults() -> void:
	var d := ThrowableData.new()
	assert_true(d.pickup_sound == null,
		"Default pickup_sound is null so old props stay silent when picked up.")
	assert_true(d.held_loop_sound == null,
		"Default held_loop_sound is null so old props stay silent while carried.")
	assert_true(d.release_sound == null,
		"Default release_sound is null so old props stay silent when dropped/thrown.")
	d = null


func test_throwable_data_carry_pose_defaults() -> void:
	var d := ThrowableData.new()
	assert_eq(typeof(d.fade_while_held), TYPE_BOOL,
		"fade_while_held must be a bool so a prop type can opt out of carry transparency.")
	assert_true(d.fade_while_held,
		"Default fade_while_held is true so old props keep the shipped see-through held-object behavior.")
	assert_eq(typeof(d.face_carrier_while_held), TYPE_BOOL,
		"face_carrier_while_held must be a bool so designers can opt a prop type into Portal-style carried facing.")
	assert_false(d.face_carrier_while_held,
		"Default face_carrier_while_held is false so old props keep their authored/physics rotation.")
	assert_eq(d.face_carrier_rotation_degrees, Vector3.ZERO,
		"Default face_carrier_rotation_degrees is zero so authored meshes are not corrected unless requested.")
	d = null


func test_throwable_data_living_motion_defaults() -> void:
	var d := ThrowableData.new()
	assert_eq(typeof(d.breathe), TYPE_BOOL,
		"breathe must be a bool so living throwables can opt into a visual idle pulse.")
	assert_false(d.breathe,
		"Default breathe is false so crates and old props stay visually static.")
	assert_eq(d.breathe_amount, 0.03,
		"Default breathe_amount matches the NPC torso idle: a subtle ~3% swell.")
	assert_eq(d.breathe_rate, 1.6,
		"Default breathe_rate matches the NPC torso idle cadence.")
	d = null


func test_throwable_data_numeric_defaults() -> void:
	var d := ThrowableData.new()
	assert_eq(typeof(d.max_hp), TYPE_INT,
		"max_hp must be an int — Throwable subtracts whole damage points from it")
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


func test_throwable_data_spawns_destroy_decal_defaults_true() -> void:
	var d := ThrowableData.new()
	assert_eq(typeof(d.spawns_destroy_decal), TYPE_BOOL,
		"spawns_destroy_decal must be a bool — Throwable branches on it when destroyed")
	assert_true(d.spawns_destroy_decal,
		"Defaults true so solid props leave a scorch/blast decal; gibs override it to false")
	d = null


# is_gib gates the confetti-+-party-horn burst that ONLY gore gibs get when the
# player shoots one out of the air. A fresh prop (the template a crate/barrel
# inherits) must default false so ordinary props can never qualify for confetti —
# only a gore-gib .tres flips it true.
func test_throwable_data_is_gib_defaults_false() -> void:
	var d := ThrowableData.new()
	assert_eq(typeof(d.is_gib), TYPE_BOOL,
		"is_gib must be a bool — Throwable branches on it to pick confetti vs. the usual gore puff")
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
