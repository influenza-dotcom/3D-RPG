extends GutTest

## The NPC "go home" LEASH (scripts/npc/npc_home_return.gd): NPCs return to the spot they were authored at when the
## PLAYER DIES, or after they've been off-screen for a while — the dog/companion hidden-blink trick aimed at the
## spawn point instead of at the player.
##
## What's pinned here is the PURE + WIRING surface: the view-cone geometry that decides "would this pop on screen"
## (static, so it runs off-tree), the off-tree/no-host inertness that keeps a bare `.new()` safe under GUT, the
## reuse reset, and the wiring seams that are silent when broken (NPC building the component by SCRIPT PATH,
## Player.die() emitting GameState.player_died, the NpcAiSettings dials the auto-build seeds from). The actual
## teleport + the perception/idle handover are in-tree behaviour -> manual playtest, per the project's test rules
## (never run an NPC's _ready in a unit test).

const HOME_RETURN := "res://scripts/npc/npc_home_return.gd"

var _hr


func before_each() -> void:
	_hr = load(HOME_RETURN).new()  # bare .new(): _init only, no _ready -> no autoload signal connection


func after_each() -> void:
	if _hr != null:
		_hr.free()
		_hr = null


# --- The on-screen guard (pure geometry) ------------------------------------------------------------------------

func test_view_cone_sees_straight_ahead_and_not_behind() -> void:
	# Camera at origin looking down -Z (Godot's camera forward). The rule is a dot vs threshold, identical to
	# CompanionFollow._in_view_cone — it is what forbids a blink that would pop on screen.
	var fwd := Vector3(0, 0, -1)
	assert_true(_hr.in_view_cone(Vector3.ZERO, fwd, Vector3(0, 0, -5), 0.35),
		"a point straight ahead of the camera is IN the view cone (blink forbidden)")
	assert_false(_hr.in_view_cone(Vector3.ZERO, fwd, Vector3(0, 0, 5), 0.35),
		"a point directly behind the camera is OUT of the view cone (blink allowed)")
	assert_false(_hr.in_view_cone(Vector3.ZERO, fwd, Vector3(5, 0, 0), 0.35),
		"a point 90 degrees off to the side is OUT of the cone (dot 0 < 0.35)")

func test_view_cone_ignores_height() -> void:
	# The cone is HORIZONTAL only (to_point.y is zeroed): an NPC on a roof directly ahead is still "on screen",
	# so the guard never blinks something the player is looking up at.
	var fwd := Vector3(0, 0, -1)
	assert_true(_hr.in_view_cone(Vector3.ZERO, fwd, Vector3(0, 30, -5), 0.35),
		"height is ignored — a point ahead but far above is still in the cone")

func test_view_cone_treats_a_point_on_the_camera_as_visible() -> void:
	# Degenerate case: no direction to test, so it must fail SAFE (visible => refuse the blink), never divide by ~0.
	assert_true(_hr.in_view_cone(Vector3.ZERO, Vector3(0, 0, -1), Vector3.ZERO, 0.35),
		"a point on top of the camera reads as visible (fail safe: refuse to move it)")

func test_view_cone_threshold_is_honoured() -> void:
	# A tighter threshold shrinks the "on screen" cone, so the same off-axis point flips to blink-allowed.
	var fwd := Vector3(0, 0, -1)
	var diagonal := Vector3(5, 0, -5)  # dot ~= 0.707
	assert_true(_hr.in_view_cone(Vector3.ZERO, fwd, diagonal, 0.35), "45 degrees off-axis is inside a 0.35 cone")
	assert_false(_hr.in_view_cone(Vector3.ZERO, fwd, diagonal, 0.9), "the same point is outside a 0.9 cone")


# --- Off-tree / no-host inertness -------------------------------------------------------------------------------

func test_host_defaults_null_and_the_component_ships_enabled() -> void:
	assert_null(_hr.host, "host is bound by NPC._build_components, never at construction")
	assert_true(_hr.enabled, "the leash ships ON (the auto-built instance is re-seeded from GameSettings.npc_ai)")
	assert_true(_hr.return_on_player_death, "player death sends NPCs home by default")
	assert_true(_hr.return_when_off_screen, "the off-screen leash is on by default")
	assert_true(_hr.blink_home, "the default return is the hidden blink, not only the walk-back")

func test_return_home_is_a_no_op_without_a_host() -> void:
	# GUT builds these bare; every entry point must be inert rather than null-deref.
	assert_false(_hr.return_home(true), "no host -> nothing to send home, even when the view guard is skipped")
	assert_false(_hr.return_home(false), "no host -> false")

func test_home_position_without_a_host_is_the_origin() -> void:
	assert_eq(_hr.home_position(), Vector3.ZERO, "no host and no marker -> a harmless origin, not a crash")
	assert_eq(_hr.home_yaw(), 0.0, "no host and no marker -> yaw 0")

func test_disabled_component_refuses_even_with_a_host() -> void:
	_hr.enabled = false
	assert_false(_hr.return_home(true), "enabled = false makes the component completely inert")


# --- The aggro rule (an enemy must never evaporate because you broke line of sight) -----------------------------

func test_an_engaged_npc_is_never_teleported_by_the_off_screen_leash() -> void:
	# THE rule: locked on, hunting, or merely holding the player as a not-yet-noticed proximity target — the
	# off-screen leash may stand that NPC down and walk it back, but it must not pop. Enforced in _may_blink() as a
	# HARD refusal, deliberately NOT behind off_screen_requires_calm (that knob only paces the clock), so opening
	# the leash up for a hard-leash level can't reintroduce a vanishing enemy.
	var src := FileAccess.get_file_as_string("res://scripts/npc/npc_home_return.gd")
	assert_true(src.contains("func _may_blink()"), "the teleport has its own gate, separate from the view guard")
	# GUARD THE OFFSETS BEFORE COMPARING THEM. find() answers -1 for a renamed needle, and it only ever reports the
	# FIRST occurrence — so a vanished or duplicated needle would have the ordering assert below measure something
	# nobody meant to pin, silently, instead of failing.
	var gate := src.find("func _may_blink()")
	assert_gt(gate, -1, "func _may_blink() no longer present — the pin is stale")
	assert_eq(src.rfind("func _may_blink()"), gate,
		"func _may_blink() must appear exactly ONCE, or the offset compared below is not the gate being pinned")
	var refusal := src.find("if _engaged():", gate)
	assert_gt(refusal, -1, "if _engaged(): no longer present after _may_blink() — the pin is stale")
	assert_true(gate > -1 and refusal > gate and refusal - gate < 200,
		"_may_blink() opens by refusing outright while the NPC has aggro")
	assert_true(src.contains("blink_home and (ignore_view or _may_blink())"),
		"return_home() consults it, and only the player-death reset (ignore_view, black screen) overrides it")
	assert_true(src.contains("_stand_down()"),
		"a refused blink still stands the NPC down so the idle floor walks it home")

func test_engaged_counts_a_proximity_target_not_just_alerted_perception() -> void:
	# NpcTargeting acquires by pure proximity with NO line-of-sight test, so a hostile holds the player as _target
	# before perception has noticed them. That window is still "wants to attack you" and must block the blink —
	# checking perception alone would let a hostile standing right next to you blink away.
	var src := FileAccess.get_file_as_string("res://scripts/npc/npc_home_return.gd")
	assert_true(src.contains("func _engaged()"), "the aggro predicate exists")
	assert_true(src.contains("Perception.State.UNAWARE"), "it checks perception state...")
	assert_true(src.contains("var target: Variant = host.get(&\"_target\")"), "...AND a live proximity target")

func test_blink_needs_distance_from_the_player() -> void:
	# Out of the view cone is not the same as unnoticeable: a body vanishing a few metres behind the player is felt,
	# and they're one turn from looking at where it was. Below min_blink_distance it walks instead.
	assert_eq(_hr.min_blink_distance, 8.0, "the blink keeps its distance by default")
	var src := FileAccess.get_file_as_string("res://scripts/npc/npc_home_return.gd")
	assert_true(src.contains("_flat_distance_to_player() >= maxf(0.0, min_blink_distance)"),
		"_may_blink() gates on the distance to the player")
	assert_true(src.contains("return INF"),
		"no player in the tree -> INF, so a headless/test scene degrades to 'nobody could notice', not 'never blink'")

func test_reset_for_reuse_clears_the_timers() -> void:
	# NpcPool reuses the body without rebuilding children, so a stale off-screen clock / pending death return would
	# leak into the next life and yank a freshly-spawned NPC back to the previous life's post.
	_hr._off_screen_t = 99.0
	_hr._death_due_msec = 5000
	_hr._scan_t = 3.0
	_hr.reset_for_reuse()
	assert_eq(_hr._off_screen_t, 0.0, "the off-screen clock rewinds")
	assert_eq(_hr._death_due_msec, -1, "a pending player-death return is dropped (-1 = none armed)")
	assert_eq(_hr._scan_t, 0.0, "the scan throttle rewinds")

func test_player_death_handler_is_inert_when_both_triggers_are_off() -> void:
	# The cue now drives TWO independent halves of the encounter reset (go home + full heal); it must arm when
	# EITHER is wanted, and only stay dark when neither is.
	_hr.return_on_player_death = false
	_hr.heal_on_player_death = false
	_hr._on_player_died()
	assert_eq(_hr._death_due_msec, -1, "with both triggers off, the death cue arms nothing")

## --- The full heal (the other half of the player-death reset) --------------------------------------------------

func test_the_heal_ships_on_and_is_independent_of_the_return() -> void:
	assert_true(_hr.heal_on_player_death,
		"survivors are topped back up on player death by default — otherwise a fight you lost gets easier every "
		+ "time you die at it, and the damage never heals for the rest of the session")
	var src := FileAccess.get_file_as_string("res://scripts/npc/npc_home_return.gd")
	assert_true(src.contains("if heal_on_player_death:\n\t\t\trestore_full_health()"),
		"the armed death beat heals BEFORE it decides whether to move the body")
	assert_true(src.contains("if not return_on_player_death:"),
		"heal-only is a valid configuration: an NPC can be healed without being sent home")

func test_restore_full_health_is_inert_without_a_host() -> void:
	assert_false(_hr.restore_full_health(), "no host -> nothing to heal, not a null-deref")

func test_restore_full_health_tops_a_wounded_host_up() -> void:
	# Off-tree Character (never _ready'd, per the project's test rules) — the heal seam is pure enough to run bare.
	var host = load("res://scripts/player/character.gd").new()
	host.max_hp = 40.0
	host.hp = 7.0
	_hr.host = host
	assert_true(_hr.restore_full_health(), "a wounded survivor heals")
	assert_eq(host.hp, 40.0, "back to FULL hp, clamped by Character.heal")
	assert_false(_hr.restore_full_health(), "an already-full NPC reports no work done")
	host.free()

func test_restore_full_health_never_revives_the_dead() -> void:
	# The reset restores the survivors of a fight; it must never undo one. An NPC you killed stays killed.
	var host = load("res://scripts/player/character.gd").new()
	host.max_hp = 40.0
	host.hp = 0.0
	host._dead = true
	_hr.host = host
	assert_false(_hr.restore_full_health(), "a corpse is not healed")
	assert_eq(host.hp, 0.0, "and its hp is left at 0")
	host.free()

func test_restore_full_health_goes_through_the_heal_seam_not_a_raw_write() -> void:
	# Character.heal() is the one seam that clamps to max_hp and emits `damaged`; a raw `hp = max_hp` would leave
	# every listener bound to that signal desynced from the restore.
	var src := FileAccess.get_file_as_string("res://scripts/npc/npc_home_return.gd")
	assert_true(src.contains("host.call(&\"heal\", missing)"), "HP is restored through Character.heal (clamps + emits damaged)")
	assert_true(src.contains("host.call(&\"heal_limbs\")"),
		"limb damage is cleared too — otherwise the guard walks back to its post permanently limping")

func test_the_heal_is_not_gated_on_the_move_exemptions() -> void:
	# _eligible() exempts a companion / bodyguard / cutscene body from being MOVED. None of those is a reason to
	# leave it wounded, so the death handler is only aliveness-gated and return_home() re-checks _eligible itself.
	var src := FileAccess.get_file_as_string("res://scripts/npc/npc_home_return.gd")
	# ⭐GUARD BOTH ENDS OF THE SLICE. This is the assert_false pin that fails OPEN: a missing needle makes find()
	# return -1, the negative length makes substr() yield "", and `assert_false("".contains(...))` PASSES — so the
	# day someone renames _on_player_died this test would go on reporting green while checking nothing at all.
	var handler := src.find("func _on_player_died()")
	assert_gt(handler, -1, "func _on_player_died() no longer present — the pin is stale")
	var armed := src.find("_death_due_msec = Time.get_ticks_msec()", handler)
	assert_gt(armed, -1, "_death_due_msec = Time.get_ticks_msec() no longer present inside the handler — the pin is stale")
	var body := src.substr(handler, armed - handler)
	assert_false(body.contains("_eligible()"), "the death cue does NOT gate the heal on the move exemptions")
	assert_true(body.contains("bool(host.get(&\"_dead\"))"), "it gates on aliveness only")


func test_player_death_handler_needs_a_host() -> void:
	# The handler gates on a live, in-tree host — a bare component must not arm a reset it can never run.
	_hr._on_player_died()
	assert_eq(_hr._death_due_msec, -1, "no host -> no armed reset")

func test_the_death_deadline_is_wall_clock_not_scaled_delta() -> void:
	# The death cinematic runs at Engine.time_scale 0.3, so a delta-based countdown would stretch a 0.5 s delay to
	# ~1.7 real seconds and fire ON the respawn (screen fading back UP) instead of behind the fade. Pin the shape.
	var src := FileAccess.get_file_as_string("res://scripts/npc/npc_home_return.gd")
	assert_true(src.contains("Time.get_ticks_msec()"), "the armed death return uses a real-time deadline")
	assert_false(src.contains("_death_due_msec -= delta"), "it must NOT be a time-scaled delta countdown")


# --- Wiring seams (silent when broken) --------------------------------------------------------------------------

func test_gamestate_declares_the_player_death_cue() -> void:
	assert_true(GameState.has_signal(&"player_died"),
		"GameState.player_died is the one broadcast NPCs connect to (no Player spawn-order handshake)")

func test_the_death_cue_fires_on_the_black_frame_not_at_death() -> void:
	# TIMING IS THE CONTRACT here, and it's invisible to any off-tree assert: the cue must land on the death
	# cinematic's FULLY BLACK frame (where the "You were killed by X" card comes up), NOT in die(). Emitting at
	# death time — ~1.6 s earlier, while the vignette is still closing — lets the player WATCH every NPC teleport
	# away, which reads worse than not resetting at all. The cinematic is a long in-tree tween a unit test must not
	# run, so pin the wiring by source.
	var src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	assert_true(src.contains("func _on_death_screen_covered()"),
		"the cue has its own callback, fired from the death-sequence tween")
	assert_true(src.contains("GameState.player_died.emit()"),
		"Player broadcasts GameState.player_died so the world can reset behind the black")
	assert_true(src.contains("tw.tween_callback(_on_death_screen_covered)"),
		"the callback is wired into the death cinematic tween")
	# THREE OFFSETS THAT GET ORDERED, so each needs both guards: present (a renamed tween call answers -1 and the
	# ordering assert stops measuring the beat it names) and UNIQUE (find() reports only the first occurrence, so a
	# second tween_callback would let the pin pass on the wrong one while the real order regressed).
	var covered := src.find("tw.tween_callback(_on_death_screen_covered)")
	assert_gt(covered, -1, "tw.tween_callback(_on_death_screen_covered) no longer present — the pin is stale")
	assert_eq(src.rfind("tw.tween_callback(_on_death_screen_covered)"), covered,
		"the death cue must be wired into the tween exactly ONCE, or this ordering pin measures the wrong one")
	var phase_one := src.find("tw.tween_method(_death_step, 0.0, 1.0")
	assert_gt(phase_one, -1, "tw.tween_method(_death_step, 0.0, 1.0 no longer present — the pin is stale")
	assert_eq(src.rfind("tw.tween_method(_death_step, 0.0, 1.0"), phase_one,
		"the vignette close must be tweened exactly ONCE, or 'the cue runs after phase 1' is measured against the wrong step")
	var card := src.find("tw.tween_callback(_show_death_card)")
	assert_gt(card, -1, "tw.tween_callback(_show_death_card) no longer present — the pin is stale")
	assert_eq(src.rfind("tw.tween_callback(_show_death_card)"), card,
		"the death card must be tweened in exactly ONCE, or 'the cue runs before the card' is measured against the wrong one")
	assert_true(phase_one > -1 and covered > phase_one,
		"it runs AFTER phase 1 (the vignette close) — i.e. on full black, not while the world is still readable")
	assert_true(card > -1 and covered < card,
		"and BEFORE _show_death_card, which early-outs on a blank message — the cue must not depend on the card rendering")

func test_npc_exposes_the_stand_down_and_send_home_seams() -> void:
	var npc = load("res://scripts/npc/npc.gd").new()
	assert_true(npc.has_method("stand_down"),
		"NPC.stand_down() is the public 'break off this engagement' seam the leash calls")
	assert_true(npc.has_method("send_home"),
		"NPC.send_home() is the facade onto the NpcHomeReturn child (also the component's parent config-warning probe)")
	npc.free()

func test_stand_down_clears_the_engagement_off_tree() -> void:
	# A bare NPC has no perception / laser children, so stand_down must be null-safe — and it must NOT touch the
	# provoke latch: a guard you shot is still angry next time, it just went back to its post.
	var npc = load("res://scripts/npc/npc.gd").new()
	npc._provoked = true
	npc.stand_down()
	assert_null(npc._target, "the combat target is dropped")
	assert_null(npc._last_attacker, "the sticky attacker lock is dropped")
	assert_true(npc._provoked, "hostility is DELIBERATELY preserved — standing down is not forgiveness")
	npc.free()

func test_npc_builds_the_leash_by_script_path_not_by_bare_type() -> void:
	# npc.gd is a @tool root: naming a newly-added class_name at parse time can fail its parse in the live editor
	# (the new-classname reimport cascade), which is why CrippleCallout is built the same way.
	var src := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
	assert_true(src.contains("res://scripts/npc/npc_home_return.gd"),
		"NPC builds/matches the leash by script path")
	assert_false(src.contains("NpcHomeReturn.new()"),
		"NPC must NOT name the class at parse time — build it via load(path).new()")
	assert_true(src.contains("_home_return.host = self"),
		"the host is bound for BOTH the auto-built and the designer-dropped instance")
	assert_true(src.contains("_home_return.call(&\"reset_for_reuse\")"),
		"pool reuse resets the leash with the other stateful children")

func test_npc_ai_settings_expose_the_leash_dials() -> void:
	# The auto-built component seeds from these; a renamed field would fail at spawn, not here, so pin the names.
	var s := NpcAiSettings.new()
	for field in ["home_return", "home_return_on_player_death", "home_return_death_delay",
			"home_return_heal_on_player_death", "home_return_off_screen",
			"home_return_off_screen_delay", "home_return_requires_calm", "home_return_slack", "home_return_blink",
			"home_return_min_blink_distance"]:
		assert_true(field in s, "NpcAiSettings exposes %s (NPC._build_components seeds the leash from it)" % field)
	assert_true(s.home_return, "the leash defaults ON project-wide")
	s = null
