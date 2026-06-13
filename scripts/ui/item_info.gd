class_name ItemInfo
extends RefCounted

## Hover breakdown for an inventory Item — what it is and, for a weapon, its combat stats. Pure formatter;
## reads Item / WeaponData fields and the holder's spare ammo. Fed into the inventory/shop/loot row tooltips
## so HOVERING an item shows its stats. Mirrors ItemRow's "labeled language" so the two never drift.

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
	var foot: String = "Weight %s" % _num(item.weight)
	if item.value > 0.0:
		foot += "  ·  %s zm" % Zorkmids.fmt(item.value)
	lines.append(foot)
	return "\n".join(lines)

## The weapon's combat one-liner: damage (× pellets), fire rate, range, headshot, ammo/clip.
static func _weapon_block(w: WeaponData, holder: CharacterInventory) -> String:
	var parts: Array[String] = []
	var dmg: String = "Damage %s" % _num(w.damage)
	if w.pellet_count > 1:
		dmg += " ×%d" % w.pellet_count
	parts.append(dmg)
	parts.append("Rate %s/s" % _num(1.0 / maxf(w.attack_speed, 0.01)))
	if w.effective_range > 0.0:
		parts.append("Range %s m" % _num(w.effective_range))
	parts.append("Headshot ×%s" % _num(w.headshot_multiplier))
	if w.is_infinite_ammo:
		parts.append("Ammo ∞")
	elif w.caliber != &"":
		var reserve: String = ""
		if holder != null:
			reserve = " (%d spare)" % holder.ammo_count(w.caliber)
		parts.append("%s · clip %d%s" % [w.caliber, w.max_ammo, reserve])
	else:
		parts.append("Clip %d" % w.max_ammo)
	return "  ·  ".join(parts)

## Trim a float to a bare/half readout ("4" / "4.5").
static func _num(x: float) -> String:
	if is_equal_approx(x, roundf(x)):
		return str(int(roundf(x)))
	return ("%.1f" % x).rstrip("0").rstrip(".")
