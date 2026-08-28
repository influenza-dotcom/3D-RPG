extends GutTest

## GUT suite for the single NPC class (scripts/npc/npc.gd). After the structural fold NPC is the ONE
## concrete non-player actor (Character -> NPC); the former Enemy / RangedEnemy classes are gone and
## their behaviour lives here, data-driven (weapon_data null = civilian, set = combatant). These
## asserts guard the class shape and that `NPC is Character` stays true, so every `is Character` /
## `is NPC` runtime check across combat / effects / death keeps matching.
##
## NPC is now concrete (instantiable), but we still build off-tree (load().new() WITHOUT add_child)
## so _ready never runs — it spawns a Perception / NavigationAgent3D and calls get_tree(). The
## @abstract REMOVAL is asserted by source-grepping npc.gd (no runtime abstract flag in GDScript),
## the same _read_file pattern test_smoke.gd uses.

const NPC_PATH := "res://scripts/npc/npc.gd"
const EPS := 0.0001

class _SittingLocomotionHost:
	extends Node
	var _follow = null
	var _spawn_yaw: float = 1.25
	var _spawn_position: Vector3 = Vector3(4.0, 0.0, 4.0)
	var sitting: bool = true
	var wanders: bool = true
	var face_yaw_calls: int = 0
	var move_calls: int = 0
	func is_following() -> bool:
		return false
	func is_sitting() -> bool:
		return sitting
	func _face_yaw(_yaw: float, _delta: float) -> void:
		face_yaw_calls += 1
	func _move_toward(_point: Vector3) -> bool:
		move_calls += 1
		return true
	func _snap_to_navmesh(point: Vector3, _max_drift: float) -> Vector3:
		return point
	func _face_travel(_delta: float) -> void:
		pass
	func _pick_wander_point() -> Vector3:
		return Vector3(9.0, 0.0, 9.0)

func test_npc_script_loads() -> void:
	var script = load(NPC_PATH)
	assert_not_null(script, "npc.gd must load — it is the single non-player actor class")
	assert_true(script is GDScript, "npc.gd must be a GDScript")

func test_npc_is_concrete_not_abstract() -> void:
	# The fold makes NPC the single CONCRETE class — the @abstract annotation must be GONE, or the
	# enemy scenes that instance npc.gd would fail to load.
	var content := _read_file(NPC_PATH)
	assert_false("@abstract" in content,
		"npc.gd must NOT be @abstract — NPC is now the single concrete class the enemy scenes instance")
	assert_true("class_name NPC" in content,
		"npc.gd must declare class_name NPC so `is NPC` checks and the scene scripts resolve globally")

func test_npc_is_a_character_actor() -> void:
	# The fold must keep NPC a Character / CharacterBody3D so combat / effects / death (`is Character`
	# and `is NPC` checks in attack.gd, explosion_area.gd, player.gd) plus move_and_slide keep working.
	# Off-tree (no add_child) so _ready never runs.
	var n = load(NPC_PATH).new()
	assert_true(n is NPC, "an npc.gd instance must be an NPC")
	assert_true(n is Character,
		"NPC must stay a Character (NPC -> Character) so every `is Character` runtime check keeps matching")
	assert_true(n is CharacterBody3D,
		"NPC must stay a CharacterBody3D so move_and_slide / blast physics still apply")
	n.free()

func test_npc_outline_exports_default_to_combat_rim() -> void:
	# NPC owns the combat outline (Phase 2). Defaults reproduce the old hardcoded Character rim,
	# now actually reaching the shader. Off-tree so _ready -> _setup_outline never runs.
	# The black rim is CORRECT next to the world's InkOutline ink because actors are EXCLUDED from that
	# pass (the ACTOR_INK_MASK_LAYER stamp in _apply_overlay_to_meshes — pinned by test_ink_outline.gd);
	# it briefly shipped transparent to dodge ink-doubling, which was the wrong fix.
	var n = load(NPC_PATH).new()
	assert_true(n.has_outline, "NPC.has_outline must default true so combatants still get their outline")
	assert_eq(n.outline_color, Color.BLACK, "NPC.outline_color must default black — the dark combat rim")
	assert_eq(n.outline_width, 2.0,
		"NPC.outline_width 2.0 is the intended combat rim thickness, fed to the shader's outline_width uniform")
	n.free()

func test_npc_display_name_defaults_empty() -> void:
	# NPCs have a name (shown as the dialogue speaker label). Default empty => unnamed, label hidden.
	var n = load(NPC_PATH).new()
	assert_eq(n.display_name, "",
		"NPC.display_name must default empty so an unnamed NPC hides the dialogue speaker label")
	n.free()

func test_npc_weapon_knockback_immunity_defaults_off() -> void:
	var n = load(NPC_PATH).new()
	assert_false(n.immune_to_weapon_knockback,
		"immune_to_weapon_knockback must default false so existing enemies still take their weapon's recoil")
	n.free()

func test_npc_build_components_adds_pickpocket_talkable_when_missing() -> void:
	var n = load(NPC_PATH).new()
	n._build_components()
	var t := n.get_node_or_null(NPC.PICKPOCKET_TALKABLE_NAME) as Talkable
	assert_not_null(t,
		"a stock hostile NPC needs a dialogue-less Talkable so crouch-interact can pickpocket it")
	var shape := t.get_node_or_null("CollisionShape3D") as CollisionShape3D
	assert_not_null(shape, "the auto pickpocket Talkable needs a hitbox for PickupRay's talk-layer ray")
	assert_true(shape.shape is BoxShape3D, "the auto pickpocket hitbox uses the same simple box shape as the component prefab")
	assert_eq((shape.shape as BoxShape3D).size, NPC.PICKPOCKET_TALKABLE_SIZE,
		"the auto pickpocket hitbox should cover the NPC body")
	n.free()

func test_npc_build_components_preserves_authored_talkable() -> void:
	var n = load(NPC_PATH).new()
	var authored := Talkable.new()
	authored.name = "Talkable"
	n.add_child(authored)
	n._build_components()
	var talkable_count := 0
	for c in n.get_children():
		if c is Talkable:
			talkable_count += 1
	assert_eq(talkable_count, 1,
		"an NPC with authored dialogue must not get a second overlapping pickpocket-only Talkable")
	assert_true(n.get_node_or_null("Talkable") == authored,
		"the authored Talkable remains the one the look-at ray will hit")
	assert_null(n.get_node_or_null(NPC.PICKPOCKET_TALKABLE_NAME),
		"the auto pickpocket node is skipped when a Talkable already exists")
	n.free()

func test_sitting_locomotion_holds_post_instead_of_wandering() -> void:
	var host := _SittingLocomotionHost.new()
	var loco := NpcLocomotion.new()
	loco.host = host
	host.add_child(loco)
	loco._idle(0.1, true)
	assert_eq(host.face_yaw_calls, 1, "a seated idle NPC holds its authored facing")
	assert_eq(host.move_calls, 0, "a seated idle NPC does not wander or path back to post")
	host.free()

# --- Seated posture gating (is_sitting) -----------------------------------------------------------------
# The seat is an IDLE-AT-POST posture, and the gate is what decides whether a hostile is ever SEEN sitting.
# Perception is attached bare (never add_child'd) so no _ready runs — is_sitting only reads .state.

func _seated_npc_with_perception() -> Array:
	var n = load(NPC_PATH).new()
	n.sitting = true
	var p := Perception.new()
	n._perception = p
	return [n, p]

func test_sitting_survives_the_first_glance_but_not_a_real_engagement() -> void:
	# DETECTING is the "what was that?" beat and the GOAP Detect action only TURNS the body, so a seated NPC can
	# play it from the seat. Standing at the first flicker is why an armed NPC was never seen seated at all: a
	# hostile holds the player as a proximity target and starts detecting from anywhere inside sight_range.
	var pair := _seated_npc_with_perception()
	var n = pair[0]
	var p: Perception = pair[1]
	p.state = Perception.State.UNAWARE
	assert_true(n.is_sitting(), "idle + unaware -> seated")
	p.state = Perception.State.DETECTING
	assert_true(n.is_sitting(), "DETECTING keeps the seat — it swivels to look, it doesn't scramble up yet")
	p.state = Perception.State.ALERTED
	assert_false(n.is_sitting(), "locked on -> stand up and fight")
	p.state = Perception.State.INVESTIGATING
	assert_false(n.is_sitting(), "hunting a lost trail -> stand up (the Search action walks it to the spot)")
	p.free()
	n.free()

func test_sitting_toggle_and_cutscene_still_win_over_the_posture() -> void:
	var pair := _seated_npc_with_perception()
	var n = pair[0]
	var p: Perception = pair[1]
	p.state = Perception.State.DETECTING
	n.sitting = false
	assert_false(n.is_sitting(), "the authored toggle is still the master switch")
	n.sitting = true
	n._cutscene_control = true
	assert_false(n.is_sitting(), "a cutscene-driven body stands, whatever perception says")
	p.free()
	n.free()

func test_at_post_is_true_off_tree() -> void:
	# is_sitting() gates on being back at the post, which reads global_position + the tuning autoload. Off-tree
	# (the standard unit-test NPC) it must degrade to "never left", touching neither.
	var n = load(NPC_PATH).new()
	assert_true(n._at_post(), "an off-tree NPC has never left its post, so the seat applies")
	n.free()

# --- Held-gun anchor rides the seated drop --------------------------------------------------------------

func test_muzzle_anchor_follows_the_body_posture_offset() -> void:
	# The weapon view-model hangs off _muzzle on the NPC ROOT while the visible body drops onto the seat, so
	# without this sync a seated guard's rifle floats at standing chest height above the hands holding it.
	var n = load(NPC_PATH).new()
	n.muzzle_offset = Vector3(0.1, 0.2, 0.3)
	var muzzle := Marker3D.new()
	n.add_child(muzzle)
	n._muzzle = muzzle
	var bms = load("res://scripts/components/body_model_swap.gd").new()
	bms.leg_position = Vector3(0.095, -0.265, -0.02)
	bms.seated_hip_clearance = 0.06
	bms._seat_ground_valid = true
	bms._seat_ground_y = -1.0
	n.add_child(bms)
	n.sitting = false
	n._sync_muzzle_to_posture()
	assert_eq(muzzle.position, n.muzzle_offset, "standing -> the gun sits at its authored hand anchor")
	n.sitting = true
	n._sync_muzzle_to_posture()
	assert_eq(muzzle.position, n.muzzle_offset + bms.posture_offset(),
		"seated -> the anchor drops by the SAME offset the visible body does, so the gun stays in the hands")
	assert_lt(muzzle.position.y, n.muzzle_offset.y, "and that means it actually moves DOWN onto the seated body")
	n.free()

func test_muzzle_sync_is_a_noop_without_a_body_swap() -> void:
	# A non-swapped NPC (or one whose swap has no posture seam) must keep the authored anchor exactly as before.
	var n = load(NPC_PATH).new()
	n.muzzle_offset = Vector3(0.0, 0.4, 0.0)
	var muzzle := Marker3D.new()
	n.add_child(muzzle)
	n._muzzle = muzzle
	n.sitting = true
	assert_eq(n._body_posture_offset(), Vector3.ZERO, "no BodyModelSwap child -> the neutral ZERO offset")
	n._sync_muzzle_to_posture()
	assert_eq(muzzle.position, n.muzzle_offset, "so the hand anchor is untouched")
	n.free()

# --- Muzzle FX cancel the scale they inherit from the barrel anchor ------------------------------------
# _build_muzzle_fx PARENTS three emitters (spark, barrel smoke, ejected casing) to the held gun's Muzzle
# marker, so each one inherits that marker's whole transform — SCALE included — from two multipliers that
# have nothing to do with how big an effect should be: the view-model's baked ROOT scale (identity on
# ak_472, 0.001 Sketchfab millimetres on the pistol's silenced.tscn) and the npc_held_display_scale
# readability boost _build_weapon_mesh multiplies onto the MESH. Composed, NPC muzzle FX ran at 1.75x on a
# clean gun and 0.00175x on the pistol — a 571x spread across weapons, i.e. smoke puffs ~45 MICROMETRES
# wide. _unscale_muzzle_fx normalises every one of them to 1.0, so an NPC emits the same authored effect
# the player's rig does and per-weapon sizing stays on the dial designed for it (muzzle_smoke_scale).
#
# These asserts watch the NODE transform on purpose, because that is the only thing that moved: the bug
# was invisible to this suite twice over. --headless never compiles a particle shader, so nothing
# automated can SEE particle size; and the emitter's own properties all round-trip perfectly —
# scale_min / scale_max read identically on a working gun and a broken one, because what collapsed is the
# transform underneath them. Never judge this one from the process material. To judge it with your eyes,
# run scripts/tools/muzzle_smoke_qa_shots.gd (its NPC section prints QA_NPC_SCALE and shoots the barrel).
#
# The rig below is IN-TREE (add_child_autofree) because global_transform raises an engine error on an
# off-tree Node3D and GUT fails a test on any engine error. The NPC stays OFF-tree as usual:
# _unscale_muzzle_fx reads nothing but its two arguments, so it is a pure call with an NPC for a namespace.

## Build the real parent chain — hand anchor -> weapon mesh -> barrel marker -> FX — in-tree, and hand back
## the FX node (its anchor is fx.get_parent()). `mesh_scale` is the view-model's baked root scale already
## multiplied by the display boost; `marker_scale` is whatever the Muzzle marker's OWN basis bakes on top of
## that (the spray can bakes 0.015 there rather than on the root).
func _muzzle_fx_rig(mesh_scale: Vector3, marker_scale: Vector3) -> Node3D:
	var hand := Node3D.new()
	add_child_autofree(hand)
	var mesh := Node3D.new()
	mesh.scale = mesh_scale
	hand.add_child(mesh)
	var marker := Marker3D.new()
	marker.scale = marker_scale
	mesh.add_child(marker)
	var fx := Node3D.new()
	marker.add_child(fx)
	return fx

func test_muzzle_fx_come_out_at_world_scale_one_whatever_the_gun_bakes() -> void:
	var n = load(NPC_PATH).new()
	var boost := 1.75  # WeaponData.npc_held_display_scale's default; _build_weapon_mesh puts it on the MESH
	# [label, view-model ROOT scale, extra scale baked into the Muzzle marker itself]
	var guns := [
		["ak_472 — identity root, so the FX fight only the display boost", 1.0, 1.0],
		["silenced.tscn — 0.001 baked on the ROOT (this is the pistol whose smoke went invisible)", 0.001, 1.0],
		["the spray can — 0.015 baked into the Muzzle marker's OWN basis instead of the root", 1.0, 0.015],
		["sniper_rifle.tscn — millimetres kept on a model CHILD with the marker as its sibling", 1.0, 1.0],
	]
	var corrections: Array[float] = []
	for g in guns:
		var fx := _muzzle_fx_rig(Vector3.ONE * (float(g[1]) * boost), Vector3.ONE * float(g[2]))
		n._unscale_muzzle_fx(fx, fx.get_parent() as Node3D)
		var s: Vector3 = fx.global_transform.basis.get_scale()
		assert_almost_eq(s.x, 1.0, EPS,
			"%s: the FX must sit at WORLD scale 1.0 once unscaled — it is the node transform, not any material property, that decides how big an NPC's muzzle effect draws" % g[0])
		assert_almost_eq(s.y, 1.0, EPS, "%s: same on Y" % g[0])
		assert_almost_eq(s.z, 1.0, EPS, "%s: same on Z" % g[0])
		corrections.append(fx.scale.x)

	assert_lt(corrections[0], 1.0,
		"1.0 is the target DELIBERATELY, so a clean-root gun's FX SHRINK from the 1.75x they used to inherit — that inflation was accidental, and matching the player's authored effect beats matching the old look")
	assert_almost_eq(corrections[1] / corrections[0], 1000.0, 0.01,
		"the pistol needs a 1000x bigger correction than the clean gun (its root bakes 0.001) — that entire spread used to reach the particles instead, which is why one weapon smoked and another emitted nothing visible")

	n.free()

func test_muzzle_fx_unscale_is_per_axis() -> void:
	# A non-uniform anchor — a squashed view-model root, or one axis stretched by an importer — must come
	# back to 1.0 on ALL THREE axes. Dividing by one uniform factor would leave the plume stretched, which
	# reads as a "wrong-looking" effect nobody would trace back to the gun's transform.
	var n = load(NPC_PATH).new()
	var fx := _muzzle_fx_rig(Vector3(0.5, 2.0, 4.0), Vector3.ONE)
	n._unscale_muzzle_fx(fx, fx.get_parent() as Node3D)
	var s: Vector3 = fx.global_transform.basis.get_scale()
	assert_almost_eq(s.x, 1.0, EPS, "a squashed X must be cancelled on X alone")
	assert_almost_eq(s.y, 1.0, EPS, "a stretched Y must be cancelled on Y alone")
	assert_almost_eq(s.z, 1.0, EPS, "and Z too — the correction is per-axis, never one averaged divisor")
	n.free()

func test_muzzle_fx_unscale_leaves_the_authored_position_and_rotation_alone() -> void:
	# LOCAL scale only. SparkAttack bakes a barrel roll into its own root and all three FX roots sit at the
	# origin, so writing a whole global_transform here would flatten that roll (and there is no offset to
	# un-crush anyway). Whatever the FX scene authored has to survive the correction untouched.
	var n = load(NPC_PATH).new()
	var fx := _muzzle_fx_rig(Vector3.ONE * 0.00175, Vector3.ONE)
	fx.position = Vector3(0.0, 0.02, 0.1)
	fx.rotation_degrees = Vector3(0.0, 0.0, 37.0)
	n._unscale_muzzle_fx(fx, fx.get_parent() as Node3D)
	assert_eq(fx.position, Vector3(0.0, 0.02, 0.1),
		"the FX scene's authored offset must survive — the fix writes scale, not the full transform")
	assert_almost_eq(fx.rotation_degrees.z, 37.0, 0.001,
		"and so must its authored roll: SparkAttack's barrel roll is baked into the scene, not applied at runtime")
	n.free()

func test_muzzle_fx_unscale_leaves_a_degenerate_anchor_alone() -> void:
	# A collapsed axis (a broken import, or a designer typing 0 into the mesh scale) would make the divisor
	# INF and put the emitter's transform beyond recovery. Warn and leave it as-is instead: a wrongly-sized
	# plume is a thing you can see and fix, a NaN transform is not. The 1e-9 below says "collapsed" rather
	# than "a designer typed 0" — the float32 transform stores it as a flat 0.0 either way, and the guard's
	# is_zero_approx catches anything under ~1e-5, so both spellings take the same branch.
	var n = load(NPC_PATH).new()
	var fx := _muzzle_fx_rig(Vector3(1.0, 1e-9, 1.0), Vector3.ONE)
	fx.scale = Vector3.ONE * 3.0
	n._unscale_muzzle_fx(fx, fx.get_parent() as Node3D)
	assert_eq(fx.scale, Vector3.ONE * 3.0,
		"a degenerate anchor must leave the FX exactly as it was found — no INF, no NaN written into the transform")
	assert_true(is_finite(fx.global_transform.basis.get_scale().y),
		"and the composed world scale stays finite, so the emitter is still a recoverable node")
	n.free()

func test_every_fx_hung_on_the_muzzle_anchor_cancels_its_scale() -> void:
	# The regression this file cannot catch any other way: a FOURTH emitter added to _build_muzzle_fx
	# without its _unscale_muzzle_fx line. Nothing would complain at runtime — it would simply be born the
	# wrong size on every weapon, and per the section header no property assert can tell. So pair the two
	# calls in TEXT. If the cancel ever moves somewhere else (a helper that adds AND unscales, say), retire
	# this assert deliberately rather than loosening it — but keep the pairing guaranteed somehow.
	var n = load(NPC_PATH).new()
	assert_true(n.has_method("_unscale_muzzle_fx"),
		"NPC must keep _unscale_muzzle_fx — it is the single seam that stops the held gun's display scale from resizing its muzzle effects")
	n.free()

	var src := _read_file(NPC_PATH)
	var start := src.find("func _build_muzzle_fx()")
	assert_gt(start, -1,
		"npc.gd must still define _build_muzzle_fx — it is what parents the spark, smoke and casing to the barrel")
	var end := src.find("\nfunc ", start + 1)
	if end < 0:
		end = src.length()
	var body := src.substr(start, end - start)
	var adds := body.count("anchor.add_child(")
	var cancels := body.count("_unscale_muzzle_fx(")
	assert_gt(adds, 0, "_build_muzzle_fx must still hang its emitters on the barrel anchor")
	assert_eq(cancels, adds,
		"every node added to the muzzle anchor needs its own _unscale_muzzle_fx right after it — %d add_child vs %d cancels means an emitter is inheriting the gun's display scale, which on the pistol is 0.00175x and invisible" % [adds, cancels])

# --- Anti-stuck navigation (pathfinding fix: steer ALONG a wall instead of grinding into it) -----------
# The full stuck-detection (is_on_floor + wall-vs-floor contact + speed-vs-intended) is in-tree physics
# state -> playtested. The unit-testable slices: the wall-slide steering MATH (a static) and the unstick
# timer countdown + off-tree safety.

func test_npc_anti_stuck_tuning_is_sane() -> void:
	assert_gt(NPC.STUCK_TIME, 0.0,
		"STUCK_TIME (>0) is the grace an NPC must be pressed on a wall before it counts as stuck")
	assert_gt(NPC.UNSTICK_TIME, 0.0,
		"UNSTICK_TIME (>0) is how long it then steers along the wall to slip free")
	assert_gt(NPC.CHASE_STUCK_GIVEUP_TIME, NPC.STUCK_GIVEUP_TIME,
		"hop-capable pursuit should keep trying longer than idle navigation before a give-up pause")
	assert_true(NPC.CHASE_STUCK_HOLD_TIME > 0.0 and NPC.CHASE_STUCK_HOLD_TIME < NPC.STUCK_HOLD_TIME,
		"hop-capable pursuit should only pause briefly before pressing the chase again")
	assert_true(NPC.STUCK_HOP_TIME > 0.0 and NPC.STUCK_HOP_TIME < NPC.STUCK_GIVEUP_TIME,
		"stuck recovery hop must fire before the old give-up timer")
	assert_true(NPC.STUCK_SPEED_FRAC > 0.0 and NPC.STUCK_SPEED_FRAC < 1.0,
		"STUCK_SPEED_FRAC is the fraction of intended speed below which it counts as blocked — a fraction in (0,1)")

func test_npc_wall_slide_dir_steers_along_wall_toward_goal() -> void:
	# Wall normal pointing +X (a wall on our left/right), goal straight ahead at +Z.
	var dir := NPC.wall_slide_dir(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0))
	assert_almost_eq(dir.length(), 1.0, 0.001, "the slide direction is a unit vector")
	assert_almost_eq(dir.dot(Vector3(1.0, 0.0, 0.0)), 0.0, 0.001,
		"it runs ALONG the wall (perpendicular to the contact normal) so the NPC stops pressing INTO it")
	assert_gt(dir.dot(Vector3(0.0, 0.0, 1.0)), 0.0,
		"of the two ways along the wall it picks the one heading toward the goal (+Z)")
	# Flip the goal: same wall, it must take the OTHER way along it.
	var back := NPC.wall_slide_dir(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0))
	assert_gt(back.dot(Vector3(0.0, 0.0, -1.0)), 0.0,
		"goal behind us -> slide the other way along the wall, still toward the goal")
	assert_almost_eq(dir.dot(back), -1.0, 0.001,
		"opposite goal directions pick opposite sides of the same wall")

func test_locomotor_unstick_timer_counts_down_and_is_off_tree_safe() -> void:
	# The anti-stuck timers migrated from npc._update_stuck to Locomotor.update_stuck (Phase B). Off-tree (a bare body,
	# not on the floor) it early-returns, but must still tick the unstick timer DOWN so the steer expires, and never
	# crash on the missing physics state. Drive it the way the NPC does: loco.update_stuck(body, delta).
	var body := CharacterBody3D.new()
	var loco := Locomotor.new()
	body.add_child(loco)
	loco._unstick_t = Locomotor.UNSTICK_TIME
	loco.update_stuck(body, 0.1)
	assert_almost_eq(loco._unstick_t, Locomotor.UNSTICK_TIME - 0.1, 0.0001,
		"the unstick steer timer counts down each tick so the NPC stops wall-following after UNSTICK_TIME")
	assert_eq(loco._stuck_t, 0.0,
		"off-tree (not on the floor) update_stuck resets the stuck timer and bails — no false 'stuck' without ground contact")
	body.free()  # frees loco too (child)

func test_locomotor_drive_move_to_off_tree_returns_false() -> void:
	# Driven-mode entry contract: off-tree (never _ready'd, so _nav == null) drive_move_to returns false immediately and
	# leaves desired_velocity ZERO — the NPC's _move_toward shell relays that false (arrived / can't-move) safely pre-build.
	var loco := Locomotor.new()
	assert_false(loco.drive_move_to(Vector3(5, 0, 5), true, null),
		"off-tree drive_move_to (no agent) reports not-travelling instead of crashing")
	assert_eq(loco.desired_velocity, Vector3.ZERO,
		"and produces no steering")
	loco.free()

func test_npc_thanks_pool_ships_unauthored() -> void:
	# THANKS_LINES is the pool the assist-thanks bark draws from. Speech is authored content: it ships
	# EMPTY (= silent — _pick_bark returns "" and _emit_bark skips) until a designer fills BarkSet.thanks.
	assert_true(NPC.THANKS_LINES is Array,
		"NPC.THANKS_LINES must be an Array — thank_for_assist() picks a random line from it")
	assert_eq(NPC.THANKS_LINES.size(), 0,
		"THANKS_LINES ships unauthored (empty = silent)")

func test_npc_has_assist_and_bark_methods() -> void:
	# Assert the assist-thanks ENTRY POINT (thank_for_assist) and the unified bark EMITTER (_emit_bark,
	# which every bark path routes through) both exist on an instance. has_method only — we do NOT drive
	# them: _emit_bark awaits get_tree() and the thanks path needs a Talkable, so both need the tree.
	# Off-tree (no add_child) so _ready never runs, matching this suite's construction idiom.
	var n = load(NPC_PATH).new()
	assert_true(n.has_method("thank_for_assist"),
		"NPC must expose thank_for_assist() — the assist-thanks entry point called from _on_died")
	assert_true(n.has_method("_emit_bark"),
		"NPC must expose _emit_bark() — the single bark emitter every bark/thanks/remark path routes through")
	n.free()

func test_npc_head_look_range_expands_only_for_player_lock() -> void:
	var n = load(NPC_PATH).new()
	var p := Perception.new()
	var target := Node3D.new()
	target.add_to_group(Groups.PLAYER)
	n._perception = p
	n._target = target
	n.sight_range = 25.0
	n.fire_range = 30.0

	assert_almost_eq(n.head_look_max_range(12.0), 12.0, EPS,
		"idle / not-alerted NPCs keep the mount's authored short look range")
	p.state = Perception.State.DETECTING
	assert_almost_eq(n.head_look_max_range(12.0), 12.0, EPS,
		"first-spotting DETECTING still uses the normal head range")
	p.state = Perception.State.ALERTED
	assert_almost_eq(n.head_look_max_range(12.0), 30.0, EPS,
		"once locked onto the player, the head tracks across normal combat range")

	target.free()
	p.free()
	n.free()

# Local source reader (mirrors test_smoke.gd's own _read_file — a file-local helper there, not a
# shared GutTest method, so this suite defines its own copy).
func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	var s := f.get_as_text()
	f.close()
	return s
