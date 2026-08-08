class_name AbilityManager
extends RefCounted

## The Player's ability SUBSYSTEM, pulled out of player.gd so the grant / revoke / persistence bookkeeping lives in
## one cohesive, testable unit instead of ~150 lines woven through the 2,500-line Player. Each unlockable mechanic is
## still a drag-drop `Ability` CHILD NODE of the Player (presence + `enabled` IS the grant); this manager just owns
## the LIVE LIST and the operations over it — discovery/tracking, the gate (`has`), the runtime build (`_build` via
## the shared naming convention), grant/re-enable, revoke (`take`), and the save projection (`unlocked_ids` /
## `set_unlocks`). The Player keeps only the three typed HOT-PATH refs (_wall_climb / _slide / _grapple_ability) and
## the physics-step beats that drive them — those are irreducibly Player-side, so this manager never touches them.
##
## WHY RefCounted (not a Node / autoload):
##  - It is created at the Player's var-init and wired in Player._init, so the white-box unit tests — which build a
##    bare `Player.new()` and NEVER run _ready — can drive unlock/grant/has immediately. A Node child would need
##    add_child (only reachable in _ready) and would otherwise leak as an orphan in those off-tree tests.
##  - It holds no per-frame process and no tree presence; it is pure state + logic. Ability NODES stay children of
##    the PLAYER (authoring contract: drop them under the Player), so `unlock`/`grant` add to `host`, not to us.
##
## HOST is the owning Player, injected once (Player._init sets `host = self`). Typed Node — not Player — to avoid a
## Player <-> AbilityManager class cycle, so the two callbacks into the Player (add_child + _register_ability) go
## through the dynamic `host` surface, the same idiom PerkManager uses for host.grant_ability.

## The ability id-set on disk + the id -> ability-script resolution, both by the ONE snake_case naming convention
## (WallClimb.tscn <-> ability_id() wall_climb <-> wall_climb.gd). This is what lets `_build` reconstruct an ability
## with no hand-maintained id->script table — the old Player.ABILITY_SCRIPTS dict is gone. No class_name → preload.
const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")

## Relayed out by the Player as its own `mechanic_unlocked` (Player._on_mechanic_unlocked), so existing listeners
## (ChipInstallScreen) keep connecting to `player.mechanic_unlocked` unchanged.
signal mechanic_unlocked(id: StringName)

## An INSTALLED implant was switched off or back on by the player (set_active — the Implants-tab toggle).
## Relayed out by the Player as its own `mechanic_toggled`, mirroring the mechanic_unlocked relay. Deliberately
## NOT mechanic_unlocked: that signal means "granted" (ChipInstaller autosaves on it as a milestone), while a
## toggle is a reversible preference flip.
signal mechanic_toggled(id: StringName, active: bool)

var host: Node = null  ## the owning Player, injected by Player._init

var _abilities: Array[Ability] = []  ## the live drag-drop ability components (the gate + the save projection iterate this)

## Record a discovered / newly-built ability: inject the host and add it to the live set (deduped). Called only via
## Player._register_ability (which also caches the typed hot-path ref), so every add to the list funnels through the
## one chokepoint. setup() runs even for a duplicate (harmless re-inject), matching the pre-extraction behaviour.
func track(a: Ability) -> void:
	if a == null:
		return
	a.setup(host)
	if not _abilities.has(a):
		_abilities.append(a)

## True while an ENABLED ability grants `id` — the ACTIVE predicate. The GATE consumed (via Player.has_mechanic)
## by air_dash / laser_sight / grapple / fall_immunity / chess_visualizer; wall_climb / slide are driven through
## the Player's typed refs instead. A player-disabled implant reads FALSE here (all gameplay switches off) while
## still reading true on is_installed — the ChipInstaller re-sell guards key on THAT, never on this.
func has(id: StringName) -> bool:
	for a in _abilities:
		if a != null and a.enabled and a.ability_id() == id:
			return true
	return false

## True while ANY ability node grants `id`, enabled or not — the INSTALLED predicate (owning the implant,
## regardless of whether it's currently switched on). Consumed by the ChipInstaller guards (an owned-but-off
## chip must never be re-sold or re-charged) and the Implants tab roster.
func is_installed(id: StringName) -> bool:
	for a in _abilities:
		if a != null and a.ability_id() == id:
			return true
	return false

## Switch an INSTALLED implant off / back on (the Implants-tab toggle). Flips `enabled` on every node granting
## `id` (matching set_unlocks' all-nodes sweep); switching OFF also fires each node's on_deactivated() hygiene
## hook (Slide ends a live slide, Grapple severs a live rope) so a later re-enable can't resume stale state.
## Returns false for an id with no node (nothing to toggle) — never builds. A no-change call is a silent no-op
## (no emit). Emits mechanic_toggled, NOT mechanic_unlocked (a toggle is a preference, not a grant milestone).
func set_active(id: StringName, on: bool) -> bool:
	if not is_installed(id):
		return false
	if has(id) == on:
		return true  # already in the wanted state — idempotent, no signal
	for a in _abilities:
		if a != null and a.ability_id() == id:
			a.enabled = on
			if not on:
				a.on_deactivated()
	mechanic_toggled.emit(id, on)
	return true

## True iff unlock(id) would actually grant something: either the runtime registry can build the id, or an ability
## node with this id already exists to re-enable. Lets a PAID install (ChipInstaller) verify the grant resolves
## BEFORE charging, so a typo'd chip id never takes money for nothing.
func can_grant(id: StringName) -> bool:
	if AbilityRegistry.can_build(id):
		return true
	for a in _abilities:
		if a != null and a.ability_id() == id:
			return true
	return false

## Build the ability node for `id` from the shared naming convention (a runtime grant: pickup / chip / save load).
## Unknown / unconventional id -> null (grants nothing).
func _build(id: StringName) -> Ability:
	if not AbilityRegistry.can_build(id):
		return null
	return load(AbilityRegistry.script_path_for(id)).new() as Ability

## Permanently grant a mechanic (an UpgradePickup / a paid install / a loaded save). Idempotent. Re-enables a
## disabled ability if one's already present; otherwise builds the node from the registry, parents it under the
## Player, and registers it (which caches the Player's typed ref). Emits once.
##
## NOTE the re-enable arm also switches a PLAYER-disabled implant (Implants tab) back on: a fresh grant of a
## mechanic you'd switched off turns it on, which is the intuitive read of "you were just granted this". The
## PAID path can't reach it — ChipInstaller's guards key on is_installed, so an owned-but-off implant is never
## re-sold — so this fires only for a free grant (UpgradePickup / perk) or the load path's rebuild.
func unlock(id: StringName) -> void:
	if has(id):
		return
	for a in _abilities:
		if a != null and a.ability_id() == id:
			a.enabled = true                       # had it as a disabled node — switch it back on
			mechanic_unlocked.emit(id)
			return
	var made := _build(id)
	if made == null:
		return
	host.add_child(made)
	host.call(&"_register_ability", made)          # tracks + caches the Player's typed hot-path ref (dynamic: host is Node)
	mechanic_unlocked.emit(id)

## Adopt a ready-built Ability NODE and grant its mechanic — a scene-based UpgradePickup / a Perk hands one over, so
## the node's own authored tuning/config rides along (unlike the registry-built unlock). Idempotent by id: if the
## mechanic is already live the incoming node is discarded; a same-id DISABLED node is re-enabled instead of stacking
## a second. Returns TRUE only when it actually introduced a NEW ability node — so a grantor (a perk) knows whether
## it OWNS the ability for later revocation. A dup or a re-enabled editor-placed node returns false, so respec never
## deletes an ability the perk didn't bring.
func grant(a: Ability) -> bool:
	if a == null:
		return false
	var id := a.ability_id()
	if has(id):
		a.free()  # already granted + enabled -> drop the duplicate (the incoming node never entered the tree)
		return false
	for existing in _abilities:
		if existing != null and existing.ability_id() == id:
			existing.enabled = true  # had it as a disabled node -> switch it back on, discard the incoming dupe
			a.free()
			mechanic_unlocked.emit(id)
			return false  # re-enabled an existing (editor-placed) node — not a NEW grant; respec must not delete it
	a.enabled = true
	host.add_child(a)
	host.call(&"_register_ability", a)             # tracks + caches the Player's typed hot-path ref
	mechanic_unlocked.emit(id)
	return true

## Remove every ability granting `id` from the live set and RETURN them (NOT freed) so the Player can null any
## hot-path ref BEFORE it queue_frees the node (a freed ability must never dangle in the physics step). This is the
## sole removal path (set_unlocks only DISABLES); the Player's revoke_ability drives it. Idempotent (empty for an
## unknown/absent id).
func take(id: StringName) -> Array:
	var removed: Array = []
	var keep: Array[Ability] = []
	for a in _abilities:
		if a != null and a.ability_id() == id:
			removed.append(a)
		elif a != null:
			keep.append(a)
	_abilities = keep
	return removed

## The granted-and-ACTIVE ability ids — the save system's [player].unlocks projection of the live node set.
## Deduped (two same-id nodes count once). Presence+enabled stays the single source of truth for ACTIVE; a
## player-disabled implant is deliberately omitted here and persists through disabled_ids() -> the SEPARATE
## [player].disabled_unlocks key instead (GameState.capture reads both), so switching an implant off never
## uninstalls it across a save/load.
func unlocked_ids() -> Array:
	var ids: Array = []
	for a in _abilities:
		if a != null and a.enabled and not ids.has(a.ability_id()):
			ids.append(a.ability_id())
	return ids

## Every INSTALLED ability id, switched on or off — unlocked_ids' superset. Deduped. The Implants tab lists
## this (an off implant must stay visible to be switchable back on).
func installed_ids() -> Array:
	var ids: Array = []
	for a in _abilities:
		if a != null and not ids.has(a.ability_id()):
			ids.append(a.ability_id())
	return ids

## The installed-but-switched-OFF ability ids — what GameState.capture persists as [player].disabled_unlocks.
## An id counts as disabled only when NO node grants it enabled (two same-id nodes, one on = active, not here).
func disabled_ids() -> Array:
	var ids: Array = []
	for a in _abilities:
		var id := a.ability_id() if a != null else &""
		if id != &"" and not has(id) and not ids.has(id):
			ids.append(id)
	return ids

## Replace the live unlock set wholesale (loading a save). Enable wanted abilities, DISABLE the rest (disables rather
## than frees, so an editor-placed node survives a load), and build any wanted ability we don't have yet.
func set_unlocks(ids: Array) -> void:
	var want := {}
	for id in ids:
		want[StringName(id)] = true
	for a in _abilities:
		if a != null:
			a.enabled = want.has(a.ability_id())
	for id in want.keys():
		if not has(id):
			unlock(id)

## Restore the saved installed-but-switched-OFF implants (loading a save; runs AFTER set_unlocks). Each id is
## BUILT if absent — a runtime-granted implant has no editor-placed node on a fresh scene, and set_unlocks only
## builds WANTED (enabled) ids — then disabled. Skips on_deactivated (freshly-built state has nothing live to
## end) and emits nothing beyond unlock's own build emit (mirrors set_unlocks' quiet per-node disables). An
## unbuildable id (a stale save naming a deleted ability) grants nothing and simply drops out at the next
## capture — the same soft degrade set_unlocks has.
func set_disabled(ids: Array) -> void:
	for raw in ids:
		var id := StringName(str(raw))
		if id == &"":
			continue
		if not is_installed(id):
			unlock(id)  # build the node so the implant EXISTS to be off (and to be switched back on later)
		for a in _abilities:
			if a != null and a.ability_id() == id:
				a.enabled = false
