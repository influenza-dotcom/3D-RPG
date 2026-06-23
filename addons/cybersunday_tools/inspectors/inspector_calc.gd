extends RefCounted

## Pure compute backing the VALIDATION INSPECTORS (weapon / GOAP profile / perk cards). NO EditorInterface,
## NO scene tree, NO node lifecycle — every function here is a static that takes a resource (or plain values)
## and returns Strings / PackedStringArrays the thin inspector cards render verbatim. This is the ONLY part
## that's unit-tested headless (the cards themselves need a live editor and are user-verified).
##
## NO class_name on purpose — const-preloaded by each inspector card (mirrors Calibers / Factions / GoapLibrary),
## so there's nothing for the global script class cache to miss.

## The HP anchors the weapon math reports against (Character.max_hp default = player, NpcData.max_hp default = NPC).
## Kept as named consts so a card reads "vs 4 HP / 10 HP" without re-deriving them, and the test can pin them.
const PLAYER_HP := 4.0
const NPC_HP := 10.0

# ──────────────────────────────────────────────────────────────────────────────────────────────────────────
# WeaponData — derived combat readout + amber warnings
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────

## Per-shot damage for ONE pellet at a given multiplier stack (headshot / sneak / both), times pellet_count for
## a full trigger pull. `mult` is the product of the multipliers in play (1.0 = body shot).
static func burst_damage(wd: WeaponData, mult: float) -> float:
	if wd == null:
		return 0.0
	var pellets := maxf(float(wd.pellet_count), 1.0)
	return wd.damage * pellets * maxf(mult, 0.0)


## Shots (trigger pulls) needed to drop `hp` at the given multiplier — ceil of hp / burst, min 1. Returns a big
## sentinel (9999) when the gun deals no damage, so the card shows "never" rather than dividing by zero.
static func shots_to_kill(wd: WeaponData, hp: float, mult: float) -> int:
	var per := burst_damage(wd, mult)
	if per <= 0.0:
		return 9999
	return int(ceil(hp / per))


## Cooldown between shots (seconds): the weapon's attack_speed is the fire-rate timer, plus its wind-up. Floored
## so a 0 attack_speed (instant) still reads as a tiny positive cadence for the time math.
static func shot_interval(wd: WeaponData) -> float:
	if wd == null:
		return 0.0
	return maxf(wd.attack_speed, 0.0) + maxf(wd.attack_windup, 0.0)


## Damage per second at a sustained body-shot cadence (ignores reload — that's the sustain line). burst over the
## per-shot interval. 0 cadence -> treat the whole burst as instant DPS via a tiny epsilon.
static func dps(wd: WeaponData) -> float:
	if wd == null:
		return 0.0
	return burst_damage(wd, 1.0) / maxf(shot_interval(wd), 0.001)


## Seconds to kill `hp` at `mult`: (shots-1) intervals between shots (the first shot is at t=0). Returns -1.0 when
## the gun can never kill (no damage), so the card shows "never".
static func time_to_kill(wd: WeaponData, hp: float, mult: float) -> float:
	var s := shots_to_kill(wd, hp, mult)
	if s >= 9999:
		return -1.0
	return float(s - 1) * shot_interval(wd)


## Multiplier stacks the card reports (label -> product), built from the weapon's own multipliers. Headshot,
## sneak, and a stealth-headshot (sneak × headshot, the way ShotResolver stacks them).
static func mult_for(wd: WeaponData, kind: String) -> float:
	if wd == null:
		return 1.0
	match kind:
		"body": return 1.0
		"headshot": return wd.headshot_multiplier
		"sneak": return wd.sneak_attack_multiplier
		"stealth_headshot": return wd.headshot_multiplier * wd.sneak_attack_multiplier
	return 1.0


## The full derived readout (DPS, burst, STK/TTK vs player & NPC for each multiplier, clip sustain, recoil line)
## as display lines. Pure -> the test asserts the numbers; the card just joins them.
static func weapon_lines(wd: WeaponData) -> PackedStringArray:
	var out := PackedStringArray()
	if wd == null:
		return out
	out.append("DPS %.1f   burst %.1f (dmg %.1f × %d pellet%s)" % [
		dps(wd), burst_damage(wd, 1.0), wd.damage, wd.pellet_count, "" if wd.pellet_count == 1 else "s",
	])
	var kinds := [["body", "body"], ["headshot", "head"], ["sneak", "sneak"], ["stealth_headshot", "stealth-head"]]
	for pair in kinds:
		var m: float = mult_for(wd, pair[0])
		out.append("  %s ×%.2f → player %s / %s   NPC %s / %s" % [
			pair[1], m,
			_stk_label(wd, PLAYER_HP, m), _ttk_label(wd, PLAYER_HP, m),
			_stk_label(wd, NPC_HP, m), _ttk_label(wd, NPC_HP, m),
		])
	out.append("clip %d, reload %.1fs → ~%.1f dmg/clip, %.1f dmg/s sustained (with reload)" % [
		wd.max_ammo, wd.reload_time, _clip_damage(wd), _sustain_dps(wd),
	])
	out.append(_recoil_line(wd))
	return out


static func _stk_label(wd: WeaponData, hp: float, mult: float) -> String:
	var s := shots_to_kill(wd, hp, mult)
	return "never" if s >= 9999 else "%d shot%s" % [s, "" if s == 1 else "s"]


static func _ttk_label(wd: WeaponData, hp: float, mult: float) -> String:
	var t := time_to_kill(wd, hp, mult)
	return "—" if t < 0.0 else "%.2fs" % t


## Total damage a full clip can deal (body shots), max_ammo trigger pulls × burst. is_infinite_ammo -> 0 clips
## conceptually, so report a single burst's worth as "unbounded" via the sustain line instead.
static func _clip_damage(wd: WeaponData) -> float:
	return burst_damage(wd, 1.0) * maxf(float(wd.max_ammo), 0.0)


## Sustained DPS that AMORTISES the reload: a clip's worth of damage spread over (firing time + one reload).
static func _sustain_dps(wd: WeaponData) -> float:
	if wd.is_infinite_ammo or wd.max_ammo <= 0:
		return dps(wd)
	var firing := float(wd.max_ammo) * shot_interval(wd)
	var window := firing + maxf(wd.reload_time, 0.0)
	if window <= 0.0:
		return dps(wd)
	return _clip_damage(wd) / window


static func _recoil_line(wd: WeaponData) -> String:
	return "recoil: kick %.1f°/shot (recover %.1f°/s), bloom %.2f°/shot → max %.2f°" % [
		wd.recoil_kick_deg, wd.recoil_recovery, wd.bloom_per_shot_deg, wd.bloom_max_deg,
	]


## Amber authoring warnings for a WeaponData (pure -> unit-tested). Each is a knob that's been half-configured
## so it silently no-ops in play. `known_calibers` is the set of ammo calibers on disk (Calibers.ids()) — passed
## in so the static stays scene-tree-free and the test can feed a fixed list.
static func weapon_warnings(wd: WeaponData, known_calibers: PackedStringArray) -> PackedStringArray:
	var w := PackedStringArray()
	if wd == null:
		return w
	if wd.pellet_count > 1 and wd.pellet_spread <= 0.0:
		w.append("pellet_count %d but pellet_spread is 0 — every pellet lands on the same point (no shotgun cone)." % wd.pellet_count)
	if wd.recoil_kick_deg > 0.0 and wd.recoil_recovery <= 0.0:
		w.append("recoil_kick_deg is set but recoil_recovery is 0 — the kick never recovers, the aim climbs forever.")
	if wd.bloom_per_shot_deg > 0.0 and wd.bloom_max_deg <= 0.0:
		w.append("bloom_per_shot_deg is set but bloom_max_deg is 0 — bloom is capped at 0, so it never widens (inert).")
	# (no explosion_radius/projectile_scene warning: explosion_radius DEFAULTS to 4.0 on every WeaponData, so it
	# would false-positive on every hitscan gun — there's no reliable signal to tell designer intent from the default.)
	var cal := String(wd.caliber)
	if cal != "" and not known_calibers.has(cal):
		w.append("caliber '%s' matches no ammo Item on disk — this weapon could never reload." % cal)
	if wd.is_infinite_ammo and cal != "":
		w.append("is_infinite_ammo is on but caliber '%s' is set — the caliber/reserve is ignored (the clip never depletes)." % cal)
	return w


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────
# GoapProfile — resolved priority/cost table
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────

## The resolved per-goal priority table (one line per known goal, base 0.0 fallback so an unset goal reads its
## fallback). Uses GoapProfile.priority_for so the card shows exactly what the planner would resolve.
static func goap_priority_lines(gp: GoapProfile, goal_names: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	if gp == null:
		return out
	for g in goal_names:
		out.append("  priority[%s] = %.2f" % [g, gp.priority_for(StringName(g), 0.0)])
	return out


## The resolved per-action cost table (one line per known action), via GoapProfile.cost_for with a 1.0 fallback
## (the planner's neutral cost) so an un-overridden action reads its default.
static func goap_cost_lines(gp: GoapProfile, action_names: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	if gp == null:
		return out
	for a in action_names:
		out.append("  cost[%s] = %.2f" % [a, gp.cost_for(StringName(a), 1.0)])
	return out


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────
# Perk — bad-key + dangling-prereq warnings
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────

## The combat_bonuses keys the damage seam actually reads (PerkManager.combat_bonus). Anything else is inert.
const PERK_COMBAT_KEYS := ["damage", "crit"]

## Amber authoring warnings for a Perk (pure -> unit-tested). Replicates Perk.validate's stat-key check AND adds
## the combat_bonuses-key + dangling-prerequisite checks the inspector wants. `known_stats` = CharacterStats
## .stat_names(); `known_perk_ids` = the perk ids found on disk (the card scans resources/perks/, may be EMPTY
## when the folder is absent — then the prereq check is SKIPPED so a lone perk doesn't false-alarm).
static func perk_warnings(perk: Perk, known_stats: PackedStringArray, known_perk_ids: PackedStringArray, perks_folder_present: bool) -> PackedStringArray:
	var w := PackedStringArray()
	if perk == null:
		return w
	for key in perk.stat_bonuses:
		if not known_stats.has(String(key)):
			w.append("stat_bonuses key '%s' is not a CharacterStats attribute — it will be ignored." % String(key))
	for key in perk.combat_bonuses:
		if not PERK_COMBAT_KEYS.has(String(key)):
			w.append("combat_bonuses key '%s' is outside {damage, crit} — no seam reads it (inert)." % String(key))
	if perks_folder_present:
		for req in perk.requires_perks:
			if not known_perk_ids.has(String(req)):
				w.append("requires_perks '%s' names no Perk .tres on disk — this prerequisite can never be met." % String(req))
	return w
