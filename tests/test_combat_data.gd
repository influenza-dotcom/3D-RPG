extends GutTest

## Combat data + simple components — GUT unit suite.
##
## COVERS:
##   - The per-shot STAMINA PRICE and the post-shot REGEN HOLD, through the pure statics the trigger itself runs
##     (Attack.shot_stamina_cost_for / shot_stamina_ceiling_for / shot_regen_hold_for): first their guarantees on
##     synthetic weapons (the sprint-drain clamp, the refund-proof floor, a hold that lasts exactly until the weapon
##     can fire again), then a sweep of every shipped ranged .tres against the design rules (the test_calibers.gd
##     idiom). Nothing here re-derives the price, so a production regression and a .tres retune both go red. The
##     regen sweep reads the hold from Attack._shot_regen_hold() itself - a bare baseline Attack holding a real
##     Ammo clip - and measures it against the weapon's own TIMELINE, read off the machinery that really paces the
##     next shot (the attack Timer's cooldown, the clip's consume_ammo() gate, the reload Timer _on_reload_reload()
##     starts), so the instance glue that decides "this shot emptied the clip" and builds the reload wait is on the
##     hook too, not just the static it feeds. Every shipped cadence sits under the shot delay, so a synthetic slow
##     gun (cooldown > reload wait > shot delay) drives that same glue to hold the cooldown input to account.
##   - The AI flight-range ratchet: every shipped gun's AI round outflies the band its own trigger pulls in
##     (ProjectileSpawner.round_speed x projectile_life_time against NpcCombat.attempt_fire_range).
##   - What a FRESHLY AUTHORED weapon (WeaponData.new() — the template every .tres inherits its unset fields from)
##     does out of the box, asserted as behaviour instead of as copied literals: it pays exactly one baseline shot
##     cost, rewards headshots and sneak attacks, outflies its own attempt band, reloads into a magazine that fires
##     one round per pull, hands its Timers legal durations, has no optic of its own, and sprays in colour. Its
##     presentation defaults are read the same way, through the code that branches on them: drawing it leaves the
##     wielder's pace alone (WeaponStance), an NPC holding it passes the laser-sight gate, it smokes at the muzzle
##     (MuzzleSmoke.puff_scale) and it keeps its view model up while aiming (GunMesh.view_model_visible_now). A .tres
##     only stores what it overrides, so flipping one of these defaults silently changes every shipped weapon that
##     inherits it — a behaviour change, not a retune.
##   - Props: a prop whose ThrowableData authors nothing behaves exactly like a prop with no data at all (the "old
##     props keep working" promise, read through Throwable's own resolvers), a smashed prop whose data authors no
##     decal opt-out still scorching the floor it broke on (the destroy-decal ship decision, driven through
##     Throwable._spawn_destroy_decal on the shared prefab), the mesh slot's accepted types, and the breathing defaults.
##   - spray_paint.tres wiring; Inventory.equip() state; Ammo clip math + per-weapon background reload; Reload's signal.
##
## DELIBERATELY SKIPS (and why):
##   - Pure tuning defaults with no invariant behind them (knockback, screen shake, hitstop, explosion force,
##     pellet spread, bullet gravity, launch angle, a prop's mass / max_hp / destroy shake): a designer retune is
##     not a bug, so pinning those literals would only detect change.
##   - The price's instance path and the spend against a live wielder (Attack._shot_stamina_cost /
##     _spend_shot_stamina) — tests/test_combat_systems.gd.
##   - An AGILITY-scaled wielder's regen hold: that needs a Character stat sheet behind effective_attack_speed /
##     effective_reload_time, so the sweep here holds the baseline wielder (no character: authored durations).
##   - Flag defaults with no reader a unit test can drive: spawns_casing / auto_reload (read only inside attack.gd's
##     in-tree shot resolution) and auto_fire (attack.gd's semi-auto gate polls live Input; MuzzleFlash's
##     _do_muzzle_flash only hands it, as a bool, to MuzzleFlash.hold_seconds, so there it shows up only as how long a
##     live in-tree flash stays lit). ThrowableData's sound
##     slots are Object exports with no initializer, so null is the only default they can have; Throwable's
##     silent-by-default sound resolution is tests/test_combat_systems.gd's.
##   - Defaults already driven where they are read: WeaponData.is_spray_paint (ShotResolver.ai_fires_live_projectile
##     in test_a_freshly_authored_gun_outflies_its_own_attempt_band below, WeaponAudio.fire_bus_for in
##     tests/test_audio_bus_hygiene.gd) and ThrowableData.is_gib (a fresh ThrowableData never confettis:
##     tests/test_combat_systems.gd::test_interactable_is_confetti_kill_false_for_non_gib_data).
##   - Inventory.equip() signal emits — test_smoke.gd::test_inventory_equip_*.
##   - Ammo._ready / _on_weapon_changed / set_to_max_ammo — _ready null-derefs its (unset) inventory, so the node
##     can never be add_child'd bare; the swap/bank/restore logic needs a wired Inventory.
##   - Reload._unhandled_input — engine-driven input routing; its payload is reload_weapon(), called directly.
##
## Resources are .new() and dropped with = null. The nodes (Inventory / Ammo / Reload / Attack / ScopeIn /
## SprayPainter / BodyModelSwap / Throwable / Weapon / WeaponStance, and an NPC built from its script) are .new() and
## .free()d WITHOUT add_child, so no _ready / _unhandled_input ever runs. Only three things enter the tree: the Inventory
## case that mirrors the proven smoke-test setup, the bare Timers the timeline helper hands an Attack (a Timer only
## starts inside the tree), which it frees itself, and the destroy-decal test's frozen throwable.tscn prop over a floor
## slab (the tests/test_throwable_destructible.gd harness: both autofreed, every decal it spawns freed before asserting).

const PISTOL = preload("res://resources/weapons/pistol.tres")
const SHOTGUN = preload("res://resources/weapons/shotgun.tres")
const SPRAY_PAINT = preload("res://resources/weapons/spray_paint.tres")
## Folder swept by the shipped-weapon guards below (the test_calibers.gd idiom): a derived price is only as safe as
## the WORST .tres on disk, so the guards validate every one instead of the three preloaded here.
const WEAPONS_DIR := "res://resources/weapons/"
const NPC_AI_SETTINGS := "res://resources/tuning/NpcAiSettings.tres"
const NPC_PATH := "res://scripts/npc/npc.gd"

func _property(obj: Object, prop_name: String) -> Dictionary:
	for p in obj.get_property_list():
		if p.get("name", "") == prop_name:
			return p
	return {}


## A movement tuning with the shipped SHAPE (1.8 per baseline shot, a 0.95 x 18.0 sprint-drain clamp), built fresh
## so the rule tests read their own numbers instead of whatever the live PlayerMovementSettings.tres is tuned to.
func _tuning() -> PlayerMovementSettings:
	var mv := PlayerMovementSettings.new()
	mv.stamina_shot_cost = 1.8
	mv.stamina_shot_drain_ceiling = 0.95
	mv.stamina_sprint_drain = 18.0
	return mv


# ---------------------------------------------------------------------------
# The shot-price and regen-hold RULES (Attack's pure statics), on synthetic weapons.
# ---------------------------------------------------------------------------

func test_shot_price_clamp_holds_any_authored_weapon_under_the_sprint_drain() -> void:
	# "Shooting never costs more per second than sprinting" must be a THEOREM of the price, not something the
	# shipped .tres files happen to respect. So author the worst weapon imaginable - a thousand-damage, 16-pellet
	# exploding round - at every cadence from buzz-saw to bolt-action, and hold its held-trigger drain to sprinting.
	var mv := _tuning()
	for cadence in [0.05, 0.125, 0.44, 2.0]:
		var absurd := WeaponData.new()
		absurd.damage = 1000.0
		absurd.pellet_count = 16
		absurd.projectile_explodes = true
		absurd.attack_speed = cadence
		var cost := Attack.shot_stamina_cost_for(absurd, mv)
		assert_gt(cost, 0.0,
			"an over-powered weapon at a %.3fs cadence must still cost stamina - the clamp caps the price, it never makes fire free" % cadence)
		assert_lt(cost / cadence, mv.stamina_sprint_drain,
			"an over-powered weapon at a %.3fs cadence drains %.1f/sec on a held trigger, at or above the %.1f/sec sprint drain - the cadence clamp is not holding" % [cadence, cost / cadence, mv.stamina_sprint_drain])
	# CONTROL: an ordinary gun sits under the clamp and is priced by its effort - double the damage, double the
	# price. Without this, a clamp that flattened EVERY weapon to one price would pass the loop above.
	var plain := WeaponData.new()
	plain.attack_speed = 0.44
	var heavy := WeaponData.new()
	heavy.attack_speed = 0.44
	heavy.damage = 2.0
	assert_almost_eq(Attack.shot_stamina_cost_for(heavy, mv), 2.0 * Attack.shot_stamina_cost_for(plain, mv), 0.001,
		"below the clamp the price must track power: twice the damage must cost twice the stamina per shot")


func test_shot_price_never_refunds_stamina_and_never_prices_a_swing() -> void:
	var mv := _tuning()
	var gun := WeaponData.new()
	gun.attack_speed = 0.44
	assert_gt(Attack.shot_stamina_cost_for(gun, mv), 0.0,
		"CONTROL: an ordinary ranged shot costs stamina - otherwise every zero below proves nothing")
	gun.stamina_cost_mult = -5.0
	assert_almost_eq(Attack.shot_stamina_cost_for(gun, mv), 0.0, 0.0001,
		"a negative stamina_cost_mult must floor the price to FREE - it may never pay stamina back on every trigger pull")
	gun.stamina_cost_mult = 1.0
	gun.damage = -100.0
	assert_almost_eq(Attack.shot_stamina_cost_for(gun, mv), 0.0, 0.0001,
		"negative damage must floor the price to free rather than invert it into a per-shot refill")
	var knife := WeaponData.new()
	knife.is_melee = true
	knife.damage = 50.0
	knife.attack_speed = 0.44
	assert_almost_eq(Attack.shot_stamina_cost_for(knife, mv), 0.0, 0.0001,
		"a melee swing is priced by stamina_melee_attack_cost - a non-zero RANGED price would charge every swing twice")
	assert_almost_eq(Attack.shot_stamina_cost_for(null, mv), 0.0, 0.0001,
		"with nothing equipped there is no shot to pay for")


func test_shot_regen_hold_lasts_until_the_weapon_can_fire_again_and_no_longer() -> void:
	# The hold is the real gap to the next possible shot, floored at the shot delay. Too SHORT and a weapon
	# regenerates between its own shots, so firing is free; too LONG and a quick gun eats a stamina lockout for a
	# reload it never reached. Numbers: a 1.5s shot delay and a 3.5s auto-reload wait (the sniper's shape).
	const BASE := 1.5
	const RELOAD_WAIT := 3.5
	var magazine_gun := WeaponData.new()
	assert_almost_eq(Attack.shot_regen_hold_for(magazine_gun, false, BASE, 0.1, RELOAD_WAIT), BASE, 0.001,
		"a mid-clip shot from a fast gun holds exactly the shot delay - a reload it has not reached must not lock stamina")
	assert_almost_eq(Attack.shot_regen_hold_for(magazine_gun, false, BASE, 2.0, RELOAD_WAIT), 2.0, 0.001,
		"a cooldown longer than the shot delay IS the gap to the next shot, so the hold must stretch to cover all of it")
	assert_almost_eq(Attack.shot_regen_hold_for(magazine_gun, true, BASE, 0.668, RELOAD_WAIT), RELOAD_WAIT, 0.001,
		"a clip-emptying shot cannot be followed until the reload lands, so it must hold recovery for the whole reload wait")
	# The mirror case: a bolt-action whose cooldown (4.0s) outlasts even its reload wait. Emptying the clip ADDS a
	# wait the weapon may have to sit through; it never replaces the cooldown, so the hold is the longer of the two.
	assert_almost_eq(Attack.shot_regen_hold_for(magazine_gun, true, BASE, 4.0, RELOAD_WAIT), 4.0, 0.001,
		"a clip-emptying shot whose cooldown outlasts its reload still waits the cooldown - the hold must cover the LONGER of the two")
	var endless := WeaponData.new()
	endless.is_infinite_ammo = true
	assert_almost_eq(Attack.shot_regen_hold_for(endless, true, BASE, 0.1, RELOAD_WAIT), BASE, 0.001,
		"an infinite-ammo weapon never reloads, so an 'empty' clip must not stretch its hold to a reload it never waits out")
	assert_almost_eq(Attack.shot_regen_hold_for(null, true, BASE, 0.1, RELOAD_WAIT), BASE, 0.001,
		"with no weapon the hold is just the shot delay")


# ---------------------------------------------------------------------------
# Shipped-weapon guards for the DERIVED per-shot stamina price. The price is stamina_shot_cost x
# WeaponData.stamina_effort() x stamina_cost_mult, clamped to stamina_shot_drain_ceiling x stamina_sprint_drain x
# attack_speed (Attack.shot_stamina_cost_for). Because power and cadence are authored on separate knobs, a
# rebalance can quietly invert the design or rail a weapon against its clamp with nothing else going red, so the
# whole folder is swept through production's own rule.
#
# SCOPE NOTE: the drain figures in the first two guards are the RAW held-trigger rate. They do NOT model the regen
# a weapon earns back between its own shots - that is the regen hold's job and the subject of
# test_no_shipped_weapon_regenerates_between_its_own_shots below.
# ---------------------------------------------------------------------------

## The price of one shot from `w` under the live tuning - production's rule, fed exactly as the trigger feeds it.
func _shot_cost_for(w: WeaponData) -> float:
	return Attack.shot_stamina_cost_for(w, GameSettings.player_movement)


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
		# The held-trigger rate is shots per real second, so the weapon's own cooldown is the divisor. A 0 cooldown
		# is not a gun that fires infinitely fast - the attack Timer cannot wait 0 - so it fails on its own here.
		assert_gt(w.attack_speed, 0.0,
			"weapon '%s' authors a %.3fs attack_speed - the attack Timer cannot wait that, so its fire rate is undefined" % [f, w.attack_speed])
		if w.attack_speed <= 0.0:
			continue
		var per_second := _shot_cost_for(w) / w.attack_speed
		assert_lt(per_second, sprint_drain,
			"weapon '%s' drains %.1f stamina/sec on a held trigger, at or above the %.1f/sec sprint drain - lower its damage or its stamina_cost_mult, or shooting costs more than running" % [f, per_second, sprint_drain])


func test_no_shipped_weapon_is_railed_against_its_cadence_clamp() -> void:
	# The clamp's failure mode is SILENT CHEAPENING, not an inversion: once a weapon's derived price reaches its
	# ceiling the clamp discards the derived value, so making the weapon MORE powerful (or faster) stops raising its
	# cost and every other test here stays green. Nothing shipped may sit on that rail, so the day someone raises the
	# launcher's damage the suite says so. (A price is never above its ceiling, so "below it" means "not railed".)
	var weapons := _priced_ranged_weapons()
	assert_gt(weapons.size(), 0, "expected at least one ranged weapon to validate")
	var mv: PlayerMovementSettings = GameSettings.player_movement
	for f in weapons:
		var w: WeaponData = weapons[f]
		var cost := Attack.shot_stamina_cost_for(w, mv)
		var ceiling := Attack.shot_stamina_ceiling_for(w, mv)
		assert_lt(cost, ceiling,
			"weapon '%s' costs %.2f stamina/shot, which is its %.2f cadence clamp (effort %.2f) - its price has stopped tracking its power, so raise stamina_shot_drain_ceiling or slow the weapon down" % [f, cost, ceiling, w.stamina_effort()])


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


## The regen hold production ACTUALLY arms after a shot from `w`, read off Attack._shot_regen_hold() on a bare
## Attack (never add_child'd, so no _ready) wielding `w` with a real Ammo clip. `emptied` sets that clip to what it
## reads right after the shot that fired the last round (0 left) versus a mid-clip shot (a full magazine left).
## ⭐ Deliberately the INSTANCE method, not the static it feeds: _shot_regen_hold() is the glue that decides "this
## shot emptied the clip" and composes the reload wait, and feeding the static here from the same inputs the timeline
## below is read from would make "the hold covers the gap" true by construction for any glue regression. With no
## `character` there is no stat sheet, so effective_attack_speed / effective_reload_time are the authored values -
## the same baseline wielder _inter_shot_gap_for below drives.
func _shot_regen_hold_for(w: WeaponData, emptied: bool) -> float:
	var atk := Attack.new()
	var mag := Ammo.new()
	mag.current_weapon = w
	mag.current_ammo = 0 if emptied else maxi(w.max_ammo, 1)
	atk.clip = mag
	atk.current_weapon = w
	var hold: float = atk._shot_regen_hold()
	atk.free()
	mag.free()
	return hold


## The REQUIREMENT side of the regen guards: how long `w` really waits before it can fire again, READ OFF the machinery
## that paces its next shot rather than retyped from the hold's own formula. A second bare baseline Attack (never
## add_child'd, no `character`) is handed real attack / reload / swap Timers - in the tree, since a Timer only starts
## there - and a real Ammo clip left the way the shot left it (`emptied` = 0 rounds, otherwise a full magazine):
##   - the COOLDOWN is the attack Timer's wait_time once start_secondary_cooldown() puts the weapon on its normal fire
##     cooldown;
##   - whether the next pull needs a RELOAD is the clip's own consume_ammo() answer, so an infinite-ammo weapon, or a
##     clip with a round left, says "no" exactly the way the trigger's ammo gate would;
##   - when it does, the reload is the reload Timer that _on_reload_reload() really starts, behind the auto-reload
##     beat (auto_reload_delay): a self-reloading gun (sniper_wep.tres) waits that beat before Attack starts its
##     reload, and the hold charges a manual reloader, which waits on the reload key instead, the same beat.
## A clip-emptying shot whose reload never starts can never be followed at all: it fails here and returns INF.
## The Timers wait the same effective_attack_speed / effective_reload_time the hold is built from - those ARE the
## durations - so what this puts on the hook is everything around them: the emptied test, the reload branch, the beat,
## and whether a reload can start at all. For a 1-round magazine (sniper_wep.tres) the reload branch is EVERY shot.
func _inter_shot_gap_for(w: WeaponData, emptied: bool) -> float:
	var atk := Attack.new()
	var mag := Ammo.new()
	var cooldown := Timer.new()
	var reload_timer := Timer.new()
	var swap_timer := Timer.new()
	for t in [cooldown, reload_timer, swap_timer]:
		add_child(t)
	mag.current_weapon = w
	mag.current_ammo = 0 if emptied else maxi(w.max_ammo, 1)
	atk.clip = mag
	atk.current_weapon = w
	atk.attack = cooldown
	atk.reload = reload_timer
	atk.swap = swap_timer
	atk.start_secondary_cooldown(w)
	var gap := cooldown.wait_time
	if not mag.consume_ammo():
		atk._on_reload_reload()
		var reloading := not reload_timer.is_stopped()
		assert_true(reloading,
			"weapon '%s': the %s shot leaves nothing to fire, but no reload starts - the weapon can never shoot again" % [w.resource_path.get_file(), "clip-emptying" if emptied else "mid-clip"])
		gap = maxf(gap, GameSettings.weapon_general.auto_reload_delay + reload_timer.wait_time) if reloading else INF
	for t in [cooldown, reload_timer, swap_timer]:
		t.free()
	atk.free()
	mag.free()
	return gap


func test_a_slow_gun_holds_recovery_for_its_whole_cooldown_whether_or_not_the_shot_emptied_the_clip() -> void:
	# The shipped sweeps below cannot see the COOLDOWN input of _shot_regen_hold(): every shipped cadence (1.4s at
	# most) sits under the 1.5s shot delay, so the floor answers for all of them. A glue that fed the rule the wrong
	# cadence, or a rule that let an emptied clip's reload wait REPLACE the cooldown instead of extending it, would
	# stay green there. So author the gun that exposes both: a 4.0s bolt-action with a quick 5-round reload. Its next
	# shot is a full cooldown away on either path, and any shorter hold hands back stamina_regen_idle per missing
	# second on every shot. Driven through the instance glue (_shot_regen_hold_for above), not the static.
	var slow := WeaponData.new()
	slow.attack_speed = 4.0
	slow.reload_time = 2.0
	slow.max_ammo = 5
	var base_hold: float = GameSettings.player_movement.stamina_regen_delay_after_shot
	var reload_wait: float = GameSettings.weapon_general.auto_reload_delay + slow.reload_time
	# Preconditions: cooldown > reload wait > shot delay, strictly. Only the cooldown can then give the right hold,
	# and dropping it for the reload wait or the floor gives a DIFFERENT wrong value each. A retune of either global
	# that broke the ordering would make this test vacuous, so it fails here first.
	assert_false(slow.is_infinite_ammo,
		"precondition: the synthetic gun has a finite clip, so its clip-emptying shot really does reach the reload branch")
	assert_gt(slow.attack_speed, reload_wait,
		"precondition: the synthetic gun's %.2fs cooldown must outlast its %.2fs reload wait (auto_reload_delay + reload_time)" % [slow.attack_speed, reload_wait])
	assert_gt(reload_wait, base_hold,
		"precondition: the synthetic gun's %.2fs reload wait must outlast the %.2fs shot delay, or a hold that dropped the cooldown could not be told from the floor" % [reload_wait, base_hold])
	assert_gt(slow.attack_speed, base_hold,
		"precondition: the synthetic gun's %.2fs cooldown must outlast the %.2fs shot delay, or the floor would answer for it like every shipped gun" % [slow.attack_speed, base_hold])
	for emptied in [false, true]:
		var hold := _shot_regen_hold_for(slow, emptied)
		assert_almost_eq(hold, slow.attack_speed, 0.001,
			"a %.2fs-cooldown gun's %s shot holds recovery for %.2fs - it cannot fire again for the whole cooldown, so it would regenerate for %.2fs between its own shots" % [slow.attack_speed, "clip-emptying" if emptied else "mid-clip", hold, maxf(slow.attack_speed - hold, 0.0)])
	slow = null


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
	# The wait is _inter_shot_gap_for's: the Timers and the clip gate that really pace the next shot, so a hold that
	# drifts from them (a missed emptied clip, a dropped reload wait or beat, a reload that never starts) goes red.
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


func test_no_shipped_weapon_locks_recovery_past_its_next_possible_shot() -> void:
	# The other edge of the same hold. It exists to cover the wait before the weapon can fire again, floored at the
	# shot delay - and no longer. A hold that outlasts BOTH is a stamina lockout for nothing: a mid-clip pistol shot
	# that waited out a reload it never reached would sit on an empty pool 1.6s instead of 1.5s after every shot.
	var weapons := _priced_ranged_weapons()
	assert_gt(weapons.size(), 0, "expected at least one ranged weapon to validate")
	var mv: PlayerMovementSettings = GameSettings.player_movement
	var stretched := 0
	for f in weapons:
		var w: WeaponData = weapons[f]
		for emptied in [false, true]:
			var gap := _inter_shot_gap_for(w, emptied)
			var hold := _shot_regen_hold_for(w, emptied)
			var longest_needed := maxf(mv.stamina_regen_delay_after_shot, gap)
			assert_true(hold <= longest_needed + 0.001,
				"weapon '%s' (%s shot) holds recovery for %.2fs, but it can fire again after %.2fs and the shot delay is only %.2fs - the player is locked out of stamina for a reload the shot never triggered" % [f, "clip-emptying" if emptied else "mid-clip", hold, gap, mv.stamina_regen_delay_after_shot])
			if hold > mv.stamina_regen_delay_after_shot + 0.001:
				stretched += 1
	# CONTROL: the bound is not only ever met by the bare shot delay. At least one shipped shot (today, every
	# clip-emptying shot whose reload wait outlasts the delay - sniper_wep.tres's 3.5s among them) really holds past
	# it, so the sweep did reach a hold that tracks a real wait.
	assert_gt(stretched, 0,
		"no shipped shot holds recovery past the %.2fs shot delay - the bound above only ever compared the floor, or the clip-emptying reload wait is no longer reaching the hold" % mv.stamina_regen_delay_after_shot)


## THE "enemies never hitscan" flight-range ratchet (2026-08-25). Every ranged AI shot is a LIVE round
## (ShotResolver.ai_fires_live_projectile) whose damage exists only while the projectile does — so each shipped
## gun's AI round must fly (ProjectileSpawner.round_speed for an AI wielder x projectile_life_time) at least as far
## as the farthest point its OWN trigger pulls at (NpcCombat.attempt_fire_range: effective_range + the
## fire_grace_range band). The sniper shipped exactly this bug: 100 x 5.0 = 500m flight vs a 508m attempt band, so
## max-range bolts despawned 8m short — masked back when hitscan covered in-range damage. effective_range-0 lobs
## (the rock) get no band and ground ballistically, so they're skipped like melee/spray.
func test_shipped_ai_rounds_outfly_the_attempt_band() -> void:
	var grace: float = (load(NPC_AI_SETTINGS) as NpcAiSettings).fire_grace_range
	var weapons := _priced_ranged_weapons()
	assert_gt(weapons.size(), 0, "expected at least one ranged weapon to validate")
	var checked := 0
	for f in weapons:
		var w: WeaponData = weapons[f]
		if not ShotResolver.ai_fires_live_projectile(w) or w.effective_range <= 0.0:
			continue  # no live rounds / no band — nothing to outfly
		checked += 1
		var flight := ProjectileSpawner.round_speed(w, false) * w.projectile_life_time
		var attempt := NpcCombat.attempt_fire_range(w.effective_range, w, grace)
		assert_gte(flight, attempt,
			"weapon '%s': AI rounds fly %.0fm (speed %.0f x npc mult %.2f x life %.1fs) but its trigger pulls out to %.0fm (effective_range %.0f + %.0fm grace band) — max-range shots would despawn mid-air; raise projectile_life_time or npc_projectile_speed_mult" \
			% [f, flight, w.projectile_speed, w.npc_projectile_speed_mult, w.projectile_life_time, attempt, w.effective_range, grace])
	assert_gt(checked, 0, "at least one shipped gun must fire live AI rounds, or this ratchet validated nothing")


# ---------------------------------------------------------------------------
# A FRESHLY AUTHORED weapon (WeaponData.new()) — what every field a .tres leaves unset inherits, asserted as
# what that weapon DOES rather than as the literals it happens to be declared with.
# ---------------------------------------------------------------------------

func test_a_freshly_authored_gun_pays_exactly_one_baseline_shot_cost() -> void:
	# stamina_shot_cost is documented as "what one baseline shot costs", which only holds if a weapon nobody has
	# priced - one damage, one pellet, no blast, an untouched trim - is exactly one unit of effort. A default that
	# drifts on any of those silently re-prices every .tres that inherits it.
	var mv := _tuning()
	var w := WeaponData.new()
	w.attack_speed = 0.44  # an authored cadence: the bare 0.1 default sits just under the clamp's break-even
	assert_almost_eq(Attack.shot_stamina_cost_for(w, mv), mv.stamina_shot_cost, 0.001,
		"a freshly authored gun must cost exactly stamina_shot_cost per shot - otherwise the global knob no longer means 'one baseline shot'")
	w = null


func test_a_freshly_authored_weapon_rewards_headshots_and_sneak_attacks() -> void:
	var w := WeaponData.new()
	var body := ShotResolver.resolve_damage(w, false, false, -1.0)
	var head := ShotResolver.resolve_damage(w, true, false, -1.0)
	var sneak := ShotResolver.resolve_damage(w, false, true, -1.0)
	var stealth_head := ShotResolver.resolve_damage(w, true, true, -1.0)
	var from_behind := ShotResolver.resolve_damage(w, false, false, -1.0, true)
	assert_gt(body, 0.0, "a freshly authored weapon must actually hurt - every bonus below multiplies this")
	assert_gt(head, body, "a headshot from a fresh weapon must hit harder than a body shot, or aiming for the head buys nothing")
	assert_gt(sneak, body, "a sneak attack on an off-guard target must hit harder than a body shot, or stealth buys nothing")
	assert_gt(stealth_head, maxf(head, sneak), "a stealth headshot must STACK both bonuses rather than take the larger one")
	assert_almost_eq(from_behind, body, 0.001,
		"the backstab rear-arc bonus is opt-in per weapon (the knife authors it) - a fresh weapon hitting from behind deals a plain body shot")
	w = null


func test_a_freshly_authored_gun_outflies_its_own_attempt_band() -> void:
	# The ratchet above, for the template: a designer who makes a new gun and only drops in a projectile scene must
	# not ship rounds that despawn short of where the AI pulls the trigger.
	var grace: float = (load(NPC_AI_SETTINGS) as NpcAiSettings).fire_grace_range
	var w := WeaponData.new()
	w.projectile_scene = PackedScene.new()
	assert_true(ShotResolver.ai_fires_live_projectile(w),
		"precondition: a fresh gun with a projectile scene fires LIVE rounds for an AI, so its flight range is its damage range")
	var flight := ProjectileSpawner.round_speed(w, false) * w.projectile_life_time
	var attempt := NpcCombat.attempt_fire_range(w.effective_range, w, grace)
	assert_gte(flight, attempt,
		"a freshly authored gun's AI round flies %.0fm but its trigger pulls out to %.0fm - every new gun's max-range shots would despawn mid-air" % [flight, attempt])
	w = null


func test_a_freshly_authored_weapon_dry_fires_until_reloaded_then_fires_one_round_per_pull() -> void:
	var a := Ammo.new()
	var w := WeaponData.new()
	a.current_weapon = w
	assert_false(a.consume_ammo(),
		"an unfilled clip must dry-fire - rounds come from a reload or set_to_max_ammo on equip, never from nowhere")
	a.reload()
	var shots := 0
	while shots < 1000 and a.consume_ammo():
		shots += 1
	assert_gt(shots, 0,
		"a freshly authored weapon must reload into a magazine that actually FIRES - an empty default would dry-click every new gun")
	assert_eq(shots, w.max_ammo,
		"a full magazine must give exactly max_ammo trigger pulls - one round per pull, no free rounds and none skipped")
	a.free()
	w = null


func test_a_freshly_authored_weapon_hands_its_timers_legal_durations() -> void:
	# Attack assigns these straight to Timer.wait_time, and a wait_time of 0 is an engine error.
	var atk := Attack.new()
	var w := WeaponData.new()
	assert_gt(atk.effective_attack_speed(w), 0.0,
		"the attack Timer waits this cadence - a 0 would error on the first shot of every newly authored gun")
	assert_false(w.is_infinite_ammo,
		"precondition: a fresh weapon has a finite clip, so it really does reach the reload below")
	assert_gt(atk.effective_reload_time(w), 0.0,
		"the reload Timer waits this duration - a 0 would error on the first reload of every newly authored gun")
	atk.free()
	w = null


func test_a_freshly_authored_weapon_has_no_optic_of_its_own() -> void:
	var si := ScopeIn.new()
	var w := WeaponData.new()
	var global_fov: float = si.global_scoped_fov()
	assert_false(w.has_variable_scope_zoom(),
		"a fresh weapon is not a variable scope, so the mouse wheel keeps switching weapons straight through ADS")
	assert_almost_eq(si.scoped_target_fov(w), global_fov, 0.001,
		"a fresh weapon's ADS must ease to the global magnification solve - scoped_fov_override's 0.0 means 'no optic of my own'")
	# CONTROL: the same weapon with an authored optic does NOT fall through, so the assert above is not vacuous.
	w.scoped_fov_override = 12.0
	assert_true(absf(global_fov - 12.0) > 1.0, "the control FOV must differ from the global solve or it proves nothing")
	assert_almost_eq(si.scoped_target_fov(w), 12.0, 0.001,
		"an authored scoped_fov_override must win over the global solve")
	si.free()
	w = null


func test_a_spray_can_that_authors_no_palette_still_sprays_in_colour() -> void:
	var atk := Attack.new()
	var painter := SprayPainter.new()
	painter.host = atk
	var can := WeaponData.new()
	can.is_spray_paint = true
	atk.current_weapon = can
	assert_ne(painter.resolved_color(), Color.WHITE,
		"a spray can that does not author paint_colors (spray_paint.tres does not) must paint from the inherited palette, not the white no-palette fallback")
	var distinct := {}
	for c in can.paint_colors:
		distinct[c] = true
	assert_gt(distinct.size(), 1,
		"the inherited palette needs more than one distinct colour, or Zoom + wheel cycling changes nothing")
	# CONTROL: with the palette emptied the painter really does fall back to white, so the first assert read the palette.
	var no_palette: Array[Color] = []
	can.paint_colors = no_palette
	assert_eq(painter.resolved_color(), Color.WHITE,
		"a weapon with no palette paints white - the fallback the first assert must NOT be seeing")
	painter.free()
	atk.free()
	can = null


## An off-tree NPC (its _ready never runs) holding `weapon` DRAWN: a Weapon hub whose Inventory equips `weapon` and
## whose Attack is out of the holster, plus the WeaponStance child NPC._ready builds for a combatant, pointed at it.
## Free it with _free_npc_drawing.
func _npc_drawing(weapon: WeaponData) -> Dictionary:
	var npc = load(NPC_PATH).new()
	var rig := Weapon.new()
	rig.inventory = Inventory.new()
	rig.inventory.equipped_weapon = weapon
	rig.attack = Attack.new()
	rig.attack.holstered = false
	npc._weapon = rig
	var stance := WeaponStance.new()
	stance.host = npc
	return {"npc": npc, "rig": rig, "stance": stance}


func _free_npc_drawing(g: Dictionary) -> void:
	var rig: Weapon = g["rig"]
	var npc = g["npc"]
	g["stance"].free()
	npc._weapon = null
	rig.attack.free()
	rig.inventory.free()
	rig.free()
	npc.free()


# A weapon imposes no movement penalty out of the box: move_speed_multiplier is the wielder's speed factor WHILE THIS
# WEAPON IS DRAWN (WeaponStance for an NPC, GroundMovement for the player); only a heavier .tres authors a slowdown
# (FNV-style). pistol.tres and rock_weapon.tres author none, so this is the pace they are carried at.
func test_a_freshly_authored_weapon_does_not_slow_the_wielder_who_draws_it() -> void:
	var g := _npc_drawing(null)
	var stance: WeaponStance = g["stance"]
	var rig: Weapon = g["rig"]
	var empty_handed := stance.current_move_speed()
	assert_gt(empty_handed, 0.0, "precondition: the NPC walks at a real pace with nothing drawn")
	rig.inventory.equipped_weapon = WeaponData.new()
	assert_almost_eq(stance.current_move_speed(), empty_handed, 0.0001,
		"drawing a freshly authored weapon must leave the wielder at exactly the pace empty hands give - only a .tres that authors a heavier weapon may slow its holder, and every .tres that authors nothing inherits this")
	# CONTROL: a drawn weapon that DOES author a slowdown slows the same stance, so the assert above really read the
	# drawn weapon rather than a stance that ignores what is in hand.
	var heavy := WeaponData.new()
	heavy.move_speed_multiplier = 0.5
	rig.inventory.equipped_weapon = heavy
	assert_lt(stance.current_move_speed(), empty_handed,
		"control: drawing a weapon authored heavy must slow the same wielder, or the stance never read the drawn weapon")
	_free_npc_drawing(g)


func test_an_npc_drawing_a_freshly_authored_gun_passes_the_laser_sight_gate() -> void:
	# The NPC aiming laser is the player's "you are being aimed at" telegraph. It is double-gated - the NPC's own
	# show_laser AND the weapon's has_laser_sight, read through npc.gd _current_weapon_has_laser_sight() - and this is
	# the weapon half. pistol.tres, shotgun.tres, smg.tres and rock_weapon.tres author no has_laser_sight, so the fresh
	# answer is the one an NPC holding them gets.
	var g := _npc_drawing(WeaponData.new())
	var npc = g["npc"]
	assert_true(npc._current_weapon_has_laser_sight(),
		"an NPC drawing a freshly authored gun must pass the weapon's laser-sight gate - only a weapon that authors has_laser_sight off (the fists, the knife, the spray can) turns the telegraph off")
	# CONTROL: the same NPC drawing a gun that turns the sight off hides it, so the answer above came from the weapon.
	var rig: Weapon = g["rig"]
	var no_sight := WeaponData.new()
	no_sight.has_laser_sight = false
	rig.inventory.equipped_weapon = no_sight
	assert_false(npc._current_weapon_has_laser_sight(),
		"control: an NPC drawing a weapon authored with has_laser_sight off must fail the weapon's laser-sight gate")
	_free_npc_drawing(g)


func test_a_freshly_authored_gun_smokes_at_the_muzzle() -> void:
	# has_muzzle_flash is the shared "this weapon goes bang" gate: MuzzleFlash, SparkAttack and MuzzleSmoke each skip a
	# weapon that turns it off (the fists, the knife, the spray can author it off). MuzzleSmoke.puff_scale is the pure
	# one of those gates. pistol.tres, shotgun.tres, smg.tres, sniper_wep.tres and rock_weapon.tres author no
	# has_muzzle_flash, so the fresh answer is theirs.
	var gun := WeaponData.new()
	assert_gt(MuzzleSmoke.puff_scale(gun, 1.0), 0.0,
		"a freshly authored gun fired with the player's smoke dial at full must puff smoke - a gun that authors nothing must still read as a firearm")
	# CONTROL: the same weapon with the flag turned off does not smoke, so the puff above came from the flag.
	gun.has_muzzle_flash = false
	assert_eq(MuzzleSmoke.puff_scale(gun, 1.0), 0.0,
		"control: a weapon authored with has_muzzle_flash off must not smoke at any dial")
	gun = null


func test_a_freshly_authored_gun_keeps_its_view_model_up_while_aiming() -> void:
	# Only a crisp-scope weapon (sniper_wep.tres authors disable_dof_while_scoped) hides its first-person model while
	# aiming, so you sight THROUGH the scope; every other gun keeps its model up for iron-sight ADS. That per-frame
	# decision is GunMesh.view_model_visible_now, and every .tres that authors no disable_dof_while_scoped (the
	# pistol, shotgun, smg, grenade launcher) takes the fresh answer.
	var gun := WeaponData.new()
	assert_true(GunMesh.view_model_visible_now(true, true, gun),
		"aiming a freshly authored gun must keep its view model on screen for iron-sight ADS - only a scope weapon opts into vanishing")
	# CONTROL: the same weapon authored as a scope weapon does vanish while aiming, so the answer above read the flag.
	gun.disable_dof_while_scoped = true
	assert_false(GunMesh.view_model_visible_now(true, true, gun),
		"control: aiming a weapon authored with disable_dof_while_scoped must hide its view model")
	gun = null


# ---------------------------------------------------------------------------
# WeaponData — removed fields stay removed.
# ---------------------------------------------------------------------------

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
# spray_paint.tres — load-bearing resource wiring. It must actually opt into graffiti mode and keep a usable
# colour cycle.
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
# ThrowableData — what a prop inherits (Resource, no _init/_ready/autoload). Old props authored before a field existed,
# and props that simply leave it unset, inherit these, so each one is the "old props keep working" promise.
# ---------------------------------------------------------------------------

func test_a_prop_whose_data_authors_nothing_behaves_like_a_prop_with_no_data() -> void:
	# wooden_crate.tres authors none of these fields, so a crate is exactly this case. The expectation is the SAME
	# Throwable's answer before it carries any data - its look-at prompt and its carry pose, read through the
	# resolvers the prompt, PickupRay's carry and Throwable's own carry fade / face_carrier really call - never a
	# literal copied off the declarations.
	var prop := Throwable.new()
	var bare_prompt := prop.look_name()
	var bare_fades := prop.fades_while_held()
	var bare_faces := prop.faces_carrier_while_held()
	var bare_offset := prop._face_carrier_offset_radians()
	prop.data = ThrowableData.new()
	assert_eq(prop.look_name(), bare_prompt,
		"a prop whose data names nothing must keep the generic Pick Up prompt of an unnamed prop, not pick up a name from the data template")
	assert_eq(prop.fades_while_held(), bare_fades,
		"a prop whose data authors no fade_while_held must keep the see-through carry of a prop with no data")
	assert_eq(prop.faces_carrier_while_held(), bare_faces,
		"a prop whose data authors no face_carrier_while_held must keep its own physics rotation while carried")
	assert_eq(prop._face_carrier_offset_radians(), bare_offset,
		"a prop whose data authors no face_carrier_rotation_degrees must add no mesh-front correction to the carry pose")
	# CONTROL: data that DOES author each field changes each answer, so every comparison above really read the data.
	var authored := ThrowableData.new()
	authored.display_name = "Crate"
	authored.fade_while_held = not bare_fades
	authored.face_carrier_while_held = not bare_faces
	authored.face_carrier_rotation_degrees = Vector3(0.0, 90.0, 0.0)
	prop.data = authored
	assert_ne(prop.look_name(), bare_prompt, "control: a prop whose data authors a display_name must be named by it")
	assert_ne(prop.fades_while_held(), bare_fades, "control: a prop whose data authors fade_while_held must follow it")
	assert_ne(prop.faces_carrier_while_held(), bare_faces,
		"control: a prop whose data authors face_carrier_while_held must follow it")
	assert_ne(prop._face_carrier_offset_radians(), bare_offset,
		"control: a prop whose data authors face_carrier_rotation_degrees must carry that correction")
	prop.free()


func test_throwable_data_mesh_accepts_scene_or_mesh() -> void:
	var d := ThrowableData.new()
	var prop := _property(d, "mesh")
	assert_false(prop.is_empty(), "ThrowableData exposes mesh as the prop's model slot")
	assert_eq(prop.get("hint", -1), PROPERTY_HINT_RESOURCE_TYPE,
		"ThrowableData.mesh uses a resource-type hint")
	var accepted: Array[String] = []
	for t in String(prop.get("hint_string", "")).split(","):
		accepted.append(t.strip_edges())
	assert_true(accepted.has("PackedScene"),
		"ThrowableData.mesh must accept a PackedScene — that is what a .glb/.gltf/.blend model imports as (hint_string %s)" % [accepted])
	assert_true(accepted.has("Mesh"),
		"ThrowableData.mesh must accept a Mesh — that is what an .obj model imports as (hint_string %s)" % [accepted])
	d = null


func test_throwable_data_living_motion_defaults() -> void:
	var d := ThrowableData.new()
	assert_false(d.breathe,
		"Default breathe is false so crates and old props stay visually static.")
	assert_gt(d.breathe_amount, 0.0,
		"a prop that ticks breathe on and keeps the inherited amount must visibly pulse — a 0 default would make the toggle do nothing")
	var torso := BodyModelSwap.new()
	assert_almost_eq(d.breathe_rate, torso.breathe_rate, 0.0001,
		"a living prop's default breathing cadence is the same calm idle cadence an NPC torso (BodyModelSwap) breathes at")
	torso.free()
	d = null


const THROWABLE_PREFAB := "res://scenes/components/throwable.tscn"


## Runs the prop's own destroy-decal spawn once and returns how many Decals that call added anywhere in the tree,
## freeing them BEFORE the caller asserts so a failing assert never leaks a decal into the next test. Diffing every
## Decal in the tree (not just the root's children) keeps the count honest wherever WorldSpawn parents the spawn.
func _decals_spawned_by_destroy_decal(prop: Throwable) -> int:
	var root := get_tree().root
	var before := root.find_children("*", "Decal", true, false)
	prop._spawn_destroy_decal()
	var spawned := 0
	for decal in root.find_children("*", "Decal", true, false):
		if before.has(decal):
			continue
		spawned += 1
		decal.get_parent().remove_child(decal)
		decal.free()
	return spawned


# A SHIP DECISION, not a tuning literal: wooden_crate.tres authors no spawns_destroy_decal, so what a data resource that
# leaves the field unset does is what a smashed crate does - it leaves a scorch decal where it broke. gore_gib_data.tres
# is the one prop that authors it off (Throwable: gibs bleed instead). Driven through the flag's only reader,
# Throwable._spawn_destroy_decal, on the tests/test_throwable_destructible.gd harness: the shared prefab frozen at the
# origin over a floor slab, given two physics frames so the slab is in the space the floor probe queries. No mutation
# target is git-clean for it here (throwable_data.gd and Throwable.gd both carry other sessions' work).
func test_a_smashed_prop_whose_data_authors_no_decal_opt_out_scorches_the_floor_it_broke_on() -> void:
	var floor_slab := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(8.0, 1.0, 8.0)
	floor_shape.shape = floor_box
	floor_slab.add_child(floor_shape)
	add_child_autofree(floor_slab)
	floor_slab.global_position = Vector3(0.0, -1.5, 0.0)  # top face at y = -1.0, below the prop and inside the floor probe's reach
	var prop: Throwable = load(THROWABLE_PREFAB).instantiate()
	prop.freeze = true
	prop.gravity_scale = 0.0
	add_child_autofree(prop)
	prop.global_position = Vector3.ZERO
	await wait_physics_frames(2)
	assert_true(prop.data == null, "precondition: the shared prefab carries no ThrowableData, so the first break below is the no-data baseline")
	var bare := _decals_spawned_by_destroy_decal(prop)
	prop.data = ThrowableData.new()
	var unauthored := _decals_spawned_by_destroy_decal(prop)
	var opted_out := ThrowableData.new()
	opted_out.spawns_destroy_decal = false
	prop.data = opted_out
	var gib_like := _decals_spawned_by_destroy_decal(prop)
	assert_eq(bare, 1,
		"precondition: a prop with no data that breaks over a floor leaves exactly one scorch decal (the floor probe finds the slab)")
	assert_eq(unauthored, bare,
		"SHIP DECISION: a destroyed prop whose data authors no spawns_destroy_decal (wooden_crate.tres) leaves the same scorch/blast decal where it broke as a prop with no data; only gore gibs (gore_gib_data.tres) author it off")
	assert_eq(gib_like, 0,
		"control: the same prop over the same floor, with data that authors spawns_destroy_decal off (as gore_gib_data.tres does), leaves no decal")


# ---------------------------------------------------------------------------
# Inventory — the equipped_weapon STATE equip() leaves behind. The signal emit / no-op behaviour is already covered
# by test_smoke.gd, so only the resulting source-of-truth value is asserted here.
# ---------------------------------------------------------------------------

func test_inventory_equip_updates_equipped_weapon_state() -> void:
	# add_child_autofree is safe here (Inventory has no _ready), mirroring the proven smoke-test setup.
	var inv := Inventory.new()
	add_child_autofree(inv)
	assert_true(inv.equipped_weapon == null,
		"A fresh Inventory holds no weapon until one is authored or equipped — the rig must not assume one exists")
	inv.equip(PISTOL)
	assert_eq(inv.equipped_weapon, PISTOL,
		"equip() from empty hands must make the handed-in weapon the equipped one")
	inv.equip(SHOTGUN)
	assert_eq(inv.equipped_weapon, SHOTGUN,
		"Equipping a different weapon must replace it — equipped_weapon is the single source of truth every listener reads")


# ---------------------------------------------------------------------------
# Ammo — pure clip math via Ammo.new() WITHOUT add_child. Ammo._ready connects to (and reads) its unset
# `inventory`, which would null-deref and crash the runner, so we never add it to the tree; consume_ammo() touches
# no node refs.
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


func test_ammo_background_reload_tracks_and_clears_per_weapon() -> void:
	# Swapping away mid-reload hands THAT gun a slower background top-up while you fight with another, so the
	# bookkeeping is per weapon: two stowed guns can top up at once, a gun that never started one is not reloading,
	# and foreground-reloading one of them (which cancels its top-up) must leave the other's running.
	var a := Ammo.new()
	var stowed := WeaponData.new()
	var other := WeaponData.new()
	assert_false(a.is_background_reloading(stowed),
		"a weapon isn't background-reloading until one is started")
	a.start_background_reload(stowed, 2.0)
	assert_true(a.is_background_reloading(stowed),
		"start_background_reload registers the outgoing weapon as topping up in the background")
	assert_false(a.is_background_reloading(other),
		"only the weapon handed a background reload is topping up - a gun that never started one must not read as reloading")
	a.start_background_reload(other, 1.0)
	a.cancel_background_reload(other)
	assert_false(a.is_background_reloading(other),
		"cancel_background_reload drops that weapon's top-up (e.g. when the player foreground-reloads that gun)")
	assert_true(a.is_background_reloading(stowed),
		"cancelling one weapon's top-up must leave the other stowed gun still topping up")
	a.cancel_background_reload(stowed)
	assert_false(a.is_background_reloading(stowed),
		"cancelling the remaining weapon's top-up drops it too")
	a.free()


# ---------------------------------------------------------------------------
# Reload — the input adapter's pure payload. Reload extends Node3D with an _unhandled_input that the ENGINE only
# calls on real input, so calling reload_weapon() directly (without add_child) exercises the logic safely.
# ---------------------------------------------------------------------------

func test_reload_weapon_emits_reload_signal() -> void:
	var r := Reload.new()
	watch_signals(r)
	r.reload_weapon()
	assert_signal_emitted(r, "reload",
		"reload_weapon() must emit `reload` so attack.gd can decide whether a reload is allowed")
	r.free()
