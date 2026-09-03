class_name DebugActionsWorld
extends RefCounted

## The IMPURE half of the in-game debug tools for the WORLD half of the registry: every `DebugCommands` row whose
## `mod` is &"world" — the World, AI, Story and View categories, plus the three world-side Meta rows (`errors`,
## `events`, `saves`). `DebugActionsPlayer` is its twin (the &"player" rows); `DebugCommands` is the pure registry
## both front-ends parse against.
##
## CONTRACT (identical in both action modules, relied on by DebugConsole AND DebugMenu):
##   static run(cmd, ctx, args) -> PackedStringArray   — the lines to print. NEVER null, NEVER push_error: a
##       failure is a one-line explanation in the return value, because a console that silently no-ops looks
##       broken and a push_error only reaches the Godot log the player can't see.
##   static sources() -> Dictionary                    — completion ids this module owns, keyed by
##       DebugCommands.SOURCE_KEYS: &"npc", &"level", &"quest", &"flag".
##
## `DebugCommands.validate()` has ALREADY run before `run()` is called, so arity and the on/off + verb word lists
## are guaranteed. This module therefore never re-checks argv length — but it DOES null-guard every node, because
## the console can be opened on the main menu, mid-death, or with no level loaded at all.
##
## ctx keys: &"tree" (SceneTree, always valid), &"player" (Node or NULL), &"host" (the invoking CanvasLayer),
## &"state" (Dictionary that PERSISTS across commands — the home for toggle snapshots; our keys are namespaced
## "world/…" so the player module can't collide with us).
##
## DEV-ONLY: every string here is developer copy. This file paints NOTHING (it only returns Strings, like
## debug_commands.gd), so it is not a paint site and needs no ScanText.SKIP_FILES entry — keep it that way: never
## call notify_toast / set a Label here, hand the lines back and let the console paint them.

# Brand-new class_names are preloaded BY PATH into an untyped-usable const, never referenced by their class_name:
# until the editor rescans, a type annotation fails the WHOLE file to parse with "Could not find type X" and that
# cascades into every script that touches it. Precedent: debug_overlay.gd:11 (ErrorSinkScript).
const DebugCommandsScript := preload("res://scripts/components/debug_commands.gd")

## ⭐DebugInspector is referenced by PATH and loaded LAZILY, never preloaded — matching the DebugNoclip handling in
## debug_actions_player.gd:40-45. A `preload()` of a path not on disk YET is a HARD PARSE FAILURE, so preloading a
## sibling script that lands in the same change would take this module — and the console and menu that preload US —
## down with it until every file exists. A runtime load degrades to one honest line instead. Swap it back to a
## preload only if debug_inspector.gd is ever guaranteed to ship ahead of this file.
const INSPECTOR_SCRIPT_PATH := "res://scripts/components/debug_inspector.gd"

## ⭐The two RING-BUFFER drop-ins (`ailog` -> AiEventLog, `events` -> DebugEventTicker) are referenced by PATH and
## loaded LAZILY (_ring_script) for exactly the reason above: both land in the SAME change as their commands, and a
## preload of a path not on disk yet is the hard parse failure that would take the console and menu down with this
## module. Their history lives in `static var` rings ON THE SCRIPT (a death reload / quickload frees the node, not
## the static), which is why dump + clear go through STATICS on the loaded GDScript and only the on-screen
## panel/column toggle needs the live node. Never referenced by class_name here — see the *_SEAM dicts below.
const AI_EVENT_LOG_SCRIPT_PATH := "res://scripts/components/ai_event_log.gd"
const EVENT_TICKER_SCRIPT_PATH := "res://scripts/components/debug_event_ticker.gd"

# Existing classes, but preloaded by path for the same reason the registries are: no compile-time class dependency,
# so a stale global-class cache can never take this file down with it.
const DebugOverlayScript := preload("res://scripts/components/debug_overlay.gd")
const NavDebugOverlayScript := preload("res://scripts/components/nav_debug_overlay.gd")
const GroupsScript := preload("res://scripts/world/groups.gd")
const HostilityHelpersScript := preload("res://scripts/npc/hostility_helpers.gd")
## `npc hostile|neutral|friendly` writes Disposition.Kind and `brain`/`npc` read Perception.State — both enums come
## off the preloaded scripts (never `Disposition.Kind` / `Perception.State` by class_name) for the same stale-cache
## reason as the two above; the inspector does the same for Disposition (debug_inspector.gd:40).
const DispositionScript := preload("res://scripts/npc/disposition.gd")
const PerceptionScript := preload("res://scripts/npc/perception.gd")
## `brain` re-runs the PURE planner (GoapPlanner.plan / select_goal are statics with no host, no tree, no side
## effect) over the executor's own goal + action library, so the "why this plan" readout can never disagree with
## what the executor would decide from the same facts.
const GoapPlannerScript := preload("res://scripts/npc/goap/goap_planner.gd")

## The WorldClock AUTOLOAD's own script — needed for exactly ONE call. `delta_to_next_boundary` is a STATIC, and
## reaching a static through the autoload INSTANCE (`WorldClock.delta_to_next_boundary(...)`) raises the engine's
## STATIC_CALLED_ON_INSTANCE warning in the editor. Every live FIELD (time_of_day, day_start, day_length_seconds)
## and every instance method (phase(), set_time_of_day(), advance_hours()) still goes through the autoload, because
## those ARE per-instance state. Same split tests/test_world_clock.gd:7 uses.
const WorldClockScript := preload("res://managers/WorldClock.gd")

# --- content locations (scanned once, cached in the statics below) ------------------------------------------
const NPC_DIR := "res://resources/characters/"
const LEVEL_DIR := "res://resources/levels/"
const QUEST_DIR := "res://resources/quests/"
## The standard spawnable NPC. load()ed (not preloaded) on purpose: a PackedScene preload here would drag the whole
## NPC subtree — and its script cycle risk — into this file's parse.
const NPC_SCENE_PATH := "res://scenes/characters/NPC.tscn"

# --- debug-command defaults ---------------------------------------------------------------------------------
# These are DEV-TOOL defaults, not designer-tunable gameplay numbers (a static-only RefCounted has no inspector
# surface to hang an @export on; the drop-in components own the designer-facing knobs). Every one of them is
# overridable by the command's own argument.
## `spawn` cap. NPC._ready builds ~20 child components, a Perception, a NavigationAgent3D, a Locomotor and
## instantiates weapon.tscn — a big count hitches hard, which is exactly what NpcPool exists for. Capped so a
## fat-fingered `spawn raider 500` doesn't lock the game.
const MAX_SPAWN_COUNT := 12
const SPAWN_DISTANCE := 4.0   ## metres in front of the player
const SPAWN_SPACING := 1.6    ## metres between bodies when count > 1
const SPAWN_LIFT := 0.15      ## metres above the player's feet plane, so a body isn't birthed inside the floor
## `killall` damage. Routed through take_damage (NOT die()) so the kill is fully credited: XP, notify_kill for a
## quest, the faction kill_penalty, the bounty, the lootable corpse.
const KILL_DAMAGE := 99999.0
## Below this, Engine.time_scale is effectively a freeze with no way back except another console command.
const MIN_TIME_SCALE := 0.01
const MAX_TIME_SCALE := 20.0
## `advance` spans at or beyond this print the multi-boundary warning (each crossing queues a real disk write).
const LONG_ADVANCE_HOURS := 24.0
## WorldClock.MAX_ADVANCE_STEPS is 800 boundary steps (~2 per day), so past ~400 days the walk silently degrades
## into a seek and stops firing rent/interest. Mirrored here only to warn about it.
const ADVANCE_STEP_BUDGET_DAYS := 400.0
## `ledger` prints at most this many entries per bucket before a "... N more" tail — a long-played level's
## world_objects bucket holds one row per door/pickup/prop ever touched, and the console scrollback is finite.
const LEDGER_MAX_LINES := 40
## `resurrect` names at most this many forgotten snapshot keys inline (the rest are counted).
const RESURRECT_MAX_NAMED := 8
## `ailog` / `events` print at most this many ring lines when the count is 0 or omitted.
const RING_DEFAULT_COUNT := 40
## Passed as `count` to a drop-in's lines() when the WHOLE ring is wanted (the header's "(M total)"). Both rings are
## capped by an @export max applied to the static, so anything this large reads as "everything" — the drop-in clamps.
const RING_READ_ALL := 1000000
## The filter word that EMPTIES a ring instead of filtering it — the same word for both ring commands.
const RING_CLEAR_WORD := "clear"

# --- the two long-running HARNESS commands (`roundtrip`, `soak`) — see the ROUND-TRIP + SOAK section ---------
## ⭐The DebugRoundtrip harness node is referenced by PATH and loaded LAZILY (never preloaded, never by class_name):
## it lands in the SAME change as its command, and a preload of a path not on disk yet is the hard parse failure that
## would take this module — and the console and menu that preload us — down with it. Same rule as INSPECTOR_SCRIPT_PATH.
const ROUNDTRIP_SCRIPT_PATH := "res://scripts/components/debug_roundtrip.gd"
## The node name the harness mounts under (mirrors DebugRoundtrip.NODE_NAME, read off the loaded script's constant map
## at run time so the two cannot drift; this literal is only the fallback for a script without the const).
const ROUNDTRIP_NODE_NAME := &"DebugRoundtrip"
## SoakHarness (scripts/tools/soak_harness.gd) is an EXISTING class, but it is load()ed at command time rather than
## preloaded: its own `npc_scene` export preloads NPC.tscn, and a preload here would drag the whole NPC subtree — and
## its script-cycle risk — into this module's parse (the same reason NPC_SCENE_PATH is a load()).
const SOAK_HARNESS_PATH := "res://scripts/tools/soak_harness.gd"
## SoakReport — read only for its STRANDED_THRESHOLD const (see _soak_stranded_threshold); the harness returns the report.
const SOAK_REPORT_PATH := "res://scripts/tools/soak_report.gd"
## The wave's faction. The harness ships raiders (mirrors authored enemies for the HEADLESS run, where there is no
## player) — but in a level WITH a player, NPC.tscn's sight_range 500 means a hostile wave aggroes and chases instead of
## wandering, which corrupts the stranding signal (the WANDER is the whole test) and shoots the dev. Neutral wildlife
## walks the navmesh and leaves you alone.
const SOAK_FACTION_PATH := "res://resources/factions/neutral_wildlife.tres"
## The root-parented driver's node name (its "already running" find keys on it).
const SOAK_DRIVER_NAME := &"DebugSoak"
## `soak` NPC cap. The harness spawns the wave THREE times (one stranded phase + leak_waves x2 by default), each a
## synchronous NPC._ready x n hitch — so this is capped like `spawn` (MAX_SPAWN_COUNT) and for the same reason.
const MAX_SOAK_NPCS := 12
## `soak` stranded-phase bounds in REAL seconds (the harness awaits real physics frames). Below ~10 s a strand cannot
## register at all (SoakReport.STRANDED_THRESHOLD stranded cycles ~ 10 s wedged — the harness's own export doc), so a
## short soak is a leak check only and the command says so; above the cap the game is unplayable for minutes.
const MIN_SOAK_SECONDS := 1.0
const MAX_SOAK_SECONDS := 120.0
const SOAK_STRAND_MIN_SECONDS := 10.0

# --- ctx[&"state"] keys (namespaced; the player module owns "player/…") -------------------------------------
## The GameSettings.allow_timescale_changes value we clobbered, banked while a `timescale` override is in force.
const STATE_TS_ALLOW := &"world/timescale_allow_saved"
## Whether `freezeai` currently has the cast under cutscene control (there is no engine-side flag to read back).
const STATE_FREEZE_AI := &"world/freeze_ai"
## `notarget` banks the player's two AUTHORED noise exports here while it has them zeroed (see _cmd_notarget for
## why the exports must go too — the meta alone leaves footsteps audible to the &"noise" scan).
const STATE_NOTARGET_NOISE_MOVE := &"world/notarget_noise_move"
const STATE_NOTARGET_NOISE_GUN := &"world/notarget_noise_gun"
## The NPC the last `npc`/`brain` command acted on (a Node handle, validity-checked on every read). The
## crosshair NPC ALWAYS wins; this is only the fallback that lets `npc walkto` / `npc investigate` take a POINT
## from the crosshair — you cannot aim at the NPC and at the spot it should walk to in the same frame.
const STATE_NPC_STICKY := &"world/npc_sticky"
## `hud off`'s snapshot: a PackedStringArray of UI-relative NodePaths (String) of every direct HUD child the sweep
## hid, held while the HUD is down. Node PATHS, not handles: toasts and floats are freed under the hide, and a path
## that no longer resolves is simply skipped on restore. Erased by `hud on` and by release_scene_scoped_state.
const STATE_HUD_HIDDEN := &"world/hud_hidden"

## `screenshot` output. user:// only — the project rule for anything a debug command writes.
const SCREENSHOT_DIR := "user://screenshots"
## The 2D debug drop-ins a `screenshot clean` frame hides, matched by SCRIPT PATH on any CanvasLayer in the tree
## (never `is <class>` — the stale-cache cascade, and a designer may parent one under an autoload). The two
## Groups.DEBUG_SURFACE members are listed too, belt and braces, for a build where the group is empty.
const CLEAN_HIDDEN_SCRIPT_PATHS: Array[String] = [
	"res://scripts/components/debug_console.gd",
	"res://scripts/components/debug_menu.gd",
	"res://scripts/components/debug_overlay.gd",
	"res://scripts/components/ai_event_log.gd",
	"res://scripts/components/debug_event_ticker.gd",
]

## The dev-only GHOST SEAM: NPC._treats_as_enemy(node) returns false FIRST for any node carrying this meta
## (npc.gd `DEBUG_NOTARGET_META`, the same literal). That predicate is THE gate NpcTargeting acquires and keeps a
## target by (npc_targeting.gd _target_invalid / the player + peer scans) AND the per-frame
## `_perception.is_hostile = _treats_as_enemy(_target)` writer (npc.gd:2529), so a held ghost target is dropped on
## the very next tick and Perception.can_see()/can_hear() both read false with no target. Spelled as a bare
## StringName here (never `NPC.DEBUG_NOTARGET_META`) so this file has no compile-time dependency on the NPC class.
const NOTARGET_META := &"debug_notarget"
## The Perception fields NPC._build_perception copies ONCE at build time and never re-syncs (npc.gd:1977-1984 —
## the survey's #1 AI trap: writing npc.sight_range at runtime does not move the sight cone). `npc rebrain`
## re-stamps every one of them from the NPC's live exports; `npc sight <r>` writes the two sight_range knobs.
const PERCEPTION_COPIED_ONCE: Array[StringName] = [
	&"sight_range", &"fov_degrees", &"crouch_sight_mult", &"time_to_detect", &"forget_time", &"pursuit_grace_time",
	&"eye_height", &"hearing",
]

# --- disk-scan caches. sources() runs on EVERY Tab press, so the DirAccess walks happen exactly once. ---------
static var _npc_index: Dictionary = {}     ## file stem -> .tres path
static var _npc_scanned: bool = false
static var _level_index: Dictionary = {}   ## file stem -> .tres path
static var _level_scanned: bool = false
static var _quest_index: Dictionary = {}   ## Quest.id (String) -> .tres path
static var _quest_scanned: bool = false
## RenderingServer.set_debug_generate_wireframes(true) is a one-shot process-wide arm; WIREFRAME renders NOTHING
## until it has been called. Nothing else in the project calls it, so we own the latch.
static var _wireframes_armed: bool = false


# =============================================================================================================
# DISPATCH
# =============================================================================================================

## Run one &"world" command. `args` are the tokens AFTER the command name, already arity/word validated.
static func run(cmd: String, ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	match cmd:
		# --- World ---
		"time": return _cmd_time(ctx, args)
		"advance": return _cmd_advance(ctx, args)
		"clock": return _cmd_clock(ctx)
		"stationmusic": return _cmd_station_music()
		"wandermusic": return _cmd_wander_music(ctx)
		"timescale": return _cmd_timescale(ctx, args)
		"warp": return _cmd_warp(ctx, args)
		"levels": return _cmd_levels()
		"reload": return _cmd_reload(ctx)
		"save": return _cmd_save(ctx, args)
		"load": return _cmd_load(ctx, args)
		"sandbox": return _cmd_sandbox(ctx, args)
		"roundtrip": return _cmd_roundtrip(ctx)
		# --- Meta (world side) ---
		"errors": return _cmd_errors(ctx, args)
		"events": return _cmd_events(ctx, args)
		"saves": return _cmd_saves()
		# --- AI ---
		"spawn": return _cmd_spawn(ctx, args)
		"npcs": return _cmd_npcs(ctx)
		"killall": return _cmd_killall(ctx, args)
		"peace": return _cmd_peace(ctx)
		"aggro": return _cmd_aggro(ctx)
		"freezeai": return _cmd_freezeai(ctx, args)
		"who": return _cmd_who(ctx)
		"brain": return _cmd_brain(ctx)
		"npc": return _cmd_npc(ctx, args)
		"ailog": return _cmd_ailog(ctx, args)
		"notarget": return _cmd_notarget(ctx, args)
		"soak": return _cmd_soak(ctx, args)
		# --- Story ---
		"flag": return _cmd_flag(args)
		"flags": return _cmd_flags()
		"quest": return _cmd_quest(args)
		"quests": return _cmd_quests()
		"notify": return _cmd_notify(ctx, args)
		"ledger": return _cmd_ledger(args)
		"wipeobjects": return _cmd_wipeobjects(ctx)
		"resurrect": return _cmd_resurrect(ctx)
		"names": return _cmd_names(args)
		# --- View ---
		"inspect": return _cmd_inspect(ctx, args)
		"navdebug": return _cmd_navdebug(ctx, args)
		"perf": return _cmd_perf(ctx, args)
		"wireframe", "overdraw", "unshaded": return _cmd_debug_draw(cmd, ctx, args)
		"screenshot": return _cmd_screenshot(ctx, args)
		"hud": return _cmd_hud(ctx, args)
		"quantize": return _cmd_quantize(args)
		"dither": return _cmd_dither(ctx, args)
		"dof": return _cmd_dof(ctx, args)
		"sway": return _cmd_sway(ctx, args)
		"lens": return _cmd_lens(ctx, args)
	return _one("\"%s\" is not a world command (registry/actions drift — add a case in debug_actions_world.gd)" % cmd)


## Completion ids this module owns. Keyed off DebugCommands.SOURCE_KEYS rather than hand-typed StringNames so the
## registry and the actions can never drift on a spelling.
static func sources() -> Dictionary:
	var key_npc: StringName = DebugCommandsScript.SOURCE_KEYS[DebugCommandsScript.Kind.NPC]
	var key_level: StringName = DebugCommandsScript.SOURCE_KEYS[DebugCommandsScript.Kind.LEVEL]
	var key_quest: StringName = DebugCommandsScript.SOURCE_KEYS[DebugCommandsScript.Kind.QUEST]
	var key_flag: StringName = DebugCommandsScript.SOURCE_KEYS[DebugCommandsScript.Kind.FLAG]
	return {
		key_npc: _sorted_keys(_npcs()),
		key_level: _sorted_keys(_levels()),
		key_quest: _sorted_keys(_quests()),
		# Flags are NOT disk content and NOT cached: the shipped game authors essentially zero story flags, so the
		# only honest source is the live dict plus the one flag name that exists in code.
		key_flag: _flag_names(),
	}


# =============================================================================================================
# WORLD — time
# =============================================================================================================

## SEEK the clock. WorldClock.set_time_of_day emits NOTHING (managers/WorldClock.gd:50-56 documents it as the
## rent/interest exploit) — deliberately a DIFFERENT implementation from `advance`, and the output says which one
## you got so nobody files "time didn't charge rent" as a bug.
static func _cmd_time(_ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var raw := args[0].strip_edges()
	var frac := -1.0
	var how := ""
	if raw.contains(":"):
		var parts := raw.split(":", false)
		if parts.size() < 2 or not parts[0].is_valid_float() or not parts[1].is_valid_float():
			return _one("could not read \"%s\" as HH:MM" % raw)
		frac = fposmod((parts[0].to_float() + parts[1].to_float() / 60.0) / 24.0, 1.0)
		how = "HH:MM"
	elif raw.is_valid_float():
		var v := raw.to_float()
		# 0..1 is the engine's own unit (0 = midnight, 0.5 = noon); anything larger can only sanely be an HOUR, so
		# `time 6` means 06:00 rather than fposmod-ing to midnight. The output states which reading was used.
		if v >= 0.0 and v <= 1.0:
			frac = v
			how = "0..1 fraction"
		elif v > 1.0 and v <= 24.0:
			frac = fposmod(v / 24.0, 1.0)
			how = "hours"
		else:
			return _one("\"%s\" is out of range — pass HH:MM, 0..1, or 0..24 hours" % raw)
	else:
		return _one("could not read \"%s\" — pass HH:MM or a 0..1 fraction" % raw)

	var before := float(WorldClock.time_of_day)
	var before_phase := int(WorldClock.phase())
	WorldClock.set_time_of_day(frac)
	var out := PackedStringArray()
	out.append("time SEEK %s -> %s  (read as %s, frac %.4f)" % [_clock_text(before), _clock_text(frac), how, frac])
	out.append("phase %s -> %s" % [_phase_text(before_phase), _phase_text(int(WorldClock.phase()))])
	out.append("SEEK fires NO boundary events: no rent, no bank interest, no phase_changed subscriber. Use `advance` to walk time.")
	out.append("NPC schedules poll phase() live, so routines still move on the next tick.")
	return out


## WALK the clock. Every dawn/dusk the span crosses is emitted, in order, IN ONE FRAME.
static func _cmd_advance(_ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var hours := args[0].to_float()
	if hours <= 0.0:
		return _one("advance needs a positive hour count (advance_hours clamps a negative to 0 and returns). Use `time` to seek backwards.")
	var days := hours / 24.0
	var before := float(WorldClock.time_of_day)
	var before_phase := int(WorldClock.phase())

	var out := PackedStringArray()
	# Warn BEFORE the call: a long span runs RentCollector's notice->grace->charge schedule and
	# LedgerAccrual.post_interest once per crossing, each queueing a full-profile atomic disk write.
	if hours >= LONG_ADVANCE_HOURS:
		out.append("! %.1f in-game days pass in ONE frame — every dawn/dusk fires now (rent notice/grace/charge, bank interest)." % days)
		out.append("! each boundary queues a real gamestate.cfg write. Never put `advance` behind a held key.")
	if days > ADVANCE_STEP_BUDGET_DAYS:
		out.append("! beyond ~%d days the walk exceeds WorldClock.MAX_ADVANCE_STEPS and silently finishes as a SEEK — the tail fires nothing." % int(ADVANCE_STEP_BUDGET_DAYS))

	WorldClock.advance_hours(hours)
	out.append("time WALK +%.2f h (%.2f days): %s -> %s" % [hours, days, _clock_text(before), _clock_text(float(WorldClock.time_of_day))])
	out.append("phase %s -> %s  (every crossing in the span was emitted)" % [_phase_text(before_phase), _phase_text(int(WorldClock.phase()))])
	return out


## Read-only clock + rent status. Rent lives on a plain child node with no group and no registry, so it is found
## by name under the level subtree and re-found every call (the old one is freed on a level swap).
static func _cmd_clock(ctx: Dictionary) -> PackedStringArray:
	var tree := _tree(ctx)
	var out := PackedStringArray()
	var t := float(WorldClock.time_of_day)
	out.append("time %s  (frac %.4f)" % [_clock_text(t), t])
	out.append("phase %s   day starts %.3f, night starts %.3f" % [_phase_text(int(WorldClock.phase())), float(WorldClock.day_start), float(WorldClock.night_start)])
	var day_len := float(WorldClock.day_length_seconds)
	if day_len <= 0.0:
		out.append("day length 0 = CLOCK FROZEN — the Wait screen refuses to open, and rent/interest never come due.")
	else:
		out.append("day length %.1f real seconds per in-game day" % day_len)
		var to_boundary := float(WorldClockScript.delta_to_next_boundary(t, float(WorldClock.day_start), float(WorldClock.night_start)))
		out.append("next boundary in %.2f in-game hours (%.1f real s)" % [to_boundary * 24.0, to_boundary * day_len])
	out.append("Engine.time_scale %.3f%s" % [Engine.time_scale, ("  (timescale override active)" if _has_state(ctx, STATE_TS_ALLOW) else "")])

	var rent := _find_rent_collector(tree)
	if rent == null:
		out.append("rent: no node named \"RentCollector\" carrying rent_collector.gd under the level subtree (it is in no group, so it can only be found by name)")
		return out
	var amount := float(rent.get(&"rent_amount"))
	if amount <= 0.0:
		out.append("rent: DISARMED (rent_amount 0) — never charges, never serves a notice")
		return out
	out.append("rent %.2f every %d day(s), grace %d dawn(s)" % [amount, int(rent.get(&"period_days")), int(rent.get(&"grace_days"))])
	# _days_since_charge / _notice_served / _dawns_seen are private with no getters — a status readout has to read
	# the underscore fields (rent_collector.gd:57-59).
	out.append("  dawns seen %d, days since charge %d, notice served %s" % [
		int(rent.get(&"_dawns_seen")), int(rent.get(&"_days_since_charge")), str(bool(rent.get(&"_notice_served")))])
	return out


## Own Engine.time_scale. BulletTime lerps it back toward 1.0 while it is managing, and FreezeFrame slams it on
## every hit — both check GameSettings.allow_timescale_changes first, so clearing that flag is the ONLY way a
## console value survives past the frame. The original is banked in ctx state and restored on the way back to 1.0.
## The station-radio readout. NO automated test can hear a filter, a fade or a bus send, so this is how you
## check the machine's music by hand: open a terminal, drop the console, and read the live state. It reports
## the GATE (which registry rows are open), the tier flag other music layers stand down for, the live level
## against its authored target, and the resolved bus — the four things that go wrong silently.
static func _cmd_station_music() -> PackedStringArray:
	var cfg: StationMusicSettings = GameSettings.station_music
	var out := PackedStringArray()
	var open_screens := PackedStringArray()
	InputManager._ensure_modal_reg()
	for e in InputManager._modal_reg:
		if e.station_music and e.screen.is_open():
			open_screens.append(str((e.screen as Node).name))
	out.append("gate: %s%s" % [
		str(InputManager.any_station_music_open()),
		("  (open: %s)" % ", ".join(open_screens)) if not open_screens.is_empty() else ""])
	out.append("wanted: %s   playing: %s   track: %s" % [
		str(StationMusic.is_bed_wanted()), str(StationMusic.playing),
		StationMusic.current_track_name() if StationMusic.current_track_name() != "" else "-"])
	# Both flags, because they answer different questions and their DIFFERENCE is the hold window: `wanted`
	# rides hold_seconds out (what the dialogue BED steps aside for), `screen open` drops the instant the
	# screen closes (what the conversation MUSIC DUCK stands down for — MusicDucker.note_station_radio).
	# ⭐`screen open` reads FALSE here by construction: debug_console.open() refuses over any registered modal,
	# so you can never type this command WITH a station screen up. It is printed anyway because a `true` would
	# mean the flag has latched on with the screen already gone — the exact leak that would re-break this.
	# The DUCK line is the one you actually read after the fact: it is the ducker's real latch (not a
	# re-derivation of it) beside the live bus level, so a duck stuck armed with no conversation, or a music
	# bus left sitting low, is visible without reproducing anything.
	var music_bus := AudioServer.get_bus_index(&"music")
	out.append("screen open: %s   conversation duck: %s   music bus: %.1f dB (configured %.1f)" % [
		str(StationMusic.is_screen_open()),
		"ARMED" if DialogueManager.is_music_ducked() else ("released" if DialogueManager.is_engaged() else "idle"),
		AudioServer.get_bus_volume_db(music_bus) if music_bus >= 0 else 0.0,
		Settings.current_bus_db(&"music")])
	out.append("level: %.1f dB  ->  target %.1f dB   (floor %.1f, fade in %.2fs / out %.2fs, hold %.2fs)" % [
		StationMusic.volume_db,
		cfg.volume_db if StationMusic.is_bed_wanted() else cfg.silent_db,
		cfg.silent_db, cfg.fade_in, cfg.fade_out, cfg.hold_seconds])
	var routed := str(StationMusic.bus)
	out.append("bus: %s%s   enabled: %s   playlist: %d track(s)" % [
		routed,
		"" if routed == str(cfg.bus) else "  ⚠ authored '%s' does not exist — fell back" % cfg.bus,
		str(cfg.enabled), cfg.tracks.size()])
	return out


## The WANDERING-BED readout. Same reason as the station one — no automated test can hear a fade — but this
## layer gets a second, sharper question that nothing else does: "why is it quiet RIGHT NOW?" It is quiet for
## exactly five reasons, and this prints which: somebody OWNS the moment (combat / caution / dialogue / station
## / radio), the calm clock has not yet reached resume_delay, the bed is resting between tracks, the playlist
## is empty, or the layer is disabled. Read `owner` first, then `calm`, then `rest`.
##
## The node is found BY TYPE, not by name or path, so renaming or re-parenting it in game.tscn cannot silently
## turn this command into "not present". Referenced as a STRING for the same reason the registries are preloaded
## by path — no compile-time class dependency in this file (see the header).
static func _cmd_wander_music(ctx: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var bed: Node = _find_wander_music(ctx)
	if bed == null:
		out.append("no WanderMusic node in the current scene (it lives in game.tscn under Player — the main menu has none).")
		return out
	# UNTYPED on purpose — see the header rule: WanderMusicSettings lands in the same change as this file,
	# and a type annotation on a not-yet-rescanned class_name fails this whole module (and the console and
	# menu that preload it) to parse. Field reads below are Variant lookups, which is fine for a readout.
	var cfg = GameSettings.wander_music
	var owner_now := str(bed.call(&"owner_of_the_moment"))
	var wanted: bool = bool(bed.call(&"is_bed_wanted"))
	var track := str(bed.call(&"current_track_name"))
	out.append("owner: %s%s" % [
		owner_now if owner_now != "" else "nobody",
		"   (wandering — the bed may play)" if owner_now == "" else "   (the bed stands down for this)"])
	out.append("wanted: %s   playing: %s   track: %s" % [
		str(wanted), str(bed.get(&"playing")), track if track != "" else "-"])
	out.append("calm: %.1fs / %.1fs needed   rest: %.1fs left   (rest window %.0f-%.0fs, continuous: %s)" % [
		float(bed.call(&"calm_seconds")), cfg.resume_delay, float(bed.call(&"rest_remaining")),
		cfg.rest_seconds_min, cfg.rest_seconds_max, str(cfg.continuous)])
	out.append("level: %.1f dB  ->  target %.1f dB   (floor %.1f, fade in %.2fs / out %.2fs)" % [
		float(bed.get(&"volume_db")), cfg.volume_db if wanted else cfg.silent_db,
		cfg.silent_db, cfg.fade_in, cfg.fade_out])
	var routed := str(bed.get(&"bus"))
	out.append("bus: %s%s   enabled: %s   playlist: %d track(s)" % [
		routed,
		"" if routed == str(cfg.bus) else "  ⚠ authored '%s' does not exist — fell back" % cfg.bus,
		str(cfg.enabled), cfg.tracks.size()])
	return out


## The live WanderMusic node, or null when there isn't one (the main menu, or a scene that never authored it).
## Searched from the current scene root by TYPE — see the note on _cmd_wander_music.
static func _find_wander_music(ctx: Dictionary) -> Node:
	var tree: SceneTree = ctx.get(&"tree")
	if tree == null:
		return null
	var root: Node = tree.current_scene
	if root == null:
		return null
	var found: Array[Node] = root.find_children("*", "WanderMusic", true, false)
	return found[0] if not found.is_empty() else null


static func _cmd_timescale(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var state := _state(ctx)
	var want := 1.0 if args.is_empty() else args[0].to_float()
	var out := PackedStringArray()

	if is_equal_approx(want, 1.0):
		Engine.time_scale = 1.0
		if state.has(STATE_TS_ALLOW):
			GameSettings.allow_timescale_changes = bool(state[STATE_TS_ALLOW])
			state.erase(STATE_TS_ALLOW)
			out.append("time_scale 1.0 — hitstop / bullet-time handed back (allow_timescale_changes restored to %s)" % str(bool(GameSettings.allow_timescale_changes)))
		else:
			out.append("time_scale 1.0 (no override was active)")
		return out

	var clamped := clampf(want, MIN_TIME_SCALE, MAX_TIME_SCALE)
	# Bank the ORIGINAL exactly once, so `timescale 0.2` then `timescale 4` then `timescale` restores the authored
	# value rather than the value the first override already wrote.
	if not state.has(STATE_TS_ALLOW):
		state[STATE_TS_ALLOW] = bool(GameSettings.allow_timescale_changes)
	GameSettings.allow_timescale_changes = false
	Engine.time_scale = clamped
	out.append("time_scale %.3f%s" % [clamped, ("  (clamped from %.3f)" % want) if not is_equal_approx(clamped, want) else ""])
	out.append("GameSettings.allow_timescale_changes = false — bullet-time and hitstop are locked out so this sticks.")
	out.append("WorldClock._process uses SCALED delta, so the day/night cycle runs at this rate too.")
	out.append("`timescale` with no argument restores 1.0 and hands the knob back.")
	return out


# =============================================================================================================
# WORLD — levels and saves
# =============================================================================================================

## Swap levels through GameRoot. ALWAYS with a LOADED .tres: a code-built LevelData has a blank resource_path, so
## GameState.set_current_level("") records nothing, Continue boots the export instead, and every world_objects key
## WorldSaveId computes gets a blank level component.
static func _cmd_warp(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var tree := _tree(ctx)
	if tree == null:
		return _one("no SceneTree")
	var wanted := args[0]
	var path := _lookup(_levels(), wanted)
	if path == "":
		return _one("no LevelData \"%s\" — try: %s" % [wanted, ", ".join(_sorted_keys(_levels()))])
	var data := load(path)
	if data == null:
		return _one("could not load %s" % path)
	if String(data.resource_path) == "":
		return _one("%s loaded with a blank resource_path — warping it would break the save ledger and Continue" % path)
	if data.get("scene") == null:
		return _one("%s has no `scene` — GameRoot.load_level no-ops on it" % path)

	var gr := _game_root(tree)
	if gr == null:
		return _one("no GameRoot in the tree (group \"%s\") — level warping is only possible in the gameplay scene" % String(GroupsScript.GAME_ROOT))
	if not gr.has_method(&"load_level"):
		return _one("the node in group \"%s\" has no load_level()" % String(GroupsScript.GAME_ROOT))

	var out := PackedStringArray()
	out.append("warping to %s (%s)" % [wanted, String(data.get("display_name"))])
	# Synchronous: instantiate + add_child happen inside this call. Safe from a console _input / a menu button —
	# NEVER from a _ready() (add_child is blocked while the parent is setting up children).
	gr.call(&"load_level", data)
	out.append("old level subtree was renamed, detached and queue_free()d — anything parented inside it is gone.")

	var lvl := _level_node(tree)
	if lvl == null:
		out.append("! no \"Level\" child after the load — the scene may have instantiated null (reimport transient)")
	elif not _has_level_root_script(lvl):
		# ps1_warp.gd:43 gates cover() on `level_root is LevelRoot` and returns silently otherwise.
		out.append("! this level's root carries no level_root.gd, so Ps1Warp.cover() skipped it — no PS1 vertex-snap here.")
	out.append("nav: the fresh NavigationRegion3D needs a map-sync frame before any NPC can path.")
	# The old cast went with the level subtree and the new one boots with the AI live, so a latched `freezeai ON`
	# is now a lie — left set, the next bare `freezeai` would resolve to OFF and look like it did nothing.
	_state(ctx).erase(STATE_FREEZE_AI)
	return out


static func _cmd_levels() -> PackedStringArray:
	var index := _levels()
	if index.is_empty():
		return _one("no LevelData resources under %s" % LEVEL_DIR)
	var active := String(GameState.current_level_path)
	var out := PackedStringArray()
	for stem in _sorted_keys(index):
		var path := String(index[stem])
		var data := load(path)
		var label := String(data.get("display_name")) if data != null else "?"
		var mark := "*" if path == active else " "
		out.append("%s %-18s %s" % [mark, stem, label])
	out.append("* = the active level (GameState.current_level_path)")
	return out


static func _cmd_reload(ctx: Dictionary) -> PackedStringArray:
	var tree := _tree(ctx)
	if tree == null:
		return _one("no SceneTree")
	var err := tree.reload_current_scene()
	if err != OK:
		return _one("reload_current_scene failed (error %d)" % err)
	var out := release_scene_scoped_state(ctx)
	out.append("reloading the current scene — every debug overlay parented into it is destroyed and must be re-toggled.")
	return out


## quicksave / slot save. Both MOVE the respawn checkpoint to the player's current spot before capturing
## (GameState._capture_and_write), and both return a bool that is the ONLY honest success signal — reporting
## "saved" off the call alone lies on a full disk or an off-tree player.
static func _cmd_save(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var player := _player(ctx)
	if player == null:
		return _one("no player — a save captures the live player and no-ops without one")
	if not player.is_inside_tree():
		return _one("player is off-tree — GameState refuses to write (that guard is what keeps unit tests from clobbering your save)")
	if GameState.reload_pending():
		return _one("a quickload is in flight (GameState.reload_pending) — persistence is frozen until the fresh scene boots")

	var out := PackedStringArray()
	var ok := false
	if args.is_empty():
		ok = bool(GameState.quicksave(player))
		out.append("quicksave: %s" % ("written" if ok else "FAILED (nothing hit disk)"))
	else:
		var slot := int(args[0].to_float())
		if slot < 1 or slot > GameState.SLOT_COUNT:
			return _one("slot must be 1..%d" % GameState.SLOT_COUNT)
		ok = bool(GameState.save_to_slot(player, slot))
		out.append("slot %d: %s" % [slot, "written" if ok else "FAILED (nothing hit disk)"])
	if ok:
		out.append("your respawn checkpoint MOVED here (a quick/slot save is your new checkpoint).")
		out.append("this is the exact-snapshot tier: live NPCs, cross-level kills and container contents were captured too.")
	return out


static func _cmd_load(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var tree := _tree(ctx)
	if tree == null:
		return _one("no SceneTree")
	var out := PackedStringArray()
	var ok := false
	if args.is_empty():
		if not GameState.has_quicksave():
			return _one("no quicksave on disk")
		ok = bool(GameState.quickload())
		out.append("quickload: %s" % ("reloading" if ok else "REFUSED (unreadable or off-tree)"))
	else:
		var slot := int(args[0].to_float())
		if slot < 1 or slot > GameState.SLOT_COUNT:
			return _one("slot must be 1..%d" % GameState.SLOT_COUNT)
		if not GameState.has_slot(slot):
			return _one("slot %d is empty" % slot)
		ok = bool(GameState.load_from_slot(slot))
		out.append("slot %d: %s" % [slot, "reloading" if ok else "REFUSED (unreadable or off-tree)"])
	if ok:
		out.append_array(release_scene_scoped_state(ctx))
		out.append("the scene reloads: Engine.time_scale was reset to 1.0 and every modal was closed.")
		out.append("this console and every debug overlay in the scene go with it — re-open after the reload.")
	return out


## Sandbox saves. Autosaves fire behind your back on EVERY money / inventory / flag / quest / object-state change,
## so a single `give` or `money` used to overwrite the player's real gamestate.cfg immediately. The sandbox latch on
## GameState (`_sandbox_dir`, driven by enable_sandbox / disable_sandbox / commit_sandbox) makes resolve_save_path
## rewrite ONLY the five canonical profile basenames into user://sandbox/ while active — this command just drives
## the latch and reports. It is session-only: nothing persists the latch, so a crash or relaunch boots the REAL
## profile, which is why `on` and `status` both print the standing warning (and why the F3 overlay paints one).
##
## Every GameState call is duck-typed (has_method / call / get): the sandbox API is ADDITIVE and lands in the same
## change as this command, so an older GameState — or a partial build — must degrade to a printed line, never a
## crash. `status` prefers GameState.sandbox_status_lines() (real vs sandbox presence + size + mtime per file, the
## "which is newer / which is a ghost" answer a commit decision needs) and falls back to a table composed here from
## sandbox_files + resolve_save_path when that method is missing — read from the rewrite itself, never recomputed
## from dir + basename, so the fallback cannot disagree with where a write actually lands.
static func _cmd_sandbox(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	if not GameState.has_method(&"sandbox_active"):
		return _one("sandbox: this GameState has no sandbox API (sandbox_active / enable_sandbox / resolve_save_path) — nothing to drive")
	# validate() already checked the word against the row's verb list (case-insensitively); a blank slot = status.
	var verb := "status" if args.is_empty() else args[0].strip_edges().to_lower()
	match verb:
		"status":
			return _sandbox_status()
		"on":
			return _sandbox_on()
		"off":
			return _sandbox_off(ctx)
		"commit":
			return _sandbox_commit()
	return _one("unknown sandbox action \"%s\" (on, off, status, commit)" % verb)


static func _sandbox_status() -> PackedStringArray:
	var out := PackedStringArray()
	var active := bool(GameState.call(&"sandbox_active"))
	# GameState's own report carries the ON/OFF header plus size + mtime per file (and, while OFF, whether a
	# leftover user://sandbox/ from an earlier session is sitting there for a grab). Only when it is missing do we
	# compose the plainer presence table here.
	var gs_lines: Variant = GameState.call(&"sandbox_status_lines") if GameState.has_method(&"sandbox_status_lines") else null
	if gs_lines is PackedStringArray and not (gs_lines as PackedStringArray).is_empty():
		out.append_array(gs_lines as PackedStringArray)
	elif active:
		out.append("sandbox ON — every profile write lands in %s (the real files are frozen as of `sandbox on`)" % _sandbox_dir_text())
		out.append_array(_sandbox_file_lines(active))
	else:
		out.append("sandbox OFF — writes go to the real profile")
		out.append_array(_sandbox_file_lines(active))
	if active:
		out.append("! STANDING WARNING: a crash or relaunch boots the REAL profile — sandbox progress is lost unless you `sandbox commit`.")
		out.append("! the Save/Load screen's row captions and the editor Saves dock read the REAL files by raw path — trust this status, not a caption.")
	out.append_array(_save_telemetry_lines())
	return out


static func _sandbox_on() -> PackedStringArray:
	if not GameState.has_method(&"enable_sandbox"):
		return _one("sandbox: GameState has no enable_sandbox()")
	var out := PackedStringArray()
	if bool(GameState.call(&"sandbox_active")):
		# Deliberately NOT re-entered: enable_sandbox re-copies the real files INTO the sandbox, which would throw
		# away everything the sandbox run has written since. "Already on" is a report, not a reset.
		out.append("sandbox already ON — %s (nothing re-copied; `sandbox off` then `sandbox on` for a fresh copy)" % _sandbox_dir_text())
	else:
		var err := int(GameState.call(&"enable_sandbox"))
		var now_on := bool(GameState.call(&"sandbox_active"))
		if not now_on:
			return _one("sandbox on: enable_sandbox returned Error %d (%s) and the latch did NOT set — writes still go to the real profile" % [err, error_string(err)])
		if err != OK:
			out.append("! enable_sandbox returned Error %d (%s) — the latch IS set, but at least one real file failed to copy (see the list)" % [err, error_string(err)])
		out.append("sandbox ON — the real profile was copied into %s and EVERY save now lands there" % _sandbox_dir_text())
		out.append("  autosave, F5 quicksave, the slots and Continue all read/write the sandbox copies; the real files are frozen as of now.")
		out.append("  the live run was NOT reloaded — you keep playing exactly where you were, only the write target moved.")
		out.append_array(_sandbox_file_lines(true))
	out.append("! STANDING WARNING: a crash or relaunch boots the REAL profile — sandbox progress is lost unless you `sandbox commit`.")
	# GameState redirects ITS OWN file access only; SaveLoadScreen.slot_metadata and the editor Saves dock still open
	# the raw user:// paths for their captions (documented as a known limitation on GameState's sandbox block).
	out.append("! the Save/Load screen's row captions and the editor Saves dock read the REAL files by raw path — trust `sandbox status`, not a caption.")
	out.append("`sandbox off` reloads the real profile (the scene reloads); `sandbox commit` copies the sandbox over the real files.")
	return out


## `off` MUST reload the real profile, not just clear the latch: the in-memory GameState is the sandbox run
## (cheated money, flags, quests), and the next autosave — which fires on the next money/inventory/flag change —
## would write it to the REAL path. Reusing GameState._load_and_reload(SAVE_PATH) (the quickload body: load_from_disk
## + close_all_modals + time_scale 1.0 + the _reload_pending latch + reload_current_scene) rather than mirroring it
## here, so the one place that knows how to swap profiles safely stays the one place — the _reload_pending latch is
## what stops a same-frame deferred autosave flush from writing the abandoned sandbox timeline over the just-loaded
## real file. Called AFTER disable_sandbox, so its own resolve_save_path is the identity and SAVE_PATH is the real file.
##
## With NO real gamestate.cfg to reload into (the sandbox was armed from the main menu and New Game ran inside it),
## `off` REFUSES and leaves the latch ON: clearing it would make the very next autosave mint a real profile out of
## the cheated run — the one leak the sandbox exists to prevent — and there is nothing to reload the memory from.
## The two clean exits (commit, then off; or relaunch — the latch is session-only) are printed instead. The existence
## check runs BEFORE disable_sandbox against the raw SAVE_PATH const, which IS the real file while the latch is on.
static func _sandbox_off(ctx: Dictionary) -> PackedStringArray:
	if not bool(GameState.call(&"sandbox_active")):
		return _one("sandbox is already OFF")
	if not GameState.has_method(&"disable_sandbox"):
		return _one("sandbox: GameState has no disable_sandbox()")
	if GameState.reload_pending():
		return _one("a quickload is in flight (GameState.reload_pending) — let the fresh scene boot before turning the sandbox off")
	var real_path := String(GameState.SAVE_PATH)
	if not FileAccess.file_exists(real_path):
		var refused := PackedStringArray()
		refused.append("sandbox off REFUSED — no real profile at %s to reload into, so the latch stays ON." % real_path)
		refused.append("! clearing it would let the next autosave write the sandbox run to the REAL path (a cheated Continue).")
		refused.append("`sandbox commit` first to make this run the real profile, then `sandbox off` — or relaunch (the sandbox is session-only).")
		return refused
	if not GameState.has_method(&"_load_and_reload"):
		return _one("sandbox off REFUSED — GameState has no _load_and_reload(path), so the real profile could not be reloaded; the latch stays ON. Relaunch to leave the sandbox.")

	var out := PackedStringArray()
	var dir_text := _sandbox_dir_text()
	var armed_dir := String(GameState.call(&"sandbox_dir"))
	GameState.call(&"disable_sandbox")
	var ok := bool(GameState.call(&"_load_and_reload", real_path))
	if not ok:
		# ⭐RE-ARM, do not leak. The latch is already clear and the in-memory profile is still the sandbox run, so
		# the very next autosave would mint a cheated real Continue. Re-setting `_sandbox_dir` directly (NOT
		# enable_sandbox, which would re-FORK the real files over the sandbox and destroy the run) puts every
		# write back where it was. Only the private field does this without side effects — an intentional reach.
		GameState.set(&"_sandbox_dir", armed_dir)
		out.append("sandbox off REFUSED — _load_and_reload(%s) failed (unreadable primary + both rungs, or GameState off-tree); the latch is RE-ARMED so nothing leaks." % real_path)
		out.append("`sandbox commit` then relaunch is the safe way out of this state.")
		return out
	out.append("sandbox OFF — the latch is clear; %s stays on disk (the next `sandbox on` re-copies the real files over it)" % dir_text)
	# reload_current_scene is deferred to the end of the frame, so the console (and ctx[&"state"]) is still alive
	# here — same order as `load`: release only once the reload is actually in flight, so a refused reload keeps
	# the timescale override the user still has.
	out.append_array(release_scene_scoped_state(ctx))
	out.append("real profile reloaded from %s — the scene reloads into ITS level, checkpoint and clock." % real_path)
	out.append("_reload_pending is latched, so a deferred autosave queued this frame cannot write the sandbox run over it.")
	out.append("this console and every debug overlay in the scene go with the reload — re-open after it.")
	return out


## `commit` is the one sandbox verb that touches the real profile. The registry marks the row danger (the menu
## confirms, the console prints its note), and this body says so again in its own words because no in-game command
## reverses a commit — the only undo is the `.bak` GameState._commit_file rotates the previous real primary to (via
## _swap_into_place, the same rotate rules as a normal write; a fallback-flagged real path is discarded instead and
## its .bak left alone), and restoring that is a by-hand file copy outside the game. The per-file result is
## measured, not assumed: after the call each real file is compared byte-for-byte (FileAccess.get_md5) against its
## sandbox source, so a copy that silently did not land reads MISMATCH.
static func _sandbox_commit() -> PackedStringArray:
	if not bool(GameState.call(&"sandbox_active")):
		return _one("sandbox is OFF — nothing to commit (`sandbox on`, play, then `sandbox commit`)")
	if not GameState.has_method(&"commit_sandbox"):
		return _one("sandbox: GameState has no commit_sandbox()")
	var out := PackedStringArray()
	out.append("! COMMIT: the real profile files are being OVERWRITTEN by the sandbox copies — no in-game command undoes this.")
	out.append("  (each previous real file rotates to <name>.bak beside it — a by-hand copy outside the game is the only way back)")
	var err := int(GameState.call(&"commit_sandbox"))
	out.append("commit_sandbox: %s" % ("OK" if err == OK else "Error %d (%s) — per-file result below" % [err, error_string(err)]))
	for real: String in _sandbox_files():
		var boxed := _resolved_save_path(real)
		var label := real.get_file()
		if boxed == real or not FileAccess.file_exists(boxed):
			out.append("  %-18s no sandbox copy — the real file was left as it was" % label)
		elif not FileAccess.file_exists(real):
			out.append("  %-18s NOT COPIED — no real file after the commit" % label)
		elif FileAccess.get_md5(boxed) == FileAccess.get_md5(real):
			out.append("  %-18s committed (real file is byte-identical to the sandbox copy)" % label)
		else:
			out.append("  %-18s MISMATCH — the real file differs from the sandbox copy; the copy did not land" % label)
	out.append("sandbox stays ON: later writes keep landing in the sandbox — `sandbox commit` again to push them, `sandbox off` to play the (now committed) real profile.")
	return out


## One line per canonical save file: whether the real file exists and, while active, whether its sandbox copy does.
static func _sandbox_file_lines(active: bool) -> PackedStringArray:
	var out := PackedStringArray()
	var files := _sandbox_files()
	if files.is_empty():
		out.append("  (GameState has no sandbox_files() — cannot list the canonical paths)")
		return out
	for real: String in files:
		var line := "  %-18s real %s" % [real.get_file(), ("yes" if FileAccess.file_exists(real) else "-")]
		if active:
			var boxed := _resolved_save_path(real)
			line += "   sandbox %s" % ("yes" if boxed != real and FileAccess.file_exists(boxed) else "-")
		out.append(line)
	return out


## The five REAL canonical paths (gamestate / quicksave / 3 slots), or empty when the API is missing.
static func _sandbox_files() -> PackedStringArray:
	if not GameState.has_method(&"sandbox_files"):
		return PackedStringArray()
	var raw: Variant = GameState.call(&"sandbox_files")
	if raw is PackedStringArray:
		var files: PackedStringArray = raw
		return files
	return PackedStringArray()


## Where a canonical path ACTUALLY lands right now — the sandbox rewrite when active, the path itself otherwise.
## Read from resolve_save_path (never recomputed from dir + basename) so the report cannot drift from the rewrite.
static func _resolved_save_path(path: String) -> String:
	if not GameState.has_method(&"resolve_save_path"):
		return path
	var raw: Variant = GameState.call(&"resolve_save_path", path)
	return String(raw) if raw is String else path


static func _sandbox_dir_text() -> String:
	if not GameState.has_method(&"sandbox_dir"):
		return "(sandbox_dir() missing)"
	var raw: Variant = GameState.call(&"sandbox_dir")
	var dir := String(raw) if raw is String else ""
	return dir if dir != "" else "(no dir — latch off)"


# =============================================================================================================
# AI
# =============================================================================================================

## Spawn NPCs in front of the player. The ordering here is the whole command:
##   1. `profile` MUST be written BEFORE add_child — _apply_profile() is the FIRST line of NPC._ready and stamps
##      ~50 fields (max_hp, faction, weapon_data, sight_range, threat_response). Setting it after does nothing.
##   2. `_dynamic_spawn` marks the body as ephemeral so _record_snapshot_death never writes its @-generated node
##      path into the per-level save death ledger (where it could later suppress a legit authored enemy).
##   3. `_spawn_position` is latched in _ready from global_position — i.e. BEFORE we move the body — so it must be
##      re-stamped, or wander radius / return-to-post / is_sitting()'s at-post test anchor at the wrong spot.
##   4. The body is added as a SIBLING inside the LEVEL subtree, never under a CanvasLayer or the player.
static func _cmd_spawn(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var tree := _tree(ctx)
	if tree == null:
		return _one("no SceneTree")
	var player := _player3d(ctx)
	if player == null:
		return _one("no player — spawn places bodies relative to you")

	var wanted := args[0]
	var profile_path := _lookup(_npcs(), wanted)
	if profile_path == "":
		return _one("no NpcData archetype \"%s\" — try: %s" % [wanted, ", ".join(_sorted_keys(_npcs()))])
	var profile := load(profile_path)
	if profile == null:
		return _one("could not load %s" % profile_path)

	var scene := load(NPC_SCENE_PATH) as PackedScene
	if scene == null:
		return _one("could not load %s" % NPC_SCENE_PATH)

	var requested := 1
	if args.size() > 1:
		requested = int(args[1].to_float())
	var count := clampi(requested, 1, MAX_SPAWN_COUNT)

	var parent := _level_node(tree)
	if parent == null:
		parent = tree.current_scene
	if parent == null:
		return _one("nowhere to parent the spawn (no level and no current scene)")

	# Aim basis, flattened: "in front of me" means where I am LOOKING, not where the capsule happens to point.
	# get_aim_basis() (NOT get_aim_direction(), which applies the AimSway drift) is the camera's own basis.
	var basis := player.global_transform.basis
	if player.has_method(&"get_aim_basis"):
		var aim: Variant = player.call(&"get_aim_basis")
		if aim is Basis:
			basis = aim
	var forward := -basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var side := forward.cross(Vector3.UP).normalized()
	var origin := player.global_position + forward * SPAWN_DISTANCE + Vector3.UP * SPAWN_LIFT

	var made := 0
	var last := Vector3.ZERO
	for i in count:
		var npc := scene.instantiate()
		if npc == null:
			continue  # empty-PackedScene reimport transient; EncounterSpawner and NpcPool both guard for it
		npc.set(&"profile", profile)         # (1) before add_child or _apply_profile never sees it
		npc.set(&"_dynamic_spawn", true)     # (2) keep it out of the save's death ledger
		parent.add_child(npc)                # runs the whole (expensive) _ready synchronously
		var body := npc as Node3D
		if body != null:
			var pos := origin + side * ((float(i) - float(count - 1) * 0.5) * SPAWN_SPACING)
			body.global_position = pos
			npc.set(&"_spawn_position", pos)  # (3) re-anchor wander / return-to-post after the move
			last = pos
		made += 1

	var out := PackedStringArray()
	out.append("spawned %d x %s under %s" % [made, wanted, parent.name])
	if made > 0:
		out.append("at ~(%.1f, %.1f, %.1f), marked _dynamic_spawn so their deaths never enter the save ledger" % [last.x, last.y, last.z])
	if requested > count:
		out.append("! %d requested, capped at %d — NPC._ready builds ~20 components + a weapon per body and hitches badly" % [requested, MAX_SPAWN_COUNT])
	out.append("nav: a body spawned before the map syncs cannot path yet; it will start moving a frame or two late.")
	out.append("NPC.tscn ships sight_range 500, so these hold you as _target immediately — `who` shows their real perception state.")
	return out


static func _cmd_npcs(ctx: Dictionary) -> PackedStringArray:
	var tree := _tree(ctx)
	var out := PackedStringArray()
	var index := _npcs()
	if index.is_empty():
		out.append("no NpcData archetypes under %s" % NPC_DIR)
	else:
		out.append("-- archetypes on disk (spawn by the name on the left)")
		for stem in _sorted_keys(index):
			var res := load(String(index[stem]))
			var label := String(res.get("display_name")) if res != null else "?"
			out.append("   %-20s %s" % [stem, label])
	if tree == null:
		return out
	var alive := 0
	var dead := 0
	for n in tree.get_nodes_in_group(GroupsScript.NPC):
		# is_instance_valid FIRST, always: queue_free() is deferred, so the group can still hold a freed body this
		# frame, and `is` CRASHES on a freed instance.
		if not is_instance_valid(n):
			continue
		if n.has_method(&"is_alive") and bool(n.call(&"is_alive")):
			alive += 1
		else:
			dead += 1
	out.append("-- in this level: %d alive, %d dying/dead still in the \"%s\" group" % [alive, dead, String(GroupsScript.NPC)])
	return out


## Kill every living NPC (optionally within a radius of the player).
##
## The hitstop is the whole difficulty here: every death calls FreezeFrame.pause_briefly, and every body also runs
## a death FREEZE beat on a SceneTree timer before it gores. Both are gated on GameSettings.allow_timescale_changes
## (freeze_frame.gd:16/:39, npc.gd _begin_death), so clearing that flag for the duration of the sweep suppresses
## BOTH — and, because the freeze beat is skipped, each death completes SYNCHRONOUSLY inside the loop, so restoring
## the flag immediately afterwards is safe rather than racing a pending timer.
static func _cmd_killall(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var tree := _tree(ctx)
	if tree == null:
		return _one("no SceneTree")
	var player := _player(ctx)
	var player3 := _player3d(ctx)
	var radius := -1.0
	if not args.is_empty():
		radius = maxf(0.0, args[0].to_float())
		if player3 == null:
			return _one("a radius needs a player to measure from")

	var saved_allow := bool(GameSettings.allow_timescale_changes)
	GameSettings.allow_timescale_changes = false

	# Iterate a DUPLICATE: each kill frees (or pools) a body, and get_nodes_in_group's array must not be the thing
	# we mutate underneath ourselves.
	var nodes := tree.get_nodes_in_group(GroupsScript.NPC).duplicate()
	var killed := 0
	var skipped := 0
	for n in nodes:
		if not is_instance_valid(n):
			continue
		# take_damage EARLY-RETURNS on the dead latch, and hp can already be <= 0 while the body is still grouped —
		# so gate on is_alive(), not on membership.
		if not n.has_method(&"is_alive") or not bool(n.call(&"is_alive")):
			continue
		if radius >= 0.0:
			var body := n as Node3D
			if body == null or body.global_position.distance_to(player3.global_position) > radius:
				skipped += 1
				continue
		if not n.has_method(&"take_damage"):
			continue
		# attacker = the player so the kill is fully credited (XP, notify_kill, bounty, wallet bequeath) and the
		# enemy health bar paints. hit_pos is left at its default Vector3.INF to skip limb/cripple damage.
		n.call(&"take_damage", KILL_DAMAGE, false, player)
		killed += 1

	GameSettings.allow_timescale_changes = saved_allow

	var out := PackedStringArray()
	out.append("killed %d NPC%s%s" % [killed, ("" if killed == 1 else "s"), (" within %.1f m" % radius) if radius >= 0.0 else ""])
	if skipped > 0:
		out.append("%d living NPC(s) outside the radius were left alone" % skipped)
	out.append("hitstop + per-body death freeze suppressed for the sweep (allow_timescale_changes restored to %s)." % str(saved_allow))
	if killed > 0:
		out.append("! still fired per kill: gore/gibs, a lootable corpse, a corpse marker, witness barks and a faction kill_penalty.")
		# A recruited COMPANION is an NPC that additionally joined Groups.PLAYER (npc.gd:1924) without ever leaving
		# &"npc" — so a group sweep kills your own escort too. Say so rather than let it read as a bug.
		out.append("! recruited companions live in the \"%s\" group too — they were killed with everyone else." % String(GroupsScript.NPC))
		# Every AUTHORED (.tscn-placed) death went through NPC._record_snapshot_death -> GameState.record_npc_death, and
		# GameRoot.load_level suppresses those keys on EVERY re-instantiate — so `killall` + `reload` leaves the level
		# empty for the rest of the session. Nothing public clears that ledger except `resurrect`; say so here.
		out.append("! authored (.tscn-placed) kills were written to the exact-snapshot death ledger — they stay dead across `reload` / door swaps for the rest of the session; `resurrect` forgets this level's entries.")
		if player == null:
			out.append("! no player was passed as the attacker, so no XP, no kill bounty and no quest notify_kill.")
	return out


## De-escalate everyone. `stand_down_on_player_death` is the REPEATABLE de-provoke: it runs the same _clear_provoke
## body as forgive_provoke (dropping _provoked and restoring the exact faction rep the provoke took) but plays no
## cue and does NOT spend the once-per-life holster-forgiveness latch, which forgive_provoke would.
static func _cmd_peace(ctx: Dictionary) -> PackedStringArray:
	var tree := _tree(ctx)
	if tree == null:
		return _one("no SceneTree")
	var nodes := tree.get_nodes_in_group(GroupsScript.NPC).duplicate()
	var settled := int(HostilityHelpersScript.settle_provoked_grudges(nodes))
	var stood := 0
	var grudges := 0
	for n in nodes:
		if not is_instance_valid(n):
			continue
		# NPC-vs-NPC grudges are a private Array with no public clear, and stand_down() deliberately leaves them
		# alone — but "peace" that leaves the cast still hunting each other is a lie, so clear the array in place.
		var g: Variant = n.get(&"_npc_grudges")
		if g is Array:
			var arr: Array = g  # the SAME array, not a copy — .clear() lands on the NPC's own field
			if not arr.is_empty():
				grudges += arr.size()
				arr.clear()
		if n.has_method(&"stand_down"):
			n.call(&"stand_down")  # drop the held target, forget, hide the laser
			stood += 1
	var out := PackedStringArray()
	out.append("peace: %d provocation(s) settled, %d peer grudge(s) cleared, %d NPC(s) stood down" % [settled, grudges, stood])
	out.append("! a faction soured by KILLS keeps that penalty — kill_penalty is never reversed.")
	out.append("! a predisposed-hostile NPC (raiders) was never provoked and stays hostile; it re-acquires within ~0.5 s.")
	return out


## Provoke everyone onto the player. apply_rep MUST be false: the default true applies the faction reputation
## penalty PER MEMBER, so a bulk aggro multiplies GameSettings.reputation.provoke_penalty by the squad size.
static func _cmd_aggro(ctx: Dictionary) -> PackedStringArray:
	var tree := _tree(ctx)
	if tree == null:
		return _one("no SceneTree")
	var player := _player(ctx)
	if player == null:
		return _one("no player to aggro onto")
	var count := 0
	for n in tree.get_nodes_in_group(GroupsScript.NPC).duplicate():
		if not is_instance_valid(n) or not n.has_method(&"provoke"):
			continue
		# Skip the dead: provoke() is not gated on the death latch, so on a corpse it would still flip _provoked,
		# recolour the outline and pop a negative icon over a body that will never act on any of it — and it would
		# inflate the count with kills. Same is_alive() gate `killall` uses, same reason.
		if not n.has_method(&"is_alive") or not bool(n.call(&"is_alive")):
			continue
		n.call(&"provoke", player, false)
		count += 1
	var out := PackedStringArray()
	out.append("provoked %d living NPC(s) onto you" % count)
	out.append("apply_rep = false: NO faction reputation was spent (the default true would charge provoke_penalty per member).")
	# Groups.NPC is the whole cast; a RECRUITED COMPANION is an NPC that ALSO joined Groups.PLAYER (npc.gd:1924)
	# and never left &"npc", so it is provoked onto you along with everyone else.
	out.append("! recruited companions are in the \"%s\" group too — they were turned on you as well." % String(GroupsScript.NPC))
	return out


## The only TRUE AI suppression. The cutscene-control gate returns before perception, targeting and GOAP; AiLod
## only changes the think CADENCE, and Perception.forget() / stand_down() only break the current engagement.
static func _cmd_freezeai(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var tree := _tree(ctx)
	if tree == null:
		return _one("no SceneTree")
	var state := _state(ctx)
	var current := bool(state.get(STATE_FREEZE_AI, false))
	var on := bool(DebugCommandsScript.toggle_value("" if args.is_empty() else args[0], current))
	var count := 0
	for n in tree.get_nodes_in_group(GroupsScript.NPC).duplicate():
		if not is_instance_valid(n) or not n.has_method(&"set_cutscene_control"):
			continue
		n.call(&"set_cutscene_control", on)
		count += 1
	state[STATE_FREEZE_AI] = on
	var out := PackedStringArray()
	out.append("freezeai %s — %d NPC(s) under cutscene control" % ["ON" if on else "OFF", count])
	if on:
		out.append("perception, targeting, GOAP and locomotion are all suppressed; only gravity and scripted movement run.")
		out.append("! NPCs spawned after this stay live — re-run `freezeai on` after a `spawn`.")
	else:
		out.append("released: the scripted walk/face was cleared and desired velocity zeroed, so the AI resumes from a standstill.")
	return out


## The look-at readout, on demand. Reuses DebugInspector.describe_target() rather than duplicating its raycast, so
## `who` and the live `inspect` overlay can never disagree about what you are pointing at.
static func _cmd_who(ctx: Dictionary) -> PackedStringArray:
	var insp := _inspector(ctx)
	if insp == null:
		return _one("who: no DebugInspector available (%s missing, or the name is taken under the current scene)" % INSPECTOR_SCRIPT_PATH)
	if not insp.has_method(&"describe_target"):
		return _one("who: DebugInspector has no describe_target()")
	var lines: PackedStringArray = insp.call(&"describe_target")
	if lines.is_empty():
		return _one("nothing under the crosshair")
	return lines


# =============================================================================================================
# AI — the per-NPC verbs (brain / npc <verb> / notarget)
# =============================================================================================================

## Which NPC a `brain` / `npc <verb>` acts on, and where "the point" is. Returned as a small Dictionary so the two
## commands share ONE resolution and can never disagree:
##   &"npc"    Node or null   — the acted-on NPC (crosshair NPC first, else the sticky one from the last command)
##   &"aimed"  Node or null   — whatever the inspector resolved this tick (may be a wall, the player, or the NPC)
##   &"sticky" bool           — the NPC came from STATE_NPC_STICKY, not the crosshair
##   &"error"  String         — non-empty = nothing to act on; the caller returns it verbatim
##
## Reads the inspector's PHYSICS-TICK CACHE through its target() accessor — never a fresh raycast: a
## direct_space_state query outside a physics frame silently returns EMPTY (the spacestate-needs-a-physics-frame
## trap `tpaim` documents in debug_actions_player.gd), and run() is called from an input callback. Both accessors
## are ADDITIVE and land beside this change, so they are probed with has_method and their absence is one honest
## line rather than a crash.
static func _resolve_aimed_npc(ctx: Dictionary) -> Dictionary:
	var out := {&"npc": null, &"aimed": null, &"sticky": false, &"error": ""}
	var insp := _inspector(ctx)
	if insp == null:
		out[&"error"] = "no DebugInspector available (%s missing, or the name is taken under the current scene)" % INSPECTOR_SCRIPT_PATH
		return out
	if not insp.has_method(&"target"):
		out[&"error"] = "DebugInspector has no target() accessor — the look-at inspector predates the per-NPC commands (add target()/hit_point() to debug_inspector.gd)"
		return out
	# The two "cold cache" walls describe_target() reports, mirrored — but tracking-OFF is checked FIRST and
	# regardless of _has_ticked: an inspector that ticked once and was then switched off (`inspect off` on an authored
	# node with always_track unticked) still HOLDS its last resolved target, and `who` will happily describe that
	# stale node — acceptable for a readout, not for `npc kill`, which would act on whatever you aimed at minutes
	# ago. A node that IS tracking but has not run a physics tick yet (this command just created it) is the other
	# wall: ask again next frame.
	if _bool_of(insp.get(&"_gated_off")):
		out[&"error"] = "the DebugInspector is inert (release-build gate, force_in_release unticked) — target()/hit_point() always read null/INF here"
		return out
	if not insp.is_physics_processing():
		out[&"error"] = "look-at tracking is OFF (the inspector is disabled and always_track is unticked) — `inspect on` first"
		return out
	var ticked: Variant = insp.get(&"_has_ticked")
	if ticked is bool and not bool(ticked):
		out[&"error"] = "the look-at inspector arms on the next physics frame (the aim ray is only valid inside one) — run it again"
		return out
	var raw: Variant = insp.call(&"target")
	var aimed: Node = null
	if raw != null and is_instance_valid(raw):
		aimed = raw as Node
	out[&"aimed"] = aimed
	var state := _state(ctx)
	if aimed != null and aimed.is_inside_tree() and aimed.is_in_group(GroupsScript.NPC):
		out[&"npc"] = aimed
		state[STATE_NPC_STICKY] = aimed
		return out
	# Not aiming at an NPC: fall back to the last one an `npc`/`brain` command touched, if it still stands.
	var held: Variant = state.get(STATE_NPC_STICKY)
	if held != null and is_instance_valid(held):
		var prev := held as Node
		if prev != null and prev.is_inside_tree() and prev.is_in_group(GroupsScript.NPC):
			out[&"npc"] = prev
			out[&"sticky"] = true
			return out
	state.erase(STATE_NPC_STICKY)
	if aimed != null and aimed.is_in_group(GroupsScript.PLAYER) and not aimed.is_in_group(GroupsScript.NPC):
		out[&"error"] = "that is you — aim at an NPC (a recruited companion counts; it is in both groups)"
	elif aimed != null:
		out[&"error"] = "\"%s\" is not an NPC (not in the \"%s\" group) and no earlier `npc` target is standing — aim at one first" % [String(aimed.name), String(GroupsScript.NPC)]
	else:
		out[&"error"] = "nothing under the crosshair and no earlier `npc` target is standing — aim at an NPC first"
	return out


## The world POINT for `npc investigate` / `npc walkto`. When the crosshair is on the acted-on NPC itself, the
## hit is on ITS BODY — "walk to where you already stand" — so "here" resolves to YOUR position (walk to me /
## investigate me, the classic per-NPC poke) and the output says so. When the NPC is the sticky one, the crosshair
## is free to point at the floor across the room, and THAT hit is the point. Vector3.INF = no usable point; the
## caller prints the workflow hint. Reads the inspector's cached hit (hit_point(), physics-tick, INF when nothing
## was struck) — never a fresh raycast, for the reason on _resolve_aimed_npc.
static func _npc_point(ctx: Dictionary, pick: Dictionary) -> Dictionary:
	var out := {&"point": Vector3.INF, &"how": ""}
	var npc: Node = pick[&"npc"]
	var aimed: Node = pick[&"aimed"]
	if aimed != null and aimed == npc:
		var player := _player3d(ctx)
		if player == null or not player.is_inside_tree():
			out[&"how"] = "the crosshair is on the NPC itself and there is no player to stand in for \"here\""
			return out
		out[&"point"] = player.global_position
		out[&"how"] = "your position (the crosshair is on the NPC itself, so \"here\" means you)"
		return out
	var insp := _inspector(ctx)
	if insp == null or not insp.has_method(&"hit_point"):
		out[&"how"] = "DebugInspector has no hit_point() accessor"
		return out
	var raw: Variant = insp.call(&"hit_point")
	if raw is Vector3:
		var p: Vector3 = raw
		if p.is_finite():
			out[&"point"] = p
			out[&"how"] = "the crosshair hit at %s" % _vec3_text(p)
			return out
	out[&"how"] = "the crosshair is on nothing — aim at the floor / a wall where it should go and run it again"
	return out


## `brain` — the GOAP "why this plan" dump for the aimed NPC. The executor keeps ONLY the winner (decide() stores
## current_goal + plan and select_goal SHORT-CIRCUITS, so losing goals are never even planned) and the shipped
## "goal / action" label cannot show why a behaviour silently never runs (a sensed sentinel fact self-satisfies a
## goal -> plan() == [] -> skipped; goap_executor.gd @risk lines). So this re-runs the PURE planner over a FRESH
## world state and prints every candidate, then puts the executor's STICKY plan beside it, labelled — the two can
## legitimately differ, because tick() only replans when the stepped action is null or is_runtime_valid() fails.
## Everything here is read-only: _build_world_state is underscore-private but pure (host reads), plan()/
## select_goal() are side-effect-free statics, and is_runtime_valid() on every shipped action is a plain state read.
static func _cmd_brain(ctx: Dictionary) -> PackedStringArray:
	var pick := _resolve_aimed_npc(ctx)
	var err: String = pick[&"error"]
	if err != "":
		return _one("brain: " + err)
	var npc: Node = pick[&"npc"]
	var out := PackedStringArray()
	out.append("brain: %s%s" % [_npc_label(npc), "   (sticky: your last `npc` target — the crosshair is not on an NPC)" if bool(pick[&"sticky"]) else ""])
	if not _alive(npc):
		out.append("dead — the executor stopped ticking with the body; the plan below is whatever it last held")

	var executor: Object = npc.get(&"_executor")
	if executor == null or not is_instance_valid(executor):
		out.append("no _executor on this NPC (bare / partially built) — nothing plans for it")
		return out
	if not executor.has_method(&"_build_world_state"):
		out.append("the executor has no _build_world_state(host) — API drift between goap_executor.gd and this command")
		return out

	# --- the sensed facts (a FRESH snapshot, exactly what tick() would build this frame) ---
	var ws: Variant = executor.call(&"_build_world_state", npc)
	if ws == null or not is_instance_valid(ws):
		out.append("_build_world_state returned nothing")
		return out
	var facts_v: Variant = ws.get(&"facts")
	var facts: Dictionary = facts_v if facts_v is Dictionary else {}
	out.append("facts " + _facts_text(facts))
	var cutscene: Variant = npc.get(&"_cutscene_control")
	if cutscene is bool and bool(cutscene):
		out.append("! under cutscene control (freezeai / `npc walkto|freeze` / a CutsceneActor) — the executor is NOT ticking; its plan below is frozen where it was")

	var goals_v: Variant = executor.get(&"goals")
	var actions_v: Variant = executor.get(&"actions")
	var goals: Array = goals_v if goals_v is Array else []
	var actions: Array = actions_v if actions_v is Array else []
	if goals.is_empty() or actions.is_empty():
		out.append("library: %d goal(s), %d action(s) — an empty library never plans (setup() not run?)" % [goals.size(), actions.size()])
		return out

	# --- every goal, in priority order, each planned from the fresh facts ---
	var would_pick: Object = GoapPlannerScript.select_goal(ws, goals, actions)
	var ordered: Array = goals.duplicate()
	ordered.sort_custom(func(a: Variant, b: Variant) -> bool: return _goal_priority(a, ws) > _goal_priority(b, ws))
	out.append("-- goals by priority(ws)   (* = what select_goal would pick NOW: highest priority with a non-empty plan)")
	for g in ordered:
		if g == null or not is_instance_valid(g):
			continue
		var gname := _name_of(g)
		var mark := "*" if g == would_pick else " "
		var satisfied := bool(g.call(&"satisfied_by", ws)) if g.has_method(&"satisfied_by") else false
		var unmet := int(g.call(&"unmet_count", ws)) if g.has_method(&"unmet_count") else -1
		var plan: Array = GoapPlannerScript.plan(ws, actions, g)
		var plan_text := ""
		if not plan.is_empty():
			plan_text = "plan %s  (cost %.1f)" % [_plan_text(plan), _plan_cost(plan, ws)]
		elif satisfied:
			plan_text = "no plan — ALREADY SATISFIED, so select_goal skips it (a sensed sentinel fact would silence this goal for good)"
		else:
			plan_text = "no plan — " + _why_no_plan(g, actions, ws)
		out.append(" %s %-12s prio %5.2f  unmet %d  %s" % [mark, gname, _goal_priority(g, ws), unmet, plan_text])

	# --- every action against the same facts ---
	out.append("-- actions   (available = preconditions hold in the facts; runtime = is_runtime_valid(npc) this instant)")
	for a in actions:
		if a == null or not is_instance_valid(a):
			continue
		var avail := bool(a.call(&"available_in", ws)) if a.has_method(&"available_in") else false
		var cost := float(a.call(&"cost", ws)) if a.has_method(&"cost") else 0.0
		var runtime := bool(a.call(&"is_runtime_valid", npc)) if a.has_method(&"is_runtime_valid") else false
		var pre_v: Variant = a.get(&"preconditions")
		var eff_v: Variant = a.get(&"effects")
		out.append("   %-12s cost %4.1f  available %-3s  runtime %-3s  pre %s  eff %s" % [
			_name_of(a), cost, "yes" if avail else "no", "yes" if runtime else "no",
			_facts_text(pre_v if pre_v is Dictionary else {}), _facts_text(eff_v if eff_v is Dictionary else {})])

	# --- what the executor is ACTUALLY stepping (its sticky plan) vs the fresh pick ---
	var cur_goal: Object = executor.get(&"current_goal")
	var cur_plan_v: Variant = executor.get(&"plan")
	var cur_plan: Array = cur_plan_v if cur_plan_v is Array else []
	var index := _int_of(executor.get(&"index"))
	var stepping: Object = null
	if executor.has_method(&"current_action"):
		stepping = executor.call(&"current_action")
	var goal_text := _name_of(cur_goal) if cur_goal != null and is_instance_valid(cur_goal) else "-"
	var step_text := "-"
	if stepping != null and is_instance_valid(stepping):
		step_text = _name_of(stepping)
		if stepping.has_method(&"is_runtime_valid"):
			step_text += "  [runtime %s]" % ("valid" if bool(stepping.call(&"is_runtime_valid", npc)) else "INVALID — replans on its next think tick")
	out.append("-- executor NOW: goal %s   plan %s   index %d/%d   stepping %s" % [goal_text, _plan_text(cur_plan) if not cur_plan.is_empty() else "[]", index, cur_plan.size(), step_text])
	var pick_text := _name_of(would_pick) if would_pick != null and is_instance_valid(would_pick) else "- (NO feasible goal — Idle should always be; check the goals allow-list)"
	if would_pick != null and cur_goal != null and would_pick == cur_goal:
		out.append("   planner would pick NOW: %s — same goal the executor holds" % pick_text)
	else:
		out.append("   planner would pick NOW: %s — DIFFERS from the executor: tick() only replans when the stepped action is null or is_runtime_valid() fails, so the held plan is sticky until then" % pick_text)
	out.append("(re-run to watch it change; a distant UNAWARE NPC thinks on the AI-LOD cadence, so a poke can take ~0.25 s to land)")
	return out


## `npc <verb> [value]` — act on ONE NPC: the one under the crosshair, else the sticky last one. Every shipped AI
## verb is cast-wide (killall / peace / aggro / freezeai) and the only per-NPC surface was the read-only `who`;
## the bugs that needed "poke this one and watch" — the home-return leash, follow-blink, ledge-following, pacing
## on props, stairs — are all per-NPC. See each verb for the seam it drives and the trap it dodges.
static func _cmd_npc(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var verb := args[0].strip_edges().to_lower()
	var pick := _resolve_aimed_npc(ctx)
	var err: String = pick[&"error"]
	if err != "":
		return _one("npc %s: %s" % [verb, err])
	var npc: Node = pick[&"npc"]
	var out := PackedStringArray()
	out.append("npc %s -> %s%s" % [verb, _npc_label(npc), "   (sticky: your last `npc` target — the crosshair is not on an NPC)" if bool(pick[&"sticky"]) else ""])
	# validate() has already checked the verb against the registry's word list; the value slot is a NUMBER only
	# `sight` reads — it is accepted (and ignored) on every other verb so `npc kill 3` is not an arity error.
	var value := args[1].to_float() if args.size() > 1 else NAN
	match verb:
		"kill": out.append_array(_npc_kill(ctx, npc))
		"heal": out.append_array(_npc_heal(npc))
		"restock": out.append_array(_npc_restock(npc))
		"hostile": out.append_array(_npc_disposition(npc, DispositionScript.Kind.HOSTILE))
		"neutral": out.append_array(_npc_disposition(npc, DispositionScript.Kind.NEUTRAL))
		"friendly": out.append_array(_npc_disposition(npc, DispositionScript.Kind.FRIENDLY))
		"provoke": out.append_array(_npc_provoke(ctx, npc))
		"alert": out.append_array(_npc_alert(ctx, npc))
		"investigate": out.append_array(_npc_investigate(ctx, pick))
		"walkto": out.append_array(_npc_walkto(ctx, pick))
		"release": out.append_array(_npc_control(npc, false, "release"))
		"freeze": out.append_array(_npc_control(npc, true, "freeze"))
		"unfreeze": out.append_array(_npc_control(npc, false, "unfreeze"))
		"home": out.append_array(_npc_home(npc))
		"panic": out.append_array(_npc_panic(npc))
		"sight": out.append_array(_npc_sight(npc, value))
		"rebrain": out.append_array(_npc_rebrain(npc))
		_:
			out.append("unknown verb \"%s\" (registry/actions drift — add a case in _cmd_npc)" % verb)
	return out


## kill: take_damage (NOT die()) so the kill is fully credited — XP, notify_kill, bounty, wallet bequeath, a
## lootable corpse — with the same hitstop suppression `killall` uses (FreezeFrame.pause_briefly and the per-body
## death freeze beat are both gated on allow_timescale_changes, and with the beat skipped the death completes
## synchronously inside this call, so restoring the flag right after is safe).
static func _npc_kill(ctx: Dictionary, npc: Node) -> PackedStringArray:
	if not _alive(npc):
		return _one("already dead — take_damage early-returns on the death latch, nothing to do")
	if not npc.has_method(&"take_damage"):
		return _one("no take_damage() on this node")
	var player := _player(ctx)
	var saved_allow := bool(GameSettings.allow_timescale_changes)
	GameSettings.allow_timescale_changes = false
	npc.call(&"take_damage", KILL_DAMAGE, false, player)
	GameSettings.allow_timescale_changes = saved_allow
	var out := PackedStringArray()
	out.append("killed (%.0f damage, hitstop suppressed, allow_timescale_changes back to %s)" % [KILL_DAMAGE, str(saved_allow)])
	if player == null:
		out.append("! no player passed as the attacker — no XP, no kill bounty, no quest notify_kill")
	else:
		out.append("credited to you: XP, notify_kill, bounty, wallet bequeath; gore/gibs, a lootable corpse, witness barks and the faction kill_penalty all fired")
	# The SAME predicate _record_snapshot_death (npc.gd) and WorldSnapshot use: pooled OR _dynamic_spawn = a dynamic
	# actor. EncounterSpawner stamps _dynamic_spawn on every body it produces (pooled ones included), so the _pool
	# half is belt-and-braces for a body pooled by some other route — mirroring the ledger's own gate rather than
	# half of it keeps this line true if that ever changes.
	var pool: Variant = npc.get(&"_pool")
	var pooled := pool != null and is_instance_valid(pool)
	if _bool_of(npc.get(&"_dynamic_spawn")) or pooled:
		out.append("a dynamic (spawner-produced%s) body — its death stays OUT of the save's death ledger" % (" / pooled" if pooled else ""))
	else:
		# _record_snapshot_death writes an authored NPC's node path into GameState's per-level death ledger, so the
		# exact-snapshot tier (quick/slot saves) remembers it dead — the profile/Continue tier does not.
		out.append("! an AUTHORED NPC — its death is recorded in the exact-snapshot death ledger: a quick/slot save made from here keeps it dead (Continue/autosave does not)")
	return out


## heal: prefer NpcHomeReturn.restore_full_health (the leash's own top-up: Character.heal() so `damaged` fires for
## any bound bar, plus heal_limbs so a crippled leg does not outlive the reset), else the same two seams by hand.
static func _npc_heal(npc: Node) -> PackedStringArray:
	if not _alive(npc):
		return _one("dead — heal restores survivors, it never revives a corpse (there is no path back past the death freeze)")
	var before := _float_of(npc.get(&"hp"))
	var max_hp := _float_of(npc.get(&"max_hp"))
	var out := PackedStringArray()
	var home: Object = npc.get(&"_home_return")
	if home != null and is_instance_valid(home) and home.has_method(&"restore_full_health"):
		var restored := bool(home.call(&"restore_full_health"))
		out.append("NpcHomeReturn.restore_full_health: %s  hp %.0f -> %.0f / %.0f (limbs cleared either way)" % [
			"restored" if restored else "already full", before, _float_of(npc.get(&"hp")), max_hp])
		return out
	if not npc.has_method(&"heal"):
		return _one("no heal() on this node")
	if npc.has_method(&"heal_limbs"):
		npc.call(&"heal_limbs")
	npc.call(&"heal", maxf(max_hp - before, 0.0))
	out.append("heal(): hp %.0f -> %.0f / %.0f, limbs cleared (no NpcHomeReturn on this NPC — healed by hand)" % [before, _float_of(npc.get(&"hp")), max_hp])
	return out


## restock: NPC.restore_spent_ammo — the AMMO half of the player-death encounter reset, driven by hand so you can
## watch it without dying. Refills the magazine and returns every spare clip this NPC's reloads BURNED; it never
## hands back ammo you PICKPOCKETED (the ledger only books clips as they are spent), so a guard you stripped to
## disarm him stays stripped no matter how often you run this. Prints the mag + reserve either side of the call,
## which is what makes the "stolen ammo did NOT come back" half visible.
static func _npc_restock(npc: Node) -> PackedStringArray:
	if not _alive(npc):
		return _one("dead — a corpse's backpack is the loot you earned; the restock only tops up survivors")
	if not npc.has_method(&"restore_spent_ammo"):
		return _one("no restore_spent_ammo() on this node")
	var weapon: Variant = npc.get(&"_weapon")
	if weapon == null or not is_instance_valid(weapon):
		return _one("no weapon hub — a CIVILIAN (weapon_data unset) has no magazine to fill and no caliber to stock")
	var caliber: StringName = &""
	var wd: Variant = weapon.get(&"equipped_weapon")
	if wd != null and is_instance_valid(wd):
		caliber = wd.caliber
	var bag: Variant = npc.get(&"inventory")
	var has_bag := bag != null and is_instance_valid(bag)
	var mag_before := _int_of(weapon.get(&"current_ammo"))
	var clips_before := int(bag.call(&"ammo_count", caliber)) if has_bag and caliber != &"" else 0
	var restored := bool(npc.call(&"restore_spent_ammo"))
	var out := PackedStringArray()
	out.append("NPC.restore_spent_ammo: %s  magazine %d -> %d" % [
		"gave ammo back" if restored else "nothing owed (it has fired nothing since the last restock)",
		mag_before, _int_of(weapon.get(&"current_ammo"))])
	if caliber == &"":
		out.append("  its weapon is caliber-less (melee / free-refill) — there is no reserve to restock")
	elif has_bag:
		out.append("  reserve %s: %d -> %d clips  (only clips its RELOADS spent; anything you pickpocketed stays yours)" % [
			caliber, clips_before, int(bag.call(&"ammo_count", caliber))])
	else:
		out.append("  no backpack on this body — the magazine free-refills and no reserve is tracked")
	return out


## hostile / neutral / friendly — the HostilityHelpers.resolved_kind composite, written as ONE attitude change:
## disposition + disposition_overrides_faction=true (so a factioned NPC reads its OWN disposition instead of the
## faction's rep — `peace` cannot pacify a predisposed raider precisely because the faction decides), then the
## REPEATABLE de-provoke (stand_down_on_player_death: drops _provoked and restores the exact rep the provoke took,
## no cue, does not spend the once-per-life holster pardon that forgive_provoke would), the rim recolour, and
## stand_down (drop target / forget / hide laser) so the AI re-scans against the NEW attitude. Live-only: neither
## save tier stores disposition, so a reload restores the authored attitude.
static func _npc_disposition(npc: Node, kind: int) -> PackedStringArray:
	if not _alive(npc):
		return _one("dead — a corpse has no attitude to change")
	var before_kind := int(npc.call(&"resolved_disposition")) if npc.has_method(&"resolved_disposition") else -1
	npc.set(&"disposition", kind)
	npc.set(&"disposition_overrides_faction", true)
	var settled := false
	if npc.has_method(&"stand_down_on_player_death"):
		settled = bool(npc.call(&"stand_down_on_player_death"))
	if npc.has_method(&"_apply_outline"):
		npc.call(&"_apply_outline")
	if npc.has_method(&"stand_down"):
		npc.call(&"stand_down")
	var after_kind := int(npc.call(&"resolved_disposition")) if npc.has_method(&"resolved_disposition") else kind
	var out := PackedStringArray()
	out.append("attitude %s -> %s  (disposition written, disposition_overrides_faction = true: its faction's rep no longer decides)" % [_disposition_text(before_kind), _disposition_text(after_kind)])
	if settled:
		out.append("its provoke was settled and the exact faction rep that provoke took was restored")
	out.append("target dropped + perception forgotten + laser hidden — it re-scans within ~%.1f s against the new attitude" % _retarget_interval())
	if after_kind == DispositionScript.Kind.HOSTILE:
		out.append("hostile: it re-acquires you by proximity (no LOS gate) inside sight_range — unless `notarget` is on")
	else:
		out.append("non-hostile: dialogue / pickpocket / trade are open on it now; a hit still provoke()s it back to HOSTILE")
	out.append("live-only — neither save tier stores disposition; a reload restores the authored attitude. Rim recoloured.")
	return out


## provoke: apply_rep MUST be false — the default true charges GameSettings.reputation.provoke_penalty, and a debug
## poke should aggro the body without souring the whole faction (the same GA-3 reasoning as `aggro`).
static func _npc_provoke(ctx: Dictionary, npc: Node) -> PackedStringArray:
	if not _alive(npc):
		return _one("dead — provoke() is not gated on the death latch and would flip a corpse's outline for nothing")
	if not npc.has_method(&"provoke"):
		return _one("no provoke() on this node")
	var player := _player(ctx)
	if player == null:
		return _one("no player to provoke it onto")
	var was: Variant = npc.get(&"_provoked")
	npc.call(&"provoke", player, false)
	var out := PackedStringArray()
	if was is bool and bool(was):
		out.append("already provoked — provoke() is idempotent, nothing changed")
	else:
		out.append("provoked onto you (apply_rep = false: NO faction reputation spent). Rim red, negative icon popped.")
	out.append("undo: `npc neutral` / `npc friendly` (settles the provoke), or `peace` for the whole cast")
	return out


## alert: Perception.alert_to(your position, you) — full lock-on at a known spot, the "just got shot" reaction. The
## second arg names YOU as what it noticed (Perception.noticed), so from UNAWARE the "!" is the 2D player-detection
## sting, exactly as a real shot from you would be.
## ⭐It only STICKS while the NPC holds a hostile target: with no target the no-target branch's _react_unaware
## either forget()s a stale ALERTED outright or winds it down through sense() (npc_distraction.gd:58-89), and
## Perception.can_see() is gated on is_hostile — which npc.gd:2529 rewrites every frame from _treats_as_enemy.
static func _npc_alert(ctx: Dictionary, npc: Node) -> PackedStringArray:
	if not _alive(npc):
		return _one("dead")
	var perception: Object = npc.get(&"_perception")
	if perception == null or not is_instance_valid(perception) or not perception.has_method(&"alert_to"):
		return _one("no Perception child (bare NPC) — nothing to alert")
	var player := _player3d(ctx)
	if player == null or not player.is_inside_tree():
		return _one("no player position to alert it to")
	var before := int(_float_of(perception.get(&"state"), -1.0))
	perception.call(&"alert_to", player.global_position, player)
	var out := PackedStringArray()
	out.append("Perception %s -> %s, detection pinned 1.0, last_known_position = you" % [_perception_state_text(before), _perception_state_text(int(_float_of(perception.get(&"state"), -1.0)))])
	# Read _target as a bare Variant, NOT into an Object-typed local: a typed assignment of a previously freed
	# instance is a script error ("Trying to assign invalid previously freed instance"), and an NPC legitimately
	# holds a freed _target for up to retarget_interval after a foe frees mid-fight (npc.gd _physics_process C8).
	var held: Variant = npc.get(&"_target")
	if held == null or not is_instance_valid(held):
		out.append("! it holds NO target — the no-target tick forget()s or decays this alert; it only sticks on a hostile that has you as _target (aim it with `npc hostile` first)")
	elif held == player:
		out.append("it holds you as _target, so sense() keeps this ALERTED while it can see/hear you (under `notarget` it drops next tick)")
	else:
		out.append("its _target is %s (not you) — the alert points at your spot but sense() tracks that target" % String((held as Node).name))
	return out


## investigate: NPC.investigate(point, alerted=true) -> Perception.investigate_point -> INVESTIGATING + the "!"
## sting; the no-target GOAP tick's Search action walks + sweeps the spot. No-op while DETECTING/ALERTED (a real
## target it can see outranks a hunch — perception.gd:258).
static func _npc_investigate(ctx: Dictionary, pick: Dictionary) -> PackedStringArray:
	var npc: Node = pick[&"npc"]
	if not _alive(npc):
		return _one("dead")
	if not npc.has_method(&"investigate"):
		return _one("no investigate() on this node")
	var pt := _npc_point(ctx, pick)
	var point: Vector3 = pt[&"point"]
	if not point.is_finite():
		return _one("needs a point — %s" % String(pt[&"how"]))
	var perception: Object = npc.get(&"_perception")
	var before := -1
	if perception != null and is_instance_valid(perception):
		before = int(_float_of(perception.get(&"state"), -1.0))
	npc.call(&"investigate", point, true)
	var after := before
	if perception != null and is_instance_valid(perception):
		after = int(_float_of(perception.get(&"state"), -1.0))
	var out := PackedStringArray()
	out.append("investigate %s — point = %s" % [_vec3_text(point), String(pt[&"how"])])
	if before == PerceptionScript.State.DETECTING or before == PerceptionScript.State.ALERTED:
		out.append("! no-op: it is %s — a target it can see outranks a hunch (Perception.investigate_point returns early)" % _perception_state_text(before))
	else:
		out.append("Perception %s -> %s; _scripted_investigating set so the no-target tick winds it down over forget_time instead of snapping to idle" % [_perception_state_text(before), _perception_state_text(after)])
		out.append("the GOAP Search action walks + sweeps it off last_known_position — `brain` shows Investigate winning")
	return out


## walkto: set_cutscene_control(true) + walk_to(point) — the ONLY movement input GOAP does not overwrite (the
## AI zeroes _desired_velocity every think). ⭐_tick_cutscene_movement clears the WALK on arrival but LEAVES CONTROL
## LATCHED (npc.gd:2967-2973), so the NPC stands frozen at the spot with perception/GOAP suppressed until `npc
## release` — and the cast-wide `freezeai` latch does not know about this one body.
static func _npc_walkto(ctx: Dictionary, pick: Dictionary) -> PackedStringArray:
	var npc: Node = pick[&"npc"]
	if not _alive(npc):
		return _one("dead")
	if not npc.has_method(&"set_cutscene_control") or not npc.has_method(&"walk_to"):
		return _one("no set_cutscene_control()/walk_to() on this node")
	var pt := _npc_point(ctx, pick)
	var point: Vector3 = pt[&"point"]
	if not point.is_finite():
		return _one("needs a point — %s" % String(pt[&"how"]))
	npc.call(&"set_cutscene_control", true)
	npc.call(&"walk_to", point)
	var body := npc as Node3D
	var dist := body.global_position.distance_to(point) if body != null else 0.0
	var out := PackedStringArray()
	out.append("walking to %s (%.1f m) — point = %s" % [_vec3_text(point), dist, String(pt[&"how"])])
	out.append("! cutscene control LATCHED on this NPC: perception, targeting and GOAP are suspended; arrival clears the walk but NOT the latch — `npc release` hands it back")
	out.append("navmesh move (_move_toward): a point off the mesh reads as arrived immediately; `send_home`/`npc home` refuses while controlled")
	return out


## release / freeze / unfreeze: set_cutscene_control per NPC. Releasing clears the scripted walk/face and the desired
## velocity so the AI resumes from a standstill (npc.gd:2947-2952). Per-body: the `freezeai` STATE_FREEZE_AI latch
## is cast-wide bookkeeping and is neither read nor written here.
static func _npc_control(npc: Node, on: bool, verb: String) -> PackedStringArray:
	if not npc.has_method(&"set_cutscene_control"):
		return _one("no set_cutscene_control() on this node")
	var was: Variant = npc.get(&"_cutscene_control")
	var before := was is bool and bool(was)
	npc.call(&"set_cutscene_control", on)
	var out := PackedStringArray()
	if on:
		out.append("%s: cutscene control ON%s — perception, targeting, GOAP and locomotion suppressed; only gravity + scripted movement run" % [verb, " (it already was)" if before else ""])
		out.append("undo with `npc release` / `npc unfreeze`; the cast-wide `freezeai` latch does not track this body")
	else:
		out.append("%s: cutscene control OFF%s — scripted walk/face cleared, desired velocity zeroed; the AI resumes from a standstill" % [verb, "" if before else " (it was not under control)"])
	return out


## home: NPC.send_home(force=true) -> NpcHomeReturn.return_home(ignore_view) — blink (if blink_home) or stand down
## and let the Idle floor walk it back. Returns false when exempt: dead, under cutscene control, following, a
## bodyguard, mid-talk approach, or the component disabled/missing.
static func _npc_home(npc: Node) -> PackedStringArray:
	if not npc.has_method(&"send_home"):
		return _one("no send_home() on this node")
	var sent := bool(npc.call(&"send_home", true))
	var out := PackedStringArray()
	if sent:
		var home: Object = npc.get(&"_home_return")
		var blink := home != null and is_instance_valid(home) and _bool_of(home.get(&"blink_home"))
		out.append("sent home (force = true, the on-screen guard skipped): %s" % ("BLINKED to its post (nav agent re-seeded, steering reset)" if blink else "stood down — the GOAP Idle floor walks it back to _spawn_position"))
		return out
	out.append("REFUSED — return_home only acts on an eligible NPC:")
	var cutscene: Variant = npc.get(&"_cutscene_control")
	if cutscene is bool and bool(cutscene):
		out.append("  it is under cutscene control (`npc walkto|freeze` / freezeai) — `npc release` first")
	if not _alive(npc):
		out.append("  it is dead")
	if npc.has_method(&"is_following") and bool(npc.call(&"is_following")):
		out.append("  it is a recruited companion (its home is you)")
	var vip: Variant = npc.get(&"_guarding")
	if vip != null and is_instance_valid(vip):
		out.append("  it is bodyguarding someone")
	# The two remaining _eligible() gates (npc_home_return.gd): a Talkable walk-up in progress, and an open
	# conversation anywhere (DialogueManager.is_engaged() — the tree is normally paused then, but the console runs
	# ALWAYS, so this IS reachable from here).
	var talk: Variant = npc.get(&"_talk")
	# is_instance_valid FIRST: `is` on a freed instance is a hard error, and _talk is a cached child handle.
	if talk != null and is_instance_valid(talk) and talk.has_method(&"is_approaching") and bool(talk.call(&"is_approaching")):
		out.append("  it is mid walk-up to a conversation (Talkable approach) — let it arrive or leave the talk range")
	if DialogueManager.is_engaged():
		out.append("  a dialogue is open (DialogueManager.is_engaged) — the leash never moves anyone mid-conversation")
	var home2: Object = npc.get(&"_home_return")
	if home2 == null or not is_instance_valid(home2):
		out.append("  no NpcHomeReturn child on this NPC")
	elif not _bool_of(home2.get(&"enabled")):
		out.append("  its NpcHomeReturn is disabled")
	if out.size() == 1:
		out.append("  (no gate visible from here — off-tree host, or a refusal inside return_home itself)")
	return out


## panic: break_and_flee — flip threat_response to FLEE + the "forget this!" bark. ⭐ONE-WAY within a life
## (npc.gd:1867-1870): nothing sets FIGHT back except NpcPool reuse restoring _pre_panic_threat_response, or a
## level reload. Say so, every time.
static func _npc_panic(npc: Node) -> PackedStringArray:
	if not _alive(npc):
		return _one("dead")
	if not npc.has_method(&"break_and_flee"):
		return _one("no break_and_flee() on this node")
	if npc.has_method(&"is_fleeing") and bool(npc.call(&"is_fleeing")):
		return _one("already fleeing (threat_response FLEE) — break_and_flee is re-entrant-safe and changed nothing")
	npc.call(&"break_and_flee")
	var out := PackedStringArray()
	out.append("threat_response FIGHT -> FLEE, flee bark played — the Survive goal now wins while it notices a threat (`brain` shows it)")
	out.append("! ONE-WAY for this life: nothing sets FIGHT back except pool reuse or a level reload")
	return out


## sight [r]: with no value, READ both knobs; with one, WRITE BOTH — the copied-once trap: NpcTargeting acquires by
## host.sight_range (npc_targeting.gd:31, with the ×retain hysteresis) while Perception.can_see uses ITS OWN
## sight_range copied at build (npc.gd:1977). Writing one alone moves the pick radius or the cone, never both.
static func _npc_sight(npc: Node, value: float) -> PackedStringArray:
	var perception: Object = npc.get(&"_perception")
	var has_perception := perception != null and is_instance_valid(perception)
	var npc_range := _float_of(npc.get(&"sight_range"))
	var per_range := _float_of(perception.get(&"sight_range")) if has_perception else NAN
	var out := PackedStringArray()
	if is_nan(value):
		out.append("sight_range: NPC (targeting pick radius) %.1f m   Perception (see cone) %s" % [npc_range, ("%.1f m" % per_range) if has_perception else "- (no Perception child)"])
		if has_perception and not is_equal_approx(npc_range, per_range):
			out.append("! the two knobs DIFFER — a live edit of one never reaches the other; `npc sight <r>` writes both")
		out.append("pass a value to set both: `npc sight 12`")
		return out
	var r := maxf(0.0, value)
	npc.set(&"sight_range", r)
	if has_perception:
		perception.set(&"sight_range", r)
	out.append("sight_range %.1f -> %.1f on the NPC (targeting) %s" % [npc_range, r, ("and %.1f -> %.1f on Perception (cone)" % [per_range, r]) if has_perception else "(no Perception child to mirror it onto)"])
	out.append("acquire radius = r; an already-held target is retained to the hysteresis multiple of r; the FOV cone and LOS are unchanged")
	out.append("live-only: the profile is not re-applied at runtime, so this holds until pool reuse or a reload")
	return out


## rebrain: rebuild the GOAP library from the NPC's CURRENT goap_profile + re-stamp the copied-once Perception
## fields. Both are DEAD KNOBS at runtime otherwise: priorities/costs are copied into GoapGoal/GoapAction at build
## (goap_library.gd build_goals/build_actions) and the Perception copies happen once in _build_perception — so a
## remote-inspector edit of goap_profile / sight_range / fov does nothing until this runs. setup() mid-plan MUST be
## followed by reset_for_reuse(): the old plan would keep stepping stale action objects from the previous library.
static func _npc_rebrain(npc: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var executor: Object = npc.get(&"_executor")
	if executor == null or not is_instance_valid(executor) or not executor.has_method(&"setup"):
		out.append("no _executor (or no setup()) on this NPC — the GOAP library was not rebuilt")
	elif not npc.has_method(&"_build_goap_actions") or not npc.has_method(&"_build_goap_goals"):
		out.append("NPC has no _build_goap_actions/_build_goap_goals — API drift; the GOAP library was not rebuilt")
	else:
		var actions: Variant = npc.call(&"_build_goap_actions")
		var goals: Variant = npc.call(&"_build_goap_goals")
		executor.call(&"setup", actions, goals)
		if executor.has_method(&"reset_for_reuse"):
			executor.call(&"reset_for_reuse")  # drop the old plan: its action objects belong to the previous library
		var goal_bits := PackedStringArray()
		if goals is Array:
			var goal_list: Array = goals
			for g in goal_list:
				if g != null and is_instance_valid(g):
					goal_bits.append("%s %.2f" % [_name_of(g), _float_of(g.get(&"base_priority"))])
		var action_bits := PackedStringArray()
		if actions is Array:
			var action_list: Array = actions
			for a in action_list:
				if a != null and is_instance_valid(a):
					action_bits.append("%s %.1f" % [_name_of(a), _float_of(a.get(&"base_cost"))])
		out.append("GOAP library rebuilt from goap_profile — goals (base prio): %s" % (", ".join(goal_bits) if not goal_bits.is_empty() else "none"))
		out.append("  actions (base cost): %s" % (", ".join(action_bits) if not action_bits.is_empty() else "none"))
		out.append("  plan dropped (reset_for_reuse) — the next think tick replans from fresh facts")
	var perception: Object = npc.get(&"_perception")
	if perception == null or not is_instance_valid(perception):
		out.append("no Perception child — nothing to re-stamp")
	else:
		var stamped := PackedStringArray()
		for field: StringName in PERCEPTION_COPIED_ONCE:
			var v: Variant = npc.get(field)
			if v == null:
				continue
			perception.set(field, v)
			stamped.append(String(field))
		out.append("Perception re-stamped from the NPC's live exports: %s" % ", ".join(stamped))
	return out


## `notarget [on|off]` — GHOST MODE: no NPC can acquire, see or hear you, but the AI keeps RUNNING. The gap this
## fills: `freezeai` suspends perception+GOAP+locomotion entirely, `peace` cannot pacify a predisposed hostile
## (raiders re-acquire within retarget_interval) and `killall` removes the cast — so an idle brain (wander,
## schedule, home-return leash, NavLink stairs, pacing on props) could only ever be watched from far away or frozen.
##
## TWO writes, both needed:
##   1. player.set_meta(NOTARGET_META) — read FIRST by NPC._treats_as_enemy (npc.gd), THE predicate NpcTargeting
##      acquires/keeps by AND the per-frame Perception.is_hostile writer, so every held ghost target drops next
##      tick and can_see()/can_hear() read false with no target.
##   2. bank-and-ZERO the player's noise exports (noise_move_per_speed / noise_gunfire_radius, player.gd:303/305,
##      consumed by noise_emitter.gd:24/33) — the ambient &"noise" channel scan (npc_distraction.gd:114
##      _loudest_noise -> investigate_point) is gated on is_hostile() (npc.gd:2987), NOT on the target, so with
##      the meta alone your footsteps would still pull hostiles into INVESTIGATING at your feet.
## ⭐is_hostile_to(player) is deliberately left TRUE (npc.gd:1089): shooting a ghost still provoke()s and sours the
## faction — "provoked but blind". Groups.PLAYER membership is NOT touched (kill-XP, HUD, AiLod all key on it).
static func _cmd_notarget(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var player := _player(ctx)
	if player == null:
		return _one("no player to ghost")
	var tree := _tree(ctx)
	var state := _state(ctx)
	var current := player.has_meta(NOTARGET_META)
	var on := bool(DebugCommandsScript.toggle_value("" if args.is_empty() else args[0], current))
	var out := PackedStringArray()

	if not on:
		# "Already off" only when NOTHING is left to undo: no meta AND neither bank key (a Player stub with only one
		# of the two exports banks only that one, so test both — an orphaned zeroed export must still be restorable).
		if not current and not state.has(STATE_NOTARGET_NOISE_MOVE) and not state.has(STATE_NOTARGET_NOISE_GUN):
			return _one("notarget was already OFF")
		if current:
			player.remove_meta(NOTARGET_META)
		var restored := PackedStringArray()
		if state.has(STATE_NOTARGET_NOISE_MOVE):
			player.set(&"noise_move_per_speed", float(state[STATE_NOTARGET_NOISE_MOVE]))
			restored.append("noise_move_per_speed %.2f" % float(state[STATE_NOTARGET_NOISE_MOVE]))
			state.erase(STATE_NOTARGET_NOISE_MOVE)
		if state.has(STATE_NOTARGET_NOISE_GUN):
			player.set(&"noise_gunfire_radius", float(state[STATE_NOTARGET_NOISE_GUN]))
			restored.append("noise_gunfire_radius %.1f" % float(state[STATE_NOTARGET_NOISE_GUN]))
			state.erase(STATE_NOTARGET_NOISE_GUN)
		out.append("notarget OFF — visible and audible again%s" % ((" (restored " + ", ".join(restored) + ")") if not restored.is_empty() else ""))
		if restored.is_empty():
			# The meta was on the body but the bank is gone: a console freed while the Player survived (a remote-inspector
			# delete / reparent) took ctx[&"state"] with it. Say so — a silent zero would quietly change stealth balance.
			out.append("! no banked noise exports to restore (the bank died with an earlier console) — noise_move_per_speed / noise_gunfire_radius stay where they are until a reload")
		out.append("hostiles inside sight_range re-acquire you within ~%.1f s (the usual proximity pick, no LOS gate) and start DETECTING" % _retarget_interval())
		return out

	if not current:
		player.set_meta(NOTARGET_META, true)
	# Bank the AUTHORED pair exactly once (a repeated `notarget on` must not bank the zero it already wrote), and
	# only when the export actually exists on this Player — a stub/older player degrades to "meta only" + a note.
	var banked := PackedStringArray()
	var move_v: Variant = player.get(&"noise_move_per_speed")
	if not state.has(STATE_NOTARGET_NOISE_MOVE) and (move_v is float or move_v is int):
		state[STATE_NOTARGET_NOISE_MOVE] = float(move_v)
		player.set(&"noise_move_per_speed", 0.0)
		banked.append("noise_move_per_speed %.2f -> 0" % float(move_v))
	var gun_v: Variant = player.get(&"noise_gunfire_radius")
	if not state.has(STATE_NOTARGET_NOISE_GUN) and (gun_v is float or gun_v is int):
		state[STATE_NOTARGET_NOISE_GUN] = float(gun_v)
		player.set(&"noise_gunfire_radius", 0.0)
		banked.append("noise_gunfire_radius %.1f -> 0" % float(gun_v))

	# How many bodies currently hold you — they all let go on their next retarget tick.
	var holders := 0
	var guard_present := true
	var npc_seen := false
	if tree != null:
		for n in tree.get_nodes_in_group(GroupsScript.NPC):
			if not is_instance_valid(n):
				continue
			if not npc_seen:
				npc_seen = true
				# The whole command hinges on npc.gd's DEBUG_NOTARGET_META guard, which is ADDITIVE and lands beside
				# this file. Read the constant map off a LIVE NPC's script (already loaded, no extra parse): if the
				# const is missing, the meta is set but NOTHING reads it — say so instead of promising a ghost.
				# Walk the BASE chain too: get_script_constant_map() is per-script, not inherited, so a body running
				# a subclass of npc.gd (none ship today) would otherwise read as "unguarded" and print a false alarm.
				guard_present = _script_chain_has_const(n.get_script() as GDScript, "DEBUG_NOTARGET_META")
			var held: Variant = n.get(&"_target")
			if held != null and is_instance_valid(held) and held == player:
				holders += 1

	out.append("notarget %s — you are a GHOST: no NPC can acquire, see or hear you (meta \"%s\" on the player; NPC._treats_as_enemy returns false first)" % ["ON" if not current else "still ON", String(NOTARGET_META)])
	if not guard_present:
		out.append("! npc.gd carries no DEBUG_NOTARGET_META guard — the meta is SET but nothing reads it; the ghost seam is not wired (add the first-line check in NPC._treats_as_enemy)")
	if holders > 0:
		# _should_immediately_retarget() (npc.gd _physics_process, before the branch split) fires the same-frame
		# re-acquire for a HELD target that stopped being an enemy — so the drop is the very next think tick, not the
		# retarget_interval throttle (that throttle only paces NEW acquisitions; a distant UNAWARE body thinks on the
		# AI-LOD cadence, so "next tick" can still be ~0.25 s away).
		out.append("%d NPC(s) hold you as _target right now — each drops it on its very next think tick (a held target that stops being an enemy re-acquires same-frame, no %.1f s throttle) and its perception falls to UNAWARE" % [holders, _retarget_interval()])
	if banked.is_empty():
		out.append("noise exports: %s" % ("already zeroed by an earlier `notarget on`" if state.has(STATE_NOTARGET_NOISE_MOVE) else "NOT found on this Player (noise_move_per_speed / noise_gunfire_radius) — footsteps and gunfire may still pull hostiles into INVESTIGATING"))
	else:
		out.append("footsteps + gunfire silenced (%s) so the &\"noise\" scan cannot pull hostiles into INVESTIGATING either; a spike already in flight decays out over its usual ~0.6 s" % ", ".join(banked))
	# The damage hook (npc.gd _on_damaged_by) locks the attacker by is_hostile_to — NOT _treats_as_enemy — and
	# alert_to()s its position. But the retarget check runs BEFORE the has-target branch every tick, so that lock is
	# dropped (same-frame re-acquire) before the body ever acts on it: the no-target tick then forget()s the stale
	# ALERTED outright (default settings) or, with hearing_initiates / body_discovery on, winds it down through sense()
	# as an investigation of your last spot. Either way it never faces, charges or fires at the ghost.
	out.append("! provoked but blind: shooting one still provoke()s it and sours its faction rep — the hit locks you for ONE tick, then the same-frame re-acquire drops you before it acts (the stale alert is forgotten, or wound down as an investigation if ambient hearing/body-discovery is on). Recruited companions are NOT ghosted; hostiles still fight them.")
	out.append("unlike `freezeai`, the AI keeps running — wander, schedules, home-return, NavLink climbs and NPC-vs-NPC fights all continue. `notarget off` restores; a reload frees the ghosted body anyway.")
	return out


# --- per-NPC helpers -----------------------------------------------------------------------------------------

## "Name (identity_key)  hp x/y" for a command header. identity_key() is the stable NpcData.id-or-display-name.
static func _npc_label(npc: Node) -> String:
	var label := String(npc.name)
	if npc.has_method(&"identity_key"):
		var key := String(npc.call(&"identity_key"))
		if key != "" and key != label:
			label += " (%s)" % key
	if npc.has_method(&"is_alive"):
		label += "  hp %.0f/%.0f" % [_float_of(npc.get(&"hp")), _float_of(npc.get(&"max_hp"))]
	return label


## is_alive() gate — take_damage early-returns on the dead latch and hp can be <= 0 while the body is still grouped.
static func _alive(n: Node) -> bool:
	return n != null and is_instance_valid(n) and n.has_method(&"is_alive") and bool(n.call(&"is_alive"))


static func _retarget_interval() -> float:
	var npc_ai: Object = GameSettings.get(&"npc_ai")
	if npc_ai == null or not is_instance_valid(npc_ai):
		return 0.5
	return _float_of(npc_ai.get(&"retarget_interval"), 0.5)


## GoapGoal.priority(ws) through a Variant handle; -INF for anything that is not a goal so it sorts last.
static func _goal_priority(g: Variant, ws: Variant) -> float:
	if g == null or not is_instance_valid(g) or not g.has_method(&"priority"):
		return -INF
	return float(g.call(&"priority", ws))


static func _plan_text(plan: Array) -> String:
	var names := PackedStringArray()
	for a in plan:
		names.append(_name_of(a) if a != null and is_instance_valid(a) else "?")
	return " -> ".join(names)


static func _plan_cost(plan: Array, ws: Variant) -> float:
	var total := 0.0
	for a in plan:
		if a != null and is_instance_valid(a) and a.has_method(&"cost"):
			total += float(a.call(&"cost", ws))
	return total


## Why plan() came back empty for an UNSATISFIED goal: for each desired fact, the actions whose effects would set
## it and the preconditions of theirs that do not hold in the facts. Today every goal is single-step (one action
## sets its sentinel), so this names the exact fact that gates the behaviour.
static func _why_no_plan(goal: Object, actions: Array, ws: Variant) -> String:
	var desired_v: Variant = goal.get(&"desired_state")
	var facts_v: Variant = ws.get(&"facts")
	var desired: Dictionary = desired_v if desired_v is Dictionary else {}
	var facts: Dictionary = facts_v if facts_v is Dictionary else {}
	var bits := PackedStringArray()
	for k in desired:
		var producers := 0
		for a in actions:
			if a == null or not is_instance_valid(a):
				continue
			var eff_v: Variant = a.get(&"effects")
			var eff: Dictionary = eff_v if eff_v is Dictionary else {}
			if not eff.has(k) or eff[k] != desired[k]:
				continue
			producers += 1
			var pre_v: Variant = a.get(&"preconditions")
			var pre: Dictionary = pre_v if pre_v is Dictionary else {}
			var missing := PackedStringArray()
			for pk in pre:
				if facts.get(pk) != pre[pk]:
					missing.append("%s=%s (is %s)" % [String(pk), str(pre[pk]), str(facts.get(pk, "unset"))])
			if not missing.is_empty():
				bits.append("%s needs %s" % [_name_of(a), ", ".join(missing)])
		if producers == 0:
			bits.append("no action produces %s=%s" % [String(k), str(desired[k])])
	return "; ".join(bits) if not bits.is_empty() else "unreachable within the iteration cap"


## "{a=true, b=false}" for a facts / preconditions / effects Dictionary, keys sorted so two dumps line up.
static func _facts_text(d: Dictionary) -> String:
	if d.is_empty():
		return "{}"
	var keys := PackedStringArray()
	for k in d.keys():
		keys.append(String(k))
	keys.sort()
	var bits := PackedStringArray()
	for k in keys:
		# String and StringName are the SAME Dictionary key in Godot 4, so the String we sorted by finds the
		# StringName-keyed fact.
		var v: Variant = d.get(k)
		bits.append("%s=%s" % [k, ("%.2f" % float(v)) if v is float else str(v)])
	return "{" + ", ".join(bits) + "}"


## `name` off a GoapGoal / GoapAction handle (StringName), "?" when absent.
static func _name_of(o: Variant) -> String:
	if o == null or not is_instance_valid(o):
		return "?"
	var n: Variant = o.get(&"name")
	return String(n) if n != null else "?"


## if/elif rather than `match`: a pattern must be a constant expression, and an enum reached THROUGH a preloaded
## script const (PerceptionScript.State.X) is a subscript the analyzer need not fold — a comparison always works.
static func _perception_state_text(state: int) -> String:
	if state == PerceptionScript.State.UNAWARE:
		return "UNAWARE"
	if state == PerceptionScript.State.DETECTING:
		return "DETECTING"
	if state == PerceptionScript.State.ALERTED:
		return "ALERTED"
	if state == PerceptionScript.State.INVESTIGATING:
		return "INVESTIGATING"
	return "?"


static func _disposition_text(kind: int) -> String:
	if kind == DispositionScript.Kind.HOSTILE:
		return "HOSTILE"
	if kind == DispositionScript.Kind.NEUTRAL:
		return "NEUTRAL"
	if kind == DispositionScript.Kind.FRIENDLY:
		return "FRIENDLY"
	return "?"


## bool of a Variant that may be null (Object.get() on a missing property) — never `bool(null)`.
static func _bool_of(value: Variant) -> bool:
	return value is bool and bool(value)


## True when `script` or ANY script it extends declares a constant named `const_name`. get_script_constant_map() is
## per-script (a subclass's map does not include its base's consts), so a guard declared on npc.gd must be looked
## for up the get_base_script() chain. Null-safe: no script -> false.
static func _script_chain_has_const(script: GDScript, const_name: String) -> bool:
	var s := script
	var depth := 0
	while s != null and depth < 16:  # a script chain is a handful deep; the cap only guards a malformed cycle
		if s.get_script_constant_map().has(const_name):
			return true
		s = s.get_base_script() as GDScript
		depth += 1
	return false


# =============================================================================================================
# STORY
# =============================================================================================================

## Read / set / ERASE a story flag.
##
## Two traps drive the shape of this command:
##   - set_flag(name, false) does NOT unset. It stores false, still autosaves, and has_flag() still returns true;
##     notify_flag_set is gated on a TRUTHY value so nothing downstream is driven. `clear` is the real unset, and
##     it must poke flags.erase() (there is no public API) plus an explicit autosave, because erase bypasses both.
##   - a TRUTHY set fans out: notify_flag_set -> FLAG objectives advance -> a quest can auto-complete (granting
##     money/xp/items/reputation) -> its next_quest chain starts, and any quest with expire_on_flag FAILS.
static func _cmd_flag(args: PackedStringArray) -> PackedStringArray:
	var flag_name := args[0].strip_edges()
	if flag_name == "":
		return _one("flag name is blank")
	var out := PackedStringArray()

	if args.size() < 2:
		if not GameState.has_flag(flag_name):
			out.append("%s: not set" % flag_name)
			return out
		out.append("%s = %s" % [flag_name, str(GameState.get_flag(flag_name))])
		out.append("(as bool: %s)" % str(GameState.get_flag_bool(flag_name)))
		return out

	var raw := args[1].strip_edges()
	var lower := raw.to_lower()
	if lower == "clear":
		# GameState.flags is keyed by String (set_flag coerces a StringName at the boundary), so erase with a String.
		if not GameState.flags.has(flag_name):
			return _one("%s was not set — nothing to erase" % flag_name)
		GameState.flags.erase(flag_name)
		GameState.autosave_world_state()  # erase() bypasses the write set_flag would have queued
		out.append("%s ERASED (has_flag is now false)" % flag_name)
		out.append("! nothing was notified and nothing repaints — a quest already advanced by this flag stays advanced.")
		return out

	var value: Variant = raw
	if ["true", "on", "1", "yes"].has(lower):
		value = true
	elif ["false", "off", "0", "no"].has(lower):
		value = false
	elif raw.is_valid_int():
		value = raw.to_int()
	elif raw.is_valid_float():
		value = raw.to_float()

	GameState.set_flag(flag_name, value)
	out.append("%s = %s" % [flag_name, str(value)])
	# ⭐The fan-out predicate MUST be set_flag's own (`if value:` — Variant booleanize, GameState.gd:1172), NOT
	# GameState.as_bool(). as_bool deliberately reports FALSE for anything that is not a bool/int/float, so a
	# `flag mytag hello` would be announced as inert while set_flag had in fact fired notify_flag_set: a non-empty
	# String (or Array / Dictionary) booleanizes TRUE. Reporting the wrong half here is worse than saying nothing,
	# because it tells you no quest moved when one just did.
	if value:
		out.append("! truthy: FLAG objectives advanced, a quest may have auto-completed (rewards granted, next_quest started), and any quest with expire_on_flag FAILED.")
	else:
		out.append("! a falsy value does NOT unset the flag — has_flag() is still true and nothing was notified. Use `flag %s clear` to erase the key." % flag_name)
	out.append("this queued a full-profile write over your Continue save.")
	return out


static func _cmd_flags() -> PackedStringArray:
	var out := PackedStringArray()
	var keys := PackedStringArray()
	for k in GameState.flags.keys():
		keys.append(String(k))
	keys.sort()
	if keys.is_empty():
		out.append("no story flags set this run")
	else:
		for k in keys:
			out.append("  %-44s %s" % [k, str(GameState.flags[k])])
		out.append("%d flag(s) set" % keys.size())
	# The shipped game authors essentially zero story flags — a content scan would come back empty, so name the one
	# flag that actually exists in code.
	out.append("known in code: %s" % String(GameState.HOLSTER_FORGIVENESS_TUTORIAL_SEEN_FLAG))
	return out


## Start / complete / fail / inspect / advance a quest, keyed by Quest.id — which is NOT the filename
## (resources/quests/recover_the_package.tres declares id "recover_package"). The registry row is
## [VERB, QUEST, TEXT, NUMBER] min 2, so `args` is 2..4 long: slots 2 and 3 (objective id, amount) exist only for
## `advance` and are IGNORED by the other four verbs, so `quest show x y 3` is not an arity error.
static func _cmd_quest(args: PackedStringArray) -> PackedStringArray:
	var verb := args[0].to_lower()
	var wanted := args[1]
	var path := _lookup(_quests(), wanted)
	if path == "":
		return _one("no quest with id \"%s\" — try: %s" % [wanted, ", ".join(_sorted_keys(_quests()))])
	# Typed as Quest so it can be handed straight to QuestTracker.start_quest (which takes the RESOURCE, not an id)
	# without an unsafe-argument downcast — and so a .tres that is NOT a Quest comes back null instead of erroring
	# deep inside the tracker.
	var quest := load(path) as Quest
	if quest == null:
		return _one("%s did not load as a Quest" % path)
	var qid := StringName(String(quest.get("id")))

	match verb:
		"show":
			return _quest_report(quest, qid, path)
		"start":
			# start_quest has SIX silent no-op paths. Report WHICH one hit, or the command just looks broken.
			if qid == &"":
				return _one("%s has a BLANK id — start_quest refuses it" % path.get_file())
			if QuestTracker.is_quest_active(qid):
				return _one("%s is already ACTIVE — start_quest no-ops" % qid)
			if QuestTracker.is_quest_completed(qid):
				return _one("%s is already COMPLETED — start_quest no-ops" % qid)
			if QuestTracker.is_quest_failed(qid):
				return _one("%s is FAILED — closed forever. start_quest refuses it and there is no un-fail; only QuestTracker.reset() reopens it." % qid)
			var prereq := StringName(String(quest.get("prereq_quest_id")))
			if prereq != &"" and not QuestTracker.is_quest_completed(prereq):
				return _one("%s needs prereq \"%s\" completed first — start_quest no-ops" % [qid, prereq])
			QuestTracker.start_quest(quest)
			var out := PackedStringArray()
			if QuestTracker.is_quest_active(qid):
				out.append("started %s (\"%s\")" % [qid, String(quest.get("title"))])
			else:
				out.append("start_quest ran but %s is still not active — a no-op path this command did not anticipate" % qid)
			out.append("FLAG objectives whose flag was already set were back-filled; a full-profile save was queued.")
			return out
		"complete":
			if not QuestTracker.is_quest_active(qid):
				return _one("%s is not ACTIVE — complete_quest requires an active quest (state: %s)" % [qid, _quest_state(qid)])
			QuestTracker.complete_quest(qid)
			var out2 := PackedStringArray()
			out2.append("completed %s" % qid)
			out2.append(_reward_text(quest))
			out2.append("! rewards were granted BEFORE quest_completed fired — and grant silently gives NOTHING with no live player (a main-menu context).")
			if quest.get("next_quest") != null:
				out2.append("next_quest chained automatically.")
			return out2
		"fail":
			if not QuestTracker.is_quest_active(qid):
				return _one("%s is not ACTIVE — fail_quest requires an active quest (state: %s)" % [qid, _quest_state(qid)])
			QuestTracker.fail_quest(qid)
			var out3 := PackedStringArray()
			out3.append("failed %s — no rewards, no chaining" % qid)
			out3.append("! a failed quest can NEVER be restarted. Only QuestTracker.reset() (which wipes the whole journal) gets it back.")
			return out3
		"advance":
			return _quest_advance(quest, qid, args)
	return _one("unknown quest action \"%s\"" % verb)


## `quest advance <quest> [objective] [n]` — tick ONE objective through QuestTracker.advance_objective, the real
## path (objective_advanced -> HUD tracker + compass/minimap marker sync -> auto_complete -> complete_quest ->
## rewards -> next_quest). `complete` skips all of that, so this is the only way to stand a quest at KILL 3/5
## without killing things.
##
## Three silent no-ops in advance_objective are turned into lines here: quest not ACTIVE (:111), unknown objective
## id (:116-117), and — not a no-op but invisible — the mini() clamp to required_count (:120) that makes a tick on a
## finished objective change nothing while STILL firing the signal and the cascade check. Progress is keyed by
## String(objective_id) inside the tracker; we only ever go through its API, never poke _quests_active.
##
## Objective ids are PER-QUEST (quest.objectives[].id, blank ones are unkeyed), so with no id given the objectives
## are LISTED with live progress and nothing is ticked. The list is taken off the tracker's OWN Quest instance
## (active_quest) rather than the disk copy: load() caches, so they are normally the same resource, but the ids
## advance_objective will actually match are the tracker's — that instance is the truth.
static func _quest_advance(quest: Quest, qid: StringName, args: PackedStringArray) -> PackedStringArray:
	var live := QuestTracker.active_quest(qid)
	if live != null:
		quest = live
	var oid_raw := args[2].strip_edges() if args.size() > 2 else ""
	var active := QuestTracker.is_quest_active(qid)
	var out := PackedStringArray()

	if oid_raw == "":
		if active:
			out.append("quest advance %s needs an objective id — objectives (progress/required):" % qid)
		else:
			out.append("%s is not ACTIVE (state: %s) — advance_objective silently no-ops on it; `quest start %s` first. Its objectives:" % [qid, _quest_state(qid), qid])
		out.append_array(_objective_lines(quest, qid))
		out.append("usage: quest advance %s <objective id> [amount]   (amount defaults to 1; a negative amount un-ticks)" % qid)
		return out

	if not active:
		return _one("%s is not ACTIVE (state: %s) — advance_objective returns before touching anything; `quest start %s` first" % [qid, _quest_state(qid), qid])

	var obj := _find_objective(quest, oid_raw)
	if obj == null:
		out.append("no objective \"%s\" on %s (matched exactly, then case-insensitively) — advance_objective would silently no-op. Objectives:" % [oid_raw, qid])
		out.append_array(_objective_lines(quest, qid))
		return out
	var oid := StringName(String(obj.get("id")))
	if oid == &"":
		return _one("that objective has a BLANK id — start_quest never seeded progress for it and advance_objective cannot address it (author an id on the QuestObjective)")

	var amount := 1
	if args.size() > 3:
		amount = int(args[3].to_float())
	if amount == 0:
		return _one("amount 0 ticks nothing (it would still fire objective_advanced and the auto-complete check for no change) — pass a positive count, or a negative one to un-tick")
	var required := _int_of(obj.get("required_count"), 1)
	var before := QuestTracker.objective_progress(qid, oid)
	# The tracker clamps only the TOP (mini to required_count): a negative amount past zero would leave a NEGATIVE
	# count in the save. Floor it here and say so.
	var floored := false
	if amount < 0 and before + amount < 0:
		amount = -before
		floored = true
	if amount == 0:
		return _one("%s/%s is already at 0 — nothing to un-tick" % [qid, oid])
	var active_before := _active_id_set()

	QuestTracker.advance_objective(qid, oid, amount)

	if oid_raw != String(oid):
		out.append("(\"%s\" resolved case-insensitively to the authored id \"%s\")" % [oid_raw, oid])
	if floored:
		out.append("(amount floored to %d so the count cannot go below 0 — the tracker only clamps the top)" % amount)
	# It was ACTIVE going in (guarded above), so "completed now" can only mean this very call cascaded.
	if QuestTracker.is_quest_completed(qid):
		# The whole cascade fired inside that one call: mini() clamp -> objective_advanced -> _all_required_done ->
		# complete_quest -> _grant_quest_rewards -> quest_completed -> start_quest(next_quest).
		out.append("%s/%s %d -> DONE (%d required) and that was the LAST open required objective: auto_complete cascaded — %s is COMPLETED" % [qid, oid, before, required, qid])
		out.append("  " + _reward_text(quest) + " — granted NOW (nothing is granted with no live player, e.g. a main-menu context)")
		var next_v: Variant = quest.get("next_quest")
		if next_v != null and next_v is Resource:
			var next_id := StringName(String((next_v as Resource).get("id")))
			if next_id != &"" and QuestTracker.is_quest_active(next_id) and not active_before.has(String(next_id)):
				out.append("  next_quest %s STARTED (its FLAG objectives whose flag is already set were back-filled)" % next_id)
			elif next_id != &"" and active_before.has(String(next_id)):
				out.append("  next_quest %s was ALREADY active — start_quest no-oped on it" % next_id)
			elif next_id != &"" and QuestTracker.is_quest_completed(next_id):
				# Two histories read the same here: it was completed before (start_quest refused it), or it STARTED and
				# its back-filled FLAG objectives completed it inside this very cascade (rewards granted, its own
				# next_quest chained). _new_active_since below names anything that chained past it.
				out.append("  next_quest %s is COMPLETED — either it already was (start_quest no-oped), or it started and its back-filled FLAG objectives finished it in this same cascade (its rewards granted too)" % next_id)
			else:
				out.append("  next_quest %s did NOT start (failed already, blank id, or an unmet prereq — start_quest's silent no-ops)" % next_id)
	else:
		var after := QuestTracker.objective_progress(qid, oid)
		var done := QuestTracker.is_objective_done(qid, oid)
		out.append("%s/%s %d -> %d / %d%s" % [qid, oid, before, after, required, "  DONE" if done else ""])
		if after == before:
			out.append("  no change: already at required_count — mini() clamped it, but objective_advanced STILL fired and the auto-complete check ran")
		if done:
			var open := _open_required_objectives(quest, qid)
			if not _bool_of(quest.get("auto_complete")):
				if open.is_empty():
					out.append("  every required objective is met but auto_complete is OFF — `quest complete %s` is the explicit turn-in" % qid)
			elif not open.is_empty():
				out.append("  still open (required): %s — the quest completes when the last of these is met" % ", ".join(open))
	out.append("objective_advanced fired (HUD quest tracker + compass/minimap markers repaint); a coalesced full-profile write was queued over your Continue save (it also nulls a pending in-memory WorldSnapshot).")
	var started := _new_active_since(active_before)
	if not started.is_empty():
		out.append("newly ACTIVE after the cascade: %s" % ", ".join(started))
	return out


## Per-objective lines for `quest advance` (id, type word, target, optional, and live progress while ACTIVE).
## Read duck-typed off the Resource like _quest_report, so a partial/malformed objective degrades to a line.
static func _objective_lines(quest: Resource, qid: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	var objectives_v: Variant = quest.get("objectives")
	if not (objectives_v is Array):
		out.append("  (no objectives array on this quest)")
		return out
	var objectives: Array = objectives_v
	var active := QuestTracker.is_quest_active(qid)
	var listed := 0
	for o in objectives:
		var obj := o as Resource
		if obj == null:
			continue
		var oid := StringName(String(obj.get("id")))
		var line := "  %-18s %-10s target \"%s\"" % [
			(String(oid) if oid != &"" else "(blank id!)"), _objective_type_text(_int_of(obj.get("type"), -1)), String(obj.get("target_id"))]
		if _bool_of(obj.get("optional")):
			line += " (optional)"
		if active and oid != &"":
			# objective_progress reads 0 for a NON-active quest and is_objective_done reads true for EVERY objective
			# of a completed one — both only mean something while the quest is active (same caveat as `quest show`).
			line += "   %d/%d%s" % [
				QuestTracker.objective_progress(qid, oid), _int_of(obj.get("required_count"), 1),
				"  DONE" if QuestTracker.is_objective_done(qid, oid) else ""]
		out.append(line)
		listed += 1
	if listed == 0:
		out.append("  (no objectives authored)")
	return out


## The objective whose id is `wanted` — exact first, then case-insensitive (typing convenience; the RESOLVED
## authored id is what gets sent, and the caller says so). Null when nothing matches.
static func _find_objective(quest: Resource, wanted: String) -> Resource:
	var objectives_v: Variant = quest.get("objectives")
	if not (objectives_v is Array):
		return null
	var objectives: Array = objectives_v
	for o in objectives:
		var obj := o as Resource
		if obj != null and String(obj.get("id")) == wanted:
			return obj
	var lower := wanted.to_lower()
	for o in objectives:
		var obj := o as Resource
		if obj != null and String(obj.get("id")).to_lower() == lower:
			return obj
	return null


## Ids of the REQUIRED (non-optional) objectives of an ACTIVE quest that are not yet done — what still gates
## auto-complete. Empty for a non-active quest.
static func _open_required_objectives(quest: Resource, qid: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	if not QuestTracker.is_quest_active(qid):
		return out
	var objectives_v: Variant = quest.get("objectives")
	if not (objectives_v is Array):
		return out
	var objectives: Array = objectives_v
	for o in objectives:
		var obj := o as Resource
		if obj == null or _bool_of(obj.get("optional")):
			continue
		var oid := StringName(String(obj.get("id")))
		if oid != &"" and not QuestTracker.is_objective_done(qid, oid):
			out.append(String(oid))
	return out


## { quest id -> true } of everything active right now — snapshotted BEFORE a cascade so newly chained quests
## (next_quest, and its next_quest if a back-filled FLAG completes it in turn) can be named afterwards.
static func _active_id_set() -> Dictionary:
	var out := {}
	for a in QuestTracker.active_quest_ids():
		out[String(a)] = true
	return out


static func _new_active_since(before: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for a in QuestTracker.active_quest_ids():
		var s := String(a)
		if not before.has(s):
			out.append(s)
	out.sort()
	return out


## if/elif rather than `match`, like _perception_state_text: an enum reached through a class is a subscript the
## analyzer need not fold into a constant pattern — a comparison always works.
static func _objective_type_text(t: int) -> String:
	if t == QuestObjective.Type.KILL:
		return "KILL"
	if t == QuestObjective.Type.TALK:
		return "TALK"
	if t == QuestObjective.Type.PICKUP:
		return "PICKUP"
	if t == QuestObjective.Type.ENTER_AREA:
		return "ENTER_AREA"
	if t == QuestObjective.Type.USE_ITEM:
		return "USE_ITEM"
	if t == QuestObjective.Type.FLAG:
		return "FLAG"
	return "type %d" % t


## `notify <kill|talk|pickup|enter|use> [target] [legacy name]` — fire the SAME QuestTracker hook the game fires
## (npc.gd _on_died -> notify_kill / DialogueManager.start -> notify_talk / CanPickUp -> notify_pickup /
## TriggerVolume -> notify_enter / Player.use_consumable -> notify_use) WITHOUT doing the thing, and report which
## active objectives matched. `quest advance` bypasses matching entirely; the bug class this project actually had is
## the KEY — quests key NpcData.id (the identity key) with the display name as a legacy fallback
## (_advance_objectives_matching), and only a notify-driven test proves an authored target_id will ever match.
##
## With no target, kill/talk take the NPC under the crosshair through the module's picker (_resolve_aimed_npc: the
## crosshair NPC first, else the sticky last `npc` target — labelled) and send its identity_key() as the target
## with its live display_name as the legacy fallback — exactly the pair npc.gd:1420 sends on a real kill. The
## match report mirrors the tracker's own predicate (target_id == target, or == legacy when legacy differs from
## target) rather than diffing counts, because a tick on an already-finished objective changes no count while
## STILL matching (and still cascading).
static func _cmd_notify(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var verb := args[0].strip_edges().to_lower()
	var obj_type := _notify_type_for(verb)
	if obj_type < 0:
		return _one("unknown notify event \"%s\" (kill, talk, pickup, enter, use — registry/actions drift)" % verb)
	var target := args[1].strip_edges() if args.size() > 1 else ""
	var legacy := args[2].strip_edges() if args.size() > 2 else ""
	var pair := verb == "kill" or verb == "talk"
	var out := PackedStringArray()
	# Only notify_kill / notify_talk take a legacy fallback; the registry row is one shape for all five verbs, so a
	# third token on pickup/enter/use is legal to type but NEVER reaches the tracker. It must not reach the match
	# report either — mirroring the tracker's predicate with a legacy the hook never received would print a MATCH
	# for an objective the game did not advance. Blank it here and say so.
	if not pair and legacy != "":
		out.append("(third argument \"%s\" ignored — notify_%s takes one id; only kill/talk have a legacy-name fallback)" % [legacy, verb])
		legacy = ""

	if target == "":
		if not pair:
			var need := "an Item.id (`items` lists them)"
			if verb == "enter":
				need = "an area name (a TriggerVolume's quest_area_id — none ships in any level, so this is the only way to test ENTER_AREA today)"
			return _one("notify %s needs a target: %s" % [verb, need])
		var pick := _resolve_aimed_npc(ctx)
		var err: String = pick[&"error"]
		if err != "":
			return _one("notify %s: %s" % [verb, err])
		var npc: Node = pick[&"npc"]
		if not npc.has_method(&"identity_key"):
			return _one("notify %s: %s has no identity_key() — not an NPC-shaped node" % [verb, String(npc.name)])
		target = String(npc.call(&"identity_key"))
		if legacy == "":
			var dn: Variant = npc.get(&"display_name")
			legacy = String(dn) if dn is String else ""
		out.append("notify %s <- %s%s" % [verb, _npc_label(npc), "   (sticky: your last `npc` target — the crosshair is not on an NPC)" if bool(pick[&"sticky"]) else ""])
		if target == "":
			out.append("notify %s: that NPC's identity_key() is BLANK (no NpcData.id and no display_name) — nothing to send, hook NOT fired" % verb)
			return out

	# Snapshot BEFORE the hook so the cascade (auto-complete -> rewards -> next_quest) can be named afterwards.
	var rows := _objective_rows_of_type(obj_type)
	var active_before := _active_id_set()
	var t_key := StringName(target)
	var l_key := StringName(legacy)
	var source := ""
	match verb:
		"kill":
			QuestTracker.notify_kill(t_key, l_key)
			source = "NPC._on_died fires on a player kill"
		"talk":
			QuestTracker.notify_talk(t_key, l_key)
			source = "DialogueManager.start fires with a named speaker"
		"pickup":
			QuestTracker.notify_pickup(t_key)
			source = "CanPickUp fires on a pickup"
		"enter":
			QuestTracker.notify_enter(t_key)
			source = "TriggerVolume fires with a quest_area_id"
		"use":
			QuestTracker.notify_use(t_key)
			source = "Player.use_consumable fires on use"
	var sent := "\"%s\"" % target
	if pair and legacy != "":
		sent += ", legacy \"%s\"" % legacy
	out.append("QuestTracker.notify_%s(%s) fired — the hook %s" % [verb, sent, source])

	if rows.is_empty():
		out.append("no ACTIVE %s objective exists right now — nothing could match (`quests` lists what is on disk; `quest start <id>` first)" % _objective_type_text(obj_type))
	else:
		var matched := 0
		for r in rows:
			var qid := StringName(String(r["qid"]))
			var oid := StringName(String(r["oid"]))
			var authored := StringName(String(r["target"]))
			var hit_id := authored == t_key
			var hit_legacy := l_key != &"" and l_key != t_key and authored == l_key
			if hit_id or hit_legacy:
				matched += 1
				var after_text := "quest COMPLETED" if QuestTracker.is_quest_completed(qid) else str(QuestTracker.objective_progress(qid, oid))
				out.append("  MATCH %s/%s (target_id \"%s\" via the %s): %d -> %s / %d" % [
					qid, oid, authored, "identity key" if hit_id else "legacy display name", int(r["before"]), after_text, int(r["required"])])
			else:
				out.append("  no match %s/%s: target_id \"%s\" != %s" % [qid, oid, authored, sent])
		if matched == 0:
			out.append("! no active %s objective's target_id matched what was sent — the exact bug class this command exposes: for KILL/TALK author the NpcData.id (or the display name as the legacy fallback), for PICKUP/USE_ITEM the Item.id, for ENTER_AREA the TriggerVolume's quest_area_id" % _objective_type_text(obj_type))
		else:
			out.append("each match ran the full advance cascade: objective_advanced (HUD tracker + markers) -> auto_complete -> rewards (money/xp/items/rep) -> next_quest, and queued a full-profile write over your Continue save (nulling a pending in-memory WorldSnapshot).")
	var started := _new_active_since(active_before)
	if not started.is_empty():
		out.append("newly ACTIVE after the cascade: %s" % ", ".join(started))

	# What did NOT happen — the hook is the whole command.
	match verb:
		"kill":
			out.append("hook only — no NPC died: no XP, bounty, corpse, faction kill_penalty or witness bark (`npc kill` does the real thing).")
		"talk":
			out.append("hook only — DialogueManager.start was NOT called: no speaker freeze, no tree pause, no reveal_name, no cursor change.")
		"enter":
			out.append("hook only — no TriggerVolume fired its other actions (flags, level load, cutscene).")
		_:
			out.append("hook only — no item moved or was consumed.")
	return out


## Every objective of `obj_type` on every ACTIVE quest, with its progress BEFORE a hook fires — the rows the
## tracker's _advance_objectives_matching walks. Read through the tracker's public API only (active_quest_ids /
## active_quest / objective_progress); the id list is a fresh keys() Array, so a cascade erasing from
## _quests_active cannot invalidate this walk.
static func _objective_rows_of_type(obj_type: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for a in QuestTracker.active_quest_ids():
		var qid := StringName(String(a))
		var quest := QuestTracker.active_quest(qid)
		if quest == null:
			continue
		var objectives_v: Variant = quest.get("objectives")
		if not (objectives_v is Array):
			continue
		var objectives: Array = objectives_v
		for o in objectives:
			var obj := o as Resource
			if obj == null or _int_of(obj.get("type"), -1) != obj_type:
				continue
			var oid := StringName(String(obj.get("id")))
			rows.append({
				"qid": String(qid), "oid": String(oid), "target": String(obj.get("target_id")),
				"required": _int_of(obj.get("required_count"), 1), "before": QuestTracker.objective_progress(qid, oid),
			})
	return rows


## notify verb -> QuestObjective.Type, -1 for an unknown word (validate() already restricted the slot, so -1 is
## registry/actions drift). if-chain for the same reason as _objective_type_text.
static func _notify_type_for(verb: String) -> int:
	if verb == "kill":
		return QuestObjective.Type.KILL
	if verb == "talk":
		return QuestObjective.Type.TALK
	if verb == "pickup":
		return QuestObjective.Type.PICKUP
	if verb == "enter":
		return QuestObjective.Type.ENTER_AREA
	if verb == "use":
		return QuestObjective.Type.USE_ITEM
	return -1


## `ledger [all]` — READ-ONLY dump of the live save-ledger state. Three things nothing else shows:
##   1. GameState.world_objects (the additive per-object PROFILE-tier ledger: Door open/locked, consumed pickups,
##      destroyed props) for the current level — every level with `all`;
##   2. GameState._dead_authored (the cross-level authored-NPC death ledger — EXACT-SNAPSHOT tier only, private
##      with no getter and no clear, read via GameState.get(&"…") — underscore is convention here, not access);
##   3. the latches: world_snapshot present?, _world_snapshot_pending, reload_pending(), _world_save_queued.
## Flags the two key-shape traps world_save_id.gd documents: entries on the FRAGILE level|path|pos fallback (no
## save_id — a move/rename silently orphans them) and entries whose level component is BLANK (recorded while
## current_level_path was "" — the code-built LevelData trap). The editor Saves dock reads ON-DISK cfg only and
## the F3 overlay shows account/level/time, so _dead_authored appears nowhere else.
## Never calls consume_world_snapshot() (a destructive one-shot latch) or take_load_warnings() (consume-once, and
## ui.gd already owns it) — every read here is a plain field/getter.
static func _cmd_ledger(args: PackedStringArray) -> PackedStringArray:
	var all := not args.is_empty() and args[0].strip_edges().to_lower() == "all"
	var level := String(GameState.current_level_path)
	var out := PackedStringArray()
	out.append("ledger — current level \"%s\"%s" % [level, "   (BLANK: no level loaded, or a code-built LevelData — this level's buckets are keyed by \"\")" if level == "" else ""])

	# --- 1. world_objects (profile tier) ---
	var wo: Dictionary = GameState.world_objects
	var levels := PackedStringArray()
	if all:
		levels = _sorted_keys(wo)
		var total := 0
		for lvl in levels:
			var b: Variant = wo.get(lvl)
			if b is Dictionary:
				total += (b as Dictionary).size()
		out.append("-- world_objects: %d level bucket(s), %d entries in all   (profile tier: Continue, quicksave and slot files all carry it)" % [levels.size(), total])
		if levels.is_empty():
			out.append("   (empty — nothing has recorded object state this run)")
	else:
		levels.append(level)
	for lvl in levels:
		var bucket_v: Variant = wo.get(lvl)
		if not (bucket_v is Dictionary) or (bucket_v as Dictionary).is_empty():
			out.append("-- world_objects[\"%s\"]: no entries%s" % [lvl, "" if all else "   (profile tier: Continue, quicksave and slot files all carry it; `ledger all` shows other levels)"])
			continue
		var bucket: Dictionary = bucket_v
		out.append("-- world_objects[\"%s\"]: %d entr%s%s" % [lvl, bucket.size(), "y" if bucket.size() == 1 else "ies", "" if all else "   (profile tier: Continue, quicksave and slot files all carry it)"])
		var keys := _sorted_keys(bucket)
		var fragile := 0
		var blank_level := 0
		var shown := 0
		for k in keys:
			if not k.begins_with("id:"):
				fragile += 1
				if k.begins_with("|"):
					blank_level += 1
			if shown < LEDGER_MAX_LINES:
				var st: Variant = bucket.get(k)
				out.append("   %s  ->  %s" % [k, _facts_text(st as Dictionary) if st is Dictionary else str(st)])
				shown += 1
		if keys.size() > shown:
			out.append("   ... %d more" % (keys.size() - shown))
		if fragile > 0:
			out.append("   ! %d on the FRAGILE fallback key (no save_id): moving or renaming that node between saves silently orphans the entry (world_save_id.gd @risk)" % fragile)
		if blank_level > 0:
			out.append("   ! %d recorded with a BLANK level component (current_level_path was \"\" at record time — the code-built LevelData trap); a real level never matches them" % blank_level)

	# --- 2. the cross-level dead-NPC ledger (exact-snapshot tier) ---
	var dead_v: Variant = GameState.get(&"_dead_authored")
	if not (dead_v is Dictionary):
		out.append("-- dead authored NPCs: GameState has no _dead_authored Dictionary (API drift) — nothing to read")
	else:
		var dead: Dictionary = dead_v
		var dlevels := PackedStringArray()
		if all:
			dlevels = _sorted_keys(dead)
			out.append("-- dead authored NPCs (_dead_authored): %d level bucket(s)   (exact-snapshot tier ONLY: session-live, reaches disk only folded into a manual quick/slot save's [world_snapshot]; the profile never carries it; load_level frees the NPCs under these keys on EVERY re-instantiate)" % dlevels.size())
			if dlevels.is_empty():
				out.append("   (empty — no authored NPC has died this session and no snapshot load restored one)")
		else:
			dlevels.append(level)
		for lvl in dlevels:
			var b: Variant = dead.get(lvl)
			if not (b is Dictionary) or (b as Dictionary).is_empty():
				out.append("-- dead authored NPCs [\"%s\"]: none%s" % [lvl, "" if all else "   (exact-snapshot tier ONLY: session-live, folded into a manual quick/slot save; the profile never carries it; load_level frees the NPCs under these keys on every re-instantiate)"])
				continue
			var keys := _sorted_keys(b as Dictionary)
			out.append("-- dead authored NPCs [\"%s\"]: %d%s" % [lvl, keys.size(), "" if all else "   (exact-snapshot tier ONLY: session-live, folded into a manual quick/slot save; the profile never carries it; load_level frees the NPCs under these keys on every re-instantiate — `resurrect` clears this bucket)"])
			var shown := 0
			for k in keys:
				if shown < LEDGER_MAX_LINES:
					out.append("   %s" % k)
					shown += 1
			if keys.size() > shown:
				out.append("   ... %d more" % (keys.size() - shown))

	# --- corpse discovery, the one other profile-tier world ledger (not level-bucketed) ---
	out.append("-- discovered_corpses: %d key(s) in all   (profile tier; keyed by Corpse.save_id / the WorldSaveId fallback, not bucketed per level)" % GameState.discovered_corpses.size())

	# --- 3. latches ---
	var snap: Variant = GameState.get(&"world_snapshot")
	var snap_text := "none"
	if snap != null and is_instance_valid(snap):
		snap_text = "present"
		if snap.has_method(&"is_empty") and bool(snap.call(&"is_empty")):
			snap_text += " (empty)"
	out.append("-- latches: world_snapshot %s · _world_snapshot_pending %s · reload_pending %s · _world_save_queued %s" % [
		snap_text, str(_bool_of(GameState.get(&"_world_snapshot_pending"))), str(bool(GameState.reload_pending())), str(_bool_of(GameState.get(&"_world_save_queued")))])
	out.append("   world_snapshot = the in-memory exact snapshot left by the last manual quick/slot save or load (ANY autosave nulls it); pending = a loaded one GameRoot has not applied yet; reload_pending = a quickload is in flight (autosave refuses); _world_save_queued = a coalesced world-state autosave flushes at end of frame.")
	out.append("key shape (WorldSaveId.key_for): 'id:<save_id>' when the object has an authored save_id, else '<level>|<node path>|x,y,z' (fragile — re-keys on any move/rename); NPC.snapshot_key drops the position: 'id:<save_id>' else '<level>|<node path>'.")
	out.append("in NEITHER ledger by design: corpses, dropped loot, dynamic (spawner) NPCs. Container contents ride the exact-snapshot tier only.")
	return out


## `wipeobjects` (danger) — erase this level's world_objects bucket, persist the erase, then re-instantiate the level
## in place so every consumed pickup / opened door / destroyed prop comes back at its authored state — without a New
## Game. The survey's own gotcha: world_objects has no public clear; the ONLY in-repo clear sits inside
## reset_for_new_game(), which also wipes money, stats, quests, flags and reputation. And clearing the ledger changes
## NOTHING on screen by itself — Door / CanPickUp / CanDestroy / MoneyPickup / UpgradePickup all consult it only in
## _ready — so the re-instantiate is half the command.
##
## ORDER: guards (BEFORE any mutation, so a refusal never leaves the ledger erased with the level still showing the
## old state) -> erase -> autosave_world_state() -> load_level(same LevelData, place_at_spawn=false). The autosave is
## queued deferred and runs BEFORE load_level's own deferred hooks (FIFO), so what hits disk is the wiped ledger.
static func _cmd_wipeobjects(ctx: Dictionary) -> PackedStringArray:
	var g := _same_level_reload_guard(ctx)
	var err: String = g[&"error"]
	if err != "":
		return _one("wipeobjects REFUSED — " + err)
	var path: String = g[&"path"]
	var bucket_v: Variant = GameState.world_objects.get(path)
	var count := (bucket_v as Dictionary).size() if bucket_v is Dictionary else 0
	if count == 0:
		var none := PackedStringArray()
		none.append("no world_objects entries recorded under \"%s\" — nothing to wipe, and the level was NOT re-loaded." % path)
		none.append("(`reload` re-instantiates the whole scene; `ledger all` shows whether the entries sit under a different level key)")
		return none

	GameState.world_objects.erase(path)
	GameState.autosave_world_state()  # erase() bypasses the write record_object_state would have queued
	var out := PackedStringArray()
	out.append("wiped %d world_objects entr%s for \"%s\" (doors' open/locked, consumed pickups, destroyed props)." % [count, "y" if count == 1 else "ies", path])
	# The flush resolves the player itself (GameState.live_player, by group) — ctx's handle is only a proxy for
	# whether that will find anyone; autosave() is a hard no-op without an in-tree player.
	if _player(ctx) == null:
		out.append("! no player in ctx: if there is no live in-tree player the queued autosave NO-OPs, and the wipe lives in memory only until the next successful save.")
	else:
		out.append("a coalesced full-profile autosave was queued (deferred, end of frame): your Continue save now holds the wiped ledger, and a pending in-memory WorldSnapshot is nulled by it. (Sandbox rewrite applies if `sandbox on`.)")
	out.append_array(_reload_same_level(ctx, g))
	out.append("every Door / CanPickUp / CanDestroy / MoneyPickup / UpgradePickup reads the ledger ONLY in _ready — the re-instantiate is what makes them come back authored.")
	out.append("untouched: discovered_corpses, the cross-level dead-NPC ledger (authored NPCs you killed stay dead — `resurrect` is the other half), and the exact-snapshot container DATA in any quick/slot file (the LIVE containers still re-seeded authored contents, per the line above — that is the re-instantiate, not this ledger).")
	out.append("! a quicksave / slot file written BEFORE this still holds the OLD ledger — loading it brings every entry back.")
	return out


## `resurrect` (danger) — forget every authored-NPC death recorded for this level (GameState._dead_authored[level],
## the private cross-level ledger) and re-instantiate the level in place, so every authored NPC the player killed
## this session stands again — the undo for `killall`. The trap it exists for: `killall` -> take_damage -> died ->
## NPC._record_snapshot_death -> GameState.record_npc_death for every AUTHORED body; then `reload` / a door swap ->
## GameRoot.load_level -> _suppress_dead_authored frees them again, so the level stays EMPTY for the rest of the
## process; only a New Game or a quickload resets the ledger, and nothing public clears it.
##
## The Dictionary GameState.get(&"_dead_authored") hands back IS the field (Godot Dictionaries are shared by
## reference; only duplicate() copies), so erase() on it lands on the ledger itself. That is the ONLY route — an
## intentional underscore reach, verified after the fact so a copy could never masquerade as a clear.
static func _cmd_resurrect(ctx: Dictionary) -> PackedStringArray:
	var g := _same_level_reload_guard(ctx)
	var err: String = g[&"error"]
	if err != "":
		return _one("resurrect REFUSED — " + err)
	var path: String = g[&"path"]
	var dead_v: Variant = GameState.get(&"_dead_authored")
	if not (dead_v is Dictionary):
		return _one("resurrect REFUSED — GameState has no _dead_authored Dictionary (API drift); nothing to clear, level not re-loaded")
	var dead: Dictionary = dead_v
	var bucket_v: Variant = dead.get(path)
	var keys := _sorted_keys(bucket_v as Dictionary) if bucket_v is Dictionary else PackedStringArray()
	if keys.is_empty():
		var none := PackedStringArray()
		none.append("no authored deaths recorded for \"%s\" — every authored NPC already stands (or was never killed); the level was NOT re-loaded." % path)
		none.append("dynamic (spawner-produced) bodies never enter this ledger — their EncounterSpawner re-arms on a `reload`. `ledger all` shows other levels' buckets.")
		return none

	dead.erase(path)
	# Belt-and-braces: confirm the erase landed on the FIELD, not on a copy, before freeing the whole level over it.
	var check: Variant = GameState.get(&"_dead_authored")
	if check is Dictionary and (check as Dictionary).has(path):
		return _one("resurrect REFUSED — erase() did not reach GameState._dead_authored (a copy came back?); the ledger still holds %d key(s) and the level was NOT re-loaded" % keys.size())

	var out := PackedStringArray()
	var named := PackedStringArray()
	for i in mini(keys.size(), RESURRECT_MAX_NAMED):
		named.append(keys[i])
	out.append("forgot %d authored death%s for \"%s\": %s%s" % [
		keys.size(), "" if keys.size() == 1 else "s", path, ", ".join(named),
		("  (+%d more)" % (keys.size() - named.size())) if keys.size() > named.size() else ""])
	out.append_array(_reload_same_level(ctx, g))
	out.append("GameRoot's deferred _suppress_dead_authored now finds an empty bucket, so every authored NPC stands at its .tscn spot with full hp; their corpses went with the old subtree (corpses are not persisted).")
	out.append("kill XP, bounty, faction kill_penalty and any KILL objective fire again on a re-kill — a cheat, they are re-farmable.")
	# The two save tiers, honestly: this ledger never touches the profile, and the exact-snapshot tier is SEPARATE.
	out.append("no disk write happened: this ledger reaches disk only folded into a manual quick/slot save's [world_snapshot]. A quicksave/slot made BEFORE this still holds the deaths — loading it restores _dead_authored from its dead_map() and load_level frees them again (resurrect does NOT survive an older quickload). A quicksave made from HERE captures them alive (capture: live wins) and sticks. Continue/autosave never carried the ledger, so that tier revived them anyway.")
	return out


## The guards `wipeobjects` / `resurrect` run BEFORE touching a ledger, mirroring `_cmd_warp`'s for the SAME
## LevelData — a refusal must never leave a ledger erased while the level still shows the old state. Returns
## {&"error": String (non-empty = refuse verbatim), &"data": the loaded LevelData, &"root": the GameRoot node,
## &"path": GameState.current_level_path}.
static func _same_level_reload_guard(ctx: Dictionary) -> Dictionary:
	var out := {&"error": "", &"data": null, &"root": null, &"path": ""}
	var tree := _tree(ctx)
	if tree == null:
		out[&"error"] = "no SceneTree"
		return out
	var path := String(GameState.current_level_path)
	if path == "":
		# A code-built LevelData records nothing (blank resource_path), so there is no .tres to re-load AND every
		# ledger key for it carries a blank level component — the trap `warp` refuses for the same reason.
		out[&"error"] = "GameState.current_level_path is BLANK (no level loaded, or a code-built LevelData) — nothing to re-load; `warp <level>` onto a real .tres first"
		return out
	if not ResourceLoader.exists(path):
		out[&"error"] = "current_level_path \"%s\" does not resolve on disk (deleted / renamed .tres) — cannot re-load it" % path
		return out
	var data := load(path)
	if data == null:
		out[&"error"] = "could not load LevelData %s" % path
		return out
	if String(data.resource_path) == "":
		out[&"error"] = "%s loaded with a blank resource_path — re-loading it would blank current_level_path and break the ledger keys" % path
		return out
	if data.get("scene") == null:
		out[&"error"] = "%s has no `scene` — GameRoot.load_level no-ops on it" % path
		return out
	var gr := _game_root(tree)
	if gr == null:
		out[&"error"] = "no GameRoot in the tree (group \"%s\") — an in-place level re-load is only possible in the gameplay scene" % String(GroupsScript.GAME_ROOT)
		return out
	if not gr.has_method(&"load_level"):
		out[&"error"] = "the node in group \"%s\" has no load_level()" % String(GroupsScript.GAME_ROOT)
		return out
	if GameState.reload_pending():
		# The scene is about to reload on its own, autosave() refuses meanwhile, and the ledger edit would ride into
		# a fresh boot that reads the just-loaded profile anyway.
		out[&"error"] = "a quickload is in flight (GameState.reload_pending) — let the fresh scene boot first"
		return out
	out[&"data"] = data
	out[&"root"] = gr
	out[&"path"] = path
	return out


## Re-instantiate the CURRENT level over itself: GameRoot.load_level(same LevelData, entry_id "", place_at_spawn
## = false) — the Player is a SIBLING of Level (game.tscn), so it survives, and place_at_spawn=false leaves it
## standing where it is (game_root.gd:115). Synchronous: instantiate + add_child happen inside the call (safe from
## a console _input / a menu button, NEVER from a _ready). Same post-load notes and state hygiene as `_cmd_warp`;
## unlike `reload`/`load` this does NOT release the scene-scoped state — the player (its ghost meta, the timescale
## override) survives a level swap exactly as it does under `warp`.
static func _reload_same_level(ctx: Dictionary, g: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	# Read both handles as bare Variants and validity-check BEFORE the typed cast: a typed assignment of a freed
	# instance is a script error, not a null (the same rule every ctx accessor here follows).
	var gr_v: Variant = g[&"root"]
	var data_v: Variant = g[&"data"]
	if gr_v == null or not is_instance_valid(gr_v) or data_v == null or not is_instance_valid(data_v):
		out.append("! level re-load skipped: the guard's GameRoot/LevelData went away between check and call")
		return out
	var gr := gr_v as Node
	var data := data_v as Resource
	if gr == null or data == null:
		out.append("! level re-load skipped: the guard handed back a non-Node root or a non-Resource level")
		return out
	gr.call(&"load_level", data, &"", false)
	out.append("level re-instantiated in place (GameRoot.load_level on the same LevelData, place_at_spawn = false — you keep standing where you are; if that was in a doorway that re-closed or on a prop that came back, `noclip`/`tpaim` out).")
	var tree := _tree(ctx)
	var lvl := _level_node(tree)
	if lvl == null:
		out.append("! no \"Level\" child after the load — the scene may have instantiated null (reimport transient); the old subtree was already detached, so `reload` to recover")
	elif not _has_level_root_script(lvl):
		# ps1_warp.gd:43 gates cover() on `level_root is LevelRoot` and returns silently otherwise.
		out.append("! this level's root carries no level_root.gd, so Ps1Warp.cover() skipped it — no PS1 vertex-snap here.")
	out.append("the old subtree was queue_free()d: corpses, dropped items, spawned NPCs and anything you parented into Level are gone; the RentCollector's dawn counters reset (the notice can serve again next dawn), DayNightSky re-captures its authored look, and the fresh NavigationRegion3D needs a map-sync frame before NPCs path.")
	# Everything below is what a fresh Level._ready re-seeds from authored exports — none of it reads either ledger, so
	# it comes back regardless of what the caller wiped (container.gd seeds in _ready and only a WorldSnapshot.apply
	# restores contents; a persist_collected=false pickup never recorded itself; a recruited companion is an authored
	# NPC that stayed parented under Level — CompanionRecruiter never reparents it — so it went with the subtree).
	out.append("also re-seeded to authored by the re-instantiate: every ItemContainer's contents (loot you took is back — re-farmable), MoneyPickup/UpgradePickup with persist_collected off, and every EncounterSpawner re-arms; a recruited companion standing in this level was freed with it and its fresh copy is NOT following you.")
	# The old cast went with the subtree and the new one boots live, so a latched `freezeai ON` would now lie; the
	# sticky `npc` target is a Node that was just freed.
	var state := _state(ctx)
	state.erase(STATE_FREEZE_AI)
	state.erase(STATE_NPC_STICKY)
	return out


static func _cmd_quests() -> PackedStringArray:
	var index := _quests()
	var out := PackedStringArray()
	if index.is_empty():
		out.append("no Quest resources under %s" % QUEST_DIR)
	for qid in _sorted_keys(index):
		var path := String(index[qid])
		var quest := load(path)
		var title := String(quest.get("title")) if quest != null else "?"
		var file := path.get_file()
		var note := "" if file.get_basename() == qid else "   (file: %s)" % file
		out.append("  %-10s %-22s %s%s" % [_quest_state(StringName(qid)), qid, title, note])
	out.append("keyed by Quest.id, which is NOT the filename.")
	# active_quest_ids() returns the live dict's keys; anything already tracked but no longer on disk still shows.
	var extra := PackedStringArray()
	for a in QuestTracker.active_quest_ids():
		var s := String(a)
		if not index.has(s):
			extra.append(s)
	if not extra.is_empty():
		out.append("active but not on disk: %s" % ", ".join(extra))
	return out


## Lift or restore the stranger-name veil. `names on` = real names shown (the veil OFF), because that is what a
## debug command is for; the wording is stated explicitly in the output so nobody has to guess the polarity.
static func _cmd_names(args: PackedStringArray) -> PackedStringArray:
	var showing := not bool(GameState.stranger_names_enabled)
	var on := bool(DebugCommandsScript.toggle_value("" if args.is_empty() else args[0], showing))
	GameState.stranger_names_enabled = not on
	var out := PackedStringArray()
	out.append("names %s — real names are %s (stranger_names_enabled = %s)" % [
		"ON" if on else "OFF", "SHOWN" if on else "veiled", str(bool(GameState.stranger_names_enabled))])
	out.append("nothing repaints on the flip: the look-at readout, corpse header and dialogue speaker update on their next natural refresh.")
	out.append("this switch is deliberately NOT serialized — it resets to veiled on the next launch and never bakes into a save.")
	return out


# =============================================================================================================
# VIEW
# =============================================================================================================

## The look-at inspector (a Node3D, so it lives under the current scene, not on the console's CanvasLayer).
static func _cmd_inspect(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var insp := _inspector(ctx)
	if insp == null:
		return _one("inspect: no DebugInspector available (%s missing, or the name is taken under the current scene)" % INSPECTOR_SCRIPT_PATH)
	if not insp.has_method(&"is_enabled") or not insp.has_method(&"set_enabled"):
		return _one("inspect: DebugInspector is missing set_enabled/is_enabled")
	var on := bool(DebugCommandsScript.toggle_value("" if args.is_empty() else args[0], bool(insp.call(&"is_enabled"))))
	insp.call(&"set_enabled", on)
	return _one("inspect %s" % ("ON — live state is drawn over whatever you aim at" if on else "OFF"))


## The AI/nav overlay. Created on demand: NO level in the project ships a NavDebugOverlay, so a command that
## expects to find one finds nothing. It is parented under the CURRENT SCENE, never under the console's
## CanvasLayer, because it renders through an AiDebugDraw (a Node3D) child that must live in the 3D world — and
## whose _ready forces an identity transform, so it has to sit at world origin anyway.
static func _cmd_navdebug(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var tree := _tree(ctx)
	if tree == null:
		return _one("no SceneTree")
	var created := false
	var ov := _find_or_create(tree.current_scene, &"DebugNavOverlay", NavDebugOverlayScript)
	if ov == null:
		return _one("could not create a NavDebugOverlay under the current scene")
	if not ov.has_meta(&"debug_layers_armed"):
		ov.set_meta(&"debug_layers_armed", true)
		created = true
		# The four AI layers ship OFF; this command promises cones, factions, GOAP labels and zones, so arm them
		# once on the instance we own rather than silently showing only the navmesh. Guarded by a meta so a
		# designer who later unticks a layer in the remote inspector doesn't get it forced back on next toggle.
		for setter: StringName in [&"set_show_sight_cones", &"set_show_faction_colors", &"set_show_goap_labels", &"set_show_trigger_zones"]:
			if ov.has_method(setter):
				ov.call(setter, true)
	var current := bool(ov.get(&"enabled"))
	var on := bool(DebugCommandsScript.toggle_value("" if args.is_empty() else args[0], current))
	if ov.has_method(&"set_enabled"):
		ov.call(&"set_enabled", on)
	else:
		ov.set(&"enabled", on)
	var out := PackedStringArray()
	out.append("navdebug %s%s" % ["ON" if on else "OFF", "  (overlay created — no level ships one)" if created else ""])
	out.append("! PROCESS-WIDE: this writes NavigationServer3D.set_debug_enabled, the tree's debug_navigation_hint, and debug_enabled on EVERY NavigationAgent3D — not just this overlay's own drawing.")
	return out


## The F3 perf HUD. A CanvasLayer, so it hangs off the console's host and rides with it.
static func _cmd_perf(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var tree := _tree(ctx)
	if tree == null or tree.current_scene == null:
		return _one("no scene to find or mount the perf overlay in")
	# ⭐Find the SHIPPED overlay first, by SCRIPT and anywhere under the scene — scenes/game.tscn carries one named
	# "DebugOverlay". A name-keyed find-or-create under the console host used to grow a SECOND overlay (two panels,
	# two ErrorSinks counting independently) the moment `perf` was typed. Only when none exists at all is one
	# created, at the scene root so it survives level swaps.
	var ov := _find_by_script(tree.current_scene, DebugOverlayScript)
	if ov == null:
		ov = _find_or_create(tree.current_scene, &"DebugOverlay", DebugOverlayScript)
	if ov == null:
		return _one("could not find or create a DebugOverlay")
	var on := bool(DebugCommandsScript.toggle_value("" if args.is_empty() else args[0], bool(ov.get(&"visible"))))
	ov.set(&"visible", on)
	var out := PackedStringArray()
	out.append("perf %s (its own F3 key still works)" % ("ON" if on else "OFF"))
	return out


## wireframe / overdraw / unshaded are ONE Viewport.debug_draw enum, not three independent switches — so they are
## treated as one state: turning one on turns the others off, and "off" returns to DEBUG_DRAW_DISABLED. The
## viewport's own field is the source of truth (no shadow state to drift).
static func _cmd_debug_draw(cmd: String, ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var tree := _tree(ctx)
	if tree == null or tree.root == null:
		return _one("no viewport")
	var vp := tree.root as Viewport
	var want := Viewport.DEBUG_DRAW_DISABLED
	match cmd:
		"wireframe": want = Viewport.DEBUG_DRAW_WIREFRAME
		"overdraw": want = Viewport.DEBUG_DRAW_OVERDRAW
		"unshaded": want = Viewport.DEBUG_DRAW_UNSHADED
	var previous := vp.debug_draw
	var on := bool(DebugCommandsScript.toggle_value("" if args.is_empty() else args[0], previous == want))
	var out := PackedStringArray()
	if on:
		if cmd == "wireframe" and not _wireframes_armed:
			# WIREFRAME renders NOTHING until the server has been told to generate wireframe index buffers, and
			# nothing else in the project ever calls this. One-shot: it is a process-wide arm, not a mode.
			RenderingServer.set_debug_generate_wireframes(true)
			_wireframes_armed = true
			out.append("armed RenderingServer.set_debug_generate_wireframes(true) — required once, or wireframe draws nothing.")
		vp.debug_draw = want
		if previous != Viewport.DEBUG_DRAW_DISABLED and previous != want:
			out.append("(%s replaced the previous debug draw mode — these three share one enum)" % cmd)
		out.append("%s ON" % cmd)
	else:
		vp.debug_draw = Viewport.DEBUG_DRAW_DISABLED
		out.append("%s OFF — debug draw back to DISABLED" % cmd)
	return out


# --- quantize -------------------------------------------------------------------------------------------------

## `quantize [0-8]` — set the screen post-process COLOUR DEPTH, the Options -> Video -> Colour Depth dropdown.
##
## Writes Settings.color_quantization and stops there: the player's post-process driver (player.gd _update_low_hp)
## re-pushes `quantize_levels` onto the live ColorRect material every frame, so the next frame is already the new
## depth. That is why this command never goes looking for the material — reaching past the driver would mean two
## writers of one uniform, and the driver would win on the very next frame anyway.
##
## ⭐ THE FIELD, NEVER THE SETTER. `Settings.set_color_quantization` PERSISTS — it calls save_settings(), which
## rewrites the player's real user://settings.cfg. A debug command that quietly leaves someone's game at 3-bit
## after they close the console is the __perf_probe lesson repeating itself, so this pokes the field through
## `.set()` and says so in its output. Reopening the Options menu (or a `Revert`) shows the persisted value,
## not this one.
##
## Off-tree safe: no ctx, no player, no tree. It works from the console before a level even loads.
static func _cmd_quantize(args: PackedStringArray) -> PackedStringArray:
	var count := int(Settings.COLOR_QUANTIZE_LEVELS.size())
	var live := int(Settings.color_quantization)
	var out := PackedStringArray()
	if args.is_empty():
		out.append("colour depth %d of 0..%d — %s" % [live, count - 1, _quantize_text(live)])
		for i in range(count):
			out.append("  %s %d  %s" % ["->" if i == live else "  ", i, _quantize_text(i)])
		out.append("  the DITHER is what makes the coarse rows readable — see `dither`.")
		return out
	var word := args[0].strip_edges()
	# is_valid_FLOAT, not is_valid_int: the registry types this slot Kind.NUMBER, so the console already let
	# "3.0" through validation — rejecting it here would refuse a value the parser said was fine.
	if not word.is_valid_float():
		return _one("quantize: \"%s\" is not a depth index — pass 0..%d, or no argument to list them" % [word, count - 1])
	var want := int(roundi(word.to_float()))
	if want < 0 or want >= count:
		return _one("quantize: %d is outside 0..%d (0 = authored, %d = coarsest)" % [want, count - 1, count - 1])
	Settings.set(&"color_quantization", want)
	out.append("colour depth %d -> %d  (%s)" % [live, want, _quantize_text(want)])
	out.append("  in-memory only: settings.cfg still holds %d, and the Options menu will show that." % live)
	if want == 0:
		out.append("  0 hands the material back its authored `color_steps` (16 on the player overlay, 32 on the CRT wall).")
	return out


## One depth index as a line: its per-channel steps and how many colours that actually is. The counts come from
## Settings so this can never quote a different number than the shader is given.
static func _quantize_text(mode: int) -> String:
	@warning_ignore("static_called_on_instance")  # `Settings` is the autoload instance; these mappings are static
	var levels: Vector3 = Settings.color_quantize_levels(mode)
	if levels == Vector3.ZERO:
		return "authored (the material's own color_steps)"
	@warning_ignore("static_called_on_instance")  # as above
	var colors := int(Settings.color_quantize_color_count(mode))
	return "steps r%d g%d b%d = %s colours" % [int(levels.x), int(levels.y), int(levels.z), _grouped(colors)]


## 16777216 -> "16,777,216". Thousands separators by hand: %d has none, and a raw nine-digit run in a console
## line is unreadable at a glance, which is the whole point of printing the count next to the depth.
static func _grouped(n: int) -> String:
	var digits := str(maxi(n, 0))
	var out := ""
	var seen := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		seen += 1
		if seen % 3 == 0 and i > 0:
			out = "," + out
	return out

# --- screenshot -----------------------------------------------------------------------------------------------

## `screenshot [clean]` — save the EXACT root render target to user://screenshots/<yyyy-mm-dd_hh-mm-ss>.png.
##
## THE TARGET. What the root viewport holds depends on Settings.presentation: RETRO runs the authored viewport
## stretch (aspect expand, scale 0.5), so the root IS the low-res ~792x444 canvas (menu_qa_shots.gd:3) and the
## window merely nearest-upscales it; HIGH FIDELITY (canvas_items stretch) renders the root at the NATIVE window
## resolution. Either way `tree.root.get_texture().get_image()` is the pixel-exact frame — the same read every `-s`
## screenshot probe uses (day_night_shots.gd:62, menu_qa_shots.gd _shot()) — so the driver's root read is correct
## in BOTH modes; the report line stamps the presentation + live native_scale() so a shot is self-describing.
## Never a DisplayServer window grab: that would be the monitor-sized blit (in RETRO an upscaled one, comb
## artefacts and all).
##
## WHY A HELPER NODE. run() is a static that returns its lines synchronously, but a capture must wait for a DRAW: an
## Image read here, mid-command, is the PREVIOUS frame (the command runs during input dispatch or the exec queue's
## physics tick — both before this frame's draw). So this mounts a one-shot _ShotDriver at tree.root (the
## menu_qa_shots.gd _ready "driver at root" idiom: root children survive a reload, and a child of the console or the
## level would die with it) and answers "capturing the next frame"; the driver hides, awaits the draw, captures,
## restores and reports through the console's echo() when it is done (see _ShotDriver for the frame timing).
##
## `clean` hides, for exactly ONE drawn frame, the player HUD (through the same seam `hud off` uses, so the two can
## never disagree about what "the HUD" is) plus every 2D debug surface — the console you typed into, the F1 menu,
## the F3 overlay, the ailog panel, the events column (Groups.DEBUG_SURFACE members + a script-path walk, duck-typed)
## — and the F4 inspector's 3D readout; then it restores exactly what it hid (a layer that was already hidden stays
## hidden). A HUD `hud off` already has down is NOT released: the driver only re-sweeps what the Player's per-frame
## pushers brought back and folds those into `hud off`'s snapshot, so the frame is clean AND `hud on` still restores
## everything. Without `clean` you get the frame as-is, console and all — the "what did it look like when it broke"
## form. `navdebug` draws through the engine's navigation debug layer and is deliberately NOT toggled per frame (a
## process-wide state flip); turn it off first for a clean frame.
static func _cmd_screenshot(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var tree := _tree(ctx)
	if tree == null or tree.root == null:
		return _one("screenshot: no SceneTree / root viewport to read")
	# validate() pinned the only word to `clean`, so presence is the whole test.
	var clean := not args.is_empty()
	var dir_err := DirAccess.make_dir_recursive_absolute(SCREENSHOT_DIR)
	if dir_err != OK:
		return _one("screenshot: could not create %s (error %d %s)" % [SCREENSHOT_DIR, dir_err, error_string(dir_err)])
	var path := _next_screenshot_path()

	var driver := _ShotDriver.new()
	driver.name = "DebugScreenshot"
	driver.path = path
	driver.clean = clean
	if clean:
		driver.hidables = _clean_hidables(tree)
		var player := _player(ctx)
		var ui := _hud_layer(player)
		# A HUD the death cinematic owns is left to the cinematic (its fade IS the frame you would be capturing).
		if ui != null and not _hud_owned_by_death(player):
			driver.hud_layer = ui
			# `hud off` already has the HUD down (and its bail latch armed): the driver must neither re-sweep from
			# scratch nor RELEASE it afterwards — releasing would re-derive the ring / minimap / clock over the dev's
			# own hide. HOLD mode: only the re-shown nodes are swept, and they join `hud off`'s snapshot (the ctx state
			# Dictionary is a reference, so the driver can extend it after the frame) instead of being restored.
			if _has_state(ctx, STATE_HUD_HIDDEN):
				driver.hud_hold = true
				driver.hud_hold_state = _state(ctx)
	# add_child runs the driver's _ready synchronously, which is where the hide happens — still THIS frame, i.e.
	# before this frame's draw, which is the whole point.
	tree.root.add_child(driver)

	var out := PackedStringArray()
	out.append("screenshot: capturing the next drawn frame%s -> %s" % [
		" CLEAN (HUD + every 2D debug surface hidden for that one frame)" if clean else "", ProjectSettings.globalize_path(path)])
	out.append("  the result lands in this scrollback when the frame has been read (a line beginning \"screenshot:\").")
	return out


## "2026-08-18 14:03:07" (Time.get_datetime_string_from_system(false, true)) -> "2026-08-18_14-03-07": a filename
## with no spaces or colons (Windows refuses a colon; a space is merely annoying in a shell). Also swallows the "T"
## of the ISO form, so either datetime flavour maps to the same shape. Pure.
static func screenshot_stamp(datetime: String) -> String:
	return datetime.replace(" ", "_").replace("T", "_").replace(":", "-")


## Same-second collisions are real (two `screenshot`s in one exec file, or a bind held down): the serial bumps while
## the stamp repeats within this process, and file_exists() covers a previous session's leftovers.
static var _last_shot_stamp := ""
static var _last_shot_serial := 0


static func _next_screenshot_path() -> String:
	var stamp := screenshot_stamp(Time.get_datetime_string_from_system(false, true))
	if stamp != _last_shot_stamp:
		_last_shot_stamp = stamp
		_last_shot_serial = 0
	var base := SCREENSHOT_DIR.path_join(stamp)
	while true:
		_last_shot_serial += 1
		var candidate := (base + ".png") if _last_shot_serial == 1 else ("%s_%d.png" % [base, _last_shot_serial])
		if not FileAccess.file_exists(candidate):
			return candidate
	return base + ".png"  # unreachable — the loop returns the first free name


## Every visible-toggleable debug READOUT a clean frame must lose: the Groups.DEBUG_SURFACE CanvasLayers (console,
## menu), every CanvasLayer anywhere in the tree whose script is one of CLEAN_HIDDEN_SCRIPT_PATHS (F3 overlay, ailog
## panel, events column — wherever a designer parented them), and the F4 inspector's AiDebugDraw renderer (a Node3D
## drawing labels in the world; present only while `inspect` is on, read duck-typed off the inspector's private
## `_renderer`). Deduped by instance. The driver only ever touches the members that are VISIBLE when it runs.
static func _clean_hidables(tree: SceneTree) -> Array[Node]:
	var out: Array[Node] = []
	var seen := {}
	for s in tree.get_nodes_in_group(GroupsScript.DEBUG_SURFACE):
		if is_instance_valid(s) and s is CanvasLayer and not seen.has(s.get_instance_id()):
			seen[s.get_instance_id()] = true
			out.append(s)
	var stack: Array[Node] = [tree.root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if not is_instance_valid(n):
			continue
		var scr := n.get_script() as Script
		var scr_path := String(scr.resource_path) if scr != null else ""
		if scr_path != "":
			if n is CanvasLayer and CLEAN_HIDDEN_SCRIPT_PATHS.has(scr_path) and not seen.has(n.get_instance_id()):
				seen[n.get_instance_id()] = true
				out.append(n)
			elif scr_path == INSPECTOR_SCRIPT_PATH:
				var renderer: Variant = n.get(&"_renderer")
				if renderer != null and is_instance_valid(renderer) and renderer is Node3D and not seen.has(renderer.get_instance_id()):
					seen[renderer.get_instance_id()] = true
					out.append(renderer)
		for child in n.get_children():
			stack.push_back(child)
	return out


## Report lines from a root-parented helper. The console (a Groups.DEBUG_SURFACE member with echo(), which appends
## whether or not its panel is up and mirrors to stdout) is the transcript; when no surface has echo() — the console
## was freed by a reload mid-capture, or the command came from a scene without one — plain print() is the fallback,
## so the result is never lost. Never push_warning: that would inflate the F3 ErrorSink tallies.
static func _echo_to_surfaces(tree: SceneTree, lines: PackedStringArray) -> void:
	var echoed := false
	if tree != null:
		for s in tree.get_nodes_in_group(GroupsScript.DEBUG_SURFACE):
			if is_instance_valid(s) and s.has_method(&"echo"):
				s.call(&"echo", lines)
				echoed = true
	if not echoed:
		for line in lines:
			print(line)


## The one-shot capture driver `screenshot` mounts at tree.root. Lifetime = one drawn frame: _ready hides (clean),
## awaits the draw, reads the root viewport, saves, restores, reports, frees itself.
##
## ⭐WHY `RenderingServer.frame_post_draw` AND NOT `tree.process_frame`. The command that spawns this runs during
## INPUT dispatch (Enter in the console's LineEdit, a click in the F1 menu, a bound key) or during the exec queue's
## _physics_process tick — both come BEFORE this frame's process step, and `process_frame` is emitted at the START of
## that step. So `await tree.process_frame` from here resumes in the SAME frame, before anything has been drawn since
## the hide, and a read then hands back LAST frame's texture — with the console still in it. `frame_post_draw` is
## emitted by the RenderingServer right after it has finished drawing the CURRENT frame (menu_qa_shots.gd _shot() is
## the proven read-after-it idiom in this project), i.e. it is unconditionally "the first draw that happens after
## now" — whichever callback we were spawned from. Hide -> await frame_post_draw -> read == the frame drawn WITHOUT
## the hidden layers, exactly once, then everything is put back before the next draw. One visible flicker frame is
## the price, and it is the whole mechanism.
##
## ⭐WHY A SECOND SWEEP AT `RenderingServer.frame_pre_draw`. The hide above happens BEFORE this frame's physics and
## process steps, and the Player's own per-frame HUD pushers run in between: set_stealth_level / set_detection_meter
## every physics tick (player.gd _update_stealth_hud), the look-at name, the takedown / pet / claim cue facades, the
## enemy HP bar on a hit — each writes `visible` on a DIRECT child of the UI layer, and each is gated on the PLAYER's
## `_dying` / `_hud_quiet` (never on the UI's death latch), flags a screenshot must not set (they also swallow toasts
## and damage juice). So a crouched dev would get a "clean" frame with [ HIDDEN ] and the heat bar in it. frame_pre_draw
## is emitted by RenderingServer.draw() right before the frame's draw command is queued — after every physics/process
## callback of the frame, i.e. the LAST point at which a visibility write still lands in THIS draw. The driver
## re-sweeps there (non-clobbering: _hud_sweep_more) and merges the extra paths into the same restore set.
##
## Focus: hiding a CanvasLayer propagates NOTIFICATION_VISIBILITY_CHANGED to its Controls, and a Control that is no
## longer visible in tree DROPS keyboard focus (Viewport::_gui_hide_control) — which would leave the console you typed
## `screenshot clean` into with a dead field until you clicked it. The driver remembers the focus owner before the
## hide and re-grabs it after the restore, if nothing else took focus meanwhile.
class _ShotDriver extends Node:
	var path: String = ""
	var clean: bool = false
	## Candidates to hide (CanvasLayers + the inspector's Node3D renderer); only the VISIBLE ones are touched.
	var hidables: Array[Node] = []
	## The player's UI CanvasLayer to sweep through _hud_hide/_hud_show, or null to leave the HUD alone.
	var hud_layer: Node = null
	## HOLD mode: `hud off` is in force. The HUD is already down and its latch armed, so the sweeps only catch what the
	## per-frame pushers re-showed, NOTHING is restored afterwards, and the extra paths are merged into `hud off`'s
	## snapshot in `hud_hold_state` (the console's ctx state Dictionary — a REFERENCE, so a write after the frame lands
	## in the same dict `hud on` reads). Guarded on the key still being there: a release_scene_scoped_state in the
	## meantime (the console freed by a reload) erased it, and a fresh console owns a NEW dict — never re-create it.
	var hud_hold: bool = false
	var hud_hold_state: Dictionary = {}
	var _hidden: Array[Node] = []
	var _hud_paths := PackedStringArray()
	var _focus: Control = null

	func _ready() -> void:
		# A dialogue pause must not stall the restore; the frame signals fire regardless, but be explicit like every
		# other debug node.
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()

	func _run() -> void:
		var tree := get_tree()
		if clean:
			_hide(tree)
			# Second pass right before the draw — see the class doc. Both signals come from the same
			# RenderingServer.draw() call, so this cannot skip a frame between them.
			await RenderingServer.frame_pre_draw
			_hide_again()
		await RenderingServer.frame_post_draw
		var lines := PackedStringArray()
		var img: Image = null
		# Re-resolve the tree: a reload can land inside the awaited frame and this node (root-parented) outlives it.
		tree = get_tree()
		if tree != null and tree.root != null:
			var tex := tree.root.get_texture()
			if tex != null:
				img = tex.get_image()
		var global := ProjectSettings.globalize_path(path)
		if img == null or img.is_empty():
			lines.append("screenshot: FAILED — the root viewport texture read back empty (headless, or no frame drawn yet)")
		else:
			var err := img.save_png(global)
			if err == OK:
				# Presentation stamp: the same WxH could be a RETRO canvas on one monitor or a HIGH FIDELITY native
				# frame on another, so the line names the target it read. native_scale() is read LIVE per the
				# Settings contract (1.0 in RETRO by identity).
				var pres := "RETRO" if Settings.presentation == Settings.PRESENTATION_RETRO else "HIGH_FIDELITY"
				lines.append("screenshot: wrote %s  (%dx%d%s, %s native_scale=%.2f)" % [global, img.get_width(), img.get_height(), ", clean" if clean else "", pres, Settings.native_scale()])
			else:
				lines.append("screenshot: save_png FAILED (error %d %s) -> %s" % [err, error_string(err), global])
		if clean:
			lines.append_array(_restore(tree))
		DebugActionsWorld._echo_to_surfaces(tree, lines)
		queue_free()

	func _hide(tree: SceneTree) -> void:
		if tree != null and tree.root != null:
			# `focus_owner`, not `owner`: a local named `owner` would shadow Node.owner on this Node subclass.
			var focus_owner := tree.root.gui_get_focus_owner()
			if focus_owner != null and is_instance_valid(focus_owner):
				_focus = focus_owner
		_sweep_hidables()
		if hud_layer != null and is_instance_valid(hud_layer):
			if hud_hold:
				# Already down: catch only what came back since `hud off`, without touching the armed latch.
				_merge_hud_paths(DebugActionsWorld._hud_sweep_more(hud_layer))
			else:
				_hud_paths = DebugActionsWorld._hud_hide(hud_layer)

	## The pre-draw pass (see the class doc): anything hidden in _hide that came back, plus the HUD children the
	## Player's per-frame pushers re-showed. Merges into the same sets _restore reads, so the restore stays exact.
	func _hide_again() -> void:
		_sweep_hidables()
		if hud_layer != null and is_instance_valid(hud_layer):
			_merge_hud_paths(DebugActionsWorld._hud_sweep_more(hud_layer))

	## Hide every VISIBLE hidable not already in _hidden. `visible` read duck-typed: the list mixes CanvasLayers and a
	## Node3D. Only a visible member is hidden, so the restore can blanket-show _hidden without waking a layer that
	## was down (an F3 the dev had off).
	func _sweep_hidables() -> void:
		for n in hidables:
			if not is_instance_valid(n) or _hidden.has(n):
				continue
			var raw: Variant = n.get(&"visible")
			if raw is bool and bool(raw):
				n.set(&"visible", false)
				_hidden.append(n)

	func _merge_hud_paths(paths: PackedStringArray) -> void:
		for p in paths:
			if not _hud_paths.has(p):
				_hud_paths.append(p)

	func _restore(tree: SceneTree) -> PackedStringArray:
		var out := PackedStringArray()
		var restored := 0
		for n in _hidden:
			if is_instance_valid(n):
				n.set(&"visible", true)
				restored += 1
		var hud_note := "HUD left as it was (no player, or the death cinematic owns it)"
		if hud_layer != null and is_instance_valid(hud_layer):
			var player: Node = DebugActionsWorld.GroupsScript.human_player(tree) if tree != null else null
			if hud_hold:
				# `hud off` owns the HUD: nothing is shown back. What the two sweeps hid joins its snapshot so `hud on`
				# restores it — only while the key is still there (see the field doc); a death mid-frame changes
				# nothing here, `hud off`'s own documented death behaviour applies.
				var key: StringName = DebugActionsWorld.STATE_HUD_HIDDEN
				if hud_hold_state.has(key):
					var held := DebugActionsWorld._hud_held_paths(hud_hold_state)
					for p in _hud_paths:
						if not held.has(p):
							held.append(p)
					hud_hold_state[key] = held
				hud_note = "HUD kept down (`hud off` in force; %d re-shown node(s) re-swept into its snapshot)" % _hud_paths.size()
			elif player != null and DebugActionsWorld._hud_owned_by_death(player):
				# Died INSIDE the captured frame: die()'s own sweep replaced the UI's list, and showing our nodes now
				# would paint HP bars over the fade. Hand them to the death sweep instead, so the revive restores them.
				DebugActionsWorld._hud_adopt_into_death_sweep(hud_layer, _hud_paths)
				hud_note = "died mid-capture — the %d hidden HUD node(s) were handed to the death sweep; the revive restores them" % _hud_paths.size()
			else:
				var shown := DebugActionsWorld._hud_show(hud_layer, _hud_paths)
				hud_note = "HUD restored (%d node(s))" % shown
		# Re-grab the focus the hidden frame dropped (see the class doc) — only if nothing else took it meanwhile.
		if _focus != null and is_instance_valid(_focus) and _focus.is_inside_tree() and _focus.is_visible_in_tree():
			if tree != null and tree.root != null and tree.root.gui_get_focus_owner() == null:
				_focus.grab_focus()
		out.append("  clean frame: hid %d debug surface(s), %s" % [restored, hud_note])
		return out


# --- hud ------------------------------------------------------------------------------------------------------

## `hud [on|off]` — hide / show the player HUD, restoring exactly what was hidden.
##
## THE HUD is scripts/ui/ui.gd's CanvasLayer under the Player (Player.tscn "UI"): every readout — the HP/ammo labels
## and bars, the hotbar, the crosshair (a direct child, ui.gd:187-198), the stamina ring / bar, the minimap + clock +
## objective tracker, the toast stack, the blood splatter, and every PlayerHud overlay (stealth badge, prompts, enemy
## health bar, hit flashes — all `ui.add_child`, player_hud.gd:69-236) — is a DIRECT CHILD of that layer. Nothing HUD-
## like lives elsewhere. Also on that layer is the post-process ColorRect (colour quantisation / dither / grain /
## night vision, ui.tscn) — that is the game's LOOK, not the HUD, and it must survive a "clean" frame.
##
## Two nodes the HUD ghost (scripts/ui/hud_ghost.gd) adds are the exception that proves the rule, and both fall out
## correctly with no wiring here: its `HudGhost` display TextureRect IS a direct CanvasItem child (seated just above
## the post-process ColorRect, so it is drawn as a HUD element rather than fed into that shader), so it
## is swept like any other readout and a "clean" frame has no ghost trails in it; its `HudGhostDriver` is a plain
## Node, so the `child is CanvasItem` filter skips it the same way that filter skips any nested CanvasLayer — which
## is what we want, because the driver only writes shader uniforms and its accumulator has nothing left to photograph
## once the HUD is hidden. The driver also honours the same bail latch (ui.gd hands it `_death_hidden_hud.is_empty()` each frame), so
## it cannot re-show the display out from under a sweep.
##
## MECHANISM: ui.hide_hud_for_death() + our own path snapshot, NOT a hand-rolled child sweep. The reason is the UI's
## per-frame drivers: _apply_stamina_mode (every frame from _update_stamina_readout), _apply_minimap_visibility (every
## frame from _process) and _apply_crosshair_visibility (every holster / dialogue change) each WRITE `visible` on the
## ring / bar / minimap / clock / crosshair — and each BAILS only while `ui._death_hidden_hud` is non-empty (ui.gd:
## 508-511, 566-570, 957-963). A snapshot that merely set `visible = false` would see those nodes resurrected on the
## very next frame; hide_hud_for_death() is the ONE sweep that also arms that bail latch, and it already spares the
## ColorRect. What we own on top is the SNAPSHOT: UI-relative node paths in ctx state (STATE_HUD_HIDDEN), because
## the UI's own list is not ours to trust — die() REPLACES it (a death while `hud off` is in force re-records only
## what was visible, i.e. nothing) and the revive CONSUMES it — so `hud on` restores from OUR paths, then releases
## the latch and re-derives the crosshair from the live holster / dialogue state (see _hud_show for why that is not
## restore_hud_after_death()).
##
## Whether the reuse is safe outside death: YES for the hide (the sweep + latch is exactly the contract we need, and
## the toast-swallowing / readout-clearing gates are on the PLAYER's `_dying` / `_hud_quiet` flags, not on the UI
## list — we never touch those). The restore half is NOT reused: restore_hud_after_death() also frees every live
## toast + the money float (_purge_transient_notices), a revive-only sweep a screenshot must not perform.
##
## Refused while the death cinematic owns the HUD (`_dying` / `_hud_quiet`): the sweep would clobber the cinematic's
## own list. Three known, documented leaks: (1) a conversation's close re-shows the HP bar / ammo / hotbar / toasts
## (_set_gameplay_hud_visible + _on_dialogue_finished write those directly, bypassing the latch); (2) the PLAYER's own
## per-frame HUD pushers — set_stealth_level / set_detection_meter every physics tick, the look-at name on a new
## target, the takedown / pet / claim cue facades, the enemy HP bar on a hit — re-show their labels past the latch,
## because they gate on Player `_dying` / `_hud_quiet` (never on the UI list), flags this command must not set (they
## also swallow toasts and damage juice). For both, a second `hud off` RE-SWEEPS (non-clobbering — _hud_hide) and
## merges; `screenshot clean` covers them with its own pre-draw pass. (3) A death while hidden finds nothing to sweep,
## so its latch never arms and the ring / minimap / clock / crosshair re-derive over the fade — cosmetic, `hud off`
## again after the revive.
##
## Released in release_scene_scoped_state: the UI is freed WITH the Player on a scene reload, so only the state key
## needs erasing (a fresh Player must never be "restored" from a stale snapshot). `warp` keeps the Player, and the
## hide with it — correct, and the same rule `notarget` follows.
static func _cmd_hud(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var player := _player(ctx)
	if player == null:
		return _one("hud: no player — the HUD is the Player's UI layer, and there is no player in the tree")
	var ui := _hud_layer(player)
	if ui == null:
		return _one("hud: the player's UI has no hide_hud_for_death() / restore_hud_after_death() seam — nothing this command can drive")
	if _hud_owned_by_death(player):
		return _one("hud: the death cinematic owns the HUD right now (Player._dying / _hud_quiet) — wait for the respawn")
	var state := _state(ctx)
	var hidden_now := state.has(STATE_HUD_HIDDEN)
	var held := _hud_held_paths(state)
	# `hud on` = shown, so the toggle's "current" is "is the HUD up".
	var on := bool(DebugCommandsScript.toggle_value("" if args.is_empty() else args[0], not hidden_now))
	var out := PackedStringArray()
	if on:
		if not hidden_now:
			return _one("hud is already ON (nothing hidden by `hud off`)")
		var shown := _hud_show(ui, held)
		state.erase(STATE_HUD_HIDDEN)
		out.append("hud ON — restored %d of the %d HUD node(s) `hud off` hid%s" % [
			shown, held.size(), "" if shown == held.size() else " (the rest were freed meanwhile — expired toasts, a money float)"])
		out.append("  crosshair re-derived from the live holster / dialogue state, not the snapshot; toasts pushed while hidden survive.")
		return out

	var newly := _hud_hide(ui)
	var merged := held.duplicate()
	for p in newly:
		if not merged.has(p):
			merged.append(p)
	state[STATE_HUD_HIDDEN] = merged
	if hidden_now:
		out.append("hud OFF — re-swept: hid %d node(s) that had come back (a conversation's close, or the Player's per-frame stealth / look-at / prompt / enemy-HP pushers, past the latch); %d held for `hud on`" % [newly.size(), merged.size()])
	else:
		out.append("hud OFF — hid %d direct child(ren) of %s: %s" % [newly.size(), String(ui.name), _hud_names(ui, newly)])
	out.append("  kept: the post-process ColorRect (colour steps / dither / grain — the LOOK, not the HUD). `hud on` restores exactly these.")
	out.append("  ! sneaking / a new look-at target / a prompt / a hit re-show their own label past the latch (Player-driven, gated on _dying, not on this) — `hud off` again re-sweeps; `screenshot clean` re-sweeps by itself.")
	out.append("  ! a death while hidden finds nothing to sweep, so the ring / minimap / clock / crosshair re-derive over the fade — `hud off` again after the revive.")
	return out


# --- lens: depth of field -------------------------------------------------------------------------------------

## Mirrors the CameraAttributesPractical authored in scenes/player/camera_rig.tscn, plus Godot's own defaults for
## the three fields that scene never writes. `dof reset` restores THIS rather than a snapshot taken at first touch:
## `ctx.state` is per-front-end, so a snapshot the MENU took after the CONSOLE had already dialled something would
## "restore" the console's value instead of the authored one. Same shape, and the same caveat, as
## SHADER_DEFAULT_BAYER_ORDER above: if camera_rig.tscn is re-authored this is cosmetic drift (a wrong `reset`
## target and a wrong report line), not a behaviour bug.
const DOF_AUTHORED := {
	# ABSENT from camera_rig.tscn -> engine default false. That is why the authored near_distance below has never
	# done anything: someone tuned a near blur and never wrote its switch (the same dead-knob shape as
	# `auto_exposure_max_sensitivity = 400.0` on the next line of that .tscn with `auto_exposure_enabled` absent).
	"near_enabled": false,
	"near_distance": 0.5,     # camera_rig.tscn -- authored, and dead until `dof near` flips the switch
	"near_transition": 1.0,   # absent -> engine default
	# The far half was RETIRED from camera_rig.tscn on 2026-08-24: its 30 m far blur was tuned when the main
	# level's volumetric fog had the far field ~78% covered, and the day the level dropped that fog the whole
	# distance rendered as naked mush ("things in the distance are WAY too blurry"). Both fields are now absent
	# from the .tscn -> engine defaults. ADS still gets far blur (set_scope_dof pushes it to
	# GameSettings.camera.dof_scoped_far_distance while scoped); only the RESTING state is blur-free.
	"far_enabled": false,     # absent -> engine default
	"far_distance": 10.0,     # absent -> engine default
	"far_transition": 5.0,    # absent -> engine default
	"amount": 0.1,            # absent -> engine default
}


## `dof [near|far|amount|off|on|reset] [value] [transition]` -- dial the camera's depth of field live.
##
## WHY THIS IS A LENS DIAL AND NOT A BLUR TOY. Defocus is the one depth cue the FOV slider cannot fake. In a
## pinhole projection an object's on-screen size is h / (2 d tan(fov/2)), so for ANY two objects the tan term
## cancels: FOV is a UNIFORM scale on the whole image and moves framing, never near-to-far separation. Blur is a
## function of distance, so it does separate them. THE NEAR HALF IS THE WHOLE EFFECT here: a windowed A/B
## (2026-08-20, when the rig still authored a 30 m far blur under volumetric fog) measured `near 1.0` at ~16%
## of frame change and `amount` alone at ~1.5%, because `amount` only strengthens blur that already exists and
## the far field was ~78% fog at that 30 m onset. Both far blur and the main level's fog are gone since
## 2026-08-24, which makes the near half MORE of the whole effect, not less.
## And it separates them where it is wanted: the weapon and the
## carry-hands render through ViewModelCamera's own Camera3D, built with NO CameraAttributes on purpose
## (scripts/camera/view_model_camera.gd:116-117), so everything here softens the WORLD while what is in your
## hands stays sharp.
##
## THE NEAR RAMP RUNS TOWARD THE LENS, which is the opposite of what the field names suggest. Godot's near blur
## is SHARP at dof_blur_near_distance and reaches FULL STRENGTH at (distance - transition), so a transition >= the
## distance puts full blur behind the camera and the effect never reaches full strength anywhere. camera_rig.tscn
## shipped in exactly that state (0.5 distance against the default 1.0 transition) on top of the missing switch --
## so `dof near <m>` auto-sizes the transition unless you give one, and always says where the ramp landed.
##
## THE FAR HALF IS SHARED WITH THE ADS. CameraEffects.set_scope_dof() rewrites dof_blur_far_enabled AND
## dof_blur_far_distance on every scope, and on unscope restores the PAIR it snapshotted in _ready()
## (`_dof_default_far_enabled` / `_dof_default_far_distance`). So every far-side verb here (`far <d>`, `far 0`,
## `off`, `on`, `reset`) writes that snapshot pair too (and `far <d>` REPORTS whether the write took) --
## otherwise the next ADS cycle would silently undo it and read as "the command did nothing". Unscope used to
## force the enabled flag TRUE unconditionally, which made `dof off` honest only until the next aim; since
## 2026-08-24 (far blur retired from camera_rig.tscn) the restore honours the snapshot, so far-side overrides
## hold. Nothing at runtime touches the NEAR fields, so a near override is stable without any snapshot.
##
## HOW LONG AN OVERRIDE LASTS -- longer than you expect, the same trap as `dither`. CameraAttributesPractical is
## a SUB-RESOURCE of the cached camera_rig.tscn PackedScene and is not resource_local_to_scene, so the camera a
## respawn or a level change builds carries the SAME attributes object, still holding whatever this wrote. An
## override therefore survives death, respawn and level transitions and only clears on a process restart or an
## explicit `dof reset`. No auto-restore on purpose: an A/B dial that snapped back on the next death is useless.
static func _cmd_dof(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var cam := _camera_effects(ctx)
	if cam == null:
		return _one("dof: no player camera -- depth of field lives on the CameraEffects Camera3D, and there is no player in the tree")
	var attrs := cam.attributes as CameraAttributesPractical
	if attrs == null:
		return _one("dof: the player camera carries no CameraAttributesPractical -- nothing to drive (camera_rig.tscn authors one; a scene edit must have dropped it)")

	var out := PackedStringArray()
	var verb := "" if args.is_empty() else args[0].strip_edges().to_lower()
	match verb:
		"amount":
			if args.size() < 2:
				out.append("dof amount needs a value 0-1. It scales the blur RADIUS at BOTH ends without moving where either one starts -- but it only makes EXISTING blur stronger, it cannot create any. Both ends ship OFF (the far half was retired 2026-08-24 with the main level's fog), so on the authored state this dial acts on nothing. Turn `dof near` or `dof far` on first; then it is worth something.")
			else:
				attrs.dof_blur_amount = clampf(float(args[1]), 0.0, 1.0)
				out.append("dof amount %.3f -- blur radius, both ends; the onset distances are untouched." % attrs.dof_blur_amount)
				if not attrs.dof_blur_near_enabled and not attrs.dof_blur_far_enabled:
					out.append("  ! BOTH ends are OFF (the shipped state), so this is scaling nothing at all. `dof near <m>` or `dof far <m>` first.")
				elif not attrs.dof_blur_near_enabled:
					out.append("  ! near blur is OFF, so this is only scaling the FAR blur. `dof near 1.0` for the depth cue.")
				if attrs.dof_blur_amount > 0.2:
					out.append("  ! past ~0.2 the near field crawls: project.godot ships use_taa=false, screen_space_aa=0 and msaa_3d=0, so nothing temporally stabilises a screen-space gather.")
		"near":
			if args.size() < 2:
				out.append("dof near needs a distance in metres, or 0 to switch it off. Sharp AT that distance, blurrier toward the lens.")
			else:
				var near_d := maxf(float(args[1]), 0.0)
				if near_d <= 0.0:
					attrs.dof_blur_near_enabled = false
					out.append("dof near OFF -- the world's near field is sharp again. Nothing at runtime rewrites the near fields, so this holds until you change it back or the process restarts.")
				else:
					var near_t := near_d * 0.75
					if args.size() >= 3:
						near_t = maxf(float(args[2]), 0.0)
					else:
						out.append("dof near: no transition given, so the ramp was auto-sized to %.2f m (0.75 x the distance) -- that is what makes it land in front of the lens instead of behind it." % near_t)
					attrs.dof_blur_near_enabled = true
					attrs.dof_blur_near_distance = near_d
					attrs.dof_blur_near_transition = near_t
					out.append("dof near ON -- sharp at %.2f m, ramping to full blur %.2f m from the lens." % [near_d, maxf(near_d - near_t, 0.0)])
					if near_t >= near_d:
						out.append("  ! transition >= distance, so full blur wants to land at %.2f m -- BEHIND the lens. The blur will never reach full strength anywhere in front of you. Pass a transition smaller than the distance." % (near_d - near_t))
		"far":
			if args.size() < 2:
				out.append("dof far needs a distance in metres, or 0 to switch it off. Sharp UNTIL that distance, full blur `transition` metres past it.")
			else:
				var far_d := maxf(float(args[1]), 0.0)
				if args.size() >= 3:
					attrs.dof_blur_far_transition = maxf(float(args[2]), 0.0)
				if far_d <= 0.0:
					attrs.dof_blur_far_enabled = false
					cam.set(&"_dof_default_far_enabled", false)
					out.append("dof far OFF -- and it HOLDS through aim cycles: unscope restores CameraEffects' snapshot pair, and this just wrote enabled=false into it. (That is also the shipped state since 2026-08-24.)")
				else:
					attrs.dof_blur_far_enabled = true
					attrs.dof_blur_far_distance = far_d
					cam.set(&"_dof_default_far_enabled", true)
					cam.set(&"_dof_default_far_distance", far_d)
					out.append("dof far ON -- sharp until %.2f m, full blur by %.2f m." % [far_d, far_d + attrs.dof_blur_far_transition])
					# Report whether the snapshot write actually took: set() on a property this camera does not
					# have is a silent no-op, and the symptom would be "it reverted after I aimed once".
					var snap: Variant = cam.get(&"_dof_default_far_distance")
					if snap is float and is_equal_approx(float(snap), far_d):
						out.append("  also wrote CameraEffects' _dof_default_far_enabled/_distance snapshot pair, so the next unscope restores THIS far blur instead of the authored state (far off).")
					else:
						out.append("  ! this camera has no _dof_default_far_distance to update, so the first unscope after an ADS will restore the authored state (far blur OFF) and undo the line above.")
		"off":
			attrs.dof_blur_near_enabled = false
			attrs.dof_blur_far_enabled = false
			cam.set(&"_dof_default_far_enabled", false)
			out.append("dof OFF at both ends -- the A/B kill switch, NOT a restore (`dof reset` puts the authored values back).")
			out.append("  holds through aim cycles: the far half's unscope-restore snapshot was set to off too. (Off IS the shipped state at both ends.)")
		"on":
			attrs.dof_blur_near_enabled = true
			attrs.dof_blur_far_enabled = true
			cam.set(&"_dof_default_far_enabled", true)
			out.append("dof ON at both ends, at the CURRENT distances -- not the authored ones (which ship both ends OFF). `dof reset` for those. The far half's unscope-restore snapshot was switched ON but keeps its own distance (the last `dof far <d>`, or the authored one), so an aim cycle lands the far blur THERE -- `dof far <d>` to pin a distance.")
		"reset":
			attrs.dof_blur_near_enabled = bool(DOF_AUTHORED["near_enabled"])
			attrs.dof_blur_near_distance = float(DOF_AUTHORED["near_distance"])
			attrs.dof_blur_near_transition = float(DOF_AUTHORED["near_transition"])
			attrs.dof_blur_far_enabled = bool(DOF_AUTHORED["far_enabled"])
			attrs.dof_blur_far_distance = float(DOF_AUTHORED["far_distance"])
			attrs.dof_blur_far_transition = float(DOF_AUTHORED["far_transition"])
			attrs.dof_blur_amount = float(DOF_AUTHORED["amount"])
			cam.set(&"_dof_default_far_enabled", bool(DOF_AUTHORED["far_enabled"]))
			cam.set(&"_dof_default_far_distance", float(DOF_AUTHORED["far_distance"]))
			out.append("dof reset -- camera_rig.tscn's authored state is back: BOTH ends off. The near half has been dead since the day it was typed (authored near_distance 0.5, switch never written); the far half was retired 2026-08-24 when the main level dropped the volumetric fog that had been hiding its 30 m blur.")

	out.append_array(_dof_report(ctx, attrs))
	return out


## The always-printed live block. The whole point of the command is A/B-ing a look, so every run ends by saying
## what the lens is actually doing -- including the two things that decide whether a change is even visible: what
## is EXEMPT from it (the view model) and whether the volumetric fog has already swallowed the far field.
static func _dof_report(ctx: Dictionary, attrs: CameraAttributesPractical) -> PackedStringArray:
	var out := PackedStringArray()
	var near_text := "off"
	if attrs.dof_blur_near_enabled:
		near_text = "on, sharp at %.2f m -> full %.2f m" % [
			attrs.dof_blur_near_distance, maxf(attrs.dof_blur_near_distance - attrs.dof_blur_near_transition, 0.0)]
	var far_text := "off"
	if attrs.dof_blur_far_enabled:
		far_text = "on, sharp to %.1f m -> full %.1f m" % [
			attrs.dof_blur_far_distance, attrs.dof_blur_far_distance + attrs.dof_blur_far_transition]
	out.append("live: amount %.3f | near %s | far %s" % [attrs.dof_blur_amount, near_text, far_text])
	out.append("  the view model is IMMUNE by construction -- the gun and the carry-hands render through ViewModelCamera's own Camera3D, built with no CameraAttributes on purpose. Only the WORLD softens, which is the whole near/far separation.")

	# Is there anything left out there to blur? On a level that runs volumetric fog (TestLevel does; the main
	# level dropped its 2026-08-24), the engine-default 0.05/m density has the far field most of the way to
	# opaque well before a far blur even starts -- which is the difference between "the far blur did nothing"
	# and "the far blur is not the problem". Self-gating: prints only when fog AND far blur are both live.
	var env := _lens_world_env(ctx)
	if env != null and env.volumetric_fog_enabled and attrs.dof_blur_far_enabled and attrs.dof_blur_far_distance > 0.0:
		var opacity := 1.0 - exp(-maxf(env.volumetric_fog_density, 0.0) * attrs.dof_blur_far_distance)
		out.append("  fog check: volumetric fog (density %.3f/m) is already %d%% opaque at the far onset (%.1f m) -- the more of that there is, the less a far blur can add, and the far field is ALSO softened by the PS1 snap fade (20-40 m) and the ink fade (40-90 m)." % [
			env.volumetric_fog_density, int(round(opacity * 100.0)), attrs.dof_blur_far_distance])
	out.append("  overrides survive death, respawn and level changes (shared sub-resource of the cached camera_rig.tscn) -- only a process restart or `dof reset` clears them. Commit what you like into scenes/player/camera_rig.tscn.")
	return out


# --- lens: view-model mouse sway ------------------------------------------------------------------------------

## GunPose's @export names behind the short words this command takes. Kept as a table so `sway` and its report
## cannot drift on a spelling, and so a knob added here is one row rather than two match arms.
const SWAY_KNOBS := {
	"pos": &"mouse_sway_pos",
	"max": &"mouse_sway_max",
	"roll": &"mouse_sway_roll_deg",
	"pitch": &"mouse_sway_pitch_deg",
	"decay": &"mouse_sway_decay",
}
## Mirrors the @export defaults in scripts/effects/gun_pose.gd. GunPose is built with .new() by GunMesh, so it
## has NO .tscn override surface anywhere in the project -- these script defaults ARE the shipped values, and
## `sway reset` restores them. Cosmetic drift if gun_pose.gd is re-tuned, same as DOF_AUTHORED above.
const SWAY_AUTHORED := {"pos": 0.04, "max": 0.35, "roll": 0.0, "pitch": 0.0, "decay": 12.0}
## Three graded settings for A/B, indexed by `sway preset N`. Peak hip-fire lag is pos x max: 26 mm / 38 mm /
## 55 mm against the shipped 14 mm. Roll and pitch ship at literal 0.0, so every preset switches on two channels
## that have never run.
const SWAY_PRESETS: Array[Dictionary] = [
	{"pos": 0.065, "max": 0.40, "roll": 1.0, "pitch": 0.6, "decay": 10.0},
	{"pos": 0.085, "max": 0.45, "roll": 1.6, "pitch": 1.0, "decay": 9.0},
	{"pos": 0.110, "max": 0.50, "roll": 2.4, "pitch": 1.5, "decay": 8.0},
]
const SWAY_PRESET_NAMES: Array[String] = ["timid", "recommended", "loud"]


## `sway [pos|max|roll|pitch|decay|preset|off|reset] [value]` -- dial how far the view model lags behind a turn.
##
## WHY A GUN LAG IS A DEPTH CUE. Turning is by far the most frequent camera motion in the game, and a pure yaw
## carries ZERO parallax: every depth sweeps the screen at the same angular rate, so a turn tells the eye nothing
## about distance. The only near-to-far separation a turn can produce is a NEAR object that fails to keep up with
## it. GunPose already has the whole mechanism -- it accumulates MouseInput.rotate into `_mouse_sway`, clamps it to
## mouse_sway_max, decays it, and converts it into a gun offset -- but it ships at 0.04 x 0.35 = 14 mm of travel
## with the roll and pitch channels at literal 0.0. The feature is wired and switched almost off.
##
## THIS DOES NOT SURVIVE A DEATH, A RESPAWN OR A LEVEL CHANGE -- the exact opposite of `dof` on the same menu
## page, and worth knowing before you conclude a preset "stopped working". GunMesh builds a FRESH GunPose with
## GunPose.new() every time it is set up, so a new Player comes up on the script defaults. `dof` overrides ride a
## shared PackedScene sub-resource and outlive everything; these ride a node that gets rebuilt.
##
## MOUSE SWAY SITS OUTSIDE EVERY ACCESSIBILITY GATE. Settings.view_bob_enabled reaches only GunPose's walk-bob
## factor; the `_mouse_sway` decay and the four mouse_off / roll / pitch terms run unconditionally, and
## Settings.fov_effects_enabled never reaches GunPose at all. That is survivable at the shipped 14 mm. Committing
## a preset without adding the gate to gun_pose.gd first is a straight regression for motion-sensitive players,
## and rotation-linked view-model motion provokes more than translation-linked bob does.
##
## It moves the gun MODEL only: the shot ray is AimSway's, and the crosshair never moves. ADS damps the whole
## block by ads_sway_mult (0.35 as shipped), so the aimed peak stays near today's hip-fire number whatever you
## dial here -- the report prints both.
static func _cmd_sway(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var pose := _gun_pose(ctx)
	if pose == null:
		return _one("sway: no GunPose -- mouse sway lives on the pose node GunMesh builds under the player's view model, and there is no player (or no gun mesh) in the tree")

	var out := PackedStringArray()
	var verb := "" if args.is_empty() else args[0].strip_edges().to_lower()
	var knob: StringName = SWAY_KNOBS.get(verb, &"")
	if knob != &"":
		if args.size() < 2:
			out.append("sway %s needs a value -- live is %.3f, authored is %.3f." % [verb, _float_of(pose.get(knob)), float(SWAY_AUTHORED[verb])])
		else:
			var v := maxf(float(args[1]), 0.0)
			pose.set(knob, v)
			out.append("sway %s %.3f (authored %.3f)" % [verb, v, float(SWAY_AUTHORED[verb])])
	else:
		match verb:
			"preset":
				if args.size() < 2:
					out.append("sway preset needs an index: 0 %s, 1 %s, 2 %s." % SWAY_PRESET_NAMES)
				else:
					var idx := int(float(args[1]))
					if idx < 0 or idx >= SWAY_PRESETS.size():
						out.append("sway preset must be 0, 1 or 2 (%s) -- got \"%s\", nothing changed." % [", ".join(SWAY_PRESET_NAMES), args[1]])
					else:
						_sway_apply(pose, SWAY_PRESETS[idx])
						out.append("sway preset %d (%s) applied -- all five knobs at once, so the A/B is one command each way (`sway reset` for the shipped feel)." % [idx, SWAY_PRESET_NAMES[idx]])
			"off":
				_sway_apply(pose, {"pos": 0.0, "max": SWAY_AUTHORED["max"], "roll": 0.0, "pitch": 0.0, "decay": SWAY_AUTHORED["decay"]})
				out.append("sway OFF -- the gun is welded to the camera. The A/B floor: turn hard with this on, then `sway preset 1`, and the difference IS the depth cue.")
			"reset":
				_sway_apply(pose, SWAY_AUTHORED)
				out.append("sway reset -- gun_pose.gd's shipped defaults are back (roll and pitch to literal 0.0, which is how they ship).")

	out.append_array(_sway_report(pose))
	return out


## Write one knob table onto the live GunPose. Missing keys are left alone, so a partial table is a partial write
## rather than a silent zeroing.
static func _sway_apply(pose: Node, values: Dictionary) -> void:
	for word in SWAY_KNOBS:
		if values.has(word):
			pose.set(SWAY_KNOBS[word], float(values[word]))


## The always-printed live block, in the units that actually decide the feel: peak lag is pos x max (that product
## is the number to compare, not either factor), and the aimed peak is that times ads_sway_mult.
static func _sway_report(pose: Node) -> PackedStringArray:
	var pos := _float_of(pose.get(&"mouse_sway_pos"))
	var cap := _float_of(pose.get(&"mouse_sway_max"))
	var ads := _float_of(pose.get(&"ads_sway_mult"), 0.35)
	var peak := pos * cap
	var out := PackedStringArray()
	out.append("live: pos %.3f | max %.2f | roll %.2f deg | pitch %.2f deg | decay %.1f" % [
		pos, cap, _float_of(pose.get(&"mouse_sway_roll_deg")), _float_of(pose.get(&"mouse_sway_pitch_deg")),
		_float_of(pose.get(&"mouse_sway_decay"))])
	out.append("  peak lag %.1f mm hip-fire (pos x max) | %.1f mm aimed (x ads_sway_mult %.2f) | shipped is %.1f mm" % [
		peak * 1000.0, peak * ads * 1000.0, ads, float(SWAY_AUTHORED["pos"]) * float(SWAY_AUTHORED["max"]) * 1000.0])
	out.append("  ! gone on death / respawn / level change -- GunMesh rebuilds GunPose from the script defaults each time (unlike `dof`, which outlives all three).")
	out.append("  ! outside every accessibility gate: Settings.view_bob_enabled reaches only the walk-bob. Add the gate in gun_pose.gd before committing a raised value.")
	out.append("  gun MODEL only -- the shot ray is AimSway's and the crosshair never moves.")
	return out


## The player's main Camera3D (a CameraEffects), or null off-level / on the main menu. Typed as Camera3D rather
## than CameraEffects so a host that swapped the script still yields its `attributes`; the two CameraEffects
## privates this file pokes go through set()/get(), which degrade to a no-op and a null instead of a parse error.
static func _camera_effects(ctx: Dictionary) -> Camera3D:
	var player := _player(ctx)
	if player == null:
		return null
	var raw: Variant = player.get(&"camera_effects")
	if raw == null or not is_instance_valid(raw):
		return null
	return raw as Camera3D


## The live GunPose node GunMesh builds under the view model, or null when there is no player / no gun mesh.
## Reached duck-typed through a private member on purpose: `_pose` is GunMesh-internal and there is no public
## accessor, and a typed hop would turn a missing host into a parse-time dependency rather than a null here.
static func _gun_pose(ctx: Dictionary) -> Node:
	var player := _player(ctx)
	if player == null:
		return null
	var raw_mesh: Variant = player.get(&"gun_mesh")
	if raw_mesh == null or not is_instance_valid(raw_mesh):
		return null
	var mesh := raw_mesh as Node
	if mesh == null:
		return null
	var raw_pose: Variant = mesh.get(&"_pose")
	if raw_pose == null or not is_instance_valid(raw_pose):
		return null
	return raw_pose as Node


## The level's Environment, or null. Read only to REPORT how much fog is already sitting in front of the far
## blur -- this command never writes it (CameraEffects owns the scoped fog thin, and two writers would fight).
static func _lens_world_env(ctx: Dictionary) -> Environment:
	var tree := _tree(ctx)
	if tree == null:
		return null
	var we := tree.get_first_node_in_group(GroupsScript.WORLD_ENVIRONMENT) as WorldEnvironment
	if we == null:
		return null
	return we.environment


# --- lens: the world barrel (fisheye) warp ---------------------------------------------------------------------

## Mirrors the @export defaults in resources/tuning/CameraSettings.gd ("Lens" group). `lens reset` restores THESE
## rather than a snapshot: `ctx.state` is per-front-end, so a snapshot the MENU took after the CONSOLE had already
## dialled something would restore the console's value. Cosmetic drift if CameraSettings.gd is re-tuned, the same
## caveat as DOF_AUTHORED and SHADER_DEFAULT_BAYER_ORDER above.
##
## ⭐ resources/tuning/CameraSettings.tres carries NO property overrides at all, so these .gd defaults really are
## the shipped values — there is no second place to look.
const LENS_AUTHORED := {"barrel": 0.12, "chroma": 0.35}


## `lens [barrel] [chroma]` — dial the world's barrel (fisheye) lens live.
##
## WHAT IT IS. post_process.gdshader bends the SCREEN FETCH radially: the centre of the frame is magnified and the
## periphery squeezed, so straight lines off the centre bow outward. That is the only way to get a fisheye here —
## a Camera3D cannot do it. FOV is a UNIFORM scale on the projected image (`h / (2 d tan(fov/2))`: for any two
## points the tan term cancels), so no field-of-view number bends a straight line; it just changes how much you
## can see. The bend has to happen after projection, which is why it lives in the post-process.
##
## ⭐ THE NUMBER IS CENTRE MAGNIFICATION MINUS ONE. The shader normalises the bend by the corner and divides by
## its own value there, so `0.12` reads as "the middle of the frame is ~12% bigger" and the CORNERS STAY PINNED.
## Pinning is not cosmetic: SCREEN_TEXTURE is `repeat_disable`, so a fetch running past the edge would smear the
## border texel down the whole side. It also means this can never produce a black edge, at any strength.
##
## ⭐ WRITES THE SOURCE, NOT THE MATERIAL — and that is the whole reason this function is not two lines.
## player.gd re-pushes `lens_barrel` onto the material EVERY FRAME (`_update_low_hp`, beside contrast / dither /
## quantize_levels), so a direct `set_shader_parameter` here would be overwritten on the very next frame and read
## as "the command did nothing" — the same coupling `_cmd_dither` documents for dither strength. So this writes
## `GameSettings.camera.lens_barrel_amount` / `lens_chroma_amount`, which is what player.gd multiplies.
##
## ⭐ WHICH MEANS THE PLAYER'S SLIDER CAN VETO IT. The pushed value is `amount x Settings.lens_curve`
## (Options -> Accessibility -> "Lens Curve"). At lens_curve 0 the frame is flat no matter what you type here, so
## the report always prints both numbers and the product, and says so outright when the scale is what is winning.
##
## ⭐ HOW LONG IT LASTS: the whole PROCESS, and no further. `GameSettings.camera` is a preloaded Resource shared
## by every scene, so an override survives death, respawn and level changes (the same lifetime as a `dof` override
## and the opposite of `sway`) — but nothing ever writes it to disk. To keep a value, put it in
## resources/tuning/CameraSettings.tres in the Inspector, or change the @export default in CameraSettings.gd.
static func _cmd_lens(_ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var cam_set: Variant = GameSettings.get(&"camera")
	if cam_set == null:
		return _one("lens: GameSettings has no `camera` group — nothing to drive (a reimport transient; try again in a second)")
	var out := PackedStringArray()
	if not args.is_empty():
		var barrel := maxf(float(args[0]), -0.25)
		(cam_set as Resource).set(&"lens_barrel_amount", barrel)
		if barrel <= 0.0:
			out.append("lens FLAT — the shader early-outs to a plain screen fetch, so the frame is pixel-identical to a build without the feature (and costs nothing).")
		else:
			out.append("lens barrel %.3f — the centre of the frame reads ~%.0f%% bigger, corners pinned." % [barrel, barrel * 100.0])
			if barrel > 0.35:
				out.append("  ! past ~0.35 the periphery smears rather than bends: the bend is squeezing more source pixels into fewer output ones, and SCREEN_TEXTURE is point-filtered.")
	if args.size() >= 2:
		var chroma := clampf(float(args[1]), 0.0, 1.0)
		(cam_set as Resource).set(&"lens_chroma_amount", chroma)
		out.append("lens chroma %.2f — the colour fringe, as a fraction of the bend, so it grows with the curve and vanishes with it. This is what makes a warp read as GLASS." % chroma)

	# Always report: this command writes the AUTHORED amount, the player's slider scales it, and only the product
	# reaches the GPU. Printing one of the three is how someone concludes the command is broken.
	var live_barrel := _float_of((cam_set as Resource).get(&"lens_barrel_amount"))
	var live_chroma := _float_of((cam_set as Resource).get(&"lens_chroma_amount"))
	var scale := _float_of(Settings.get(&"lens_curve"), 1.0)
	out.append("live: barrel %.3f x Lens Curve %.2f = %.3f reaching the shader | chroma %.2f | authored %.3f / %.2f" % [
		live_barrel, scale, live_barrel * scale, live_chroma,
		float(LENS_AUTHORED["barrel"]), float(LENS_AUTHORED["chroma"])])
	if live_barrel > 0.0 and scale <= 0.0:
		out.append("  ! Options -> Accessibility -> \"Lens Curve\" is at 0, so the frame is FLAT whatever you type here. That slider is the veto.")
	out.append("  the HUD does not bend with it: the post-process ColorRect and the HUD share one CanvasLayer, but the HUD draws ABOVE this shader. The crosshair sits at the centre, which is the one point a radial warp never moves.")
	out.append("  in-memory for the whole PROCESS — survives death, respawn and level changes (GameSettings.camera is a shared preloaded Resource) and is never written to disk. Commit a value in resources/tuning/CameraSettings.tres.")
	return out


# --- dither ---------------------------------------------------------------------------------------------------

## `dither [strength] [grid]` — tune the ordered (Bayer) dither the screen post-process quantises through, live.
##
## TWO KNOBS WITH TWO DIFFERENT HOMES, and mixing them up is the trap this comment exists for:
##  - STRENGTH is the PLAYER's dial (Options -> Video -> Dithering), so it is written through
##    `Settings.set_dither_strength` and NEVER onto the material. player.gd pushes `Settings.dither_strength` onto
##    this exact uniform EVERY FRAME (_update_low_hp), so a direct material write would be stomped on the next
##    frame and read as "the command did nothing". Writing Settings also persists it, like the Options slider.
##  - GRID is the MATERIAL's authored art choice (`bayer_order`, set in scenes/player/ui.tscn), which nothing
##    polls — so it goes straight onto the material. Deliberately NOT written to Settings: it is a palette
##    decision to eyeball here and then commit to the .tscn, not a player preference.
##
## ⭐ HOW LONG A GRID OVERRIDE LASTS, precisely — it is longer than you expect. The ShaderMaterial is a
## SUB-RESOURCE OF THE CACHED PackedScene, so the fresh player instantiated by a respawn or a level change gets
## the SAME material object, still carrying whatever this command wrote. (That is the documented shape of the old
## "respawned to a black screen" bug — see player.gd _restart_scene.) An override therefore survives death,
## respawn and level transitions, and only clears when the PROCESS restarts. There is no auto-restore on
## purpose: an A/B dial that silently snapped back on the next death would be useless. To hand the art back,
## re-run the command with the authored grid, which the report line below always prints.
##
## `grid` is typed as the matrix WIDTH (2 / 4 / 8 — what you see) and stored as the ORDER IN BITS (1 / 2 / 3 —
## what the shader loops over); 0 turns the matrix off at the material and leaves plain round-to-nearest banding.
static func _cmd_dither(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var mat := _post_process_material(ctx)
	if mat == null:
		return _one("dither: no post-process material — the Bayer dither lives on the player's UI/ColorRect, and there is no player (or no shaded ColorRect) in the tree")
	var out := PackedStringArray()
	if not args.is_empty():
		var strength := clampf(float(args[0]), 0.0, 1.0)
		Settings.set_dither_strength(strength)
		out.append("dither strength %.2f -> Settings (Options -> Video -> Dithering), saved; player.gd pushes it to the shader next frame." % strength)
	if args.size() >= 2:
		var grid := int(float(args[1]))
		# Typed target, never `:=` off a Dictionary read: Dictionary.get() is a Variant, so `:=` would infer
		# Variant and `as int` is not a cast GDScript offers for a built-in type.
		var order: int = GRID_TO_BAYER_ORDER.get(grid, -1)
		if order < 0:
			out.append("dither: grid must be 2, 4 or 8 (the matrix width), or 0 for off — got \"%s\", grid left unchanged." % args[1])
		elif order == 0:
			mat.set_shader_parameter("bayer_order", 0)
			out.append("dither grid OFF (bayer_order 0) — the frame now quantises by plain round-to-nearest, i.e. visible banding.")
		else:
			mat.set_shader_parameter("bayer_order", order)
			out.append("dither grid %dx%d (bayer_order %d) — on the material, and it OUTLIVES death / respawn / a level change (cached PackedScene sub-resource); only a process restart clears it. Commit it to scenes/player/ui.tscn to keep it for real." % [grid, grid, order])
	# Always report the resulting state: the whole point of the command is A/B-ing a look, and the two knobs live
	# in different places, so seeing them side by side is what stops the next person writing grid into Settings.
	# get_shader_parameter answers null for a uniform the MATERIAL never overrode (it does not fall through to the
	# shader's own default), so every read here degrades explicitly rather than printing "0" / "false" as if the
	# material had said so.
	var live_order := _int_of(mat.get_shader_parameter("bayer_order"), -1)
	var order_text := str(live_order)
	var shown_order := live_order
	if live_order < 0:
		shown_order = SHADER_DEFAULT_BAYER_ORDER
		order_text = "%d (shader default — the material carries no override)" % SHADER_DEFAULT_BAYER_ORDER
	var grid_text := "off"
	if shown_order > 0:
		grid_text = "%dx%d" % [1 << shown_order, 1 << shown_order]
	var enabled_raw: Variant = mat.get_shader_parameter("enable_dithering")
	var enabled := true if enabled_raw == null else bool(enabled_raw)
	out.append("live: strength %.2f | grid %s (bayer_order %s) | enable_dithering %s | color_steps %d" % [
		Settings.dither_strength, grid_text, order_text, str(enabled),
		_int_of(mat.get_shader_parameter("color_steps"), 0)])
	out.append("  the dither only has something to do where the palette BANDS — fewer colour steps = a louder pattern.")
	out.append("  authored grid is %dx%d (scenes/player/ui.tscn) — re-run `dither %.2f %d` to hand a grid override back." % [
		1 << SHADER_DEFAULT_BAYER_ORDER, 1 << SHADER_DEFAULT_BAYER_ORDER,
		Settings.dither_strength, 1 << SHADER_DEFAULT_BAYER_ORDER])
	return out


## Matrix WIDTH (what a human types) -> `bayer_order` (the bit count the shader loops over). 0 is a real entry: it
## is how the command turns the matrix off, and it must not collide with the "unknown grid" -1.
const GRID_TO_BAYER_ORDER := {0: 0, 2: 1, 4: 2, 8: 3}
## Mirrors `uniform int bayer_order ... = 3` in post_process.gdshader — used only to LABEL a material that carries
## no override of its own (get_shader_parameter answers null there, not the shader default). If the shader default
## ever changes, this line is cosmetic drift, not a behaviour bug.
const SHADER_DEFAULT_BAYER_ORDER := 3


## The ShaderMaterial on the player's post-process ColorRect (`UI/ColorRect` — the same node player.gd caches as
## `_nv_rect` and drives night vision / hurt / low-HP / the death fade through). Null off-level, on the main menu,
## or if the ColorRect ever loses its material. Kept separate from `_hud_layer` because this is explicitly the
## node `hud off` REFUSES to touch: it is the LOOK, not the HUD.
static func _post_process_material(ctx: Dictionary) -> ShaderMaterial:
	var player := _player(ctx)
	if player == null:
		return null
	var rect := player.get_node_or_null("UI/ColorRect") as CanvasItem
	if rect == null:
		return null
	return rect.material as ShaderMaterial


## The player's UI CanvasLayer, or null when there is none or it lacks the two-method seam this command rides on.
static func _hud_layer(player: Node) -> Node:
	if player == null or not is_instance_valid(player):
		return null
	var raw: Variant = player.get(&"ui")
	if raw == null or not is_instance_valid(raw):
		return null
	var ui := raw as Node
	if ui == null or not ui.has_method(&"hide_hud_for_death") or not ui.has_method(&"restore_hud_after_death"):
		return null
	return ui


## True while the death cinematic or the revive quiet window owns the HUD (player.gd:2455 `_dying`, :2479
## `_hud_quiet`) — the two windows in which the UI's death list belongs to the cinematic, not to us.
static func _hud_owned_by_death(player: Node) -> bool:
	return player != null and is_instance_valid(player) and (_bool_of(player.get(&"_dying")) or _bool_of(player.get(&"_hud_quiet")))


## The paths `hud off` is holding, as a fresh PackedStringArray (empty when none, or when the state was clobbered).
static func _hud_held_paths(state: Dictionary) -> PackedStringArray:
	var raw: Variant = state.get(STATE_HUD_HIDDEN)
	if raw is PackedStringArray:
		return (raw as PackedStringArray).duplicate()
	return PackedStringArray()


## Run the UI's own death sweep (hides every VISIBLE direct CanvasItem child except the post-process ColorRect and
## arms the per-frame bail latch — see _cmd_hud) and read back WHAT it hid as UI-relative node paths. The list is
## the UI's private `_death_hidden_hud` (Array[CanvasItem]), read duck-typed; if it cannot be read the sweep still
## happened and the caller's snapshot is simply empty — _hud_show then falls back to the public restore.
##
## ⭐ONLY when the latch is NOT already armed. hide_hud_for_death() `.clear()`s the list FIRST and re-records just what
## is visible NOW — so a second call while a hide is in force (a repeated `hud off`, two `screenshot clean`s in one
## exec tick) drops every earlier node off the UI's own list, and when nothing new is visible leaves it EMPTY: the
## latch RELEASED with the HUD still down, and the ring / minimap / clock / crosshair re-derive on the very next
## frame. An armed latch is therefore extended by the non-clobbering _hud_sweep_more instead.
static func _hud_hide(ui: Node) -> PackedStringArray:
	var raw: Variant = ui.get(&"_death_hidden_hud")
	if raw is Array and not (raw as Array).is_empty():
		return _hud_sweep_more(ui)
	ui.call(&"hide_hud_for_death")
	var out := PackedStringArray()
	raw = ui.get(&"_death_hidden_hud")
	if raw is Array:
		for ci in (raw as Array):
			if ci != null and is_instance_valid(ci) and ci is Node:
				out.append(String(ui.get_path_to(ci)))
	return out


## The NON-CLOBBERING sweep: hide every VISIBLE direct CanvasItem child except the post-process ColorRect — the same
## rule as ui.hide_hud_for_death() (ui.gd:649-657), mirrored rather than called because that call `.clear()`s the
## death list first (see _hud_hide) — and APPEND each to the UI's list so the bail latch stays armed and grows.
## Used wherever a hide is already in force: the `hud off` re-sweep, and the screenshot driver's second pass (the
## Player's per-frame HUD pushers — set_stealth_level / set_detection_meter every physics tick, the look-at name,
## the takedown / pet / claim cues, the enemy HP bar — write `visible` on direct children of this layer PAST the
## latch, because they gate on the PLAYER's `_dying` / `_hud_quiet`, which nothing here may set). Returns the
## UI-relative paths of what it hid. If the private list cannot be read the nodes are still hidden (the caller's
## path snapshot restores them) — only the latch is not extended.
static func _hud_sweep_more(ui: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var keep := ui.get_node_or_null(^"ColorRect")
	# The UI's OWN list when readable (Arrays are references — appending here extends the latch); a throwaway
	# otherwise, so the loop below needs no second branch.
	var latch: Array = []
	var raw: Variant = ui.get(&"_death_hidden_hud")
	if raw is Array:
		latch = raw
	for child in ui.get_children():
		if child == keep or not (child is CanvasItem):
			continue
		var ci := child as CanvasItem
		if not ci.visible:
			continue
		ci.visible = false
		if not latch.has(ci):
			latch.append(ci)
		out.append(String(ui.get_path_to(ci)))
	return out


## Show every path in `paths` that still resolves (freed toasts / floats are skipped), then hand the HUD back to its
## per-frame drivers: empty the bail latch and re-derive the crosshair from the live holster / dialogue latches
## (they kept updating while the apply bailed, ui.gd:1012 — a weapon holstered under the hide must come back with
## NO crosshair, so the snapshot's `visible` is deliberately not the last word for it). Returns how many resolved.
##
## This is restore_hud_after_death() MINUS its _purge_transient_notices(): that purge frees every live toast + the
## money float, which is right for a revive and wrong for a `hud on` or a one-frame screenshot. So the latch is
## cleared directly (duck-typed, same private list _hud_hide reads) and the UI's own re-derive is called; anything
## still in the UI's list (a death mid-hide can leave a subset there) is shown too so no swept node stays dark
## whichever list it landed in. Only when the private list is unreadable does this fall back to the public
## restore_hud_after_death() — the latch MUST be released, or the ring / minimap / clock stay hidden for good.
static func _hud_show(ui: Node, paths: PackedStringArray) -> int:
	var shown := 0
	for p in paths:
		var n := ui.get_node_or_null(NodePath(p))
		if n != null and n is CanvasItem:
			(n as CanvasItem).visible = true
			shown += 1
	var raw: Variant = ui.get(&"_death_hidden_hud")
	if raw is Array:
		var latch: Array = raw
		for ci in latch:
			if ci != null and is_instance_valid(ci) and ci is CanvasItem:
				(ci as CanvasItem).visible = true
		latch.clear()
		if ui.has_method(&"_apply_crosshair_visibility"):
			ui.call(&"_apply_crosshair_visibility")
	else:
		ui.call(&"restore_hud_after_death")
	return shown


## The mid-capture-death hand-off (see _ShotDriver._restore): append our still-hidden nodes to the UI's death list
## so the revive's restore_hud_after_death() shows them. Duck-typed on the same private list; a no-op if unreadable
## (then the nodes come back on the next `hud off` / `hud on` round trip or the reload).
static func _hud_adopt_into_death_sweep(ui: Node, paths: PackedStringArray) -> void:
	var raw: Variant = ui.get(&"_death_hidden_hud")
	if not (raw is Array):
		return
	var latch: Array = raw
	for p in paths:
		var n := ui.get_node_or_null(NodePath(p))
		if n != null and n is CanvasItem and not latch.has(n):
			latch.append(n)


## "HP, AMMO, BloodSplatter, ColorRect, Label, ... +N more" — the swept nodes by name, or by CLASS for the code-built
## ones (their auto names, "@Label@42", say nothing). Capped so a 30-node sweep is one readable line.
const HUD_NAMES_MAX := 12
static func _hud_names(ui: Node, paths: PackedStringArray) -> String:
	var bits := PackedStringArray()
	for p in paths:
		if bits.size() >= HUD_NAMES_MAX:
			bits.append("+%d more" % (paths.size() - HUD_NAMES_MAX))
			break
		var n := ui.get_node_or_null(NodePath(p))
		if n == null:
			continue
		var label := String(n.name)
		if label.begins_with("@"):
			label = n.get_class()
		bits.append(label)
	return ", ".join(bits) if not bits.is_empty() else "(nothing was visible)"


# =============================================================================================================
# META (world side) — the session's error trail and the profile's disk-write telemetry
# =============================================================================================================

## `errors [count]` — the last N entries of the F3 overlay's ErrorSink, default this many.
const ERRORS_DEFAULT_COUNT := 10

## Dump the tail of the ErrorSink ring buffer. The sink is OWNED by the shipped DebugOverlay (game.tscn carries one;
## `perf` creates one when none exists) and is a debug-build-only install, so both "no overlay" and "no sink" are
## legitimate states this command reports rather than errors. Read duck-typed off the overlay's private `_sink`
## (there is no getter) and off the sink's fields, so an ErrorSink API drift degrades to a line.
static func _cmd_errors(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var tree := _tree(ctx)
	if tree == null:
		return _one("no SceneTree")
	# The shipped overlay lives under the current scene; fall back to the whole tree for a designer who parented
	# it elsewhere (an autoload, a persistent HUD layer). Matched by SCRIPT, never by name.
	var ov := _find_by_script(tree.current_scene, DebugOverlayScript)
	if ov == null:
		ov = _find_by_script(tree.root, DebugOverlayScript)
	if ov == null:
		return _one("no DebugOverlay in the tree (game.tscn ships one; `perf` creates one) — there is no ErrorSink to read")
	var sink: Variant = ov.get(&"_sink")
	if sink == null or not is_instance_valid(sink):
		return _one("the DebugOverlay has no ErrorSink installed (release build, or capture_errors is off) — nothing is being captured")
	if not sink.has_method(&"recent"):
		return _one("the ErrorSink has no recent() — API drift between error_sink.gd and this command")

	var out := PackedStringArray()
	var errors := _int_of(sink.get(&"error_count"))
	var warnings := _int_of(sink.get(&"warning_count"))
	out.append("errors %d   warnings %d   (this session, since the overlay booted)" % [errors, warnings])
	var raw_recent: Variant = sink.call(&"recent")
	if not (raw_recent is Array):
		out.append("recent() did not return an Array — nothing to list")
		return out
	var recent: Array = raw_recent
	if recent.is_empty():
		out.append("nothing captured — no push_error / push_warning / engine error has fired since the sink installed")
		return out
	var count := ERRORS_DEFAULT_COUNT if args.is_empty() else maxi(1, int(args[0].to_float()))
	var n := mini(count, recent.size())
	var kept := _int_of(sink.get(&"_max_recent"), recent.size())
	out.append("-- last %d of %d kept (ring buffer holds %d; newest last)" % [n, recent.size(), kept])
	for i in range(recent.size() - n, recent.size()):
		var e: Variant = recent[i]
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		var tag := "W" if String(d.get("type", "")) == "WARN" else "E"
		# push_error("msg") arrives with the message in `code` and a blank `rationale`; an engine ERR_FAIL_COND
		# carries the condition in `code` and the explanation in `rationale`. Show whichever is present, both when both.
		var code := String(d.get("code", ""))
		var rationale := String(d.get("rationale", ""))
		var msg := rationale
		if msg == "":
			msg = code
		elif code != "":
			msg += " (%s)" % code
		out.append("[%s] %s:%d %s — %s" % [tag, String(d.get("file", "")), _int_of(d.get("line")), String(d.get("function", "")), msg])
	out.append("the overlay dumps the same buffer to %s on quit." % String(DebugOverlayScript.ERROR_LOG_PATH))
	return out


## `saves` — the profile's disk-write telemetry. The autosave-storm bug class (a `give`/`money`/flag loop writing
## gamestate.cfg every frame) was invisible until GameState started counting its _write_atomic attempts; this line
## is where a count that climbs while you stand still gets noticed.
static func _cmd_saves() -> PackedStringArray:
	var out := _save_telemetry_lines()
	out.append("counts every _write_atomic attempt: autosave (each money / inventory / flag / quest / object-state change), F5 quicksave, the slots.")
	out.append("an autosave that no-ops (no player, player off-tree, or a quickload in flight) never reaches the disk and is NOT counted.")
	out.append("a count that climbs while you stand still is an autosave storm — find the money_changed / inventory.changed / set_flag caller.")
	return out


## "profile writes N ok / M failed · last <path> <OK|Error n> <secs> ago · sandbox on|off". Every field is an
## ADDITIVE GameState member read duck-typed (Object.get -> null on an older build), so this degrades to one honest
## line rather than an invalid-constructor error on int(null).
static func _save_telemetry_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var raw_count: Variant = GameState.get(&"save_count")
	if raw_count == null:
		out.append("saves: no disk-write telemetry on this GameState (save_count missing) — the counter lands with the sandbox API")
		return out
	var ok_count := _int_of(raw_count)
	var failed := _int_of(GameState.get(&"save_fail_count"))
	var last_msec := _int_of(GameState.get(&"last_save_msec"), -1)
	var raw_path: Variant = GameState.get(&"last_save_path")
	var last_path := String(raw_path) if raw_path is String else ""
	var last_err := _int_of(GameState.get(&"last_save_err"), OK)
	var sandbox_on := GameState.has_method(&"sandbox_active") and bool(GameState.call(&"sandbox_active"))
	var sandbox_text := "on" if sandbox_on else "off"
	if last_msec < 0:
		out.append("profile writes %d ok / %d failed · no write yet this session · sandbox %s" % [ok_count, failed, sandbox_text])
		return out
	var result := "OK" if last_err == OK else "Error %d (%s)" % [last_err, error_string(last_err)]
	var age := float(Time.get_ticks_msec() - last_msec) / 1000.0
	out.append("profile writes %d ok / %d failed · last %s %s %.1fs ago · sandbox %s" % [
		ok_count, failed, (last_path if last_path != "" else "(no path recorded)"), result, age, sandbox_text])
	if sandbox_on:
		out.append("  (the last path is the RESOLVED one — the sandbox rewrite is already applied)")
	return out


# =============================================================================================================
# RING BUFFERS — the two observability drop-ins (`ailog` -> AiEventLog, `events` -> DebugEventTicker)
# =============================================================================================================

## One seam description per ring-buffer drop-in, so `ailog` and `events` share ONE body (_ring_command) and can
## never drift on the count / filter / clear / on|off grammar. Keys:
##   &"label"       the command name, for the output lines
##   &"path"        the drop-in script (the *_SCRIPT_PATH consts — loaded lazily, see _ring_script)
##   &"class"       its class_name — for MESSAGES ONLY, never a type reference (the stale-cache cascade)
##   &"node_name"   the name a scene-less mount gets under tree.current_scene
##   &"is_visible" / &"set_visible"   the drop-in's on-screen surface getter/setter (INSTANCE methods, need the node)
##   &"surface"     what that surface is called in the output ("panel" / "column")
## Both drop-ins expose the same STATIC pair — lines(count, filter) -> PackedStringArray (newest `count` entries whose
## text contains `filter`, "" = all, oldest first / newest last) and clear() — which is all the dump needs.
const AI_LOG_SEAM := {
	&"label": "ailog", &"path": AI_EVENT_LOG_SCRIPT_PATH, &"class": "AiEventLog", &"node_name": &"AiEventLog",
	&"is_visible": &"is_panel_visible", &"set_visible": &"set_panel_visible", &"surface": "panel",
}
const EVENT_TICKER_SEAM := {
	&"label": "events", &"path": EVENT_TICKER_SCRIPT_PATH, &"class": "DebugEventTicker", &"node_name": &"DebugEventTicker",
	&"is_visible": &"is_column_visible", &"set_visible": &"set_column_visible", &"surface": "column",
}

static var _ring_scripts: Dictionary = {}  ## script path -> loaded GDScript, resolved once (see _ring_script)


## `ailog [count] [filter|on|off|clear]` — the AI transition log (AiEventLog: perception state, target acquire/lose,
## goal change, provoke/stand-down, flee, freeze, stranded, spawn/free). See _ring_command for the shared grammar.
static func _cmd_ailog(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	return _ring_command(ctx, args, AI_LOG_SEAM)


## `events [count] [filter|on|off|clear]` — the game-event ticker (DebugEventTicker: quests, reputation, phase,
## rent, dialogue, money/xp, effects, death, level, saves). Same body as `ailog`.
static func _cmd_events(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	return _ring_command(ctx, args, EVENT_TICKER_SEAM)


## The shared body. Grammar (validate() has already pinned slot 1 to a NUMBER and the arity to <= 2):
##   <label>                    the last RING_DEFAULT_COUNT lines
##   <label> <n>                the last n lines (0 or negative = the default)
##   <label> <n> <substring>    the last n lines whose text contains <substring>
##   <label> clear              empty the ring
##   <label> on|off             show / hide the drop-in's on-screen surface (ailog's panel, events' column)
## Both slots are Kind.TEXT in the registry: a numeric first token is the count, a non-numeric one is the control
## word (on / off / clear), so `events on` and `ailog clear` validate as typed. A dev who wants to FILTER by the
## literal words on / off / clear cannot: those three are reserved in the word slot.
##
## The DUMP MOUNTS a drop-in when the tree has none (find-or-create at the current-scene root, like the inspector):
## a recorder that is not in the tree records nothing, and "0 lines" forever with no hint is the failure this exists
## to prevent. The mount is reported in the output. `off` deliberately does NOT mount — a node created only to be
## hidden is a surprise, and there is nothing to hide.
static func _ring_command(ctx: Dictionary, args: PackedStringArray, seam: Dictionary) -> PackedStringArray:
	var label := String(seam[&"label"])
	var cls := String(seam[&"class"])
	var path := String(seam[&"path"])
	var script := _ring_script(path)
	if script == null:
		return _one("%s: the %s drop-in is not built (%s is not on disk) — nothing is recording and there is nothing to dump" % [label, cls, path])
	# has_method() SEES STATICS on a GDScript (cyber.gd:172-176 verified it — Script.has_static_method is not
	# exposed to scripts), so a renamed or de-static'd lines()/clear() is one honest line, not an invalid call. A
	# GDScript whose PARSE failed also comes back non-null from load() with an EMPTY function table (cyber.gd:169-171),
	# so this same guard is what turns a broken drop-in into a line instead of an "Invalid call" on script.call().
	if not script.has_method(&"lines") or not script.has_method(&"clear"):
		return _one("%s: %s exposes no static lines(count, filter) / clear() — did %s fail to compile (check the Output panel / `errors`), or was the API renamed?" % [label, cls, path])

	var count := RING_DEFAULT_COUNT
	var word := ""
	if not args.is_empty():
		var first := args[0].strip_edges()
		if first.is_valid_float():
			var wanted := int(first.to_float())
			if wanted > 0:
				count = wanted
			if args.size() > 1:
				word = args[1].strip_edges()
		else:
			# Slot 1 is Kind.TEXT in the registry precisely so `events on` / `ailog clear` validate: a non-numeric first
			# token is the control word (on/off/clear), a numeric one is the count.
			word = first
	var lowered := word.to_lower()
	if lowered == "on" or lowered == "off":
		return _ring_toggle(ctx, seam, script, lowered == "on")
	if lowered == RING_CLEAR_WORD:
		return _ring_clear(seam, script)

	# The recorder is resolved BEFORE the read so a first-ever `ailog` mounts one (the same call reports it below);
	# the ring is a static, so a node mounted this frame changes nothing about what the read returns.
	var found := _ring_node(ctx, script, StringName(seam[&"node_name"]), true)
	var node: Node = found.get(&"node")
	var created := bool(found.get(&"created", false))

	var out := PackedStringArray()
	# `word` is passed as typed (not lowered): whether the substring match is case-sensitive is the drop-in's call.
	var shown := _ring_lines(script, count, word)
	var total := _ring_lines(script, RING_READ_ALL, "").size()
	if word == "":
		out.append("%d lines (%d total)" % [shown.size(), total])
	else:
		var matching := _ring_lines(script, RING_READ_ALL, word).size()
		out.append("%d lines matching \"%s\" (%d match, %d total)" % [shown.size(), word, matching, total])
	for line in shown:
		out.append("  " + line)
	if node == null:
		out.append("! no %s is mounted (no current scene to mount one in, or the name \"%s\" is taken by an unrelated node) — nothing is recording; any lines above are history the static ring kept" % [cls, String(seam[&"node_name"])])
	elif created:
		out.append("(no scene shipped a %s — one was mounted under %s; recording starts now, and the ring keeps its history across reloads)" % [cls, node.get_parent().name])
		# The two drop-ins ship OPPOSITE surface defaults (the ticker's column starts VISIBLE, the AI log's panel starts
		# hidden), so a plain dump can paint a column nobody asked for — say what the mount just did to the screen.
		out.append("  its %s is %s at the drop-in's default (`%s 0 on` / `%s 0 off` toggles it)" % [String(seam[&"surface"]), _ring_surface_state(seam, node), label, label])
	elif total == 0:
		out.append("nothing recorded since the %s mounted (the ring is a static: reloads keep it, `%s 0 %s` empties it)" % [cls, label, RING_CLEAR_WORD])
	return out


## on|off for the drop-in's on-screen surface. Reads the state BACK after the write, so the line reports what the
## node actually did rather than what was asked (a release build without force_in_release may refuse).
static func _ring_toggle(ctx: Dictionary, seam: Dictionary, script: GDScript, on: bool) -> PackedStringArray:
	var label := String(seam[&"label"])
	var cls := String(seam[&"class"])
	var surface := String(seam[&"surface"])
	var node_name := StringName(seam[&"node_name"])
	var found := _ring_node(ctx, script, node_name, on)
	var node: Node = found.get(&"node")
	if node == null:
		if on:
			return _one("%s: no %s in the tree and none could be mounted (no current scene, or the name \"%s\" is taken by an unrelated node)" % [label, cls, String(node_name)])
		return _one("%s: no %s in the tree — nothing to hide (and nothing is recording); `%s 0 on` mounts one" % [label, cls, label])
	var setter: StringName = seam[&"set_visible"]
	var getter: StringName = seam[&"is_visible"]
	if not node.has_method(setter) or not node.has_method(getter):
		return _one("%s: %s has no %s() / %s() — API drift between %s and this command" % [label, cls, String(setter), String(getter), String(seam[&"path"])])
	node.call(setter, on)
	var now := bool(node.call(getter))
	var out := PackedStringArray()
	out.append("%s %s %s" % [label, surface, "ON" if now else "OFF"])
	if now != on:
		out.append("! asked for %s but %s() reads back %s — the drop-in refused (release build without force_in_release?)" % ["ON" if on else "OFF", String(getter), "ON" if now else "OFF"])
	if bool(found.get(&"created", false)):
		out.append("(no scene shipped a %s — one was mounted under %s; recording starts now)" % [cls, node.get_parent().name])
	return out


## `clear` — empties the STATIC ring on the script. Counted before and re-read after so the line reports what
## happened: the ring is what a death reload / quickload deliberately preserves, so an accidental clear deserves a
## number in the scrollback, and a clear() that did not land deserves to be called out.
static func _ring_clear(seam: Dictionary, script: GDScript) -> PackedStringArray:
	var label := String(seam[&"label"])
	var before := _ring_lines(script, RING_READ_ALL, "").size()
	script.call(&"clear")
	var after := _ring_lines(script, RING_READ_ALL, "").size()
	if after != 0:
		return _one("%s: clear() ran but %d line(s) still read back (was %d) — check %s" % [label, after, before, String(seam[&"path"])])
	return _one("%s: cleared %d line(s) — the ring is a static, so this is the ONLY thing that empties it (reloads keep it)" % [label, before])


## "ON" / "OFF" from the drop-in's OWN visibility getter (the seam's &"is_visible" — an INSTANCE method, hence the
## live node), or "?" when that method is missing. Read back, never assumed: the getter also folds the debug-build
## gate (a release build without force_in_release answers false whatever was asked). `node` is the mount this same
## command just made or found in-tree this frame — never a cached handle — so a typed param is safe here.
static func _ring_surface_state(seam: Dictionary, node: Node) -> String:
	var getter: StringName = seam[&"is_visible"]
	if node == null or not node.has_method(getter):
		return "?"
	return "ON" if bool(node.call(getter)) else "OFF"


## lines(count, filter) off the loaded script, normalised to a PackedStringArray. The drop-in owns the ordering and
## the tail (newest `count`, oldest first / newest last — the registry help row states it); this never re-slices.
## A non-array return (drift) reads as empty rather than erroring.
static func _ring_lines(script: GDScript, count: int, filter: String) -> PackedStringArray:
	var raw: Variant = script.call(&"lines", count, filter)
	if raw is PackedStringArray:
		var lines: PackedStringArray = raw
		return lines
	if raw is Array:
		var out := PackedStringArray()
		for v in (raw as Array):
			out.append(str(v))
		return out
	return PackedStringArray()


## The live recorder for a ring seam. Found by SCRIPT identity (never `is <class>` — the class_name may not be in
## the global cache yet, and an authored drop-in may carry any name): under the current scene first, then anywhere
## in the tree (a designer may parent one under an autoload or a persistent HUD layer). With `mount` and none found,
## one is created at the current-scene ROOT — a sibling of GameRoot/Player in game.tscn — so it survives
## GameRoot.load_level freeing the level subtree. Returns {&"node": Node or null, &"created": bool}.
static func _ring_node(ctx: Dictionary, script: GDScript, node_name: StringName, mount: bool) -> Dictionary:
	var tree := _tree(ctx)
	if tree == null:
		return {&"node": null, &"created": false}
	var node := _find_by_script(tree.current_scene, script)
	if node == null:
		node = _find_by_script(tree.root, script)
	if node != null:
		return {&"node": node, &"created": false}
	if not mount or tree.current_scene == null:
		return {&"node": null, &"created": false}
	node = _find_or_create(tree.current_scene, node_name, script)
	return {&"node": node, &"created": node != null}


## The loaded drop-in script for `path`, or null while it is not on disk. A MISS IS NOT CACHED: the file can land
## later in the same session (the drop-ins are built beside these commands and the editor is usually open), and the
## next call should simply pick it up. Same lazy idiom as _inspector / debug_actions_player.gd's _find_or_make_noclip.
static func _ring_script(path: String) -> GDScript:
	if _ring_scripts.has(path):
		return _ring_scripts[path] as GDScript
	if not ResourceLoader.exists(path):
		return null
	var scr := load(path) as GDScript
	if scr != null:
		_ring_scripts[path] = scr
	return scr


# =============================================================================================================
# ROUND-TRIP + SOAK — the two commands whose work OUTLIVES the call (a coroutine on a root-parented Node)
# =============================================================================================================
##
## Console dispatch is SYNCHRONOUS (`_print_lines(run(...))`), but both of these walk real frames: `roundtrip`
## reloads the whole scene and waits for it to settle, `soak` awaits seconds of physics. So each command mounts a
## Node at `tree.root` — NOT under the level (a `warp` frees it) and NOT under the console (the reload frees it,
## and so does a death) — the menu_qa_shots.gd "driver at root" idiom: root children survive reload_current_scene,
## so the coroutine never resumes on a freed instance ("Resumed function after await, but class instance is gone"),
## and it can find the FRESH console (Groups.DEBUG_SURFACE, duck-typed `echo`) to post its report into. The command
## itself returns a "started" line immediately; the report arrives later, into the console AND stdout.

## `roundtrip` (danger): capture -> scratch save -> GameState._load_and_reload -> settle -> capture -> diff. The whole
## body lives on the DebugRoundtrip harness (debug_roundtrip.gd); this command only mounts it, hands it the player,
## and — the one thing the harness cannot do because it has no ctx — releases this module's scene-scoped state
## the moment the reload is in flight (`timescale`'s banked flag would otherwise die with the console's Dictionary,
## exactly as `load` handles it). begin() runs capture A + the write + the reload kick synchronously and returns ""
## once reload_current_scene has been REQUESTED. ⭐In Godot 4.2+ that request DETACHES the current scene on the spot
## (root.remove_child + queue_free; the fresh scene lands at the next SceneTree flush), so by the time begin() returns
## the console that typed this has already run its _exit_tree — which calls release_scene_scoped_state for BOTH
## modules — and the release below is the idempotent belt-and-braces (`load` has the same shape). The lines returned
## here reach a detached console (stdout mirror only); the harness recaps into the FRESH console, so nothing is
## lost. A non-empty return is a refusal with NOTHING reloaded and every field the harness touched put back, and the
## mounted node is freed again.
static func _cmd_roundtrip(ctx: Dictionary) -> PackedStringArray:
	var tree := _tree(ctx)
	if tree == null or tree.root == null:
		return _one("roundtrip: no SceneTree")
	var player := _player(ctx)
	if player == null:
		return _one("roundtrip: no player — the round trip captures the live one (open the console in-game, not on the menu)")
	if not player.is_inside_tree():
		return _one("roundtrip: the player is off-tree — GameState.capture would read nothing")
	if GameState.reload_pending():
		return _one("roundtrip: a quickload is in flight (GameState.reload_pending) — let the fresh scene boot first")
	if not ResourceLoader.exists(ROUNDTRIP_SCRIPT_PATH):
		return _one("roundtrip: the DebugRoundtrip harness is not built (%s is not on disk) — nothing reloaded" % ROUNDTRIP_SCRIPT_PATH)
	var script := load(ROUNDTRIP_SCRIPT_PATH) as GDScript
	if script == null:
		return _one("roundtrip: %s did not load as a GDScript — nothing reloaded" % ROUNDTRIP_SCRIPT_PATH)
	# The node name comes off the script's own constant map so a rename there cannot silently break the
	# "already running" find below; the local const is only the fallback.
	var node_name := StringName(str(script.get_script_constant_map().get("NODE_NAME", String(ROUNDTRIP_NODE_NAME))))
	if tree.root.get_node_or_null(NodePath(String(node_name))) != null:
		return _one("roundtrip: one is already running (the harness frees itself once its report lands in the console) — wait for it")

	var harness := script.new() as Node
	if harness == null:
		return _one("roundtrip: DebugRoundtrip.new() returned null (did %s fail to compile? check the Output panel / `errors`)" % ROUNDTRIP_SCRIPT_PATH)
	if not harness.has_method(&"begin"):
		harness.free()
		return _one("roundtrip: DebugRoundtrip has no begin(player) — API drift between debug_roundtrip.gd and this command")
	harness.name = node_name
	# ROOT, before begin(): the harness needs get_tree() for its captures, and root is the one parent that survives the
	# reload it is about to trigger (the console's own scene does not).
	tree.root.add_child(harness)
	var refusal := str(harness.call(&"begin", player))
	if refusal != "":
		harness.queue_free()
		return _one(refusal)

	# The reload is IN FLIGHT: hand back what this module clobbered while ctx[&"state"] — the only record of the banked
	# authored values — still exists (the console Object outlives its detach until frame end). Idempotent with the
	# console's own _exit_tree release that reload_current_scene already triggered inside begin(); same shape as `load`.
	var out := release_scene_scoped_state(ctx)
	out.append("roundtrip started — results arrive in the console after the reload (and on stdout, prefixed [roundtrip]).")
	out.append("capture A taken (profile + quests + world snapshot + live hands), scratch save written to %s, GameState._load_and_reload kicked — the same path F9 quickload takes." % str(script.get_script_constant_map().get("SCRATCH_PATH", "user://debug_roundtrip.cfg")))
	out.append("the scratch path is NON-canonical, so resolve_save_path passes it through unchanged (sandbox on or off) — the scratch write never touches the real profile; your checkpoint is banked and restored, and the fresh Player lands where you stand.")
	out.append("this console and every debug overlay in the scene go with the reload — press backtick again to read the report (it waits in the scrollback).")
	return out


## `soak [n] [seconds]`: the SoakHarness (scripts/tools/soak_harness.gd) on the LIVE level — spawn n wanderers,
## sample each NPC's own _stranded_cycles for `seconds` of physics, then the spawn/free node-leak waves — and echo its
## SoakReport (scripts/tools/soak_report.gd) into the console when it finishes: THE SAME report tests_soak/test_soak.gd
## prints headless (`gut.p(report.summary())`), so a strand seen here reads exactly like one seen there.
##
## Mounting: the harness spawns its wave as SIBLINGS of itself under get_parent() (soak_harness.gd `_spawn_wave`),
## so it is childed to a root-parented SoakDriver — the wave lands under the driver, at root, in the same World3D as
## the level (game.tscn is a Node3D straight under root; the level's NavigationRegion3D registers on that world's
## default map, so the NPCs path on it). That is what lets a `warp`/`reload` mid-run NOT free the harness under its
## own coroutine — the report still lands, marked INCONCLUSIVE — and it is why the driver's queue_free (report posted)
## sweeps every straggler NPC in one go. Every wave is queue_free()d by the harness itself between phases (`_free_wave`).
static func _cmd_soak(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var tree := _tree(ctx)
	if tree == null or tree.root == null:
		return _one("soak: no SceneTree")
	if tree.root.get_node_or_null(NodePath(String(SOAK_DRIVER_NAME))) != null:
		return _one("soak: one is already running (the driver frees itself once its report lands in the console) — wait for it")
	if GameState.reload_pending():
		return _one("soak: a quickload is in flight (GameState.reload_pending) — the level is about to change under the wave")
	var level := _level_node(tree)
	if level == null:
		return _one("soak: no \"Level\" in the tree — the wave needs a level with a baked NavigationRegion3D to wander")
	if not ResourceLoader.exists(SOAK_HARNESS_PATH):
		return _one("soak: %s is not on disk — nothing to run" % SOAK_HARNESS_PATH)
	var script := load(SOAK_HARNESS_PATH) as GDScript
	if script == null:
		return _one("soak: %s did not load as a GDScript" % SOAK_HARNESS_PATH)
	var harness := script.new() as Node
	if harness == null:
		return _one("soak: SoakHarness.new() returned null (did %s fail to compile? check the Output panel / `errors`)" % SOAK_HARNESS_PATH)
	if not harness.has_method(&"run_soak"):
		harness.free()
		return _one("soak: SoakHarness has no run_soak() — API drift between soak_harness.gd and this command")

	# Arguments over the harness's AUTHORED defaults (read back off the instance, never duplicated here), each capped.
	var requested_n := _int_of(harness.get(&"npc_count"), 4)
	if args.size() >= 1:
		requested_n = int(args[0].to_float())
	var count := clampi(requested_n, 1, MAX_SOAK_NPCS)
	var requested_s := _float_of(harness.get(&"stranded_seconds"), 12.0)
	if args.size() >= 2:
		requested_s = args[1].to_float()
	var seconds := clampf(requested_s, MIN_SOAK_SECONDS, MAX_SOAK_SECONDS)
	harness.set(&"npc_count", count)
	harness.set(&"stranded_seconds", seconds)
	var faction_note := ""
	var faction: Resource = null
	if ResourceLoader.exists(SOAK_FACTION_PATH):
		faction = load(SOAK_FACTION_PATH)
	if faction != null:
		harness.set(&"faction", faction)  # neutral: the wave WANDERS instead of hunting you (see SOAK_FACTION_PATH)
	else:
		faction_note = "! %s is missing — the wave keeps the harness's default faction (raiders) and WILL aggro you; `notarget on` first." % SOAK_FACTION_PATH
	var leak_waves := _int_of(harness.get(&"leak_waves"), 2)
	var wave_seconds := _float_of(harness.get(&"leak_wave_seconds"), 3.0)

	var driver := SoakDriver.new()
	driver.name = SOAK_DRIVER_NAME
	driver.harness = harness
	driver.level_id = level.get_instance_id()
	driver.level_name = String(level.name)
	driver.add_child(harness)      # harness.get_parent() == driver: the wave spawns as its siblings, under root
	tree.root.add_child(driver)    # root, NOT the level: the awaiting coroutine must outlive a warp/reload
	driver.start()

	var out := PackedStringArray()
	out.append("soak started on %s: %d %s wanderer(s), %.0f s stranded phase + %d leak wave(s) x %.0f s — about %.0f REAL seconds; expect a hitch per wave (NPC._ready x %d, %d waves)." % [
		driver.level_name, count, ("neutral" if faction != null else "RAIDER"), seconds, leak_waves, wave_seconds,
		seconds + float(leak_waves) * wave_seconds + 1.0, count, 1 + leak_waves])
	out.append("it walks real seconds — stand still if the LEAK trend is the question (the node count is global: gunfire, gore, toasts and barks all move it and would read as a leak); the report (SoakReport.summary(), the same one tests_soak/ prints) lands in the console and on stdout when it finishes.")
	if requested_n > count:
		out.append("! %d requested, capped at %d — each wave runs NPC._ready per body and the soak spawns %d waves of them" % [requested_n, MAX_SOAK_NPCS, 1 + leak_waves])
	if not is_equal_approx(requested_s, seconds):
		out.append("! %.1f s requested, clamped to %.1f s (%.0f..%.0f)" % [requested_s, seconds, MIN_SOAK_SECONDS, MAX_SOAK_SECONDS])
	if seconds < SOAK_STRAND_MIN_SECONDS:
		out.append("! under ~%.0f s a strand cannot register (an NPC must give up in one spot %d times in a row, ~10 s) — this run is a node-leak check only" % [SOAK_STRAND_MIN_SECONDS, _soak_stranded_threshold()])
	if faction_note != "":
		out.append(faction_note)
	out.append("the wave spawns under a root-parented driver (not the level), so a `warp`/`reload` mid-run does not free it — the report still arrives, marked INCONCLUSIVE; `navdebug on` shows the islands they wedge on.")
	out.append("nav must be synced: a soak right after `warp` reports INCONCLUSIVE (nav_ready false) by design — retry once the map is up.")
	out.append("the driver stamps every wave body _dynamic_spawn (kept out of the exact-save tier + the death ledger, like `spawn`) and re-anchors its wander centre on the scattered spot (soak_harness.gd moves a body AFTER its _ready latched _spawn_position at the origin) — the wave renders un-warped (no Ps1Warp cover under root; cosmetic).")
	return out


## SoakReport.STRANDED_THRESHOLD read off the script's constant map (never the class_name, never a mirrored literal —
## the const is what the harness's verdict keys on, so the warning must quote the same number). 3 is only the fallback
## for a missing/renamed const.
static func _soak_stranded_threshold() -> int:
	if not ResourceLoader.exists(SOAK_REPORT_PATH):
		return 3
	var script := load(SOAK_REPORT_PATH) as GDScript
	if script == null:
		return 3
	return _int_of(script.get_script_constant_map().get("STRANDED_THRESHOLD"), 3)


## The `soak` driver — a plain Node at tree.root that OWNS the SoakHarness as its child (so the wave spawns under
## it, see _cmd_soak), awaits run_soak(), posts the report, and frees itself + the harness + any straggler NPC in one
## queue_free. An INNER class rather than a file: it has no designer surface, no @exports, nothing to drop into a
## scene — it exists only to give the await somewhere to live that the level and the console cannot take with them.
##
## It also patches two seams of the HEADLESS harness that only bite on a LIVE level, from the parent side (the wave
## is add_child()ed to this node, so `child_entered_tree` sees every body BEFORE its _ready — soak_harness.gd itself
## is not touched):
##   * `_dynamic_spawn` — the harness stamps display_name/wanders/faction only, so a mid-soak quicksave would capture
##     the wave under ephemeral @-paths and a killed body would enter the death ledger; the same stamp `spawn` and
##     EncounterSpawner apply.
##   * `_spawn_position` — NPC._ready latches the wander/return-to-post centre from global_position, and the harness
##     moves the body to the scattered anchor AFTER add_child, so on any level whose PlayerSpawn is not at the origin
##     the whole wave would wander back toward (0,0,0) — off-mesh on a real map, i.e. FALSE strands. Re-stamped
##     DEFERRED (the move is synchronous inside the harness's spawn loop; the flush runs after it), the way
##     restore_snapshot_state / NpcPool re-anchor a moved body. Duck-typed on the property existing (a corpse the
##     wave drops under us has neither field and is skipped).
class SoakDriver extends Node:
	var harness: Node = null
	var level_id: int = 0          ## the level the soak started on — invalid at report time = it was swapped mid-run
	var level_name: String = "?"
	var _started_msec: int = 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS  # a dialogue pause must not stall the await forever
		child_entered_tree.connect(_on_wave_child_entered)

	func start() -> void:
		_started_msec = Time.get_ticks_msec()
		_run()  # a coroutine: suspends on the harness's first await and finishes on its own

	## Every child the harness spawns under us (see the class doc). Runs before the child's _ready.
	func _on_wave_child_entered(node: Node) -> void:
		if node == null or not is_instance_valid(node) or node == harness:
			return
		if node.get(&"_dynamic_spawn") is bool:
			node.set(&"_dynamic_spawn", true)
		if node.get(&"_spawn_position") is Vector3:
			call_deferred(&"_reanchor", node.get_instance_id())  # by id: the body may be freed before the flush

	func _reanchor(id: int) -> void:
		var node := instance_from_id(id) as Node3D
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			return
		if node.get(&"_spawn_position") is Vector3:
			node.set(&"_spawn_position", node.global_position)

	func _run() -> void:
		var lines := PackedStringArray()
		if harness == null or not is_instance_valid(harness):
			lines.append("soak: the harness went away before it ran — nothing to report")
			_post(lines)
			return
		# `call` (not a typed method) — the harness is duck-typed here; awaiting the returned function state is the
		# same idiom GUT uses to run a coroutine test (gut.gd `await script_inst.call(test_name)`).
		var report: Variant = await harness.call(&"run_soak")
		var elapsed := float(Time.get_ticks_msec() - _started_msec) / 1000.0
		lines.append("soak done in %.1f real s on %s — SoakReport (the same one tests_soak/test_soak.gd prints):" % [elapsed, level_name])
		if report == null or not is_instance_valid(report) or not report.has_method(&"summary"):
			lines.append("! run_soak() returned no SoakReport (API drift between soak_harness.gd / soak_report.gd and this command)")
			_post(lines)
			return
		# The harness names the report after its PARENT (the level, headless) — that is this driver here, so put the
		# level the wave actually walked on the SOAK [...] line.
		if report.get(&"level_name") is String:
			report.set(&"level_name", level_name)
		for line in str(report.call(&"summary")).split("\n"):
			lines.append("  " + line)
		# `report` is an untyped Variant (duck-typed SoakReport), so annotate: `:=` cannot infer through
		# `Variant.has_method(...) and ...` — the recurring parse trap in this repo.
		var nav_ready: bool = report.get(&"nav_ready") is bool and bool(report.get(&"nav_ready"))
		var ok: bool = report.has_method(&"ok") and bool(report.call(&"ok"))
		if not nav_ready:
			lines.append("verdict INCONCLUSIVE — the navmesh never synced within the harness timeout (a soak right after `warp` / a re-bake, or the level has no NavigationRegion3D); retry once the map is up.")
		elif ok:
			lines.append("verdict OK — no NPC stranded, no node leak.")
		else:
			lines.append("verdict FAIL — each STRANDED row is a likely bad-bake island (a prop/car roof the bake made walkable): carve it with a NavBlocker(CARVE) or re-bake, then re-run; a rising post_wave trend is a spawn-path node leak — unless YOU spawned nodes meanwhile (shots, gore, toasts): re-run standing still before trusting it.")
		# The level the wave started on is gone (warp / reload / death mid-run): the stranded samples straddle two
		# levels and the leak baseline moved under the harness — an honest INCONCLUSIVE, not a fault in the bake.
		var level_now := instance_from_id(level_id) as Node
		if level_now == null or not is_instance_valid(level_now) or not level_now.is_inside_tree():
			lines.append("! the level this soak started on was swapped/reloaded mid-run — the result mixes levels; treat it as INCONCLUSIVE and re-run.")
		lines.append("every soak NPC was queue_free()d by the harness between phases; the root-parented driver frees itself (and any straggler) now.")
		_post(lines)

	## stdout AND the FRESH console — found by group at report time, never cached: a `reload` mid-soak freed the one
	## that typed the command (the DebugMenu has no echo(), so at most one surface prints).
	func _post(lines: PackedStringArray) -> void:
		for line in lines:
			print("[soak] " + line)
		var tree := get_tree()
		if tree != null:
			# Qualified through the outer class like _ShotDriver does (an inner class reads outer consts either way).
			for surface in tree.get_nodes_in_group(DebugActionsWorld.GroupsScript.DEBUG_SURFACE):
				if is_instance_valid(surface) and surface.has_method(&"echo"):
					surface.call(&"echo", lines)
					break
		queue_free()


# =============================================================================================================
# ctx helpers
# =============================================================================================================

## ⭐EVERY ctx object goes through is_instance_valid() BEFORE the `as` cast. ctx is built by the host and can be
## re-used across commands, so a handle in it can outlive its node: `reload` / `load` free the whole scene, `warp`
## frees the level subtree, `killall` queue_free()s bodies. A cast (like `is`) evaluates the object's type and
## errors on a FREED instance — the project rule is validity FIRST, always. A stale handle degrades to null here,
## which every call site already guards.
static func _tree(ctx: Dictionary) -> SceneTree:
	var raw: Variant = ctx.get(&"tree")
	if not is_instance_valid(raw):
		return null
	return raw as SceneTree


static func _host(ctx: Dictionary) -> Node:
	var raw: Variant = ctx.get(&"host")
	if not is_instance_valid(raw):
		return null
	return raw as Node


## The human player, or null. ALWAYS null-guarded at every call site: the console can be open on the main menu,
## before the player spawns, or over a corpse.
static func _player(ctx: Dictionary) -> Node:
	var raw: Variant = ctx.get(&"player")
	if not is_instance_valid(raw):
		return null
	return raw as Node


static func _player3d(ctx: Dictionary) -> Node3D:
	var raw: Variant = ctx.get(&"player")
	if not is_instance_valid(raw):
		return null
	return raw as Node3D


## The host-owned Dictionary that PERSISTS across commands. Returns a throwaway when the host forgot to supply
## one, so a toggle degrades to "stateless" instead of crashing.
static func _state(ctx: Dictionary) -> Dictionary:
	var raw: Variant = ctx.get(&"state")
	if raw is Dictionary:
		var s: Dictionary = raw
		return s
	return {}


static func _has_state(ctx: Dictionary, key: StringName) -> bool:
	return _state(ctx).has(key)


## Hand back everything this module clobbered that is scoped to the LIVE SCENE, immediately before a command that
## destroys it (`reload`, `load`). RETURNS its notes rather than filling a caller's array: an out-parameter would
## make the whole unwind hinge on Packed*Array reference semantics, and this is not a detail worth betting on.
##
## ⭐THIS IS NOT OPTIONAL, IT IS THE ONLY UNWIND PATH. `timescale <n>` sets GameSettings.allow_timescale_changes
## false and banks the AUTHORED value in ctx[&"state"] — that Dictionary is the only record of it anywhere. A
## reload frees a console parented into game.tscn and takes the Dictionary with it, and nothing else in the project
## ever sets the flag back, so hitstop, bullet time AND the NPC death-freeze beat would stay dead for the rest of
## the session with no way to recover them. GameState's own reload path resets Engine.time_scale (GameState.gd:1038)
## but NOT the flag, so it does not cover us.
##
## The freezeai latch is dropped for a different reason: the reload builds a FRESH cast that is not under cutscene
## control, so a stale "ON" would make the next bare `freezeai` resolve to OFF and look like a no-op.
## PUBLIC (no underscore) on purpose: the console's `_exit_tree` calls this too, because a death reload / F9
## quickload / the End key all free the console WITHOUT passing through `reload`/`load` — and this dictionary is
## the only record of the banked authored value. Idempotent (keys erased after restore).
##
## `notarget` needs NO unwind here, only hygiene: its meta AND the two zeroed noise exports live on the PLAYER
## INSTANCE (`noise_move_per_speed` / `noise_gunfire_radius` are per-instance @exports on player.gd:303/305, not
## GameSettings fields), and the reload frees that body with the scene — the same reason the player module never
## restores `god`'s armour. The bank keys are erased so a fresh Player is never handed a stale "authored" pair, and
## the sticky `npc` target (a Node about to be freed) goes with them. `warp` keeps the player and deliberately does
## NOT come through here, so a ghost survives a level swap and `notarget off` still finds its bank.
##
## `hud off` is the same shape as `notarget`: its snapshot (STATE_HUD_HIDDEN, UI-relative node paths) points into the
## Player's UI CanvasLayer, which is FREED WITH THE PLAYER by the reload — there is nothing to restore, and a fresh
## Player boots with its HUD fully up. Only the KEY is erased, so a bare `hud` after the reload flips the right way
## and `hud on` never "restores" a stale snapshot onto the new UI. `warp` keeps the Player (and the hide) — correct.
static func release_scene_scoped_state(ctx: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var state := _state(ctx)
	if state.has(STATE_TS_ALLOW):
		GameSettings.allow_timescale_changes = bool(state[STATE_TS_ALLOW])
		state.erase(STATE_TS_ALLOW)
		Engine.time_scale = 1.0
		out.append("timescale override released first — allow_timescale_changes back to %s (the reload would have destroyed the only record of it)." % str(bool(GameSettings.allow_timescale_changes)))
	state.erase(STATE_FREEZE_AI)
	state.erase(STATE_NOTARGET_NOISE_MOVE)
	state.erase(STATE_NOTARGET_NOISE_GUN)
	state.erase(STATE_NPC_STICKY)
	state.erase(STATE_HUD_HIDDEN)
	return out


static func _one(line: String) -> PackedStringArray:
	return PackedStringArray([line])


# =============================================================================================================
# tree lookups
# =============================================================================================================

static func _game_root(tree: SceneTree) -> Node:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GroupsScript.GAME_ROOT)


## The live level subtree ("Level"). GameRoot works in TWO layouts — script on the scene root, or a drop-in child
## with Player/Level as siblings (which is what scenes/game.tscn uses, so the level lands at Game/Level, NOT
## GameRoot/Level). Check both rather than hardcoding either.
static func _level_node(tree: SceneTree) -> Node:
	var gr := _game_root(tree)
	if gr != null:
		var own := gr.get_node_or_null(^"Level")
		if own != null:
			return own
		var parent := gr.get_parent()
		if parent != null:
			var sibling := parent.get_node_or_null(^"Level")
			if sibling != null:
				return sibling
	if tree != null and tree.current_scene != null:
		return tree.current_scene.get_node_or_null(^"Level")
	return null


## Ps1Warp.cover() silently skips a level root that is not a LevelRoot, so `warp` checks for the script by path
## rather than by type (no compile-time dependency, and it works for a root whose script simply is not set).
static func _has_level_root_script(level: Node) -> bool:
	var scr := level.get_script() as Script
	return scr != null and String(scr.resource_path).get_file() == "level_root.gd"


## RentCollector is in NO group and has no registry — the shipping instance is a plain child node in the level
## scene. Re-found on every call because a level swap frees the old one.
##
## find_child matches by NAME ALONE, so the hit is confirmed against the SCRIPT before `clock` reads any field off
## it: every read there is a bare `rent.get(&"…")`, and Object.get() answers null for a property that does not
## exist — `float(null)` / `int(null)` is an invalid-constructor error, not a graceful 0. A designer who names some
## other node "RentCollector" would otherwise break the whole readout. Same script-path idiom as
## _has_level_root_script: no compile-time class dependency.
static func _find_rent_collector(tree: SceneTree) -> Node:
	var level := _level_node(tree)
	if level == null:
		return null
	var found := level.find_child("RentCollector", true, false)
	if found == null:
		return null
	var scr := found.get_script() as Script
	if scr == null or String(scr.resource_path).get_file() != "rent_collector.gd":
		return null
	return found


## Find-or-create a debug node by name under `parent`. Refuses to shadow an unrelated node that happens to own the
## name. add_child is called directly (not deferred) because a console command must be able to report the resulting
## state in the same line — commands run from input/button callbacks, never from inside a child iteration.
## `script` is typed GDScript, not Script: only GDScript exposes new(), and Script alone would not compile.
## Depth-first search for the first node under `root` carrying exactly `script` (an authored drop-in whose name
## the designer may have changed). Matched by script identity, never `is <class>`, so a not-yet-cached class_name
## cannot cascade — and is_instance_valid first, since a level mid-free can still be a child for a frame.
static func _find_by_script(root: Node, script: GDScript) -> Node:
	if root == null or script == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		if node.get_script() == script:
			return node
		for child in node.get_children():
			stack.push_back(child)
	return null


static func _find_or_create(parent: Node, node_name: StringName, script: GDScript) -> Node:
	if parent == null or script == null:
		return null
	var existing := parent.get_node_or_null(NodePath(String(node_name)))
	if existing != null:
		if existing.get_script() == script:
			return existing
		return null  # the name is taken by something unrelated — refuse rather than shadow or clobber it
	var made := script.new() as Node
	if made == null:
		return null
	made.name = node_name
	parent.add_child(made)
	return made


static var _inspector_script: GDScript = null  ## the loaded DebugInspector GDScript (see INSPECTOR_SCRIPT_PATH)


## The shared DebugInspector, created on demand under the current scene. It is a Node3D that raycasts from the
## player's aim, so it belongs in the 3D world, not on the console's CanvasLayer. `who` and `inspect` both go
## through here so there is exactly one raycast implementation and the two can never disagree.
static func _inspector(ctx: Dictionary) -> Node:
	var tree := _tree(ctx)
	if tree == null or tree.current_scene == null:
		return null
	if _inspector_script == null:
		if not ResourceLoader.exists(INSPECTOR_SCRIPT_PATH):
			return null
		_inspector_script = load(INSPECTOR_SCRIPT_PATH) as GDScript
	if _inspector_script == null:
		return null
	return _find_or_create(tree.current_scene, &"DebugInspector", _inspector_script)


# =============================================================================================================
# content scans (disk, cached in statics — sources() runs on every Tab press)
# =============================================================================================================

## NpcData archetypes, keyed by FILE STEM. Deliberately not by identity_key(): "[PH] Beastmaster" is unusable as a
## console token, while the stem is short, unique and typeable.
static func _npcs() -> Dictionary:
	if _npc_scanned:
		return _npc_index
	_npc_scanned = true
	_npc_index = _scan(NPC_DIR, "npc_data.gd", "threat_response", "")
	return _npc_index


static func _levels() -> Dictionary:
	if _level_scanned:
		return _level_index
	_level_scanned = true
	_level_index = _scan(LEVEL_DIR, "level_data.gd", "display_name", "")
	return _level_index


## Quests keyed by Quest.id, NOT the filename — recover_the_package.tres declares id "recover_package", and every
## QuestTracker call keys on the id.
static func _quests() -> Dictionary:
	if _quest_scanned:
		return _quest_index
	_quest_scanned = true
	_quest_index = _scan(QUEST_DIR, "quest.gd", "objectives", "id")
	return _quest_index


## Scan one resource folder into { key -> res:// path }.
##
## load() + a type test, never a regex over the .tres TEXT: Godot converts text resources to binary on export, so
## a shipped build's text scan returns garbage (this is the scripts/items/item_ids.gd pattern, including the
## ".remap" suffix a packed build appends). The type test prefers the SCRIPT path — exact, and it still identifies
## a resource whose discriminating field happens to be null — and falls back to a duck-typed probe property.
##
## `key_field` blank = key by file stem; otherwise key by that field's value (Quest.id).
static func _scan(dir_path: String, script_file: String, probe: String, key_field: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		var path := dir_path.path_join(f)
		var res := load(path)
		if res == null:
			continue
		var scr := res.get_script() as Script
		var by_script := scr != null and String(scr.resource_path).get_file() == script_file
		# Object.get() returns null for a property that does not exist, so a probe whose default is never null
		# (an Array, an int enum) discriminates without loading the class.
		if not by_script and res.get(probe) == null:
			continue
		var key := f.get_basename()
		if key_field != "":
			var raw: Variant = res.get(key_field)
			if raw == null:
				continue
			key = String(raw)
			if key == "":
				continue
		out[key] = path
	return out


## Story flags for completion: the LIVE dict (the shipped game authors essentially zero flags, so a content scan
## would come back empty) plus the one flag name that exists in code. Never cached — flags appear as you play.
static func _flag_names() -> PackedStringArray:
	var out := PackedStringArray()
	for k in GameState.flags.keys():
		out.append(String(k))
	var known := String(GameState.HOLSTER_FORGIVENESS_TUTORIAL_SEEN_FLAG)
	if not out.has(known):
		out.append(known)
	out.sort()
	return out


## Case-insensitive lookup so `warp TestLevel` and `warp testlevel` both land.
static func _lookup(index: Dictionary, wanted: String) -> String:
	if index.has(wanted):
		return String(index[wanted])
	var lower := wanted.to_lower()
	for k in index.keys():
		if String(k).to_lower() == lower:
			return String(index[k])
	return ""


static func _sorted_keys(index: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for k in index.keys():
		out.append(String(k))
	out.sort()
	return out


# =============================================================================================================
# formatting
# =============================================================================================================

static func _clock_text(frac: float) -> String:
	var t := fposmod(frac, 1.0) * 24.0
	var h := int(floorf(t))
	var m := int(roundf((t - float(h)) * 60.0))
	if m >= 60:
		m = 0
		h = (h + 1) % 24
	return "%02d:%02d" % [h, m]


static func _phase_text(phase: int) -> String:
	return "DAY" if phase == WorldClock.Phase.DAY else "NIGHT"


static func _quest_state(qid: StringName) -> String:
	if QuestTracker.is_quest_active(qid):
		return "ACTIVE"
	if QuestTracker.is_quest_completed(qid):
		return "DONE"
	if QuestTracker.is_quest_failed(qid):
		return "FAILED"
	return "-"


## `quest show`: the resource's flow fields plus, for an ACTIVE quest, live per-objective progress.
static func _quest_report(quest: Resource, qid: StringName, path: String) -> PackedStringArray:
	var out := PackedStringArray()
	out.append("%s  \"%s\"   [%s]" % [qid, String(quest.get("title")), _quest_state(qid)])
	out.append("  file %s   auto_complete %s" % [path.get_file(), str(bool(quest.get("auto_complete")))])
	var prereq := StringName(String(quest.get("prereq_quest_id")))
	if prereq != &"":
		out.append("  prereq %s (%s)" % [prereq, _quest_state(prereq)])
	var expire := StringName(String(quest.get("expire_on_flag")))
	if expire != &"":
		out.append("  expires when flag \"%s\" is set" % expire)
	if quest.get("next_quest") != null:
		out.append("  chains into a next_quest on completion")
	out.append("  " + _reward_text(quest))
	var objectives_v: Variant = quest.get("objectives")
	var active := QuestTracker.is_quest_active(qid)
	if objectives_v is Array:
		var objectives: Array = objectives_v
		for o in objectives:
			var obj := o as Resource
			if obj == null:
				continue
			var oid := StringName(String(obj.get("id")))
			var line := "  - %-18s type %d target \"%s\"" % [oid, int(obj.get("type")), String(obj.get("target_id"))]
			if bool(obj.get("optional")):
				line += " (optional)"
			if active:
				# objective_progress returns 0 for a NON-active quest (a COMPLETED one included), and
				# is_objective_done returns true for EVERY objective of a completed quest — so both are only
				# meaningful while the quest is active.
				line += "   %d/%d%s" % [
					QuestTracker.objective_progress(qid, oid), int(obj.get("required_count")),
					"  DONE" if QuestTracker.is_objective_done(qid, oid) else ""]
			out.append(line)
	if not active:
		out.append("  (per-objective progress only reads true while the quest is ACTIVE)")
	return out


## One line of reward summary, read duck-typed so a malformed/partial resource degrades instead of erroring.
static func _reward_text(quest: Resource) -> String:
	return "rewards: money %.0f, xp %.0f, %d item stack(s), rep on %d faction(s)" % [
		float(quest.get("reward_money")), float(quest.get("reward_xp")),
		_count_of(quest.get("rewards")), _count_of(quest.get("reward_reputation"))]


## size() of an Array or Dictionary held in a Variant; 0 for anything else (including a missing property).
static func _count_of(value: Variant) -> int:
	if value is Array:
		var a: Array = value
		return a.size()
	if value is Dictionary:
		var d: Dictionary = value
		return d.size()
	return 0


## int() of a Variant that may be null or junk. Object.get() answers null for a property that does not exist and
## `int(null)` is an invalid-constructor error, not a graceful 0 — so every duck-typed numeric read of an ADDITIVE
## autoload member (save_count, error_count, a ring-buffer line) comes through here and degrades to `fallback`.
static func _int_of(value: Variant, fallback: int = 0) -> int:
	if value is int or value is float or value is bool:
		return int(value)
	return fallback


## float() of a Variant that may be null or junk — the same guard as _int_of for the per-NPC readouts (hp, ranges,
## a Perception state read as a number).
static func _float_of(value: Variant, fallback: float = 0.0) -> float:
	if value is float or value is int or value is bool:
		return float(value)
	return fallback


static func _vec3_text(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]
