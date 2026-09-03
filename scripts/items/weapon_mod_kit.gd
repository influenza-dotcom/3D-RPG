extends RefCounted

## THE FOLD — the one and only place weapon-part stat maths lives. A WeaponMod is inert DATA (a slot, a list
## of WeaponStatDelta lines, a handful of resource overrides); this file is the function that turns "these six
## slot ids" into a finished WeaponData stat block. Everything else in the system — the bench, the save
## restore, the screen's before/after preview — calls in here and never does arithmetic of its own.
##
## ⭐rebuild() ALWAYS starts from `template_weapon.duplicate()`. It never mutates the template and it never
## folds onto an already-folded block. That single rule is what buys all four properties the design depends on:
##   • IDEMPOTENT — folding the same id set twice gives byte-identical scalars.
##   • ORDER-INDEPENDENT — slots are walked in enum order, so a Dictionary's insertion order can't move a number.
##   • LOSSLESS — pulling a part returns the AUTHORED values exactly, with zero accumulated float drift.
##   • SAFE — a MULT can never compound onto its own output (fit/refit/refit would otherwise cube it).
## Mutating the template instead would be catastrophic in a quiet way: the template IS the diff baseline
## ItemDb.weapon_delta_for measures against, so the change would persist NOTHING while silently buffing every
## instance of that gun in the world — NPC hands and shop shelves included.
##
## ⭐It takes `resolve: Callable` (id -> WeaponMod) rather than naming ItemDb. ItemDb const-preloads this file;
## naming ItemDb back would close a preload cycle, and a cycle here would break every level load, not just mods.
## ItemDb._resolve_weapon_mod is the production resolver; a test passes a lambda over a hand-built dictionary.
##
## NO class_name on purpose — const-preloaded where needed (ItemDb, WeaponBench), so there's nothing for the
## global script class cache to miss; mirrors the Calibers / ItemIds / WeaponFields registries.

## The property list a diff() is measured over — the same DERIVED set that populates WeaponStatDelta's dropdown,
## so the footer can never claim a change on a field a part was not allowed to move.
const WeaponFields = preload("res://scripts/items/weapon_fields.gd")

## ⭐THE CLAMP FLOOR — safety rails, NOT balance dials, which is why they are consts here and not @exports on
## the bench. A designer tunes a part's MULT; nobody tunes "the minimum legal rate of fire". Each entry exists
## because the engine misbehaves below it rather than because the game plays badly:
##   • attack_speed  — SECONDS PER SHOT. At 0 the fire loop's cooldown never elapses (Attack re-arms forever)
##     AND WeaponData.power_score() divides by it, so a zeroed rate poisons the AI's equip ranking for every
##     NPC that ever picks the gun up. 0.01 s = 100 rounds/s, far past anything authorable.
##   • max_ammo / pellet_count — whole counts the firing pipeline loops over; 0 is a gun that cannot shoot.
##   • effective_range / noise_radius_mult / reload_time — negatives are nonsense the consumers don't guard.
## Applied ONCE, at the very end of rebuild(), so it clamps the FINAL number no matter which pass produced it.
const CLAMP_FLOORS: Dictionary = {
	# ⭐ NOT the last word on the value the game actually uses. A MELEE weapon's cadence and EVERY weapon's reload
	# are scaled again at consumption time by the wielder's AGILITY (Attack.effective_attack_speed /
	# effective_reload_time), bounded by GameSettings.weapon_general's own floors. Those floors are non-lengthening
	# (Attack._duration_floor takes minf(floor, authored)), so a part that drops a cadence below them still reads
	# true in the bench preview and still swings that fast in the hands — it simply stops responding to agility.
	"attack_speed": 0.01,
	"max_ammo": 1.0,
	"pellet_count": 1.0,
	"effective_range": 0.0,
	"noise_radius_mult": 0.0,
	"reload_time": 0.0,
}


# --- The slot map: the currency every caller passes around -------------------------------------------------

## `weapon`'s fitted set as {slot ordinal int -> part Item.id}, with ALL SIX slots always present (&"" = empty).
## Fixed arity on purpose: the bench builds one of these, writes ONE key, and hands it straight to rebuild(),
## so "fit" and "remove" are the same call with a different value and neither can forget a slot.
## A null weapon yields six blanks rather than an empty dict — callers may then treat it uniformly.
static func slot_map(weapon: WeaponData) -> Dictionary:
	var out := {}
	for slot in WeaponData.MOD_SLOT_PROPS.size():
		out[slot] = weapon.mod_id(slot) if weapon != null else &""
	return out

## True when nothing is fitted. ItemDb.rebuild_weapon_mods early-outs on this so the load path stays a pure
## no-op for the overwhelmingly common unmodded weapon — no duplicate, no reflection, no template lookup.
static func is_empty_map(ids: Dictionary) -> bool:
	for v in ids.values():
		if StringName(str(v)) != &"":
			return false
	return true

## The fitted part ids in SLOT ORDER, blanks omitted — for callers that want to enumerate what is on a gun
## (the screen's "Fitted" section, a tooltip) without re-deriving the enum walk. Order is stable by construction.
static func ids_of(ids: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for slot in WeaponData.MOD_SLOT_PROPS.size():
		var id := StringName(str(ids.get(slot, &"")))
		if id != &"":
			out.append(id)
	return out


# --- Fitment ----------------------------------------------------------------------------------------------

## Does `mod` fit `gun`? ⭐EMPTY `fits_weapon_ids` is UNIVERSAL — that is the authoring default, so a part that
## should go on everything is authored by leaving the list alone. Otherwise the gun's Item.id must be listed.
##
## Fitment lives on the PART, so shipping a scope for a new shotgun is one new .tres and zero edits to anything
## that already exists. This predicate deliberately says NOTHING about whether `gun` is a weapon at all, whether
## the slot is free, or whether the bench works that slot — those are separate, separately-messaged bench guards
## (weapon_bench.gd), and folding them in here would make one refusal reason stand for four different problems.
static func fits(mod: WeaponMod, gun: Item) -> bool:
	if mod == null or gun == null:
		return false
	if mod.fits_weapon_ids.is_empty():
		return true
	return mod.fits_weapon_ids.has(gun.id)


# --- The fold ----------------------------------------------------------------------------------------------

## Fold `ids` onto a FRESH copy of `template_weapon` and return it. `template_weapon` is untouched.
##
## Pass order is fixed and global — every SET across all fitted parts, then every ADD, then every MULT — which
## is what makes fit order irrelevant: a MULT always sees the summed base, never a half-built number that
## depended on which slot the player filled first. BOOL targets use `flag` (there is no sensible "add" to a
## true/false) and are written during the SET pass.
##
## An id `resolve` returns null for is DROPPED with a push_warning naming it, and its slot is re-stamped BLANK —
## so a save referencing a part that was deleted from the game comes back wearing the parts that still exist and
## HEALS ITSELF on the next capture, instead of carrying a dangling id forever.
##
## ⭐The six slot ids are re-stamped onto the returned block last (blanks included), so a folded WeaponData
## always describes itself: ItemDb.weapon_delta_for diffs the ids out of it, and the next rebuild reads them
## back. Nothing else in the game writes those fields.
static func rebuild(template_weapon: WeaponData, ids: Dictionary, resolve: Callable) -> WeaponData:
	if template_weapon == null:
		return null
	var fresh := template_weapon.duplicate() as WeaponData
	if fresh == null:
		return null

	# Resolve in ENUM ORDER, not dictionary order — this walk is the whole order-independence guarantee, and
	# it also fixes which slot wins a resource-override collision below (the later slot).
	var fitted: Array[WeaponMod] = []
	var stamped := {}
	for slot in WeaponData.MOD_SLOT_PROPS.size():
		var id := StringName(str(ids.get(slot, &"")))
		stamped[slot] = &""
		if id == &"":
			continue
		var mod: WeaponMod = null
		if resolve.is_valid():
			mod = resolve.call(id) as WeaponMod
		if mod == null:
			push_warning("WeaponModKit: unknown weapon mod '%s' in slot %d — dropped, slot cleared." % [id, slot])
			continue
		stamped[slot] = id
		fitted.append(mod)

	# Declared type per mod-targetable field, off the block we are about to write. Reflection once, not once
	# per delta line, and it is what tells an ADD on `max_ammo` to round while an ADD on `damage` does not.
	var types := _scalar_types(fresh)

	# Flatten every fitted part's lines into the three passes BEFORE applying any of them. Flattening first is
	# what keeps an unauthorable-property warning to one per line instead of one per pass.
	var sets: Array[Dictionary] = []
	var adds: Array[Dictionary] = []
	var mults: Array[Dictionary] = []
	for mod in fitted:
		for d in mod.deltas:
			if d == null or d.property == &"":
				continue
			var prop := String(d.property)
			if not types.has(prop):
				# Only reachable from a hand-edited .tres: WeaponStatDelta's dropdown offers exactly this set.
				# Loud, because a silent no-op is this system's worst failure — the part costs money and does nothing.
				push_warning("WeaponModKit: delta targets unknown WeaponData property '%s' — ignored." % prop)
				continue
			var t := int(types[prop])
			if t == TYPE_BOOL:
				sets.append({"prop": prop, "type": t, "value": d.flag})
				continue
			match d.op:
				WeaponStatDelta.Op.SET:
					sets.append({"prop": prop, "type": t, "value": d.amount})
				WeaponStatDelta.Op.MULT:
					mults.append({"prop": prop, "type": t, "value": d.amount})
				_:
					adds.append({"prop": prop, "type": t, "value": d.amount})

	# SET establishes, ADD adjusts, MULT scales. Two parts SETting the SAME property is an authoring conflict
	# with no right answer; slot enum order decides it, deterministically, rather than dictionary luck.
	for line in sets:
		if int(line["type"]) == TYPE_BOOL:
			fresh.set(String(line["prop"]), bool(line["value"]))
		else:
			_write_number(fresh, String(line["prop"]), int(line["type"]), float(line["value"]))
	for line in adds:
		var prop := String(line["prop"])
		_write_number(fresh, prop, int(line["type"]), float(fresh.get(prop)) + float(line["value"]))
	for line in mults:
		var prop := String(line["prop"])
		_write_number(fresh, prop, int(line["type"]), float(fresh.get(prop)) * float(line["value"]))

	# The RESOURCE overrides (§2.3) — assigned after the numbers because they are replacements, not arithmetic.
	# `fitted` is in slot enum order, so a later slot's non-null override wins over an earlier one: a MUZZLE
	# suppressor's fire sound beats a BARREL's, always, no matter which was fitted first.
	for mod in fitted:
		if mod.view_model_override != null:
			fresh.view_model = mod.view_model_override
		if mod.projectile_scene_override != null:
			fresh.projectile_scene = mod.projectile_scene_override
		if mod.on_hit_effect_override != null:
			fresh.on_hit_effect = mod.on_hit_effect_override
		if mod.fire_sound_override != null:
			fresh.audio = mod.fire_sound_override
		if mod.whiz_sound_override != null:
			fresh.whiz_sound = mod.whiz_sound_override
		if mod.reload_sound_override != null:
			fresh.reload_sound = mod.reload_sound_override
		if mod.caliber_override != &"":
			fresh.caliber = mod.caliber_override

	# Re-stamp the slot ids (blanks included) so the block describes itself — see the header note.
	for slot in WeaponData.MOD_SLOT_PROPS.size():
		fresh.set_mod_id(slot, StringName(str(stamped.get(slot, &""))))

	# ⭐The floor, once, at the end — see CLAMP_FLOORS.
	for prop in CLAMP_FLOORS:
		var name_s := String(prop)
		if not types.has(name_s):
			continue
		_write_number(fresh, name_s, int(types[name_s]), maxf(float(fresh.get(name_s)), float(CLAMP_FLOORS[prop])))

	return fresh


# --- The before/after report -------------------------------------------------------------------------------

## What changed between two stat blocks: {property name -> {"before": value, "after": value}}, changed
## properties ONLY. Measured over WeaponFields.ids() — the mod-targetable scalars — so the report can never
## mention a field a part was not allowed to move, and never mentions the six slot ids (they are bookkeeping,
## not a stat). Keys are Strings, matching WeaponFields; WeaponModInfo.compare_block paints them.
##
## Exact equality is deliberate, not sloppy: rebuild() always restarts from the template, so an untouched
## property is bit-identical to it — there is no drift for an epsilon to absorb, and an epsilon would instead
## hide a genuine hairline retune.
static func diff(before: WeaponData, after: WeaponData) -> Dictionary:
	var out := {}
	if before == null or after == null:
		return out
	for prop in WeaponFields.ids():
		var b: Variant = before.get(prop)
		var a: Variant = after.get(prop)
		if b != a:
			out[prop] = {"before": b, "after": a}
	return out


# --- Internals -----------------------------------------------------------------------------------------------

## {property name -> declared type} for the mod-targetable scalars on `weapon`. Same filter WeaponFields.ids()
## applies (SCRIPT_VARIABLE, BOOL/INT/FLOAT), computed on the LIVE object rather than read off that cached list,
## because this is the map the writes key on — the type must come from the very block being written.
static func _scalar_types(weapon: WeaponData) -> Dictionary:
	var out := {}
	for prop in weapon.get_property_list():
		if (int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var t := int(prop.get("type", TYPE_NIL))
		if not (t in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT]):
			continue
		out[String(prop["name"])] = t
	return out

## Write a number back into its declared type. An INT field ROUNDS (roundi, not truncation — a MULT landing on
## 19.999 must be 20 rounds, not 19); a FLOAT field takes the value as-is.
static func _write_number(weapon: WeaponData, prop: String, t: int, value: float) -> void:
	# An `if` and not a ternary: an int branch beside a float branch has no common type, so the ternary form
	# types as Variant and the analyzer flags it. set() takes a Variant either way.
	var out: Variant = value
	if t == TYPE_INT:
		out = roundi(value)
	weapon.set(prop, out)
