class_name StatInfo
extends RefCounted

const StatTextResource := preload("res://scripts/ui/stat_text.gd")

## Human-readable breakdowns for CharacterStats — fed into menu tooltips so HOVERING a stat shows
## what it does and its effect at the current value. Pure formatter; reads the live sheet for the current
## numbers. The TITLE + BLURB are now AUTHORED TEXT (resources/stats/<id>.tres, see StatText) so a designer can
## edit them in the CYBER SUNDAY Text tab — this file no longer hardcodes them. The live "Now:" effect line stays
## computed here (it's derived numbers, not prose). A missing StatText degrades to a bare capitalized title.

## A multi-line tooltip for `stat` given the character's live `sheet` (null = treated as baseline). Pulls the
## title + blurb from the authored StatText resource for this stat; falls back to a bare title if none exists yet.
static func tooltip(stat: StringName, sheet: CharacterStats) -> String:
	var s: CharacterStats = sheet if sheet != null else CharacterStats.new()
	var v: int = s.get_stat(stat)
	return "%s  ·  %d\n%s\nNow: %s" % [title(stat), v, blurb(stat), _effect(stat, s)]

## The authored title for `stat` (e.g. "Strength"), or a bare capitalized id when no StatText is authored yet.
## The ONE place stat title text resolves — the stats screen + character creation read through here, not a local
## const table, so all three stay in sync with resources/stats/<id>.tres (edited in the CYBER SUNDAY Text tab).
static func title(stat: StringName) -> String:
	var st := StatTextResource.by_id(stat)
	var display_name := String(st.get("display_name")) if st != null else ""
	return display_name if not display_name.is_empty() else String(stat).capitalize()

## The authored one-line blurb for `stat` ("" when none is authored yet) — the shared read for every stat readout.
static func blurb(stat: StringName) -> String:
	var st := StatTextResource.by_id(stat)
	return String(st.get("description")) if st != null else ""

## The single-line "current effect" string for `stat` at the sheet's live value. Sign-correct across the whole
## range: a NEGATIVE stat reads as a real penalty (a minus, not a stray "+-"), since character creation lets a
## stat go below baseline and CharacterStats inverts every derived effect there.
static func _effect(stat: StringName, s: CharacterStats) -> String:
	match stat:
		&"strength":
			# The merged physical stat: melee damage (a %) plus the spawn-stamped carry / max HP (flat numbers).
			return "[PH] melee %s, %s carry, %s max HP" % [
				_signed_pct(roundi((s.melee_damage_mult() - 1.0) * 100.0)),
				_signed_num(s.carry_bonus()),
				_signed_num(s.max_hp_bonus())]
		&"endurance":
			return "[PH] %s max stamina" % _signed_num(s.stamina_bonus())
		&"gunplay":
			return "[PH] %s gun damage, %s aim steadiness" % [
				_signed_pct(roundi((s.weapon_damage_mult() - 1.0) * 100.0)),
				_signed_pct(roundi((1.0 - s.sway_mult()) * 100.0))]
		&"agility":
			return "[PH] %s move speed" % _signed_pct(roundi((s.move_speed_mult() - 1.0) * 100.0))
		&"streetwise":
			# The merged social stat: prices (+ = in your favour, cheaper buys / dearer sales) AND reputation gains.
			return "[PH] buys %s, sales %s, rep gains %s" % [
				_signed_pct(roundi((1.0 - s.buy_price_mult()) * 100.0)),
				_signed_pct(roundi((s.sell_price_mult() - 1.0) * 100.0)),
				_signed_pct(roundi((s.rep_gain_mult() - 1.0) * 100.0))]
		&"stealth":
			# detection_rate_mult < 1.0 = slower to be spotted; the signed % reads "-N% enemy detection speed" (good).
			return "[PH] %s enemy detection speed" % _signed_pct(roundi((s.detection_rate_mult() - 1.0) * 100.0))
		&"pickpocket":
			# Concrete at the encounter defaults (PickpocketSettings): the caught risk per lift + the value ceiling.
			var pp := GameSettings.pickpocket
			return "[PH] %d%% caught risk, lift value <= %s" % [
				roundi(s.pickpocket_catch_chance(pp.base_catch_chance, pp.catch_chance_per_point) * 100.0),
				_num(s.pickpocket_value_allowance(pp.base_value_allowance, pp.value_allowance_per_point))]
	return ""

## Trim a float to a bare/half readout ("4" / "4.5"), matching the Zorkmids.fmt feel. A negative carries its own minus.
static func _num(x: float) -> String:
	if is_equal_approx(x, roundf(x)):
		return str(int(roundf(x)))
	return ("%.1f" % x).rstrip("0").rstrip(".")

## A SIGNED bare/half number: "+4", "-4", "+4.5", and "0" at baseline (never "+0" / "-0").
static func _signed_num(x: float) -> String:
	if is_zero_approx(x):
		return "0"
	return ("+" + _num(x)) if x > 0.0 else _num(x)  # a negative already carries its minus

## A SIGNED percentage: "+8%", "-8%", and "0%" at baseline.
static func _signed_pct(p: int) -> String:
	if p == 0:
		return "0%"
	return ("+%d%%" % p) if p > 0 else ("%d%%" % p)  # a negative already carries its minus
