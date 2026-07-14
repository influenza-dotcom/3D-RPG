class_name PassiveItemBuffs
extends Node

## @system Passive Item Buffs
## @seam Exposes a stat_modifier/speed_multiplier/apply_effect surface Character sums/multiplies; held strength re-stamps via CharacterStats.restamp_derived; serializes nothing.
## @risk If max_hp is ever serialized as a stored number, the held +HP/+carry delta double-counts each reload; the carrier silently gains stats, no error.
## @risk If _restamp tracked the ideal delta instead of restamp_derived's real post-floor return, dropping a negative-strength item silently inflates max_hp/carry above base.
## @risk If apply_effect or the method names drift from Character's has_method scanner, every held buff silently stops folding into live stats/speed, no crash.
## @test res://tests/test_passive_item_buffs.gd
## Dota / ARTS-style PASSIVE ITEM BUFFS. Any Item carried in this Character's backpack whose `held_passive_effect`
## (a StatusEffect used purely as a data payload) is set grants that effect's `stat_modifiers` + `speed_multiplier`
## WHILE HELD — no equip step, on the instant it enters the bag and off the instant it leaves. Built in
## Character._ready (both Player and NPC), so an NPC authored to carry a buff item benefits too.
##
## HOW IT FOLDS INTO GAMEPLAY (the LIVE stats). This node exposes the SAME duck-typed surface a
## StatusEffectManager does — stat_modifier(stat) + speed_multiplier() (+ a no-op apply_effect() so Character's
## scanner recognises it as a buff source) — and Character.status_stat_modifier / status_move_multiplier SUM /
## PRODUCT across every such child. So agility (move/jump), gunplay (weapon damage / sway), streetwise (shop prices
## + reputation), stealth (detection) and pickpocket pick up held-item buffs automatically at their existing live
## seams, with no per-frame work here — recompute happens only when the bag changes.
##
## STRENGTH is the exception. Its carry_capacity / max_hp are spawn-stamped and NOT read live, so a held modifier
## to strength is RE-STAMPED here as a running DELTA on the host's max_hp / carry_capacity — via the shared
## CharacterStats.restamp_derived chokepoint LevelUp / PerkManager also use — recomputed whenever the bag changes so dropping a +STR trinket removes EXACTLY what
## it added (hp clamped so a wounded carrier is never over-healed, never pushed below 1). CARRY_PER_STRENGTH /
## HP_PER_STRENGTH live on CharacterStats, so a held +strength item grants the same carry + max HP a level-up of
## that size would. (Its melee_damage_mult IS live, but a HELD strength buff is intentionally NOT folded into melee —
## stat_modifier() returns 0 for strength — so held strength stays a carry/HP item; TIMED strength effects do fold
## into melee via status_stat_modifier at the swing seam.)
##
## STACKING. By default a buff scales with how many copies are held (count, by Item.id). An Item flagged
## `passive_unique` counts as 1 no matter how many are carried (Dota "unique" items).
##
## SAVE / LOAD: nothing to serialize. The pool is a PURE function of the (already-saved) inventory. On load,
## CharacterInventory.restore_stack() fires `changed` as each saved stack lands and the pool rebuilds; max_hp isn't
## saved as a number (it re-derives from the stat sheet at spawn, then this adds the held delta on top), so the
## +HP buff can never double-count across a save.

## The Character that owns this pool — set by the host BEFORE add_child. Duck-typed access (get/set on
## _host.inventory / max_hp / hp / carry_capacity), matching PerkManager, so a test stub without a full Character works.
var _host: Node = null

## Live-stat additive pool: String stat -> summed float bonus. Holds the live multiplier stats
## (gunplay/agility/streetwise/stealth/pickpocket); strength is routed to the re-stamp, not here. Read by stat_modifier().
var _pool: Dictionary = {}
## Product of every held item's speed_multiplier (1.0 = none). Read by speed_multiplier().
var _speed: float = 1.0

## The max_hp / carry_capacity we have ACTUALLY added to the host (post-floor). A recompute applies only the DELTA
## from these, so a removed item takes back exactly what it gave. Tracked here (never recomputed from the host's
## live fields) because the stat->derived formulas are LINEAR, so deltas telescope back to zero on the last item
## leaving. We accumulate the REAL applied change, not the ideal target — so a negative-strength item that hits the
## max_hp floor still telescopes exactly (storing the ideal would over-restore on drop and inflate max_hp).
var _applied_hp: float = 0.0
var _applied_carry: float = 0.0

## Collapse a burst of inventory.changed (a multi-stack load restore fires one per stack; a buy/sell fires several)
## into ONE recompute at idle, mirroring the Player's autosave debounce.
var _dirty: bool = false

# --- duck-typed buff-source surface (matched by Character.status_stat_modifier / status_move_multiplier) ---

## Additive modifier for a LIVE stat while these items are held. Returns 0 for strength — a held strength buff is
## applied by re-stamping max_hp / carry_capacity (see _recompute / _restamp), not exposed as a live modifier.
func stat_modifier(stat: StringName) -> float:
	return float(_pool.get(String(stat), 0.0))

## Product of held items' speed_multipliers (1.0 = none) — folded into locomotion by Character.status_move_multiplier.
func speed_multiplier() -> float:
	return _speed

## No-op — exists ONLY so Character's duck-typed scanner (matches a child with stat_modifier / speed_multiplier AND
## apply_effect) recognises this node as a buff source alongside the StatusEffectManager. Held buffs are recomputed
## in bulk from inventory, never applied one at a time, so there is nothing to do here.
func apply_effect(_effect) -> void:
	pass

# --- recompute ---

## Connected to CharacterInventory.changed in Character._ready. Debounced: mark dirty + recompute once at idle so a
## multi-stack restore or a rapid buy/sell burst collapses to a single pass.
func on_inventory_changed() -> void:
	if _dirty:
		return
	_dirty = true
	call_deferred(&"_recompute")

## Rebuild the whole pool from the current backpack contents, then re-stamp the strength-derived
## max_hp / carry_capacity. Idempotent — safe to run as many times as `changed` fires.
func _recompute() -> void:
	_dirty = false
	if not is_instance_valid(_host):
		return
	var old_stamina_max := float(_host.call(&"stamina_max")) if _host.has_method(&"stamina_max") else 0.0
	var inv = _host.get(&"inventory")
	var pool: Dictionary = {}
	var speed := 1.0
	var str_points := 0.0
	if inv != null:
		var seen: Dictionary = {}  # aggregate each item KIND once; count_of_id already sums its stacks
		for row in inv.contents():
			var item: Item = row["item"]
			# A blank id can't be counted by kind (or save/load-tracked), so a passive needs one — skip if missing.
			if item == null or item.held_passive_effect == null or String(item.id) == "":
				continue
			if seen.has(item.id):
				continue
			seen[item.id] = true
			var fx: StatusEffect = item.held_passive_effect
			var n: int = 1 if item.passive_unique else int(inv.count_of_id(item.id))
			if n <= 0:
				continue
			for k in fx.stat_modifiers:
				var key := String(k)
				var amount := float(fx.stat_modifiers[k]) * float(n)
				match key:
					"strength": str_points += amount  # re-stamped onto carry/max_hp, not a live modifier
					_: pool[key] = float(pool.get(key, 0.0)) + amount
			if fx.speed_multiplier != 1.0:
				speed *= pow(fx.speed_multiplier, n)
	_pool = pool
	_speed = speed
	# The re-stamp chokepoint applies the strength->max_hp/carry delta AND re-seeds the endurance stamina cap
	# (via old_stamina_max, captured above before the pool moved) — a single call, no separate stamina step.
	_restamp(str_points, old_stamina_max)

## Re-stamp the strength-derived carry_capacity / max_hp as a DELTA from what we last applied, so held
## +HP/+carry items add on pickup and take back EXACTLY that on drop — through the shared
## CharacterStats.restamp_derived chokepoint (linear formula; hp clamped to [1, new max] so removing a +HP item
## while wounded can't over-heal or drop below 1). `old_stamina_max` (captured before the pool moved) lets the
## chokepoint re-seed the endurance stamina cap in the same call. We accumulate the REAL applied (post-floor) delta
## the chokepoint RETURNS, not the ideal target, so pickup and drop stay EXACT inverses even when a negative-strength
## item drives the value into its floor (storing the ideal would over-restore on drop and inflate the value).
func _restamp(str_points: float, old_stamina_max: float) -> void:
	if not is_instance_valid(_host):
		return
	var target_hp := str_points * CharacterStats.HP_PER_STRENGTH
	var target_carry := str_points * CharacterStats.CARRY_PER_STRENGTH
	var applied := CharacterStats.restamp_derived(_host, target_hp - _applied_hp, target_carry - _applied_carry, old_stamina_max)
	_applied_hp += applied.x
	_applied_carry += applied.y
