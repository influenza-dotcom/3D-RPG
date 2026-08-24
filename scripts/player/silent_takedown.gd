class_name SilentTakedown
extends Node


## Slice 6b — the silent-takedown VERB. HOLD the Takedown key (default Q) while looking at an UNAWARE NPC from a
## short rear arc to instantly + QUIETLY kill it.
##
## GATED BY AN ABILITY: this verb is an unlockable mechanic — the player installs the Takedown Chip
## (resources/items/chip_takedown.tres) at a ChipInstaller, granting the SilentTakedownAbility gate node
## (scripts/components/abilities/silent_takedown.gd). This component is built unconditionally by Player._ready but
## _can_run() short-circuits until host.has_mechanic(&"silent_takedown") — so a fresh game (zero abilities) can't
## take anyone down until the chip is fitted. It's the same gate idiom AirDash uses.
##
## Reuses the shipped backstab geometry (DamageApplier.is_behind)
## and the off-guard gate (NPC.is_off_guard()), routes the kill through Character.take_damage CREDITED to the
## player (so XP / bounty / kill-quest all land), and flips NPC.mark_silent_takedown() FIRST so _on_died suppresses
## the witness bark — the Slice 5 body-discovery corpse marker becomes the DELAYED cost instead (silent now, found
## later). The takedown key is its OWN action, never overloaded onto Interact (which already pickpockets).
##
## Designer surface: GameSettings.takedown (SilentTakedownSettings.tres) — enabled / hold_time / min_hold_time /
## max_range / behind_arc_degrees / require_behind / require_crouch / takedown_sfx / takedown_sfx_volume_db. Built by
## Player._ready (.new() + host) and runs its own _physics_process with the same dialogue/menu guards the player's
## polled input uses.
##
## Two feel touches ride on the hold: (1) the wind-up SFX (the hydraulic press) plays WHILE the key is down over an
## eligible target and is cut the instant you release OR the kill commits — see _set_pressing. (2) the hold length
## SCALES with the attacker's LARCENY stat (CharacterStats.takedown_time_mult): a stealthier operator kills quicker,
## floored at min_hold_time so it's never a zero-length instant kill — see _effective_hold.

var host: Player = null  ## the owning Player, set right after .new()

var _hold_t: float = 0.0   ## seconds the Takedown key has been held over the current eligible target
var _eligible: NPC = null  ## the NPC currently under the crosshair AND eligible (null = nothing to take down)
var _press_player: AudioStreamPlayer = null  ## looping wind-up SFX (the press); started while charging, cut on release/commit


## Build the wind-up SFX player once, in-tree. A bare .new() unit stub never enters the tree, so _ready doesn't run
## there and this is skipped (mirrors Slide._build_slide_sfx) — the pure eligibility tests stay node-free.
func _ready() -> void:
	_press_player = AudioStreamPlayer.new()
	_press_player.bus = &"sfx"  # respect the SFX volume slider (a bare player lands on Master and ignores it)
	# Loop for the whole hold: reconnect finished -> play so a clip SHORTER than the wind-up sustains instead of
	# falling silent. stop() (on release/commit) does NOT emit finished, so cutting the press never re-triggers it.
	_press_player.finished.connect(_press_player.play)
	add_child(_press_player)


func _physics_process(delta: float) -> void:
	if not _can_run():
		_reset()
		return
	var s: SilentTakedownSettings = GameSettings.takedown
	if s == null or not s.enabled:
		_reset()
		return
	var npc := _aimed_eligible_npc(s)
	if npc == null:
		_reset()
		return
	_eligible = npc
	var hold := _effective_hold(s)
	# Hold-to-confirm: accumulate + sound the wind-up press while the key is down, fire once full, cut on release.
	if InputManager.is_action_pressed(InputManager.action_takedown):
		_hold_t += delta
		_set_pressing(true, s)
		if _hold_t >= hold:
			_execute(npc)  # -> _reset() cuts the press SFX, so it stops the instant the kill commits
			return
	else:
		_hold_t = 0.0
		_set_pressing(false)  # released before the press finished -> cut it
	_cue(npc, hold)


## The larceny-scaled wind-up: the authored base hold_time * the attacker's larceny multiplier
## (CharacterStats.takedown_time_mult — higher larceny, quicker press), floored at min_hold_time so a maxed-larceny
## build still gets a brief press, never a zero-length instant kill. Duck-typed on stats_or_default, so an odd host
## without a stat sheet just takes the base hold.
func _effective_hold(s: SilentTakedownSettings) -> float:
	var mult := 1.0
	if host != null and host.has_method(&"stats_or_default"):
		var cs: CharacterStats = host.stats_or_default()
		if cs != null:
			# Fold the LIVE larceny status modifier (timed/held buffs), like the pickpocket + Stats-screen seams do —
			# otherwise a larceny buff speeds up the displayed takedown but never the actual one (a broken contract).
			var larceny_bonus := 0.0
			if host.has_method(&"status_stat_modifier"):
				larceny_bonus = host.status_stat_modifier(&"larceny")
			mult = cs.takedown_time_mult(larceny_bonus)
	return maxf(s.min_hold_time, s.hold_time * mult)


## Start (idempotent) or stop the looping wind-up SFX. `on` true begins the press the frame the hold starts and is a
## no-op every frame after (guarded on `playing` so we don't restart-to-frame-0 each tick); false cuts it. Reads the
## clip + volume live from settings so a designer swapping SilentTakedownSettings.takedown_sfx is honoured. Off-tree
## (unit stub) _press_player is null -> a safe no-op.
func _set_pressing(on: bool, s: SilentTakedownSettings = null) -> void:
	if _press_player == null:
		return
	if on:
		if s == null or s.takedown_sfx == null:
			return
		if not _press_player.playing:
			_press_player.stream = s.takedown_sfx
			_press_player.volume_db = s.takedown_sfx_volume_db
			# Varied per PRESS, not per frame — the `playing` guard above is what keeps this one roll per wind-up.
			AudioManager.play_varied(_press_player)
	elif _press_player.playing:
		_press_player.stop()


## Shared with the player's own polled input: never mid-dialogue or with a modal/menu up, and only while in the
## live tree with a valid host (a bare .new() unit stub has no host -> safely inert).
func _can_run() -> bool:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return false
	# The takedown VERB is an UNLOCKABLE ability now — you install the Takedown Chip (resources/items/chip_takedown.tres)
	# at a ChipInstaller, which adds a SilentTakedownAbility gate node under the Player. This behaviour component is
	# always built (Player._ready) but stays INERT until that mechanic is granted, the same gate idiom AirDash uses
	# (its launch code lives in attack.gd, gated by has_mechanic). Fresh game = no chip = no silent kill.
	if not host.has_mechanic(&"silent_takedown"):
		return false
	if host.get(&"_dying"):
		return false  # no takedowns during the player's death cinematic — a dead player must not score the kill / XP / a post-mortem autosave
	if DialogueManager.is_active() or InputManager.gameplay_suppressed():
		return false
	# The LEAN has CLAIMED the Takedown key for the current hold — you pressed it with nothing to take down, so
	# it became a peek (see the contextual-key rule in scripts/player/lean.gd). Stand down until the key is
	# released. Without this a lean that swept an off-guard NPC into the crosshair mid-hold would quietly start
	# charging a silent takedown underneath the peek — a kill the player never asked for.
	if host.lean_owns_action(InputManager.action_takedown):
		return false
	return true


## The contextual verb this driver is holding a target for, as an ACTION name (&"" = nothing eligible). Duck-typed
## by Player.pending_verb_actions(); the LEAN asks it before claiming a shared key, so a Q press with an unaware
## NPC in the crosshair goes to the takedown and one with nothing there becomes a peek. Reads the target resolved
## by the last _physics_process pass — Lean runs at process_physics_priority 1 precisely so that pass is THIS
## frame's, not the previous one.
func pending_verb_action() -> StringName:
	return InputManager.action_takedown if (_eligible != null and is_instance_valid(_eligible)) else &""

## The NPC under the crosshair eligible for a takedown, or null. Casts the player's aim ray (copying
## Player._check_aim_remark), then applies the pure eligibility gate so the decision is unit-testable.
func _aimed_eligible_npc(s: SilentTakedownSettings) -> NPC:
	var from: Vector3 = host.get_aim_origin()
	var to: Vector3 = from + host.get_aim_direction() * s.max_range
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [host.get_rid()]
	# A prop you're carrying floats in front of the camera; mask out the held-prop layer so it can't block the
	# aim ray from reaching an NPC behind it (a raycast ignores the carry collision exception the player gets).
	params.collision_mask = 0xFFFFFFFF & ~TalkHelpers.held_prop_collision_layer()
	var hit := host.get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return null
	var npc := hit.get("collider") as NPC
	if npc == null:
		return null
	var dist: float = from.distance_to(hit["position"])
	# REUSE the shipped backstab arc (basis.z = the model's facing, the same convention damage_trace/Perception use).
	var behind := DamageApplier.is_behind(host.global_position, npc.global_position, npc.global_transform.basis.z, s.behind_arc_degrees)
	if eligible(npc.is_off_guard(), host.is_crouching(), s.require_crouch, behind, s.require_behind, dist, s.max_range):
		return npc
	return null


## Pure eligibility predicate (no tree / nodes) — unit-tested. `behind` is precomputed via DamageApplier.is_behind.
## A takedown needs an off-guard (not-yet-ALERTED) target, optionally crouched, optionally within the rear arc,
## within reach.
static func eligible(off_guard: bool, crouching: bool, require_crouch: bool, behind: bool, require_behind: bool, dist: float, max_range: float) -> bool:
	if not off_guard:
		return false
	if require_crouch and not crouching:
		return false
	if require_behind and not behind:
		return false
	return dist <= max_range


## Commit the kill: mark it silent (NPC._on_died then skips the witness bark), then apply lethal damage CREDITED to
## the player so XP / bounty / kill-quest land. take_damage's _dead latch makes a double-fire a no-op; a large
## sentinel (not raw hp) outruns any armor/DR applied before the hp subtract.
func _execute(npc: NPC) -> void:
	if is_instance_valid(npc):
		if npc.has_method(&"mark_silent_takedown"):
			npc.mark_silent_takedown()
		npc.take_damage(1.0e9, false, host)
		if host.has_method(&"notify_toast"):
			host.notify_toast(PlayerText.TOAST_TAKEDOWN, Color(0.72, 0.86, 0.92))
	_reset()


## Drive the HUD prompt + hold fill via the Player facade (forwards to PlayerHud.set_takedown_cue). `hold` is the
## stealth-scaled wind-up (from _effective_hold), so the fill reaches full exactly when the kill commits.
func _cue(npc: NPC, hold: float) -> void:
	if not host.has_method(&"set_takedown_cue"):
		return
	var nm := ""
	var raw: Variant = npc.get(&"display_name")
	if raw is String:
		nm = GameState.public_name(raw)  # the takedown prompt names a Stranger until they've introduced themselves
	var key := InputManager.get_action_binding(InputManager.action_takedown)
	var text := PlayerText.takedown_prompt(key, nm)
	host.set_takedown_cue(true, text, clampf(_hold_t / maxf(0.01, hold), 0.0, 1.0))


func _reset() -> void:
	_hold_t = 0.0
	_eligible = null
	_set_pressing(false)  # any exit from an eligible hold (release, off-target, dialogue, death, commit) cuts the press
	if host != null and is_instance_valid(host) and host.has_method(&"set_takedown_cue"):
		host.set_takedown_cue(false, "", 0.0)
