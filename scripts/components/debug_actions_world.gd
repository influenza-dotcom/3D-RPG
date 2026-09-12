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

## The family split (2026-09-11): the per-NPC verbs, the Story commands and the View commands live in their own
## files, and the helpers they share sit in debug_actions_world_common.gd. run() below still owns EVERY match arm —
## the registry-row <-> match-case pairing tests/test_debug_commands.gd pins by source scan is unchanged — so adding
## a command is still ONE registry row + ONE match case here, plus the `_cmd_*` static in the family file. All four
## are preloaded by PATH (no class_name, no editor-rescan dependency); Common preloads none of them, so no cycle.
const Common := preload("res://scripts/components/debug_actions_world_common.gd")
const NpcActions := preload("res://scripts/components/debug_actions_world_npc.gd")
const StoryActions := preload("res://scripts/components/debug_actions_world_story.gd")
const ViewActions := preload("res://scripts/components/debug_actions_world_view.gd")

## ⭐The two RING-BUFFER drop-ins (`ailog` -> AiEventLog, `events` -> DebugEventTicker) are referenced by PATH and
## loaded LAZILY (_ring_script) for the same reason DebugInspector is (see INSPECTOR_SCRIPT_PATH in
## debug_actions_world_common.gd): both land in the SAME change as their commands, and a
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
## Below this, Engine.time_scale is effectively a freeze with no way back except another console command.
const MIN_TIME_SCALE := 0.01
const MAX_TIME_SCALE := 20.0
## `advance` spans at or beyond this print the multi-boundary warning (each crossing queues a real disk write).
const LONG_ADVANCE_HOURS := 24.0
## WorldClock.MAX_ADVANCE_STEPS is 800 boundary steps (~2 per day), so past ~400 days the walk silently degrades
## into a seek and stops firing rent/interest. Mirrored here only to warn about it.
const ADVANCE_STEP_BUDGET_DAYS := 400.0
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
## `notarget` banks the player's two AUTHORED noise exports here while it has them zeroed (see _cmd_notarget for
## why the exports must go too — the meta alone leaves footsteps audible to the &"noise" scan).
const STATE_NOTARGET_NOISE_MOVE := &"world/notarget_noise_move"
const STATE_NOTARGET_NOISE_GUN := &"world/notarget_noise_gun"
## The dev-only GHOST SEAM: NPC._treats_as_enemy(node) returns false FIRST for any node carrying this meta
## (npc.gd `DEBUG_NOTARGET_META`, the same literal). That predicate is THE gate NpcTargeting acquires and keeps a
## target by (npc_targeting.gd _target_invalid / the player + peer scans) AND the per-frame
## `_perception.is_hostile = _treats_as_enemy(_target)` writer (npc.gd:2529), so a held ghost target is dropped on
## the very next tick and Perception.can_see()/can_hear() both read false with no target. Spelled as a bare
## StringName here (never `NPC.DEBUG_NOTARGET_META`) so this file has no compile-time dependency on the NPC class.
const NOTARGET_META := &"debug_notarget"
# --- disk-scan caches. sources() runs on EVERY Tab press, so the DirAccess walks happen exactly once. ---------
static var _npc_index: Dictionary = {}     ## file stem -> .tres path
static var _npc_scanned: bool = false
static var _level_index: Dictionary = {}   ## file stem -> .tres path
static var _level_scanned: bool = false
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
		"brain": return NpcActions._cmd_brain(ctx)
		"npc": return NpcActions._cmd_npc(ctx, args)
		"ailog": return _cmd_ailog(ctx, args)
		"notarget": return _cmd_notarget(ctx, args)
		"soak": return _cmd_soak(ctx, args)
		# --- Story ---
		"flag": return StoryActions._cmd_flag(args)
		"flags": return StoryActions._cmd_flags()
		"quest": return StoryActions._cmd_quest(args)
		"quests": return StoryActions._cmd_quests()
		"notify": return StoryActions._cmd_notify(ctx, args)
		"ledger": return StoryActions._cmd_ledger(args)
		"wipeobjects": return StoryActions._cmd_wipeobjects(ctx)
		"resurrect": return StoryActions._cmd_resurrect(ctx)
		"names": return StoryActions._cmd_names(args)
		# --- View ---
		"inspect": return ViewActions._cmd_inspect(ctx, args)
		"navdebug": return ViewActions._cmd_navdebug(ctx, args)
		"perf": return ViewActions._cmd_perf(ctx, args)
		"wireframe", "overdraw", "unshaded": return ViewActions._cmd_debug_draw(cmd, ctx, args)
		"screenshot": return _cmd_screenshot(ctx, args)
		"hud": return ViewActions._cmd_hud(ctx, args)
		"quantize": return _cmd_quantize(args)
		"dither": return ViewActions._cmd_dither(ctx, args)
		"dof": return ViewActions._cmd_dof(ctx, args)
		"sway": return ViewActions._cmd_sway(ctx, args)
		"lens": return ViewActions._cmd_lens(ctx, args)
	return Common._one("\"%s\" is not a world command (registry/actions drift — add a case in debug_actions_world.gd)" % cmd)


## Completion ids this module owns. Keyed off DebugCommands.SOURCE_KEYS rather than hand-typed StringNames so the
## registry and the actions can never drift on a spelling.
static func sources() -> Dictionary:
	var key_npc: StringName = DebugCommandsScript.SOURCE_KEYS[DebugCommandsScript.Kind.NPC]
	var key_level: StringName = DebugCommandsScript.SOURCE_KEYS[DebugCommandsScript.Kind.LEVEL]
	var key_quest: StringName = DebugCommandsScript.SOURCE_KEYS[DebugCommandsScript.Kind.QUEST]
	var key_flag: StringName = DebugCommandsScript.SOURCE_KEYS[DebugCommandsScript.Kind.FLAG]
	return {
		key_npc: Common._sorted_keys(_npcs()),
		key_level: Common._sorted_keys(_levels()),
		key_quest: Common._sorted_keys(Common._quests()),
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
			return Common._one("could not read \"%s\" as HH:MM" % raw)
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
			return Common._one("\"%s\" is out of range — pass HH:MM, 0..1, or 0..24 hours" % raw)
	else:
		return Common._one("could not read \"%s\" — pass HH:MM or a 0..1 fraction" % raw)

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
		return Common._one("advance needs a positive hour count (advance_hours clamps a negative to 0 and returns). Use `time` to seek backwards.")
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
	var tree := Common._tree(ctx)
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
	var state := Common._state(ctx)
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
	var tree := Common._tree(ctx)
	if tree == null:
		return Common._one("no SceneTree")
	var wanted := args[0]
	var path := Common._lookup(_levels(), wanted)
	if path == "":
		return Common._one("no LevelData \"%s\" — try: %s" % [wanted, ", ".join(Common._sorted_keys(_levels()))])
	var data := load(path)
	if data == null:
		return Common._one("could not load %s" % path)
	if String(data.resource_path) == "":
		return Common._one("%s loaded with a blank resource_path — warping it would break the save ledger and Continue" % path)
	if data.get("scene") == null:
		return Common._one("%s has no `scene` — GameRoot.load_level no-ops on it" % path)

	var gr := Common._game_root(tree)
	if gr == null:
		return Common._one("no GameRoot in the tree (group \"%s\") — level warping is only possible in the gameplay scene" % String(GroupsScript.GAME_ROOT))
	if not gr.has_method(&"load_level"):
		return Common._one("the node in group \"%s\" has no load_level()" % String(GroupsScript.GAME_ROOT))

	var out := PackedStringArray()
	out.append("warping to %s (%s)" % [wanted, String(data.get("display_name"))])
	# Synchronous: instantiate + add_child happen inside this call. Safe from a console _input / a menu button —
	# NEVER from a _ready() (add_child is blocked while the parent is setting up children).
	gr.call(&"load_level", data)
	out.append("old level subtree was renamed, detached and queue_free()d — anything parented inside it is gone.")

	var lvl := Common._level_node(tree)
	if lvl == null:
		out.append("! no \"Level\" child after the load — the scene may have instantiated null (reimport transient)")
	elif not Common._has_level_root_script(lvl):
		# ps1_warp.gd:43 gates cover() on `level_root is LevelRoot` and returns silently otherwise.
		out.append("! this level's root carries no level_root.gd, so Ps1Warp.cover() skipped it — no PS1 vertex-snap here.")
	out.append("nav: the fresh NavigationRegion3D needs a map-sync frame before any NPC can path.")
	# The old cast went with the level subtree and the new one boots with the AI live, so a latched `freezeai ON`
	# is now a lie — left set, the next bare `freezeai` would resolve to OFF and look like it did nothing.
	Common._state(ctx).erase(Common.STATE_FREEZE_AI)
	return out


static func _cmd_levels() -> PackedStringArray:
	var index := _levels()
	if index.is_empty():
		return Common._one("no LevelData resources under %s" % LEVEL_DIR)
	var active := String(GameState.current_level_path)
	var out := PackedStringArray()
	for stem in Common._sorted_keys(index):
		var path := String(index[stem])
		var data := load(path)
		var label := String(data.get("display_name")) if data != null else "?"
		var mark := "*" if path == active else " "
		out.append("%s %-18s %s" % [mark, stem, label])
	out.append("* = the active level (GameState.current_level_path)")
	return out


static func _cmd_reload(ctx: Dictionary) -> PackedStringArray:
	var tree := Common._tree(ctx)
	if tree == null:
		return Common._one("no SceneTree")
	var err := tree.reload_current_scene()
	if err != OK:
		return Common._one("reload_current_scene failed (error %d)" % err)
	var out := release_scene_scoped_state(ctx)
	out.append("reloading the current scene — every debug overlay parented into it is destroyed and must be re-toggled.")
	return out


## quicksave / slot save. Both MOVE the respawn checkpoint to the player's current spot before capturing
## (GameState._capture_and_write), and both return a bool that is the ONLY honest success signal — reporting
## "saved" off the call alone lies on a full disk or an off-tree player.
static func _cmd_save(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var player := Common._player(ctx)
	if player == null:
		return Common._one("no player — a save captures the live player and no-ops without one")
	if not player.is_inside_tree():
		return Common._one("player is off-tree — GameState refuses to write (that guard is what keeps unit tests from clobbering your save)")
	if GameState.reload_pending():
		return Common._one("a quickload is in flight (GameState.reload_pending) — persistence is frozen until the fresh scene boots")

	var out := PackedStringArray()
	var ok := false
	if args.is_empty():
		ok = bool(GameState.quicksave(player))
		out.append("quicksave: %s" % ("written" if ok else "FAILED (nothing hit disk)"))
	else:
		var slot := int(args[0].to_float())
		if slot < 1 or slot > GameState.SLOT_COUNT:
			return Common._one("slot must be 1..%d" % GameState.SLOT_COUNT)
		ok = bool(GameState.save_to_slot(player, slot))
		out.append("slot %d: %s" % [slot, "written" if ok else "FAILED (nothing hit disk)"])
	if ok:
		out.append("your respawn checkpoint MOVED here (a quick/slot save is your new checkpoint).")
		out.append("this is the exact-snapshot tier: live NPCs, cross-level kills and container contents were captured too.")
	return out


static func _cmd_load(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var tree := Common._tree(ctx)
	if tree == null:
		return Common._one("no SceneTree")
	var out := PackedStringArray()
	var ok := false
	if args.is_empty():
		if not GameState.has_quicksave():
			return Common._one("no quicksave on disk")
		ok = bool(GameState.quickload())
		out.append("quickload: %s" % ("reloading" if ok else "REFUSED (unreadable or off-tree)"))
	else:
		var slot := int(args[0].to_float())
		if slot < 1 or slot > GameState.SLOT_COUNT:
			return Common._one("slot must be 1..%d" % GameState.SLOT_COUNT)
		if not GameState.has_slot(slot):
			return Common._one("slot %d is empty" % slot)
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
		return Common._one("sandbox: this GameState has no sandbox API (sandbox_active / enable_sandbox / resolve_save_path) — nothing to drive")
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
	return Common._one("unknown sandbox action \"%s\" (on, off, status, commit)" % verb)


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
		return Common._one("sandbox: GameState has no enable_sandbox()")
	var out := PackedStringArray()
	if bool(GameState.call(&"sandbox_active")):
		# Deliberately NOT re-entered: enable_sandbox re-copies the real files INTO the sandbox, which would throw
		# away everything the sandbox run has written since. "Already on" is a report, not a reset.
		out.append("sandbox already ON — %s (nothing re-copied; `sandbox off` then `sandbox on` for a fresh copy)" % _sandbox_dir_text())
	else:
		var err := int(GameState.call(&"enable_sandbox"))
		var now_on := bool(GameState.call(&"sandbox_active"))
		if not now_on:
			return Common._one("sandbox on: enable_sandbox returned Error %d (%s) and the latch did NOT set — writes still go to the real profile" % [err, error_string(err)])
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
		return Common._one("sandbox is already OFF")
	if not GameState.has_method(&"disable_sandbox"):
		return Common._one("sandbox: GameState has no disable_sandbox()")
	if GameState.reload_pending():
		return Common._one("a quickload is in flight (GameState.reload_pending) — let the fresh scene boot before turning the sandbox off")
	var real_path := String(GameState.SAVE_PATH)
	if not FileAccess.file_exists(real_path):
		var refused := PackedStringArray()
		refused.append("sandbox off REFUSED — no real profile at %s to reload into, so the latch stays ON." % real_path)
		refused.append("! clearing it would let the next autosave write the sandbox run to the REAL path (a cheated Continue).")
		refused.append("`sandbox commit` first to make this run the real profile, then `sandbox off` — or relaunch (the sandbox is session-only).")
		return refused
	if not GameState.has_method(&"_load_and_reload"):
		return Common._one("sandbox off REFUSED — GameState has no _load_and_reload(path), so the real profile could not be reloaded; the latch stays ON. Relaunch to leave the sandbox.")

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
		return Common._one("sandbox is OFF — nothing to commit (`sandbox on`, play, then `sandbox commit`)")
	if not GameState.has_method(&"commit_sandbox"):
		return Common._one("sandbox: GameState has no commit_sandbox()")
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
	var tree := Common._tree(ctx)
	if tree == null:
		return Common._one("no SceneTree")
	var player := Common._player3d(ctx)
	if player == null:
		return Common._one("no player — spawn places bodies relative to you")

	var wanted := args[0]
	var profile_path := Common._lookup(_npcs(), wanted)
	if profile_path == "":
		return Common._one("no NpcData archetype \"%s\" — try: %s" % [wanted, ", ".join(Common._sorted_keys(_npcs()))])
	var profile := load(profile_path)
	if profile == null:
		return Common._one("could not load %s" % profile_path)

	var scene := load(NPC_SCENE_PATH) as PackedScene
	if scene == null:
		return Common._one("could not load %s" % NPC_SCENE_PATH)

	var requested := 1
	if args.size() > 1:
		requested = int(args[1].to_float())
	var count := clampi(requested, 1, MAX_SPAWN_COUNT)

	var parent := Common._level_node(tree)
	if parent == null:
		parent = tree.current_scene
	if parent == null:
		return Common._one("nowhere to parent the spawn (no level and no current scene)")

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
	var tree := Common._tree(ctx)
	var out := PackedStringArray()
	var index := _npcs()
	if index.is_empty():
		out.append("no NpcData archetypes under %s" % NPC_DIR)
	else:
		out.append("-- archetypes on disk (spawn by the name on the left)")
		for stem in Common._sorted_keys(index):
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
	var tree := Common._tree(ctx)
	if tree == null:
		return Common._one("no SceneTree")
	var player := Common._player(ctx)
	var player3 := Common._player3d(ctx)
	var radius := -1.0
	if not args.is_empty():
		radius = maxf(0.0, args[0].to_float())
		if player3 == null:
			return Common._one("a radius needs a player to measure from")

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
		n.call(&"take_damage", Common.KILL_DAMAGE, false, player)
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
	var tree := Common._tree(ctx)
	if tree == null:
		return Common._one("no SceneTree")
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
	var tree := Common._tree(ctx)
	if tree == null:
		return Common._one("no SceneTree")
	var player := Common._player(ctx)
	if player == null:
		return Common._one("no player to aggro onto")
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
	var tree := Common._tree(ctx)
	if tree == null:
		return Common._one("no SceneTree")
	var state := Common._state(ctx)
	var current := bool(state.get(Common.STATE_FREEZE_AI, false))
	var on := bool(DebugCommandsScript.toggle_value("" if args.is_empty() else args[0], current))
	var count := 0
	for n in tree.get_nodes_in_group(GroupsScript.NPC).duplicate():
		if not is_instance_valid(n) or not n.has_method(&"set_cutscene_control"):
			continue
		n.call(&"set_cutscene_control", on)
		count += 1
	state[Common.STATE_FREEZE_AI] = on
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
	var insp := Common._inspector(ctx)
	if insp == null:
		return Common._one("who: no DebugInspector available (%s missing, or the name is taken under the current scene)" % Common.INSPECTOR_SCRIPT_PATH)
	if not insp.has_method(&"describe_target"):
		return Common._one("who: DebugInspector has no describe_target()")
	var lines: PackedStringArray = insp.call(&"describe_target")
	if lines.is_empty():
		return Common._one("nothing under the crosshair")
	return lines


# =============================================================================================================
# AI — `notarget` only: the per-NPC verbs (who / brain / npc <verb>) live in debug_actions_world_npc.gd
# =============================================================================================================

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
	var player := Common._player(ctx)
	if player == null:
		return Common._one("no player to ghost")
	var tree := Common._tree(ctx)
	var state := Common._state(ctx)
	var current := player.has_meta(NOTARGET_META)
	var on := bool(DebugCommandsScript.toggle_value("" if args.is_empty() else args[0], current))
	var out := PackedStringArray()

	if not on:
		# "Already off" only when NOTHING is left to undo: no meta AND neither bank key (a Player stub with only one
		# of the two exports banks only that one, so test both — an orphaned zeroed export must still be restorable).
		if not current and not state.has(STATE_NOTARGET_NOISE_MOVE) and not state.has(STATE_NOTARGET_NOISE_GUN):
			return Common._one("notarget was already OFF")
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
		out.append("hostiles inside sight_range re-acquire you within ~%.1f s (the usual proximity pick, no LOS gate) and start DETECTING" % NpcActions._retarget_interval())
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
				guard_present = NpcActions._script_chain_has_const(n.get_script() as GDScript, "DEBUG_NOTARGET_META")
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
		out.append("%d NPC(s) hold you as _target right now — each drops it on its very next think tick (a held target that stops being an enemy re-acquires same-frame, no %.1f s throttle) and its perception falls to UNAWARE" % [holders, NpcActions._retarget_interval()])
	if banked.is_empty():
		out.append("noise exports: %s" % ("already zeroed by an earlier `notarget on`" if state.has(STATE_NOTARGET_NOISE_MOVE) else "NOT found on this Player (noise_move_per_speed / noise_gunfire_radius) — footsteps and gunfire may still pull hostiles into INVESTIGATING"))
	else:
		out.append("footsteps + gunfire silenced (%s) so the &\"noise\" scan cannot pull hostiles into INVESTIGATING either; a spike already in flight decays out over its usual ~0.6 s, and a hearing reaction ALREADY COMMITTED to (npc_ai.hearing_reaction_time) still fires — one guard may turn toward where you were" % ", ".join(banked))
	# The damage hook (npc.gd _on_damaged_by) locks the attacker by is_hostile_to — NOT _treats_as_enemy — and
	# alert_to()s its position. But the retarget check runs BEFORE the has-target branch every tick, so that lock is
	# dropped (same-frame re-acquire) before the body ever acts on it: the no-target tick then forget()s the stale
	# ALERTED outright (default settings) or, with hearing_initiates / body_discovery on, winds it down through sense()
	# as an investigation of your last spot. Either way it never faces, charges or fires at the ghost.
	out.append("! provoked but blind: shooting one still provoke()s it and sours its faction rep — the hit locks you for ONE tick, then the same-frame re-acquire drops you before it acts (the stale alert is forgotten, or wound down as an investigation if ambient hearing/body-discovery is on). Recruited companions are NOT ghosted; hostiles still fight them.")
	out.append("unlike `freezeai`, the AI keeps running — wander, schedules, home-return, NavLink climbs and NPC-vs-NPC fights all continue. `notarget off` restores; a reload frees the ghosted body anyway.")
	return out


# --- per-NPC helpers -----------------------------------------------------------------------------------------

# =============================================================================================================
# VIEW — `quantize` only (tests/test_color_quantization.gd pins it here): the rest lives in debug_actions_world_view.gd
# =============================================================================================================

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
		return Common._one("quantize: \"%s\" is not a depth index — pass 0..%d, or no argument to list them" % [word, count - 1])
	var want := int(roundi(word.to_float()))
	if want < 0 or want >= count:
		return Common._one("quantize: %d is outside 0..%d (0 = authored, %d = coarsest)" % [want, count - 1, count - 1])
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
	return "steps r%d g%d b%d = %s colours" % [int(levels.x), int(levels.y), int(levels.z), ViewActions._grouped(colors)]


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
	var tree := Common._tree(ctx)
	if tree == null or tree.root == null:
		return Common._one("screenshot: no SceneTree / root viewport to read")
	# validate() pinned the only word to `clean`, so presence is the whole test.
	var clean := not args.is_empty()
	var dir_err := DirAccess.make_dir_recursive_absolute(Common.SCREENSHOT_DIR)
	if dir_err != OK:
		return Common._one("screenshot: could not create %s (error %d %s)" % [Common.SCREENSHOT_DIR, dir_err, error_string(dir_err)])
	var path := ViewActions._next_screenshot_path()

	var driver := _ShotDriver.new()
	driver.name = "DebugScreenshot"
	driver.path = path
	driver.clean = clean
	if clean:
		driver.hidables = ViewActions._clean_hidables(tree)
		var player := Common._player(ctx)
		var ui := ViewActions._hud_layer(player)
		# A HUD the death cinematic owns is left to the cinematic (its fade IS the frame you would be capturing).
		if ui != null and not ViewActions._hud_owned_by_death(player):
			driver.hud_layer = ui
			# `hud off` already has the HUD down (and its bail latch armed): the driver must neither re-sweep from
			# scratch nor RELEASE it afterwards — releasing would re-derive the ring / minimap / clock over the dev's
			# own hide. HOLD mode: only the re-shown nodes are swept, and they join `hud off`'s snapshot (the ctx state
			# Dictionary is a reference, so the driver can extend it after the frame) instead of being restored.
			if _has_state(ctx, Common.STATE_HUD_HIDDEN):
				driver.hud_hold = true
				driver.hud_hold_state = Common._state(ctx)
	# add_child runs the driver's _ready synchronously, which is where the hide happens — still THIS frame, i.e.
	# before this frame's draw, which is the whole point.
	tree.root.add_child(driver)

	var out := PackedStringArray()
	out.append("screenshot: capturing the next drawn frame%s -> %s" % [
		" CLEAN (HUD + every 2D debug surface hidden for that one frame)" if clean else "", ProjectSettings.globalize_path(path)])
	out.append("  the result lands in this scrollback when the frame has been read (a line beginning \"screenshot:\").")
	return out


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
		ViewActions._echo_to_surfaces(tree, lines)
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
				_merge_hud_paths(ViewActions._hud_sweep_more(hud_layer))
			else:
				_hud_paths = ViewActions._hud_hide(hud_layer)

	## The pre-draw pass (see the class doc): anything hidden in _hide that came back, plus the HUD children the
	## Player's per-frame pushers re-showed. Merges into the same sets _restore reads, so the restore stays exact.
	func _hide_again() -> void:
		_sweep_hidables()
		if hud_layer != null and is_instance_valid(hud_layer):
			_merge_hud_paths(ViewActions._hud_sweep_more(hud_layer))

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
				var key: StringName = Common.STATE_HUD_HIDDEN
				if hud_hold_state.has(key):
					var held := ViewActions._hud_held_paths(hud_hold_state)
					for p in _hud_paths:
						if not held.has(p):
							held.append(p)
					hud_hold_state[key] = held
				hud_note = "HUD kept down (`hud off` in force; %d re-shown node(s) re-swept into its snapshot)" % _hud_paths.size()
			elif player != null and ViewActions._hud_owned_by_death(player):
				# Died INSIDE the captured frame: die()'s own sweep replaced the UI's list, and showing our nodes now
				# would paint HP bars over the fade. Hand them to the death sweep instead, so the revive restores them.
				ViewActions._hud_adopt_into_death_sweep(hud_layer, _hud_paths)
				hud_note = "died mid-capture — the %d hidden HUD node(s) were handed to the death sweep; the revive restores them" % _hud_paths.size()
			else:
				var shown := ViewActions._hud_show(hud_layer, _hud_paths)
				hud_note = "HUD restored (%d node(s))" % shown
		# Re-grab the focus the hidden frame dropped (see the class doc) — only if nothing else took it meanwhile.
		if _focus != null and is_instance_valid(_focus) and _focus.is_inside_tree() and _focus.is_visible_in_tree():
			if tree != null and tree.root != null and tree.root.gui_get_focus_owner() == null:
				_focus.grab_focus()
		out.append("  clean frame: hid %d debug surface(s), %s" % [restored, hud_note])
		return out


# --- hud ------------------------------------------------------------------------------------------------------

# --- lens: depth of field -------------------------------------------------------------------------------------

# --- lens: view-model mouse sway ------------------------------------------------------------------------------

# --- lens: the world barrel (fisheye) warp ---------------------------------------------------------------------

# --- dither ---------------------------------------------------------------------------------------------------

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
	var tree := Common._tree(ctx)
	if tree == null:
		return Common._one("no SceneTree")
	# The shipped overlay lives under the current scene; fall back to the whole tree for a designer who parented
	# it elsewhere (an autoload, a persistent HUD layer). Matched by SCRIPT, never by name.
	var ov := Common._find_by_script(tree.current_scene, DebugOverlayScript)
	if ov == null:
		ov = Common._find_by_script(tree.root, DebugOverlayScript)
	if ov == null:
		return Common._one("no DebugOverlay in the tree (game.tscn ships one; `perf` creates one) — there is no ErrorSink to read")
	var sink: Variant = ov.get(&"_sink")
	if sink == null or not is_instance_valid(sink):
		return Common._one("the DebugOverlay has no ErrorSink installed (release build, or capture_errors is off) — nothing is being captured")
	if not sink.has_method(&"recent"):
		return Common._one("the ErrorSink has no recent() — API drift between error_sink.gd and this command")

	var out := PackedStringArray()
	var errors := Common._int_of(sink.get(&"error_count"))
	var warnings := Common._int_of(sink.get(&"warning_count"))
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
	var kept := Common._int_of(sink.get(&"_max_recent"), recent.size())
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
		out.append("[%s] %s:%d %s — %s" % [tag, String(d.get("file", "")), Common._int_of(d.get("line")), String(d.get("function", "")), msg])
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
	var ok_count := Common._int_of(raw_count)
	var failed := Common._int_of(GameState.get(&"save_fail_count"))
	var last_msec := Common._int_of(GameState.get(&"last_save_msec"), -1)
	var raw_path: Variant = GameState.get(&"last_save_path")
	var last_path := String(raw_path) if raw_path is String else ""
	var last_err := Common._int_of(GameState.get(&"last_save_err"), OK)
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
		return Common._one("%s: the %s drop-in is not built (%s is not on disk) — nothing is recording and there is nothing to dump" % [label, cls, path])
	# has_method() SEES STATICS on a GDScript (cyber.gd:172-176 verified it — Script.has_static_method is not
	# exposed to scripts), so a renamed or de-static'd lines()/clear() is one honest line, not an invalid call. A
	# GDScript whose PARSE failed also comes back non-null from load() with an EMPTY function table (cyber.gd:169-171),
	# so this same guard is what turns a broken drop-in into a line instead of an "Invalid call" on script.call().
	if not script.has_method(&"lines") or not script.has_method(&"clear"):
		return Common._one("%s: %s exposes no static lines(count, filter) / clear() — did %s fail to compile (check the Output panel / `errors`), or was the API renamed?" % [label, cls, path])

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
			return Common._one("%s: no %s in the tree and none could be mounted (no current scene, or the name \"%s\" is taken by an unrelated node)" % [label, cls, String(node_name)])
		return Common._one("%s: no %s in the tree — nothing to hide (and nothing is recording); `%s 0 on` mounts one" % [label, cls, label])
	var setter: StringName = seam[&"set_visible"]
	var getter: StringName = seam[&"is_visible"]
	if not node.has_method(setter) or not node.has_method(getter):
		return Common._one("%s: %s has no %s() / %s() — API drift between %s and this command" % [label, cls, String(setter), String(getter), String(seam[&"path"])])
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
		return Common._one("%s: clear() ran but %d line(s) still read back (was %d) — check %s" % [label, after, before, String(seam[&"path"])])
	return Common._one("%s: cleared %d line(s) — the ring is a static, so this is the ONLY thing that empties it (reloads keep it)" % [label, before])


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
	var tree := Common._tree(ctx)
	if tree == null:
		return {&"node": null, &"created": false}
	var node := Common._find_by_script(tree.current_scene, script)
	if node == null:
		node = Common._find_by_script(tree.root, script)
	if node != null:
		return {&"node": node, &"created": false}
	if not mount or tree.current_scene == null:
		return {&"node": null, &"created": false}
	node = Common._find_or_create(tree.current_scene, node_name, script)
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
	var tree := Common._tree(ctx)
	if tree == null or tree.root == null:
		return Common._one("roundtrip: no SceneTree")
	var player := Common._player(ctx)
	if player == null:
		return Common._one("roundtrip: no player — the round trip captures the live one (open the console in-game, not on the menu)")
	if not player.is_inside_tree():
		return Common._one("roundtrip: the player is off-tree — GameState.capture would read nothing")
	if GameState.reload_pending():
		return Common._one("roundtrip: a quickload is in flight (GameState.reload_pending) — let the fresh scene boot first")
	if not ResourceLoader.exists(ROUNDTRIP_SCRIPT_PATH):
		return Common._one("roundtrip: the DebugRoundtrip harness is not built (%s is not on disk) — nothing reloaded" % ROUNDTRIP_SCRIPT_PATH)
	var script := load(ROUNDTRIP_SCRIPT_PATH) as GDScript
	if script == null:
		return Common._one("roundtrip: %s did not load as a GDScript — nothing reloaded" % ROUNDTRIP_SCRIPT_PATH)
	# The node name comes off the script's own constant map so a rename there cannot silently break the
	# "already running" find below; the local const is only the fallback.
	var node_name := StringName(str(script.get_script_constant_map().get("NODE_NAME", String(ROUNDTRIP_NODE_NAME))))
	if tree.root.get_node_or_null(NodePath(String(node_name))) != null:
		return Common._one("roundtrip: one is already running (the harness frees itself once its report lands in the console) — wait for it")

	var harness := script.new() as Node
	if harness == null:
		return Common._one("roundtrip: DebugRoundtrip.new() returned null (did %s fail to compile? check the Output panel / `errors`)" % ROUNDTRIP_SCRIPT_PATH)
	if not harness.has_method(&"begin"):
		harness.free()
		return Common._one("roundtrip: DebugRoundtrip has no begin(player) — API drift between debug_roundtrip.gd and this command")
	harness.name = node_name
	# ROOT, before begin(): the harness needs get_tree() for its captures, and root is the one parent that survives the
	# reload it is about to trigger (the console's own scene does not).
	tree.root.add_child(harness)
	var refusal := str(harness.call(&"begin", player))
	if refusal != "":
		harness.queue_free()
		return Common._one(refusal)

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
	var tree := Common._tree(ctx)
	if tree == null or tree.root == null:
		return Common._one("soak: no SceneTree")
	if tree.root.get_node_or_null(NodePath(String(SOAK_DRIVER_NAME))) != null:
		return Common._one("soak: one is already running (the driver frees itself once its report lands in the console) — wait for it")
	if GameState.reload_pending():
		return Common._one("soak: a quickload is in flight (GameState.reload_pending) — the level is about to change under the wave")
	var level := Common._level_node(tree)
	if level == null:
		return Common._one("soak: no \"Level\" in the tree — the wave needs a level with a baked NavigationRegion3D to wander")
	if not ResourceLoader.exists(SOAK_HARNESS_PATH):
		return Common._one("soak: %s is not on disk — nothing to run" % SOAK_HARNESS_PATH)
	var script := load(SOAK_HARNESS_PATH) as GDScript
	if script == null:
		return Common._one("soak: %s did not load as a GDScript" % SOAK_HARNESS_PATH)
	var harness := script.new() as Node
	if harness == null:
		return Common._one("soak: SoakHarness.new() returned null (did %s fail to compile? check the Output panel / `errors`)" % SOAK_HARNESS_PATH)
	if not harness.has_method(&"run_soak"):
		harness.free()
		return Common._one("soak: SoakHarness has no run_soak() — API drift between soak_harness.gd and this command")

	# Arguments over the harness's AUTHORED defaults (read back off the instance, never duplicated here), each capped.
	var requested_n := Common._int_of(harness.get(&"npc_count"), 4)
	if args.size() >= 1:
		requested_n = int(args[0].to_float())
	var count := clampi(requested_n, 1, MAX_SOAK_NPCS)
	var requested_s := Common._float_of(harness.get(&"stranded_seconds"), 12.0)
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
	var leak_waves := Common._int_of(harness.get(&"leak_waves"), 2)
	var wave_seconds := Common._float_of(harness.get(&"leak_wave_seconds"), 3.0)

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
	return Common._int_of(script.get_script_constant_map().get("STRANDED_THRESHOLD"), 3)


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

static func _host(ctx: Dictionary) -> Node:
	var raw: Variant = ctx.get(&"host")
	if not is_instance_valid(raw):
		return null
	return raw as Node


static func _has_state(ctx: Dictionary, key: StringName) -> bool:
	return Common._state(ctx).has(key)


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
## quickload all free the console WITHOUT passing through `reload`/`load` — and this dictionary is
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
	var state := Common._state(ctx)
	if state.has(STATE_TS_ALLOW):
		GameSettings.allow_timescale_changes = bool(state[STATE_TS_ALLOW])
		state.erase(STATE_TS_ALLOW)
		Engine.time_scale = 1.0
		out.append("timescale override released first — allow_timescale_changes back to %s (the reload would have destroyed the only record of it)." % str(bool(GameSettings.allow_timescale_changes)))
	state.erase(Common.STATE_FREEZE_AI)
	state.erase(STATE_NOTARGET_NOISE_MOVE)
	state.erase(STATE_NOTARGET_NOISE_GUN)
	state.erase(Common.STATE_NPC_STICKY)
	state.erase(Common.STATE_HUD_HIDDEN)
	return out


# =============================================================================================================
# tree lookups
# =============================================================================================================

## RentCollector is in NO group and has no registry — the shipping instance is a plain child node in the level
## scene. Re-found on every call because a level swap frees the old one.
##
## find_child matches by NAME ALONE, so the hit is confirmed against the SCRIPT before `clock` reads any field off
## it: every read there is a bare `rent.get(&"…")`, and Object.get() answers null for a property that does not
## exist — `float(null)` / `int(null)` is an invalid-constructor error, not a graceful 0. A designer who names some
## other node "RentCollector" would otherwise break the whole readout. Same script-path idiom as
## _has_level_root_script: no compile-time class dependency.
static func _find_rent_collector(tree: SceneTree) -> Node:
	var level := Common._level_node(tree)
	if level == null:
		return null
	var found := level.find_child("RentCollector", true, false)
	if found == null:
		return null
	var scr := found.get_script() as Script
	if scr == null or String(scr.resource_path).get_file() != "rent_collector.gd":
		return null
	return found


# =============================================================================================================
# content scans (disk, cached in statics — sources() runs on every Tab press)
# =============================================================================================================

## NpcData archetypes, keyed by FILE STEM. Deliberately not by identity_key(): "[PH] Beastmaster" is unusable as a
## console token, while the stem is short, unique and typeable.
static func _npcs() -> Dictionary:
	if _npc_scanned:
		return _npc_index
	_npc_scanned = true
	_npc_index = Common._scan(NPC_DIR, "npc_data.gd", "threat_response", "")
	return _npc_index


static func _levels() -> Dictionary:
	if _level_scanned:
		return _level_index
	_level_scanned = true
	_level_index = Common._scan(LEVEL_DIR, "level_data.gd", "display_name", "")
	return _level_index


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
