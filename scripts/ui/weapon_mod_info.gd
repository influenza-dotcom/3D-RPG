class_name WeaponModInfo
extends RefCounted

## Hover/preview breakdown for WEAPON PARTS — the sibling of ItemInfo (a whole item) and StatInfo (one stat).
## Pure statics, no state beyond one reflection cache. Two surfaces, one voice:
##   • part_line(part)   — a part's effects as ONE labeled line, fed into ItemInfo._effect_lines, so the
##     inventory, shop, loot AND bench tooltips all describe a part identically from a single branch.
##   • compare_block(...) — the bench footer's BEFORE → AFTER preview for the row under the cursor (or under
##     pad focus — the bench wires focus_entered alongside mouse_entered), built from WeaponModKit.diff so the
##     preview can only ever report a change the fold actually produced.
##
## ⭐The labeled stat vocabulary below (STAT_LABELS, the on/off words, the "  ·  " joins) is COMPOSED INSIDE
## this formatter and is deliberately NOT routed through PlayerText — exactly like ItemInfo._weapon_block's
## "Damage / Rate / Range / Headshot" labels. The PlayerText chokepoint is about paint SITES (a label.text, a
## toast, a title); a formatter that RETURNS a string to a caller which then paints it is the sanctioned way
## to build a derived, mechanical readout, and pushing a per-property label table into PlayerText would put
## twenty near-identical single words in the registry with nothing but this file ever reading them. The
## SENTENCES around this — the bench's headings, notices and toasts — are PlayerText members.
##
## LOCALIZATION NOTE: the same recorded, deferred gap ItemInfo carries (CURRENT_ARCHITECTURE → Localization
## Readiness) — the composer joins English-shaped labeled fragments. What IS wired: every number goes through
## TextFormat.num / TextFormat.signed / TextFormat.signed_pct, and the slot names come from PlayerText.

## The fold and its diff — the ONE place stat maths lives. Const-preloaded (no class_name, the Calibers idiom).
## No cycle: the kit names WeaponData and WeaponFields and nothing in the UI layer.
const WeaponModKit = preload("res://scripts/items/weapon_mod_kit.gd")

## WeaponData property -> display label. Short on purpose: these sit in a fixed-width column beside a number,
## and a wrapped label would break the bench footer's constant line count. Deliberately mirrors the words
## ItemInfo._weapon_block already uses for the same fields ("Damage", "Rate", "Range", "Headshot", "Clip"), so
## a player reading a gun's tooltip and a part's preview sees ONE vocabulary.
## ⭐The three scope fields all read "Zoom" on purpose — they are one concept to the player (how far the scope
## pulls in) and three fields only because the wheel-zoom dial needs a min/max pair.
## A property that is NOT listed degrades to the capitalized id ("bullet_gravity_scale" -> "Bullet Gravity
## Scale") rather than a blank — the StatInfo.title / AbilityRegistry fallback rule, and a legible-if-clumsy
## label is what a designer needs the moment they point a delta at an unusual field.
const STAT_LABELS: Dictionary = {
	&"damage": "Damage",
	&"pellet_count": "Pellets",
	&"pellet_spread": "Spread",
	&"headshot_multiplier": "Headshot",
	&"attack_speed": "Rate",
	&"attack_windup": "Wind-up",
	&"effective_range": "Range",
	&"max_ammo": "Clip",
	&"reload_time": "Reload",
	&"auto_fire": "Automatic",
	&"auto_reload": "Auto Reload",
	&"move_speed_multiplier": "Move",
	&"stamina_cost_mult": "Stamina",
	&"noise_radius_mult": "Noise",
	&"hip_sway_mult": "Hip Sway",
	&"screen_shake_amount": "Shake",
	&"recoil_kick_deg": "Recoil",
	&"recoil_horizontal_deg": "Sideways Recoil",
	&"recoil_recovery": "Recovery",
	&"bloom_per_shot_deg": "Bloom",
	&"bloom_max_deg": "Max Bloom",
	&"has_muzzle_flash": "Muzzle Flash",
	&"muzzle_smoke_scale": "Smoke",
	&"spawns_casing": "Casings",
	&"casing_size_scale": "Casing Size",
	&"has_tracer": "Tracer",
	&"no_ads": "No Aim-Down-Sights",
	&"scoped_fov_override": "Zoom",
	&"scoped_zoom_fov_max": "Zoom",
	&"scoped_zoom_fov_min": "Zoom",
	&"projectile_speed": "Muzzle Velocity",
	&"projectile_explodes": "Explosive",
	&"explosion_radius": "Blast",
	&"explosion_damage": "Blast Damage",
	&"enemy_knockback": "Knockback",
}

## Props whose CHANGE is reported as a signed PERCENT rather than a signed absolute delta. Two families:
##   (a) the multiplier / ratio fields, where the absolute delta is a meaningless fraction ("Move +-0.04");
##   (b) the fields whose live values are too small or too unit-laden for a raw delta to read as anything
##       (pellet_spread lives around 0.01, attack_speed is SECONDS PER SHOT, damage sits on a 0.9-vs-1.17 scale).
## Everything else — range in metres, clip size, pellet count, reload seconds — reports its absolute delta,
## because that IS the number the player feels. ⭐A part's own MULT line always renders as a percent regardless
## of this list: a MULT is a ratio by construction, so "Range -25%" is the truth about the LINE even though a
## fitted range change reports as "+8 m".
const PERCENT_STATS: Array[StringName] = [
	&"damage",
	&"attack_speed",
	&"pellet_spread",
	&"screen_shake_amount",
	&"move_speed_multiplier",
	&"noise_radius_mult",
	&"hip_sway_mult",
	&"stamina_cost_mult",
	&"muzzle_smoke_scale",
	&"casing_size_scale",
	&"recoil_recovery",
]

## Props where DOWN is an improvement, so the bench footer inks a decrease with MenuStyle.accent() and an
## increase with MenuStyle.danger(). attack_speed is the one that catches everybody: it is SECONDS PER SHOT,
## so a smaller number is a FASTER gun (WeaponData authors it that way and ItemInfo prints its reciprocal).
## recoil_kick_deg / bloom_* are NOT listed even though lower is obviously better there: they are 0.0 on every
## shipped weapon, so no part can move them today — add them here the day one is authored non-zero, rather
## than carrying rows nothing exercises.
const LOWER_IS_BETTER: Array[StringName] = [
	&"attack_speed",
	&"pellet_spread",
	&"reload_time",
	&"noise_radius_mult",
	&"hip_sway_mult",
	&"screen_shake_amount",
	&"stamina_cost_mult",
]

## The separator between labeled parts — ItemInfo's exact glyph (U+00B7 with two spaces each side), which is
## also what compare_block folds overflow rows together with.
const JOIN := "  ·  "

## BOOL targets have no arithmetic, so they read as a state word. Composed here for the same reason the labels
## are (see the header note); kept to one word each so a bool row fits the same column as a number.
const FLAG_ON := "on"
const FLAG_OFF := "off"

## A throwaway WeaponData, built once, used ONLY to ask what type a property was declared as (a part's delta
## line renders differently for a bool than for a number, and the WeaponStatDelta resource does not record
## which it targets — the fold reads the type off the block it is writing, and so must we). Static so the cost
## is paid once per run; it resets on a script reload, which is exactly when WeaponData's property list could
## have changed. Same caching rule as WeaponFields._ids.
static var _type_probe: WeaponData = null


# --- The part one-liner (fed into ItemInfo._effect_lines) --------------------------------------------------

## `part`'s slot, effects and stat gate as ONE "  ·  "-joined labeled line — "Barrel part  ·  Range +8  ·
## Spread -25%  ·  Move -4%  ·  Hip Sway +10%". Returns "" for anything that is not a weapon part, so the
## ItemInfo branch can append it unconditionally.
##
## The SLOT leads because it is the first thing that decides whether the part is any use to you (one part per
## slot, and pulling the occupant costs money). What is deliberately NOT here is FITMENT — which guns the part
## goes on. That list would double the line's length on a universal part and say nothing on the common case;
## the bench dims a row that does not fit and its Notice band names the reason, which is the surface where the
## question is actually being asked.
##
## A delta whose change rounds away to nothing at display resolution is DROPPED rather than printed as "+0" —
## the ItemInfo._held_effect_parts rule. A part whose every line rounds away shows its slot and gate alone,
## which is honest: it really does nothing measurable.
static func part_line(part: Item) -> String:
	if part == null or not part.is_weapon_mod():
		return ""
	var mod: WeaponMod = part.weapon_mod
	var parts: Array[String] = [PlayerText.mod_slot_name(mod.slot) + " part"]
	for d: WeaponStatDelta in mod.deltas:
		if d == null or d.property == &"":
			continue
		var text := _delta_text(d)
		if not text.is_empty():
			parts.append(text)
	# The GUNPLAY rung, last, because it is a condition rather than an effect. Resolved through StatInfo.title
	# (the requires_stat idiom) so renaming the stat in resources/stats/gunplay.tres reaches this line; the
	# stat ID is fixed here because WeaponMod's gate field is (min_gunplay).
	if mod.min_gunplay > 0:
		parts.append("needs %s %d" % [StatInfo.title(&"gunplay"), mod.min_gunplay])
	return JOIN.join(parts)


## ONE authored delta line as a labeled part ("Range +8", "Spread -25%", "Zoom 25", "Muzzle Flash off").
## Returns "" when the line moves nothing measurable — a MULT of exactly 1.0, an ADD of 0, a delta rounding
## below display resolution — so a no-op authoring mistake reads as an ABSENT claim rather than as "+0".
static func _delta_text(d: WeaponStatDelta) -> String:
	var label := stat_label(d.property)
	if _declared_type(d.property) == TYPE_BOOL:
		# The fold ignores `op` entirely for a BOOL target and writes `flag` — say the resulting STATE, not
		# the arithmetic, because "Muzzle Flash SET 0" is engine-speak for "no muzzle flash".
		return "%s %s" % [label, FLAG_ON if d.flag else FLAG_OFF]
	match d.op:
		WeaponStatDelta.Op.SET:
			# A SET replaces the authored value outright, so there is no delta to sign — show the destination.
			return "%s %s" % [label, _scalar_text(d.property, d.amount)]
		WeaponStatDelta.Op.MULT:
			# A MULT is a RATIO, so it always reads as a percent whatever PERCENT_STATS says about the field.
			var pct := roundi((d.amount - 1.0) * 100.0)
			if pct == 0:
				return ""
			return "%s %s" % [label, TextFormat.signed_pct(pct, false)]
		_:
			if is_zero_approx(snappedf(d.amount, 0.01)):
				return ""
			return "%s %s" % [label, TextFormat.signed(d.amount, 2, false)]


# --- The bench footer's before -> after block --------------------------------------------------------------

## The fit/remove PREVIEW: `header` on line one, then one "{Label}  {before} → {after}  ({delta})" row per
## changed property.
##
## ⭐CONSTANT LINE COUNT BY CONSTRUCTION — the block is ALWAYS exactly `max_lines` lines (header plus
## max_lines - 1 body lines, blank-padded when there is less to say). The footer is a fixed-height band under
## the two lists; if its height tracked the number of changes, the lists above it would re-flow every time the
## cursor crossed a row and the card would hop out from under the player mid-transaction. That is the shipped
## list-screen bug this shape exists to avoid, and it is why the padding is not an oversight.
## Overflow past the last body line is FOLDED into it, joined with "  ·  ", so a part that moves eight stats
## still reports all eight rather than silently truncating the tail.
##
## The rows come from WeaponModKit.diff, which measures only the mod-targetable scalars — so the preview can
## never claim a change on a field no part is allowed to move, and never mentions the six slot bookkeeping ids.
## Row ORDER is the diff's own (WeaponFields.ids(), sorted and stable across runs): deterministic is the
## property that matters here, because a preview that reordered itself between two hovers of the same row
## would look like the numbers were moving.
static func compare_block(before: WeaponData, after: WeaponData, header: String, max_lines: int) -> String:
	var body_room := maxi(max_lines - 1, 0)
	if body_room <= 0:
		return header
	var rows := change_rows(before, after)
	if rows.size() > body_room:
		var kept := rows.slice(0, body_room - 1)
		kept.append(JOIN.join(rows.slice(body_room - 1)))
		rows = kept
	var lines: Array[String] = [header]
	lines.append_array(rows)
	while lines.size() < body_room + 1:
		lines.append("")
	return "\n".join(lines)


## One row per CHANGED property, unpadded and unfolded — compare_block's body. Public rather than private
## because it is the only shape a caller can use to treat rows INDIVIDUALLY (ink one accent and one danger,
## count them, drop one); compare_block is the fixed-height convenience over it, not the other way round.
static func change_rows(before: WeaponData, after: WeaponData) -> Array[String]:
	var out: Array[String] = []
	if before == null or after == null:
		return out
	var changes := WeaponModKit.diff(before, after)
	for prop: String in changes:
		var entry: Dictionary = changes[prop]
		var row := _change_row(StringName(prop), entry["before"], entry["after"])
		if not row.is_empty():
			out.append(row)
	return out


## "{Label}  {before} → {after}  ({delta})" for one changed property, or "" when the change is below display
## resolution. The ARROW is U+2192 with one space each side; TWO spaces separate the three columns.
##
## ⭐The percent branch gates on `roundi(...) != 0`, NEVER on is_equal_approx: a 1.003 ratio sails past an
## approx test and then renders a meaningless "+0%". The absolute branch gates the same way, on the value
## ROUNDED to the two decimals it will actually be printed at — same rule, same reason.
## Both use the COMPARISON voice (TextFormat's `zero_plus = true`), StatInfo's: a surface whose whole job is
## before-versus-after must be able to say "+0" out loud. The gates above mean it rarely has to.
static func _change_row(prop: StringName, before: Variant, after: Variant) -> String:
	var label := stat_label(prop)
	if before is bool or after is bool:
		# No delta parenthetical for a flag — "on → off" IS the whole story, and "(+1)" would be nonsense.
		return "%s  %s → %s" % [label, FLAG_ON if bool(before) else FLAG_OFF, FLAG_ON if bool(after) else FLAG_OFF]
	var bf := float(before)
	var af := float(after)
	var delta_text := ""
	if is_percent_stat(prop) and not is_zero_approx(bf):
		var pct := roundi((af / bf - 1.0) * 100.0)
		if pct == 0:
			return ""
		delta_text = TextFormat.signed_pct(pct, true)
	else:
		var delta := snappedf(af - bf, 0.01)
		if is_zero_approx(delta):
			return ""
		delta_text = TextFormat.signed(delta, 2, true)
	var pair := _pair_text(before, after)
	return "%s  %s → %s  (%s)" % [label, pair[0], pair[1], delta_text]


## The two VALUE columns, rendered at the shallowest decimal depth that still tells them apart. Two decimals
## is the readable default, but the small-valued fields (pellet_spread lives around 0.0075) would otherwise
## print "0.01 → 0.01  (-25%)" — a row that contradicts itself. Ints print bare, never "10.00".
static func _pair_text(before: Variant, after: Variant) -> PackedStringArray:
	if before is int and after is int:
		return PackedStringArray([str(int(before)), str(int(after))])
	var bf := float(before)
	var af := float(after)
	for decimals: int in [2, 3, 4]:
		var b_s := TextFormat.num(bf, decimals)
		var a_s := TextFormat.num(af, decimals)
		if b_s != a_s:
			return PackedStringArray([b_s, a_s])
	return PackedStringArray([TextFormat.num(bf, 4), TextFormat.num(af, 4)])


# --- The property vocabulary --------------------------------------------------------------------------------

## THE WeaponData-property -> display-label table (see STAT_LABELS). Unknown props degrade to the capitalized
## id, never a blank — a designer pointing a delta at an unusual field gets a clumsy label, not a nameless row.
static func stat_label(prop: StringName) -> String:
	var label := String(STAT_LABELS.get(prop, ""))
	return label if not label.is_empty() else String(prop).capitalize()


## Does this property's CHANGE read as a signed percent rather than a signed absolute delta? See PERCENT_STATS.
static func is_percent_stat(prop: StringName) -> bool:
	return PERCENT_STATS.has(prop)


## Is DOWN an improvement for this property? See LOWER_IS_BETTER — and note attack_speed is seconds per shot.
static func is_lower_better(prop: StringName) -> bool:
	return LOWER_IS_BETTER.has(prop)


# --- Internals ------------------------------------------------------------------------------------------------

## A raw value in its declared type's voice: an INT field prints bare ("20"), a FLOAT trims to at most two
## decimals ("1.17", "25"). Used by a SET line, which shows a destination rather than a delta.
static func _scalar_text(prop: StringName, value: float) -> String:
	if _declared_type(prop) == TYPE_INT:
		return str(roundi(value))
	return TextFormat.num(value, 2)


## The declared type of a WeaponData property (TYPE_BOOL / TYPE_INT / TYPE_FLOAT), TYPE_NIL when there is no
## such property. Read off a cached throwaway instance rather than the property list, because `get()` on a
## real object already answers with the declared type and cannot drift from what the fold writes.
static func _declared_type(prop: StringName) -> int:
	if _type_probe == null:
		_type_probe = WeaponData.new()
	var v: Variant = _type_probe.get(String(prop))
	return TYPE_NIL if v == null else typeof(v)
