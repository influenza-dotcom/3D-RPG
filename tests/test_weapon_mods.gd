extends GutTest

## WEAPON MODS — the data spine (WeaponData's six slot fields), the authoring guard rails (WeaponFields /
## WeaponStatDelta), and THE FOLD (WeaponModKit.rebuild). Pure Resource logic, so everything here is off-tree:
## `.new()` a throwaway WeaponData / WeaponMod / WeaponStatDelta and release it with `= null`. No bench, no
## screen, no player — those are test_weapon_bench.gd / test_weapon_bench_screen_scene.gd / test_weapon_refit.gd.
##
## ⭐Three of these tests exist because the failure they catch is SILENT, and each is worth more than the rest
## put together:
##   • test_mod_slot_fields_are_storage_only_string_names + test_mod_ids_survive_resource_duplicate — a plain
##     `var` (usage 4096) is dropped by Resource.duplicate() with no error anywhere, so every acquired weapon
##     would come back stock. @export_storage (4098) is the whole persistence story.
##   • test_weapon_fields_are_a_subset_of_the_delta_able_set — the dropdown a designer authors from is a subset
##     of what the save can carry, so "a delta that reverts on quickload" is UNAUTHORABLE rather than merely rare.
##   • test_clamp_floors — a MULT to zero on attack_speed stalls the fire loop AND poisons power_score(), which
##     ranks every NPC's loadout.

const WeaponFields = preload("res://scripts/items/weapon_fields.gd")
const WeaponModKit = preload("res://scripts/items/weapon_mod_kit.gd")

const WEAPONS_DIR := "res://resources/weapons/"
const ITEMS_DIR := "res://resources/items/"


# --- Fixtures ------------------------------------------------------------------------------------------------

## A hand-built stat block with known round numbers, so an assertion reads as arithmetic rather than as a
## restatement of whatever pistol.tres happens to be tuned to this week. Tests that must speak about SHIPPED
## content name the .tres explicitly instead.
func _template() -> WeaponData:
	var w := WeaponData.new()
	w.damage = 1.0
	w.effective_range = 20.0
	w.pellet_spread = 0.1
	w.pellet_count = 1
	w.max_ammo = 10
	w.attack_speed = 0.1
	w.reload_time = 1.5
	w.noise_radius_mult = 1.0
	w.hip_sway_mult = 1.0
	w.has_muzzle_flash = true
	return w

func _delta(prop: StringName, op: WeaponStatDelta.Op, amount: float = 0.0, flag: bool = false) -> WeaponStatDelta:
	var d := WeaponStatDelta.new()
	d.property = prop
	d.op = op
	d.amount = amount
	d.flag = flag
	return d

## `deltas` is an untyped Array copied in via Array.assign() — a bare `[...]` literal at a call site is NOT
## automatically an Array[WeaponStatDelta], and assigning one straight across fails the typed-array check.
func _mod(slot: WeaponData.ModSlot, deltas: Array = []) -> WeaponMod:
	var m := WeaponMod.new()
	m.slot = slot
	var typed: Array[WeaponStatDelta] = []
	typed.assign(deltas)
	m.deltas = typed
	return m

## A resolve Callable over a hand-built {id -> WeaponMod} table — the test's stand-in for
## ItemDb._resolve_weapon_mod. Deliberately UNTYPED so an unknown id returns null instead of tripping a
## typed-lambda return check; rebuild() casts the result itself.
func _resolver(parts: Dictionary) -> Callable:
	return func(id): return parts.get(StringName(str(id)), null)

## An ids map (all six slots) with the given {slot -> id} pairs filled in.
func _ids(pairs: Dictionary) -> Dictionary:
	var out := WeaponModKit.slot_map(null)
	for slot in pairs:
		out[slot] = pairs[slot]
	return out

## First entry in get_property_list() whose name matches, else {}.
func _property(obj: Object, prop_name: String) -> Dictionary:
	for p in obj.get_property_list():
		if p.get("name", "") == prop_name:
			return p
	return {}

func _list_tres(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")  # exported builds may append .remap to packed resources
		if f.ends_with(".tres") or f.ends_with(".res"):
			out.append(dir_path.path_join(f))
	return out


# --- The slot vocabulary -------------------------------------------------------------------------------------

func test_mod_slot_props_matches_the_enum() -> void:
	# MOD_SLOT_PROPS is indexed BY the enum ordinal (WeaponData.mod_id/set_mod_id), so a length or ordering
	# drift silently re-points every fitted part one slot over — and old saves with it.
	assert_eq(WeaponData.MOD_SLOT_PROPS.size(), WeaponData.ModSlot.size(),
		"MOD_SLOT_PROPS must have exactly one row per ModSlot entry — it is indexed by the enum ordinal")
	assert_eq(WeaponData.MOD_SLOT_PROPS.size(), 6,
		"the FO4 slot vocabulary is six: RECEIVER, BARREL, MAGAZINE, SIGHT, MUZZLE, STOCK")
	var seen := {}
	for prop in WeaponData.MOD_SLOT_PROPS:
		assert_false(seen.has(prop), "MOD_SLOT_PROPS must not repeat a property name — '%s' appears twice" % prop)
		seen[prop] = true

func test_mod_slot_fields_are_storage_only_string_names() -> void:
	# ⭐THE @export_storage KEYSTONE. STORAGE is what makes Resource.duplicate() carry the value; SCRIPT_VARIABLE
	# is what ItemDb._is_saved_weapon_property requires; the ABSENCE of EDITOR is what stops a designer typing a
	# part id into a weapon TEMPLATE and giving every instance of that gun a permanent non-empty delta.
	# A bare `var` fails the STORAGE half; a visible `@export` fails the EDITOR half.
	var w := WeaponData.new()
	for prop_name in WeaponData.MOD_SLOT_PROPS:
		var p := _property(w, String(prop_name))
		assert_false(p.is_empty(), "WeaponData must declare the slot field '%s'" % prop_name)
		var usage := int(p.get("usage", 0))
		assert_true((usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0,
			"'%s' must be a SCRIPT_VARIABLE or ItemDb's weapon_delta will not carry it" % prop_name)
		assert_true((usage & PROPERTY_USAGE_STORAGE) != 0,
			"'%s' must have STORAGE usage (@export_storage) or Resource.duplicate() drops it silently" % prop_name)
		assert_true((usage & PROPERTY_USAGE_EDITOR) == 0,
			"'%s' must be HIDDEN from the inspector — a value authored on a template poisons every instance" % prop_name)
		assert_eq(int(p.get("type", TYPE_NIL)), TYPE_STRING_NAME,
			"'%s' must be a StringName (the part's Item.id) — TYPE_STRING_NAME is already delta-able" % prop_name)
	w = null

func test_mod_ids_survive_resource_duplicate() -> void:
	# ⭐The bare-var trap made loud: ItemDb.make_weapon_item / Item.clone_unique both go through duplicate(),
	# so if this ever regresses every acquired or restored weapon comes back stock with no error anywhere.
	var w := _template()
	w.set_mod_id(WeaponData.ModSlot.BARREL, &"mod_long_barrel")
	var copy := w.duplicate() as WeaponData
	assert_eq(copy.mod_id(WeaponData.ModSlot.BARREL), StringName("mod_long_barrel"),
		"Resource.duplicate() must carry the fitted slot ids — that is what @export_storage buys")
	assert_eq(copy.mod_id(WeaponData.ModSlot.MUZZLE), StringName(""),
		"an unfitted slot duplicates as blank")
	w = null
	copy = null

func test_mod_fields_are_delta_able() -> void:
	# The six ids (and the new noise_radius_mult lever) must ride the EXISTING weapon_delta seam — no new save
	# key, no new write site. _is_saved_weapon_property is exactly what all three capture sites filter on.
	var w := _template()
	var wanted := PackedStringArray()
	for prop_name in WeaponData.MOD_SLOT_PROPS:
		wanted.append(String(prop_name))
	wanted.append("noise_radius_mult")
	for prop_name in wanted:
		var p := _property(w, prop_name)
		assert_false(p.is_empty(), "WeaponData must declare '%s'" % prop_name)
		assert_true(ItemDb._is_saved_weapon_property(p),
			"'%s' must pass ItemDb._is_saved_weapon_property or a save cannot carry it" % prop_name)
	w = null

func test_mod_id_accessors_are_independent_per_slot() -> void:
	# mod_id/set_mod_id are the ONE place the enum maps to a field; an off-by-one here writes the wrong slot.
	var w := _template()
	for slot in WeaponData.MOD_SLOT_PROPS.size():
		w.set_mod_id(slot, StringName("part_%d" % slot))
	for slot in WeaponData.MOD_SLOT_PROPS.size():
		assert_eq(w.mod_id(slot), StringName("part_%d" % slot),
			"slot %d must read back exactly what was stamped into it" % slot)
	assert_eq(w.fitted_mod_count(), 6, "all six slots filled reads as 6/6")
	w.set_mod_id(WeaponData.ModSlot.SIGHT, &"")
	assert_eq(w.mod_id(WeaponData.ModSlot.SIGHT), StringName(""), "clearing a slot writes a blank id")
	assert_eq(w.fitted_mod_count(), 5, "fitted_mod_count must not count a cleared slot")
	# Out of range is a deliberate silent no-op: a broken part .tres must not crash a whole bench transaction.
	w.set_mod_id(99, &"nonsense")
	assert_eq(w.mod_id(99), StringName(""), "an out-of-range slot reads blank rather than erroring")
	w = null

func test_every_shipped_weapon_template_ships_no_mods() -> void:
	# A template with a fitted id would make weapon_delta_for report a permanent non-empty delta for EVERY
	# instance of that gun — and would be invisible in the inspector, so nobody would ever find it.
	var files := _list_tres(WEAPONS_DIR)
	var checked := 0
	for path in files:
		var w := load(path) as WeaponData
		if w == null:
			continue  # resources/weapons/ also holds a few loose audio/texture assets
		checked += 1
		for slot in WeaponData.MOD_SLOT_PROPS.size():
			assert_eq(w.mod_id(slot), StringName(""),
				"%s must ship with slot %d BLANK — only WeaponBench ever writes a slot id" % [path, slot])
	assert_gt(checked, 0, "there must be at least one WeaponData .tres in %s to validate" % WEAPONS_DIR)


# --- The authoring guard rail: WeaponFields ---------------------------------------------------------------

func test_weapon_fields_are_a_subset_of_the_delta_able_set() -> void:
	# ⭐This is what makes "a delta the save silently reverts on load" UNAUTHORABLE: WeaponStatDelta.property's
	# only dropdown source is WeaponFields, and every name it offers round-trips through _is_weapon_delta_type.
	var w := WeaponData.new()
	var offered := WeaponFields.ids()
	assert_gt(offered.size(), 0, "WeaponFields.ids() must find WeaponData's scalar exports by reflection")
	for prop_name in offered:
		var p := _property(w, prop_name)
		assert_false(p.is_empty(), "WeaponFields offered '%s' but WeaponData has no such property" % prop_name)
		assert_true(ItemDb._is_saved_weapon_property(p),
			"WeaponFields must only offer properties the save can carry — '%s' cannot round-trip" % prop_name)
	# ...and it must EXCLUDE the fold's own bookkeeping: a delta writing a slot id is a part re-stamping a slot
	# mid-rebuild, which is a loop, not a stat change.
	for prop_name in WeaponData.MOD_SLOT_PROPS:
		assert_false(offered.has(String(prop_name)),
			"WeaponFields must not offer the slot bookkeeping field '%s' as a delta target" % prop_name)
	assert_true(offered.has("noise_radius_mult"),
		"noise_radius_mult is the suppressor's lever — it must be delta-targetable")
	w = null


# --- The fold: WeaponModKit.rebuild --------------------------------------------------------------------------

func test_rebuild_never_mutates_the_template() -> void:
	# ⭐Mutating the template would persist NOTHING (the template IS weapon_delta_for's baseline) while silently
	# buffing every instance of that gun in the world — NPC hands and shop shelves included.
	var tmpl := _template()
	var before_damage := tmpl.damage
	var parts := {&"boost": _mod(WeaponData.ModSlot.RECEIVER, [_delta(&"damage", WeaponStatDelta.Op.MULT, 2.0)])}
	var fresh := WeaponModKit.rebuild(tmpl, _ids({WeaponData.ModSlot.RECEIVER: &"boost"}), _resolver(parts))
	assert_eq(tmpl.damage, before_damage, "rebuild must never write to the template it folds from")
	assert_eq(tmpl.mod_id(WeaponData.ModSlot.RECEIVER), StringName(""),
		"rebuild must not stamp a slot id onto the template either")
	assert_ne(fresh, tmpl, "rebuild must return a NEW WeaponData object — the equip seam's identity gate needs one")
	assert_eq(fresh.damage, 2.0, "the fold applied the MULT to the copy")
	assert_eq(fresh.mod_id(WeaponData.ModSlot.RECEIVER), StringName("boost"),
		"the returned block re-stamps its own slot ids, so it describes itself")
	tmpl = null
	fresh = null

func test_rebuild_is_order_independent_and_idempotent() -> void:
	# Slots are walked in ENUM order, never dictionary order — a Dictionary's insertion order must not be able
	# to move a number. And because the fold always restarts from the pristine template, re-folding the same
	# set is a no-op rather than a compounding MULT.
	var tmpl := _template()
	var parts := {
		&"barrel": _mod(WeaponData.ModSlot.BARREL, [_delta(&"effective_range", WeaponStatDelta.Op.ADD, 8.0)]),
		&"recv": _mod(WeaponData.ModSlot.RECEIVER, [_delta(&"damage", WeaponStatDelta.Op.MULT, 1.5)]),
	}
	var resolve := _resolver(parts)
	var a_ids := {}
	a_ids[WeaponData.ModSlot.BARREL] = &"barrel"
	a_ids[WeaponData.ModSlot.RECEIVER] = &"recv"
	var b_ids := {}
	b_ids[WeaponData.ModSlot.RECEIVER] = &"recv"
	b_ids[WeaponData.ModSlot.BARREL] = &"barrel"
	var a := WeaponModKit.rebuild(tmpl, _ids(a_ids), resolve)
	var b := WeaponModKit.rebuild(tmpl, _ids(b_ids), resolve)
	assert_eq(WeaponModKit.diff(a, b).size(), 0,
		"the same fitted set in two dictionary orders must fold to byte-identical scalars")
	# Idempotence: folding the ALREADY-FOLDED block's own id map from the template again reproduces it exactly.
	var again := WeaponModKit.rebuild(tmpl, WeaponModKit.slot_map(a), resolve)
	assert_eq(WeaponModKit.diff(a, again).size(), 0, "re-folding the same set must not compound")
	assert_eq(again.damage, 1.5, "the MULT applied once, not twice")
	tmpl = null
	a = null
	b = null
	again = null

func test_strip_returns_exactly_to_the_template() -> void:
	# Removing a part must return the AUTHORED numbers, not "close enough" — that is the whole reason the fold
	# restarts from the template instead of trying to invert its own arithmetic.
	var tmpl := _template()
	var parts := {&"barrel": _mod(WeaponData.ModSlot.BARREL, [
		_delta(&"effective_range", WeaponStatDelta.Op.ADD, 8.0),
		_delta(&"pellet_spread", WeaponStatDelta.Op.MULT, 0.75),
		_delta(&"max_ammo", WeaponStatDelta.Op.MULT, 2.0),
	])}
	var resolve := _resolver(parts)
	var fitted := WeaponModKit.rebuild(tmpl, _ids({WeaponData.ModSlot.BARREL: &"barrel"}), resolve)
	assert_ne(WeaponModKit.diff(tmpl, fitted).size(), 0, "sanity: the part actually changed something")
	var stripped := WeaponModKit.rebuild(tmpl, _ids({}), resolve)
	assert_eq(WeaponModKit.diff(tmpl, stripped).size(), 0,
		"pulling every part must return every scalar to the template's authored value, with no float drift")
	assert_eq(stripped.fitted_mod_count(), 0, "a stripped block reports no fitted slots")
	tmpl = null
	fitted = null
	stripped = null

func test_pass_order_is_set_then_add_then_mult() -> void:
	# EVERY set, then EVERY add, then EVERY mult — across all fitted parts at once. Applied per-part instead,
	# (10+5)*2 and (10*2)+5 would both be reachable depending on which slot the player filled first.
	var tmpl := _template()
	var parts := {
		&"mult": _mod(WeaponData.ModSlot.RECEIVER, [_delta(&"damage", WeaponStatDelta.Op.MULT, 2.0)]),
		&"add": _mod(WeaponData.ModSlot.BARREL, [_delta(&"damage", WeaponStatDelta.Op.ADD, 5.0)]),
		&"set": _mod(WeaponData.ModSlot.STOCK, [_delta(&"damage", WeaponStatDelta.Op.SET, 10.0)]),
	}
	var ids := _ids({
		WeaponData.ModSlot.RECEIVER: &"mult",
		WeaponData.ModSlot.BARREL: &"add",
		WeaponData.ModSlot.STOCK: &"set",
	})
	var fresh := WeaponModKit.rebuild(tmpl, ids, _resolver(parts))
	assert_eq(fresh.damage, 30.0,
		"SET 10 then ADD 5 then MULT 2 = 30 — the RECEIVER's MULT must not run before the STOCK's SET")
	tmpl = null
	fresh = null

func test_clamp_floors() -> void:
	# ⭐A MULT to zero must never produce a gun the engine cannot fire. attack_speed is SECONDS PER SHOT: at 0
	# the cooldown never elapses and WeaponData.power_score() divides by it, poisoning every NPC equip ranking.
	var tmpl := _template()
	var parts := {&"zero": _mod(WeaponData.ModSlot.RECEIVER, [
		_delta(&"attack_speed", WeaponStatDelta.Op.MULT, 0.0),
		_delta(&"max_ammo", WeaponStatDelta.Op.MULT, 0.0),
		_delta(&"pellet_count", WeaponStatDelta.Op.MULT, 0.0),
		_delta(&"effective_range", WeaponStatDelta.Op.ADD, -100.0),
		_delta(&"noise_radius_mult", WeaponStatDelta.Op.MULT, -1.0),
		_delta(&"reload_time", WeaponStatDelta.Op.ADD, -50.0),
	])}
	var fresh := WeaponModKit.rebuild(tmpl, _ids({WeaponData.ModSlot.RECEIVER: &"zero"}), _resolver(parts))
	assert_gte(fresh.attack_speed, 0.01, "attack_speed must be floored at 0.01s — 0 stalls the fire loop")
	assert_gte(fresh.max_ammo, 1, "max_ammo must be floored at 1 — a 0-round clip cannot fire")
	assert_gte(fresh.pellet_count, 1, "pellet_count must be floored at 1 — a 0-pellet shot hits nothing")
	assert_gte(fresh.effective_range, 0.0, "effective_range must never go negative")
	assert_gte(fresh.noise_radius_mult, 0.0, "noise_radius_mult must never go negative")
	assert_gte(fresh.reload_time, 0.0, "reload_time must never go negative")
	assert_gt(fresh.power_score(), 0.0, "a clamped block must still produce a finite, positive power_score")
	tmpl = null
	fresh = null

func test_unknown_mod_id_is_dropped_with_a_warning_and_the_slot_is_cleared() -> void:
	# The SAVE SELF-HEALS: a part deleted from the game resolves to null, so its slot is re-stamped blank and
	# the parts that still exist are kept. (rebuild also push_warnings the id — a warning cannot fail a GUT run,
	# and this is the one place a player-visible loss happens, so it must be traceable in the log.)
	var tmpl := _template()
	var parts := {&"barrel": _mod(WeaponData.ModSlot.BARREL, [_delta(&"effective_range", WeaponStatDelta.Op.ADD, 8.0)])}
	var ids := _ids({WeaponData.ModSlot.BARREL: &"barrel", WeaponData.ModSlot.MUZZLE: &"mod_deleted_last_patch"})
	var fresh := WeaponModKit.rebuild(tmpl, ids, _resolver(parts))
	assert_not_null(fresh, "an unresolvable part id must never fail the whole fold")
	assert_eq(fresh.effective_range, 28.0, "the parts that still resolve must still apply")
	assert_eq(fresh.mod_id(WeaponData.ModSlot.BARREL), StringName("barrel"), "the surviving slot keeps its id")
	assert_eq(fresh.mod_id(WeaponData.ModSlot.MUZZLE), StringName(""),
		"the unresolvable slot must be re-stamped BLANK so the next capture writes a healed delta")
	tmpl = null
	fresh = null

func test_bool_targets_use_flag_not_amount() -> void:
	# There is no sensible "add 1" to a true/false, so a BOOL target reads `flag` and IGNORES both `amount` and
	# `op` — it is written during the SET pass whatever the authored op says. The suppressor's "no muzzle flash".
	var tmpl := _template()
	tmpl.auto_fire = false  # so a `true` result below can only have come from the part's `flag`
	assert_true(tmpl.has_muzzle_flash, "sanity: the template ships with a muzzle flash")
	var parts := {
		&"quiet": _mod(WeaponData.ModSlot.MUZZLE, [_delta(&"has_muzzle_flash", WeaponStatDelta.Op.SET, 1.0, false)]),
		&"odd": _mod(WeaponData.ModSlot.STOCK, [_delta(&"auto_fire", WeaponStatDelta.Op.MULT, 0.0, true)]),
	}
	var fresh := WeaponModKit.rebuild(tmpl, _ids({
		WeaponData.ModSlot.MUZZLE: &"quiet", WeaponData.ModSlot.STOCK: &"odd",
	}), _resolver(parts))
	assert_false(fresh.has_muzzle_flash,
		"a BOOL target must take `flag` (false) and ignore a non-zero `amount`")
	assert_true(fresh.auto_fire, "a BOOL target must apply even when the authored op is MULT — op is ignored")
	tmpl = null
	fresh = null

func test_resource_overrides_apply() -> void:
	# ⭐The seven override slots are the WHOLE REASON the save stores part IDS: these types are exactly what
	# ItemDb._is_weapon_delta_type rejects, so a system that wrote them onto the instance would have them
	# silently revert on quickload. Here they come back off the part's .tres on every load.
	var tmpl := _template()
	tmpl.caliber = &"9mm"
	var view := PackedScene.new()
	var proj := PackedScene.new()
	var effect := StatusEffect.new()
	var fire := AudioStreamWAV.new()
	var whiz := AudioStreamWAV.new()
	var reload := AudioStreamWAV.new()
	var m := _mod(WeaponData.ModSlot.RECEIVER)
	m.view_model_override = view
	m.projectile_scene_override = proj
	m.on_hit_effect_override = effect
	m.fire_sound_override = fire
	m.whiz_sound_override = whiz
	m.reload_sound_override = reload
	m.caliber_override = &"7.62"
	var fresh := WeaponModKit.rebuild(tmpl, _ids({WeaponData.ModSlot.RECEIVER: &"kit"}), _resolver({&"kit": m}))
	assert_eq(fresh.view_model, view, "view_model_override must replace the view model — the gun you SEE changes")
	assert_eq(fresh.projectile_scene, proj, "projectile_scene_override must replace the projectile")
	assert_eq(fresh.on_hit_effect, effect, "on_hit_effect_override must replace the on-hit effect")
	assert_eq(fresh.audio, fire, "fire_sound_override must replace WeaponData.audio — the suppressor's voice")
	assert_eq(fresh.whiz_sound, whiz, "whiz_sound_override must replace the supersonic crack")
	assert_eq(fresh.reload_sound, reload, "reload_sound_override must replace the reload sfx")
	assert_eq(fresh.caliber, StringName("7.62"), "a non-blank caliber_override must convert the calibre")
	# A blank override leaves the template's value alone — that is what makes the seven fields independent.
	var bare := _mod(WeaponData.ModSlot.STOCK)
	var untouched := WeaponModKit.rebuild(tmpl, _ids({WeaponData.ModSlot.STOCK: &"bare"}), _resolver({&"bare": bare}))
	assert_eq(untouched.caliber, StringName("9mm"), "a blank caliber_override must not wipe the template's calibre")
	assert_null(untouched.view_model, "a null view_model_override must not wipe the template's view model")
	tmpl = null
	fresh = null
	untouched = null
	m = null
	bare = null
	view = null
	proj = null
	effect = null
	fire = null
	whiz = null
	reload = null

func test_fits_gate() -> void:
	# Fitment lives on the PART: an EMPTY fits_weapon_ids is UNIVERSAL (the authoring default), otherwise the
	# gun's Item.id must be listed. This predicate says nothing about slots or bench capability on purpose —
	# those are separately-messaged bench guards, and merging them would make one refusal stand for four causes.
	var pistol := Item.new()
	pistol.id = &"pistol"
	var shotgun := Item.new()
	shotgun.id = &"shotgun"
	var universal := _mod(WeaponData.ModSlot.MUZZLE)
	assert_true(WeaponModKit.fits(universal, pistol), "an empty fits_weapon_ids fits everything")
	assert_true(WeaponModKit.fits(universal, shotgun), "an empty fits_weapon_ids fits everything")
	var pistol_only := _mod(WeaponData.ModSlot.MUZZLE)
	var fitment: Array[StringName] = [&"pistol", &"smg"]
	pistol_only.fits_weapon_ids = fitment
	assert_true(WeaponModKit.fits(pistol_only, pistol), "a listed weapon id fits")
	assert_false(WeaponModKit.fits(pistol_only, shotgun), "an unlisted weapon id must be refused")
	assert_false(WeaponModKit.fits(null, pistol), "a null part fits nothing")
	assert_false(WeaponModKit.fits(pistol_only, null), "nothing fits a null gun")
	pistol = null
	shotgun = null
	universal = null
	pistol_only = null

func test_diff_reports_only_changed_properties() -> void:
	# The footer preview is built from this, so a spurious row ("Damage 1 → 1") would read as a lie about what
	# the player is about to pay for. Measured over WeaponFields only, so the six slot ids never show up as stats.
	var tmpl := _template()
	var parts := {&"barrel": _mod(WeaponData.ModSlot.BARREL, [_delta(&"effective_range", WeaponStatDelta.Op.ADD, 8.0)])}
	var fresh := WeaponModKit.rebuild(tmpl, _ids({WeaponData.ModSlot.BARREL: &"barrel"}), _resolver(parts))
	var d := WeaponModKit.diff(tmpl, fresh)
	assert_eq(d.size(), 1, "exactly one property changed, so the report must have exactly one row")
	assert_true(d.has("effective_range"), "the changed property must be named in the report")
	assert_eq(float(d["effective_range"]["before"]), 20.0, "the report must carry the BEFORE value")
	assert_eq(float(d["effective_range"]["after"]), 28.0, "the report must carry the AFTER value")
	assert_false(d.has("mod_barrel"), "the slot ids are bookkeeping, not stats — diff must never report one")
	assert_eq(WeaponModKit.diff(tmpl, tmpl).size(), 0, "an unchanged block reports no rows")
	assert_eq(WeaponModKit.diff(null, fresh).size(), 0, "a null side degrades to an empty report, never a crash")
	tmpl = null
	fresh = null
	d = {}


# --- The shipped content ---------------------------------------------------------------------------------

func test_all_shipped_mod_items_are_valid() -> void:
	# Every authored part, swept off disk — parts are ordinary Items in resources/items/, so ItemDb's boot scan
	# already registers them and there is no separate roster to keep in sync with this test.
	# `weapon_mod` is read duck-typed so this test is meaningful the moment Item gains the field.
	var found := 0
	for path in _list_tres(ITEMS_DIR):
		var it := load(path) as Item
		if it == null:
			continue
		var payload: Variant = it.get("weapon_mod")
		if payload == null:
			continue
		var mod := payload as WeaponMod
		assert_not_null(mod, "%s: weapon_mod must be a WeaponMod resource" % path)
		if mod == null:
			continue
		found += 1
		assert_ne(it.id, StringName(""), "%s: a part needs a non-blank Item.id — the save keys on it" % path)
		assert_gt(it.value, 0.0, "%s: a part needs a value > 0 — the bench prices labour off it" % path)
		assert_eq(it.category, Item.Category.MISC,
			"%s: a part is a MISC item — a WEAPON category would file it under ItemDb._by_weapon" % path)
		# Duck-called: Item.is_weapon_mod() lands in Step 3, and a hard reference would stop this whole file
		# COMPILING before then. has_method is the assertion — the helper must exist, not just the field.
		assert_true(it.has_method("is_weapon_mod") and bool(it.call("is_weapon_mod")),
			"%s: Item.is_weapon_mod() must exist and key on the weapon_mod payload" % path)
		assert_false(it.is_holdable(),
			"%s: a part is FITTED, never carried as a physics prop — is_holdable() must exclude it" % path)
		assert_between(int(mod.slot), 0, WeaponData.MOD_SLOT_PROPS.size() - 1,
			"%s: slot must be a real ModSlot ordinal" % path)
		for d in mod.deltas:
			assert_not_null(d, "%s: a null row in `deltas` is an authoring slip" % path)
			if d == null:
				continue
			assert_true(WeaponFields.ids().has(String(d.property)),
				"%s: delta targets '%s', which is not a mod-targetable WeaponData field" % [path, d.property])
		for weapon_id in mod.fits_weapon_ids:
			var target := ItemDb.item_by_id(weapon_id)
			assert_not_null(target, "%s: fits_weapon_ids names '%s', which is not a registered item" % [path, weapon_id])
			if target != null:
				assert_true(target.is_weapon(), "%s: fits_weapon_ids names '%s', which is not a WEAPON" % [path, weapon_id])
	if found == 0:
		# Steps 1-2 land the spine and the fold; the ten shipped parts arrive in Step 6. This goes green on its
		# own the moment the first part .tres exists — it is not skipped because the check is optional.
		pending("no weapon-mod parts authored in %s yet — Step 6 content" % ITEMS_DIR)
		return
	assert_gt(found, 0, "at least one weapon part must ship")
