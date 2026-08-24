extends GutTest

## LEAN (scripts/player/lean.gd) — the Deus Ex / Cruelty Squad corner-peek, and the CONTEXTUAL-KEY rule that lets
## it share Q with the verb already living there (Takedown/Pet). E is the lean's ALONE — Interact moved to F.
##
## What these pin, and why each one is worth a test:
##  - The BINDING-SHARE seam (InputManager.actions_share_binding / same_binding). It is the whole arbitration:
##    "does my lean key also press the verb?". It reads the LIVE InputMap, so a defaults change (or a lean row
##    dropped from project.godot [input]) silently turns the SHARED side unconditional — Q would stop taking down.
##  - The CLAIM (Lean.owns_action). SilentTakedown and PetInteraction stand down on it; if it stopped matching
##    the shared action, a peek would charge a takedown underneath itself with no error anywhere.
##  - The POSE math (_apply) — offset off the AUTHORED rest X (not 0), and the roll SIGN, which must match the
##    strafe tilt CameraEffects already applies or the two conventions fight.
##  - The accessibility tie-in: "Camera Tilt" off must kill the ROLL and keep the positional peek.
##
## Off-tree throughout: Lean is a plain Node whose _ready() touches nothing but its own fields, so we call it by
## hand after wiring a stub head (Player._enter_tree does that injection in the real game). Nothing here runs a
## Player _ready(), per the house rule.

const LeanScript := preload("res://scripts/player/lean.gd")
const SETTINGS_PATH := "res://resources/tuning/PlayerLeanSettings.tres"


func _settings() -> PlayerLeanSettings:
	return load(SETTINGS_PATH) as PlayerLeanSettings


## A Lean with a stub head, wired + _ready()'d the way Player._enter_tree does it. `rest_x` stands in for the
## authored Head nudge in Player.tscn, which the component must treat as the rest position.
func _rig(rest_x: float = 0.0) -> Array:
	var head := Node3D.new()
	head.position = Vector3(rest_x, 1.6, 0.0)
	var lean: Lean = LeanScript.new()
	lean.head = head
	lean._ready()
	return [lean, head]


func _free_rig(rig: Array) -> void:
	(rig[0] as Node).free()
	(rig[1] as Node).free()


# --- the tuning resource -------------------------------------------------------------------------------------

func test_settings_resource_loads_and_is_sane() -> void:
	var s := _settings()
	assert_not_null(s, "%s must load as a PlayerLeanSettings (a parse error here = no lean at all)" % SETTINGS_PATH)
	if s == null:
		return
	assert_true(s.enabled, "the shipped lean settings ship ENABLED — the feature is on by default")
	assert_gt(s.max_offset, 0.0, "max_offset must be positive or a 'lean' moves the head nowhere")
	assert_gt(s.lerp_speed, 0.0, "lerp_speed must be positive or the lean never reaches its target")
	assert_gt(s.probe_radius, 0.0, "the clearance probe needs a real radius or the camera clips the corner it peeks past")
	assert_lt(s.probe_margin, s.max_offset,
		"probe_margin must be smaller than max_offset, or the margin eats the whole lean and _clearance always returns 0")
	assert_eq(s.probe_collision_mask & 1, 1,
		"the probe must include layer 1 (the world/brush geometry) — that's the only thing that should stop a lean")

func test_game_settings_exposes_the_lean_group() -> void:
	assert_not_null(GameSettings.player_lean,
		"GameSettings.player_lean must be wired — every lean number is read through it, never hardcoded")


# --- the binding-share seam (the arbitration the whole feature rests on) --------------------------------------

func test_lean_actions_exist_in_the_input_map() -> void:
	assert_true(InputMap.has_action(InputManager.action_lean_left), "LeanLeft must be a real InputMap action")
	assert_true(InputMap.has_action(InputManager.action_lean_right), "LeanRight must be a real InputMap action")

func test_lean_left_shares_the_contextual_verb_key() -> void:
	# The contextual rule expressed as data: Q is Takedown (and Pet) and ALSO Lean Left. If it stops sharing,
	# that side leans unconditionally and eats the verb — silently, because both actions still exist.
	assert_true(InputManager.actions_share_binding(InputManager.action_lean_left, InputManager.action_takedown),
		"Lean Left must default onto the SAME key as Takedown (Q), so Q stays takedown/pet first and peek second")

func test_lean_right_is_no_longer_contextual_because_interact_moved_to_f() -> void:
	# ⭐Interact was rebound off E onto F (2026-08-20), which is exactly the escape hatch the design documents:
	# no shared event -> no arbitration -> E peeks unconditionally. Pinned so moving Interact BACK onto E is a
	# deliberate, visible change and not a silent one — it would make the right peek defer to interact prompts.
	assert_false(InputManager.actions_share_binding(InputManager.action_lean_right, InputManager.action_pickup),
		"Interact has its own key (F) now — Lean Right (E) must not share with it")
	assert_false(_keycodes_for(InputManager.action_pickup).has(KEY_E),
		"Interact must not default back onto E")
	assert_true(_keycodes_for(InputManager.action_pickup).has(KEY_F),
		"Interact defaults to F")

## The physical keycodes bound to `action` right now (the live InputMap, so a default change shows up here).
func _keycodes_for(action: StringName) -> Array:
	var codes := []
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null:
			codes.append(key.physical_keycode)
	return codes

func test_lean_sides_do_not_share_with_each_other_or_the_wrong_verb() -> void:
	assert_false(InputManager.actions_share_binding(InputManager.action_lean_left, InputManager.action_lean_right),
		"the two lean sides must be different keys")
	assert_false(InputManager.actions_share_binding(InputManager.action_lean_left, InputManager.action_pickup),
		"Lean Left (Q) must NOT share with Interact (F) — else peeking left would defer to an interact prompt")
	assert_false(InputManager.actions_share_binding(InputManager.action_lean_right, InputManager.action_takedown),
		"Lean Right (E) must NOT share with Takedown (Q)")

func test_actions_share_binding_edges() -> void:
	assert_true(InputManager.actions_share_binding(InputManager.action_jump, InputManager.action_jump),
		"an action always shares a binding with itself")
	assert_false(InputManager.actions_share_binding(&"NoSuchAction", InputManager.action_jump),
		"an unknown action shares with nothing (never assume a missing action into a match)")

func test_same_binding_compares_the_control_not_the_event() -> void:
	var a := InputEventKey.new()
	a.physical_keycode = KEY_E
	var b := InputEventKey.new()
	b.physical_keycode = KEY_E
	b.pressed = true  # pressed-state / echo / modifiers are irrelevant to "same physical key"
	assert_true(InputManager.same_binding(a, b), "two events on the same physical key match regardless of state")
	var c := InputEventKey.new()
	c.physical_keycode = KEY_Q
	assert_false(InputManager.same_binding(a, c), "different keys never match")
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	assert_false(InputManager.same_binding(a, m), "different event CLASSES never match")
	var m2 := InputEventMouseButton.new()
	m2.button_index = MOUSE_BUTTON_LEFT
	assert_true(InputManager.same_binding(m, m2), "same mouse button matches")

func test_same_binding_falls_back_to_keycode_when_physical_is_absent() -> void:
	# The project's [input] defaults are all physical_keycode, but a hand-authored or rebound event may carry
	# only `keycode`. Falling back keeps the arbitration honest for those instead of reading them as "no match".
	var a := InputEventKey.new()
	a.keycode = KEY_E
	var b := InputEventKey.new()
	b.keycode = KEY_E
	assert_true(InputManager.same_binding(a, b), "keycode-only events still compare")


# --- the claim (what the verb drivers stand down on) ----------------------------------------------------------

func test_a_fresh_lean_claims_nothing() -> void:
	var rig := _rig()
	var lean: Lean = rig[0]
	assert_false(lean.owns_action(InputManager.action_takedown),
		"an idle lean must claim nothing, or SilentTakedown/PetInteraction would be permanently inert")
	assert_false(lean.owns_action(InputManager.action_pickup), "...and likewise for Interact")
	_free_rig(rig)

func test_claiming_the_left_key_stands_down_the_takedown_but_not_interact() -> void:
	var rig := _rig()
	var lean: Lean = rig[0]
	lean._set_claim(true, true)  # the state a Q press with nothing to take down leaves behind
	assert_true(lean.owns_action(InputManager.action_takedown),
		"a claimed Lean Left must own Takedown (its shared key) so the takedown stands down for the hold")
	assert_false(lean.owns_action(InputManager.action_pickup),
		"...and must NOT own Interact — a left peek can't disable the E verb on the other side of the keyboard")
	_free_rig(rig)

func test_claiming_the_right_key_owns_interact() -> void:
	var rig := _rig()
	var lean: Lean = rig[0]
	lean._set_claim(false, true)
	assert_true(lean.owns_action(InputManager.action_pickup), "a claimed Lean Right owns the Interact key")
	assert_false(lean.owns_action(InputManager.action_takedown), "...but not the Takedown key")
	_free_rig(rig)

func test_reset_drops_the_claims_and_snaps_the_pose() -> void:
	var rig := _rig(-0.05)
	var lean: Lean = rig[0]
	var head: Node3D = rig[1]
	lean._set_claim(true, true)
	lean._set_claim(false, true)
	lean.lean_t = 1.0
	lean._apply(1.0, _settings())
	lean.reset()
	assert_eq(lean.lean_t, 0.0, "reset snaps the blend to upright (a death taken mid-peek must not revive tilted)")
	assert_false(lean.owns_action(InputManager.action_takedown),
		"reset drops the claims too, or the takedown stays standing down for a hold that ended with the last life")
	assert_almost_eq(head.position.x, -0.05, 0.0001, "reset restores the head's AUTHORED rest X, not 0")
	assert_almost_eq(head.rotation.z, 0.0, 0.0001, "reset levels the roll")
	_free_rig(rig)


# --- REGRESSION: a posture gate must not destroy the key claim ------------------------------------------------
# 2026-08-20, reported as "i cant shoot and lean at the same time". EVERY shipped weapon applies
# WeaponData.self_knockback to the shooter on fire (attack.gd) → explosion_velocity → velocity, so a shot aimed
# even slightly DOWNWARD shoves the player up and un-grounds them for a few frames. The lean's airborne gate used
# to call _release_claims(), and the claim is only ever re-decided on `just_pressed` — so one trigger pull killed
# the peek until the player physically let go of the key. The gate is now SOFT: it zeroes the lean target and
# leaves the claim alone.

func test_posture_gate_zeroes_the_lean_but_keeps_the_claim() -> void:
	var rig := _rig()
	var lean: Lean = rig[0]
	lean._set_claim(false, true)      # a right lean already claimed and held
	lean._airborne_t = 10.0           # ...and now a recoil hop (or a jump) has us off the floor
	var s := _settings()
	assert_false(lean._posture_allows(s), "off the floor past the grace window, the posture gate must refuse")
	assert_true(lean.owns_action(InputManager.action_pickup),
		"the claim MUST survive a posture refusal — dropping it strands a HELD key, since only a fresh press re-arms it")
	_free_rig(rig)

func test_ground_grace_absorbs_a_recoil_hop() -> void:
	var rig := _rig()
	var lean: Lean = rig[0]
	var s := _settings()
	assert_gt(s.ground_grace, 0.0, "ground_grace must be positive or every shot's self-knockback dips the lean")
	lean._airborne_t = s.ground_grace * 0.5
	assert_true(lean._posture_allows(s),
		"a brief hop inside the grace window still counts as grounded — that's what stops firing from dipping the peek")
	lean._airborne_t = s.ground_grace + 0.01
	assert_false(lean._posture_allows(s), "past the window a real jump/fall does gate the lean")
	_free_rig(rig)

func test_hard_gate_is_the_one_that_drops_claims() -> void:
	# The other half of the split: when the input genuinely isn't ours (a menu owns the keyboard, the player is
	# dead), the claim MUST go, or the takedown/pet verbs stay standing down forever on a key we no longer drive.
	var rig := _rig()
	var lean: Lean = rig[0]
	lean._set_claim(true, true)
	lean._set_claim(false, true)
	lean._release_claims()
	assert_false(lean.owns_action(InputManager.action_takedown), "a hard gate releases the Takedown-side claim")
	assert_false(lean.owns_action(InputManager.action_pickup), "...and the Interact-side one")
	_free_rig(rig)

func test_airborne_tracker_resets_without_a_player() -> void:
	# A bare/AI rig has no floor state; it must read as grounded so an off-tree unit rig can still lean.
	var rig := _rig()
	var lean: Lean = rig[0]
	lean._airborne_t = 5.0
	lean._track_airborne(0.016)
	assert_eq(lean._airborne_t, 0.0, "no Player wired -> treated as grounded, not permanently airborne")
	_free_rig(rig)


# --- the pose ------------------------------------------------------------------------------------------------

func test_lean_offsets_from_the_authored_rest_x() -> void:
	# Player.tscn nudges the whole Head rig a few millimetres off centre. Writing an ABSOLUTE offset would throw
	# that authored nudge away the first time you leaned and never put it back.
	var rig := _rig(-0.05)
	var lean: Lean = rig[0]
	var head: Node3D = rig[1]
	var s := _settings()
	lean._apply(1.0, s)
	assert_almost_eq(head.position.x, -0.05 + s.max_offset, 0.0001, "a full right lean is rest + max_offset")
	lean._apply(-1.0, s)
	assert_almost_eq(head.position.x, -0.05 - s.max_offset, 0.0001, "a full left lean is rest - max_offset")
	lean._apply(0.0, s)
	assert_almost_eq(head.position.x, -0.05, 0.0001, "upright is exactly the authored rest X")
	_free_rig(rig)

func test_lean_rolls_into_the_lean_matching_the_strafe_tilt_convention() -> void:
	# CameraEffects rolls a RIGHT strafe to a NEGATIVE rotation.z. The lean must use the same sign or the two
	# rolls cancel each other when you lean and strafe the same way.
	var rig := _rig()
	var lean: Lean = rig[0]
	var head: Node3D = rig[1]
	var s := _settings()
	var was := Settings.camera_tilt_enabled
	Settings.camera_tilt_enabled = true
	lean._apply(1.0, s)
	assert_almost_eq(head.rotation.z, -deg_to_rad(s.max_roll_deg), 0.0001, "a right lean rolls NEGATIVE, like a right strafe")
	lean._apply(-1.0, s)
	assert_almost_eq(head.rotation.z, deg_to_rad(s.max_roll_deg), 0.0001, "a left lean rolls positive")
	Settings.camera_tilt_enabled = was
	_free_rig(rig)

func test_camera_tilt_accessibility_toggle_kills_the_roll_but_keeps_the_peek() -> void:
	var rig := _rig()
	var lean: Lean = rig[0]
	var head: Node3D = rig[1]
	var s := _settings()
	var was := Settings.camera_tilt_enabled
	Settings.camera_tilt_enabled = false
	lean._apply(1.0, s)
	assert_almost_eq(head.rotation.z, 0.0, 0.0001,
		"Options -> Accessibility -> Camera Tilt off must level the lean roll (it's the same motion-comfort switch as the strafe roll)")
	assert_almost_eq(head.position.x, s.max_offset, 0.0001,
		"...but the POSITIONAL peek stays — turning off camera roll must not remove the ability to look round a corner")
	Settings.camera_tilt_enabled = was
	_free_rig(rig)


# --- inert without a rig -------------------------------------------------------------------------------------

func test_a_lean_with_no_head_is_inert() -> void:
	# The Player wires `head` in _enter_tree; a bare .new() (or an extraction that clears the export) must
	# no-op rather than crash the physics step.
	var lean: Lean = LeanScript.new()
	lean._ready()
	lean._physics_process(0.016)
	assert_eq(lean.lean_t, 0.0, "no head -> no lean, no error")
	lean.reset()
	assert_eq(lean.lean_t, 0.0, "reset is safe with no head wired")
	lean.free()


# --- the E half of the rule: the ray's interact-availability report -------------------------------------------

func test_pickup_ray_reports_no_pending_verb_when_it_has_nothing_to_interact_with() -> void:
	# The lean claims E only when this is empty. A ray with no held prop, no talk handler and no collision has
	# nothing for E to do, so E is free to become a peek.
	var ray := PickupRay.new()
	assert_false(ray.interact_available(),
		"an idle interaction ray offers no interact, so an E press is the lean's to claim")
	assert_eq(ray.pending_verb_action(), &"",
		"pending_verb_action reports &\"\" when Interact would do nothing")
	ray.free()


# --- the Options surface -------------------------------------------------------------------------------------

func test_both_lean_actions_are_rebindable_in_the_controls_tab() -> void:
	var cat := load("res://resources/input/ActionCatalog.tres") as ActionCatalog
	assert_not_null(cat, "ActionCatalog.tres must load")
	if cat == null:
		return
	var names := cat.rebindable_actions()
	assert_true(names.has(InputManager.action_lean_left),
		"Lean Left needs an ActionCatalog row or the player can't rebind it off Q (the whole escape hatch from the shared key)")
	assert_true(names.has(InputManager.action_lean_right), "Lean Right needs an ActionCatalog row too")
