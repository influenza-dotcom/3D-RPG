class_name DebugCommands
extends RefCounted

## The PURE half of the in-game debug tools: the command registry, the line parser, argument validation and
## tab-completion. No tree access, no autoloads, no disk — everything here is a static function over plain data,
## so GUT can cover it off-tree (the project's pure/glue split, same shape as WireShapes vs AiDebugDraw).
##
## WHO READS THIS
##  - `DebugConsole` (scripts/components/debug_console.gd) — parses a typed line, completes on Tab, prints help.
##  - `DebugMenu` (scripts/components/debug_menu.gd) — builds its clickable pages straight from CATEGORIES /
##    in_category(), and its search bar from search(), so a command added here shows up in BOTH surfaces —
##    and is FINDABLE in the menu — with no second edit. That is the whole point of the registry: one table,
##    two front-ends.
##  - `DebugActionsPlayer` / `DebugActionsWorld` — the IMPURE halves that actually touch the game. Each row's
##    `mod` names which one runs it; `&"meta"` rows are handled by the console itself (they need its scrollback).
##
## ADDING A COMMAND: add a row here, then a `case` in the matching actions module. Keep `min_args`/`max_args`
## honest — the console rejects a bad arity before the action ever runs, so actions can trust their argv length.
##
## DEV-ONLY: every string in this file is developer copy that must never reach a player or a translation
## catalog, which is why the console/menu that paint it are listed in ScanText.SKIP_FILES. This file itself
## paints nothing (it only returns Strings), so it is not — and must not become — a paint site.

## What a positional argument accepts. Drives completion (the console supplies the live id list per kind) and
## the `<x>`/`[x]` usage text. NONE is the "this command takes no argument in this slot" filler.
enum Kind {
	NONE,
	TOGGLE,   ## on / off / (blank = flip)
	NUMBER,   ## any float; the action decides whether a negative or zero is legal
	TEXT,     ## free text, no completion
	COMMAND,  ## another command's name (help)
	ITEM,     ## Item id           -> ItemIds.ids()
	NPC,      ## NpcData archetype -> resources/characters/*.tres
	LEVEL,    ## LevelData         -> resources/levels/*.tres
	QUEST,    ## Quest.id          -> resources/quests/*.tres (id, NOT filename)
	FACTION,  ## Faction id        -> Factions.ids()
	PERK,     ## Perk id           -> Perks.ids()
	EFFECT,   ## StatusEffect id   -> resources/status/*.tres
	FLAG,     ## story flag        -> GameState.flags.keys()
	STAT,     ## CharacterStats stat name
	ABILITY,  ## mechanic/ability id -> AbilityRegistry.ids() (+ "all")
	VERB,     ## a fixed word list carried on the row itself (`verbs`)
}

## Completion-source keys the console hands to `complete()`. Kept as constants so the console and the tests
## cannot drift on a spelling.
const SOURCE_KEYS := {
	Kind.COMMAND: &"command",
	Kind.ITEM: &"item",
	Kind.NPC: &"npc",
	Kind.LEVEL: &"level",
	Kind.QUEST: &"quest",
	Kind.FACTION: &"faction",
	Kind.PERK: &"perk",
	Kind.EFFECT: &"effect",
	Kind.FLAG: &"flag",
	Kind.STAT: &"stat",
	Kind.ABILITY: &"ability",
}

const TOGGLE_WORDS := ["on", "off"]

## Display order for the menu's pages and the grouped `help` listing. A category that appears on a row but not
## here would sort to the end — `categories()` derives from the rows, this only orders them.
const CATEGORIES: Array[String] = ["Player", "Economy", "World", "AI", "Story", "View", "Meta"]

## THE REGISTRY. One row per command.
##  name      — what you type. Lowercase, no spaces.
##  mod       — &"player" | &"world" | &"meta": which actions module runs it (meta = the console itself).
##  category  — the menu page it lands on; must be one of CATEGORIES.
##  args      — Kind per positional slot, in order. Length is the MAXIMUM arity.
##  min_args  — how many of those are required.
##  arg_names — display names for usage text; same length as `args`.
##  verbs     — for a Kind.VERB slot, the allowed words (also its completion source).
##  help      — one line, imperative, shown by `help` and as the menu button's tooltip.
##  danger    — true if it destroys progress or writes the player's save irreversibly. The menu confirms these;
##              the console prints a warning line. (Every state mutator here writes the profile save eventually —
##              `danger` is reserved for the ones you cannot walk back.)
const COMMANDS: Array[Dictionary] = [
	# --- Meta ------------------------------------------------------------------------------------------------
	{
		"name": "help", "mod": &"meta", "category": "Meta",
		"args": [Kind.COMMAND], "min_args": 0, "arg_names": ["command"], "verbs": [],
		"help": "List every command, or show usage for one.", "danger": false,
	},
	{
		"name": "clear", "mod": &"meta", "category": "Meta",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Clear the console scrollback.", "danger": false,
	},
	{
		"name": "keys", "mod": &"meta", "category": "Meta",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Show the dev keys the debug drop-ins bind.", "danger": false,
	},
	{
		"name": "exec", "mod": &"meta", "category": "Meta",
		"args": [Kind.TEXT], "min_args": 1, "arg_names": ["file"], "verbs": [],
		"help": "Run a command file line by line (one command per line, `#` comments, `wait <frames>` supported). A bare name resolves under user://. `user://autoexec.cfg` runs by itself at boot in debug builds.",
		"danger": false,
	},
	{
		"name": "bind", "mod": &"meta", "category": "Meta",
		"args": [Kind.TEXT, Kind.TEXT], "min_args": 0, "arg_names": ["key", "line"], "verbs": [],
		"help": "Bind a dev key to a console line (quote it; `;` chains commands): `bind F6 \"god; noclip on\"`. `bind F6` clears, no arguments lists. Persisted in user://debug_binds.cfg.",
		"danger": false,
	},
	{
		"name": "errors", "mod": &"world", "category": "Meta",
		"args": [Kind.NUMBER], "min_args": 0, "arg_names": ["count"], "verbs": [],
		"help": "Dump the most recent engine errors/warnings captured by the F3 overlay's ErrorSink (newest last).",
		"danger": false,
	},
	{
		"name": "events", "mod": &"world", "category": "Meta",
		"args": [Kind.TEXT, Kind.TEXT], "min_args": 0, "arg_names": ["count / on / off / clear", "filter"], "verbs": [],
		"help": "Dump the game-event ticker ring (quests, reputation, phase, rent, dialogue, money/xp, effects, death, level, saves), newest last: `events [n] [filter]`; `events on|off` toggles the on-screen column, `events clear` empties it.",
		"danger": false,
	},
	{
		"name": "saves", "mod": &"world", "category": "Meta",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "How many disk writes the profile has taken this session, the last path/result, and whether the sandbox is on.",
		"danger": false,
	},

	# --- Player ----------------------------------------------------------------------------------------------
	{
		"name": "god", "mod": &"player", "category": "Player",
		"args": [Kind.TOGGLE], "min_args": 0, "arg_names": ["on/off"], "verbs": [],
		"help": "Immunity: banks armor_flat AND zeroes the continuous-fall death timer (which bypasses damage).",
		"danger": false,
	},
	{
		"name": "heal", "mod": &"player", "category": "Player",
		"args": [Kind.NUMBER], "min_args": 0, "arg_names": ["amount"], "verbs": [],
		"help": "Heal by amount, or to full when omitted. Also clears crippled limbs.", "danger": false,
	},
	{
		"name": "hurt", "mod": &"player", "category": "Player",
		"args": [Kind.NUMBER, Kind.VERB], "min_args": 1, "arg_names": ["amount", "body part"],
		"verbs": ["head", "arms", "legs", "torso"],
		"help": "Apply damage through the real take_damage path (armour and god mode still apply); name a body part to land it there for limb damage.",
		"danger": false,
	},
	{
		"name": "cripple", "mod": &"player", "category": "Player",
		"args": [Kind.VERB], "min_args": 1, "arg_names": ["body part"], "verbs": ["head", "arms", "legs"],
		"help": "Cripple a limb outright (the located-damage pool is drained), to test the limb penalties. `heal` clears it.",
		"danger": false,
	},
	{
		"name": "me", "mod": &"player", "category": "Player",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Player self-readout: the speed chain factor by factor, limbs, carry, hands/holster/draw-lock, the weapon hub, and every ability with its state.",
		"danger": false,
	},
	{
		"name": "ability", "mod": &"player", "category": "Player",
		"args": [Kind.ABILITY, Kind.VERB], "min_args": 0, "arg_names": ["ability id / all", "state"],
		"verbs": ["on", "off", "revoke"],
		"help": "Grant an ability by id (or `all`) through the real unlock path; `on`/`off` toggles an installed one, `revoke` removes it. No arguments lists them.",
		"danger": false,
	},
	{
		"name": "kill", "mod": &"player", "category": "Player",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Kill the player outright, running the full death sequence.", "danger": false,
	},
	{
		"name": "revive", "mod": &"player", "category": "Player",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Refill HP and clear the dead latch. Refuses mid-death-cinematic — wait for the respawn.",
		"danger": false,
	},
	{
		"name": "noclip", "mod": &"player", "category": "Player",
		"args": [Kind.TOGGLE], "min_args": 0, "arg_names": ["on/off"], "verbs": [],
		"help": "Fly the player body with no collision or gravity. Keeps the real camera, so the ink outline and view-model stay correct.",
		"danger": false,
	},
	{
		"name": "speed", "mod": &"player", "category": "Player",
		"args": [Kind.NUMBER], "min_args": 0, "arg_names": ["multiplier"], "verbs": [],
		"help": "Scale walk/run speed. No argument restores the authored value.", "danger": false,
	},
	{
		"name": "stamina", "mod": &"player", "category": "Player",
		"args": [Kind.NUMBER], "min_args": 0, "arg_names": ["amount"], "verbs": [],
		"help": "Set stamina, or refill to max when omitted.", "danger": false,
	},
	{
		"name": "tp", "mod": &"player", "category": "Player",
		"args": [Kind.NUMBER, Kind.NUMBER, Kind.NUMBER], "min_args": 3, "arg_names": ["x", "y", "z"], "verbs": [],
		"help": "Teleport to world coordinates.", "danger": false,
	},
	{
		"name": "tpaim", "mod": &"player", "category": "Player",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Teleport to whatever the crosshair is pointing at.", "danger": false,
	},
	{
		"name": "mark", "mod": &"player", "category": "Player",
		"args": [Kind.TEXT], "min_args": 0, "arg_names": ["name"], "verbs": [],
		"help": "Remember the current position for `back` — or, with a name, save a persistent bookmark for `goto <name>` (per level, user://debug_marks.cfg).",
		"danger": false,
	},
	{
		"name": "goto", "mod": &"player", "category": "Player",
		"args": [Kind.TEXT], "min_args": 1, "arg_names": ["name"], "verbs": [],
		"help": "Teleport to a named bookmark saved with `mark <name>` (this level's, or another level's if you warp first).",
		"danger": false,
	},
	{
		"name": "marks", "mod": &"player", "category": "Player",
		"args": [Kind.TEXT], "min_args": 0, "arg_names": ["name to delete"], "verbs": [],
		"help": "List the named bookmarks for this level (and how many other levels have some); `marks <name>` deletes one.",
		"danger": false,
	},
	{
		"name": "back", "mod": &"player", "category": "Player",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Teleport to the last `mark` (or the position you were at before the last teleport).",
		"danger": false,
	},
	{
		"name": "pos", "mod": &"player", "category": "Player",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Print the player's position, yaw and current level.", "danger": false,
	},
	{
		"name": "stat", "mod": &"player", "category": "Player",
		"args": [Kind.STAT, Kind.NUMBER], "min_args": 1, "arg_names": ["stat", "value"], "verbs": [],
		"help": "Set a base stat (omit the value to read it). Re-stamps derived max HP, carry and stamina.",
		"danger": false,
	},
	{
		"name": "stats", "mod": &"player", "category": "Player",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Print the whole stat sheet with its derived values.", "danger": false,
	},

	# --- Economy ---------------------------------------------------------------------------------------------
	{
		"name": "money", "mod": &"player", "category": "Economy",
		"args": [Kind.NUMBER], "min_args": 1, "arg_names": ["amount"], "verbs": [],
		"help": "Add zorkmids to the wallet (negative removes). Goes through add_money so the HUD and purse update.",
		"danger": false,
	},
	{
		"name": "bank", "mod": &"player", "category": "Economy",
		"args": [Kind.NUMBER], "min_args": 1, "arg_names": ["amount"], "verbs": [],
		"help": "Add to the signed bank account (negative overdraws). Snaps to the coin quantum.", "danger": false,
	},
	{
		"name": "credit", "mod": &"player", "category": "Economy",
		"args": [Kind.NUMBER], "min_args": 1, "arg_names": ["delta"], "verbs": [],
		"help": "Move credit standing by delta, through the clamped setter.", "danger": false,
	},
	{
		"name": "xp", "mod": &"player", "category": "Economy",
		"args": [Kind.NUMBER], "min_args": 1, "arg_names": ["amount"], "verbs": [],
		"help": "Grant XP. The difficulty multiplier applies, so the granted total is reported back.",
		"danger": false,
	},
	{
		"name": "sp", "mod": &"player", "category": "Economy",
		"args": [Kind.NUMBER], "min_args": 1, "arg_names": ["points"], "verbs": [],
		"help": "Grant perk/skill points directly, without the XP curve.", "danger": false,
	},
	{
		"name": "perk", "mod": &"player", "category": "Economy",
		"args": [Kind.PERK], "min_args": 1, "arg_names": ["perk id"], "verbs": [],
		"help": "Unlock a perk by id, ignoring its point cost.", "danger": false,
	},
	{
		"name": "perks", "mod": &"player", "category": "Economy",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "List every perk id and whether it is unlocked.", "danger": false,
	},
	{
		"name": "respec", "mod": &"player", "category": "Economy",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Refund every perk and hand the points back. Free — no station, no charge.", "danger": true,
	},
	{
		"name": "weapon", "mod": &"player", "category": "Economy",
		"args": [Kind.ITEM, Kind.NUMBER], "min_args": 1, "arg_names": ["weapon item id / none", "clips"], "verbs": [],
		"help": "Give a weapon AND draw it through both inventories (backpack + hub), with optional spare clips of its caliber. `none` holsters to fists.",
		"danger": false,
	},
	{
		"name": "ammo", "mod": &"player", "category": "Economy",
		"args": [Kind.VERB], "min_args": 0, "arg_names": ["mode"], "verbs": ["on", "off", "fill"],
		"help": "`fill` tops the magazine and stocks every ammo type; `on`/`off` toggles infinite ammo (no consumption). No argument reports the state.",
		"danger": false,
	},
	{
		"name": "level", "mod": &"player", "category": "Economy",
		"args": [Kind.NUMBER], "min_args": 1, "arg_names": ["level"], "verbs": [],
		"help": "Set the player level directly: up through add_xp (one level-up beat), down by writing xp/level and autosaving.",
		"danger": false,
	},
	{
		"name": "give", "mod": &"player", "category": "Economy",
		"args": [Kind.ITEM, Kind.NUMBER], "min_args": 1, "arg_names": ["item id", "count"], "verbs": [],
		"help": "Put an item in the backpack. Reports how many actually fit — the grid can refuse.",
		"danger": false,
	},
	{
		"name": "items", "mod": &"player", "category": "Economy",
		"args": [Kind.TEXT], "min_args": 0, "arg_names": ["filter"], "verbs": [],
		"help": "List item ids, optionally filtered by substring.", "danger": false,
	},
	{
		"name": "effect", "mod": &"player", "category": "Economy",
		"args": [Kind.EFFECT, Kind.NUMBER], "min_args": 1, "arg_names": ["effect id", "seconds"], "verbs": [],
		"help": "Apply a status effect. Duration 0 means permanent until cleared.", "danger": false,
	},
	{
		"name": "effects", "mod": &"player", "category": "Economy",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "List the status effects on disk and which are currently active.", "danger": false,
	},
	{
		"name": "cleareffects", "mod": &"player", "category": "Economy",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Remove every active status effect.", "danger": false,
	},
	{
		"name": "rep", "mod": &"player", "category": "Economy",
		"args": [Kind.FACTION, Kind.NUMBER], "min_args": 1, "arg_names": ["faction", "value"], "verbs": [],
		"help": "Set standing with a faction to an exact value (omit the value to read it). Bypasses the streetwise scaling.",
		"danger": false,
	},
	{
		"name": "reps", "mod": &"player", "category": "Economy",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "List every faction, its standing and the disposition that follows from it.", "danger": false,
	},

	# --- World -----------------------------------------------------------------------------------------------
	{
		"name": "time", "mod": &"world", "category": "World",
		"args": [Kind.TEXT], "min_args": 1, "arg_names": ["HH:MM or 0..1"], "verbs": [],
		"help": "SEEK the clock to a time. Fires no boundary events — no rent, no interest. Use `advance` to walk time.",
		"danger": false,
	},
	{
		"name": "advance", "mod": &"world", "category": "World",
		"args": [Kind.NUMBER], "min_args": 1, "arg_names": ["hours"], "verbs": [],
		"help": "WALK the clock forward, firing every phase boundary — rent, interest and dawn all resolve.",
		"danger": false,
	},
	{
		"name": "clock", "mod": &"world", "category": "World",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Print the time of day, phase, day length and rent status.", "danger": false,
	},
	{
		"name": "stationmusic", "mod": &"world", "category": "World",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Print the station-radio bed state (wanted / playing / track / dB / bus / gate).", "danger": false,
	},
	{
		"name": "wandermusic", "mod": &"world", "category": "World",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Print the wandering exploration bed (who owns the moment / calm / rest / dB / bus).", "danger": false,
	},
	{
		"name": "timescale", "mod": &"world", "category": "World",
		"args": [Kind.NUMBER], "min_args": 0, "arg_names": ["scale"], "verbs": [],
		"help": "Set Engine.time_scale and lock out bullet-time/hitstop so it sticks. No argument restores 1.0.",
		"danger": false,
	},
	{
		"name": "warp", "mod": &"world", "category": "World",
		"args": [Kind.LEVEL], "min_args": 1, "arg_names": ["level"], "verbs": [],
		"help": "Load a level by its LevelData resource.", "danger": false,
	},
	{
		"name": "levels", "mod": &"world", "category": "World",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "List the LevelData resources on disk and mark the active one.", "danger": false,
	},
	{
		"name": "reload", "mod": &"world", "category": "World",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Hard-reload the current scene.", "danger": false,
	},
	{
		"name": "save", "mod": &"world", "category": "World",
		"args": [Kind.NUMBER], "min_args": 0, "arg_names": ["slot"], "verbs": [],
		"help": "Quicksave, or save to a numbered slot. Moves your respawn checkpoint to here.", "danger": false,
	},
	{
		"name": "roundtrip", "mod": &"world", "category": "World",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Save/load round-trip fuzzer: capture the live run, write a SCRATCH save, hard-reload through the real load path, re-capture, and print a field-by-field identity diff. Reloads the scene.",
		"danger": true,
	},
	{
		"name": "soak", "mod": &"world", "category": "AI",
		"args": [Kind.NUMBER, Kind.NUMBER], "min_args": 0, "arg_names": ["npc count", "seconds"], "verbs": [],
		"help": "Run the SoakHarness on THIS level: spawn N wanderers, tick game time, report stranded NPCs (bad-bake islands) and node leaks. Slow — it walks real seconds.",
		"danger": false,
	},
	{
		"name": "load", "mod": &"world", "category": "World",
		"args": [Kind.NUMBER], "min_args": 0, "arg_names": ["slot"], "verbs": [],
		"help": "Quickload, or load a numbered slot. Reloads the scene.", "danger": true,
	},
	{
		"name": "sandbox", "mod": &"world", "category": "World",
		"args": [Kind.VERB], "min_args": 0, "arg_names": ["action"],
		"verbs": ["on", "off", "status", "commit"],
		"help": "Redirect every save (autosave, quicksave, slots) into user://sandbox/ so cheats never touch the real profile. `off` reloads the real profile; `commit` copies the sandbox over it.",
		"danger": true,
	},

	# --- AI --------------------------------------------------------------------------------------------------
	{
		"name": "spawn", "mod": &"world", "category": "AI",
		"args": [Kind.NPC, Kind.NUMBER], "min_args": 1, "arg_names": ["archetype", "count"], "verbs": [],
		"help": "Spawn NPCs from an NpcData archetype in front of you, marked as dynamic so they never enter the save ledger.",
		"danger": false,
	},
	{
		"name": "npcs", "mod": &"world", "category": "AI",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "List NPC archetypes on disk and count who is alive in the level.", "danger": false,
	},
	{
		"name": "killall", "mod": &"world", "category": "AI",
		"args": [Kind.NUMBER], "min_args": 0, "arg_names": ["radius"], "verbs": [],
		"help": "Kill every living NPC, or only those within a radius. Suppresses the per-kill hitstop.",
		"danger": false,
	},
	{
		"name": "peace", "mod": &"world", "category": "AI",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Clear provocations and grudges, and drop every NPC out of combat.", "danger": false,
	},
	{
		"name": "aggro", "mod": &"world", "category": "AI",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Provoke every NPC onto you, without the faction reputation penalty.", "danger": false,
	},
	{
		"name": "freezeai", "mod": &"world", "category": "AI",
		"args": [Kind.TOGGLE], "min_args": 0, "arg_names": ["on/off"], "verbs": [],
		"help": "Suspend perception, GOAP and locomotion on every NPC (the cutscene-control gate).", "danger": false,
	},
	{
		"name": "who", "mod": &"world", "category": "AI",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Dump the full live state of the NPC under your crosshair.", "danger": false,
	},
	{
		"name": "brain", "mod": &"world", "category": "AI",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "GOAP 'why this plan' for the NPC under your crosshair: sensed facts, every goal's priority/satisfied/plan cost, the goal the planner would pick NOW, and the plan the executor is actually stepping.",
		"danger": false,
	},
	{
		"name": "npc", "mod": &"world", "category": "AI",
		"args": [Kind.VERB, Kind.NUMBER], "min_args": 1, "arg_names": ["verb", "value"],
		"verbs": ["kill", "heal", "hostile", "neutral", "friendly", "provoke", "alert", "investigate", "walkto", "release", "home", "panic", "freeze", "unfreeze", "sight", "rebrain"],
		"help": "Act on the NPC under your crosshair (the F4 inspector's last physics-tick target). investigate/walkto use the crosshair hit point; `sight <r>` sets its sight range; `walkto` latches cutscene control until `release`.",
		"danger": false,
	},
	{
		"name": "ailog", "mod": &"world", "category": "AI",
		"args": [Kind.TEXT, Kind.TEXT], "min_args": 0, "arg_names": ["count / on / off / clear", "filter"], "verbs": [],
		"help": "Dump the AI transition log (perception state, target acquire/lose, goal change, provoke/stand-down, flee, freeze, stranded, spawn/free), newest last: `ailog [n] [filter]`; `ailog on|off` toggles its panel, `ailog clear` empties it. Needs the AiEventLog drop-in.",
		"danger": false,
	},
	{
		"name": "notarget", "mod": &"world", "category": "AI",
		"args": [Kind.TOGGLE], "min_args": 0, "arg_names": ["on/off"], "verbs": [],
		"help": "Ghost mode: no NPC can target, see or hear you, but the AI keeps running (unlike freezeai). Shooting one still provokes it — it just cannot find you.",
		"danger": false,
	},

	# --- Story -----------------------------------------------------------------------------------------------
	{
		"name": "flag", "mod": &"world", "category": "Story",
		"args": [Kind.FLAG, Kind.TEXT], "min_args": 1, "arg_names": ["flag", "value"], "verbs": [],
		"help": "Set a story flag (omit the value to read it, pass `clear` to erase the key).", "danger": false,
	},
	{
		"name": "flags", "mod": &"world", "category": "Story",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "List every story flag currently set.", "danger": false,
	},
	{
		"name": "quest", "mod": &"world", "category": "Story",
		"args": [Kind.VERB, Kind.QUEST, Kind.TEXT, Kind.NUMBER], "min_args": 2,
		"arg_names": ["action", "quest id", "objective id", "amount"],
		"verbs": ["start", "complete", "fail", "show", "advance"],
		"help": "Start, complete, fail or inspect a quest by its Quest.id (NOT the filename); `advance <quest> <objective> [n]` ticks one objective through the real cascade.",
		"danger": false,
	},
	{
		"name": "notify", "mod": &"world", "category": "Story",
		"args": [Kind.VERB, Kind.TEXT, Kind.TEXT], "min_args": 1, "arg_names": ["event", "target", "legacy name"],
		"verbs": ["kill", "talk", "pickup", "enter", "use"],
		"help": "Fire a quest world-hook (notify_kill/talk/pickup/enter/use) by id — omit the target for kill/talk to use the NPC under your crosshair.",
		"danger": false,
	},
	{
		"name": "ledger", "mod": &"world", "category": "Story",
		"args": [Kind.VERB], "min_args": 0, "arg_names": ["scope"], "verbs": ["all"],
		"help": "Read-only dump of the per-object save ledger (world_objects) for this level — or every level with `all` — plus the cross-level dead-NPC ledger and the snapshot/reload latches.",
		"danger": false,
	},
	{
		"name": "wipeobjects", "mod": &"world", "category": "Story",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Erase this level's world_objects ledger (doors/pickups/destroyed props go back to authored) and re-load the level in place.",
		"danger": true,
	},
	{
		"name": "resurrect", "mod": &"world", "category": "AI",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "Forget every authored NPC death recorded for this level (the cross-level ledger) and re-load the level in place so they stand again.",
		"danger": true,
	},
	{
		"name": "quests", "mod": &"world", "category": "Story",
		"args": [], "min_args": 0, "arg_names": [], "verbs": [],
		"help": "List quests on disk with their live active/completed/failed state.", "danger": false,
	},
	{
		"name": "names", "mod": &"world", "category": "Story",
		"args": [Kind.TOGGLE], "min_args": 0, "arg_names": ["on/off"], "verbs": [],
		"help": "Turn the stranger-name veil on or off, so everyone reads by their real name.", "danger": false,
	},

	# --- View ------------------------------------------------------------------------------------------------
	{
		"name": "inspect", "mod": &"world", "category": "View",
		"args": [Kind.TOGGLE], "min_args": 0, "arg_names": ["on/off"], "verbs": [],
		"help": "Toggle the look-at inspector: live state drawn over whatever you aim at.", "danger": false,
	},
	{
		"name": "navdebug", "mod": &"world", "category": "View",
		"args": [Kind.TOGGLE], "min_args": 0, "arg_names": ["on/off"], "verbs": [],
		"help": "Toggle the AI/nav overlay (sight cones, factions, GOAP labels, zones). Changes global navigation debug state.",
		"danger": false,
	},
	{
		"name": "perf", "mod": &"world", "category": "View",
		"args": [Kind.TOGGLE], "min_args": 0, "arg_names": ["on/off"], "verbs": [],
		"help": "Toggle the F3 performance HUD.", "danger": false,
	},
	{
		"name": "wireframe", "mod": &"world", "category": "View",
		"args": [Kind.TOGGLE], "min_args": 0, "arg_names": ["on/off"], "verbs": [],
		"help": "Render the world as wireframe.", "danger": false,
	},
	{
		"name": "overdraw", "mod": &"world", "category": "View",
		"args": [Kind.TOGGLE], "min_args": 0, "arg_names": ["on/off"], "verbs": [],
		"help": "Render the overdraw heat view.", "danger": false,
	},
	{
		"name": "screenshot", "mod": &"world", "category": "View",
		"args": [Kind.VERB], "min_args": 0, "arg_names": ["clean"], "verbs": ["clean"],
		"help": "Save the exact game canvas to user://screenshots/<timestamp>.png; `clean` hides the HUD and every debug surface for that frame first.",
		"danger": false,
	},
	{
		"name": "hud", "mod": &"world", "category": "View",
		"args": [Kind.TOGGLE], "min_args": 0, "arg_names": ["on/off"], "verbs": [],
		"help": "Hide or show the player HUD (crosshair, bars, minimap, toasts) — for clean captures. Restores exactly what was hidden.",
		"danger": false,
	},
	{
		"name": "unshaded", "mod": &"world", "category": "View",
		"args": [Kind.TOGGLE], "min_args": 0, "arg_names": ["on/off"], "verbs": [],
		"help": "Render with lighting off.", "danger": false,
	},
	{
		"name": "quantize", "mod": &"world", "category": "View",
		"args": [Kind.NUMBER], "min_args": 0, "arg_names": ["depth 0-8"], "verbs": [],
		"help": "Set the screen post-process COLOUR DEPTH (Options -> Video -> Colour Depth) by index: 0 authored, 1 24-bit (off), 2 16-bit, 3 15-bit (PS1), 4 12-bit, 5 9-bit, 6 8-bit, 7 6-bit, 8 3-bit. No args lists them against the live one. In-memory only — never written to settings.cfg.",
		"danger": false,
	},
	{
		"name": "dither", "mod": &"world", "category": "View",
		"args": [Kind.NUMBER, Kind.NUMBER], "min_args": 0, "arg_names": ["strength 0-1", "grid 2/4/8"], "verbs": [],
		"help": "Tune the ordered (Bayer) dither on the screen post-process: strength 0-1, then optionally the matrix grid 2, 4 or 8. No args reports the live values.",
		"danger": false,
	},
	{
		"name": "dof", "mod": &"world", "category": "View",
		"args": [Kind.VERB, Kind.NUMBER, Kind.NUMBER], "min_args": 0,
		"arg_names": ["knob", "value", "transition"], "verbs": ["near", "far", "amount", "off", "on", "reset"],
		"help": "Dial the camera's depth of field live — the near/far separation the FOV slider cannot give you: `dof near <metres> [transition]`, `dof far <metres> [transition]`, `dof amount <0-1>`, or `dof off|on|reset`. The weapon and fists are immune (own camera, no attributes), so only the WORLD softens. No args reports the live values. In-memory only — never written to settings.cfg.",
		"danger": false,
	},
	{
		"name": "sway", "mod": &"world", "category": "View",
		"args": [Kind.VERB, Kind.NUMBER], "min_args": 0,
		"arg_names": ["knob", "value"], "verbs": ["pos", "max", "roll", "pitch", "decay", "preset", "off", "reset"],
		"help": "Dial how far the view model lags behind a mouse turn — the one depth cue a pure yaw can carry: `sway pos|max|roll|pitch|decay <value>`, `sway preset 0|1|2` (timid/recommended/loud), or `sway off|reset`. No args reports the live values. In-memory only — never written to settings.cfg.",
		"danger": false,
	},
	{
		"name": "lens", "mod": &"world", "category": "View",
		"args": [Kind.NUMBER, Kind.NUMBER], "min_args": 0,
		"arg_names": ["barrel", "chroma"], "verbs": [],
		"help": "Dial the world's barrel (fisheye) lens live — the whole frame bent through a wide lens, centre magnified, corners pinned so it can never show a black edge. The number is centre magnification minus one (0.12 = ~12% bigger in the middle); 0 = flat. Optional second number is the colour fringe. No args reports the live values. In-memory for the process — never written to settings.cfg or to CameraSettings.tres.",
		"danger": false,
	},
]


# --- registry queries -------------------------------------------------------------------------------------

## Every row, in table order. Returns the shared const array — callers must treat it as read-only.
static func all() -> Array[Dictionary]:
	return COMMANDS


## The row named `name`, or an EMPTY dictionary if there is none. Callers test with `row.is_empty()` rather
## than a null compare, because a typed Array[Dictionary] can never hold null.
static func find(name: String) -> Dictionary:
	var wanted := name.strip_edges().to_lower()
	for row in COMMANDS:
		if String(row["name"]) == wanted:
			return row
	return {}


## Every command name, in table order. The console feeds this back as the Kind.COMMAND completion source.
static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for row in COMMANDS:
		out.append(String(row["name"]))
	return out


## Categories that actually have rows, ordered by CATEGORIES. A row carrying an unlisted category still shows
## up — appended after the known ones — so a typo degrades to a stray page instead of a vanished command.
static func categories() -> PackedStringArray:
	var present := {}
	for row in COMMANDS:
		present[String(row["category"])] = true
	var out := PackedStringArray()
	for c in CATEGORIES:
		if present.has(c):
			out.append(c)
			present.erase(c)
	for c in present.keys():
		out.append(String(c))
	return out


static func in_category(category: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in COMMANDS:
		if String(row["category"]) == category:
			out.append(row)
	return out


# --- search -----------------------------------------------------------------------------------------------

## Search RANKS, strongest first. Only the ORDER matters — they are the buckets `search()` walks down to sort
## its hits without a comparator.
const RANK_EXACT := 5     ## the row IS the word that was typed
const RANK_PREFIX := 4    ## its name starts with it
const RANK_NAME := 3      ## its name contains it
const RANK_CATEGORY := 2  ## its page is called that
const RANK_HELP := 1      ## it only matched through the help line, an argument name or a verb


## Everything a query is matched against, lower-cased and joined into one haystack: the command's name, the
## page it lives on, its help line, its argument names, and any VERB words the row carries.
##
## Rebuilt per call on purpose. Eighty-odd rows of string joins is nothing next to the keystroke that asked
## for it, and a cached table would be one more thing to invalidate the day a row is edited — the registry's
## whole value is that it has exactly one copy of every fact about a command.
static func haystack(row: Dictionary) -> String:
	if row.is_empty():
		return ""
	var parts := PackedStringArray([
		String(row["name"]),
		String(row["category"]),
		String(row["help"]),
	])
	# Annotated `: Array`, never `:=` — inferring off a Dictionary read is a Variant, and this repo's most
	# common parse failure is exactly that inference.
	var arg_names: Array = row["arg_names"]
	for n in arg_names:
		parts.append(String(n))
	var verbs: Array = row["verbs"]
	for v in verbs:
		parts.append(String(v))
	return " ".join(parts).to_lower()


## The lower-case words a query narrows by: whitespace-split (spaces, tabs, newlines), blanks dropped.
static func search_terms(query: String) -> PackedStringArray:
	var out := PackedStringArray()
	var words := query.to_lower().replace("\t", " ").replace("\n", " ").split(" ", false)
	for i in words.size():
		var word: String = words[i]
		if word != "":
			out.append(word)
	return out


## Free-text search across the WHOLE registry — what the F1 menu's search bar filters its pane with, and the
## only way to reach a command whose page you cannot guess (`notarget` is on the AI page, `quantize` on View).
##
## MATCHING. The query is split into TERMS and a row must carry EVERY one of them (AND, not OR): typing more
## words has to NARROW the list, or an incremental search fights the person using it. A term matches as a
## SUBSTRING rather than a prefix, because the queries that pay here are "fall", "save", "npc" — words that
## live in the middle of a help sentence. `complete()` already owns the prefix half, for the console's Tab.
##
## WHAT IS SEARCHED is `haystack()`: name, category, help, argument names, verbs. Deliberately NOT a second
## `tags`/`keywords` column on the rows — the help line already IS the prose a command is described by, and a
## second place to describe it is a second place for it to rot.
##
## ORDER. Best NAME match first, so a command you already know by name is never buried under one that merely
## mentions it in prose; ties keep the registry's own table order, so a result list reads like a filtered
## `help` listing instead of a shuffle. The ranking runs in BUCKETS rather than through `sort_custom`, which
## makes that tie-break stability a property of the loop instead of a promise about a comparator.
##
## A BLANK QUERY FILTERS NOTHING and returns every row, so a caller can hand this the raw contents of a text
## field with no special case. Like `all()`, the array it returns then IS the shared const table — read-only.
static func search(query: String) -> Array[Dictionary]:
	var terms := search_terms(query)
	if terms.is_empty():
		return all()
	var needle := " ".join(terms)   # the whole query, whitespace-normalised
	var hits: Array[Dictionary] = []
	var ranks: Array[int] = []
	for row in COMMANDS:
		var hay := haystack(row)
		var carries_all := true
		for term in terms:
			if not hay.contains(term):
				carries_all = false
				break
		if not carries_all:
			continue
		hits.append(row)
		ranks.append(_name_rank(row, needle, terms))
	var out: Array[Dictionary] = []
	for tier in range(RANK_EXACT, RANK_HELP - 1, -1):
		for i in hits.size():
			if ranks[i] == tier:
				out.append(hits[i])
	return out


## How strongly the row's own NAME — or, failing that, its category — answers the query. The whole query is
## tried first and then each term on its own, keeping the best of them: that is what floats the `spawn` row to
## the top of "npc spawn" while a row that only says "npc" in its help stays below it.
static func _name_rank(row: Dictionary, needle: String, terms: PackedStringArray) -> int:
	var best := _word_rank(row, needle)
	for term in terms:
		best = maxi(best, _word_rank(row, term))
	return best


static func _word_rank(row: Dictionary, word: String) -> int:
	if word == "":
		return RANK_HELP
	var name_s := String(row["name"]).to_lower()
	if name_s == word:
		return RANK_EXACT
	if name_s.begins_with(word):
		return RANK_PREFIX
	if name_s.contains(word):
		return RANK_NAME
	if String(row["category"]).to_lower().contains(word):
		return RANK_CATEGORY
	return RANK_HELP


# --- parsing ----------------------------------------------------------------------------------------------

## Split a typed line into tokens on whitespace, honouring "double quotes" so an item id with a space survives.
## An unterminated quote is forgiving: it closes at end-of-line rather than erroring, because a half-typed line
## is the normal state of a console being typed into. Returns [] for a blank or whitespace-only line.
static func tokenize(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	var in_quote := false
	var has_cur := false
	for i in line.length():
		var ch := line[i]
		if ch == "\"":
			in_quote = not in_quote
			has_cur = true  # `""` is a deliberate empty token, not nothing
			continue
		if not in_quote and (ch == " " or ch == "\t"):
			if has_cur:
				out.append(cur)
				cur = ""
				has_cur = false
			continue
		cur += ch
		has_cur = true
	if has_cur:
		out.append(cur)
	return out


## Validate arity and enumerated words for `row` against `args` (the tokens AFTER the command name).
## Returns "" when the call is legal, otherwise a one-line developer-facing reason. Kept separate from the
## actions so both front-ends reject the same way and every action can trust argv's length.
static func validate(row: Dictionary, args: PackedStringArray) -> String:
	if row.is_empty():
		return "no such command"
	var kinds: Array = row["args"]
	var min_args := int(row["min_args"])
	if args.size() < min_args:
		return "needs %d argument%s: %s" % [min_args, ("" if min_args == 1 else "s"), usage(row)]
	if args.size() > kinds.size():
		return "takes at most %d argument%s: %s" % [kinds.size(), ("" if kinds.size() == 1 else "s"), usage(row)]
	for i in args.size():
		var kind: int = kinds[i]
		var word := args[i]
		if kind == Kind.NUMBER and not word.is_valid_float():
			return "argument %d (%s) must be a number, got \"%s\"" % [i + 1, String(row["arg_names"][i]), word]
		if kind == Kind.TOGGLE and not TOGGLE_WORDS.has(word.to_lower()):
			return "argument %d must be on or off, got \"%s\"" % [i + 1, word]
		if kind == Kind.VERB:
			var verbs: Array = row["verbs"]
			if not verbs.has(word.to_lower()):
				return "argument %d must be one of %s, got \"%s\"" % [i + 1, ", ".join(verbs), word]
	return ""


## `name <required> [optional]` — the usage line shown by help and by a validation failure.
static func usage(row: Dictionary) -> String:
	if row.is_empty():
		return ""
	var parts := PackedStringArray([String(row["name"])])
	var kinds: Array = row["args"]
	var arg_names: Array = row["arg_names"]
	var min_args := int(row["min_args"])
	for i in kinds.size():
		var label := String(arg_names[i]) if i < arg_names.size() else "arg"
		if int(kinds[i]) == Kind.VERB:
			var verbs: Array = row["verbs"]
			if not verbs.is_empty():
				label = "|".join(verbs)
		parts.append(("<%s>" % label) if i < min_args else ("[%s]" % label))
	return " ".join(parts)


## Resolve an on/off/blank word against the CURRENT state. Blank (or anything unrecognised, which validate()
## has already rejected on a real call) flips — that is what makes a bare `noclip` a toggle.
static func toggle_value(word: String, current: bool) -> bool:
	match word.strip_edges().to_lower():
		"on", "1", "true", "yes":
			return true
		"off", "0", "false", "no":
			return false
		_:
			return not current


# --- completion -------------------------------------------------------------------------------------------

## Tab-completion over a partially typed line.
##
## `sources` maps a SOURCE_KEYS value (&"item", &"npc", …) to a PackedStringArray of live ids. The console
## gathers those from disk/autoloads and passes them in, which is what keeps this function pure and testable.
## A missing source is not an error — that slot simply has nothing to complete.
##
## Returns:
##   { "line": String, "matches": PackedStringArray, "token": String }
## `line` is the line to put back in the field: the longest unambiguous extension of what was typed (so
## repeated Tab is idempotent once ambiguous), and `matches` is what to print when there is more than one.
static func complete(line: String, sources: Dictionary) -> Dictionary:
	var trailing_space := line.ends_with(" ") or line.ends_with("\t")
	var tokens := tokenize(line)
	# Which slot is the caret in? With a trailing space the caret has moved on to the NEXT, empty token.
	var token := ""
	var index := tokens.size()
	if not trailing_space and not tokens.is_empty():
		index = tokens.size() - 1
		token = tokens[index]

	var pool := PackedStringArray()
	if index == 0:
		pool = names()
	else:
		var row := find(tokens[0]) if not tokens.is_empty() else {}
		if row.is_empty():
			return {"line": line, "matches": PackedStringArray(), "token": token}
		var kinds: Array = row["args"]
		var slot := index - 1
		if slot < 0 or slot >= kinds.size():
			return {"line": line, "matches": PackedStringArray(), "token": token}
		var kind: int = kinds[slot]
		if kind == Kind.TOGGLE:
			pool = PackedStringArray(TOGGLE_WORDS)
		elif kind == Kind.VERB:
			pool = PackedStringArray(row["verbs"])
		elif SOURCE_KEYS.has(kind):
			var key: StringName = SOURCE_KEYS[kind]
			if sources.has(key):
				pool = PackedStringArray(sources[key])

	var matches := PackedStringArray()
	var lower := token.to_lower()
	for candidate in pool:
		if candidate.to_lower().begins_with(lower):
			matches.append(candidate)
	if matches.is_empty():
		return {"line": line, "matches": matches, "token": token}

	var fill := common_prefix(matches)
	# Rebuild the line from the tokens we kept, so spacing normalises instead of accumulating.
	var kept := PackedStringArray()
	for i in index:
		kept.append(tokens[i])
	kept.append(fill)
	var rebuilt := " ".join(kept)
	# A single exact match is finished — add the separator so the next Tab completes the following slot.
	if matches.size() == 1:
		rebuilt += " "
	return {"line": rebuilt, "matches": matches, "token": token}


## The longest string every entry of `values` starts with, compared case-insensitively but returned with the
## FIRST entry's original casing (ids in this project are lowercase, but a mixed-case one must not be mangled).
static func common_prefix(values: PackedStringArray) -> String:
	if values.is_empty():
		return ""
	var prefix := values[0]
	for v in values:
		while prefix.length() > 0 and not v.to_lower().begins_with(prefix.to_lower()):
			prefix = prefix.substr(0, prefix.length() - 1)
	return prefix


# --- help rendering ---------------------------------------------------------------------------------------

## Lines for `help` with no argument: every command grouped by category. Returned as an array so the console
## can colour or paginate per line instead of splitting a blob back apart.
static func help_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for category in categories():
		out.append("-- " + category)
		for row in in_category(category):
			out.append("  %-14s %s" % [String(row["name"]), String(row["help"])])
	return out


## Lines for `help <command>`: the usage line, the description, and the argument list.
static func help_for(row: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if row.is_empty():
		return out
	out.append(usage(row))
	out.append("  " + String(row["help"]))
	if bool(row["danger"]):
		out.append("  ! destructive: this cannot be undone from the console")
	return out
