extends Node
## @system Save Model
## @seam capture() -> save_to_disk atomically write the versioned user://gamestate.cfg; load_from_disk restores it and sets loaded/profile_active, the flags gating Player._ready — a checkpoint, not a world snapshot.
## @risk Breaking _write_atomic's tmp->bak->rename rotation (e.g. dropping the Windows remove-before-rename guard) only loses the sole save on a real crash; the happy path keeps succeeding, so tests never surface it.
## @risk A field wired into only some of capture/save_to_disk/load_from_disk silently defaults on Continue; a STAT_NAMES rename with no SAVE_VERSION migration drops those points (cf. :228).
## @risk Dropping capture()'s Zorkmids.ITEM_ID skip (:420) double-counts money on load; applying respawn_position while ignoring respawn_level_matches teleports the player into the wrong level.
## @test res://tests/test_game_save.gd
## @test res://tests/test_save_slots.gd

## @system Save Model
## @seam The additive per-object ledger world_objects[level][key]=state (record_object_state/object_state/has_object_state, :779-797) persists Door open/locked + consumed-pickup/destroyed-prop 'gone' bits per authored object.
## @risk A changed WorldSaveId key or a stricter :247-258 Dictionary-shape filter silently drops ledger entries — pickups respawn (free money), doors revert, smashed props un-smash; load still returns true.
## @risk Reading a 'gone' bit with bare truthiness instead of GameState.as_bool falsely despawns a fresh pickup (or crashes via bool(<String>)) on a hand-edited String value.
## @risk A new persistable object type not wired through record_object_state + a save_id export silently never enters the ledger — its state just doesn't persist.
## @test res://tests/test_game_save.gd
## GameState — the live run's autosaved PROFILE + its RESPAWN point.
##
## Dark Souls style, ONE autosave (the run's checkpoint; a separate manual quicksave + 3 slots are the ML-1 layer below): the run persists to user://gamestate.cfg so quitting and
## relaunching resumes where you left off. The profile is the player's progression — money, the stat sheet, the
## unlocked mechanics, and the backpack (items + the drawn weapon, keyed by Item.id through ItemDb) — plus the
## respawn point (the last bonfire, or the initial spawn). It is captured + written
## at every milestone: a wallet change (kill bounty / trade / pickup), a level-up, an upgrade pickup, and a
## bonfire rest. On DEATH the world is NOT reloaded — you're brought back to LIFE at the respawn point (enemies
## stay as they are); the autosave is the only thing that survives quitting.
##
## Boot: this autoload's _ready loads the save (if any) into memory, so the start menu can offer "Continue" and
## the Player's _ready can apply the loaded build. "New Game" calls reset_for_new_game() to start clean.
##
## SAVE SCOPE — this is a PROFILE / checkpoint save with an ADDITIVE per-object ledger, NOT an exact world
## snapshot. It persists the player's progression (money, stats, unlocks, perks, backpack), the run's world FLAGS +
## QUEST state + faction standing + day/night clock, discovered Corpse markers, and the ACTIVE LEVEL identity
## (current_level_path, so a reload returns you to the level the saved respawn belongs to). It ALSO now persists a
## NAMED per-placed-object ledger (world_objects, keyed by level + WorldSaveId.key_for): a Door's open/locked
## state, and a consumed CanPickUp / MoneyPickUp / UpgradePickup / destroyed CanDestroy prop's "gone" bit — so an
## opened door stays open, a collected pickup stays collected (no respawn / infinite-money), and a smashed crate
## stays smashed on Continue. It STILL does NOT persist: looted / refilled containers, dead NPCs,
## dynamically-spawned entities (loot drops / encounter NPCs), or NPC positions — and it is NOT an exact snapshot
## (only touched, authored objects are in the ledger). LIVE WEAPON CLIP ammo is not persisted either: every gun
## loads a FULL magazine on Continue (the backpack's spare-CLIP reserve DOES persist) — a deliberate
## fresh-magazine-per-session choice. The ledger is additive: it never rebrands the profile save as an exact
## quicksave. See CLAUDE.md "Save semantics must be explicit".

const SAVE_PATH := "user://gamestate.cfg"
## Save schema version, stamped into [meta].version on every write (H1b). Bump ONLY for a BREAKING change to an
## existing key's MEANING; additive new sections stay back-compatible via their has_section checks. A pre-versioning
## save (no [meta]) reads 0. v2 (C43) was the FIRST version-gated read: the 2026-07-09 stat overhaul renamed the
## "persuasion" stat to "streetwise", so a <v2 save's persuasion points are folded into streetwise on load (the
## stat-load loop drops unknown keys, so without the migration those points would silently vanish). v3 is the SECOND:
## the "stealth" and "pickpocket" stats were consolidated into a single "larceny" stat, so a <v3 save's stealth AND
## pickpocket points both fold into larceny on load. Re-saving stamps the current version and each migration re-runs
## never. Future breaking migrations branch on save_version the same way (separate `if` branches, so a very old save
## runs every fold it needs in one load).
const SAVE_VERSION := 3
## The CharacterStats, by name — the columns of the [stats] save section. Derived from CharacterStats.STAT_NAMES
## (the single source; cannot drift — a stat added there becomes a save column here for free). Missing keys default
## to 0, so older mid-development profile saves migrate softly. A compile-time const fold (no autoload/cycle issue).
const STAT_NAMES: Array[StringName] = CharacterStats.STAT_NAMES
## Faction registry — resolves a quest's reward_reputation faction ids to live Faction resources for the grant.
const Factions := preload("res://scripts/faction/factions.gd")
## Exact-snapshot serializer for the manual save tier (preloaded, NOT class_name — no global-class-cache
## dependency, so headless GUT compiles GameState without a prior --import; matches Factions above / WorldSaveId).
const WorldSnapshot = preload("res://scripts/world/world_snapshot.gd")

## Quest signals (for the journal UI / listeners). The quest tracker lives here on GameState so it persists with
## the rest of the run profile — the spec's sanctioned "or extend GameState", which also dodges a project.godot
## autoload edit (that file carries the user's other uncommitted work).
signal quest_started(quest: Quest)
signal objective_advanced(quest: Quest, objective: QuestObjective)
signal quest_completed(quest: Quest)
## WR-6: a quest was FAILED (explicit fail_quest, or its expire_on_flag fired). Wire a journal strike-through / toast.
signal quest_failed(quest: Quest)

## THE WORLD MAY RESET NOW — the player died and the death cinematic's screen has just gone FULLY BLACK, right as
## the "You were killed by X" card comes up (emitted from Player._on_death_screen_covered, a tween callback; NOT
## from die(), which is ~1.6 s earlier while the vignette is still closing and the world is plainly visible).
## Listeners are expected to REARRANGE THE WORLD, so the timing is the contract: fire anything visible here and it
## lands behind the black instead of on screen. Runs after the killer-aware Character._on_killed_by hook (which
## settles provoked grudges), so the two compose — the town calms down AND goes home.
##
## A CUE, not save state: nothing about it is captured or written. It lives on this autoload (rather than each
## listener hunting down the Player node) so a listener can connect once at _ready with no spawn-order handshake,
## and keep that connection across an NpcPool reuse. First consumer: the NpcHomeReturn leash
## (scripts/npc/npc_home_return.gd), which blinks every NPC back to its authored post — the default
## CHECKPOINT_RESPAWN death mode leaves the world untouched, so without it an encounter never resets.
signal player_died()

## True once a save has been loaded into the fields below (boot found a file, or Continue was chosen). The Player's
## _ready reads this: true -> apply the saved build (stats / money / unlocks / teleport); false -> a fresh game.
var loaded: bool = false
## True once a real run is authoritative IN MEMORY — set by a disk load OR by character creation (New Game). Unlike
## `loaded` it is NOT cleared by a scene reload, so a New-Game session survives a RELOAD_CHECKPOINT_FRESH death: the
## death path promotes `loaded = true` when this is set, so the fresh Player APPLIES the in-memory run (unlocks/xp/
## money/inventory) instead of reseeding a default build (P0-2). A dev boot straight into game.tscn leaves it false.
var profile_active: bool = false
## The [meta].version of the loaded save (0 = a pre-versioning save; SAVE_VERSION after a New Game). Recorded on load
## and now CONSUMED by the C43 <v2 persuasion→streetwise stat migration in load_from_disk (H1b's first version-gated
## read); future breaking migrations branch on it the same way.
var save_version: int = 0
## saved wallet (fractional zorkmids — see Zorkmids); fresh-game seed reads the economy tuning group
## (explicitly annotated, NOT ':='-inferred off the GameSettings chain). EconomySettings' default is 0.0 (the player starts broke).
var money: float = GameSettings.economy.player_starting_money
## The character's chosen NAME (set once at character creation; "" for an unnamed or pre-naming save). Persisted in
## the [player] save section and applied to the live Player (Player.player_name) for display on the Stats screen.
## Never changes in-game, so capture() leaves it alone — it's authored at creation and simply carried on every save.
var player_name: String = ""
## The character's chosen APPEARANCE (head/body customizer), a lightweight save-friendly dict — NOT a live
## resource, so it round-trips cleanly through the ConfigFile save. Keys (all optional): "head"/"body" = String
## part ids into CharacterAppearanceCatalog, "skin"/"arm"/"leg" = Colour tints, "shirt" = a player-DRAWN torso
## texture stored as PNG BYTES (PackedByteArray; decoded by CharacterAppearanceCatalog.shirt_texture). EMPTY = never
## customised -> every consumer (the creation/Stats preview) falls back to the catalog's shipped default look.
## Authored at character creation and simply carried on every save (capture() leaves it, like player_name —
## appearance never changes in-game). A stored part id that's since been removed from the catalog resolves to the
## default on load.
var appearance: Dictionary = {}
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

## Lightweight per-marker corpse discovery ledger. This is deliberately narrower than full object persistence:
## it only stores the one-shot "an NPC has already reacted to this Corpse" marker, keyed by Corpse.save_key()
## (which now delegates to the shared WorldSaveId.key_for, so it keys identically to the world_objects ledger).
var discovered_corpses: Dictionary = {}

## The "Stranger until introduced" name ledger: real NPC names the player has LEARNED, keyed by the name string
## itself (used as a set). Until a name is in here, every player-facing surface shows PlayerText.STRANGER in its
## place (see public_name) — a designer opens the gate by ticking DialogueLine.reveals_name on the line where the
## NPC says who they are, which calls reveal_name during that conversation. Persisted in [world].known_names and
## CLEARED on New Game (a fresh run re-meets everyone as a stranger). Keyed by name, so two NPCs sharing one
## authored display_name are "the same person" once introduced — fine, since generic mob names never get revealed.
var known_names: Dictionary = {}

## Dev/global master switch for the masking above. true (default) = the shipped "everyone is a Stranger until
## introduced" behaviour; flip to false at runtime (console / a debug tool) to show every real name outright — the
## pre-feature behaviour, useful when authoring. NOT a player-facing Settings row and deliberately NOT serialized:
## it resets to true each launch so a debug flip never bakes into a save.
var stranger_names_enabled: bool = true

## The additive per-object WORLD-STATE ledger (v1): { level_path -> { object_key -> state Dictionary } }. A door's
## {"open","locked"}, a consumed pickup / destroyed prop's {"gone": true}. Keyed by level + WorldSaveId.key_for so
## each authored object round-trips independently. This is STILL a profile save with a named-object ledger, NOT an
## exact world snapshot — untouched objects, dynamically-spawned entities, and NPC positions are not captured.
var world_objects: Dictionary = {}

## --- EXACT-snapshot save tier (WorldSnapshot; manual quicksave/slots ONLY) -----------------------------------
## The in-memory exact snapshot for the manual save tier. NON-NULL only after a manual quicksave/slot save built
## one (in _capture_and_write) or a load pulled one off disk; the lean autosave/Continue path leaves it NULL and
## save_to_disk therefore never writes a [world_snapshot] section into gamestate.cfg. NOT part of the profile —
## kept structurally separate so the two save products can never blur (CLAUDE.md "Save semantics must be explicit").
var world_snapshot: WorldSnapshot = null
## One-shot: a load that carried a [world_snapshot] sets this true; GameRoot's post-level-load hook consumes it
## exactly once to apply the snapshot (a twin of _clock_apply_pending / consume_clock_apply). False on a
## profile-only load, a death-respawn reload, or a fresh game — so those never apply a snapshot.
var _world_snapshot_pending: bool = false
## Latched between "a quickload/slot-load has loaded a save into memory + requested a scene reload" and "the fresh scene's
## GameRoot has booted" (cleared in set_current_level). While set, autosave() refuses to run: a one-frame-deferred autosave
## flush queued in the SAME frame as the load (a kill bounty / a door fire) would otherwise run AFTER load_from_disk, on the
## still-in-tree OLD player, and overwrite the just-loaded profile (and null the pending world_snapshot) with the abandoned
## timeline's state — then persist that franken-profile over the sole checkpoint. See _load_and_reload / autosave.
var _reload_pending: bool = false
## Live per-level ledger of authored NPCs that have died this run: { level_path -> { snapshot_key: true } }.
## Fed by record_npc_death (each NPC's died signal), read by WorldSnapshot.capture (a dead NPC has freed itself,
## so it can't be seen in the tree at capture time), and reloaded from a snapshot on a snapshot load so post-load
## deaths keep accumulating. Not persisted by the profile — it only reaches disk folded into a WorldSnapshot.
var _dead_authored: Dictionary = {}

## QUESTS — the live tracker (kept here so it persists with the profile). _quests_active: quest_id ->
## { quest: Quest, progress: { objective_id(String): int } }; _quests_completed: a set of finished quest ids.
var _quests_active: Dictionary = {}
var _quests_completed: Dictionary = {}
## WR-6: failed/expired quest ids -> the Quest resource (mirrors _quests_completed). A failed quest can't be
## re-started or completed; a FAILED dialogue gate + the journal read this.
var _quests_failed: Dictionary = {}
## B-F40: user-facing warnings from the LAST profile load — one line per saved quest whose .tres failed to load
## (the resource was moved/renamed/deleted), which would otherwise drop the quest SILENTLY (progress lost). The HUD
## (ui.gd) consumes these on _ready via take_load_warnings() and toasts them. Repopulated each load; empty on a clean
## one. (Composes with a later QuestTracker split — this field would move with the tracker.)
var _load_warnings: Array[String] = []
const HOLSTER_FORGIVENESS_TUTORIAL_SEEN_FLAG := &"tutorial_holster_forgiveness_seen"
var _holster_forgiveness_tutorial_reminder_pending: bool = false
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
## Boot-only gate (M3): false when this was a LOADED game whose saved level identity (current_level_path) could NOT be
## honored — its .tres was deleted/renamed or is scene-less, so GameRoot booted the EXPORTED level instead. The saved
## respawn belongs to that now-unloaded level, so the Player must NOT teleport to it (GameRoot instead places at the
## booted level's spawn + re-seeds a valid respawn). True in every normal case: a fresh game, an honored saved level,
## OR a legacy/old save with no recorded level identity (a blank path — we don't second-guess it). Set once in
## GameRoot._ready(), read once by Player._ready(); a runtime death-respawn is unaffected (its respawn is the live level's).
var respawn_level_matches: bool = true

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
		# Atomic-write recovery (H1): the primary is missing/unreadable only if a crash struck the tiny rename window in
		# save_to_disk. Prefer a complete ".tmp" (the interrupted NEWEST write — a partial one fails to load and is
		# skipped), then the ".bak" (the previous good checkpoint). A fresh game has none of the three, so it's unloaded.
		if cfg.load(path + ".tmp") == OK:
			push_warning("GameState: primary save '%s' unreadable — recovered the interrupted latest write from .tmp." % path)
		elif cfg.load(path + ".bak") == OK:
			push_warning("GameState: primary save '%s' unreadable — recovered from .bak (the last write may be lost)." % path)
		else:
			loaded = false
			return false
	save_version = _cfg_int(cfg, "meta", "version", 0)  # H1b: 0 = a pre-versioning save; recorded for a future migration
	money = _cfg_float(cfg, "player", "money", GameSettings.economy.player_starting_money)  # missing/junk -> the fresh-game knob; older saves stored ints, _cfg_float casts them
	player_name = _cfg_str(cfg, "player", "name", "")  # missing / junk-typed -> unnamed via the type guard (name is always written as a String, so this is lossless); a raw String(<Variant>) cast could raise "Invalid constructor" and abort the load
	# Appearance (head/body customizer): rebuild the dict from whatever's present, type-guarded. A missing section
	# (older save / never customised) leaves it EMPTY -> consumers use the catalog default. Junk-typed values drop.
	appearance.clear()
	if cfg.has_section("appearance"):
		for sk in ["head", "body"]:
			var sv = cfg.get_value("appearance", sk, "")
			if sv is String and not (sv as String).is_empty():
				appearance[sk] = sv
		for ck in ["skin", "arm", "leg"]:
			# has_section_key first: get_value with a null default treats it as NO default and error-logs on a
			# missing key (an older save without the key spams the boot log otherwise).
			if not cfg.has_section_key("appearance", ck):
				continue
			var cv = cfg.get_value("appearance", ck)
			if cv is Color:
				appearance[ck] = cv
		# The player-drawn t-shirt (the "Shirt" creation tab): a tiny PNG kept as bytes. Type-guarded like the rest;
		# a missing / junk / empty value just leaves the character on its base shirt (CharacterAppearanceCatalog).
		if cfg.has_section_key("appearance", "shirt"):
			var shirt = cfg.get_value("appearance", "shirt")
			if shirt is PackedByteArray and not (shirt as PackedByteArray).is_empty():
				appearance["shirt"] = shirt
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
	# C43: pre-2026-07-09 saves stored a "persuasion" stat later renamed to "streetwise"; the loop above ignores keys
	# not in STAT_NAMES and so silently drops the points. Fold the legacy value into streetwise for any save older
	# than v2 so the build survives the rename. A current save has no persuasion key (has_section_key false -> no-op);
	# a fresh game already stamps save_version = SAVE_VERSION (v2, reset_for_new_game), so it never runs. Re-saving
	# migrates the file to v2 and this branch never re-runs. save_version was read above (from [meta].version).
	if save_version < 2 and cfg.has_section("stats") and cfg.has_section_key("stats", "persuasion"):
		stat_values[&"streetwise"] = int(stat_values.get(&"streetwise", 0)) + _cfg_int(cfg, "stats", "persuasion", 0)
	# v3 (2026-07-16): the "stealth" and "pickpocket" stats were consolidated into ONE "larceny" stat. A <v3 save
	# stored points under both legacy keys; the stat-load loop above only reads STAT_NAMES (which now carries larceny,
	# not stealth/pickpocket), so both would silently vanish. Fold BOTH legacy values into larceny. A separate `if`
	# from the persuasion branch above so a v1 save runs BOTH folds in one load. A current save has neither legacy key
	# (no-op), and re-saving stamps v3 so this never re-runs. larceny didn't exist pre-v3, so it starts at 0 here.
	if save_version < 3 and cfg.has_section("stats"):
		var legacy_larceny := _cfg_int(cfg, "stats", "stealth", 0) + _cfg_int(cfg, "stats", "pickpocket", 0)
		if legacy_larceny != 0:
			stat_values[&"larceny"] = int(stat_values.get(&"larceny", 0)) + legacy_larceny
	reputation.clear()
	if cfg.has_section("reputation"):
		for fid in cfg.get_section_keys("reputation"):
			reputation[fid] = _cfg_float(cfg, "reputation", fid, 0.0)  # junk -> 0; faction id is the key
	flags.clear()
	if cfg.has_section("flags"):
		for f in cfg.get_section_keys("flags"):
			flags[f] = cfg.get_value("flags", f, null)  # String key; the value round-trips as its stored Variant
	discovered_corpses.clear()
	var raw_corpses = cfg.get_value("world", "discovered_corpses", [])
	if raw_corpses is Array:
		for key in raw_corpses:
			var k := str(key)
			if not k.is_empty():
				discovered_corpses[k] = true
	known_names.clear()
	var raw_known = cfg.get_value("world", "known_names", [])
	if raw_known is Array:
		for nm in raw_known:
			var s := str(nm)
			if not s.is_empty():
				known_names[s] = true
	# World-object ledger: one nested Dictionary under [world_objects].data. Corrupt-safe — keep only
	# level_path -> { key -> state } entries whose shapes are Dictionaries; anything junk-typed degrades to empty.
	world_objects.clear()
	var raw_wo = cfg.get_value("world_objects", "data", {})
	if raw_wo is Dictionary:
		for lvl in raw_wo:
			var per = raw_wo[lvl]
			if per is Dictionary:
				var clean := {}
				for ok in per:
					if per[ok] is Dictionary:
						clean[str(ok)] = per[ok]
				if not clean.is_empty():
					world_objects[str(lvl)] = clean
	# Exact-snapshot tier: a MANUAL quicksave/slot file carries a [world_snapshot] section; the lean autosave does
	# not. Its ABSENCE is the back-compat path (a profile-only load leaves world_snapshot null + nothing pending —
	# byte-identical to today). A version we don't understand is ignored (profile still loads). On a real snapshot
	# load we also reload the live death ledger from it so deaths AFTER the load keep accumulating onto the right set.
	world_snapshot = null
	_world_snapshot_pending = false
	_dead_authored.clear()
	if cfg.has_section_key("world_snapshot", "data"):
		var ws_ver := _cfg_int(cfg, "world_snapshot", "version", 0)
		var ws_raw = cfg.get_value("world_snapshot", "data", {})
		if ws_ver == WorldSnapshot.SNAPSHOT_VERSION and ws_raw is Dictionary:
			world_snapshot = WorldSnapshot.new()
			world_snapshot.from_dict(ws_raw)
			_world_snapshot_pending = true
			_dead_authored = world_snapshot.dead_map()
		else:
			push_warning("GameState: [world_snapshot] version %d unsupported — loaded the profile only." % ws_ver)
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
	profile_active = true  # a disk-loaded run is authoritative in memory (P0-2)
	_clock_apply_pending = true  # a genuine disk-load: the Player applies the saved clock ONCE (not on a respawn reload)
	return true

## --- Type-guarded ConfigFile reads (see load_from_disk): junk-typed values fall back to the default
## instead of erroring in a conversion or a typed assignment. Numeric kinds convert freely between each
## other (an int 1 read as bool/float is fine); anything else is junk. _cfg_str is the same guard for a
## String value — String(<Variant>) can raise "Invalid constructor" on some junk-typed values (which would
## abort load_from_disk before `loaded = true`), so it returns the value only when it IS a String. ---
static func _cfg_int(cfg: ConfigFile, section: String, key: String, fallback: int) -> int:
	var v = cfg.get_value(section, key, fallback)
	return int(v) if (v is int or v is float or v is bool) else fallback

static func _cfg_float(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	var v = cfg.get_value(section, key, fallback)
	return float(v) if (v is int or v is float or v is bool) else fallback

static func _cfg_bool(cfg: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var v = cfg.get_value(section, key, fallback)
	return bool(v) if (v is bool or v is int or v is float) else fallback

static func _cfg_str(cfg: ConfigFile, section: String, key: String, fallback: String) -> String:
	var v = cfg.get_value(section, key, fallback)
	return v if v is String else fallback

static func _cfg_vec3(cfg: ConfigFile, section: String, key: String, fallback: Vector3) -> Vector3:
	var v = cfg.get_value(section, key, fallback)
	return v if v is Vector3 else fallback

## Write the in-memory profile to `path`. Unlocks are stored as plain Strings (clean round-trip), re-typed to
## StringName on load. The respawn fields are written straight from memory (kept current by set_respawn).
## Returns ConfigFile.save()'s Error so callers can tell a real write failure (disk full / permission / bad
## path) from a success instead of assuming it worked — a failed write also push_warnings (-> ErrorSink), so an
## autosave that silently can't persist still surfaces. void-discarding callers (autosave) keep working unchanged.
func save_to_disk(path := SAVE_PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)  # H1b: stamp the schema version FIRST so a future load can migrate
	cfg.set_value("player", "money", money)
	cfg.set_value("player", "name", player_name)
	# Appearance (head/body customizer): stamp only the keys that are set, so an uncustomised profile writes no
	# [appearance] section at all (load treats a missing section as "use the catalog default", identical behaviour).
	if not appearance.is_empty():
		for ak in ["head", "body", "skin", "arm", "leg"]:
			if appearance.has(ak):
				cfg.set_value("appearance", ak, appearance[ak])
		# The drawn shirt is stored as PNG BYTES. Guarded so a stray live-texture value (the creator holds an
		# ImageTexture in-memory; character_creation._on_begin converts it to bytes before emitting) never reaches
		# the config, which can't serialise a Texture.
		var shirt = appearance.get("shirt")
		if shirt is PackedByteArray and not (shirt as PackedByteArray).is_empty():
			cfg.set_value("appearance", "shirt", shirt)
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
	if not discovered_corpses.is_empty():
		var corpse_keys := discovered_corpses.keys()
		corpse_keys.sort()
		cfg.set_value("world", "discovered_corpses", corpse_keys)
	if not known_names.is_empty():
		var name_keys := known_names.keys()
		name_keys.sort()
		cfg.set_value("world", "known_names", name_keys)
	if not world_objects.is_empty():
		cfg.set_value("world_objects", "data", world_objects)  # nested Dictionary round-trips through ConfigFile
	# Exact-snapshot tier: write [world_snapshot] ONLY when a manual save populated one (autosave nulls world_snapshot
	# first, so it can never leak into gamestate.cfg). Its own version stamp is decoupled from [meta].version. Empty
	# snapshots are skipped so the section never bloats a save. This is what keeps the profile and the snapshot separate.
	if world_snapshot != null and not world_snapshot.is_empty():
		cfg.set_value("world_snapshot", "version", WorldSnapshot.SNAPSHOT_VERSION)
		cfg.set_value("world_snapshot", "data", world_snapshot.to_dict())
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
	return _write_atomic(cfg, path)


## Atomic write (H1): ConfigFile.save truncates-then-writes IN PLACE, so a crash / power-loss mid-write corrupts the
## ONLY autosave (this is a one-slot, Dark-Souls design) — total run loss. Write to a sibling ".tmp", then atomically
## rename it OVER the target (rename is atomic within a volume), after rotating the previous good file to ".bak" (which
## load_from_disk falls back to). A crash now costs at most the last write. On Windows a rename onto an EXISTING file
## fails, so the destination is always removed/rotated away first (guarded by file_exists so a missing sibling can't
## emit a stray engine error). The absolute DirAccess statics need no opened directory, so there's no dir-open edge.
func _write_atomic(cfg: ConfigFile, path: String) -> Error:
	var tmp_path := path + ".tmp"
	var bak_path := path + ".bak"
	var err := cfg.save(tmp_path)
	if err != OK:
		push_warning("GameState: save to %s FAILED (Error %d) — the profile did NOT persist." % [tmp_path, err])
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)  # don't strand a partial temp
		return err
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)     # clear the old .bak first (Windows rename fails onto an existing dest)
		DirAccess.rename_absolute(path, bak_path)   # rotate the prior good save to .bak (recoverable prior checkpoint)
	err = DirAccess.rename_absolute(tmp_path, path)  # atomically swap the new save into place
	if err != OK:
		push_warning("GameState: atomic swap into %s FAILED (Error %d) — the profile did NOT persist." % [path, err])
	return err

## Read the live run off `player` into the in-memory profile (money, stats, the unlocked mechanics). The
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
			if it.id == Zorkmids.ITEM_ID:
				# The zorkmids coin pile is a DERIVED mirror of the wallet float (MoneyPurse), and the wallet is
				# already persisted as [player] `money` above. Skipping it here keeps ONE source of truth: saving
				# the stack too would double-count on load (money restored AND the stack restored, then re-mirrored).
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
		# A prop pulled from the backpack to be HELD in hand (Hotbar hold -> Player.hold_item) was REMOVED from `inv`
		# above, so the loop didn't capture it. Fold it back into the snapshot as {id, count:1} (auto-placed on load)
		# so a save taken while it's in your hands never loses it — a reload isn't carrying anything, so the item just
		# lands back in the bag. Skipped for an id-less item (can't round-trip) or the money pile (mirrored elsewhere).
		var held_it: Item = player.held_inventory_item() if player.has_method(&"held_inventory_item") else null
		if held_it != null and held_it.id != &"" and held_it.id != Zorkmids.ITEM_ID:
			inventory_stacks.append({"id": String(held_it.id), "count": 1})
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
	# A quickload/slot-load is mid-flight (load_from_disk done, scene reload requested but not yet booted): the OLD player
	# is still in-tree, so a same-frame deferred flush must NOT capture it over the freshly-loaded profile. Bail — the
	# fresh scene will autosave normally once GameRoot boots (which clears this latch via set_current_level).
	if _reload_pending:
		return
	world_snapshot = null  # the lean autosave/Continue profile NEVER carries an exact snapshot — clear any that a
	_world_snapshot_pending = false  # (and its consume flag) so a stale pending can't ride into the reloaded scene
						   # prior manual quicksave left in memory so save_to_disk can't write one into gamestate.cfg.
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

## Exact-snapshot tier: consume-once the "a loaded save carried a [world_snapshot]" flag. GameRoot calls this after
## the level subtree is ready; true -> apply GameState.world_snapshot to the reloaded world (a manual quickload),
## false -> no-op (Continue / autosave load / death-respawn reload / fresh game). Twin of consume_clock_apply.
func consume_world_snapshot() -> bool:
	var pending := _world_snapshot_pending
	_world_snapshot_pending = false
	return pending

## Exact-snapshot tier: record that an authored NPC (keyed by its POSITION-FREE NPC.snapshot_key) has died, into the
## live per-level ledger a later manual quicksave folds into its WorldSnapshot. Called from NPC's died signal. No
## disk write here — deaths reach disk only when the player takes a manual quicksave/slot save. Empty key ignored.
func record_npc_death(level_path: String, key: String) -> void:
	if key.is_empty():
		return
	if not (_dead_authored.get(level_path) is Dictionary):
		_dead_authored[level_path] = {}
	_dead_authored[level_path][key] = true

## Exact-snapshot tier: free every authored NPC in `tree` whose snapshot_key is in this level's death ledger — so an NPC
## the player killed EARLIER (this session via record_npc_death, OR restored dead from a quicksave via dead_map) STAYS
## dead when the level re-instantiates: a door A->B->A return, or the boot after a load. Called by GameRoot.load_level on
## EVERY load (deferred, after NPC _ready has settled so snapshot_key resolves in-tree). A silent queue_free — NOT a death
## (no FX / loot re-roll; corpse reconstruction is a later phase). Deferred queue_free is safe while iterating the group
## snapshot. Dynamic (spawner) NPCs never enter _dead_authored, so only authored bodies are suppressed. Empty ledger / no
## tree -> no-op, so a fresh game or a lean Continue (no snapshot -> empty ledger) suppresses nothing.
func suppress_dead_authored(tree: SceneTree, level_path: String) -> void:
	if tree == null:
		return
	var dead: Variant = _dead_authored.get(level_path)
	if not (dead is Dictionary) or (dead as Dictionary).is_empty():
		return
	for n in tree.get_nodes_in_group(Groups.NPC):
		if not is_instance_valid(n) or n.is_queued_for_deletion() or not n.has_method(&"snapshot_key"):
			continue
		if (dead as Dictionary).has(str(n.snapshot_key())):
			n.queue_free()

## Record the LevelData GameRoot just loaded (its resource_path) so the next save knows which level to reload.
## Called by GameRoot.load_level on every level load (boot + door swaps). Blank for a code-built LevelData.
func set_current_level(path: String) -> void:
	# The fresh scene's GameRoot has booted — a quickload/slot-load reload (if any) is complete, so lift the autosave
	# freeze. Harmless on every non-reload level load (the latch is already false).
	_reload_pending = false
	current_level_path = path

# --- Manual save / quicksave / named slots (ML-1) -----------------------------------------------------------
## These layer over the path-parameterized save_to_disk(path) / load_from_disk(path). They are SEPARATE files from
## the Dark-Souls autosave (SAVE_PATH): quitting still resumes the autosave. Unlike the lean autosave, a quick/slot
## save is the EXACT-snapshot tier — it writes the profile+ledger PLUS a [world_snapshot] section (built in
## _capture_and_write) so a load restores the WORLD as it was, not just your progression. The two products stay
## distinct on purpose (autosave = lean profile, quick/slot = exact snapshot; see docs "Save semantics must be
## explicit"). RESTORED by a scene reload (load_from_disk sets loaded=true, then reload_current_scene rebuilds a
## fresh Player that re-applies the build; GameRoot then applies the snapshot) — we never mutate the live player,
## the same contract as boot / Continue. A quick/slot save also stamps the respawn point at the player's CURRENT
## position so a load returns you exactly where you saved (not the last bonfire).
## UI STATUS: only the QUICKSAVE is player-reachable in-game (F5/F9 in player.gd). The named SLOTS have no
## player-facing save/load screen yet — they exist for code/tests and the read-only CYBER SUNDAY "Saves" dock.
const QUICKSAVE_PATH := "user://quicksave.cfg"
const SLOT_COUNT := 3  ## how many manual save slots exist (1..SLOT_COUNT). No player-facing slot UI is wired yet (see above).

## Disk path for manual slot `slot` (1-based); the index is clamped so a bad caller can't escape user://.
func slot_path(slot: int) -> String:
	return "user://save_slot_%d.cfg" % clampi(slot, 1, SLOT_COUNT)

## Does a quicksave / the given manual slot exist on disk? (Read today by the editor Saves dock + tests; a future
## player-facing save/load screen would gate its "load" affordances on these.)
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
## there), capture the live run, write to `path`. Returns the write's success — true ONLY when the file actually
## persisted, so a caller's "Saved!" feedback can't fire over a failed disk write (disk full / permission).
func _capture_and_write(player: Node, path: String) -> bool:
	if player == null or not player.is_inside_tree():
		return false
	set_respawn(player.global_position, player.rotation.y)  # a quick/slot save IS your new checkpoint
	capture(player)
	# Exact-snapshot tier: the manual path (and ONLY this path — autosave never calls here) builds a WorldSnapshot of the
	# live world (current level's live NPCs + its dead ledger), THEN folds in every OTHER level's death ledger so a
	# cross-level kill survives a quickload (you door back into a cleared level and it stays cleared). save_to_disk writes
	# it as [world_snapshot]; a load reloads the full ledger via dead_map() and load_level suppresses the dead per level.
	world_snapshot = WorldSnapshot.new()
	if is_inside_tree() and get_tree() != null:
		world_snapshot.capture(get_tree(), current_level_path, _dead_authored.get(current_level_path, {}))
	world_snapshot.fold_dead_ledger(_dead_authored, current_level_path)  # other levels aren't in the tree — dead keys only
	return save_to_disk(path) == OK

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
		InputManager.close_all_modals()  # release any autoload screen bound to a soon-freed scene node before the reload (T1)
		Engine.time_scale = 1.0
		# Latch so a same-frame deferred autosave flush (queued BEFORE this load) can't overwrite the just-loaded profile
		# on the still-in-tree old player. Cleared when the fresh scene's GameRoot boots (set_current_level).
		_reload_pending = true
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
	_load_warnings.clear()  # B-F40: fresh warnings for THIS load (the HUD consumes them once)
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
				_load_warnings.append(PlayerText.SAVE_WARN_ACTIVE_QUEST_MISSING)
				continue
			var prog = rec.get("progress", {})
			_quests_active[StringName(qid)] = {"quest": q, "progress": (prog if prog is Dictionary else {})}
	_quests_completed.clear()
	if cfg.has_section("quests_completed"):
		for qid in cfg.get_section_keys("quests_completed"):
			var q := load(str(cfg.get_value("quests_completed", qid, ""))) as Quest
			if q == null:
				push_warning("GameState: completed quest '%s' path didn't load — skipped" % qid)
				_load_warnings.append(PlayerText.SAVE_WARN_COMPLETED_QUEST_MISSING)
				continue
			_quests_completed[StringName(qid)] = q
	_quests_failed.clear()  # WR-6: mirror the completed load
	if cfg.has_section("quests_failed"):
		for qid in cfg.get_section_keys("quests_failed"):
			var q := load(str(cfg.get_value("quests_failed", qid, ""))) as Quest
			if q == null:
				push_warning("GameState: failed quest '%s' path didn't load — skipped" % qid)
				_load_warnings.append(PlayerText.SAVE_WARN_FAILED_QUEST_MISSING)
				continue
			_quests_failed[StringName(qid)] = q

## B-F40: hand the HUD the last load's quest-restore warnings and CLEAR them (consume-once, so a HUD rebuild on a
## level change doesn't re-toast old warnings). Returns [] after a clean load. ui.gd calls this in _ready.
func take_load_warnings() -> Array:
	var w := _load_warnings.duplicate()
	_load_warnings.clear()
	return w

## The holster-forgiveness tutorial is shown once as a normal tutorial, but a death to the same provoked NPC queues
## a one-shot reminder for the next live Player (in-place respawn OR reload-style death).
func holster_forgiveness_tutorial_seen() -> bool:
	return get_flag_bool(HOLSTER_FORGIVENESS_TUTORIAL_SEEN_FLAG, false)

func mark_holster_forgiveness_tutorial_seen() -> void:
	set_flag(HOLSTER_FORGIVENESS_TUTORIAL_SEEN_FLAG, true)

func queue_holster_forgiveness_tutorial_reminder() -> void:
	_holster_forgiveness_tutorial_reminder_pending = true

func consume_holster_forgiveness_tutorial_reminder() -> bool:
	var pending := _holster_forgiveness_tutorial_reminder_pending
	_holster_forgiveness_tutorial_reminder_pending = false
	return pending

## Start a brand-new run: drop the loaded profile back to fresh-game defaults and forget the respawn point. The
## disk file is left until the first autosave overwrites it (so a New-Game-then-quit doesn't lose a prior save
## before any progress is actually made). The Player then ignores the profile (loaded = false) and seeds itself.
func reset_for_new_game() -> void:
	loaded = false
	profile_active = false  # cleared here; character creation re-sets it once the run is real (P0-2)
	save_version = SAVE_VERSION   # H1b: a fresh run is current-schema
	respawn_level_matches = true  # M3: a fresh run has no stale saved level identity to mismatch
	money = GameSettings.economy.player_starting_money
	player_name = ""             # a fresh run is unnamed until character creation stamps a name
	appearance.clear()           # ...and un-customised until character creation stamps a look (empty -> catalog default)
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
	discovered_corpses.clear()
	known_names.clear()  # ...and re-meets every NPC as a Stranger until they re-introduce themselves
	world_objects.clear()  # a fresh run forgets every door/pickup/prop world-state marker
	world_snapshot = null          # ...and any in-memory exact snapshot (matters on a RELOAD_CHECKPOINT_FRESH death,
	_world_snapshot_pending = false #    which keeps in-memory GameState — a fresh run must never apply a stale snapshot)
	_dead_authored.clear()
	_quests_active.clear()
	_quests_completed.clear()
	_quests_failed.clear()  # WR-6
	_load_warnings.clear()  # C44: forget any prior boot-load's quest-restore warnings so a fresh game doesn't toast them
	_holster_forgiveness_tutorial_reminder_pending = false
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

## Coerce an arbitrary Variant to bool WITHOUT crashing. bool() in Godot 4 has no String (or Array/Object/…)
## constructor — bool(<String>) throws "Invalid call. Nonexistent 'bool' constructor" — so any bool read of a
## value that persisted data could type-pollute (a flag, a world_objects ledger entry) must funnel through here
## instead of a bare bool(). Numeric kinds convert freely (int 1 / float 0.0 -> bool); anything else -> fallback.
func as_bool(value: Variant, fallback: bool = false) -> bool:
	return bool(value) if (value is bool or value is int or value is float) else fallback

## get_flag coerced to bool. A flag round-trips as its stored Variant (get_flag), so a hand-edited / legacy
## gamestate.cfg can hold a String under a flag key; `bool(get_flag(...))` would then crash. Bool consumers of a
## flag call this instead.
func get_flag_bool(flag: StringName, fallback: bool = false) -> bool:
	return as_bool(get_flag(flag, fallback), fallback)

## Has this flag been set at all (to any value)?
func has_flag(flag: StringName) -> bool:
	return flags.has(String(flag))

# --- Lightweight world markers -------------------------------------------------------------------------------
## Has a Corpse marker already drawn an NPC reaction? Empty keys are never persisted or matched.
func is_corpse_discovered(key: String) -> bool:
	return not key.is_empty() and discovered_corpses.has(key)

## Record a Corpse marker's one-shot discovery and queue the same coalesced world-state autosave used by flags.
func mark_corpse_discovered(key: String) -> void:
	if key.is_empty() or discovered_corpses.has(key):
		return
	discovered_corpses[key] = true
	_autosave_world_state()

# --- "Stranger until introduced" name ledger (see known_names / stranger_names_enabled) ----------------------
## Learn `real_name` — from now on public_name returns it outright instead of "Stranger", everywhere and across a
## save. Called by DialogueManager when a line with reveals_name = true plays. No-op on a blank/already-known name
## (blanks aren't identities); persists via the same coalesced world-state autosave flags/corpses use.
func reveal_name(real_name: String) -> void:
	var nm := real_name.strip_edges()
	if nm.is_empty() or known_names.has(nm):
		return
	known_names[nm] = true
	_autosave_world_state()

## Has the player been introduced to `real_name` (or is masking off)? Blank names are never "unknown" — an NPC
## with no authored name has nothing to hide, so it never reads as a Stranger.
func name_is_revealed(real_name: String) -> bool:
	var nm := real_name.strip_edges()
	return nm.is_empty() or not stranger_names_enabled or known_names.has(nm)

## THE display-name seam: the name to SHOW the player for a character whose true name is `real_name` — the real
## name once introduced (or masking off, or the name blank), else the "Stranger" placeholder. DISPLAY ONLY; every
## player-facing NPC-name surface routes through this, but quest/kill/talk matching keeps the TRUE name (public
## masking must never leak into identity — a "kill <name>" objective still needs the real string).
func public_name(real_name: String) -> String:
	if name_is_revealed(real_name):
		return real_name
	return PlayerText.STRANGER

# --- Per-object world-state ledger (doors / consumed pickups / destroyed props) ------------------------------
## Record `state` for the object `key` under `level_path`, and queue the coalesced world-state autosave. Keyed by
## level so the ledger remembers every visited level; empty keys are ignored (a fallback-keyed object with no path).
func record_object_state(level_path: String, key: String, state: Dictionary) -> void:
	if key.is_empty():
		return
	if not (world_objects.get(level_path) is Dictionary):
		world_objects[level_path] = {}
	world_objects[level_path][key] = state
	_autosave_world_state()

## The saved state Dictionary for `key` under `level_path`, or {} if none (never null — callers read `.get(...)`).
func object_state(level_path: String, key: String) -> Dictionary:
	var per = world_objects.get(level_path)
	if per is Dictionary and per.get(key) is Dictionary:
		return per[key]
	return {}

## Whether any state was saved for `key` under `level_path` (so a container can tell "restore" from "seed").
func has_object_state(level_path: String, key: String) -> bool:
	var per = world_objects.get(level_path)
	return per is Dictionary and per.has(key)

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
	# M15: back-fill FLAG objectives whose flag is ALREADY set — a CHAINED quest that keys on a flag an earlier quest
	# (or any trigger/dialogue) already flipped. set_flag won't fire again, so without this the objective stalls at 0.
	# Mirror the live set_flag hook (advance_objective, same call as _advance_flag_objectives) so it advances / auto-
	# completes identically to a flag set while active. get_flag defaults false, so a falsey/unset flag is NOT satisfied.
	for obj in quest.objectives:
		if obj != null and obj.id != &"" and obj.type == QuestObjective.Type.FLAG and get_flag(obj.target_id):
			advance_objective(quest.id, obj.id, 1)
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
				var msg := PlayerText.quest_rewards_full(wanted - placed)
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
