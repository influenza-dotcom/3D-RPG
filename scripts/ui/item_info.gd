class_name ItemInfo
extends RefCounted

## Hover breakdown for an inventory Item — what it is AND what it DOES, derived from the item's structured fields.
## Pure formatter; reads Item / WeaponData / StatusEffect data and the holder's spare ammo. Fed into the
## inventory / shop / loot / chip-install tooltips so hovering ANY item communicates its function: a weapon's combat
## line (+ melee / laser / move-speed / on-hit), a consumable's heal + applied effect, ammo's caliber, a carried
## trinket's passive buff, a chip's installed ability, and a prop's hold/throw. Item `description`s ship blank (the
## Steam AI-text scrub — no authored prose), so these GENERATED, purely-mechanical lines are what speak. Mirrors
## ItemRow's "labeled language" (functional labels, unmarked) so the two never drift.
## LOCALIZATION NOTE: the composer still joins English-shaped fragments ("  ·  ", labeled parts) — a recorded
## deferred gap (CURRENT_ARCHITECTURE → Localization Readiness) pending a target language. What IS wired: numbers
## through TextFormat.num, money through Zorkmids.money_text, ability names through AbilityRegistry.

## Canonical ability-name accessor (path-preloaded, no class_name — same idiom as item.gd).
const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")

## A multi-line tooltip for `item`. `holder` (the bag the row belongs to) adds a weapon's spare-ammo readout; null skips it.
static func tooltip(item: Item, holder: CharacterInventory = null) -> String:
	if item == null:
		return ""
	var lines: Array[String] = [item.label()]
	if not item.description.is_empty():
		lines.append(item.description)
	if item.is_weapon() and item.weapon != null:
		lines.append(_weapon_block(item.weapon, holder))
	elif item.is_consumable() and item.heal_amount > 0.0:
		lines.append("Heals %s HP" % _num(item.heal_amount))
	elif item.is_ammo():
		lines.append("Ammo · %s" % item.caliber)
	# EFFECT block — WHAT THE ITEM DOES, derived from its structured fields (installs_ability / held_passive_effect /
	# consumable_effect). Item `description`s ship EMPTY (the Steam AI-text scrub: no authored prose), so for a trinket
	# like the Chrome Grin these generated, purely-mechanical stat lines are the ONLY thing telling the player it grants
	# "+3 Streetwise while carried". Empty for a plain weapon/ammo/junk item, so their tooltips are unchanged.
	lines.append_array(_effect_lines(item))
	var foot: String = "Weight %s" % _num(item.weight)
	if item.value > 0.0:
		foot += "  ·  %s" % Zorkmids.money_text(item.value)  # the whole money phrase — the "zm" word lives in Zorkmids.MONEY_TEMPLATE, never here
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
			var reserve: String = ""
			if holder != null:
				reserve = " (%d spare)" % holder.ammo_count(w.caliber)
			parts.append("%s · clip %d%s" % [w.caliber, w.max_ammo, reserve])
		elif w.max_ammo > 0:
			parts.append("Clip %d" % w.max_ammo)  # a real self-contained clip; max_ammo 0 (spray paint) has none to show
	# (No laser-sight tag on purpose: WeaponData.has_laser_sight is a cosmetic "render the beam" flag that DEFAULTS TRUE
	# and is left unset on most guns — even the rock — so surfacing it would be noise/nonsense, not a real capability.)
	# Weight class you FEEL: a heavy weapon slows you while wielded, a light one can speed you up (move_speed_multiplier
	# is applied by the equip). Rounded so a ≈1.0 that isn't exactly 1.0 stays silent.
	var move_pct := roundi((w.move_speed_multiplier - 1.0) * 100.0)
	if move_pct != 0:
		parts.append("Move %s" % _signed_pct(move_pct))
	# A weapon that inflicts a StatusEffect on hit (poison / burn rounds, a slowing tag) — summarise it like a consumable.
	# The chance rides the LABEL and the sub-parts join with COMMAS (not the outer "  ·  "), so the clause stays visually
	# scoped instead of dissolving into the top-level weapon stats.
	if w.on_hit_effect != null:
		var eff := _timed_effect_parts(w.on_hit_effect)
		if not eff.is_empty():
			var lead := "On hit"
			if w.on_hit_chance < 1.0:
				lead += " (%d%%)" % roundi(w.on_hit_chance * 100.0)
			parts.append("%s: %s" % [lead, ", ".join(eff)])
	return "  ·  ".join(parts)

## The data-derived "what it does" lines: an upgrade chip's installed ability, a carried item's passive buff, and a
## consumable's applied effect — each generated from the item's STRUCTURED fields, never from authored prose, so a
## scrubbed-blank `description` still communicates the mechanics. Returns [] for a plain item (none of these fields
## set), leaving the tooltip exactly as before.
static func _effect_lines(item: Item) -> Array[String]:
	var out: Array[String] = []
	# Upgrade chip: carrying it does nothing until a ChipInstaller consumes it, so name the ability it unlocks.
	if item.is_upgrade_chip():
		out.append("Installs %s" % _ability_name(item.installs_ability))
	# Passive held buff (the Chrome Grin case): the effect is live WHILE the item sits in the bag.
	if item.held_passive_effect != null:
		var parts := _held_effect_parts(item.held_passive_effect)
		if not parts.is_empty():
			var line := "While carried: " + "  ·  ".join(parts)
			# The stacking rule only matters when you could actually hold more than one copy.
			if item.max_stack > 1:
				line += "  ·  " + ("counts once" if item.passive_unique else "per copy")
			out.append(line)
	# Consumable's applied StatusEffect (a stim / buff / poison) — shown ALONGSIDE any "Heals N HP" line above.
	if item.consumable_effect != null:
		var parts := _timed_effect_parts(item.consumable_effect)
		if not parts.is_empty():
			out.append("When used: " + "  ·  ".join(parts))
	# A holdable prop (the dog crate, any world_prop / world_model item that isn't a weapon/consumable/ammo/chip/coin)
	# can be pulled into the hands from the hotbar and thrown — otherwise its tooltip is just a name, saying nothing
	# about the one thing you can DO with it. is_holdable() already encodes all those exclusions.
	if item.is_holdable():
		out.append("Hold in hand · throwable")
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

## A consumable's applied StatusEffect (Item.consumable_effect) as labeled parts — the TIMED path, so unlike a held
## buff it reads duration + periodic damage, and strength IS shown raw (a timed strength buff DOES fold into melee, so
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
	if fx.duration > 0.0:
		parts.append("for %s s" % _num(fx.duration))
	return parts

## The player-facing name for an installs_ability mechanic id — routed through AbilityRegistry.display_name_for,
## THE canonical accessor: the authored Ability.display_name on the ability scene's root wins, and a blank/missing
## name degrades to the old capitalized-id look ("wall_climb" -> "Wall Climb"), never a blank. A functional label
## like the stat titles, so it carries no [PH] marker.
static func _ability_name(id: StringName) -> String:
	return AbilityRegistry.display_name_for(id)

## A SIGNED bare/half number: "+3", "-2", "+4.5". Callers skip zeros (is_zero_approx), so 0 never reaches here.
static func _signed(x: float) -> String:
	return ("+" + _num(x)) if x > 0.0 else _num(x)  # a negative already carries its own minus

## A SIGNED integer percentage: "+10%", "-25%". Callers skip a rounded 0 (`speed_pct != 0`), so "0%" never reaches here.
static func _signed_pct(p: int) -> String:
	return ("+%d%%" % p) if p > 0 else ("%d%%" % p)  # a negative already carries its own minus

## Trim a float to a bare/half readout ("4" / "4.5") — TextFormat.num at one decimal, the single copy of the trim
## idiom (this file's private duplicate is gone). Byte-identical to the old copy except TextFormat's "-0" guard:
## a negative that rounds to zero now prints "0", not "-0" (unreachable in practice — _signed callers skip zeros).
static func _num(x: float) -> String:
	return TextFormat.num(x, 1)
