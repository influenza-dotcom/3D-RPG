class_name StatInfo
extends RefCounted

## Human-readable breakdowns for the six CharacterStats — fed into menu tooltips so HOVERING a stat shows
## what it does and its effect at the current value. Pure formatter; reads the live sheet for the current
## numbers. The wording mirrors the per-stat doc comments on CharacterStats so the two never drift.

const TITLES := {
	&"strength": "Strength", &"persuasion": "Persuasion", &"gunplay": "Gunplay",
	&"endurance": "Endurance", &"streetwise": "Streetwise", &"agility": "Agility",
}
const BLURB := {
	&"strength": "Carry capacity — haul more before the over-encumbered slog kicks in.",
	&"persuasion": "Haggling — buy cheaper, sell dearer, and pass dialogue checks.",
	&"gunplay": "Steady hands — tightens the gun's idle sway for tighter shots.",
	&"endurance": "Vitality — raises your max HP (applied when you spawn).",
	&"streetwise": "Standing — good deeds land bigger, slip-ups sting less.",
	&"agility": "Fleetness — moves you faster on foot.",
}

## A multi-line tooltip for `stat` given the character's live `sheet` (null = treated as baseline).
static func tooltip(stat: StringName, sheet: CharacterStats) -> String:
	var s: CharacterStats = sheet if sheet != null else CharacterStats.new()
	var v: int = s.get_stat(stat)
	var title: String = TITLES.get(stat, str(stat))
	var blurb: String = BLURB.get(stat, "")
	return "%s  ·  %d\n%s\nNow: %s" % [title, v, blurb, _effect(stat, s)]

## The single-line "current effect" string for `stat` at the sheet's live value.
static func _effect(stat: StringName, s: CharacterStats) -> String:
	match stat:
		&"strength":
			return "+%s carry capacity" % _num(s.carry_bonus())
		&"endurance":
			return "+%s max HP" % _num(s.max_hp_bonus())
		&"persuasion":
			return "buy %d%% cheaper · sell %d%% dearer" % [roundi((1.0 - s.buy_price_mult()) * 100.0), roundi((s.sell_price_mult() - 1.0) * 100.0)]
		&"gunplay":
			return "%d%% steadier aim" % roundi((1.0 - s.sway_mult()) * 100.0)
		&"streetwise":
			return "rep gains +%d%% · losses -%d%%" % [roundi((s.rep_gain_mult() - 1.0) * 100.0), roundi((1.0 - s.rep_loss_mult()) * 100.0)]
		&"agility":
			return "%d%% move speed" % roundi(s.move_speed_mult() * 100.0)
	return ""

## Trim a float to a bare/half readout ("4" / "4.5"), matching the Zorkmids.fmt feel.
static func _num(x: float) -> String:
	if is_equal_approx(x, roundf(x)):
		return str(int(roundf(x)))
	return ("%.1f" % x).rstrip("0").rstrip(".")
