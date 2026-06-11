extends Node
## GameState — the live run's autosaved PROFILE + its RESPAWN point.
##
## Dark Souls style, ONE autosave (no manual slots): the run persists to user://gamestate.cfg so quitting and
## relaunching resumes where you left off. The profile is the player's progression — money, the five stats, the
## unlocked mechanics — plus the respawn point (the last bonfire, or the initial spawn). It is captured + written
## at every milestone: a wallet change (kill bounty / trade / pickup), a level-up, an upgrade pickup, and a
## bonfire rest. On DEATH the world is NOT reloaded — you're brought back to LIFE at the respawn point (enemies
## stay as they are); the autosave is the only thing that survives quitting.
##
## Boot: this autoload's _ready loads the save (if any) into memory, so the start menu can offer "Continue" and
## the Player's _ready can apply the loaded build. "New Game" calls reset_for_new_game() to start clean.

const SAVE_PATH := "user://gamestate.cfg"
## The five CharacterStats, by name — the columns of the [stats] save section (mirrors CharacterStats / LevelUp).
const STAT_NAMES: Array[StringName] = [&"strength", &"persuasion", &"gunplay", &"endurance", &"streetwise"]

## True once a save has been loaded into the fields below (boot found a file, or Continue was chosen). The Player's
## _ready reads this: true -> apply the saved build (stats / money / unlocks / teleport); false -> a fresh game.
var loaded: bool = false
var money: int = 100                       ## saved wallet
var stat_values: Dictionary = {}           ## StringName stat -> int; empty = all baseline (a fresh sheet)
var unlocks: Array[StringName] = []         ## the saved unlocked-mechanic ids

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
func load_from_disk(path := SAVE_PATH) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		loaded = false
		return false
	money = int(cfg.get_value("player", "money", 100))
	unlocks.clear()
	for u in (cfg.get_value("player", "unlocks", []) as Array):
		unlocks.append(StringName(u))
	stat_values.clear()
	for n in STAT_NAMES:
		stat_values[n] = int(cfg.get_value("stats", String(n), 0))
	has_respawn = bool(cfg.get_value("respawn", "has", false))
	respawn_position = cfg.get_value("respawn", "position", Vector3.ZERO)
	respawn_yaw = float(cfg.get_value("respawn", "yaw", 0.0))
	loaded = true
	return true

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
	cfg.set_value("respawn", "has", has_respawn)
	cfg.set_value("respawn", "position", respawn_position)
	cfg.set_value("respawn", "yaw", respawn_yaw)
	cfg.save(path)

## Read the live run off `player` into the in-memory profile (money, the five stats, the unlocked mechanics). The
## respawn fields aren't touched here — set_respawn keeps them current (a bonfire rest / the initial spawn).
func capture(player: Node) -> void:
	if player == null:
		return
	money = int(player.money)
	var sheet: CharacterStats = player.stats_or_default()
	stat_values.clear()
	for n in STAT_NAMES:
		stat_values[n] = sheet.get_stat(n)
	unlocks.clear()
	for u in player.unlocked_list():
		unlocks.append(StringName(u))

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
	money = 100
	stat_values.clear()
	unlocks.clear()
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
