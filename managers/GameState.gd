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

const SAVE_PATH := "user://gamestate.cfg"
## The six CharacterStats, by name — the columns of the [stats] save section (mirrors CharacterStats / LevelUp).
## (agility was previously omitted, so a leveled agility didn't survive a save — fixed by including it here.)
const STAT_NAMES: Array[StringName] = [&"strength", &"persuasion", &"gunplay", &"endurance", &"streetwise", &"agility"]

## Quest signals (for the journal UI / listeners). The quest tracker lives here on GameState so it persists with
## the rest of the run profile — the spec's sanctioned "or extend GameState", which also dodges a project.godot
## autoload edit (that file carries the user's other uncommitted work).
signal quest_started(quest: Quest)
signal objective_advanced(quest: Quest, objective: QuestObjective)
signal quest_completed(quest: Quest)

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
## resolved back through ItemDb.restore_item); equipped_index is WHICH stack was the drawn weapon (-1 = fists).
var has_inventory: bool = false
var inventory_stacks: Array = []
var equipped_index: int = -1

## Saved FACTION STANDINGS — faction_id (String) -> standing (float). Captured from the Reputation autoload;
## the Player applies them back via Reputation.restore on a loaded game (a fresh game starts at zero). Empty
## until a run earns some, and an older save with no [reputation] section simply loads none.
var reputation: Dictionary = {}

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
	has_respawn = _cfg_bool(cfg, "respawn", "has", false)
	respawn_position = _cfg_vec3(cfg, "respawn", "position", Vector3.ZERO)
	respawn_yaw = _cfg_float(cfg, "respawn", "yaw", 0.0)
	# Back-compat: a save written before inventory persisted has no [inventory] section — has_inventory stays
	# false and the Player seeds its authored loadout, exactly as those saves behaved when written.
	has_inventory = cfg.has_section("inventory")
	var raw_stacks = cfg.get_value("inventory", "stacks", []) if has_inventory else []
	inventory_stacks = raw_stacks if raw_stacks is Array else []
	equipped_index = _cfg_int(cfg, "inventory", "equipped", -1) if has_inventory else -1
	loaded = true
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
	# Written only when a bag was actually captured — so a profile that never captured one (nothing has called
	# capture with a real player yet) doesn't stamp an empty [inventory] section over the seed-on-load path.
	if has_inventory:
		cfg.set_value("inventory", "stacks", inventory_stacks)
		cfg.set_value("inventory", "equipped", equipped_index)
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
	# The backpack — when the player carries one (a bare unit-test player has no inventory; the fields are
	# then left as-is). Each stack serializes as {id, count} in stack order, PLUS its grid placement {x, y, w, h}
	# when the bag's spatial cap is on (the player's Tetris grid) so the layout survives a reload; equipped_index
	# records which SERIALIZED stack holds the drawn weapon. An item with no Item.id can't round-trip — skipped
	# with a warning (register it in resources/items/ to make it persist).
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
			# Placement only when the stack is actually on a grid (x >= 0) — an unbounded bag writes plain
			# {id, count}, which loads back as an auto-place (the back-compat shape).
			if int(s["x"]) >= 0:
				entry["x"] = int(s["x"])
				entry["y"] = int(s["y"])
				entry["w"] = int(s["w"])
				entry["h"] = int(s["h"])
			inventory_stacks.append(entry)

## Capture `player` and write the save — the autosave seam every milestone calls. Off-tree (a bare player in a
## unit test) it does NOTHING: writing would clobber the user's real save during a test run. Real gameplay always
## autosaves from an in-tree player.
func autosave(player: Node) -> void:
	if player == null or not player.is_inside_tree():
		return
	capture(player)
	save_to_disk()

## Build a CharacterStats sheet from the saved stat values — handed to the Player BEFORE its super._ready so
## _apply_stats stamps max_hp / carry from the saved build. An unset stat defaults to baseline 0.
func make_stats() -> CharacterStats:
	var s := CharacterStats.new()
	for n in STAT_NAMES:
		s.set(n, int(stat_values.get(n, 0)))
	return s

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
	flags.clear()  # a fresh run forgets all story flags
	_quests_active.clear()
	_quests_completed.clear()
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
	if quest == null or quest.id == &"" or is_quest_active(quest.id) or is_quest_completed(quest.id):
		return
	var progress := {}
	for obj in quest.objectives:
		if obj != null and obj.id != &"":
			progress[String(obj.id)] = 0
	_quests_active[quest.id] = {"quest": quest, "progress": progress}
	quest_started.emit(quest)

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
		complete_quest(quest_id)

## Finish an active quest: move it to completed, grant its rewards, emit quest_completed. Works as an explicit
## turn-in or via auto-complete.
func complete_quest(quest_id: StringName) -> void:
	if not is_quest_active(quest_id):
		return
	var entry: Dictionary = _quests_active[quest_id]
	var quest: Quest = entry["quest"]
	_quests_active.erase(quest_id)
	_quests_completed[quest_id] = true
	_grant_quest_rewards(quest)
	quest_completed.emit(quest)

func is_quest_active(quest_id: StringName) -> bool:
	return _quests_active.has(quest_id)

func is_quest_completed(quest_id: StringName) -> bool:
	return _quests_completed.has(quest_id)

func active_quest_ids() -> Array:
	return _quests_active.keys()

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

## Grant a completed quest's rewards to the player — money + items (reputation rewards are deferred until
## faction-id resolution lands). No player in the tree (a bare test / off-tree GameState) -> grants nothing.
func _grant_quest_rewards(quest: Quest) -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null:
		return
	if quest.reward_money != 0.0 and player.has_method(&"add_money"):
		player.add_money(quest.reward_money)
	if not quest.rewards.is_empty():
		var inv: Variant = player.get(&"inventory")
		if inv is CharacterInventory:
			ItemStack.seed_into(inv as CharacterInventory, quest.rewards)

## A FLAG quest objective whose target_id matches a just-set flag advances by one — the universal objective hook,
## since every flag a trigger / lock / dialogue sets can now drive a quest step. Called from set_flag.
func _advance_flag_objectives(flag: StringName) -> void:
	for quest_id in _quests_active.keys():
		var entry: Variant = _quests_active.get(quest_id)
		if entry == null:
			continue
		var quest: Quest = entry["quest"]
		for obj in quest.objectives:
			if obj != null and obj.type == QuestObjective.Type.FLAG and obj.target_id == flag:
				advance_objective(quest_id, obj.id, 1)

## A player KILL of an NPC named `target_name` (called from npc._on_died on a player-attributed death) advances
## matching KILL objectives across active quests.
func notify_kill(target_name: StringName) -> void:
	for quest_id in _quests_active.keys():
		var entry: Variant = _quests_active.get(quest_id)
		if entry == null:
			continue
		var quest: Quest = entry["quest"]
		for obj in quest.objectives:
			if obj != null and obj.type == QuestObjective.Type.KILL and obj.target_id == target_name:
				advance_objective(quest_id, obj.id, 1)
