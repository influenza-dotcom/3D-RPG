class_name PassiveItemBuffs
extends Node

## Dota / ARTS-style PASSIVE ITEM BUFFS. Any Item carried in this Character's backpack whose `held_passive_effect`
## (a StatusEffect used purely as a data payload) is set grants that effect's `stat_modifiers` + `speed_multiplier`
## WHILE HELD — no equip step, on the instant it enters the bag and off the instant it leaves. Built in
## Character._ready (both Player and NPC), so an NPC authored to carry a buff item benefits too.
##
## HOW IT FOLDS INTO GAMEPLAY (the four LIVE stats). This node exposes the SAME duck-typed surface a
## StatusEffectManager does — stat_modifier(stat) + speed_multiplier() (+ a no-op apply_effect() so Character's
## scanner recognises it as a buff source) — and Character.status_stat_modifier / status_move_multiplier SUM /
## PRODUCT across every such child. So agility (move/jump), gunplay (weapon damage / sway), persuasion (shop
## prices) and streetwise (reputation) pick up held-item buffs automatically at their existing live seams, with no
## per-frame work here — recompute happens only when the bag changes.
##
## STRENGTH / ENDURANCE are the exception. They are spawn-stamped into carry_capacity / max_hp and NOT read live
## (CharacterStats), so a held modifier to them is RE-STAMPED here as a running DELTA on the host's max_hp /
## carry_capacity — the exact pattern LevelUp / PerkManager use — recomputed whenever the bag changes so dropping a
## +HP trinket removes EXACTLY what it added (hp clamped so a wounded carrier is never over-healed, never pushed
## below 1). CARRY_PER_STRENGTH / HP_PER_ENDURANCE live on CharacterStats, so a held +endurance item grants the
## same max HP a level-up of that size would.
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

## Live-stat additive pool: String stat -> summed float bonus. Holds ONLY the four multiplier stats
## (persuasion/gunplay/streetwise/agility); strength/endurance are routed to the re-stamp, not here. Read by stat_modifier().
var _pool: Dictionary = {}
## Product of every held item's speed_multiplier (1.0 = none). Read by speed_multiplier().
var _speed: float = 1.0

## The max_hp / carry_capacity we have ACTUALLY added to the host (post-floor). A recompute applies only the DELTA
## from these, so a removed item takes back exactly what it gave. Tracked here (never recomputed from the host's
## live fields) because the stat->derived formulas are LINEAR, so deltas telescope back to zero on the last item
## leaving. We accumulate the REAL applied change, not the ideal target — so a negative-endurance item that hits the
## max_hp floor still telescopes exactly (storing the ideal would over-restore on drop and inflate max_hp).
var _applied_hp: float = 0.0
var _applied_carry: float = 0.0

## Collapse a burst of inventory.changed (a multi-stack load restore fires one per stack; a buy/sell fires several)
## into ONE recompute at idle, mirroring the Player's autosave debounce.
var _dirty: bool = false

# --- duck-typed buff-source surface (matched by Character.status_stat_modifier / status_move_multiplier) ---

## Additive modifier for a LIVE stat while these items are held. Returns 0 for strength/endurance — those are not
## read live; this pool applies them by re-stamping max_hp / carry_capacity instead (see _recompute / _restamp).
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

## Rebuild the whole pool from the current backpack contents, then re-stamp the strength/endurance-derived
## max_hp / carry_capacity. Idempotent — safe to run as many times as `changed` fires.
func _recompute() -> void:
	_dirty = false
	if not is_instance_valid(_host):
		return
	var inv = _host.get(&"inventory")
	var pool: Dictionary = {}
	var speed := 1.0
	var end_points := 0.0
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
					"endurance": end_points += amount
					"strength": str_points += amount
					_: pool[key] = float(pool.get(key, 0.0)) + amount
			if fx.speed_multiplier != 1.0:
				speed *= pow(fx.speed_multiplier, n)
	_pool = pool
	_speed = speed
	_restamp(end_points, str_points)

## Re-stamp the strength/endurance-derived carry_capacity / max_hp as a DELTA from what we last applied, so held
## +HP/+carry items add on pickup and take back EXACTLY that on drop. Mirrors LevelUp.level_up_stat /
## PerkManager._apply_stat_bonuses (linear formula; hp clamped to [1, new max] so removing a +HP item while wounded
## can't over-heal or drop below 1). Duck-typed host access so a test stub with only these fields works.
func _restamp(end_points: float, str_points: float) -> void:
	if not is_instance_valid(_host):
		return
	var target_hp := end_points * CharacterStats.HP_PER_ENDURANCE
	var target_carry := str_points * CharacterStats.CARRY_PER_STRENGTH
	# Accumulate the delta ACTUALLY applied (post-floor), not the ideal target, so pickup and drop stay EXACT
	# inverses even when a negative-endurance/strength item drives the value into its floor (max_hp >= 1, carry >= 0).
	# Moving hp by the real max change (new_max - old_max) keeps the Dark-Souls "heal on gain" without over-healing.
	var hp_delta := target_hp - _applied_hp
	if hp_delta != 0.0 and _host.get(&"max_hp") != null:
		var old_max := float(_host.get(&"max_hp"))
		var new_max := maxf(1.0, old_max + hp_delta)
		_host.set(&"max_hp", new_max)
		_host.set(&"hp", clampf(float(_host.get(&"hp")) + (new_max - old_max), 1.0, new_max))
		_applied_hp += new_max - old_max
		# Refresh the HP HUD, matching Character.heal / respawn which emit `damaged` on any hp/max change. Guarded so
		# a test stub (or any host without the signal) is a no-op.
		if _host.has_signal(&"damaged"):
			_host.emit_signal(&"damaged", float(_host.get(&"hp")), new_max)
	var carry_delta := target_carry - _applied_carry
	if carry_delta != 0.0 and _host.get(&"carry_capacity") != null:
		var old_carry := float(_host.get(&"carry_capacity"))
		var new_carry := maxf(0.0, old_carry + carry_delta)  # floor at 0, matching Character._apply_stats
		_host.set(&"carry_capacity", new_carry)
		_applied_carry += new_carry - old_carry
