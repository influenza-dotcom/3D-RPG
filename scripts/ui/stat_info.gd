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
static func _effect(stat: StringName, s: CharacterStats, bonus: float = 0.0) -> String:
	match stat:
		&"strength":
			# Strength bonuses are live for melee, while carry / max HP are stamped by the actor.
			return PlayerText.stat_effect_strength(
				_signed_pct(roundi((s.melee_damage_mult(bonus) - 1.0) * 100.0)),
				_signed_num(s.carry_bonus()),
				_signed_num(s.max_hp_bonus()))
		&"endurance":
			# Two effects now: the stamina CAP (an absolute bonus) and the out-of-combat health-regen RATE (a
			# multiplier, so it reads as a percentage like every other live-seam stat — see agility below).
			return PlayerText.stat_effect_endurance(
				_signed_num(s.stamina_bonus(bonus)),
				_signed_pct(roundi((s.hp_regen_mult(bonus) - 1.0) * 100.0)))
		&"gunplay":
			return PlayerText.stat_effect_gunplay(
				_signed_pct(roundi((s.weapon_damage_mult(bonus) - 1.0) * 100.0)),
				_signed_pct(roundi((1.0 - s.sway_mult(bonus)) * 100.0)))
		&"agility":
			return PlayerText.stat_effect_agility(_signed_pct(roundi((s.move_speed_mult(bonus) - 1.0) * 100.0)))
		&"streetwise":
			# The merged social stat: prices (+ = in your favour, cheaper buys / dearer sales) AND reputation gains.
			return PlayerText.stat_effect_streetwise(
				_signed_pct(roundi((1.0 - s.buy_price_mult(bonus)) * 100.0)),
				_signed_pct(roundi((s.sell_price_mult(bonus) - 1.0) * 100.0)),
				_signed_pct(roundi((s.rep_gain_mult(bonus) - 1.0) * 100.0)))
		&"larceny":
			# The merged thief stat shows all FOUR effects. Detection + takedown read "less is better" (a signed % of
			# mult - 1.0: detection_rate_mult < 1.0 = slower to be spotted; takedown_time_mult < 1.0 = quicker kill).
			# The pickpocket half is concrete at the encounter defaults (PickpocketSettings): the caught risk per lift
			# + the liftable-value ceiling.
			var pp := GameSettings.pickpocket
			return PlayerText.stat_effect_larceny(
				_signed_pct(roundi((s.detection_rate_mult(bonus) - 1.0) * 100.0)),
				_signed_pct(roundi((s.takedown_time_mult(bonus) - 1.0) * 100.0)),
				roundi(s.pickpocket_catch_chance(pp.base_catch_chance, pp.catch_chance_per_point, bonus) * 100.0),
				_num(s.pickpocket_value_allowance(pp.base_value_allowance, pp.value_allowance_per_point, bonus)))
	return ""

## Trim a float to a bare/half readout ("4" / "4.5"), matching the Zorkmids.fmt feel — TextFormat.num at one
## decimal, the single copy of the trim idiom (this file's private duplicate is gone). A negative carries its own
## minus; a negative that rounds to zero prints "0" (TextFormat's "-0" guard — _signed_num callers skip zeros anyway).
static func _num(x: float) -> String:
	return TextFormat.num(x, 1)

## A SIGNED bare/half number: "+4", "-4", "+4.5", and "+0" at baseline. TextFormat.signed at one decimal in the
## COMPARISON voice (zero_plus = true) — this file's private copy of the idiom is gone, and the weapon bench's
## before/after footer reads in this same voice for the same reason (see _signed_pct).
static func _signed_num(x: float) -> String:
	return TextFormat.signed(x, 1, true)

## A SIGNED percentage: "+8%", "-8%", and "+0%" at baseline — zero keeps the plus so a baseline stat reads
## as "this is your bonus: none" in the same voice as a real bonus, instead of a bare number that looks like
## a different kind of line (the creation tooltip used to say "neutral" here; user call 2026-08-12). That
## decision now lives in TextFormat.signed_pct's `zero_plus` flag, which this passes true.
static func _signed_pct(p: int) -> String:
	return TextFormat.signed_pct(p, true)
