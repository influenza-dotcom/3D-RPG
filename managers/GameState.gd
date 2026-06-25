extends Node
## GameState — the live run's autosaved PROFILE + its RESPAWN point.
##
## Dark Souls style, ONE autosave (no manual slots): the run persists to user://gamestate.cfg so quitting and
## relaunching resumes where you left off. The profile is the player's progression — money, the five stats, the
## unlocked mechanics, and the backpack (items + the drawn weapon, keyed by Item.id through ItemDb) — plus the
## respawn point (the last bonfire, or the initial spawn). It is captured + written
## at every milestone: a wallet change (kill bounty / trade / pickup), a level-up, an upgrade pickup, and a
## bonfire rest. On DEATH the world is NOT reloaded — you're brought back to LIFE at the respawn point (enemies
## stay as they are); the autosave is the only thing that survives quitting.
##
## Boot: this autoload's _ready loads the save (if any) into memory, so the start menu can offer "Continue" and
## the Player's _ready can apply the loaded build. "New Game" calls reset_for_new_game() to start clean.
##
## SAVE SCOPE — this is a PROFILE / checkpoint save, NOT an exact world snapshot. It persists the player's
## progression (money, stats, unlocks, perks, backpack), the run's world FLAGS + QUEST state + faction standing +
## day/night clock, and the ACTIVE LEVEL identity (current_level_path, so a reload returns you to the level the
## saved respawn belongs to). It does NOT persist per-placed-OBJECT world state: opened doors, looted / refilled
## containers, corpse discovery, dead NPCs, and spawned pickups all RESET on reload. Persisting those needs a
## STABLE per-object id (e.g. a save_id authored on each component) before they can round-trip — a deliberate
## future step, not an oversight. See CLAUDE.md "Save semantics must be explicit".

const SAVE_PATH := "user://gamestate.cfg"
## The six CharacterStats, by name — the columns of the [stats] save section (mirrors CharacterStats / LevelUp).
## (agility was previously omitted, so a leveled agility didn't survive a save — fixed by including it here.)
const STAT_NAMES: Array[StringName] = [&"strength", &"persuasion", &"gunplay", &"endurance", &"streetwise", &"agility"]
## Faction registry — resolves a quest's reward_reputation faction ids to live Faction resources for the grant.
const Factions := preload("res://scripts/faction/factions.gd")

## Quest signals (for the journal UI / listeners). The quest tracker lives here on GameState so it persists with
## the rest of the run profile — the spec's sanctioned "or extend GameState", which also dodges a project.godot
## autoload edit (that file carries the user's other uncommitted work).
signal quest_started(quest: Quest)
signal objective_advanced(quest: Quest, objective: QuestObjective)
signal quest_completed(quest: Quest)
## WR-6: a quest was FAILED (explicit fail_quest, or its expire_on_flag fired). Wire a journal strike-through / toast.
signal quest_failed(quest: Quest)

## True once a save has been loaded into the fields below (boot found a file, or Continue was chosen). The Player's
## _ready reads this: true -> apply the saved build (stats / money / unlocks / teleport); false -> a fresh game.
var loaded: bool = false
## saved wallet (fractional zorkmids — see Zorkmids); fresh-game seed reads the economy tuning group
## (explicitly annotated, NOT ':='-inferred off the GameSettings chain). EconomySettings' default is 0.0 (the player starts broke).
var money: float = GameSettings.economy.player_starting_money
var stat_values: Dictionary = {}           ## StringName stat -> int; empty = all baseline (a fresh sheet)
var unlocks: Array[StringName] = []         ## the saved unlocked-mechanic ids

## The saved BACKPACK. has_inventory marks that the save carried an [inventory] section at all — an older save
## (written before inventory persisted) doesn't, and the Player then seeds its authored starting loadout instead
## of restoring an empty bag. Stacks are {id: String, count: int} in stack order (Item.id is the stable key,
## resolved back through ItemDb.restore_item_from_save); a modified weapon stack can also carry `weapon_delta`.
## equipped_index is WHICH stack was the drawn weapon (-1 = fists).
var has_inventory: bool = false
var inventory_stacks: Array = []
var equipped_index: int = -1

## Saved FACTION STANDINGS — faction_id (String) -> standing (float). Captured from the Reputation autoload;
## the Player applies them back via Reputation.restore on a loaded game (a fresh game starts at zero). Empty
## until a run earns some, and an older save with no [reputation] section simply loads none.
var reputation: Dictionary = {}

## Saved DAY/NIGHT clock (WorldClock.time_of_day, 0..1) — captured from the WorldClock autoload and re-applied by
## the Player on load, so reloading doesn't snap the world back to noon (the default) and yank schedule-driven NPCs
## to their day routine. A save written before the clock persisted has no [clock] section and loads the noon default.
var time_of_day: float = 0.5

## Saved active STATUS EFFECTS on the player (CT-3): [{path: String, remaining: float}], so a buff/debuff survives a
## reload (anti quicksave-scum) with its countdown intact instead of vanishing. Effects are referenced by .tres path
## (a code-built effect with no resource_path can't round-trip and is skipped). Empty / missing section = none.
var status_effects: Array = []

## Saved ACTIVE LEVEL — the LevelData.resource_path GameRoot last loaded (set by GameRoot.load_level). On a loaded
## game GameRoot reloads THIS level instead of its exported default, so Continue / quickload / a load-death return
## you to the level you saved IN — not the editor's start level — before the saved respawn position is applied.
## Empty (or a code-built LevelData with no resource_path) -> GameRoot falls back to its exported `level`.
var current_level_path: String = ""

## One-shot: a genuine disk-load (load_from_disk) or New Game (reset_for_new_game) sets this so the Player pushes
## the saved/noon clock onto the free-running WorldClock autoload EXACTLY ONCE. A death-respawn reload leaves it
## false, so the live clock carries forward instead of rewinding to the last autosave's time.
var _clock_apply_pending: bool = false

## STORY FLAGS — designer / quest world-state: a String key -> Variant (bool/int/String) store. Set by
## triggers, dialogue, locks and quests; read by gated choices / merchants / doors. Persisted in [flags] and
## survives like the rest of the profile (written on every autosave). String-keyed internally (StringName args
## coerce at the set/get/has boundary) to dodge the GDScript String-vs-StringName Dictionary-hash trap and to
## round-trip cleanly through ConfigFile.
var flags: Dictionary = {}

## QUESTS — the live tracker (kept here so it persists with the profile). _quests_active: quest_id ->
## { quest: Quest, progress: { objective_id(String): int } }; _quests_completed: a set of finished quest ids.
var _quests_active: Dictionary = {}
var _quests_completed: Dictionary = {}
## WR-6: failed/expired quest ids -> the Quest resource (mirrors _quests_completed). A failed quest can't be
## re-started or completed; a FAILED dialogue gate + the journal read this.
var _quests_failed: Dictionary = {}
## Saved PERK LEDGER — the resource_paths of unlocked perks. Their stat bonuses ride in [stats] and their granted
## abilities in [player].unlocks; this records WHICH perks so has_perk / prereqs / "already learned" survive a reload.
var perk_paths: Array = []
## Saved PERK-GRANT LEDGER — perk id (String) -> the ability id (String) THAT perk introduced (only perks whose
## grant_ability actually added a NEW ability node are recorded). Persisted so a respec after a reload strips only
## what the perk truly granted — without this, restore_paths would re-claim an ability the player also owned from
## another source (an UpgradePickup, a starting unlock) and a later respec would wrongly revoke it.
var perk_grants: Dictionary = {}
## XP progression (rank 29): cumulative xp + cached level (persisted in [player]) + unspent skill (perk) points
## (persisted in [perks], the perk-owning section). Restored onto Player.xp/level + the PerkManager on load.
var xp: float = 0.0
var level: int = 0
var skill_points: int = 0
var points_earned: int = 0  ## cumulative XP-granted perk picks (respec refunds back up to this)

var has_respawn: bool = false
var respawn_position: Vector3 = Vector3.ZERO
var respawn_yaw: float = 0.0  ## body yaw (radians) the player faces on respawn

func _ready() -> void:
	load_from_disk()  # boot: pull the autosave into memory so the menu can offer Continue + the Player can apply it

## True if an autosave file exists on disk — the start menu gates its "Continue" button on this.
func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

## Load the autosave at `path` into the fields above. Returns false (and leaves loaded = false) if there's no file
## / it's unreadable — a fresh game. On success sets loaded = true so the Player applies the build.
## Every value reads through the type-guarded _cfg_* helpers below: this runs AT BOOT (the autoload's _ready),
## and a hand-edited/corrupt file can hold ANY Variant under a key — int() on an Array errors, `as Array` on a
## non-Array yields NULL (which would crash the restore loop), and a junk type hard-fails a typed assignment
## (respawn_position: Vector3). Junk degrades to the field's default instead of a boot crash.
func load_from_disk(path := SAVE_PATH) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		loaded = false
		return false
	money = _cfg_float(cfg, "player", "money", GameSettings.economy.player_starting_money)  # missing/junk -> the fresh-game knob; older saves stored ints, _cfg_float casts them
	xp = _cfg_float(cfg, "player", "xp", 0.0)
	level = _cfg_int(cfg, "player", "level", 0)
	unlocks.clear()
	var raw_unlocks = cfg.get_value("player", "unlocks", [])
	if raw_unlocks is Array:
		for u in raw_unlocks:
			unlocks.append(StringName(str(u)))  # str() first — StringName(<non-string Variant>) errors
	stat_values.clear()
	for n in STAT_NAMES:
		stat_values[n] = _cfg_int(cfg, "stats", String(n), 0)
	reputation.clear()
	if cfg.has_section("reputation"):
		for fid in cfg.get_section_keys("reputation"):
			reputation[fid] = _cfg_float(cfg, "reputation", fid, 0.0)  # junk -> 0; faction id is the key
	flags.clear()
	if cfg.has_section("flags"):
		for f in cfg.get_section_keys("flags"):
			flags[f] = cfg.get_value("flags", f, null)  # String key; the value round-trips as its stored Variant
	time_of_day = _cfg_float(cfg, "clock", "time_of_day", 0.5)  # missing section -> the noon default
	var raw_fx = cfg.get_value("status", "effects", [])  # [{path, remaining}]; junk-typed -> none (back-compat / corrupt-safe)
	status_effects = raw_fx if raw_fx is Array else []
	var raw_level = cfg.get_value("level", "path", "")  # active LevelData path; junk-typed / missing -> "" (GameRoot uses its export)
	current_level_path = raw_level if raw_level is String else ""
	has_respawn = _cfg_bool(cfg, "respawn", "has", false)
	respawn_position = _cfg_vec3(cfg, "respawn", "position", Vector3.ZERO)
	respawn_yaw = _cfg_float(cfg, "respawn", "yaw", 0.0)
	# Back-compat: a save written before inventory persisted has no [inventory] section — has_inventory stays
	# false and the Player seeds its authored loadout, exactly as those saves behaved when written.
	has_inventory = cfg.has_section("inventory")
	var raw_stacks = cfg.get_value("inventory", "stacks", []) if has_inventory else []
	inventory_stacks = raw_stacks if raw_stacks is Array else []
	equipped_index = _cfg_int(cfg, "inventory", "equipped", -1) if has_inventory else -1
	_load_perks_and_quests(cfg)
	loaded = true
	_clock_apply_pending = true  # a genuine disk-load: the Player applies the saved clock ONCE (not on a respawn reload)
	return true

## --- Type-guarded ConfigFile reads (see load_from_disk): junk-typed values fall back to the default
## instead of erroring in a conversion or a typed assignment. Numeric kinds convert freely between each
## other (an int 1 read as bool/float is fine); anything else is junk. ---
static func _cfg_int(cfg: ConfigFile, section: String, key: String, fallback: int) -> int:
	var v = cfg.get_value(section, key, fallback)
	return int(v) if (v is int or v is float or v is bool) else fallback

static func _cfg_float(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	var v = cfg.get_value(section, key, fallback)
	return float(v) if (v is int or v is float or v is bool) else fallback

static func _cfg_bool(cfg: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var v = cfg.get_value(section, key, fallback)
	return bool(v) if (v is bool or v is int or v is float) else fallback

static func _cfg_vec3(cfg: ConfigFile, section: String, key: String, fallback: Vector3) -> Vector3:
	var v = cfg.get_value(section, key, fallback)
	return v if v is Vector3 else fallback

## Write the in-memory profile to `path`. Unlocks are stored as plain Strings (clean round-trip), re-typed to
## StringName on load. The respawn fields are written straight from memory (kept current by set_respawn).
func save_to_disk(path := SAVE_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "money", money)
	cfg.set_value("player", "xp", xp)
	cfg.set_value("player", "level", level)
	var raw_unlocks: Array = []
	for u in unlocks:
		raw_unlocks.append(String(u))
	cfg.set_value("player", "unlocks", raw_unlocks)
	for n in STAT_NAMES:
		cfg.set_value("stats", String(n), int(stat_values.get(n, 0)))
	for fid in reputation:
		cfg.set_value("reputation", String(fid), float(reputation[fid]))
	for f in flags:
		cfg.set_value("flags", String(f), flags[f])
	cfg.set_value("respawn", "has", has_respawn)
	cfg.set_value("respawn", "position", respawn_position)
	cfg.set_value("respawn", "yaw", respawn_yaw)
	cfg.set_value("clock", "time_of_day", time_of_day)
	# Only stamp [status] when there's something to carry — an empty section over the back-compat "no effects" path
	# is harmless but pointless; the load path treats missing as none either way.
	if not status_effects.is_empty():
		cfg.set_value("status", "effects", status_effects)
	if current_level_path != "":
		cfg.set_value("level", "path", current_level_path)  # GameRoot reloads THIS level on a loaded game (not its export)
	# Written only when a bag was actually captured — so a profile that never captured one (nothing has called
	# capture with a real player yet) doesn't stamp an empty [inventory] section over the seed-on-load path.
	if has_inventory:
		cfg.set_value("inventory", "stacks", inventory_stacks)
		cfg.set_value("inventory", "equipped", equipped_index)
	_save_perks_and_quests(cfg)
	cfg.save(path)

## Read the live run off `player` into the in-memory profile (money, the five stats, the unlocked mechanics). The
## respawn fields aren't touched here — set_respawn keeps them current (a bonfire rest / the initial spawn).
func capture(player: Node) -> void:
	if player == null:
		return
	money = float(player.money)
	var sheet: CharacterStats = player.stats_or_default()
	stat_values.clear()
	for n in STAT_NAMES:
		stat_values[n] = sheet.get_stat(n)
	unlocks.clear()
	for u in player.unlocked_list():
		unlocks.append(StringName(u))
	# Faction standings are GLOBAL (the Reputation autoload), not on the player — snapshot them here so the
	# autosave carries them. Stored String-keyed for a clean cfg round-trip; Reputation.restore re-types on load.
	var standings := Reputation.all_standings()
	reputation.clear()
	for fid in standings:
		reputation[String(fid)] = float(standings[fid])
	# The day/night clock is global too (the WorldClock autoload) — snapshot it so a reload resumes the time of day.
	time_of_day = WorldClock.time_of_day
	# The backpack — when the player carries one (a bare unit-test player has no inventory; the fields are
	# then left as-is). Each stack serializes as {id, count} in stack order, PLUS its grid placement {x, y, w, h}
	# when the bag's spatial cap is on (the player's Tetris grid) so the layout survives a reload; equipped_index
	# records which SERIALIZED stack holds the drawn weapon. An item with no Item.id can't round-trip — skipped
	# with a warning (register it in resources/items/ to make it persist).
	# Per-instance weapon state rides as an additive `weapon_delta` dict when a weapon's scalar exported fields
	# differ from the registered template. Old saves without the key still restore from the template.
	var inv = player.inventory
	if inv != null:
		has_inventory = true
		inventory_stacks.clear()
		equipped_index = -1
		for s in inv.placed_contents():
			var it: Item = s["item"]
			if it == null or it.id == &"":
				if it != null:
					push_warning("GameState: item '%s' has no id — not saved" % it.label())
				continue
			if it == inv.equipped_item:
				equipped_index = inventory_stacks.size()
			var entry := {"id": String(it.id), "count": int(s["count"])}
			var weapon_delta := ItemDb.weapon_delta_for(it)
			if not weapon_delta.is_empty():
				entry["weapon_delta"] = weapon_delta
			# Placement only when the stack is actually on a grid (x >= 0) — an unbounded bag writes plain
			# {id, count}, which loads back as an auto-place (the back-compat shape).
			if int(s["x"]) >= 0:
				entry["x"] = int(s["x"])
				entry["y"] = int(s["y"])
				entry["w"] = int(s["w"])
				entry["h"] = int(s["h"])
			inventory_stacks.append(entry)
	# Active status effects (CT-3): serialize the player's StatusEffectManager (by .tres path + remaining time) so a
	# buff/debuff survives a reload. has_method-guarded for a bare test player; null manager (none applied) -> empty.
	var smgr = player.status_manager() if player.has_method(&"status_manager") else null
	status_effects = smgr.serialize() if smgr != null else []
	var pm := _perk_manager_of(player)
	perk_paths = pm.unlocked_paths() if pm != null else []
	# The perk-grant ledger (perk id -> ability id it introduced) — String-keyed for a clean cfg round-trip. Persisted
	# so a respec AFTER a reload revokes ONLY what each perk truly granted (not an ability owned from another source).
	perk_grants = {}
	if pm != null:
		var grants: Dictionary = pm.granted_abilities()
		for pid in grants:
			perk_grants[String(pid)] = String(grants[pid])
	var xp_v = player.get(&"xp")
	xp = float(xp_v) if xp_v != null else 0.0
	var level_v = player.get(&"level")
	level = int(level_v) if level_v != null else 0
	skill_points = pm.skill_points if pm != null else 0
	points_earned = pm.points_earned if pm != null else 0

## Capture `player` and write the save — the autosave seam every milestone calls. Off-tree (a bare player in a
## unit test) it does NOTHING: writing would clobber the user's real save during a test run. Real gameplay always
## autosaves from an in-tree player.
func autosave(player: Node) -> void:
	if player == null or not player.is_inside_tree():
		return
	capture(player)
	save_to_disk()

## The live HUMAN player — the non-NPC member of the Player group (companions ARE NPCs; mirrors NPC._real_player) —
## so world-state milestones can autosave without the caller threading a player ref. Null off-tree / pre-spawn.
func _live_player() -> Node:
	if not is_inside_tree() or get_tree() == null:
		return null
	for p in get_tree().get_nodes_in_group(Groups.PLAYER):
		if not (p is NPC):
			return p
	return null

## Flush the run after a WORLD-STATE change (a flag flip / a quest transition). These are milestones the player
## expects to survive a quit, but the in-memory flag/quest dicts were only persisted before when a money/xp event
## happened to coincide (the most-felt "Continue lost my progress" bug). ONE-FRAME-DEFERRED + coalesced, mirroring
## Player._queue_autosave: a burst of objective ticks / a flag fan-out (an AoE multi-kill advancing a KILL
## objective, or a set_flag that fans out to several advance_objective + an expire-fail) collapses to a SINGLE
## end-of-frame write instead of N synchronous full-profile serialize+saves. No-op off-tree (tests) / pre-spawn
## via the autosave() guard, which the deferred flush re-checks (a player freed before the flush -> no write).
var _world_save_queued: bool = false

func _autosave_world_state() -> void:
	if _world_save_queued:
		return
	_world_save_queued = true
	call_deferred(&"_flush_world_state_save")

func _flush_world_state_save() -> void:
	_world_save_queued = false
	var player := _live_player()
	if player != null:
		autosave(player)

## Consume the one-shot clock-apply flag (set by a disk-load / New Game). The Player calls this in _ready: true ->
## push GameState.time_of_day onto the live WorldClock; false (a death-respawn reload) -> leave the live clock be.
func consume_clock_apply() -> bool:
	var pending := _clock_apply_pending
	_clock_apply_pending = false
	return pending

## Record the LevelData GameRoot just loaded (its resource_path) so the next save knows which level to reload.
## Called by GameRoot.load_level on every level load (boot + door swaps). Blank for a code-built LevelData.
func set_current_level(path: String) -> void:
	current_level_path = path

# --- Manual save / quicksave / named slots (ML-1) -----------------------------------------------------------
## These layer over the path-parameterized save_to_disk(path) / load_from_disk(path). They are SEPARATE files
## from the Dark-Souls autosave (SAVE_PATH): quitting still resumes the autosave; quick/slot saves are explicit
## player-driven snapshots, RESTORED by a scene reload (load_from_disk sets loaded=true, then
## reload_current_scene rebuilds a fresh Player that re-applies the build) — we never mutate the live player,
## the same contract as boot / Continue. A quick/slot save also stamps the respawn point at the player's CURRENT
## position so a load returns you exactly where you saved (not the last bonfire).
const QUICKSAVE_PATH := "user://quicksave.cfg"
const SLOT_COUNT := 3  ## how many manual slots the save/load UI offers (1..SLOT_COUNT)

## Disk path for manual slot `slot` (1-based); the index is clamped so a bad caller can't escape user://.
func slot_path(slot: int) -> String:
	return "user://save_slot_%d.cfg" % clampi(slot, 1, SLOT_COUNT)

## Does a quicksave / the given manual slot exist on disk? (The UI gates its "load" affordances on these.)
func has_quicksave() -> bool:
	return FileAccess.file_exists(QUICKSAVE_PATH)

func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))

## Capture `player` and write a quicksave. Returns true on a successful write. Off-tree (a bare unit-test
## player) it does NOTHING — like autosave, so a test run never clobbers the user's real save files.
func quicksave(player: Node) -> bool:
	return _capture_and_write(player, QUICKSAVE_PATH)

## Capture `player` into manual slot `slot` (1-based). Same off-tree guard / return contract as quicksave.
func save_to_slot(player: Node, slot: int) -> bool:
	return _capture_and_write(player, slot_path(slot))

## Shared body: guard off-tree, stamp the respawn point at the player's current spot (so a load returns you
## there), capture the live run, write to `path`. Returns the write's success.
func _capture_and_write(player: Node, path: String) -> bool:
	if player == null or not player.is_inside_tree():
		return false
	set_respawn(player.global_position, player.rotation.y)  # a quick/slot save IS your new checkpoint
	capture(player)
	save_to_disk(path)
	return true

## Load the quicksave and re-apply it by reloading the scene (the fresh Player rebuilds the saved build from
## loaded=true — we never mutate the live player). Engine.time_scale is reset first so a quickload fired during
## the death slow-mo / BulletTime doesn't carry the dilation across the reload. Returns false (no reload) when
## there's no quicksave / it's unreadable, or we're off-tree.
func quickload() -> bool:
	return _load_and_reload(QUICKSAVE_PATH)

func load_from_slot(slot: int) -> bool:
	return _load_and_reload(slot_path(slot))

func _load_and_reload(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	if not load_from_disk(path):  # sets loaded = true on success so the reloaded Player applies the build
		return false
	if is_inside_tree() and get_tree() != null:
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()
	return true

## Build a CharacterStats sheet from the saved stat values — handed to the Player BEFORE its super._ready so
## _apply_stats stamps max_hp / carry from the saved build. An unset stat defaults to baseline 0.
func make_stats() -> CharacterStats:
	var s := CharacterStats.new()
	for n in STAT_NAMES:
		s.set(n, int(stat_values.get(n, 0)))
	return s

## The PerkManager child of `player` (named "Perks"), or null if none has been created yet.
func _perk_manager_of(player: Node) -> PerkManager:
	for c in player.get_children():
		if c is PerkManager:
			return c
	return null

## Write the perk ledger + quest tracker to `cfg`, keyed by resource_path (a code-built quest/perk with no path
## can't round-trip and is skipped). Active quests carry their objective progress; completed carry just the path.
func _save_perks_and_quests(cfg: ConfigFile) -> void:
	if not perk_paths.is_empty():
		cfg.set_value("perks", "paths", perk_paths)
	if not perk_grants.is_empty():
		cfg.set_value("perks", "grants", perk_grants)  # perk id -> granted ability id (String-keyed) for respec revocation
	cfg.set_value("perks", "points", skill_points)  # always written so unspent points round-trip even with no perks yet
	cfg.set_value("perks", "earned", points_earned)  # cumulative — needed so a respec after a reload refunds correctly
	for qid in _quests_active:
		var entry: Dictionary = _quests_active[qid]
		var q: Quest = entry.get("quest")
		if q == null or q.resource_path == "":
			continue
		cfg.set_value("quests_active", String(qid), {"path": q.resource_path, "progress": entry.get("progress", {})})
	for qid in _quests_completed:
		var qc: Quest = _quests_completed[qid]
		if qc != null and qc.resource_path != "":
			cfg.set_value("quests_completed", String(qid), qc.resource_path)
	for qid in _quests_failed:  # WR-6: mirror the completed section — just the path (no progress on a closed quest)
		var qf: Quest = _quests_failed[qid]
		if qf != null and qf.resource_path != "":
			cfg.set_value("quests_failed", String(qid), qf.resource_path)

## Restore the perk ledger + quest tracker from `cfg` (resource-path keyed). A renamed/removed .tres path is
## skipped with a warning rather than crashing the boot load — degrade, never hard-fail.
func _load_perks_and_quests(cfg: ConfigFile) -> void:
	perk_paths.clear()
	var raw_perks = cfg.get_value("perks", "paths", [])
	if raw_perks is Array:
		for pp in raw_perks:
			perk_paths.append(str(pp))
	perk_grants.clear()
	var raw_grants = cfg.get_value("perks", "grants", {})  # an older save (before the grant ledger) has none -> empty
	if raw_grants is Dictionary:
		for pid in raw_grants:
			perk_grants[String(pid)] = String(raw_grants[pid])
	skill_points = _cfg_int(cfg, "perks", "points", 0)
	points_earned = _cfg_int(cfg, "perks", "earned", 0)
	_quests_active.clear()
	if cfg.has_section("quests_active"):
		for qid in cfg.get_section_keys("quests_active"):
			var rec = cfg.get_value("quests_active", qid, null)
			if not (rec is Dictionary):
				continue
			var q := load(str(rec.get("path", ""))) as Quest
			if q == null:
				push_warning("GameState: active quest '%s' path didn't load — skipped" % qid)
				continue
			var prog = rec.get("progress", {})
			_quests_active[StringName(qid)] = {"quest": q, "progress": (prog if prog is Dictionary else {})}
	_quests_completed.clear()
	if cfg.has_section("quests_completed"):
		for qid in cfg.get_section_keys("quests_completed"):
			var q := load(str(cfg.get_value("quests_completed", qid, ""))) as Quest
			if q == null:
				push_warning("GameState: completed quest '%s' path didn't load — skipped" % qid)
				continue
			_quests_completed[StringName(qid)] = q
	_quests_failed.clear()  # WR-6: mirror the completed load
	if cfg.has_section("quests_failed"):
		for qid in cfg.get_section_keys("quests_failed"):
			var q := load(str(cfg.get_value("quests_failed", qid, ""))) as Quest
			if q == null:
				push_warning("GameState: failed quest '%s' path didn't load — skipped" % qid)
				continue
			_quests_failed[StringName(qid)] = q

## Start a brand-new run: drop the loaded profile back to fresh-game defaults and forget the respawn point. The
## disk file is left until the first autosave overwrites it (so a New-Game-then-quit doesn't lose a prior save
## before any progress is actually made). The Player then ignores the profile (loaded = false) and seeds itself.
func reset_for_new_game() -> void:
	loaded = false
	money = GameSettings.economy.player_starting_money
	stat_values.clear()
	unlocks.clear()
	has_inventory = false
	inventory_stacks.clear()
	equipped_index = -1
	reputation.clear()
	time_of_day = 0.5            # a fresh run opens at noon
	status_effects.clear()      # ...with no carried buffs/debuffs
	current_level_path = ""     # ...and GameRoot starts from its exported level, not a saved one
	_clock_apply_pending = true # ...and the Player pushes that noon onto the live WorldClock (which free-ran on the menu)
	flags.clear()  # a fresh run forgets all story flags
	_quests_active.clear()
	_quests_completed.clear()
	_quests_failed.clear()  # WR-6
	perk_paths.clear()
	perk_grants.clear()
	xp = 0.0
	level = 0
	skill_points = 0
	points_earned = 0
	Reputation.reset()  # wipe live faction standings too — a fresh run starts neutral with everyone
	clear()  # forget the respawn point

## Set the point a death brings the player back to (a bonfire, or the player's initial spawn).
func set_respawn(position: Vector3, yaw: float) -> void:
	respawn_position = position
	respawn_yaw = yaw
	has_respawn = true

## Forget the respawn point (a fresh game).
func clear() -> void:
	has_respawn = false
	respawn_position = Vector3.ZERO
	respawn_yaw = 0.0

# --- Story flags (designer / quest world-state; see `flags`) -------------------------------------------------
## Set a story flag. `value` defaults to true (the common "mark that this happened" case). String-keyed so a
## StringName arg and a String ConfigFile key never miss each other (the Dictionary StringName-vs-String trap).
func set_flag(flag: StringName, value: Variant = true) -> void:
	flags[String(flag)] = value
	if value:
		_advance_flag_objectives(flag)  # a FLAG quest objective fires when its flag is set (the universal hook)
		_expire_quests_on_flag(flag)    # WR-6: a flag can also CLOSE a quest's window (expire_on_flag -> auto-fail)
	_autosave_world_state()  # world state changed — persist so a quit doesn't lose it (Dark-Souls-style)

## WR-6: fail every ACTIVE quest whose expire_on_flag matches `flag` (the "you missed the window" trigger — e.g.
## set the flag when the hostage dies / the timer ends). Collect ids first since fail_quest mutates _quests_active.
func _expire_quests_on_flag(flag: StringName) -> void:
	var to_fail: Array = []
	for qid in _quests_active:
		var q: Quest = _quests_active[qid].get("quest")
		if q != null and q.expire_on_flag == flag:
			to_fail.append(qid)
	for qid in to_fail:
		fail_quest(qid)

## A flag's value, or `fallback` (default false) when it was never set — so an unset bool flag reads as false.
func get_flag(flag: StringName, fallback: Variant = false) -> Variant:
	return flags.get(String(flag), fallback)

## Has this flag been set at all (to any value)?
func has_flag(flag: StringName) -> bool:
	return flags.has(String(flag))

# --- Quests (the live tracker; see `_quests_active` / `_quests_completed`) ------------------------------------
## Begin tracking `quest` — no-op if it's null/idless, already active, or already completed. Seeds each
## objective's progress to 0 and emits quest_started.
func start_quest(quest: Quest) -> void:
	if quest == null or quest.id == &"" or is_quest_active(quest.id) or is_quest_completed(quest.id) or is_quest_failed(quest.id):
		return  # WR-6: a failed quest is closed for good — it can't be re-started
	if quest.prereq_quest_id != &"" and not is_quest_completed(quest.prereq_quest_id):
		return  # a prerequisite quest hasn't been finished yet — this one can't start
	var progress := {}
	for obj in quest.objectives:
		if obj != null and obj.id != &"":
			progress[String(obj.id)] = 0
	_quests_active[quest.id] = {"quest": quest, "progress": progress}
	quest_started.emit(quest)
	_autosave_world_state()  # a started quest is world state — persist it

## Bump an active quest's objective toward its required_count (clamped). Auto-completes the quest once every
## non-optional objective is met (when the quest auto_completes). No-op for an unknown quest/objective.
func advance_objective(quest_id: StringName, objective_id: StringName, amount: int = 1) -> void:
	if not is_quest_active(quest_id):
		return
	var entry: Dictionary = _quests_active[quest_id]
	var quest: Quest = entry["quest"]
	var obj := _quest_objective(quest, objective_id)
	if obj == null:
		return
	var key := String(objective_id)
	var progress: Dictionary = entry["progress"]
	progress[key] = mini(int(progress.get(key, 0)) + amount, obj.required_count)
	objective_advanced.emit(quest, obj)
	if quest.auto_complete and _all_required_done(quest, progress):
		complete_quest(quest_id)  # this autosaves via complete_quest, so don't double-save below
	else:
		_autosave_world_state()  # objective progress is world state — persist it

## Finish an active quest: move it to completed, grant its rewards, emit quest_completed. Works as an explicit
## turn-in or via auto-complete.
func complete_quest(quest_id: StringName) -> void:
	if not is_quest_active(quest_id):
		return
	var entry: Dictionary = _quests_active[quest_id]
	var quest: Quest = entry["quest"]
	_quests_active.erase(quest_id)
	_quests_completed[quest_id] = quest  # store the Quest (not just a flag) so the journal can show completed titles
	_grant_quest_rewards(quest)
	quest_completed.emit(quest)
	_autosave_world_state()  # quest finished + rewards granted — a milestone; persist the run
	if quest.next_quest != null:
		start_quest(quest.next_quest)  # chain: finishing this quest auto-starts the next stage

## WR-6: FAIL an active quest — move it to failed, emit quest_failed. No rewards, no chaining (a failed quest is
## a dead end). No-op for a quest that isn't active (already completed/failed/never started). Drives the FAILED
## dialogue gate + a journal strike-through. Called explicitly (a dialogue consequence) or by an expire_on_flag.
func fail_quest(quest_id: StringName) -> void:
	if not is_quest_active(quest_id):
		return
	var entry: Dictionary = _quests_active[quest_id]
	var quest: Quest = entry["quest"]
	_quests_active.erase(quest_id)
	_quests_failed[quest_id] = quest  # store the Quest (like completed) so the journal can show failed titles
	quest_failed.emit(quest)
	_autosave_world_state()  # a failed quest is a permanent world-state change — persist it

func is_quest_active(quest_id: StringName) -> bool:
	return _quests_active.has(quest_id)

func is_quest_completed(quest_id: StringName) -> bool:
	return _quests_completed.has(quest_id)

func is_quest_failed(quest_id: StringName) -> bool:
	return _quests_failed.has(quest_id)

func active_quest_ids() -> Array:
	return _quests_active.keys()

## The Quest resource for an ACTIVE quest id (null if it isn't active) — for the journal UI.
func active_quest(quest_id: StringName) -> Quest:
	var entry: Variant = _quests_active.get(quest_id)
	return entry["quest"] if entry != null else null

## The completed Quest resources (for the journal's "done" list).
func completed_quests() -> Array:
	var out: Array = []
	for q in _quests_completed.values():
		if q is Quest:
			out.append(q)
	return out

## WR-6: the failed Quest resources (for the journal's "failed" list).
func failed_quests() -> Array:
	var out: Array = []
	for q in _quests_failed.values():
		if q is Quest:
			out.append(q)
	return out

## An active objective's current count (0 when the quest/objective isn't active).
func objective_progress(quest_id: StringName, objective_id: StringName) -> int:
	if not is_quest_active(quest_id):
		return 0
	return int(_quests_active[quest_id]["progress"].get(String(objective_id), 0))

## Is an objective satisfied (count >= required)? A completed quest reports all its objectives done.
func is_objective_done(quest_id: StringName, objective_id: StringName) -> bool:
	if is_quest_completed(quest_id):
		return true
	if not is_quest_active(quest_id):
		return false
	var obj := _quest_objective(_quests_active[quest_id]["quest"], objective_id)
	return obj != null and int(_quests_active[quest_id]["progress"].get(String(objective_id), 0)) >= obj.required_count

func _quest_objective(quest: Quest, objective_id: StringName) -> QuestObjective:
	if quest == null:
		return null
	for obj in quest.objectives:
		if obj != null and obj.id == objective_id:
			return obj
	return null

func _all_required_done(quest: Quest, progress: Dictionary) -> bool:
	for obj in quest.objectives:
		if obj == null or obj.optional:
			continue
		if int(progress.get(String(obj.id), 0)) < obj.required_count:
			return false
	return true

## Grant a completed quest's rewards: faction reputation (global), then the player's money / xp / items. Requires
## an in-tree GameState with a live player; off-tree (a bare test / no SceneTree) it early-returns and grants
## NOTHING (not even reputation — the group lookup below needs get_tree()). In real play this always runs in-tree.
func _grant_quest_rewards(quest: Quest) -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	# Reputation rewards are GLOBAL standing (faction_id -> delta), applied via the Reputation autoload.
	for fid in quest.reward_reputation:
		var faction := Factions.by_id(str(fid))
		if faction != null:
			Reputation.add_reputation(faction, float(quest.reward_reputation[fid]))
	# The HUMAN player, not a companion (the &"Player" group also holds recruited companions, which ARE NPCs). The
	# old &"player" lowercase group was never populated, so player was always null here and quest money/xp/item
	# rewards never actually landed.
	var player := _live_player()
	if player == null:
		return
	if quest.reward_money != 0.0 and player.has_method(&"add_money"):
		player.add_money(quest.reward_money)
	if quest.reward_xp != 0.0 and player.has_method(&"add_xp"):
		player.add_xp(quest.reward_xp)
	if not quest.rewards.is_empty():
		var inv: Variant = player.get(&"inventory")
		if inv is CharacterInventory:
			# The bag may be spatial-capped (opt-in Tetris grid) and silently drop overflow — surface the shortfall
			# rather than vanishing reward items. Compare the placed item count before/after seeding; if fewer items
			# landed than the rewards total, toast/log it so the player knows to make room (the items aren't refunded —
			# seed_into stops at the first full add, matching the rest of the loot pipeline).
			var bag := inv as CharacterInventory
			var before := _reward_item_total(bag)
			ItemStack.seed_into(bag, quest.rewards)
			var wanted := 0
			for r in quest.rewards:
				if r != null and r.item != null and r.count > 0:
					wanted += r.count
			var placed := _reward_item_total(bag) - before
			if placed < wanted:
				var msg := "Inventory full — %d quest reward item(s) couldn't fit" % (wanted - placed)
				if player.has_method(&"notify_toast"):
					player.notify_toast(msg, Color(1.0, 0.6, 0.3))
				else:
					push_warning("GameState: " + msg)

## Total item UNITS currently in `bag` (summed stack counts) — used to measure how many quest reward items
## actually fit after seed_into, so a spatial-capped bag's silent overflow can be surfaced to the player.
func _reward_item_total(bag: CharacterInventory) -> int:
	var total := 0
	for s in bag.placed_contents():
		total += int(s["count"])
	return total

## Advance every active objective of `obj_type` whose target_id matches `target` — the shared body behind the
## FLAG (set_flag) / KILL / PICKUP / TALK objective hooks.
func _advance_objectives_matching(obj_type: int, target: StringName) -> void:
	for quest_id in _quests_active.keys():
		var entry: Variant = _quests_active.get(quest_id)
		if entry == null:
			continue
		var quest: Quest = entry["quest"]
		for obj in quest.objectives:
			if obj != null and obj.type == obj_type and obj.target_id == target:
				advance_objective(quest_id, obj.id, 1)

## A FLAG objective fires when its flag is set — the universal hook (any trigger/lock/dialogue flag drives a quest).
func _advance_flag_objectives(flag: StringName) -> void:
	_advance_objectives_matching(QuestObjective.Type.FLAG, flag)

## A player KILL of an NPC named `target_name` (from npc._on_died) advances matching KILL objectives.
func notify_kill(target_name: StringName) -> void:
	_advance_objectives_matching(QuestObjective.Type.KILL, target_name)

## The player PICKED UP an item with id `item_id` (from CanPickUp) — advance matching PICKUP objectives.
func notify_pickup(item_id: StringName) -> void:
	_advance_objectives_matching(QuestObjective.Type.PICKUP, item_id)

## The player started TALKING to an NPC named `npc_name` (from DialogueManager.start) — advance TALK objectives.
func notify_talk(npc_name: StringName) -> void:
	_advance_objectives_matching(QuestObjective.Type.TALK, npc_name)

## The player ENTERED an area named `area_name` (from a TriggerVolume) — advance matching ENTER_AREA objectives.
func notify_enter(area_name: StringName) -> void:
	_advance_objectives_matching(QuestObjective.Type.ENTER_AREA, area_name)

## The player USED an item with id `item_id` (from Player.use_consumable) — advance matching USE_ITEM objectives.
func notify_use(item_id: StringName) -> void:
	_advance_objectives_matching(QuestObjective.Type.USE_ITEM, item_id)
