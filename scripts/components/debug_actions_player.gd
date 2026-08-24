class_name DebugActionsPlayer
extends RefCounted

## The IMPURE half of the debug tools for everything that lives on the PLAYER actor and the ECONOMY: every
## `DebugCommands` row whose `mod` is &"player" (the Player and Economy categories) runs through `run()` here.
## Statics only — there is no instance, no state of its own, and no node. Anything that must survive between
## commands (a god-mode snapshot, the teleport mark, the saved walk speed) lives in `ctx[&"state"]`, which the
## console/menu owns.
##
## WHO CALLS THIS
##  - `DebugConsole` (scripts/components/debug_console.gd) — parses a line with DebugCommands, then dispatches.
##  - `DebugMenu` (scripts/components/debug_menu.gd) — same rows, clicked instead of typed.
##  Both ALSO call `suspend_player()` / `restore_player()` below when they free the mouse. See that pair's note.
##
## CONTRACT WITH THE FRONT-ENDS
##  - `DebugCommands.validate()` has ALREADY run: arity is guaranteed, a Kind.NUMBER token is a valid float, and
##    a Kind.TOGGLE / Kind.VERB word is one of the allowed ones. So we never re-check those. We DO re-check
##    Kind.STAT / Kind.ITEM / Kind.PERK / Kind.FACTION / Kind.EFFECT, because those are only COMPLETION sources —
##    validate() never rejects an unknown id, and every registry in this project resolves a miss SILENTLY.
##  - Every node is null-guarded. `ctx[&"player"]` is legitimately null on the main menu and between levels.
##  - `run()` never pushes an error and never returns null: a failure is a one-line explanation in the result.
##
## ⭐SAVE SIDE EFFECTS ARE UNAVOIDABLE AND ACCEPTED. Nothing here is sandboxed by default: `add_money`
## and any `inventory.changed` queue a deferred `GameState.autosave` (player.gd:1106-1120), `add_xp` autosaves
## SYNCHRONOUSLY (player.gd:1362), and the account/flag paths queue `autosave_world_state()`. So a `give` or a
## `money` command overwrites the player's real user://gamestate.cfg on the spot — and so do `weapon` / `ammo fill`
## (inventory adds), `level` (add_xp, or the explicit autosave on the way down) and `ability` (the chip-installer
## autosave idiom, because a grant is only projected into the save by the next capture). That is the documented
## price of editing a live run; the only row flagged `danger` is `respec`, because it is the one you cannot walk
## back. Every one of those rows SAYS it wrote (and `_save_landed` says whether the write could even land). The ONE
## escape hatch is the world module's `sandbox on` (GameState.enable_sandbox), which redirects every profile write
## into user://sandbox/ for the session — `_save_where()` names which of the two a row just hit.
## The ONE file this module writes on its own account is MARKS_PATH (`mark <name>` / `marks <name>`): dev
## bookmarks, NOT a save — deliberately outside GameState's canonical paths so the Saves tab, the recovery ladder
## and the sandbox redirect never see it.
##
## ⭐THIS FILE MUST NEVER PAINT. `addons/cybersunday_tools/panel_audit/scan_text.gd` scans all of scripts/ for
## twelve paint-site shapes (`.text =`, `notify_toast(`, `push_toast(`, `make_title(`, …) and the debt ratchet in
## tests/test_player_text.gd is at ABSOLUTE ZERO. Only the console and the menu are in ScanText.SKIP_FILES, so
## this module returns Strings and paints none of them — do not add a toast here, hand the lines back instead.

## Brand-new sibling scripts are preloaded BY PATH into an untyped const, never referenced by their `class_name`:
## until the editor rescans, a class_name that isn't in the global script cache fails the WHOLE file to parse with
## "Could not find type X" and cascades into everything that preloads us. Precedent: debug_overlay.gd:11
## (ErrorSinkScript). [[new-classname-not-registered-cascade]]
const Commands := preload("res://scripts/components/debug_commands.gd")

## ⭐DebugNoclip is referenced by PATH and loaded LAZILY, not preloaded. Same reason as the rule above taken one
## step further: a `preload()` of a path that is not on disk YET is a HARD PARSE FAILURE, so preloading a sibling
## script that lands in the same change would take this whole module — and the console and menu that preload
## US — down with it until every file exists. A runtime load degrades to one honest line instead. Swap it back to
## a preload only if debug_noclip.gd is ever guaranteed to ship ahead of this file.
const NOCLIP_SCRIPT_PATH := "res://scripts/components/debug_noclip.gd"

## Registries that are NOT autoloads and carry no class_name — they must be preloaded by path (the
## reputation_screen.gd:26 / build_gate idiom). Zorkmids and Disposition DO have a class_name but are likewise
## plain scripts rather than autoloads, so they are preloaded here too for one consistent rule in this file.
const PerksReg := preload("res://scripts/player/perks.gd")
const FactionsReg := preload("res://scripts/faction/factions.gd")
const ZorkmidsReg := preload("res://scripts/items/zorkmids.gd")
const DispositionReg := preload("res://scripts/npc/disposition.gd")
## The ability id registry (no class_name ON PURPOSE — ability_registry.gd:8) — statics only: ids() is a
## DirAccess scan documented editor/test-grade (fine for a debug listing), can_build()/script_path_for()/
## display_name_for() are direct-path and export-safe. AbilityManager preloads it the same way.
const AbilityReg := preload("res://scripts/components/abilities/ability_registry.gd")

## There is no registry, id scan or `ids()` for StatusEffects — unlike perks / factions / items. The folder scan
## below is the whole thing; `effect <id>` and the &"effect" completion source both key off it.
const EFFECT_DIR := "res://resources/status/"

## user://debug_marks.cfg — the persistent named bookmarks (`mark <name>` / `goto <name>` / `marks`).
## A ConfigFile: one SECTION per level identity (GameState.current_level_path — the LevelData res:// path, so a
## mark can never be replayed into the wrong level's coordinates), one KEY per mark (mark_key(name)), the VALUE a
## Dictionary {"x", "y", "z", "yaw"} of floats (MARKS_VALUE_KEYS — plain numbers, so a developer can hand-edit
## the file). The engine's text writer decides the digit count (VariantWriter has historically printed floats
## with %lg = 6 significant digits — centimetre-grade at map scale, plenty for a teleport target), which is why
## tests/test_debug_marks.gd pins the shape and the round trip on dyadic values that survive ANY writer.
## ⭐WHY A FILE AT ALL: `mark`/`back` are one slot in ctx[&"state"], which is the console NODE's dict — the console
## lives in scenes/game.tscn and `reload`/`load`/a death rebuild it, so the transient mark dies on exactly the
## reload a nav-repro loop needs. ⭐It is a dev file under user:// ONLY — never a project file, never a save
## (not routed through GameState.resolve_save_path on purpose: the sandbox must not fork it and the recovery
## ladder must not repair it). Nothing else in this module writes under user://.
const MARKS_PATH := "user://debug_marks.cfg"
## The four value keys of one stored mark, in the order they are written. String keys ON PURPOSE (not
## StringName): ConfigFile text round-trips String keys as Strings, so a read compares like-for-like.
const MARKS_VALUE_KEYS: PackedStringArray = ["x", "y", "z", "yaw"]

## Readout words for Disposition.Kind. Mapped by NAME in _disposition_word(), never by ordinal: the enum's order
## (HOSTILE < NEUTRAL < FRIENDLY) is load-bearing in Reputation's threshold mapping (disposition.gd:12-17), and a
## positional list here would silently mislabel every faction if that order were ever revised.
const DISPOSITION_HOSTILE := "hostile"
const DISPOSITION_NEUTRAL := "neutral"
const DISPOSITION_FRIENDLY := "friendly"

## `ctx[&"state"]` key a front-end MAY publish its `suspend_player()` snapshot under. OPTIONAL — nothing depends
## on it any more, and neither shipped front-end does it (both hold the snapshot privately). `revive` patches the
## snapshot when it finds one here, but correctness now rides on SUSPEND_META + restore_player's revived-under-us
## branch below, which need no cooperation from the host at all.
const SUSPEND_STATE_KEY := &"player/suspend"

## Node meta stamped on the player for exactly as long as a debug UI holds it suspended, and cleared by
## `restore_player`. ⭐It exists because `revive` MUST know whether somebody else currently owns the player's
## physics bit, and the ctx-state probe above cannot answer that: both shipped front-ends keep their snapshot
## PRIVATELY (debug_console.gd:117 `_suspend_snapshot`, debug_menu.gd:136 `_suspend`) instead of publishing it
## under SUSPEND_STATE_KEY, so the probe reads "nobody is holding the player" while the console is wide open.
## Reviving on that answer would hand movement AND fire back under a free cursor — mouse_input._process polls
## `Attack` every frame (mouse_input.gd:39-45), so the next click on a menu button shoots. Meta is per-node and
## never persisted, so nothing can outlive the UI that set it.
const SUSPEND_META := &"debug_suspend_held"

# --- debug magnitudes -------------------------------------------------------------------------------------
# This module is a statics-only RefCounted (the front-ends are the drag-drop components), so it cannot carry
# @export knobs. These are DEBUG SENTINELS, not gameplay tuning a designer balances — the real gameplay numbers
# they stand in for all live on GameSettings resources and are snapshotted/restored, never overwritten here.

## God mode's armour value. `Character.take_damage` does `maxf(0.0, (amount - armor_flat) * (1 - reduction))`
## (character.gd:376), so any value past the largest conceivable hit zeroes every mitigated damage path.
const GOD_ARMOR_FLAT := 1.0e9
## Headroom added on top of hp + armour when forcing a lethal `take_damage`, so rounding can never leave 0.1 hp.
const KILL_OVERKILL := 1000.0
## How far `tpaim` casts for a surface.
const TP_AIM_RANGE := 500.0
## How far SHORT of the hit point `tpaim` lands you, along the surface normal — roughly the player capsule's
## radius, so you arrive beside the wall/floor you aimed at instead of embedded in it.
const TP_AIM_SURFACE_OFFSET := 0.6
## How far INSIDE a body-part zone `hurt <part>` / `cripple <part>` compose their hit point (LOCAL metres past the
## zone edge). Character.body_part_at (character.gd:646) classifies HEAD as `y >= head_local_y`, LEGS as
## `y < leg_local_y` and ARMS as `|x| >= arm_local_x` inside the torso band, so a point sitting exactly ON an
## edge is ambiguous; this margin puts it unambiguously inside. The composed point is re-classified before use.
const BODY_ZONE_MARGIN := 0.05
## Headroom past a limb's remaining condition pool when `cripple` drains it: `_apply_limb_damage` cripples on
## `pool <= 0.0` (character.gd:711), so any positive overshoot lands it whatever the float rounding.
const CRIPPLE_OVERKILL := 1.0
## `ammo fill` adds this many CLIPS of every registered ammo item. Reserve ammo is counted in whole clips
## (Ammo._refilled_clip spends ONE per reload, ammo.gd:113), and the ammo items weigh 0.2-1.0 each, so 10 of
## each is a full fight's worth without instantly burying the default carry capacity (20) — the readout prints
## the carry weight before/after regardless. Not designer tuning: a debug fill amount (`give ammo_x <n>` for exact).
const AMMO_FILL_CLIPS := 10
## The unscaled ammo cost `ammo off` falls back to when the banked original is missing (Ammo.ammo_cost's own
## default, ammo.gd:19) — only reachable if the state dict was lost while the cheat was armed.
const AMMO_COST_DEFAULT := 1
## `level <n>` grants `need / xp_gain_mult` XP and add_xp multiplies it back (player.gd:1348); with a
## non-unit multiplier that round trip can land ONE ULP short of xp_to_reach(n), which level_for_xp then reads as
## the level below. This nudge is invisible at the two decimals every XP readout prints and guarantees the crossing.
const XP_EXACT_EPS := 0.001
## XpSettings.level_for_xp stops at 9999 (XpSettings.gd:28, its runaway backstop), so a level past that can
## never be REPORTED by the curve — `level` clamps to it and says so instead of writing an unreachable number.
const LEVEL_CAP := 9999


# --- entry point ------------------------------------------------------------------------------------------

## Dispatch one already-validated command. `args` are the tokens AFTER the command name. Returns the lines to
## print — never null, never empty, never an engine error.
static func run(cmd: String, ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	# ⭐is_instance_valid FIRST, before any type test: `is`/`as` CRASH on a freed instance, and ctx[&"player"] can
	# legitimately hold one after a level swap or a scene reload.
	var player_node = ctx.get(&"player", null)
	var p: Player = null
	if is_instance_valid(player_node):
		p = player_node as Player  # null for a non-Player node too — every branch below guards on it
	match cmd:
		# --- Player -------------------------------------------------------------------------------------
		"god": return _god(ctx, p, args)
		"heal": return _heal(p, args)
		"hurt": return _hurt(p, args)
		"cripple": return _cripple(p, args)
		"me": return _me(ctx, p)
		"ability": return _ability(p, args)
		"kill": return _kill(p)
		"revive": return _revive(ctx, p)
		"noclip": return _noclip(ctx, p, args)
		"speed": return _speed(ctx, args)
		"stamina": return _stamina(p, args)
		"tp": return _tp(ctx, p, args)
		"tpaim": return _tpaim(ctx, p)
		"mark": return _mark(ctx, p, args)
		"goto": return _goto(ctx, p, args)
		"marks": return _marks(args)
		"back": return _back(ctx, p)
		"pos": return _pos(p)
		"stat": return _stat(p, args)
		"stats": return _stats(p)
		# --- Economy ------------------------------------------------------------------------------------
		"money": return _money(p, args)
		"bank": return _bank(args)
		"credit": return _credit(args)
		"xp": return _xp(p, args)
		"sp": return _sp(p, args)
		"perk": return _perk(p, args)
		"perks": return _perks(p)
		"respec": return _respec(p)
		"weapon": return _weapon(p, args)
		"ammo": return _ammo(ctx, p, args)
		"level": return _level(p, args)
		"give": return _give(p, args)
		"items": return _items(args)
		"effect": return _effect(p, args)
		"effects": return _effects(p)
		"cleareffects": return _clear_effects(p)
		"rep": return _rep(args)
		"reps": return _reps()
	return PackedStringArray(["%s: not a player/economy command" % cmd])


# --- completion sources -----------------------------------------------------------------------------------

## Ids this module owns, keyed by DebugCommands.SOURCE_KEYS so the console and the registry can never drift on a
## spelling. Called on EVERY Tab press, so the three DirAccess folder scans behind it are cached in static vars —
## Perks.ids() / Factions.ids() / the status scan each load every .tres in their folder and are documented as
## editor/test-grade, never a hot path. Items come from the ItemDb autoload's in-memory registry (built once at
## boot), so those are cheap enough to re-read live.
static func sources() -> Dictionary:
	var keys: Dictionary = Commands.SOURCE_KEYS
	var out := {}
	out[keys[Commands.Kind.ITEM]] = _item_ids()
	out[keys[Commands.Kind.PERK]] = _perk_ids()
	out[keys[Commands.Kind.FACTION]] = _faction_ids()
	out[keys[Commands.Kind.EFFECT]] = _effect_ids()
	out[keys[Commands.Kind.STAT]] = CharacterStats.stat_names()
	out[keys[Commands.Kind.ABILITY]] = _ability_ids()
	return out


## Ability ids for Tab completion: AbilityRegistry.ids() (a DirAccess scan documented editor/test-grade, cached
## here once per session because sources() runs on every Tab press) plus the `all` word the `ability` row accepts.
static var _ability_ids_cache := PackedStringArray()
static var _ability_ids_scanned := false

static func _ability_ids() -> PackedStringArray:
	if not _ability_ids_scanned:
		_ability_ids_scanned = true
		_ability_ids_cache = PackedStringArray(["all"])
		var ids: PackedStringArray = AbilityReg.ids()
		for id in ids:
			_ability_ids_cache.append(String(id))
	return _ability_ids_cache


static var _perk_ids_cache := PackedStringArray()
static var _perk_ids_scanned := false
static var _faction_ids_cache := PackedStringArray()
static var _faction_ids_scanned := false
## effect id (String) -> its res:// path. Populated once by _scan_effects().
static var _effect_paths_cache := {}
static var _effects_scanned := false


static func _item_ids() -> PackedStringArray:
	var out := PackedStringArray()
	if not is_instance_valid(ItemDb):
		return out
	for item in ItemDb.all_items():
		if item != null and item.id != &"":
			out.append(String(item.id))
	out.sort()
	return out


static func _perk_ids() -> PackedStringArray:
	if not _perk_ids_scanned:
		_perk_ids_scanned = true
		_perk_ids_cache = PerksReg.ids()
	return _perk_ids_cache


## NOTE the split the survey flagged: Factions.ids() returns FILENAMES while Reputation keys on the INTERNAL
## Faction.id. Completion is fed from the filenames (that is what `by_id` resolves), but every OPERATION below
## keys off `by_id(...).id`, so a drifted .tres cannot silently write into the wrong rep pool.
static func _faction_ids() -> PackedStringArray:
	if not _faction_ids_scanned:
		_faction_ids_scanned = true
		_faction_ids_cache = FactionsReg.ids()
	return _faction_ids_cache


static func _effect_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _scan_effects():
		out.append(String(id))
	out.sort()
	return out


## Scan resources/status/ once and map each StatusEffect's INTERNAL id to its path (falling back to the filename
## for a blank id — StatusEffect.id may legitimately be empty, which is the "always stack, never refresh"
## contract at status_effect.gd:13). Type-filtered like Perks.ids(): another resource parked in the folder must
## not offer an id that apply_effect could never use.
static func _scan_effects() -> Dictionary:
	if _effects_scanned:
		return _effect_paths_cache
	var dir := DirAccess.open(EFFECT_DIR)
	if dir == null:
		# Latch only on a SUCCESSFUL scan. A DirAccess miss (an editor/import window where res:// is not yet
		# walkable) must not cache "no effects exist" for the whole session — the retry is one failed open.
		return _effect_paths_cache
	_effects_scanned = true
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")  # an exported build appends .remap to packed resources
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		var path := EFFECT_DIR.path_join(f)
		var res := load(path)
		if res is StatusEffect:
			var key := String((res as StatusEffect).id)
			if key == "":
				key = f.get_basename()
			_effect_paths_cache[key] = path
	return _effect_paths_cache


# --- the shared suspend/restore pair ----------------------------------------------------------------------

## Freeze the player so a debug UI can free the mouse without the player walking, ducking or FIRING behind it.
##
## WHY IT IS HAND-ROLLED. There is no generic "suppress gameplay" flag in this project:
## `InputManager.gameplay_suppressed()` is exactly `any_modal_open() or CutscenePlayer.is_active() or
## NameEntryDialog.is_open()` (InputManager.gd:185), and the only way in is a row in `InputManager._modal_reg` —
## which would force edits to three hard-pinned assertions in tests/test_modal_registry.gd (the `screens.size()`
## count and the blocks/allows partition). We deliberately stay out of the registry, exactly as
## docs/AUTHORING_GUIDE.md:4269 says dev tooling should.
##
## So we copy what `Player.die()` does by hand, and for the same reasons it does it:
##   * `set_physics_process(false)` (player.gd:2835) — Player._physics_process is one ~175-line function that
##     owns gravity, movement, apply_velocity and the fall-death timer. A child node cannot pre-empt it.
##   * `mouse_input.set_process(false)` + `set_process_unhandled_input(false)` (player.gd:2859) — mouse_input's
##     _process POLLS `Input.is_action_pressed("Attack")` gated only on gameplay_suppressed(), so without this a
##     click on one of the menu's own buttons FIRES THE WEAPON. Mouse-look is already dead once the cursor is
##     visible (mouse_input.gd:31 gates on MOUSE_MODE_CAPTURED), but auto-fire is not.
##   * `crouch.set_physics_process(false)` (player.gd:2891) — Crouch owns a separate physics callback and would
##     keep reading the Crouch action, shrinking the capsule under an open menu.
##
## ⭐THE SNAPSHOT IS OF THE ACTUAL CURRENT VALUES, not of `true`. Opening the console over a DEAD player (whose
## physics die() already turned off) or over an already-suspended one and closing it again must NOT resurrect
## anything. `restore_player` writes back exactly what was read here — with ONE documented exception, for a body
## that was a corpse at suspend and has been `revive`d since. See restore_player.
##
## Returns the snapshot to hand to `restore_player`. An empty-ish snapshot (`valid` false) is safe to restore.
static func suspend_player(player: Node) -> Dictionary:
	if not is_instance_valid(player):  # ⭐validity BEFORE the cast — `as` on a freed instance crashes
		return {&"valid": false}
	var p: Player = player as Player
	if p == null:
		return {&"valid": false}
	var snap := {
		&"valid": true,
		&"physics": p.is_physics_processing(),
		&"mouse": false,
		&"mouse_unhandled": false,
		&"mouse_valid": false,
		&"crouch": false,
		&"crouch_valid": false,
		# ⭐Was the body ALIVE when we froze it? This is the ONE fact that makes an exact restore safe: see
		# restore_player, which needs it to tell "this player was already frozen, leave it frozen" apart from
		# "this player was a corpse and has since been revived under us".
		&"alive": p.is_alive(),
	}
	p.set_meta(SUSPEND_META, true)
	p.set_physics_process(false)
	# The authored NodePaths (Player.tscn wires `mouse_input` -> the "MouseInput" child and `crouch` -> "Crouch");
	# both are @exports, so a hand-built test Player can legitimately leave them null.
	if is_instance_valid(p.mouse_input):
		snap[&"mouse_valid"] = true
		snap[&"mouse"] = p.mouse_input.is_processing()
		snap[&"mouse_unhandled"] = p.mouse_input.is_processing_unhandled_input()
		p.mouse_input.set_process(false)
		p.mouse_input.set_process_unhandled_input(false)
	if is_instance_valid(p.crouch):
		snap[&"crouch_valid"] = true
		snap[&"crouch"] = p.crouch.is_physics_processing()
		p.crouch.set_physics_process(false)
	return snap


## Undo `suspend_player`, writing back the values it read (see the revived-under-us exception below). Safe to
## call with an empty dictionary, with a snapshot for a player that has since been freed, or twice.
##
## Note what this deliberately does NOT restore: the weapon holster and the FP legs/fists. `suspend_player` never
## touched them (die() does, and its in-place revive is what puts them back), so neither does this.
static func restore_player(player: Node, snapshot: Dictionary) -> void:
	if not is_instance_valid(player) or not bool(snapshot.get(&"valid", false)):
		return
	var p: Player = player as Player
	if p == null:
		return
	if p.has_meta(SUSPEND_META):
		p.remove_meta(SUSPEND_META)  # guarded: some Object::remove_meta builds error on a key that is not there
	# ⭐THE ONE CASE WHERE AN EXACT RESTORE IS WRONG. Open the console over a CORPSE and the snapshot honestly
	# records die()'s frozen bits (physics/mouse/crouch all off). Run `revive`, close the console, and writing
	# that snapshot back re-freezes a LIVING player — with the cursor recaptured, no input path left to reach
	# the console again and no owner left to thaw it (die() is the only non-debug writer of those bits, and
	# DebugNoclip's _tick_unfreeze_grace only heals its OWN half of this hole). So a
	# body that was DEAD at suspend and is ALIVE now is handed back running, whatever the snapshot says.
	# Everything else still restores verbatim: a player frozen while alive (a future cutscene lock, a nested
	# debug UI) reads alive == true and keeps its freeze exactly as found.
	var revived_under_us := not bool(snapshot.get(&"alive", true)) and p.is_alive()
	p.set_physics_process(revived_under_us or bool(snapshot.get(&"physics", true)))
	if bool(snapshot.get(&"mouse_valid", false)) and is_instance_valid(p.mouse_input):
		p.mouse_input.set_process(revived_under_us or bool(snapshot.get(&"mouse", true)))
		p.mouse_input.set_process_unhandled_input(revived_under_us or bool(snapshot.get(&"mouse_unhandled", true)))
	if bool(snapshot.get(&"crouch_valid", false)) and is_instance_valid(p.crouch):
		p.crouch.set_physics_process(revived_under_us or bool(snapshot.get(&"crouch", true)))


# --- Player commands --------------------------------------------------------------------------------------

## `god [on|off]` — immunity. TWO knobs, because ONE is not enough:
##  1. `armor_flat` (character.gd:602, applied at :376) nulls every hit that goes through take_damage, which is
##     the single funnel for all attributed damage (bullets, melee, blasts, hazards, DoT, fall damage).
##  2. ⭐`GameSettings.player_movement.max_continuous_fall_time = 0` — because `_die_from_continuous_fall`
##     (player.gd:1216) writes `hp = 0.0` DIRECTLY and never calls take_damage, so armour cannot stop it. The
##     check early-outs on `limit <= 0.0` (player.gd:1202), which is why zero means "disabled".
## ⭐That second knob is a PRELOADED SHARED .tres on an autoload (GameSettings.gd:102). Writing it changes the
## project's tuning for the whole session, survives scene and death reloads, and with the editor open can be
## written back to disk — so the authored value is snapshotted into ctx state and restored on `god off`.
static func _god(ctx: Dictionary, p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var st := _state(ctx)
	# ⭐THE FLAG IS NOT THE TRUTH — the two knobs live in different lifetimes. `ctx[&"state"]` belongs to the
	# console/menu, which is mounted OUTSIDE the level subtree and therefore outlives every level WARP (a warp
	# frees only the Level subtree); `armor_flat` lives on the Player, which the death-respawn path can rebuild.
	# A full scene RELOAD frees the console too — its _exit_tree calls release_scene_scoped_state, which restores
	# the fall-time knob and erases these keys, so the fresh console starts clean. What this guard covers is the
	# in-between: the flag still says "on" over a player with no armour, and a bare `god`/`god on` would answer
	# "already on" and leave you mortal. `armed` is the player's own state, `flagged` is the bookkeeping; a
	# disagreement means the body was replaced and we RE-APPLY rather than report a no-op. (The fall-time knob is
	# on a shared autoload resource and survives a body swap, which is why re-arming below must not re-snapshot
	# it — its current 0.0 is OUR write, not the authored value.)
	var flagged := bool(st.get(&"player/god", false))
	var armed := p.armor_flat >= GOD_ARMOR_FLAT
	var current := flagged and armed
	var want := Commands.toggle_value(_word(args, 0), current)
	if want == current and flagged == armed:
		return PackedStringArray(["god: already %s" % _onoff(current)])
	var out := PackedStringArray()
	if want:
		# Snapshot the AUTHORED values before clobbering either one — but NEVER snapshot a value we already wrote.
		# Re-arming after a scene reload must keep the ORIGINAL fall time: the live one is still our 0.0, and
		# re-recording it would make `god off` "restore" the cheat permanently into the project's shared tuning
		# resource. Same for armour: 1e9 already on the body is our sentinel, not a designer's number.
		if GameSettings.player_movement.max_continuous_fall_time > 0.0:
			st[&"player/god_fall_time"] = GameSettings.player_movement.max_continuous_fall_time
		if not armed:
			st[&"player/god_armor"] = p.armor_flat
		p.armor_flat = GOD_ARMOR_FLAT
		GameSettings.player_movement.max_continuous_fall_time = 0.0
		st[&"player/god"] = true
		out.append("god: on")
		if flagged and not armed:
			out.append("  (re-armed: a scene reload replaced the player, which reset armor_flat)")
		out.append("  armor_flat %s -> %s (every take_damage path mitigates to 0)" % [_num(float(st.get(&"player/god_armor", 0.0))), _num(GOD_ARMOR_FLAT)])
		out.append("  continuous-fall death disabled (it writes hp=0 directly and armour cannot stop it)")
		out.append("  the hit flash and hurt feedback still fire on a fully-soaked hit")
	else:
		p.armor_flat = float(st.get(&"player/god_armor", 0.0))
		GameSettings.player_movement.max_continuous_fall_time = float(st.get(&"player/god_fall_time", 4.0))
		st.erase(&"player/god_armor")
		st.erase(&"player/god_fall_time")
		st[&"player/god"] = false
		out.append("god: off")
		out.append("  armor_flat restored to %s" % _num(p.armor_flat))
		out.append("  continuous-fall death restored to %ss" % _num(GameSettings.player_movement.max_continuous_fall_time))
	return out


## `heal [amount]` — heal by amount, or to full. ⭐`Character.heal()` (character.gd:577) accepts a NEGATIVE amount
## and silently drains hp with no death check, no _dead latch and no flash, so the sign is guarded here: taking
## damage is `hurt`'s job, which runs the real pipeline. heal() itself emits `damaged`, which is what keeps the HP
## bar, the low-HP vignette/heartbeat and the player-carried health light from going stale.
static func _heal(p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var before := p.hp
	var amount := p.max_hp - p.hp
	if args.size() > 0:
		amount = args[0].to_float()
		if amount <= 0.0:
			return PackedStringArray(["heal: amount must be positive — Character.heal() would silently DRAIN hp with no death check. Use `hurt` to take damage."])
	p.heal(amount)
	p.heal_limbs()
	var out := PackedStringArray(["heal: hp %s -> %s / %s (limbs cleared)" % [_num(before), _num(p.hp), _num(p.max_hp)]])
	if not p.is_alive():
		out.append("  note: still flagged dead — hp alone does not clear the latch, run `revive`")
	return out


## `hurt <amount> [head|arms|legs|torso]` — damage through the REAL funnel, so armour, difficulty scaling, limb
## damage, the hit flash, the aggro hook and (if lethal) the bounty/wallet-bequeath/death sequence all run exactly
## as in play.
##
## ⭐With a body part the hit is LOCATED: `hit_pos` is composed in the player's LOCAL frame to sit inside the zone
## `Character.body_part_at` (character.gd:646) classifies as that part, and passed as take_damage's 4th argument
## (character.gd:361) so `_apply_limb_damage` (:704, gated on `hit_pos.is_finite()` at :413) chips that limb's
## pool with the MITIGATED amount — the same difficulty/armour math the HP loss took, so under god mode the chip
## is 0 too and the "nothing landed" reason covers both. Without a part `hit_pos` stays Vector3.INF and the limb
## branch is skipped, exactly the pre-existing behaviour. Torso is accepted for symmetry but never cripples (:706).
static func _hurt(p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var amount := args[0].to_float()
	if amount <= 0.0:
		return PackedStringArray(["hurt: amount must be positive — a negative amount is a heal with no clamp"])
	var part := -1
	var hit_pos := Vector3.INF
	if args.size() > 1:
		part = _body_part_for_word(args[1])
		if part < 0:
			return PackedStringArray(["hurt: unknown body part \"%s\" — head, arms, legs or torso" % args[1]])
		hit_pos = _hit_pos_for_part(p, part)
		if p.body_part_at(hit_pos) != part:
			return PackedStringArray([_zone_overlap_reason("hurt", p, part)])
	var before := p.hp
	var pool_before := _limb_pool(p, part)
	var crippled_before := part >= 0 and p.is_limb_crippled(part)
	p.take_damage(amount, false, null, hit_pos)
	var out := PackedStringArray(["hurt: %s -> hp %s -> %s / %s" % [_num(amount), _num(before), _num(p.hp), _num(p.max_hp)]])
	if is_equal_approx(before, p.hp):
		out.append("  nothing landed — " + _damage_blocked_reason(p))
	if part == Character.BodyPart.TORSO:
		out.append("  torso: located hit, but the torso has no condition pool and never cripples (character.gd:706)")
	elif part >= 0:
		var word := _body_part_word(part)
		if crippled_before:
			out.append("  %s: already crippled — a crippled limb takes no further chip (`heal` clears it)" % word)
		else:
			var pool_after := _limb_pool(p, part)
			out.append("  %s pool %s -> %s / %s%s" % [word, _num(pool_before), _num(maxf(0.0, pool_after)), _num(_limb_pool_full(p)), (" — CRIPPLED now" if p.is_limb_crippled(part) else "")])
			if p.is_limb_crippled(part):
				out.append("  " + _cripple_effect_line(p, part))
		out.append("  limb state is NOT persisted (heal_limbs on respawn/reuse) — a reload clears it, and so does `heal`")
	return out


## `cripple <head|arms|legs>` — empty ONE limb's condition pool with no HP loss, so the limb penalties (limp,
## spread, concussion) and every "limb damage" gate — the Healer / heal-screen row, the Wait screen's heals_limbs,
## the bonfire — can be tested without being shot in the leg a dozen times.
##
## Goes through `_apply_limb_damage` (character.gd:704) rather than poking `_crippled` by hand, so the real cripple
## path runs: `_crippled[part] = true` AND `_on_limb_crippled` (:847 — the cripple SFX, and for HEAD
## Player._on_head_crippled player.gd:1713 -> hurt-feedback pulse + toast). Underscore-private, same precedent as
## `stamina`'s `_set_stamina`. The amount is the limb's REMAINING pool (lazily seeded at max_hp x
## limb_condition_frac, :708) plus CRIPPLE_OVERKILL, so a half-chipped limb lands too. `hit_pos` is composed
## exactly as `hurt <part>` does, because `_apply_limb_damage` re-classifies it through body_part_at.
static func _cripple(p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var part := _body_part_for_word(args[0])
	if part < 0 or part == Character.BodyPart.TORSO:
		return PackedStringArray(["cripple: \"%s\" — head, arms or legs only (the torso never cripples, character.gd:706)" % args[0]])
	var word := _body_part_word(part)
	if p.is_limb_crippled(part):
		return PackedStringArray(["cripple: %s already crippled — `heal` clears it (heal_limbs)" % word])
	var hit_pos := _hit_pos_for_part(p, part)
	if p.body_part_at(hit_pos) != part:
		return PackedStringArray([_zone_overlap_reason("cripple", p, part)])
	var pool := _limb_pool(p, part)
	var hp_before := p.hp
	p._apply_limb_damage(hit_pos, maxf(pool, 0.0) + CRIPPLE_OVERKILL)  # attacker null: an unattributed cripple
	var out := PackedStringArray()
	if not p.is_limb_crippled(part):
		return PackedStringArray(["cripple: %s NOT crippled — _apply_limb_damage refused (pool was %s)" % [word, _num(pool)]])
	out.append("cripple: %s CRIPPLED (pool %s -> 0, hp untouched at %s)" % [word, _num(pool), _num(hp_before)])
	out.append("  " + _cripple_effect_line(p, part))
	out.append("  has_limb_damage %s — the Healer / heal-screen / Wait / bonfire limb rows key on it; cripple SFX played if authored" % _onoff(p.has_limb_damage()))
	out.append("  not persisted: heal_limbs runs on respawn/reuse, so a reload clears it — `heal` clears it now")
	return out


## `me` — the player self-readout: everything the F3 block and the F4 inspector deliberately do NOT show. READ ONLY.
## "Why am I slow / why can't I draw / why does my aim wobble" is a product of eight hidden factors
## (GroundMovement.compute_target_speed, ground_movement.gd:16-38) plus private dicts, so every factor is printed
## beside its total. Every member read here was verified against player.gd / character.gd / ground_movement.gd /
## weapon_system.gd / attack.gd; a component a hand-built Player leaves null degrades to an "n/a" line.
static func _me(ctx: Dictionary, p: Player) -> PackedStringArray:
	if p == null:
		return _no_player()
	var out := PackedStringArray()
	var life := "alive" if p.is_alive() else "DEAD"
	if bool(p.get(&"_dying")):
		life += " (death cinematic running)"
	out.append("me: hp %s / %s   stamina %s / %s   %s   xp %s level %d" % [_num(p.hp), _num(p.max_hp), _num(p.stamina), _num(p.stamina_max()), life, _num(p.xp), p.level])

	# --- the speed chain ---------------------------------------------------------------------------------
	# ⭐is_instance_valid on every component BEFORE it is dereferenced. compute_target_speed reads
	# `player.crouch.crouch_t` UNGUARDED (ground_movement.gd:22), so the Crouch child is the one hard requirement;
	# the weapon hub it reads by truthiness (`if player.weapon_system and ...attack`, :32), and a freed Object is
	# falsy in Godot 4 ([[held-prop-freed-permanent-stuck]]), so a freed/absent hub only drops the weapon factor.
	var ws: Weapon = p.weapon_system if is_instance_valid(p.weapon_system) else null
	var attack: Attack = null
	if ws != null and is_instance_valid(ws.attack):
		attack = ws.attack
	var drawn: WeaponData = ws.equipped_weapon if ws != null else null
	var crouch_ok := is_instance_valid(p.crouch)
	var mv: PlayerMovementSettings = GameSettings.player_movement
	if crouch_ok:
		var fwd := GroundMovement.compute_target_speed(p, Vector2(0.0, -1.0))
		var back := GroundMovement.compute_target_speed(p, Vector2(0.0, 1.0))
		var strafe := GroundMovement.compute_target_speed(p, Vector2(1.0, 0.0))
		out.append("  speed: forward %s  backward %s  strafe %s m/s (compute_target_speed, this frame)" % [_num(fwd), _num(back), _num(strafe)])
		# The walk tier applies whenever Run is not held — and it is never held under a debug UI — or sprint is locked
		# out, or ADS pins you to walking (ground_movement.gd:25). Say which, so the number is not misread as the run speed.
		var run_held := Input.is_action_pressed(InputManager.action_run)
		var walk_tier := p.crouch.crouch_t < 0.5 and (not run_held or not p.can_sprint() or p.sprint_blocked_by_scope())
		if walk_tier:
			var why := "Run not held (never is under a debug UI)"
			if not p.can_sprint():
				why = "can_sprint false"
			elif p.sprint_blocked_by_scope():
				why = "ADS pins the walk tier"
			out.append("    tier: WALK x%s (%s) — run tier would be %s forward" % [_num(mv.walk_speed_mult), why, _num(fwd / maxf(mv.walk_speed_mult, 0.0001))])
		else:
			out.append("    tier: %s" % ("crouched (crouch blend replaces the walk tier)" if p.crouch.crouch_t >= 0.5 else "RUN"))
	else:
		out.append("  speed: n/a — compute_target_speed reads player.crouch.crouch_t and this player's Crouch child is missing/freed")
	var crouch_t := p.crouch.crouch_t if crouch_ok else 0.0
	out.append("    base max_speed %s   backward x%s   strafe x%s   walk x%s   crouch x%s (crouch_t %s)   scope x%s (scoped %s)" % [
		_num(mv.max_speed), _num(mv.backward_mult), _num(mv.strafe_mult), _num(mv.walk_speed_mult),
		_num(GameSettings.player_crouch.speed_mult), _num(crouch_t), _num(GameSettings.weapon_general.scope_speed_mult), _onoff(bool(p.get(&"_is_scoped")))])
	var weapon_factor := "x1 (no weapon)"
	if drawn != null:
		var applies := attack != null and not attack.holstered
		weapon_factor = "x%s (%s, %s)" % [_num(drawn.move_speed_multiplier), _weapon_name(drawn), ("drawn — applied" if applies else "holstered — not applied")]
	out.append("    x limb %s   x load %s (carry %s / %s, heaviness %s)   x agility %s   x status %s   x weapon %s" % [
		_num(p.limb_move_multiplier()), _num(p.encumbrance_move_multiplier()), _num(p.current_carry_weight()), _num(p.carry_capacity), _num(p.heaviness()),
		_num(p.stats_or_default().move_speed_mult(p.status_stat_modifier(&"agility"))), _num(p.status_move_multiplier()), weapon_factor])

	# --- limbs ------------------------------------------------------------------------------------------
	out.append("  limbs: head %s   arms %s   legs %s   (has_limb_damage %s; pools seed at %s = max_hp x limb_condition_frac %s)" % [
		_limb_state(p, Character.BodyPart.HEAD), _limb_state(p, Character.BodyPart.ARMS), _limb_state(p, Character.BodyPart.LEGS),
		_onoff(p.has_limb_damage()), _num(_limb_pool_full(p)), _num(p.limb_condition_frac)])

	# --- hands ------------------------------------------------------------------------------------------
	# ⭐A freed Object reads `== null` AND falsy in Godot 4 (verified headless, [[held-prop-freed-permanent-stuck]]),
	# so `held_prop()` CANNOT tell "empty-handed" from "the prop freed in my hands" — the only witness to the
	# stuck-carry class is the Player's own `_carrying` latch (set/cleared with draw_locked in _on_carry_changed,
	# player.gd:398/418/422) still reading true over no valid prop. That mismatch is what is flagged below.
	var carrying := bool(p.get(&"_carrying"))
	var held = p.held_prop()  # UNTYPED on purpose: a typed assign of a freed instance is a VM error in debug builds
	var held_ok := is_instance_valid(held)
	var held_word := String(held.name) if held_ok else "none"
	var bag_held := p.held_inventory_item()
	var hands := "  hands: "
	if attack != null:
		hands += "holstered %s   draw_locked %s" % [_onoff(attack.holstered), _onoff(attack.draw_locked)]
	else:
		hands += "holstered n/a   draw_locked n/a (no Attack)"
	hands += "   carrying %s   held prop %s   held bag item %s" % [_onoff(carrying), held_word, ("none" if bag_held == null else bag_held.label())]
	out.append(hands)
	if carrying and not held_ok:
		out.append("    ! carrying ON with no live prop — the freed-in-hand stuck-carry class; PickupRay's _holding recovery clears it on its next physics frame (ray_cast.gd:239), else a drop/`revive`")
	if attack != null and attack.draw_locked and not carrying:
		out.append("    ! draw_locked with carrying OFF — _on_carry_changed sets both together, so nothing will clear it; the gun cannot be drawn until a drop/revive resets it")

	# --- the hub vs the backpack ------------------------------------------------------------------------
	var inv := p.inventory
	var bag_item: Item = inv.equipped_item if inv != null else null
	if ws == null:
		out.append("  hub: n/a (weapon_system is null or freed — a bare test Player, or the hub was torn down)")
	else:
		var hub := "  hub: equipped_weapon %s" % _weapon_name(drawn)
		if drawn != null:
			var reserve := inv.ammo_count(drawn.caliber) if inv != null else 0
			hub += "   clip %d / %d   reserve %d clips (%s)" % [ws.current_ammo, drawn.max_ammo, reserve, ("no caliber" if drawn.caliber == &"" else String(drawn.caliber))]
			if drawn.is_infinite_ammo:
				hub += "   is_infinite_ammo (never decrements)"
		if is_instance_valid(ws.ammo):
			hub += "   ammo_cost %d%s" % [ws.ammo.ammo_cost, (" (INFINITE — `ammo off` restores)" if ws.ammo.ammo_cost <= 0 else "")]
		if ws.is_busy():
			hub += "   (reload/swap in flight)"
		out.append(hub)
	if inv == null:
		out.append("  bag: n/a (no CharacterInventory — built in Character._ready)")
	else:
		var bag := "  bag: equipped_item %s" % ("none" if bag_item == null else bag_item.label())
		# ⭐THE TWO-INVENTORIES TRAP: the hub holds a nameless WeaponData, the backpack marks the Item; the UI's
		# equipped marker and the death card read the BAG. They must agree, or one of them was equipped alone.
		var hub_is_fists := drawn == null or drawn == Player.FISTS
		var agree := (bag_item == null and hub_is_fists) or (bag_item != null and bag_item.weapon == drawn)
		if ws == null:
			bag += "   (hub unavailable — cannot compare)"
		elif agree:
			bag += "   — agrees with the hub"
		else:
			bag += "   ! DISAGREES with the hub (%s) — one side was equipped alone; `weapon <id>` fixes both" % _weapon_name(drawn)
		out.append(bag)

	# --- sprint / abilities / perks / effects / debug state ---------------------------------------------
	out.append("  sprint: can_sprint %s   locked out %s   blocked by scope %s" % [_onoff(p.can_sprint()), _onoff(p.is_sprint_locked_out()), _onoff(p.sprint_blocked_by_scope())])
	var active := PackedStringArray()
	for id in p.installed_list():
		if p.has_mechanic(StringName(String(id))):
			active.append(String(id))
	out.append("  abilities: active [%s]   off [%s]   (%d installed — `ability` lists every id on disk)" % [", ".join(active), ", ".join(_as_strings(p.disabled_list())), p.installed_list().size()])
	var pm := _find_perk_manager(p)
	if pm == null:
		out.append("  perks: none (no PerkManager yet)")
	else:
		out.append("  perks: [%s]   skill points %d (earned %d)" % [", ".join(_as_strings(pm.unlocked_ids())), pm.skill_points, pm.points_earned])
	var mgr := p.status_manager()
	var live_fx := PackedStringArray()
	if mgr != null:
		for id in _effect_ids():
			if mgr.has_effect(StringName(id)):
				live_fx.append(id)
	out.append("  effects: %d active%s" % [(0 if mgr == null else mgr.active_count()), ("" if live_fx.is_empty() else " [%s]" % ", ".join(live_fx))])
	var noclip_word := "off"
	var tree: SceneTree = ctx.get(&"tree", null)
	var noclip_node: Node = _find_noclip(tree.current_scene) if tree != null and tree.current_scene != null else null
	if noclip_node != null and noclip_node.has_method(&"is_enabled") and bool(noclip_node.call(&"is_enabled")):
		noclip_word = "ON"
	out.append("  debug: god %s (armor_flat %s, damage_reduction %s)   noclip %s   suspended by a debug UI %s" % [
		_onoff(p.armor_flat >= GOD_ARMOR_FLAT), _num(p.armor_flat), _num(p.damage_reduction), noclip_word, _onoff(p.has_meta(SUSPEND_META))])
	return out


## `ability [id|all] [on|off|revoke]` — grant, switch, revoke or list the unlockable mechanics.
##
## No argument (or the word `list`) prints every id AbilityRegistry can see with its INSTALLED vs ACTIVE state —
## the two predicates whose confusion is the whole risk surface here ([[implant-installed-vs-active-toggle]]):
## `has_mechanic` = installed AND enabled (every gameplay gate), `mechanic_installed` = node present on or off
## (economy / UI ownership), `disabled_list` = the off ones (a SEPARATE save key, GameState.disabled_unlocks).
##
## GRANT runs the SHIPPED chip path verbatim: `can_grant_mechanic` guard first (chip_installer.gd:176 — a typo'd
## id would build nothing), then `unlock_mechanic` (player.gd:1251 -> AbilityManager.unlock :115, which builds
## the node from the SCRIPT by the naming convention, parents it under the Player and registers the typed
## hot-path ref), then `GameState.autosave(p)` (chip_installer.gd:214-215) — because a grant persists only on the
## next capture and would otherwise evaporate on a reload before the next money/inventory event. ⭐The registry
## build uses the script's DEFAULT exports, not the ability .tscn's authored tuning — identical to a paid install,
## and reported. `all` grants every id can_build() accepts.
## `on`/`off` -> set_mechanic_active (:1183; off runs on_deactivated: a live grapple severs, a live slide ends).
## `revoke` -> revoke_ability (:1271; nulls the hot-path refs, then queue_frees). A PERK-granted ability revoked
## here leaves has_perk true — the PerkManager ledger is not consulted — so a later respec re-revokes a no-op.
static func _ability(p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var target := _word(args, 0).strip_edges()
	if target == "" or target.to_lower() == "list":
		return _ability_list(p)
	var verb := _word(args, 1).strip_edges().to_lower()
	# Only a GRANT needs the tree (unlock_mechanic add_childs the freshly built node under the Player and its
	# _ready wires it); on/off/revoke only flip `enabled` / queue_free existing nodes and work anywhere.
	if verb == "" and not p.is_inside_tree():
		return PackedStringArray(["ability: player is off-tree — unlock_mechanic has to add_child the ability node (on/off/revoke still work)"])
	var ids := PackedStringArray()
	var every := target.to_lower() == "all"
	if every:
		if verb == "":
			for id in AbilityReg.ids():
				if AbilityReg.can_build(StringName(id)):
					ids.append(id)
			if ids.is_empty():
				return PackedStringArray(["ability: the registry scan found nothing buildable under %s (DirAccess is editor/test-grade — grant ids one at a time in an export)" % AbilityReg.ABILITY_DIR])
		else:
			ids = _as_strings(p.installed_list())  # on/off/revoke `all` act on what is INSTALLED, not on disk
			if ids.is_empty():
				return PackedStringArray(["ability: nothing installed to %s" % verb])
	else:
		ids.append(target)
	var out := PackedStringArray()
	var changed := 0
	for raw in ids:
		var id := StringName(raw)
		match verb:
			"":
				changed += _ability_grant(p, id, out)
			"on", "off":
				changed += _ability_switch(p, id, verb == "on", out)
			"revoke":
				changed += _ability_revoke(p, id, out)
			_:
				out.append("ability: unknown verb \"%s\" — on, off or revoke" % verb)
				return out
	if changed == 0:
		out.append("ability: no change — nothing to save")
		return out
	# Persist exactly like the shipped chip path (chip_installer.gd:214-215) and the Implants-tab toggle
	# (implants_screen.gd:388): the live node set is only projected into [player].unlocks / disabled_unlocks by
	# the next capture, and this IS that capture. Reported honestly, including whether it could land.
	GameState.autosave(p)
	out.append("ability: %d change(s) — %s" % [changed, ("saved (GameState.autosave: %s)" % _save_where() if _save_landed(p) else "NOT saved — off-tree or a scene reload is in flight (GameState.reload_pending); the change is in memory only")])
	return out


## The `ability` listing: every id on disk (AbilityRegistry.ids(), a DirAccess scan) UNIONED with what is
## installed — an editor-placed ability with an unconventional id has no scene file to scan but is still real.
static func _ability_list(p: Player) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	var ids := PackedStringArray()
	for id in AbilityReg.ids():
		seen[id] = true
		ids.append(id)
	for raw in p.installed_list():
		var id := String(raw)
		if not seen.has(id):
			seen[id] = true
			ids.append(id)
	ids.sort()
	if ids.is_empty():
		out.append("ability: no ability scenes under %s and nothing installed (the DirAccess scan is editor/test-grade — in an export, name the id directly)" % AbilityReg.ABILITY_DIR)
		return out
	for id in ids:
		var sid := StringName(id)
		var installed := p.mechanic_installed(sid)
		var active := installed and p.has_mechanic(sid)
		var mark := "*" if active else ("o" if installed else " ")
		var note := ""
		if not AbilityReg.can_build(sid):
			note = "  (no script at %s — cannot be granted at runtime)" % AbilityReg.script_path_for(sid)
		elif installed and not active:
			note = "  (installed, switched OFF — rides GameState.disabled_unlocks)"
		out.append("  [%s] %-18s %s%s" % [mark, id, AbilityReg.display_name_for(sid), note])
	out.append("ability: %d installed, %d active, %d off   ([*] active  [o] installed but off  [ ] not installed)" % [p.installed_list().size(), p.unlocked_list().size(), p.disabled_list().size()])
	out.append("  `ability <id>` grants, `ability all` grants every buildable id, `<id> on|off` toggles, `<id> revoke` removes")
	return out


## One grant. Returns 1 when the live set changed (so the caller knows to autosave), 0 otherwise.
static func _ability_grant(p: Player, id: StringName, out: PackedStringArray) -> int:
	if p.has_mechanic(id):
		out.append("ability: %s already installed and active" % id)
		return 0
	if p.mechanic_installed(id):
		# unlock() re-enables a disabled node instead of building a second one (ability_manager.gd:118-122).
		p.unlock_mechanic(id)
		out.append("ability: %s was installed but OFF — switched back on (unlock re-enables a disabled node)" % id)
		return 1
	if not p.can_grant_mechanic(id):
		out.append("ability: no ability script for \"%s\" (expected %s) — `ability` lists the ids" % [id, AbilityReg.script_path_for(id)])
		return 0
	p.unlock_mechanic(id)
	if not p.mechanic_installed(id):
		out.append("ability: %s — unlock_mechanic built nothing (the script did not load as an Ability?)" % id)
		return 0
	out.append("ability: granted %s (%s)%s" % [id, AbilityReg.display_name_for(id), ("" if p.has_mechanic(id) else " — installed but reads INACTIVE (its `enabled` export defaults off?)")])
	out.append("  built from the SCRIPT's default exports — the shipped chip path; the ability .tscn's authored tuning is NOT applied")
	return 1


## `on` / `off` for one installed id. Returns 1 when the ACTIVE predicate actually flipped.
static func _ability_switch(p: Player, id: StringName, on: bool, out: PackedStringArray) -> int:
	if not p.mechanic_installed(id):
		out.append("ability: %s is not installed — `ability %s` grants it first" % [id, id])
		return 0
	var before := p.has_mechanic(id)
	if before == on:
		out.append("ability: %s already %s" % [id, _onoff(on)])
		return 0
	if not p.set_mechanic_active(id, on):
		out.append("ability: %s — set_mechanic_active refused (no node grants it)" % id)
		return 0
	out.append("ability: %s %s (mechanic_toggled emitted)" % [id, _onoff(on)])
	if not on:
		out.append("  on_deactivated ran — a live grapple is severed, a live slide ended; the implant stays INSTALLED (disabled_unlocks)")
	return 1


## `revoke` for one id. Returns 1 when a node was actually removed.
static func _ability_revoke(p: Player, id: StringName, out: PackedStringArray) -> int:
	if not p.mechanic_installed(id):
		out.append("ability: %s is not installed — nothing to revoke" % id)
		return 0
	p.revoke_ability(id)
	if p.mechanic_installed(id):
		out.append("ability: %s still installed after revoke_ability — a node re-registered itself?" % id)
		return 0
	out.append("ability: revoked %s (hot-path ref nulled, node queue_freed)" % id)
	out.append("  if a PERK granted it, has_perk stays true — the PerkManager ledger is not consulted here")
	return 1


## `kill` — must go through take_damage so the FULL death sequence runs (bounty, wallet bequeath, killer credit,
## the cinematic, the checkpoint respawn). Writing hp = 0 by hand does NOT kill: the death branch only exists
## inside take_damage (character.gd:415). The amount is sized past the player's own mitigation so god mode or a
## worn set of armour cannot silently soak a deliberate suicide.
static func _kill(p: Player) -> PackedStringArray:
	if p == null:
		return _no_player()
	if not p.is_alive():
		return PackedStringArray(["kill: already dead"])
	# Invert the WHOLE mitigation chain in character.gd's take_damage, in the order it applies it:
	#   1. ⭐difficulty FIRST — `_amount *= GameSettings.difficulty.damage_taken_mult` (character.gd:371-372),
	#      player-only and applied BEFORE armour. The Easy preset ships 0.5 (DifficultySettings.gd:27), so a kill
	#      amount computed without it is HALVED before it meets armour: under god mode (armor_flat 1e9) the whole
	#      hit mitigates to zero and `kill` silently refuses on any difficulty below Normal. Dividing it back out
	#      is what makes this command difficulty-invariant, which is the entire point of sizing the hit at all.
	#   2. then `(amount - armor_flat) * (1 - damage_reduction)` (character.gd:376) — reduction clamped off 1.0
	#      so a fully-immune player cannot divide by zero, and the multiplier floored so a designer's 0 (or a
	#      negative) cannot either.
	var dr := clampf(p.damage_reduction, 0.0, 0.99)
	var taken_mult := maxf(0.01, GameSettings.difficulty.damage_taken_mult)
	var amount := ((p.hp + KILL_OVERKILL) / (1.0 - dr) + maxf(0.0, p.armor_flat)) / taken_mult
	p.take_damage(amount)
	if p.is_alive():
		return PackedStringArray(["kill: refused — " + _damage_blocked_reason(p)])
	return PackedStringArray(["kill: death sequence running (bounty, wallet bequeath and the respawn all resolve)"])


## `revive` — refill and clear the death latches WITHOUT a checkpoint teleport.
##
## ⭐REFUSES while `_dying`. The death cinematic is a running tween that ends in `_respawn_at_checkpoint()`; a
## revive mid-cinematic would be silently undone (and re-teleported) a second later.
## `Character.reset_for_reuse()` is NOT an alternative — that is the NPC-pool reset and it leaves `_dying` set.
static func _revive(ctx: Dictionary, p: Player) -> PackedStringArray:
	if p == null:
		return _no_player()
	if bool(p.get(&"_dying")):
		return PackedStringArray(["revive: refused — the death cinematic is running; it ends in the real respawn. Wait for it."])
	if p.is_alive():
		return PackedStringArray(["revive: already alive (hp %s / %s)" % [_num(p.hp), _num(p.max_hp)]])
	p.set(&"_dead", false)
	p.hp = p.max_hp
	p.heal_limbs()
	p.damaged.emit(p.hp, p.max_hp)  # hp is a bare var — without this the HP bar, vignette and health light stay stale
	p.velocity = Vector3.ZERO
	# ⭐Leftover blast impulse: apply_velocity re-adds explosion_velocity on the next physics frame
	# (character.gd:977), which is the documented fling bug both die() and _respawn_at_checkpoint zero it for.
	p.explosion_velocity = Vector3.ZERO
	p.set(&"_continuous_fall_time", 0.0)
	var out := PackedStringArray(["revive: hp %s / %s, death latch cleared" % [_num(p.hp), _num(p.max_hp)]])
	# Hand physics back — but NOT while a debug UI is holding the player suspended. Re-enabling under an open
	# console would give the body movement and FIRE back beneath a free cursor (mouse_input._process polls
	# `Attack`, mouse_input.gd:39-45), so the next click on a console button shoots. The UI's own close() is what
	# hands control back, and restore_player's revived-under-us branch makes sure that restore does not re-freeze
	# the now-living player. The ctx-state snapshot is ALSO patched when a host publishes one there — belt and
	# braces for a front-end that does honour SUSPEND_STATE_KEY.
	var held := p.has_meta(SUSPEND_META)
	var snap = _state(ctx).get(SUSPEND_STATE_KEY)
	if snap is Dictionary and bool((snap as Dictionary).get(&"valid", false)):
		var live: Dictionary = snap
		live[&"physics"] = true
		live[&"mouse"] = true
		live[&"mouse_unhandled"] = true
		live[&"crouch"] = true
		live[&"alive"] = true
	if held:
		out.append("  control returns when this debug UI closes")
	else:
		p.set_physics_process(true)
		if is_instance_valid(p.mouse_input):
			p.mouse_input.set_process(true)
			p.mouse_input.set_process_unhandled_input(true)
		if is_instance_valid(p.crouch):
			p.crouch.set_physics_process(true)
	if is_instance_valid(p.ui) and p.ui.has_method(&"restore_hud_after_death"):
		p.ui.restore_hud_after_death()  # die() hid the HUD elements; only the in-place revive normally puts them back
		out.append("  HUD restored")
	out.append("  the gun stays holstered and you are NOT moved to the checkpoint — that is the real respawn's job")
	return out


## `noclip [on|off]` — delegated to the DebugNoclip drop-in, which owns the per-frame fly drive.
##
## The node is found-or-created under `tree.current_scene` — the ONE canonical parent — never under
## `ctx[&"host"]`: the host differs per surface (console vs menu), so a host mount grows a SECOND node when the
## other surface toggles, and `noclip off` then reads the fresh node's false while the first one keeps flying.
## current_scene also survives ⭐GameRoot.load_level, which FREES the whole old level subtree
## (game_root.gd:123-126) — the same reasoning as DebugActionsWorld._inspector.
static func _noclip(ctx: Dictionary, p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var tree: SceneTree = ctx.get(&"tree", null)
	if tree == null or tree.current_scene == null:
		return PackedStringArray(["noclip: no scene to mount the DebugNoclip drop-in in"])
	var node := _find_or_make_noclip(tree.current_scene)
	if node == null:
		return PackedStringArray(["noclip: the DebugNoclip drop-in is missing (%s)" % NOCLIP_SCRIPT_PATH])
	if not (node.has_method(&"set_enabled") and node.has_method(&"is_enabled")):
		return PackedStringArray(["noclip: DebugNoclip is missing set_enabled/is_enabled"])
	var current := bool(node.call(&"is_enabled"))
	var want := Commands.toggle_value(_word(args, 0), current)
	var landed := bool(node.call(&"set_enabled", want))  # returns the RESULTING state, which may refuse
	var out := PackedStringArray(["noclip: %s" % _onoff(landed)])
	if landed != want:
		out.append("  DebugNoclip refused the change")
	# The fall-death timer knob (GameSettings.player_movement.max_continuous_fall_time) is deliberately NOT
	# touched here: `god` snapshots and restores that shared .tres field as one pair, and a second snapshot of
	# the same field would corrupt whichever restore ran last. DebugNoclip itself only zeroes the player's
	# banked _continuous_fall_time accumulator on landing — it never writes the knob. The tip below is the
	# hedge for a session that flies without god mode.
	# Read the PLAYER's armour, not the ctx-state flag: after a scene reload the flag can still say "on" over a
	# fresh, unprotected body (see the note in `_god`), and the tip would then be withheld exactly when it matters.
	if landed and p.armor_flat < GOD_ARMOR_FLAT:
		out.append("  tip: `god on` also zeroes the continuous-fall death timer, which armour cannot stop")
	return out


## `speed [multiplier]` — scales `GameSettings.player_movement.max_speed`, the base every per-frame multiplier in
## GroundMovement.compute_target_speed hangs off. No argument restores the authored value.
##
## ⭐Shared preloaded .tres again: the AUTHORED base is captured on the first change and every later multiplier is
## applied to that base, never compounded onto the already-scaled value (which is how a speed cheat ends up
## permanently baking 8x into the project's tuning).
static func _speed(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var st := _state(ctx)
	var settings: PlayerMovementSettings = GameSettings.player_movement
	if args.size() == 0:
		if not st.has(&"player/speed_base"):
			return PackedStringArray(["speed: already at the authored %s" % _num(settings.max_speed)])
		settings.max_speed = float(st[&"player/speed_base"])
		st.erase(&"player/speed_base")
		st.erase(&"player/speed_mult")
		return PackedStringArray(["speed: restored authored max_speed %s" % _num(settings.max_speed)])
	var mult := args[0].to_float()
	if mult <= 0.0:
		return PackedStringArray(["speed: multiplier must be > 0"])
	if not st.has(&"player/speed_base"):
		st[&"player/speed_base"] = settings.max_speed
	var base := float(st[&"player/speed_base"])
	settings.max_speed = base * mult
	st[&"player/speed_mult"] = mult
	return PackedStringArray(["speed: x%s (max_speed %s -> %s; authored base kept for `speed` with no argument)" % [_num(mult), _num(base), _num(settings.max_speed)]])


## `stamina [amount]` — set or refill. Goes through the CLAMPED private writer `_set_stamina` (player.gd:1513 ->
## stamina_manager.gd:168), not the raw `stamina` property alias, which has no clamp and no signal. `stamina_max()`
## is recomputed live from endurance plus status modifiers on every call, so it is never cached here.
static func _stamina(p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var maximum := p.stamina_max()
	var before := p.stamina
	var target := maximum
	if args.size() > 0:
		target = args[0].to_float()
	p._set_stamina(target)
	return PackedStringArray(["stamina: %s -> %s / %s" % [_num(before), _num(p.stamina), _num(maximum)]])


## `tp <x> <y> <z>` — teleport to world coordinates.
static func _tp(ctx: Dictionary, p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var target := Vector3(args[0].to_float(), args[1].to_float(), args[2].to_float())
	var from := p.global_position
	_place(ctx, p, target)
	return PackedStringArray(["tp: %s -> %s (%s)" % [_vec(from), _vec(p.global_position), _back_note(ctx)]])


## `tpaim` — teleport to whatever the crosshair points at.
##
## Uses `get_aim_basis()` (player.gd:1418), NOT `get_aim_direction()`: the latter runs the shot direction through
## AimSway, so it drifts around the camera centre and a teleport would land beside where you were looking.
##
## ⭐PHYSICS-FRAME CAVEAT. `run()` is called from the console/menu's INPUT callback, i.e. an idle frame, and
## [[spacestate-query-needs-physics-frame]] records that a `direct_space_state` query off the physics frame can
## return an EMPTY result with no error — indistinguishable from "the ray hit nothing". We cannot `await
## tree.physics_frame` here (run() must return a PackedStringArray, and awaiting would turn it into a coroutine
## that neither front-end can consume), so the query is made directly and an empty result is REPORTED rather than
## acted on. Nothing is moved on a miss, and the message names the trap so a repeat attempt is an obvious next step.
static func _tpaim(ctx: Dictionary, p: Player) -> PackedStringArray:
	if p == null:
		return _no_player()
	if not p.is_inside_tree():
		return PackedStringArray(["tpaim: player is off-tree — no physics world to cast into"])
	var world := p.get_world_3d()
	if world == null or not world.space.is_valid():
		return PackedStringArray(["tpaim: no physics space"])
	var space := world.direct_space_state
	if space == null:
		return PackedStringArray(["tpaim: physics space is locked right now — try again"])
	var origin := p.get_aim_origin()
	var forward := -p.get_aim_basis().z  # Godot cameras look down local -Z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * TP_AIM_RANGE)
	query.exclude = [p.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return PackedStringArray([
			"tpaim: nothing within %sm under the crosshair" % _num(TP_AIM_RANGE, 0),
			"  (a space-state query made off the physics frame also reads as empty — see spacestate-query-needs-physics-frame)",
		])
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	# Land SHORT along the surface normal so we arrive beside the geometry, not inside it. The re-armed ground
	# snap then drops us onto a floor from there.
	var target := point + normal * TP_AIM_SURFACE_OFFSET
	var from := p.global_position
	_place(ctx, p, target)
	var what := "world"
	var collider = hit.get("collider")
	if is_instance_valid(collider) and collider is Node:
		what = String((collider as Node).name)
	return PackedStringArray(["tpaim: %s -> %s (hit %s, landed %sm off the surface)" % [_vec(from), _vec(target), what, _num(TP_AIM_SURFACE_OFFSET)]])


## `mark [name]` — remember here for `back`; with a name ALSO save a persistent bookmark for `goto <name>`.
##
## The bare form is untouched: the transient &"player/mark_pos"/&"player/mark_yaw" pair in ctx state that `back`
## prefers over the pre-teleport stash. The named form sets that SAME transient pair first (so `mark roof` then
## `back` behaves exactly like `mark` then `back`) and then writes {pos, yaw} to MARKS_PATH under this level's
## section. ⭐The level identity is GameState.current_level_path; a code-built LevelData has a blank one, and a
## mark filed under "" would be unreachable from every real level, so the persistent half REFUSES on a blank path
## — the transient half still lands and the line says which half did what.
static func _mark(ctx: Dictionary, p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var st := _state(ctx)
	var pos := p.global_position
	var yaw := p.rotation.y
	st[&"player/mark_pos"] = pos
	st[&"player/mark_yaw"] = yaw
	var key := mark_key(_word(args, 0))
	if key == "":
		# Bare `mark` — or a quoted all-whitespace name, which normalises to nothing and is treated as bare.
		return PackedStringArray(["mark: %s (yaw %s deg)" % [_vec(pos), _num(rad_to_deg(yaw), 1)]])
	var out := PackedStringArray(["mark %s: %s (yaw %s deg) — `back` returns here" % [key, _vec(pos), _num(rad_to_deg(yaw), 1)]])
	var level := String(GameState.current_level_path)
	if level == "":
		out.append("  NOT persisted: GameState.current_level_path is blank (no level loaded, or a code-built LevelData) — a bookmark needs a level to belong to; `warp <level>` onto a real .tres first")
		return out
	var cfg := ConfigFile.new()
	var err := _marks_load(cfg)
	if err != OK:
		out.append("  NOT persisted: %s" % _marks_load_failure(err))
		return out
	var replaced := marks_read(cfg, level).has(key)
	marks_write(cfg, level, key, pos, yaw)
	err = _marks_save(cfg)
	if err != OK:
		out.append("  NOT persisted: ConfigFile.save(%s) failed (%s)" % [MARKS_PATH, error_string(err)])
		return out
	out.append("  saved%s to %s (%s) under [%s] — `goto %s` teleports here in this level, `marks` lists" % [
		(" (replaced the old mark of that name)" if replaced else ""), MARKS_PATH, ProjectSettings.globalize_path(MARKS_PATH), level, key])
	return out


## `goto <name>` — teleport to a bookmark saved by `mark <name>` in THIS level.
##
## Moves the player EXACTLY like `tp`/`back`: `_place` stashes &"player/last_pos" (so `back` can return you),
## zeroes `velocity` and `explosion_velocity`, clears the fall timer and re-arms the ground snap; then the yaw is
## applied upright, yaw-only (the PlayerSpawn.place idiom, player_spawn.gd:25 — the same line `back` uses).
## ⭐A mark from ANOTHER level is named but never used: its coordinates only mean something inside its own level,
## so the line says which level owns it and to `warp` there first. Nothing is moved on any miss.
## The bookmark is NOT copied into the transient `mark` slot: `goto` is a hop, and clobbering a bare `mark` the
## developer set on purpose would be a surprise (see _back_note for what `back` does after a hop).
static func _goto(ctx: Dictionary, p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var key := mark_key(_word(args, 0))
	if key == "":
		return PackedStringArray(["goto: a name is required — `marks` lists this level's bookmarks"])
	var cfg := ConfigFile.new()
	var err := _marks_load(cfg)
	if err != OK:
		return PackedStringArray(["goto: " + _marks_load_failure(err)])
	var level := String(GameState.current_level_path)
	if level == "":
		return PackedStringArray(["goto: GameState.current_level_path is blank (no level loaded, or a code-built LevelData) — bookmarks are filed per level, so there is nothing to look under; `warp <level>` onto a real .tres first"])
	var here := marks_read(cfg, level)
	if here.has(key):
		var m: Dictionary = here[key]
		var target: Vector3 = m[&"pos"]
		var yaw := float(m[&"yaw"])
		var from := p.global_position
		_place(ctx, p, target)
		p.rotation = Vector3(0.0, yaw, 0.0)  # upright, yaw only — the PlayerSpawn.place idiom
		return PackedStringArray(["goto %s: %s -> %s (yaw %s deg; %s)" % [key, _vec(from), _vec(p.global_position), _num(rad_to_deg(yaw), 1), _back_note(ctx)]])
	var elsewhere := PackedStringArray()
	for other in marks_levels(cfg):
		if other != level and marks_read(cfg, other).has(key):
			elsewhere.append(other)
	if elsewhere.is_empty():
		var names := PackedStringArray(here.keys())
		names.sort()
		return PackedStringArray(["goto: no mark \"%s\" in this level%s — `mark %s` saves one here" % [key, ("" if names.is_empty() else " (it has: %s)" % ", ".join(names)), key]])
	var out := PackedStringArray(["goto: \"%s\" is not marked in this level — it belongs to %d other level(s), and a mark's coordinates only mean something in its own level:" % [key, elsewhere.size()]])
	for other in elsewhere:
		out.append("  %s   -> `warp %s` first, then `goto %s`" % [other, _level_stem(other), key])
	return out


## `marks [name]` — list this level's bookmarks (and how many other levels have some), or delete one by name.
## Deleting the last mark of a level drops its section too, so the "N more level(s)" count never counts a ghost.
static func _marks(args: PackedStringArray) -> PackedStringArray:
	var cfg := ConfigFile.new()
	var err := _marks_load(cfg)
	if err != OK:
		return PackedStringArray(["marks: " + _marks_load_failure(err)])
	var level := String(GameState.current_level_path)
	var key := mark_key(_word(args, 0))
	if key != "":
		# --- delete ---
		if level == "":
			return PackedStringArray(["marks: GameState.current_level_path is blank — bookmarks are filed per level, so there is no section to delete \"%s\" from; `warp <level>` first" % key])
		if not marks_erase(cfg, level, key):
			var miss := PackedStringArray(["marks: no mark \"%s\" in this level (%s) — nothing deleted" % [key, level]])
			for other in marks_levels(cfg):
				if other != level and marks_read(cfg, other).has(key):
					miss.append("  (%s has one of that name — `warp %s` first to delete it there)" % [other, _level_stem(other)])
			return miss
		err = _marks_save(cfg)
		if err != OK:
			return PackedStringArray(["marks: erased \"%s\" in memory but ConfigFile.save(%s) failed (%s) — the file still has it" % [key, MARKS_PATH, error_string(err)]])
		return PackedStringArray(["marks: deleted \"%s\" from [%s] — %s (%s)" % [key, level, MARKS_PATH, ProjectSettings.globalize_path(MARKS_PATH)]])
	# --- list ---
	var out := PackedStringArray()
	var levels := marks_levels(cfg)
	var others := PackedStringArray()
	for other in levels:
		if other != level:
			others.append(other)
	if level == "":
		out.append("marks: GameState.current_level_path is blank (no level loaded, or a code-built LevelData) — nothing is filed under a blank level")
	else:
		var here := marks_read(cfg, level)
		if here.is_empty():
			out.append("marks: none in this level (%s) — `mark <name>` saves one" % level)
		else:
			out.append("marks: %d in this level (%s)" % [here.size(), level])
			var names := PackedStringArray(here.keys())
			names.sort()
			for n in names:
				var m: Dictionary = here[n]
				var mpos: Vector3 = m[&"pos"]
				out.append("  %-18s %s  yaw %s deg" % [n, _vec(mpos), _num(rad_to_deg(float(m[&"yaw"])), 1)])
			out.append("  `goto <name>` teleports, `marks <name>` deletes")
	if others.is_empty():
		out.append("  no other level has marks")
	else:
		out.append("  %d more level(s) have marks (`warp <level>` then `marks` to see them):" % others.size())
		for other in others:
			out.append("    %s (%d) — warp %s" % [other, marks_read(cfg, other).size(), _level_stem(other)])
	out.append("  file: %s (%s)" % [MARKS_PATH, ProjectSettings.globalize_path(MARKS_PATH)])
	return out


# --- named marks: the pure file logic ---------------------------------------------------------------------
# Every function here takes the ConfigFile and the level section EXPLICITLY, so tests/test_debug_marks.gd can
# drive them on a scratch ConfigFile saved under user://test_debug_marks.cfg — no player, no GameState, and never
# the real MARKS_PATH. Only `_marks_load`/`_marks_save` know the real path.

## Normalise a typed name into its stored key: trimmed, lowercased, inner spaces -> `_` (a quoted `mark "my
## spot"` and a later `goto my_spot` meet in the middle). Empty for a blank/all-whitespace name.
static func mark_key(name: String) -> String:
	return name.strip_edges().to_lower().replace(" ", "_")


## Every mark filed under `level`: { key -> {&"pos": Vector3, &"yaw": float} }. Tolerant of hand edits — a value
## that is not a Dictionary carrying all of MARKS_VALUE_KEYS is skipped, never an error (the file is meant to be
## edited by hand). A level with no section reads as an empty Dictionary.
static func marks_read(cfg: ConfigFile, level: String) -> Dictionary:
	var out := {}
	if cfg == null or level == "" or not cfg.has_section(level):
		return out
	for key in cfg.get_section_keys(level):
		var raw = cfg.get_value(level, key)  # untyped: a Variant read — see [[gdscript-host-variant-no-inference]]
		if not (raw is Dictionary):
			continue
		var d: Dictionary = raw
		var complete := true
		for k in MARKS_VALUE_KEYS:
			if not d.has(k):
				complete = false
				break
		if not complete:
			continue
		out[String(key)] = {
			&"pos": Vector3(float(d["x"]), float(d["y"]), float(d["z"])),
			&"yaw": float(d["yaw"]),
		}
	return out


## File one mark under `level` as {x, y, z, yaw} floats (MARKS_VALUE_KEYS), keyed by mark_key(name). Overwrites a
## mark of the same key. Does NOT save — the caller decides where the ConfigFile goes.
static func marks_write(cfg: ConfigFile, level: String, name: String, pos: Vector3, yaw: float) -> void:
	var key := mark_key(name)
	if cfg == null or level == "" or key == "":
		return
	cfg.set_value(level, key, {"x": pos.x, "y": pos.y, "z": pos.z, "yaw": yaw})


## Remove one mark; true when it existed. Drops the section when that was its last key, so marks_levels() never
## lists a level with nothing in it. Does NOT save.
static func marks_erase(cfg: ConfigFile, level: String, name: String) -> bool:
	var key := mark_key(name)
	if cfg == null or level == "" or key == "" or not cfg.has_section_key(level, key):
		return false
	cfg.erase_section_key(level, key)
	# ⭐ConfigFile drops a section ITSELF when its last key goes, and get_section_keys/erase_section on a section
	# that is no longer there are ENGINE ERRORS (config_file.cpp ERR_FAIL_COND), not empty results — GUT fails the
	# test through its error tracker. So ask has_section first; the explicit erase only runs for an engine build
	# that keeps an empty section around.
	if cfg.has_section(level) and cfg.get_section_keys(level).is_empty():
		cfg.erase_section(level)
	return true


## Every level (section) that has at least one mark, sorted for a stable listing.
static func marks_levels(cfg: ConfigFile) -> PackedStringArray:
	var out := PackedStringArray()
	if cfg == null:
		return out
	for section in cfg.get_sections():
		if not cfg.get_section_keys(section).is_empty():
			out.append(String(section))
	out.sort()
	return out


## Read MARKS_PATH into `cfg`. OK when the file was read OR does not exist yet (the first `mark <name>` has no file
## — that is not a fault, the ConfigFile is simply empty). ⭐Any other code means the file EXISTS but could not be
## parsed, and the caller must NOT save over it: ConfigFile.load stops at the bad line, so a save would silently
## truncate every mark after it. `_marks_load_failure` words that for the console.
static func _marks_load(cfg: ConfigFile) -> Error:
	if not FileAccess.file_exists(MARKS_PATH):
		return OK
	return cfg.load(MARKS_PATH)


static func _marks_save(cfg: ConfigFile) -> Error:
	return cfg.save(MARKS_PATH)


static func _marks_load_failure(err: Error) -> String:
	return "%s exists but would not load (%s — a hand edit broke it?); refusing to write over it. Fix or delete the file: %s" % [MARKS_PATH, error_string(err), ProjectSettings.globalize_path(MARKS_PATH)]


## The word `warp <level>` takes for a level identity: the LevelData file stem — the world module's `_levels()`
## index keys by `f.get_basename()` (debug_actions_world.gd _scan, key_field blank), case-insensitively looked up.
static func _level_stem(level_path: String) -> String:
	return level_path.get_file().get_basename()


## `back` — return to the `mark`, or (with no mark) to wherever you were before the last teleport. Each `back`
## also re-stashes the position you left, so repeated calls ping-pong instead of stranding you.
static func _back(ctx: Dictionary, p: Player) -> PackedStringArray:
	if p == null:
		return _no_player()
	var st := _state(ctx)
	var target := Vector3.ZERO
	var source := ""
	if st.has(&"player/mark_pos"):
		target = st[&"player/mark_pos"]
		source = "mark"
	elif st.has(&"player/last_pos"):
		target = st[&"player/last_pos"]
		source = "pre-teleport position"
	else:
		return PackedStringArray(["back: nothing to go back to — run `mark`, or teleport once first"])
	var from := p.global_position
	_place(ctx, p, target)
	if st.has(&"player/mark_yaw") and source == "mark":
		p.rotation = Vector3(0.0, float(st[&"player/mark_yaw"]), 0.0)  # upright, yaw only — the PlayerSpawn.place idiom
	return PackedStringArray(["back: %s -> %s (%s)" % [_vec(from), _vec(p.global_position), source]])


## `pos` — where am I, and in which level. The level path matters more than it looks: a code-built LevelData has a
## blank resource_path, and every world_objects save key computed by WorldSaveId.key_for then carries a blank
## level component.
static func _pos(p: Player) -> PackedStringArray:
	if p == null:
		return _no_player()
	var level := GameState.current_level_path
	var out := PackedStringArray()
	out.append("pos: %s" % _vec(p.global_position))
	out.append("  yaw %s deg, velocity %s" % [_num(rad_to_deg(p.rotation.y), 1), _vec(p.velocity)])
	out.append("  level: %s" % ("(none recorded)" if level == "" else level))
	return out


## `stat <name> [value]` — read or SET one base stat.
##
## ⭐Kind.STAT is only a COMPLETION source: DebugCommands.validate() never rejects an unknown stat name, so the
## name is checked here against the CharacterStats master list.
## ⭐Never mutate a .tres-sourced sheet in place — both real callers duplicate first (level_up.gd:98-101,
## perk_manager.gd:118-120); editing a shared resource corrupts every other Character using it and, in the editor,
## can be saved to disk. Derived max_hp / carry / stamina then re-stamp through the ONE
## CharacterStats.restamp_derived chokepoint (character_stats.gd:145) so this behaves exactly like a level-up:
## same clamp, same heal-on-gain, same `damaged` signal.
static func _stat(p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var name := StringName(args[0].strip_edges().to_lower())
	if not (String(name) in CharacterStats.stat_names()):
		return PackedStringArray(["stat: no such stat \"%s\" — one of %s" % [args[0], ", ".join(CharacterStats.stat_names())]])
	var sheet := p.stats_or_default()
	if args.size() == 1:
		var live := p.status_stat_modifier(name)
		return PackedStringArray(["stat %s: %d base%s" % [name, sheet.get_stat(name), ("" if is_zero_approx(live) else " (%s live from status effects)" % _num(live))]])
	var value := int(round(args[1].to_float()))
	# Own a PRIVATE sheet before writing — the level_up.gd:98-101 idiom, verbatim.
	if not sheet.resource_path.is_empty():
		sheet = sheet.duplicate() as CharacterStats
		p.stats = sheet
	var before := sheet.get_stat(name)
	var old_hp_bonus := sheet.max_hp_bonus()
	var old_carry_bonus := sheet.carry_bonus()
	var old_stamina_max := p.stamina_max()  # captured BEFORE the sheet moves — stamina reads endurance
	var old_max_hp := p.max_hp
	var old_carry := p.carry_capacity
	sheet.set(name, value)
	CharacterStats.restamp_derived(p, sheet.max_hp_bonus() - old_hp_bonus, sheet.carry_bonus() - old_carry_bonus, old_stamina_max)
	GameState.autosave(p)
	var out := PackedStringArray(["stat %s: %d -> %d" % [name, before, value]])
	if not is_equal_approx(old_max_hp, p.max_hp):
		out.append("  max_hp %s -> %s (hp moved with it)" % [_num(old_max_hp), _num(p.max_hp)])
	if not is_equal_approx(old_carry, p.carry_capacity):
		out.append("  carry %s -> %s" % [_num(old_carry), _num(p.carry_capacity)])
	if not is_equal_approx(old_stamina_max, p.stamina_max()):
		out.append("  stamina max %s -> %s" % [_num(old_stamina_max), _num(p.stamina_max())])
	return out


## `stats` — the whole sheet plus everything derived from it.
static func _stats(p: Player) -> PackedStringArray:
	if p == null:
		return _no_player()
	var sheet := p.stats_or_default()
	var out := PackedStringArray()
	var total := 0
	var row := PackedStringArray()
	for n in CharacterStats.STAT_NAMES:
		total += sheet.get_stat(n)
		row.append("%s %d" % [n, sheet.get_stat(n)])
	out.append("stats: " + "  ".join(row))
	out.append("  total level %d (the sum — that is what LevelUp prices raises off)" % total)
	out.append("  hp %s / %s   stamina %s / %s" % [_num(p.hp), _num(p.max_hp), _num(p.stamina), _num(p.stamina_max())])
	out.append("  carry %s / %s" % [_num(p.current_carry_weight()), _num(p.carry_capacity)])
	var pm := _find_perk_manager(p)
	out.append("  xp %s   level %d   skill points %d" % [_num(p.xp), p.level, (0 if pm == null else pm.skill_points)])
	if not sheet.resource_path.is_empty():
		out.append("  sheet: %s (SHARED — `stat` duplicates it before writing)" % sheet.resource_path)
	return out


# --- Economy commands -------------------------------------------------------------------------------------

## `money <amount>` — the live wallet.
##
## ⭐`add_money` is the ONLY correct mutator (character.gd:39). Writing `player.money` emits no `money_changed`,
## so the MoneyPurse coin tile goes stale, the HUD readout and floating +N never fire and no autosave is queued.
## And `GameState.money` is NOT the wallet — it is a saved MIRROR that capture() overwrites from player.money.
static func _money(p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var delta := args[0].to_float()
	var before := p.money
	p.add_money(delta)
	var out := PackedStringArray(["money: %s -> %s (%s)" % [_money_text(before), _money_text(p.money), _money_text(p.money - before)]])
	if is_equal_approx(before, p.money):
		out.append("  nothing moved — add_money treats a zero (or sub-quantum) delta as a no-op")
	return out


## `bank <amount>` — the ONE SIGNED ledger account: positive is savings, negative is debt.
##
## ⭐Written directly, not through Atm.deposit/withdraw: those are clamped to the money that actually exists
## (atm.gd:94/:135) and cannot mint. ⭐Snapped to the coin QUANTUM first, because the setter compares with an
## EXACT `==` (GameState.gd:138) — an unsnapped write can leave the balance off the coin grid, and a bit-identical
## one is swallowed with no `account_changed`, leaving every listener painting a stale balance.
## The account write does not autosave itself, so `autosave_world_state()` follows (the Player.charge idiom).
static func _bank(args: PackedStringArray) -> PackedStringArray:
	var delta := args[0].to_float()
	var before := GameState.account
	GameState.account = snappedf(before + delta, ZorkmidsReg.QUANTUM)
	var out := PackedStringArray(["bank: %s -> %s" % [_money_text(before), _money_text(GameState.account)]])
	if GameState.account == before:
		out.append("  no change — the setter swallows a bit-identical write, so account_changed never fired")
	else:
		out.append("  " + ("savings" if GameState.account >= 0.0 else "OWED to the Ledger"))
		GameState.autosave_world_state()
	return out


## `credit <delta>` — move the earned half of the credit score through the CLAMPED mutator. A direct
## `GameState.credit_standing = x` bypasses the +/- credit_standing_max clamp that add_credit_standing and
## load_from_disk both enforce. The credit LIMIT itself cannot be set: it is recomputed live from the raw stat
## sheet and persisted nowhere.
static func _credit(args: PackedStringArray) -> PackedStringArray:
	var delta := args[0].to_float()
	var before := GameState.credit_standing
	var moved := GameState.add_credit_standing(delta)
	var out := PackedStringArray(["credit: standing %s -> %s" % [_num(before), _num(GameState.credit_standing)]])
	if not is_equal_approx(moved, delta):
		out.append("  clamped: asked %s, moved %s (economy.credit_standing_max)" % [_num(delta), _num(moved)])
	var p: Node = GameState.live_player()
	if p != null and p.has_method(&"credit_rating"):
		var rating: Dictionary = p.call(&"credit_rating")
		out.append("  score %d, band %s, limit %s" % [int(rating.get("score", 0)), String(rating.get("band", &"")), _money_text(float(p.call(&"credit_limit")))])
	# Only persist when something actually moved. add_credit_standing returns 0.0 for a zero/clamped-out delta,
	# and autosave_world_state is a full profile capture + atomic disk write that ALSO discards any pending
	# in-memory WorldSnapshot (GameState.gd:876-878) — not something to spend on a no-op.
	if not is_zero_approx(moved):
		GameState.autosave_world_state()
	return out


## `xp <amount>` — grant XP through the real curve.
##
## ⭐The granted total is REPORTED, not assumed: add_xp multiplies the amount by
## `GameSettings.difficulty.xp_gain_mult` (player.gd:1348), so off Normal difficulty `xp 1000` does not grant 1000.
## ⭐`amount <= 0` is a hard no-op inside add_xp and there is NO remove-XP method anywhere in the project.
static func _xp(p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var asked := args[0].to_float()
	if asked <= 0.0:
		return PackedStringArray(["xp: amount must be positive — add_xp ignores anything else and there is no remove-XP path"])
	var before_xp := p.xp
	var before_level := p.level
	var levels := p.add_xp(asked)
	var granted := p.xp - before_xp
	var out := PackedStringArray(["xp: asked %s, GRANTED %s (difficulty xp_gain_mult %s)" % [_num(asked), _num(granted), _num(GameSettings.difficulty.xp_gain_mult)]])
	out.append("  total %s, level %d%s" % [_num(p.xp), p.level, ("" if levels <= 0 else " (+%d from %d)" % [levels, before_level])])
	if levels > 0:
		var pm := _find_perk_manager(p)  # add_xp already created it when it granted the points
		out.append("  skill points now %d" % (0 if pm == null else pm.skill_points))
	return out


## `sp <points>` — hand out perk picks directly.
##
## ⭐Skill points do NOT live on the Player or on GameState at runtime — only on the PerkManager child named
## "Perks", which is auto-created on first use. `points_earned` is bumped alongside `skill_points` for the same
## reason add_xp does it: a respec refunds `skill_points` back UP TO `points_earned`, so points granted without
## it would be destroyed by the next respec.
static func _sp(p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var points := int(round(args[0].to_float()))
	var pm := _perk_manager(p)
	var before := pm.skill_points
	pm.skill_points = maxi(0, pm.skill_points + points)
	pm.points_earned = maxi(0, pm.points_earned + points)
	GameState.autosave(p)  # PerkManager persists nothing on its own
	return PackedStringArray(["sp: %d -> %d skill points (points_earned %d, which is what a respec refunds to)" % [before, pm.skill_points, pm.points_earned]])


## `perk <id>` — unlock a perk free, ignoring its point cost.
##
## ⭐Perks.by_id() is SILENT on a miss by design, so the null is reported here.
## ⭐unlock_perk re-stamps derived max_hp / carry / stamina through CharacterStats.restamp_derived, so the
## player's CURRENT HP can move as a side effect. That is reported, not hidden.
static func _perk(p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var id := StringName(args[0].strip_edges())
	var perk := PerksReg.by_id(id)
	if perk == null:
		return PackedStringArray(["perk: no perk resource for id \"%s\" (resources/perks/<id>.tres) — `perks` lists them" % id])
	var pm := _perk_manager(p)
	if pm.has_perk(perk.id):
		return PackedStringArray(["perk: %s already unlocked" % perk.id])
	if not pm.can_unlock(perk):
		return PackedStringArray(["perk: %s is gated — missing prerequisite(s): %s" % [perk.id, ", ".join(_missing_prereqs(pm, perk))]])
	var old_hp := p.hp
	var old_max := p.max_hp
	if not pm.unlock_perk(perk):
		return PackedStringArray(["perk: %s refused by PerkManager.unlock_perk" % perk.id])
	GameState.autosave(p)  # unlock_perk itself persists nothing
	var out := PackedStringArray(["perk: unlocked %s (%s)" % [perk.id, PerksReg.display_label(perk.id)]])
	if not (is_equal_approx(old_hp, p.hp) and is_equal_approx(old_max, p.max_hp)):
		out.append("  its stat bonuses re-stamped hp %s/%s -> %s/%s" % [_num(old_hp), _num(old_max), _num(p.hp), _num(p.max_hp)])
	return out


## `perks` — every perk id on disk with its unlocked state.
static func _perks(p: Player) -> PackedStringArray:
	var out := PackedStringArray()
	var pm := _find_perk_manager(p)
	var ids := PerksReg.ids()
	if ids.is_empty():
		out.append("perks: none authored under resources/perks/")
	for id in ids:
		var owned := pm != null and pm.has_perk(StringName(id))
		out.append("  [%s] %-16s %s" % [("x" if owned else " "), id, PerksReg.display_label(StringName(id))])
	if pm != null:
		out.append("perks: %d unlocked, %d skill points unspent" % [pm.unlocked_ids().size(), pm.skill_points])
	return out


## `respec` — the DANGER row. Reverses every perk's permanent stat bonuses, revokes the abilities those perks
## introduced, and refunds skill points back up to points_earned.
##
## ⭐This is `PerkManager.respec()`, the RAW call: it charges NOTHING and autosaves nothing (RespecStation
## .do_respec is the one that bills you). The autosave is added here so the refund actually survives a reload.
## The output says plainly what it did, because this is the one thing in this module you cannot undo.
static func _respec(p: Player) -> PackedStringArray:
	if p == null:
		return _no_player()
	var pm := _find_perk_manager(p)  # no manager at all means no perks — do not create one just to no-op
	if pm == null:
		return PackedStringArray(["respec: no perks unlocked — nothing to refund"])
	var owned: Array = pm.unlocked_ids().duplicate()
	if owned.is_empty():
		return PackedStringArray(["respec: no perks unlocked — nothing to refund"])
	var old_max := p.max_hp
	var count := pm.respec()
	GameState.autosave(p)
	var out := PackedStringArray()
	out.append("respec: REVERSED %d perk(s) — %s" % [count, ", ".join(_as_strings(owned))])
	out.append("  their permanent stat bonuses were subtracted and the abilities they INTRODUCED were revoked")
	out.append("  skill points refunded to %d (points_earned; free station grants never counted)" % pm.skill_points)
	if not is_equal_approx(old_max, p.max_hp):
		out.append("  max_hp %s -> %s, hp clamped into the new range" % [_num(old_max), _num(p.max_hp)])
	out.append("  charged nothing — this cannot be undone from here")
	# ⭐Do NOT report a save off the call alone: GameState.autosave is a HARD no-op off-tree and while a
	# quickload is in flight (GameState.gd:869-875), and this is the one row you cannot walk back — a
	# "saved" it did not do is exactly the lie that costs a run.
	out.append("  saved" if _save_landed(p) else "  NOT saved — a scene reload is in flight (GameState.reload_pending); the refund is in memory only")
	return out


## `weapon <item id|none> [clips]` — give a weapon AND draw it through BOTH inventories in one step.
##
## ⭐`give pistol_item` leaves the gun in the bag, and equipping through the hub alone (weapon_system.equip_weapon)
## leaves CharacterInventory.equipped_item stale — the UI's equipped marker and the death card read the BAG
## ([[character-two-inventories-weapon-name]]). So the draw goes through the BAG's `equip_item`
## (character_inventory.gd:789), whose signal chain is the real one: equip_weapon_requested ->
## Player._on_equip_weapon_requested (player.gd:830) -> Weapon.equip_weapon (weapon_system.gd:105) ->
## SwapWeapons.request_equip (swap_weapons.gd:32) -> Attack._on_swap_weapons_equip_this (attack.gd:524) ->
## set_holstered(false) (:539) -> hub inventory.equip (:551). ⭐The hub updates SYNCHRONOUSLY, at the START of
## the swap — the swap_time Timer only gates the down/up animation and firing. The one async case is a request
## that lands while a swap is already running: it is QUEUED (`_pending_swap_weapon`, :526-528) and equips when
## that raise ends, so the hub is read back AFTER the call and whichever of the two happened is reported.
## ⭐ItemDb.restore_item gives a FRESH unique Item for a weapon (item_db.gd:77) — never the shared template — and it
## is equipped ONLY if the bounded Tetris grid accepted it (add returned 1): the project invariant is "never
## wield a gun that isn't in the bag" (player.gd:733-735). Clips reuse the player.gd:810-815 seed idiom:
## ItemDb.ammo_item_for(caliber) is the SHARED template, added by reference so it stacks. `none` unequips to
## fists through the real path (inventory.unequip -> equipped_item_lost -> Player falls back to FISTS, :837).
## ⭐Attack.draw_locked (set while carrying a prop, player.gd:418) makes set_holstered(false) refuse at :139 — the
## hub still equips, the gun just stays holstered until the prop drops. Reported, not fought.
static func _weapon(p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var inv := p.inventory
	if inv == null:
		return PackedStringArray(["weapon: no backpack — CharacterInventory is built in Character._ready, so the player is off-tree"])
	var word := args[0].strip_edges()
	if word.to_lower() == "none":
		return _weapon_none(p)
	var id := StringName(word)
	var template := ItemDb.item_by_id(id)
	if template == null:
		return PackedStringArray(["weapon: no item registered with id \"%s\" — `items` lists them" % id])
	if not template.is_weapon():
		return PackedStringArray(["weapon: %s is not a weapon item (WEAPON category with a WeaponData) — `give` handles the rest" % template.label()])
	var clips := 0
	if args.size() > 1:
		clips = maxi(0, int(round(args[1].to_float())))
	var ws: Weapon = p.weapon_system if is_instance_valid(p.weapon_system) else null
	var attack: Attack = null
	if ws != null and is_instance_valid(ws.attack):
		attack = ws.attack
	var out := PackedStringArray()
	# --- the bag: a fresh unique item, equipped only if the grid took it ------------------------------------
	var one := ItemDb.restore_item(id)  # a FRESH unique weapon Item (item_db.gd:77-81), never the shared template
	var added := inv.add(one, 1) if one != null else 0
	var target: Item = one if added == 1 else null
	if target != null:
		out.append("weapon: %s added to the backpack" % template.label())
	else:
		# The grid refused the new one. Draw a copy ALREADY in the bag if there is one, so the command still puts the
		# gun in hand — but never the refused item (it is not in the bag).
		var existing := inv.find_by_id(id)
		if existing != null and existing.is_weapon():
			target = existing
			out.append("weapon: the bounded grid refused a new %s — drawing the copy already in the bag instead" % template.label())
		else:
			out.append("weapon: the bounded grid refused %s (add returned 0) and the bag holds none — NOT equipped (never wield a gun that isn't in the bag)" % template.label())
	# --- the draw, through the bag's real signal chain -----------------------------------------------------
	if target != null:
		var hub_before: WeaponData = ws.equipped_weapon if ws != null else null
		var same_data := hub_before != null and hub_before == target.weapon
		if not inv.equip_item(target):
			out.append("  equip_item refused (not a weapon-item?) — the bag's equipped marker is unchanged")
		else:
			out.append("  equipped_item -> %s (backpack marker + hotbar agree — the hotbar repaints off equip_weapon_requested)" % target.label())
			if ws == null:
				out.append("  no weapon hub on this player — the bag asked, nobody drew")
			elif same_data:
				# Attack._on_swap_weapons_equip_this drops a request for the gun already drawn (attack.gd:525), so
				# neither the swap nor its set_holstered(false) runs — a holstered gun stays holstered (hold R).
				out.append("  the hub already holds this WeaponData (shared per weapon kind) — no swap, marker moved to the new item%s" % ("; it stays HOLSTERED (the no-op swap skips the draw — hold R)" if attack != null and attack.holstered else ""))
			else:
				# Read the hub BACK: Attack equips it synchronously when the swap starts (attack.gd:551); it only
				# stays on the old gun when a swap was already in flight and this request got queued (:526-528).
				var hub_after: WeaponData = ws.equipped_weapon
				if hub_after == target.weapon:
					out.append("  hub now holds %s — the %ss swap Timer plays the down/up and blocks fire until it lands; the hub itself switched at once" % [_weapon_name(hub_after), _num(GameSettings.weapon_general.swap_time)])
				else:
					out.append("  hub still holds %s — a swap was already mid-flight, so this request is QUEUED (Attack._pending_swap_weapon) and equips when that raise ends" % _weapon_name(hub_after))
			if attack != null and attack.draw_locked:
				out.append("  ! draw_locked (carrying a prop): the hub equips but Attack.set_holstered(false) refuses — the gun stays holstered until the prop drops")
	# --- reserve clips of its caliber ----------------------------------------------------------------------
	var stocked := 0
	if clips > 0:
		var caliber: StringName = template.weapon.caliber
		if caliber == &"":
			out.append("  clips: %s has no caliber (free refill weapon) — no reserve to add" % template.label())
		else:
			var ammo_item := ItemDb.ammo_item_for(caliber)  # SHARED template — added by reference so it stacks
			if ammo_item == null:
				out.append("  clips: no ammo item registered for caliber %s" % caliber)
			else:
				stocked = inv.add(ammo_item, clips)
				out.append("  clips: %d/%d %s added (reserve now %d clips of %s)%s" % [stocked, clips, ammo_item.label(), inv.ammo_count(caliber), caliber, ("" if stocked == clips else " — the grid could not place the rest")])
	# equip_item moves the bag's marker WITHOUT emitting `changed` (character_inventory.gd:789-794); only an add
	# that actually placed something queues the deferred autosave that carries the new equipped_index along.
	if added > 0 or stocked > 0:
		out.append("  each add fired inventory.changed -> deferred profile autosave (%s)" % _save_where())
	elif target != null:
		out.append("  nothing was added, so no inventory.changed — the moved equip marker persists on the NEXT autosave (any money/inventory event)")
	return out


## `weapon none` — put the drawn weapon away to bare fists through the real unequip path.
static func _weapon_none(p: Player) -> PackedStringArray:
	var inv := p.inventory
	var ws: Weapon = p.weapon_system if is_instance_valid(p.weapon_system) else null
	var attack: Attack = null
	if ws != null and is_instance_valid(ws.attack):
		attack = ws.attack
	var out := PackedStringArray()
	var hub: WeaponData = ws.equipped_weapon if ws != null else null
	if inv.equipped_item != null:
		var was := inv.equipped_item.label()
		inv.unequip()  # -> equipped_item_lost -> Player._on_equipped_item_lost -> weapon_system.equip_weapon(FISTS); also emits changed
		out.append("weapon: unequipped %s — the bag's marker cleared, the player falls back to FISTS through the swap path" % was)
		out.append("  unequip fired inventory.changed -> deferred profile autosave (%s)" % _save_where())
	elif hub != null and hub != Player.FISTS and ws != null:
		# The bag marks nothing but the hub holds a real gun — the two disagree (hub-only equip). unequip() would
		# no-op on a null equipped_item, so fall back to the hub's own fists path and say why.
		ws.equip_weapon(Player.FISTS)
		out.append("weapon: the bag marked nothing but the hub held %s (the two inventories disagreed) — hub sent to FISTS directly" % _weapon_name(hub))
	else:
		return PackedStringArray(["weapon: already on fists (nothing equipped in the bag, hub holds %s)" % _weapon_name(hub)])
	if attack != null and attack.draw_locked:
		out.append("  draw_locked (carrying a prop): the fists equip but stay holstered until the prop drops")
	# The hub equips synchronously at swap start (attack.gd:551); it only lags when a swap was already running.
	if ws != null and ws.equipped_weapon != Player.FISTS:
		out.append("  hub still holds %s — a swap was mid-flight, so the fists request is QUEUED and lands when that raise ends" % _weapon_name(ws.equipped_weapon))
	out.append("  the item stays in the backpack; a %ss swap Timer plays the put-away" % _num(GameSettings.weapon_general.swap_time))
	return out


## `ammo [on|off|fill]` — infinite ammo, or a free top-up of the magazine plus every reserve caliber.
##
## INFINITE = `Ammo.ammo_cost = 0` (ammo.gd:19): consume_ammo does `current_ammo - ammo_cost >= 0` then decrements
## by it (:78-79), so 0 fires forever and never touches the count. It is a plain var on the player's Ammo NODE.
## ⭐WHERE THAT NODE LIVES decides the bank's lifetime: Ammo is ONE node per WIELDER (weapon.tscn's child under the
## Player, `Weapon.ammo` weapon_system.gd:18) — NOT per weapon. It survives every swap and reload (it banks each
## weapon's clip in _ammo_per_weapon, ammo.gd:26) and a level warp (the Player is untouched by GameRoot.load_level).
## It dies only WITH the Player: a scene reload / a RELOAD_* death — which also frees the console and its state
## dict, so nothing here belongs in release_scene_scoped_state (this is a per-body knob like armor_flat, not a
## shared .tres). What remains is the same "flag vs truth" window `god` handles: the ctx flag can say "on" over a
## fresh Ammo whose cost is 1, so the LIVE cost is the truth and a mismatch re-arms rather than reporting a no-op.
## Deliberately NOT WeaponData.is_infinite_ammo — a SHARED .tres field that also mutes shell/noise paths.
## FILL = Ammo.set_to_max_ammo() (:52 — the AI's free refill, no clip spent; reload() would EJECT the partial clip
## and spend a spare, :106-114) + AMMO_FILL_CLIPS of every registered is_ammo() item (SHARED templates, added by
## reference — never duplicated, or they stop stacking). NPCs own their own Ammo nodes, so only the player moves.
static func _ammo(ctx: Dictionary, p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var ws: Weapon = p.weapon_system if is_instance_valid(p.weapon_system) else null
	if ws == null or not is_instance_valid(ws.ammo):
		return PackedStringArray(["ammo: no Ammo node — the weapon hub (weapon_system.ammo) is null or freed on this player"])
	var ammo: Ammo = ws.ammo
	var st := _state(ctx)
	var word := _word(args, 0).strip_edges().to_lower()
	if word == "fill":
		return _ammo_fill(p, ammo)
	var flagged := bool(st.get(&"player/ammo_infinite", false))
	var armed := ammo.ammo_cost <= 0
	var current := flagged and armed
	if word == "":
		var report := PackedStringArray(["ammo: infinite %s (live ammo_cost %d%s)" % [_onoff(armed), ammo.ammo_cost, ("" if flagged == armed else ", ctx flag says " + _onoff(flagged) + " — the body was replaced; `ammo on` re-arms")]])
		report.append("  " + _clip_line(p, ws, ammo))
		return report
	var want := Commands.toggle_value(word, current)
	if want == current and flagged == armed:
		return PackedStringArray(["ammo: already %s" % _onoff(current)])
	var out := PackedStringArray()
	if want:
		# Bank the ORIGINAL cost, never our own 0: re-arming after a body swap must keep the real value.
		if ammo.ammo_cost > 0:
			st[&"player/ammo_cost"] = ammo.ammo_cost
		ammo.ammo_cost = 0
		st[&"player/ammo_infinite"] = true
		out.append("ammo: infinite on (ammo_cost %d -> 0; consume_ammo never decrements)" % int(st.get(&"player/ammo_cost", AMMO_COST_DEFAULT)))
		if flagged and not armed:
			out.append("  (re-armed: the ctx flag outlived the Ammo node — the body was replaced under a surviving debug state dict)")
		# consume_ammo is `current_ammo - 0 >= 0` — TRUE even at 0 rounds — so an empty clip fires too; but attack.gd:405
		# plays the empty click after every shot taken at 0 and :476 auto-reloads an auto_reload weapon, so a
		# clean test starts from a filled clip.
		out.append("  the clip count stays as it is — even an EMPTY clip fires now, but at 0 rounds the empty click plays after each shot and an auto_reload gun keeps re-chambering: `ammo fill` first")
	else:
		ammo.ammo_cost = int(st.get(&"player/ammo_cost", AMMO_COST_DEFAULT))
		st.erase(&"player/ammo_cost")
		st[&"player/ammo_infinite"] = false
		out.append("ammo: infinite off (ammo_cost restored to %d)" % ammo.ammo_cost)
	out.append("  " + _clip_line(p, ws, ammo))
	return out


## `ammo fill` — magazine to max for free, then AMMO_FILL_CLIPS of every registered ammo item into the backpack.
static func _ammo_fill(p: Player, ammo: Ammo) -> PackedStringArray:
	var out := PackedStringArray()
	var w: WeaponData = ammo.current_weapon
	if w == null:
		out.append("ammo: fill — no current weapon on the Ammo node (nothing to top up)")
	else:
		var before := ammo.current_ammo
		ammo.set_to_max_ammo()  # free: no clip spent, no eject (unlike reload())
		out.append("ammo: fill — clip %d -> %d / %d (%s; free, no reserve spent — the HUD polls current_ammo so it repaints)" % [before, ammo.current_ammo, w.max_ammo, _weapon_name(w)])
	var inv := p.inventory
	if inv == null:
		out.append("  no backpack — reserve not stocked (CharacterInventory is built in Character._ready)")
		return out
	var weight_before := p.current_carry_weight()
	var stocked := 0
	var refused := 0
	for item in ItemDb.all_items():
		if item == null or not item.is_ammo():
			continue
		var got := inv.add(item, AMMO_FILL_CLIPS)  # the SHARED template by reference — stacks with what is carried
		if got > 0:
			stocked += 1
		if got < AMMO_FILL_CLIPS:
			refused += 1
		out.append("  %-14s +%d/%d clips -> %d %s in reserve" % [item.label(), got, AMMO_FILL_CLIPS, inv.ammo_count(item.caliber), item.caliber])
	if stocked == 0 and refused == 0:
		out.append("  no is_ammo() items registered in ItemDb — reserve untouched")
	if refused > 0:
		out.append("  the bounded grid could not place every stack — `give ammo_<x> <n>` for one caliber")
	out.append("  carry %s -> %s / %s (heaviness %s)%s" % [_num(weight_before), _num(p.current_carry_weight()), _num(p.carry_capacity), _num(p.heaviness()), (" — encumbered, the load speed penalty applies" if p.heaviness() > 0.0 else "")])
	if stocked > 0:
		out.append("  each add fired inventory.changed -> deferred profile autosave (%s)" % _save_where())
	return out


## `level <n>` — set the XP level directly.
##
## UP goes through `add_xp` (player.gd:1345): the XP needed is the curve's inverse, `GameSettings.xp.xp_to_reach(n)`
## (XpSettings.gd:19) minus the current total, divided by `difficulty.xp_gain_mult` because add_xp multiplies it
## back (:1348) — so the grant lands exactly on the threshold and the whole jump is ONE leveled_up + one toast +
## the skill points for every level crossed. ⭐add_xp autosaves SYNCHRONOUSLY (:1362) — a real save write.
## DOWN has no method (there is no remove-XP path anywhere), so `xp` / `level` are written directly — bare vars,
## player.gd:67-68 — then `xp_changed` is re-emitted (nothing but the Stats screens' summary listens) and
## GameState.autosave(p) persists it, since the direct write is not on the add_xp save path. Skill points and
## points_earned are deliberately left alone on the way down (a respec refunds to points_earned): reported.
static func _level(p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var asked := int(round(args[0].to_float()))
	if asked < 0:
		return PackedStringArray(["level: must be 0 or more"])
	var n := mini(asked, LEVEL_CAP)
	var out := PackedStringArray()
	if n != asked:
		out.append("level: %d clamped to %d — XpSettings.level_for_xp never reports past it" % [asked, LEVEL_CAP])
	var curve: XpSettings = GameSettings.xp
	if n == p.level:
		out.append("level: already %d (xp %s; next at %s)" % [n, _num(p.xp), _num(curve.xp_to_reach(n + 1))])
		return out
	var before_xp := p.xp
	var before_level := p.level
	var need := curve.xp_to_reach(n) - p.xp
	if n > p.level and need > 0.0:
		var mult: float = GameSettings.difficulty.xp_gain_mult
		if mult <= 0.0:
			out.append("level: refused — GameSettings.difficulty.xp_gain_mult is %s, so add_xp would grant nothing (fix the difficulty resource, or `sp` for the points)" % _num(mult))
			return out
		var pm_before := _find_perk_manager(p)
		var sp_before := 0 if pm_before == null else pm_before.skill_points
		var gained := p.add_xp((need + XP_EXACT_EPS) / mult)
		out.append("level: %d -> %d via add_xp (asked %s, granted %s at xp_gain_mult %s)" % [before_level, p.level, _num((need + XP_EXACT_EPS) / mult), _num(p.xp - before_xp), _num(mult)])
		var pm := _find_perk_manager(p)
		out.append("  xp %s -> %s   %d level(s) crossed, skill points %d -> %d" % [_num(before_xp), _num(p.xp), gained, sp_before, (0 if pm == null else pm.skill_points)])
		if p.level != n:
			out.append("  ! landed on %d, not %d — the curve is degenerate past here (level_for_xp stops on a non-increasing ramp)" % [p.level, n])
		# add_xp's own GameState.autosave(self) is the same HARD no-op off-tree / mid-quickload as ours (GameState.gd:905-912).
		out.append("  " + ("add_xp autosaved SYNCHRONOUSLY (%s) and toasted the level-up" % _save_where() if _save_landed(p) else "add_xp's synchronous autosave was a NO-OP (off-tree or GameState.reload_pending) — the XP is in memory only"))
		return out
	# DOWN (or a state where xp already covers n but level lags): write the pair and re-emit. Going DOWN pins xp to
	# the new level's threshold; the lagging-level oddity (only a hand-edited save can produce it) keeps whatever
	# xp already covers n rather than throwing the surplus away.
	var floor_xp := curve.xp_to_reach(n)
	p.xp = floor_xp if n < before_level else maxf(p.xp, floor_xp)
	p.level = n
	p.xp_changed.emit(p.xp, p.level)
	GameState.autosave(p)
	out.append("level: %d -> %d written directly (xp %s -> %s; xp_to_reach(%d) = %s)" % [before_level, p.level, _num(before_xp), _num(p.xp), n, _num(floor_xp)])
	if n > before_level:
		out.append("  went UP by direct write because xp already covered level %d — no skill points granted (add_xp is the only points path); `sp` for those" % n)
	out.append("  skill_points / points_earned untouched — a respec still refunds to points_earned; `sp` adjusts them")
	out.append("  " + ("saved (GameState.autosave: %s)" % _save_where() if _save_landed(p) else "NOT saved — off-tree or a scene reload is in flight (GameState.reload_pending); the write is in memory only"))
	return out


## `give <item id> [count]` — put an item in the BACKPACK (Character.inventory), not the weapon hub.
##
## ⭐`CharacterInventory.add()` returns how many ACTUALLY fit and can return 0: the player's bag is a bounded
## Tetris grid (enabled at player.gd:630). The return value is always reported.
## ⭐A weapon is requested ONE AT A TIME, because ItemDb.restore_item returns a FRESH unique Item for a weapon and
## the SHARED template for everything else — asking for three pistols in one add() would file three stacks that
## all alias one object. Ammo/consumables must keep the shared template, or they stop stacking.
## ⭐Zorkmids are refused: the coin tile is a DERIVED VIEW that MoneyPurse rebuilds from `money` on every
## inventory.changed, so adding it here is silently reverted. Use `money`.
static func _give(p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	var inv := p.inventory
	if inv == null:
		return PackedStringArray(["give: no backpack — CharacterInventory is built in Character._ready, so the player is off-tree"])
	var id := StringName(args[0].strip_edges())
	if id == ZorkmidsReg.ITEM_ID:
		return PackedStringArray(["give: zorkmids are a derived tile MoneyPurse rebuilds from the wallet — use `money <amount>`"])
	var count := 1
	if args.size() > 1:
		count = maxi(1, int(round(args[1].to_float())))
	var template := ItemDb.item_by_id(id)
	if template == null:
		return PackedStringArray(["give: no item registered with id \"%s\" — `items` lists them" % id])
	var added := 0
	if template.is_weapon():
		for _i in count:
			var one := ItemDb.restore_item(id)  # a fresh unique WeaponData per acquisition
			if one == null:
				break
			added += inv.add(one, 1)
	else:
		added += inv.add(ItemDb.restore_item(id), count)
	var out := PackedStringArray(["give: %d/%d %s added" % [added, count, template.label()]])
	if added < count:
		out.append("  the bounded inventory grid could not place the rest")
	return out


## `items [filter]` — the ItemDb registry, optionally filtered by substring.
static func _items(args: PackedStringArray) -> PackedStringArray:
	var filter := ""
	if args.size() > 0:
		filter = args[0].strip_edges().to_lower()
	var out := PackedStringArray()
	var shown := 0
	for id in _item_ids():
		if filter != "" and not id.to_lower().contains(filter):
			continue
		shown += 1
		var item := ItemDb.item_by_id(StringName(id))
		out.append("  %-22s %s" % [id, ("" if item == null else item.label())])
	out.append("items: %d shown%s" % [shown, ("" if filter == "" else " matching \"%s\"" % filter)])
	return out


## `effect <id> [seconds]` — apply a status effect.
##
## ⭐A duration override DUPLICATES the resource first: the .tres under resources/status/ is shared by every
## consumable and weapon that applies it, and writing `duration` onto it would re-tune the game for the session.
## The duplicate has no resource_path, and `StatusEffectManager.serialize()` skips a path-less effect — so an
## overridden effect deliberately does not survive a save/load. Duration 0 means PERMANENT until removed.
static func _effect(p: Player, args: PackedStringArray) -> PackedStringArray:
	if p == null:
		return _no_player()
	if not p.is_inside_tree():
		return PackedStringArray(["effect: player is off-tree — apply_status_effect has to add_child the manager"])
	var id := args[0].strip_edges()
	var paths := _scan_effects()
	if not paths.has(id):
		return PackedStringArray(["effect: no status effect \"%s\" under %s — `effects` lists them" % [id, EFFECT_DIR]])
	var res := load(String(paths[id]))
	var fx := res as StatusEffect
	if fx == null:
		return PackedStringArray(["effect: %s did not load as a StatusEffect" % id])
	var overridden := false
	var replaced := false
	if args.size() > 1:
		fx = fx.duplicate() as StatusEffect  # never write duration onto the shared .tres
		fx.duration = maxf(0.0, args[1].to_float())
		overridden = true
		# ⭐apply_effect REFRESHES rather than replaces: an effect whose NON-BLANK id is already active only has
		# its `remaining` re-stamped and keeps the ORIGINAL resource (status_effect_manager.gd:41-45). With an
		# override of 0 ("permanent") that is actively wrong — remaining becomes 0 while the live resource still
		# reports duration > 0, so tick() (:137-140) expires it on the very next frame and the printed "permanent"
		# is a lie. Drop the incumbent first so OUR copy becomes the live one and the override really lands.
		var live := p.status_manager()
		if fx.id != &"" and live != null and live.has_effect(fx.id):
			live.remove_effect(fx.id)
			replaced = true
	p.apply_status_effect(fx)
	var out := PackedStringArray()
	out.append("effect: applied %s for %s" % [id, ("EVER (permanent until cleared)" if fx.duration <= 0.0 else "%ss" % _num(fx.duration))])
	if overridden:
		out.append("  duration overridden on a COPY — it will not survive a save (serialize skips a path-less effect)")
	if replaced:
		out.append("  the already-active %s was dropped first — apply_effect only REFRESHES a live id, it never swaps the resource" % id)
	if fx.id == &"":
		out.append("  blank id: this effect always STACKS and `remove_effect` cannot target it — only `cleareffects` can")
	return out


## `effects` — what is authored on disk and what is live right now.
static func _effects(p: Player) -> PackedStringArray:
	var out := PackedStringArray()
	var mgr: StatusEffectManager = p.status_manager() if p != null else null
	var ids := _effect_ids()
	for id in ids:
		var active := mgr != null and mgr.has_effect(StringName(id))
		out.append("  [%s] %s" % [("*" if active else " "), id])
	out.append("effects: %d on disk, %d active" % [ids.size(), (0 if mgr == null else mgr.active_count())])
	if mgr == null:
		out.append("  (no StatusEffectManager yet — it is created lazily on the first applied effect)")
	else:
		out.append("  note: the tick driver is gated on InputManager.world_frozen(), so effects pause in a cinematic")
	return out


## `cleareffects` — drop everything active. `clear_effects()` is the only way to remove a blank-id effect, since
## `remove_effect` matches on StatusEffect.id.
static func _clear_effects(p: Player) -> PackedStringArray:
	if p == null:
		return _no_player()
	var mgr := p.status_manager()
	if mgr == null:
		return PackedStringArray(["cleareffects: no StatusEffectManager — nothing has ever been applied"])
	var n := mgr.active_count()
	mgr.clear_effects()
	return PackedStringArray(["cleareffects: removed %d active effect(s)" % n])


## `rep <faction> [value]` — read or SET standing exactly.
##
## ⭐`add_reputation` SCALES the delta by the player's STREETWISE (Reputation.gd:38-41), so a console command using
## it would not move standing by the number typed. The exact set is `adjust_unscaled(f, target - current)`, which
## still clamps to [rep_min, rep_max] and still fires reputation_changed + alignment_changed.
## ⭐Rep is not persisted until the next GameState.capture(), so the write is followed by autosave_world_state().
static func _rep(args: PackedStringArray) -> PackedStringArray:
	var wanted := args[0].strip_edges()
	var faction := FactionsReg.by_id(wanted)
	if faction == null:
		return PackedStringArray(["rep: no faction resource \"%s\" under resources/factions/ — `reps` lists them" % wanted])
	var current := Reputation.get_reputation(faction)
	if args.size() == 1:
		return PackedStringArray(["rep %s: %s (%s)" % [faction.id, _num(current), _disposition_word(Reputation.disposition_for(faction))]])
	var target := args[1].to_float()
	var total := Reputation.adjust_unscaled(faction, target - current)
	var out := PackedStringArray(["rep %s: %s -> %s (%s)" % [faction.id, _num(current), _num(total), _disposition_word(Reputation.disposition_for(faction))]])
	if not is_equal_approx(total, target):
		out.append("  clamped to [%s, %s] by GameSettings.reputation" % [_num(GameSettings.reputation.rep_min), _num(GameSettings.reputation.rep_max)])
	if String(faction.id) != wanted:
		out.append("  note: keyed on the INTERNAL id \"%s\", not the filename \"%s\"" % [faction.id, wanted])
	GameState.autosave_world_state()
	return out


## `reps` — every faction on disk with its standing and the disposition that follows.
static func _reps() -> PackedStringArray:
	var out := PackedStringArray()
	var ids := FactionsReg.ids()
	if ids.is_empty():
		out.append("reps: no faction resources under resources/factions/")
	for fid in ids:
		var faction := FactionsReg.by_id(fid)
		if faction == null:
			out.append("  %-18s (failed to load)" % fid)
			continue
		out.append("  %-18s %8s  %s" % [faction.id, _num(Reputation.get_reputation(faction)), _disposition_word(Reputation.disposition_for(faction))])
	out.append("reps: thresholds hostile <= %s, friendly >= %s" % [_num(GameSettings.reputation.hostile_threshold), _num(GameSettings.reputation.friendly_threshold)])
	return out


# --- shared helpers ---------------------------------------------------------------------------------------

## Unwind every SHARED-TUNING override this module banked in `ctx[&"state"]`, restoring the authored values onto
## GameSettings. Called by the console's `_exit_tree` (and by the world module's reload/load path), because the
## state dictionary dies with the console — and the console dies on EVERY reload_current_scene: a death reload
## (player.gd death modes), F9 quickload, PlayerDebug's End key. Without this, `speed 3` + one death leaves
## `GameSettings.player_movement.max_speed` at 3x for the session with the fresh console calling that "authored",
## and `god`'s zeroed fall-death timer stays zero with no record left to restore it from. ⭐Only the SHARED .tres
## knobs are unwound: `armor_flat` lives on the Player and is freed with it, so it needs nothing here.
## Idempotent — every key is erased after restore, so the menu (which shares the dict) calling it too is a no-op.
static func release_scene_scoped_state(ctx: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var st := _state(ctx)
	if st.has(&"player/speed_base"):
		GameSettings.player_movement.max_speed = float(st[&"player/speed_base"])
		st.erase(&"player/speed_base")
		st.erase(&"player/speed_mult")
		out.append("speed override released — max_speed back to authored %s" % _num(GameSettings.player_movement.max_speed))
	if st.has(&"player/god_fall_time"):
		GameSettings.player_movement.max_continuous_fall_time = float(st[&"player/god_fall_time"])
		st.erase(&"player/god_fall_time")
		st.erase(&"player/god_armor")
		st.erase(&"player/god")
		out.append("god released — continuous-fall death timer back to %ss (armour is on the freed body)" % _num(GameSettings.player_movement.max_continuous_fall_time))
	return out


## The host's cross-command scratch dictionary. Dictionaries are passed by REFERENCE in GDScript, so writing into
## the returned dict (or seeding ctx with one when the host forgot) persists for the next command.
static func _state(ctx: Dictionary) -> Dictionary:
	var s = ctx.get(&"state")
	if s is Dictionary:
		return s
	var fresh := {}
	ctx[&"state"] = fresh
	return fresh


static func _word(args: PackedStringArray, index: int) -> String:
	return args[index] if index < args.size() else ""


static func _onoff(on: bool) -> String:
	return "on" if on else "off"


static func _no_player() -> PackedStringArray:
	return PackedStringArray(["no live player — this command needs one in the tree (main menu / between levels has none)"])


## Did the `GameState.autosave(p)` we just fired actually reach disk? It is a HARD no-op when the player is null
## or off-tree, and while `_reload_pending` is set — a quickload done in memory but whose scene reload has not
## booted yet (GameState.gd:869-875). A command that prints "saved" off the call alone will lie in that window.
static func _save_landed(p: Player) -> bool:
	return p != null and p.is_inside_tree() and not GameState.reload_pending()


## WHERE a profile write that landed actually went: the real user://gamestate.cfg, or the dev sandbox folder when
## the world module's `sandbox on` has GameState.enable_sandbox redirecting the canonical save paths (a "real
## profile write" claim under an armed sandbox would be the wrong scary). Duck-typed like DebugActionsWorld's
## `_cmd_sandbox`: the sandbox API is additive on GameState and this module must not fail to parse without it.
static func _save_where() -> String:
	if GameState.has_method(&"sandbox_active") and bool(GameState.call(&"sandbox_active")):
		return "a SANDBOX write — `sandbox on` is redirecting the profile, `sandbox commit` makes it real"
	return "a real profile write"


## THE teleport recipe, mirroring _respawn_at_checkpoint (player.gd:3135-3146) beat for beat:
##  * zero `velocity` AND `explosion_velocity` — ⭐the blast impulse is re-added by apply_velocity on the next
##    physics frame (character.gd:977), which is the documented fling bug both die() and the respawn zero it for;
##  * clear the continuous-fall timer so arriving mid-air does not inherit three seconds of falling;
##  * re-arm the ground-snap retry budget so the player settles onto the floor beneath the target.
## ⭐The snap only runs from Player._physics_process (player.gd:2162), so while a debug UI holds the player
## suspended nothing settles until it closes — which is exactly when you want the drop to happen anyway.
## The pre-teleport position is stashed for `back`.
static func _place(ctx: Dictionary, p: Player, target: Vector3) -> void:
	var st := _state(ctx)
	st[&"player/last_pos"] = p.global_position
	p.velocity = Vector3.ZERO
	p.explosion_velocity = Vector3.ZERO
	p.global_position = target
	p.set(&"_continuous_fall_time", 0.0)
	p.set(&"_ground_snap_frames_left", Player.GROUND_SNAP_RETRY_FRAMES)


## What `back` will actually do after the teleport that just ran — for the tp/goto readouts, so they never promise
## a return trip `_back` will not make. ⭐`_back` prefers the TRANSIENT `mark` over the pre-teleport stash `_place`
## just wrote, and `mark <name>` sets that transient pair too: after `mark roof` … wander … `goto roof`, `back`
## lands on the roof AGAIN (the mark), not where you wandered to. Read after `_place`, so the stash is current.
static func _back_note(ctx: Dictionary) -> String:
	var st := _state(ctx)
	if st.has(&"player/mark_pos"):
		var mp: Vector3 = st[&"player/mark_pos"]
		return "`back` goes to the `mark` at %s, which outranks the pre-teleport stash" % _vec(mp)
	return "`back` returns to where you were"


## Why a take_damage call landed nothing. The Player override early-returns on `_dying` (player.gd:2487) and on
## `InputManager.world_frozen()` (player.gd:2494); Character.take_damage early-returns on the `_dead` latch
## (character.gd:366) and mitigates through armor_flat / damage_reduction (character.gd:376).
static func _damage_blocked_reason(p: Player) -> String:
	if bool(p.get(&"_dying")):
		return "the death cinematic is running (take_damage early-returns on _dying)"
	if not p.is_alive():
		return "already dead (take_damage early-returns on the _dead latch)"
	if is_instance_valid(InputManager) and InputManager.world_frozen():
		return "the world is frozen (a cutscene or dialogue) — take_damage early-returns"
	# Checked BEFORE armour: difficulty scales the hit first (character.gd:371-372), so a zero (or negative)
	# multiplier zeroes every incoming hit no matter how it is sized — no amount of overkill gets past it.
	if GameSettings.difficulty.damage_taken_mult <= 0.0:
		return "GameSettings.difficulty.damage_taken_mult is %s — it zeroes every hit before armour is even read" % _num(GameSettings.difficulty.damage_taken_mult)
	if p.armor_flat >= GOD_ARMOR_FLAT:
		return "god mode is on — run `god off`"
	if p.armor_flat > 0.0 or p.damage_reduction > 0.0:
		return "armour soaked it (armor_flat %s, damage_reduction %s)" % [_num(p.armor_flat), _num(p.damage_reduction)]
	return "no reason found — check the amount"


# --- body-part / limb helpers (hurt <part>, cripple, me) -----------------------------------------------------

## The console word -> Character.BodyPart, or -1. Fully qualified (Character.BodyPart.X) because this is a
## RefCounted, not a Character — the cripple_callout.gd:63 idiom.
static func _body_part_for_word(word: String) -> int:
	match word.strip_edges().to_lower():
		"head":
			return Character.BodyPart.HEAD
		"arms":
			return Character.BodyPart.ARMS
		"legs":
			return Character.BodyPart.LEGS
		"torso":
			return Character.BodyPart.TORSO
	return -1


static func _body_part_word(part: int) -> String:
	match part:
		Character.BodyPart.HEAD:
			return "head"
		Character.BodyPart.ARMS:
			return "arms"
		Character.BodyPart.LEGS:
			return "legs"
		Character.BodyPart.TORSO:
			return "torso"
	return "?"


## A WORLD-space point that Character.body_part_at (character.gd:646) classifies as `part`, composed in the player's
## LOCAL frame from its own zone exports and pushed BODY_ZONE_MARGIN past the edge: HEAD is `y >= head_local_y`,
## LEGS `y < leg_local_y`, ARMS `|x| >= arm_local_x` inside the torso band, TORSO the middle of that band on the
## centre line. `to_global` folds the body's yaw/scale in, so the point stays correct however the player is turned.
## Callers re-classify the result and refuse on a mismatch (a designer can author zones that overlap).
static func _hit_pos_for_part(p: Player, part: int) -> Vector3:
	var band_mid := (p.head_local_y + p.leg_local_y) * 0.5
	var local := Vector3(0.0, band_mid, 0.0)  # TORSO
	match part:
		Character.BodyPart.HEAD:
			local = Vector3(0.0, p.head_local_y + BODY_ZONE_MARGIN, 0.0)
		Character.BodyPart.LEGS:
			local = Vector3(0.0, p.leg_local_y - BODY_ZONE_MARGIN, 0.0)
		Character.BodyPart.ARMS:
			local = Vector3(p.arm_local_x + BODY_ZONE_MARGIN, band_mid, 0.0)
	return p.to_global(local)


static func _zone_overlap_reason(cmd: String, p: Player, part: int) -> String:
	var got := p.body_part_at(_hit_pos_for_part(p, part))
	return "%s: could not compose a %s hit — the local point re-classified as %s; the player's zone exports overlap (head_local_y %s, leg_local_y %s, arm_local_x %s)" % [
		cmd, _body_part_word(part), _body_part_word(got), _num(p.head_local_y), _num(p.leg_local_y), _num(p.arm_local_x)]


## A limb's FULL condition pool — the lazy seed value `_apply_limb_damage` uses (character.gd:708).
static func _limb_pool_full(p: Player) -> float:
	return p.max_hp * p.limb_condition_frac


## A limb's REMAINING condition pool. `_limb_condition` is a private Dictionary keyed by BodyPart int and only
## holds limbs that have been hit (character.gd:636 — lazy-seeded), so a missing key means FULL. Read through
## `get(&"…")` per the duck-typed private-read convention this file already uses for _dying / _carrying.
static func _limb_pool(p: Player, part: int) -> float:
	var full := _limb_pool_full(p)
	if part < 0:
		return full
	var pools = p.get(&"_limb_condition")
	if pools is Dictionary:
		return float((pools as Dictionary).get(part, full))
	return full


static func _limb_state(p: Player, part: int) -> String:
	if p.is_limb_crippled(part):
		return "CRIPPLED"
	var pool := _limb_pool(p, part)
	var full := _limb_pool_full(p)
	if pool < full:
		return "chipped %s/%s" % [_num(pool), _num(full)]
	return "ok"


## What a fresh cripple of `part` now does to play — the live derived value, read back off the player.
static func _cripple_effect_line(p: Player, part: int) -> String:
	match part:
		Character.BodyPart.HEAD:
			return "head: concussion — Player._on_head_crippled pulsed the hurt feedback and toasted"
		Character.BodyPart.ARMS:
			return "arms: limb_spread_penalty now +%s rad on every shot (crippled_arm_spread)" % _num(p.limb_spread_penalty(), 3)
		Character.BodyPart.LEGS:
			return "legs: limb_move_multiplier now x%s (crippled_leg_speed_mult) — the limp is in the speed chain" % _num(p.limb_move_multiplier())
	return "torso: no effect"


# --- weapon / ammo readout helpers ---------------------------------------------------------------------------

## A WeaponData has NO display name ([[character-two-inventories-weapon-name]]) — the human label lives on the
## backpack Item. For a hub-side readout the resource file stem is the honest handle; FISTS is named for what it is.
static func _weapon_name(w: WeaponData) -> String:
	if w == null:
		return "none"
	if w == Player.FISTS:
		return "fists"
	if w.resource_path != "":
		return w.resource_path.get_file().get_basename()
	if w.resource_name != "":
		return w.resource_name
	return "(unnamed WeaponData — a per-instance clone)"


static func _clip_line(p: Player, ws: Weapon, ammo: Ammo) -> String:
	var w: WeaponData = ammo.current_weapon
	if w == null:
		return "clip: no current weapon on the Ammo node"
	var reserve := p.inventory.ammo_count(w.caliber) if p.inventory != null else 0
	return "clip %d / %d (%s)   reserve %d clips%s   has_reload_supply %s%s   busy %s" % [
		ammo.current_ammo, w.max_ammo, _weapon_name(w), reserve, ("" if w.caliber == &"" else " of " + String(w.caliber)),
		_onoff(ammo.has_reload_supply()), ("   weapon flag is_infinite_ammo" if w.is_infinite_ammo else ""), _onoff(ws.is_busy())]


## The player's PerkManager child WITHOUT creating one — null when none exists yet (the read-only twin of
## GameState._perk_manager_of). Every listing command uses this so printing `stats` or `perks` never mutates the
## scene tree as a side effect.
static func _find_perk_manager(p: Player) -> PerkManager:
	if p == null:
		return null
	for c in p.get_children():
		if is_instance_valid(c) and c is PerkManager:  # ⭐is_instance_valid FIRST — `is` crashes on a freed instance
			return c as PerkManager
	return null


## Find-or-CREATE the player's PerkManager child, mirroring Player._perk_manager (player.gd:1366) and the three
## other hand-rolled copies (LevelUp / RespecStation / PerkStation). ⭐PerkManager.host is set in its _ready from
## get_parent(), so the node MUST be add_child'd: a manager created but never parented has a null host and
## unlock_perk silently skips every stat bonus and ability grant.
static func _perk_manager(p: Player) -> PerkManager:
	var found := _find_perk_manager(p)
	if found != null:
		return found
	var pm := PerkManager.new()
	pm.name = &"Perks"
	p.add_child(pm)
	return pm


static func _missing_prereqs(pm: PerkManager, perk: Perk) -> PackedStringArray:
	var out := PackedStringArray()
	for req in perk.requires_perks:
		if not pm.has_perk(req):
			out.append(String(req))
	return out


static var _noclip_script = null  ## the loaded DebugNoclip GDScript, resolved once (see NOCLIP_SCRIPT_PATH)


## The DebugNoclip drop-in under `parent`, created on first use. Matched by SCRIPT rather than by `is DebugNoclip`:
## the class_name may not be in the editor's global cache yet, and a name-only match would adopt any stray node.
## `parent` is tree.current_scene — the caller's canonical mount (see _noclip). Direct children only: a deeper
## walk would find a hand-dropped node inside the LEVEL subtree, which dies on the next warp and is exactly the
## mount this helper exists to avoid.
static func _find_or_make_noclip(parent: Node) -> Node:
	if _noclip_script == null:
		if not ResourceLoader.exists(NOCLIP_SCRIPT_PATH):
			return null
		_noclip_script = load(NOCLIP_SCRIPT_PATH)
	if _noclip_script == null:
		return null
	for c in parent.get_children():
		if is_instance_valid(c) and c.get_script() == _noclip_script:
			return c
	var node = _noclip_script.new()
	if node == null:
		return null
	node.name = &"DebugNoclip"
	parent.add_child(node)
	return node


## The find-only twin of _find_or_make_noclip, for READ-ONLY commands (`me`): never creates the drop-in, never
## mutates the tree. Null when the script is not on disk, was never loaded, or no node exists under `parent`.
static func _find_noclip(parent: Node) -> Node:
	if parent == null:
		return null
	if _noclip_script == null and ResourceLoader.exists(NOCLIP_SCRIPT_PATH):
		_noclip_script = load(NOCLIP_SCRIPT_PATH)
	if _noclip_script == null:
		return null
	for c in parent.get_children():
		if is_instance_valid(c) and c.get_script() == _noclip_script:
			return c
	return null


static func _disposition_word(kind: int) -> String:
	if kind == DispositionReg.Kind.HOSTILE:
		return DISPOSITION_HOSTILE
	if kind == DispositionReg.Kind.NEUTRAL:
		return DISPOSITION_NEUTRAL
	if kind == DispositionReg.Kind.FRIENDLY:
		return DISPOSITION_FRIENDLY
	return "unknown"


static func _as_strings(values: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for v in values:
		out.append(String(v))
	return out


## Money through the ONE money formatter, so a console readout reads like every other balance in the game.
static func _money_text(amount: float) -> String:
	return ZorkmidsReg.money_text(amount)


## A trimmed number: "4", "4.5", "0.75" — never a noisy "4.00". The `contains(".")` guard is load-bearing;
## rstrip("0") on a bare "100" would print "1".
static func _num(value: float, decimals: int = 2) -> String:
	var s := String.num(value, decimals)
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return s


static func _vec(v: Vector3) -> String:
	return "(%s, %s, %s)" % [_num(v.x), _num(v.y), _num(v.z)]
