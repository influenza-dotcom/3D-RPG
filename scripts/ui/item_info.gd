class_name ItemInfo
extends RefCounted

## Hover breakdown for an inventory Item — what it is AND what it DOES, derived from the item's structured fields.
## Pure formatter; reads Item / WeaponData / StatusEffect data and the holder's spare ammo. Fed into the
## inventory / shop / loot / chip-install tooltips so hovering ANY item communicates its function: a weapon's combat
## line (+ melee / laser / move-speed / on-hit), a consumable's heal + applied effect, ammo's caliber, a carried
## trinket's passive buff, a chip's installed ability, and a prop's hold/throw. Item `description`s ship blank (the
## Steam AI-text scrub — no authored prose), so these GENERATED, purely-mechanical lines are what speak. Functional
## labels, unmarked — the "labeled language" the retired ItemRow row formatter once shared with this composer.
## ⭐NO MIDDLE DOTS, NO BRACKETED ASIDES (2026-09-17). Stats sit in columns three spaces apart (WeaponModInfo.JOIN)
## and a clause's own sub-parts join with commas; "(2 spare)", "On hit (50%)", a raw caliber id and
## the dotted hold/throw line were the machine-formatted tells the menus had already been cleaned of.
## LOCALIZATION NOTE: the composer still joins English-shaped fragments (column gaps, labeled parts) — a recorded
## deferred gap (CURRENT_ARCHITECTURE → Localization Readiness) pending a target language. What IS wired: numbers
## through TextFormat.num, money through Zorkmids.money_text, ability names through AbilityRegistry.

## Canonical ability-name accessor (path-preloaded, no class_name — same idiom as item.gd).
const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")

## A multi-line tooltip for `item`. `holder` (the bag the row belongs to) adds a weapon's spare-ammo readout; null skips it.
## `show_value` false drops the list value from the weight line — the shop, whose price line quotes the real deal.
static func tooltip(item: Item, holder: CharacterInventory = null, show_value: bool = true) -> String:
	if item == null:
		return ""
	var lines: Array[String] = [item.label()]
	if not item.description.is_empty():
		lines.append(item.description)
	if item.is_weapon() and item.weapon != null:
		lines.append(_weapon_block(item.weapon, holder))
	elif item.is_consumable() and item.heal_amount > 0.0:
		lines.append("Heals %s HP" % _num(item.heal_amount))
	# (No ammo line: the ammo item's own name — "Pistol Clip" — already says which guns it feeds, and the old
	# old ammo line printed the raw caliber id beside it.)
	# EFFECT block — WHAT THE ITEM DOES, derived from its structured fields (installs_ability / held_passive_effect /
	# consumable_effect). Item `description`s ship EMPTY (the Steam AI-text scrub: no authored prose), so for a trinket
	# like the Chrome Grin these generated, purely-mechanical stat lines are the ONLY thing telling the player it grants
	# "+3 Streetwise while carried". Empty for a plain weapon/ammo/junk item, so their tooltips are unchanged.
	lines.append_array(_effect_lines(item))
	var foot: String = "Weight %s" % _num(item.weight)
	if show_value and item.value > 0.0:
		foot += WeaponModInfo.JOIN + Zorkmids.money_text(item.value)  # the whole money phrase — the "zm" word lives in Zorkmids.MONEY_TEMPLATE, never here
	lines.append(foot)
	return "\n".join(lines)

## The weapon's combat one-liner: damage (× pellets), fire rate, range, headshot, ammo/clip.
static func _weapon_block(w: WeaponData, holder: CharacterInventory) -> String:
	var parts: Array[String] = []
	# A paint sprayer deals NO damage (attack.gd short-circuits to `_do_spray_paint` before the damage path), so its
	# Damage / Headshot combat readouts describe behaviour that never happens — suppress them and label the real
	# function, exactly as the melee branch does. Otherwise the tooltip frames a graffiti tool as a headshot weapon.
	if not w.is_spray_paint:
		var dmg: String = "Damage %s" % _num(w.damage)
		if w.pellet_count > 1:
			dmg += " ×%d" % w.pellet_count
		parts.append(dmg)
	# Kind tag: the weapon's defining, non-obvious mode. Guns need none; melee and paint-sprayer both do.
	if w.is_spray_paint:
		parts.append("Sprays paint")
	elif w.is_melee:
		parts.append("Melee")
	parts.append("Rate %s/s" % _num(1.0 / maxf(w.attack_speed, 0.01)))
	if w.effective_range > 0.0:
		parts.append("Range %s m" % _num(w.effective_range))
	if not w.is_spray_paint:
		parts.append("Headshot ×%s" % _num(w.headshot_multiplier))
	# Ammo readout — SKIPPED for melee AND spray (neither fires a real clip, so "Ammo ∞" / "Clip N" would mislead).
	if not w.is_melee and not w.is_spray_paint:
		if w.is_infinite_ammo:
			parts.append("Ammo ∞")
		elif w.caliber != &"":
			parts.append("Clip %d" % w.max_ammo)
			# The rounds of this caliber in the bag the row belongs to, as its own column. Not the caliber id: the
			# ammo is named on its own item ("Pistol Clip"), and the id is an internal key, never display text.
			if holder != null:
				parts.append("Reserve %d" % holder.ammo_count(w.caliber))
		elif w.max_ammo > 0:
			parts.append("Clip %d" % w.max_ammo)  # a real self-contained clip; max_ammo 0 (spray paint) has none to show
	# (No laser-sight tag on purpose: WeaponData.has_laser_sight is a cosmetic "render the beam" flag that DEFAULTS TRUE
	# and is left unset on most guns — even the rock — so surfacing it would be noise/nonsense, not a real capability.
	# It says "a laser CAN hang off this", not "this weapon has one": whether a dot actually appears is the
	# `laser_sight` IMPLANT's call, so a per-weapon tooltip is the wrong place to claim it either way.)
	# Weight class you FEEL: a heavy weapon slows you while wielded, a light one can speed you up (move_speed_multiplier
	# is applied by the equip). Rounded so a ≈1.0 that isn't exactly 1.0 stays silent.
	var move_pct := roundi((w.move_speed_multiplier - 1.0) * 100.0)
	if move_pct != 0:
		parts.append("Move %s" % _signed_pct(move_pct))
	# A weapon that inflicts a StatusEffect on hit (poison / burn rounds, a slowing tag) — summarised like a consumable.
	# The chance LEADS the label ("50% on hit:") rather than riding in brackets, and the clause's sub-parts join with
	# COMMAS (not the column gap) so it stays visually scoped instead of dissolving into the top-level weapon stats.
	if w.on_hit_effect != null:
		var clause := _timed_clause(w.on_hit_effect)
		if not clause.is_empty():
			var lead := "On hit"
			if w.on_hit_chance < 1.0:
				lead = "%d%% on hit" % roundi(w.on_hit_chance * 100.0)
			parts.append("%s: %s" % [lead, clause])
	return WeaponModInfo.JOIN.join(parts)

## The data-derived "what it does" lines: an upgrade chip's installed ability, a carried item's passive buff, and a
## consumable's applied effect — each generated from the item's STRUCTURED fields, never from authored prose, so a
## scrubbed-blank `description` still communicates the mechanics. Returns [] for a plain item (none of these fields
## set), leaving the tooltip exactly as before.
static func _effect_lines(item: Item) -> Array[String]:
	var out: Array[String] = []
	# Upgrade chip: carrying it does nothing until a ChipInstaller consumes it, so name the ability it unlocks.
	if item.is_upgrade_chip():
		out.append("Installs %s" % _ability_name(item.installs_ability))
	# A WEAPON PART: carrying it does nothing until a WeaponBench fits it, so name the slot and what it does.
	# ONE branch feeds the inventory, shop, loot AND bench tooltips at once — the bench's rows are ItemInfo
	# tooltips, so this is also the decision surface for the fit itself. Composed by WeaponModInfo (the
	# ItemInfo._weapon_block precedent: a labeled, derived readout belongs in a formatter, not in PlayerText).
	if item.is_weapon_mod():
		out.append(WeaponModInfo.part_line(item))
	# Passive held buff (the Chrome Grin case): the effect is live WHILE the item sits in the bag.
	if item.held_passive_effect != null:
		var parts := _held_effect_parts(item.held_passive_effect)
		if not parts.is_empty():
			# The stacking rule only matters when you could actually hold more than one copy.
			if item.max_stack > 1:
				parts.append("doesn't stack" if item.passive_unique else "stacks")
			out.append("While carried: " + ", ".join(parts))
	# Consumable's applied StatusEffect (a stim / buff / poison) — shown ALONGSIDE any "Heals N HP" line above.
	if item.consumable_effect != null:
		var clause := _timed_clause(item.consumable_effect)
		if not clause.is_empty():
			out.append("When used: " + clause)
	# A holdable prop (the dog crate, any world_prop / world_model item that isn't a weapon/consumable/ammo/chip/coin)
	# can be pulled into the hands from the hotbar and thrown — otherwise its tooltip is just a name, saying nothing
	# about the one thing you can DO with it. is_holdable() already encodes all those exclusions.
	if item.is_holdable():
		out.append("Can be held and thrown")
	return out

## A carried item's passive buff (Item.held_passive_effect) as labeled parts. Mirrors PassiveItemBuffs' fold EXACTLY:
## a held STRENGTH modifier is NOT a live stat — it re-stamps into Max HP + Carry (and, unlike the strength STAT, never
## melee) via the SAME CharacterStats per-point consts — so it is shown as those concrete resources rather than
## "+N Strength" (which would wrongly imply a melee boost). Every OTHER stat is a live modifier shown raw as
## "+N <StatTitle>"; speed_multiplier becomes a signed move-speed %. duration / tick / damage are ignored here (the
## held path treats the StatusEffect as a pure stat payload — author duration = 0).
static func _held_effect_parts(fx: StatusEffect) -> Array[String]:
	var parts: Array[String] = []
	var mods: Dictionary = fx.stat_modifiers
	# STRENGTH first (its spawn-stamped HP + carry), so the concrete-resource lines lead. HP_PER_STRENGTH /
	# CARRY_PER_STRENGTH are the very consts PassiveItemBuffs._restamp applies, so this can't drift from what the
	# carrier actually gains. (mule_rig's "+3 strength" is really +4.5 Max HP AND +6 Carry — the tooltip shows both.)
	if mods.has("strength"):
		var s := float(mods["strength"])
		var hp := s * CharacterStats.HP_PER_STRENGTH
		var carry := s * CharacterStats.CARRY_PER_STRENGTH
		if not is_zero_approx(hp):
			parts.append("%s Max HP" % _signed(hp))
		if not is_zero_approx(carry):
			parts.append("%s Carry" % _signed(carry))
	# The live-stat modifiers, walked in the master STAT_NAMES order so the readout is deterministic regardless of the
	# .tres authoring order. Keys are Strings (as authored + as PassiveItemBuffs reads them).
	for stat in CharacterStats.STAT_NAMES:
		var key := String(stat)
		if key == "strength" or not mods.has(key):
			continue
		var n := float(mods[key])
		if not is_zero_approx(n):
			parts.append("%s %s" % [_signed(n), StatInfo.title(stat)])
	# Any non-standard stat key a designer authored (outside STAT_NAMES) — appended after so nothing is silently dropped.
	for k in mods:
		var key := String(k)
		if key == "strength" or CharacterStats.STAT_NAMES.has(StringName(key)):
			continue
		var n := float(mods[k])
		if not is_zero_approx(n):
			parts.append("%s %s" % [_signed(n), StatInfo.title(StringName(key))])
	# Gate on the ROUNDED percent, not the raw multiplier: a value like 1.003 clears is_equal_approx(…, 1.0) yet rounds
	# to 0%, and we must not emit a meaningless "0% Move Speed" part for it.
	var speed_pct := roundi((fx.speed_multiplier - 1.0) * 100.0)
	if speed_pct != 0:
		parts.append("%s Move Speed" % _signed_pct(speed_pct))
	return parts

## One timed effect as a comma-joined clause with its duration trailing as prose: "+2 Agility, +25% Move Speed for 8 s".
## "" when the effect moves nothing (a duration alone is not an effect worth a line).
static func _timed_clause(fx: StatusEffect) -> String:
	var parts := _timed_effect_parts(fx)
	if parts.is_empty():
		return ""
	var clause := ", ".join(parts)
	if fx.duration > 0.0:
		clause += " for %s s" % _num(fx.duration)
	return clause

## A consumable's applied StatusEffect (Item.consumable_effect) as labeled parts — the TIMED path, so unlike a held
## buff it reads periodic damage (the duration is _timed_clause's trailing "for N s"), and strength IS shown raw (a timed strength buff DOES fold into melee, so
## it behaves like the stat). Poison / burn (positive damage_per_tick over tick_interval) reads as damage-per-second.
static func _timed_effect_parts(fx: StatusEffect) -> Array[String]:
	var parts: Array[String] = []
	var mods: Dictionary = fx.stat_modifiers
	for stat in CharacterStats.STAT_NAMES:
		var key := String(stat)
		if not mods.has(key):
			continue
		var n := float(mods[key])
		if not is_zero_approx(n):
			parts.append("%s %s" % [_signed(n), StatInfo.title(stat)])
	# Gate on the ROUNDED percent, not the raw multiplier: a value like 1.003 clears is_equal_approx(…, 1.0) yet rounds
	# to 0%, and we must not emit a meaningless "0% Move Speed" part for it.
	var speed_pct := roundi((fx.speed_multiplier - 1.0) * 100.0)
	if speed_pct != 0:
		parts.append("%s Move Speed" % _signed_pct(speed_pct))
	if fx.damage_per_tick > 0.0 and fx.tick_interval > 0.0:
		parts.append("%s HP/s damage" % _num(fx.damage_per_tick / fx.tick_interval))
	return parts

## The player-facing name for an installs_ability mechanic id — routed through AbilityRegistry.display_name_for,
## THE canonical accessor: the authored Ability.display_name on the ability scene's root wins, and a blank/missing
## name degrades to the old capitalized-id look ("wall_climb" -> "Wall Climb"), never a blank. A functional label
## like the stat titles, so it carries no [PH] marker.
static func _ability_name(id: StringName) -> String:
	return AbilityRegistry.display_name_for(id)

## A SIGNED bare/half number: "+3", "-2", "+4.5". TextFormat.signed at one decimal in the TERSE voice
## (zero_plus = false, so a baseline would print a bare "0" rather than StatInfo's "+0") — this file's private
## copy of the idiom is gone. Byte-identical to it: callers skip zeros (is_zero_approx), so 0 never reaches here.
static func _signed(x: float) -> String:
	return TextFormat.signed(x, 1, false)

## A SIGNED integer percentage: "+10%", "-25%". TextFormat.signed_pct in the TERSE voice — callers skip a
## rounded 0 (`speed_pct != 0`), so the "0%" baseline branch is unreachable from here.
static func _signed_pct(p: int) -> String:
	return TextFormat.signed_pct(p, false)

## Trim a float to a bare/half readout ("4" / "4.5") — TextFormat.num at one decimal, the single copy of the trim
## idiom (this file's private duplicate is gone). Byte-identical to the old copy except TextFormat's "-0" guard:
## a negative that rounds to zero now prints "0", not "-0" (unreachable in practice — _signed callers skip zeros).
static func _num(x: float) -> String:
	return TextFormat.num(x, 1)
