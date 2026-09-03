class_name Ammo
extends Node3D

## Per-weapon ammo clip. Tracks the equipped weapon's current rounds and, on a
## weapon swap, stashes/restores each weapon's count so switching guns does NOT
## refill them. attack.gd calls consume_ammo() per shot (gating fire on its bool
## return); the Reload Timer / reload() refill to max.

## Emitted when a reload completes (clip back to max). gun_mesh.gd listens to raise
## the gun back up after the reload dip; UI refreshes the count.
signal finished_reloading

## The wielder's weapon inventory: seeds the starting equipped_weapon and emits weapon_changed, which drives the per-weapon clip stash/restore on every swap.
@export var inventory: Inventory

var current_weapon: WeaponData
var current_ammo: int = 0
## Rounds consumed per shot. >1 would burn multiple rounds per trigger pull.
var ammo_cost: int = 1
## The wielder (set by Weapon.setup). Used to reach the reserve backpack (character.inventory) and to
## gate reserve consumption to the PLAYER — AI wielders refill their clips for free.
var character: Character

## Remembers each weapon's leftover ammo across swaps (WeaponData -> int), keyed by
## the WeaponData resource instance.
var _ammo_per_weapon: Dictionary = {}

## Reserve clips this wielder has BURNED reloading, per caliber (StringName -> int), since the last
## restore_spent_ammo(). The ledger for the player-death encounter reset: an NPC that emptied four clips into
## you would otherwise stay dry forever, because the default CHECKPOINT_RESPAWN death mode leaves the world
## untouched — so every retry of a fight you lost is against a progressively more disarmed enemy.
##
## ⭐COUNTED AT THE ONE SEAM THAT SPENDS THEM (_refilled_clip), never inferred from a "should have" baseline, so
## it can only ever describe ammo this wielder actually FIRED OFF. A clip the player PICKPOCKETED never lands in
## here — stealing an NPC's ammo to disarm it (npc.gd is_armed / _can_fight_with_gun) is a real mechanic, and
## refilling from a baseline would silently undo it on the next death.
var _spent_clips: Dictionary = {}

## A backgrounded (swapped-away mid-reload) reload runs this much slower than a normal one.
@export var bg_reload_slowdown: float = 1.5
## Weapons reloading in the BACKGROUND after you swapped away mid-reload (WeaponData -> normal-speed
## seconds of reload still left). Advanced slowly in _process; on completion the weapon's banked clip
## refills, so switching back later finds it loaded.
var _bg_reloads: Dictionary = {}

func _ready() -> void:
	inventory.weapon_changed.connect(_on_weapon_changed)
	current_weapon = inventory.equipped_weapon
	set_to_max_ammo()
	set_process(false)  # only runs while a background reload is in flight (see start_background_reload)

## On swap: bank the outgoing weapon's remaining ammo, then restore the incoming
## weapon's saved count — or fill to max the first time that weapon is seen.
func _on_weapon_changed(_weapon: WeaponData) -> void:
	if current_weapon:
		_ammo_per_weapon[current_weapon] = current_ammo
	current_weapon = _weapon
	if _ammo_per_weapon.has(_weapon):
		current_ammo = _ammo_per_weapon[_weapon]
	else:
		set_to_max_ammo()

func set_to_max_ammo() -> void:
	# Startup race: an enemy add_child's its Weapon (firing Ammo._ready) a beat BEFORE it equips a
	# WeaponData, so current_weapon can still be null here. Skip — the equip fires weapon_changed a
	# moment later, which refills correctly.
	if not current_weapon:
		return
	# Infinite-ammo weapons (melee, fists) carry a sane max_ammo now; consume_ammo short-circuits on the
	# is_infinite_ammo flag, so the clip count is purely cosmetic and never drives whether they can fire.
	current_ammo = current_weapon.max_ammo

## NPC-pooling reuse reset (NpcPool): refill the live magazine and drop the cross-swap bookkeeping so a reused NPC
## starts with a fresh clip and no phantom reload. Uses set_to_max_ammo (the free AI refill — NOT reload(), which
## would eject the clip and spend a spare from the backpack). Clearing _bg_reloads + set_process(false) kills any
## background (swapped-away) reload that was mid-flight when the NPC died, so it can't tick / emit finished_reloading
## on the reused body. The caller (NPC.reset_for_reuse) re-applies starts_unloaded AFTER this if the NPC spawns dry.
func reset_for_reuse() -> void:
	set_to_max_ammo()
	_ammo_per_weapon.clear()  # per-weapon banked clip counts across swaps — no stale partial clip resurfaces later
	_bg_reloads.clear()
	# The spent-clip ledger is per-LIFE too: NPC.reset_for_reuse wipes and re-seeds the whole backpack right after
	# this, so a debt carried over from the previous life would pay out as FREE clips on the fresh body's first
	# player-death restore — ammo nobody ever fired.
	_spent_clips.clear()
	set_process(false)

## Hand back the ammo this wielder has EXPENDED since the last call — the ammo half of the player-death encounter
## reset (npc_home_return.gd, alongside the full heal). Two halves, which together restore the exact state the
## wielder started the fight in:
##   1. EVERY MAGAZINE back to full — the live one and each weapon's clip banked across a swap. This covers both
##      the rounds that were fired and the partial mag a reload EJECTED (those rounds are lost, see _refilled_clip).
##      Uses the free set-to-max fill, never reload(), which would spend yet another spare clip.
##   2. EVERY SPARE CLIP reloading burned back into the reserve, from the `_spent_clips` ledger.
##
## Returns true when anything was actually given back (an untouched wielder reports no work done).
##
## ⭐THIS ONLY EVER GIVES. It never takes rounds away and it never tops the reserve up to some authored baseline:
## the ledger is the only source, so ammo the player PICKPOCKETED off an NPC stays stolen and the disarm-by-theft
## mechanic survives the reset. (The corollary: an NPC authored `starts_unloaded` comes back with a LOADED gun
## once it has reloaded during the fight — the dry-gun opening is a spawn state, not something this restores.)
##
## ⭐A clip that will not FIT (the bounded grid backpack is full) stays on the ledger rather than being dropped, so
## it is handed back on the next death instead of being silently eaten.
func restore_spent_ammo() -> bool:
	var restored := false
	if current_weapon != null and current_ammo < current_weapon.max_ammo:
		current_ammo = current_weapon.max_ammo
		restored = true
	for w in _ammo_per_weapon:
		var banked: WeaponData = w
		if banked != null and int(_ammo_per_weapon[w]) < banked.max_ammo:
			_ammo_per_weapon[w] = banked.max_ammo
			restored = true
	if character == null or character.inventory == null:
		_spent_clips.clear()  # a free-refilling wielder never took clips out of a bag; nothing to owe
		return restored
	for caliber in _spent_clips.keys():
		var owed: int = int(_spent_clips[caliber])
		var item: Item = ItemDb.ammo_item_for(caliber)
		if owed <= 0 or item == null:
			_spent_clips.erase(caliber)
			continue
		var given: int = character.inventory.add(item, owed)
		if given > 0:
			restored = true
		if given >= owed:
			_spent_clips.erase(caliber)
		else:
			_spent_clips[caliber] = owed - given  # bag full — keep the remainder owed for next time
	return restored

## Hand a weapon's banked clip + any in-flight background reload to a REPLACEMENT WeaponData object (a
## weapon-bench refit rebuilds the stat block into a NEW resource, so every WeaponData-KEYED cache here
## would otherwise see a stranger: _on_weapon_changed would miss _ammo_per_weapon and call
## set_to_max_ammo() — a FREE FULL MAGAZINE on every fit, i.e. a repeatable infinite-reload exploit).
## Reached only through Weapon.migrate_weapon_state, which is the single fan-out for an object swap.
## ⭐UNCONDITIONAL, not gated on "is it drawn": start_background_reload is called (attack.gd:643) exactly
## when you swap AWAY mid-reload, so the canonical orphan is a HOLSTERED weapon.
## ⭐Clamps DOWN to the new magazine but never UP — a bigger mag arrives with the rounds you already had,
## and a smaller one spills the overflow. An unseen weapon banks the new max, matching the first-sight
## fill _on_weapon_changed would have done.
## ⭐Nulls current_weapon when `old` is the live gun so the imminent weapon_changed SKIPS its re-bank of a
## dead object (which would overwrite the seed we just wrote) and reads the seeded key instead. The HUD
## ammo readout blanks for the swap's duration (ui.gd:1686 -> _ammo_text() and the low-clip tint are both
## null-guarded on current_weapon) — which is what a gun being handed back over a bench should look like.
func rekey_weapon(old: WeaponData, new: WeaponData) -> void:
	if old == null or new == null or old == new:
		return
	var banked: int = current_ammo if old == current_weapon else int(_ammo_per_weapon.get(old, new.max_ammo))
	_ammo_per_weapon[new] = clampi(banked, 0, maxi(new.max_ammo, 0))
	_ammo_per_weapon.erase(old)  # no dead key left behind — one per fit would leak for the rig's life
	if _bg_reloads.has(old):
		# The remaining seconds ride across untouched: refitting is not a reason to restart a reload, and
		# _process keys the completion refill on this same dictionary.
		_bg_reloads[new] = _bg_reloads[old]
		_bg_reloads.erase(old)
	if old == current_weapon:
		current_weapon = null

## Returns false (and changes nothing) when the clip can't cover one shot — attack.gd
## treats false as "empty" and plays the dry-fire click instead of firing.
func consume_ammo() -> bool:
	if current_weapon != null and current_weapon.is_infinite_ammo:
		return true  # melee / fists: always a shot, never decrements (no two's-complement overflow trick)
	if current_ammo - ammo_cost >= 0:
		current_ammo -= ammo_cost
		return true
	return false

func reload() -> void:
	current_ammo = _refilled_clip(current_weapon, current_ammo)
	finished_reloading.emit()

## True when refilling `weapon`'s clip should DRAW from the wielder's reserve: a calibered weapon held by any
## Character with a backpack — the PLAYER or an NPC (both now spend spare clips, so an enemy you've stripped
## of ammo runs dry). Caliber-less weapons, and wielders with no backpack (off-tree units), refill for free.
func _uses_reserve(weapon: WeaponData) -> bool:
	return weapon != null and weapon.caliber != &"" and character != null and character.inventory != null

## True when a reload would actually load rounds: a free-refill weapon, or a reserve weapon whose caliber
## has ammo in the backpack. attack gates the reload on this — no supply means a dry click, not a reload.
func has_reload_supply() -> bool:
	if current_weapon == null:
		return false
	if not _uses_reserve(current_weapon):
		return true
	return character.inventory.ammo_count(current_weapon.caliber) > 0

## The clip value after a reload. Reserve ammo is counted in whole CLIPS, not loose rounds. A reserve
## weapon does a MAGAZINE reload: eject the current (partial) clip — those rounds are LOST — and spend ONE
## spare clip from the reserve to seat a fresh, FULL magazine (max_ammo). Caliber-less weapons / AI / no
## backpack still free-fill to max. `from_current` is only kept when there are no spare clips to seat.
func _refilled_clip(weapon: WeaponData, from_current: int) -> int:
	if weapon == null:
		return from_current
	if not _uses_reserve(weapon):
		return weapon.max_ammo
	if character.inventory.ammo_count(weapon.caliber) <= 0:
		return from_current  # no spare clips -> keep what's chambered
	# Spend ONE clip, and BOOK it: take_ammo's return (not a blind 1) is what actually left the backpack, so the
	# ledger restore_spent_ammo() hands back can never exceed what was really burned.
	var taken: int = character.inventory.take_ammo(weapon.caliber, 1)
	if taken > 0:
		_spent_clips[weapon.caliber] = int(_spent_clips.get(weapon.caliber, 0)) + taken
	return weapon.max_ammo  # old clip discarded; the spare clip seats a full magazine

func _on_reload_timeout() -> void:
	reload()

## Begin (or replace) a BACKGROUND reload for `weapon` with `normal_seconds` of reload work left at
## normal speed. Called by Attack when you swap away mid-reload, so the outgoing gun keeps topping up
## (slower) while you fight with another.
func start_background_reload(weapon: WeaponData, normal_seconds: float) -> void:
	if weapon == null or normal_seconds <= 0.0:
		return
	_bg_reloads[weapon] = normal_seconds
	set_process(true)

## Move ONLY an in-flight background reload from `old` to `new`, leaving the clip banks alone. The narrow
## second half of a weapon-bench refit, and it exists because of an ORDERING fact that rekey_weapon cannot
## reach: Attack converts an in-progress FOREGROUND reload into a background one for the OUTGOING weapon
## (attack.gd:643) from *inside* the equip chain — i.e. AFTER the refit has already pre-seeded and retired
## `old`. So a player who refits mid-reload lands a live background reload on a block nothing will ever read
## again, and its completion silently spends a spare clip out of the backpack into a dead dictionary key.
## ⭐Deliberately NOT a second rekey_weapon call: by this point `current_weapon` is already `new`, so
## rekey_weapon's own bank line would re-read `_ammo_per_weapon.get(old, new.max_ammo)`, miss the erased key,
## and hand back a FULL magazine — the exact exploit the first call exists to prevent.
func rekey_background_reload(old: WeaponData, new: WeaponData) -> void:
	if old == null or new == null or old == new or not _bg_reloads.has(old):
		return
	# Remaining seconds ride across untouched — a refit is not a reason to restart a reload.
	_bg_reloads[new] = _bg_reloads[old]
	_bg_reloads.erase(old)

func is_background_reloading(weapon: WeaponData) -> bool:
	return _bg_reloads.has(weapon)

## Drop a weapon's background reload (e.g. the player chose to foreground-reload it instead).
func cancel_background_reload(weapon: WeaponData) -> void:
	_bg_reloads.erase(weapon)

func _process(delta: float) -> void:
	if _bg_reloads.is_empty():
		set_process(false)
		return
	# Advance every backgrounded reload slowly; a finished one refills that weapon's banked clip (and
	# the live clip + UI if it happens to be the gun in hand right now).
	for weapon in _bg_reloads.keys():
		_bg_reloads[weapon] -= delta / bg_reload_slowdown
		if _bg_reloads[weapon] <= 0.0:
			_bg_reloads.erase(weapon)
			_ammo_per_weapon[weapon] = _refilled_clip(weapon, _ammo_per_weapon.get(weapon, 0))
			if weapon == current_weapon:
				current_ammo = _ammo_per_weapon[weapon]
				finished_reloading.emit()
