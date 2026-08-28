extends Node

## @system Minimap
## @seam The IN-WORLD half of player waypoints: TAP the Mark Waypoint key (InputManager.action_mark_waypoint,
## default X) to pin the spot you are LOOKING AT — or, when the ray hits nothing in reach, the spot you are
## STANDING ON — and to make that pin the one you are NAVIGATING to. Built by Player._ready (.new() + host)
## beside the takedown / pet / claim verbs and running its own _physics_process with the same dialogue / menu /
## death guards.
## @seam The pin is stored through GameState.add_waypoint into the per-level ledger — the same records the Map
## tab authors and the same ones the minimap box paints — and is then handed to GameState.set_tracked_waypoint,
## which is what puts a pip on the top-centre heading tape (HudCompass) and a ring on the HUD corner box within
## the frame. Nothing is spawned into the world; a waypoint has no presence there (see Minimap._paint_waypoints).
## @risk THE RAY MUST STAY IN _physics_process. direct_space_state returns EMPTY, silently, off the physics
## frame — the trap the minimap's own "never draw a sight cone" @risk records — so a _process or _input version
## of this would mark your feet every single time and pass every test doing it.
## @risk NO class_name — Player preloads it BY PATH. A new class_name is absent from the editor's global class
## cache until a rescan, and until then every file that NAMES the type fails to parse and cascades.
## @test res://tests/test_waypoint_marker.gd
##
## ONE PRESS, ONE NAV POINT — AND NO TEXT BOX. This verb used to open NameEntryDialog (the real-time box that
## names a claimed pet) and ask "what do I call this?" before anything was stored. Mid-fight, aimed across a
## plaza, that was the wrong question: the player was answering a prompt instead of walking somewhere. X is the
## "set nav point" gesture now — it pins the place, names it from WAYPOINT_DEFAULT_NAME, TRACKS it, and toasts
## the name it used, all inside the press, so the compass pip is there before the key is back up. Name, note,
## icon and colour are re-authored later on the Map tab, which is where a player is already reading rather than
## moving — and until they are, "Pin 3" on the tape and "Pin 3" in the toast are the same pin.
##
## A TAP, NOT A HOLD — the ClaimInteraction argument, minus the typing half that no longer applies: a hold is
## the gesture for a continuous verb (lean, aim, carry), and this is a stamp. Holding it would only repeat.

## How far the aim ray reaches, in metres. Generous — this marks PLACES, not objects, so pointing at a
## building across a plaza should work — but finite, because a ray that never misses would make the
## "mark where I stand" fallback unreachable.
const RAY_REACH: float = 60.0

## Pulled back along the ray from whatever the ray hit, in metres, so the pin sits just OFF the surface rather
## than inside it. A pin buried in a wall is on the wrong side of it for every distance test the map does.
const SURFACE_OFFSET: float = 0.25

## The record's rules — the clamps and the icon vocabulary. Preloaded BY PATH, untyped, for the @risk above.
const WAYPOINT_BOOK := preload("res://scripts/world/waypoint_book.gd")

var host: Node = null  ## the owning Player, set right after .new(); null = a bare unit stub, safely inert


func _physics_process(_delta: float) -> void:
	if not _can_run():
		return
	if not InputManager.is_action_just_pressed(InputManager.action_mark_waypoint):
		return
	_begin_mark()


## Shared gate with the player's other polled verbs: in the live tree with a valid host, not mid-death, not
## mid-dialogue, and no modal/menu up — the Map tab is a menu, so the in-world key cannot fire underneath the
## screen that edits the same ledger. A bare .new() unit stub has no host and is therefore inert.
func _can_run() -> bool:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return false
	# The player's physics being switched OFF is a suspension this verb must honour: the F1 debug menu is
	# deliberately outside gameplay_suppressed() and stops the player by hand through
	# DebugActionsPlayer.suspend_player — which freezes the Player node but not its self-ticking verb
	# children. Without this, typing a letter bound to this key into that menu's search field fires the verb
	# underneath it. (The takedown/pet/claim siblings carry the same guard in their own _can_run.)
	if not host.is_physics_processing():
		return false
	if host.get(&"_dying"):
		return false
	if DialogueManager.is_active() or InputManager.gameplay_suppressed():
		return false
	return true


## Resolve the spot, refuse early if this level is full, then pin it — instantly, under its default name.
##
## THE CAP IS CHECKED BEFORE THE PIN IS COMPOSED, so a player at the limit gets the refusal that names the cap
## rather than the generic one _commit falls back to — the Map tab's placement path makes the same call for the
## same reason. Both refusals are toasts rather than silence: a pin that does not appear reads as a broken map.
##
## The name is composed HERE and not inside _commit because the ordinal counts the pins that exist NOW: the
## commit's own add_waypoint is what makes it stale, so composing it after would number every pin off by one.
func _begin_mark() -> void:
	var level: String = GameState.current_level_path
	if level.is_empty():
		# A code-built LevelData records no path, so there is nowhere to file a pin. Its OWN copy — telling
		# this player "the map is full" over an empty map would be a lie.
		UI.toast(PlayerText.WAYPOINT_NO_LEVEL)
		return
	if GameState.waypoints_full(level):
		UI.toast(TextFormat.subst(PlayerText.WAYPOINT_FULL, {"max": WAYPOINT_BOOK.MAX_PER_LEVEL}))
		return
	var aimed := aim_point()
	var pos: Vector3 = aimed if aimed != Vector3.INF else stand_point()
	# ⭐[PH]-STRIPPED: this string is SAVED as player data (it is the pin's name until they rename it on the
	# Map tab, and most never will), and the placeholder marker must never outlive the session that painted
	# it — the dog_pickup precedent for composed names. The TOAST keeps its own marker; only the data loses it.
	var pin_name := PlayerText.strip_prefix(TextFormat.subst(PlayerText.WAYPOINT_DEFAULT_NAME,
			{"n": GameState.waypoints_for(level).size() + 1}))
	# The LEVEL travels WITH the position into the commit rather than being re-read there. The three ledger
	# calls behind this press (the cap check above, the add, and the track) must all name ONE level, and
	# `GameState.current_level_path` is a live field a synchronous waypoints_changed handler could see move
	# between them. A pin belongs to the level where the ray landed; the per-level ledger stores non-current
	# levels natively, so there is nothing to re-derive.
	_commit(level, pos, pin_name)


## Store the pin, make it THE tracked one, and say which pin that was.
##
## TRACKING IS THE POINT OF THE KEY, not a bonus on top of it: X answers "I am going there", and a pin with no
## pip on the tape would answer "I noted it" instead. It moves the flag off whatever pin held it (that sweep is
## GameState's — one tracked pin per profile, across every level) rather than adding a second marker.
##
## The index comes back from add_waypoint and is re-validated by set_tracked_waypoint, so the one hostile case —
## a waypoints_changed listener shrinking the ledger inside the add's SYNCHRONOUS emit — leaves the new pin
## untracked instead of tracking a stranger that happens to have inherited its slot.
func _commit(level: String, pos: Vector3, pin_name: String) -> void:
	var index := GameState.add_waypoint(level, pos, pin_name, "", 0, 0)
	if index < 0:
		# Reachable even past the cap check above (a swap, or a listener filling the level mid-press), so it
		# keeps its own refusal rather than trusting the earlier gate to be the only door.
		UI.toast(TextFormat.subst(PlayerText.WAYPOINT_FULL, {"max": WAYPOINT_BOOK.MAX_PER_LEVEL}))
		return
	GameState.set_tracked_waypoint(level, index, true)
	# The name is substituted as a VALUE — it is player-facing DATA, never part of a msgid — and it is the only
	# thing telling the player which pin the pip that just appeared on the tape belongs to.
	UI.toast(TextFormat.subst(PlayerText.WAYPOINT_MARKED, {"name": pin_name}))


## The point the player is LOOKING AT, or Vector3.INF for "the ray hit nothing in reach" (the sentinel this
## project already spends for that answer — see Minimap._marker_point).
##
## Collides with BODIES and AREAS: an area-only decorative volume is still a place, and marking it is
## harmless. It masks out the talk layer and the held-prop layer for the reason ClaimInteraction's ray does —
## an NPC's conversation hitbox, or a crate you are carrying in front of your face, must not shadow the wall
## behind it and turn "mark that doorway" into "mark this crate".
## ⭐Every read off `host` is EXPLICITLY typed, never `:=`. `host` is a plain Node (so a bare unit stub can
## stand in for a Player), which makes every duck-typed call a Variant — and GDScript refuses to infer a type
## from one, so `var world := host.get_world_3d()` is a parse error rather than a runtime surprise. The house
## rule, and the reason the casts below look heavier than they need to.
func aim_point() -> Vector3:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return Vector3.INF
	var body := host as CollisionObject3D
	if body == null:
		return Vector3.INF  # not a physics body: nothing to cast from, and nothing to exclude
	var world: World3D = body.get_world_3d()
	if world == null:
		return Vector3.INF
	var from: Vector3 = host.get_aim_origin()
	var dir: Vector3 = host.get_aim_direction()
	var params := PhysicsRayQueryParameters3D.create(from, from + dir * RAY_REACH)
	params.exclude = [body.get_rid()]
	params.collide_with_areas = true
	params.collision_mask = 0xFFFFFFFF & ~TalkHelpers.TALK_LAYER & ~TalkHelpers.held_prop_collision_layer()
	var hit: Dictionary = world.direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return Vector3.INF
	# Backed off along the ray so the pin sits just clear of the surface it landed on, never inside it.
	return (hit["position"] as Vector3) - dir * SURFACE_OFFSET


## Where the player is standing — the fallback when the ray hits nothing (aimed at the sky, or across a gap
## wider than RAY_REACH). Their own origin, not a ground probe: the player IS on the floor, so their transform
## is already the answer, and a second raycast here would be a second thing to get wrong.
func stand_point() -> Vector3:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return Vector3.ZERO
	return (host as Node3D).global_position
