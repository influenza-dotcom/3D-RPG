extends GutTest

## GUT suite for the single NPC class (scripts/npc/npc.gd). After the structural fold NPC is the ONE
## concrete non-player actor (Character -> NPC); the former Enemy / RangedEnemy classes are gone and
## their behaviour lives here, data-driven (weapon_data null = civilian, set = combatant). Beyond the
## class shape (`NPC is Character`, so every `is Character` / `is NPC` check keeps matching), the suite
## DRIVES the NPC's off-tree-safe seams: the rim colour, the pickpocket hitbox, seated posture, the held
## gun's anchor / aim pitch / world layer / muzzle FX, the anti-stuck steering, the punch knockback
## immunity and the assist-thanks bark.
##
## NPC is concrete (instantiable — every `load().new()` below would return null if the @abstract came
## back), but we still build off-tree (load().new() WITHOUT add_child) so _ready never runs — it spawns
## a Perception / NavigationAgent3D and calls get_tree(). Anything that needs a global transform hangs
## on a small in-tree rig instead, never on the NPC itself.

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

func test_npc_is_a_character_actor() -> void:
	# The fold must keep NPC a Character / CharacterBody3D so combat / effects / death (`is Character`
	# and `is NPC` checks in attack.gd, explosion_area.gd, player.gd) plus move_and_slide keep working.
	# Off-tree (no add_child) so _ready never runs. The instance existing at all is the CONCRETENESS check:
	# an @abstract npc.gd refuses .new(), and every enemy scene that instances it would fail to load.
	var n = load(NPC_PATH).new()
	assert_true(n != null, "npc.gd must instantiate — NPC is the single concrete class the enemy scenes instance")
	assert_true(n is NPC, "an npc.gd instance must be an NPC (class_name NPC resolves globally)")
	assert_true(n is Character,
		"NPC must stay a Character (NPC -> Character) so every `is Character` runtime check keeps matching")
	assert_true(n is CharacterBody3D,
		"NPC must stay a CharacterBody3D so move_and_slide / blast physics still apply")
	n.free()

func test_npc_rim_colour_reads_the_attitude_and_a_neutral_wears_the_outline_color_export() -> void:
	# _outline_color_for_disposition() is the one colour source for the rim's attitude AND the laser beam's tint
	# (NpcLaser reads it directly). The black neutral rim is CORRECT next to the world's InkOutline ink because
	# actors are EXCLUDED from that pass (ACTOR_INK_MASK_LAYER, pinned by test_ink_outline.gd); it briefly shipped
	# transparent to dodge ink-doubling, which was the wrong fix. (outline_width is inert since the hull was
	# retired — nothing reads it — so it is not asserted here; test_npc_data pins that NpcData still stamps it.)
	# Off-tree so _ready -> _setup_outline never runs; the resolver reads only disposition / provoke / leader.
	var n = load(NPC_PATH).new()
	assert_true(n.has_outline,
		"SHIP DECISION: every NPC gets the combat rim unless a designer switches has_outline off on that instance")
	n.disposition = Disposition.Kind.NEUTRAL
	assert_eq(n._outline_color_for_disposition(), Color.BLACK,
		"SHIP DECISION: an unprovoked NEUTRAL NPC reads the classic black rim (and its laser draws black) out of the box")
	var authored := Color(0.2, 0.6, 0.9)
	n.outline_color = authored
	assert_eq(n._outline_color_for_disposition(), authored,
		"a neutral NPC wears the designer's outline_color export — a per-instance tint must actually reach the rim/laser")
	n.disposition = Disposition.Kind.HOSTILE
	assert_eq(n._outline_color_for_disposition(), CBPalette.hostile(),
		"a HOSTILE NPC reads the palette's hostile hue whatever outline_color says, so a threat is legible at a glance")
	n.disposition = Disposition.Kind.FRIENDLY
	assert_eq(n._outline_color_for_disposition(), CBPalette.friendly(),
		"a FRIENDLY NPC reads the palette's friendly hue, never the neutral export")
	n.disposition = Disposition.Kind.NEUTRAL
	n._provoked = true
	assert_eq(n._outline_color_for_disposition(), CBPalette.hostile(),
		"a neutral the player PROVOKED re-tints hostile — the rim must warn that it is now shooting back")
	var leader := Node3D.new()
	n._leader = leader
	assert_eq(n._outline_color_for_disposition(), NPC.OUTLINE_FOLLOWING,
		"a recruited companion following the player wears the companion blue, overriding every attitude tint")
	n._leader = null
	leader.free()
	n.free()

func test_an_unauthored_npc_shows_no_speaker_label() -> void:
	# display_name is the dialogue speaker label (TalkHelpers.speaker_name falls back to it when a line leaves
	# `speaker` blank). An NPC dropped into a level with nothing authored must read as UNNAMED — the label hides —
	# rather than leaking something the player was never meant to read, like the scene node's name.
	var n = load(NPC_PATH).new()
	n.name = &"RaiderGrunt"   # a placed NPC always carries a node name; the label must never fall back to it
	assert_eq(TalkHelpers.speaker_name("", n), "",
		"an NPC with no display_name authored must resolve to NO speaker name, so the dialogue label stays hidden")
	n.display_name = "Marta"
	assert_eq(TalkHelpers.speaker_name("", n), "Marta",
		"control: the same NPC, once a designer names it, labels its lines with that name")
	n.free()

## A punch VICTIM: a real Character (NpcCombat._punch casts its target `as Character`) with the flag the punch reads.
## Godot 4 never chains _ready / _physics_process to the parent without super(), so the in-tree body builds none of
## Character's children and never moves; take_damage only counts, so the test watches the swat alone.
class _PunchVictim:
	extends Character
	var immune_to_weapon_knockback: bool = false
	var hits: int = 0
	func _ready() -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass
	func take_damage(_amount: float, _was_crit: bool = false, _attacker: Node = null, _hit_pos: Vector3 = Vector3.INF) -> void:
		hits += 1

## The puncher: only the members NpcCombat._punch reads off its host.
class _PunchHost:
	extends Node3D
	var _target: Node = null
	func _aim_point() -> Vector3:
		return Vector3.ZERO
	func _find_body_swap() -> Node:
		return null

func test_a_stock_npc_is_swatted_by_a_punch_but_a_knockback_immune_one_holds_its_ground() -> void:
	# immune_to_weapon_knockback lets a heavy / anchored NPC ignore weapon shoves; every other NPC must still be
	# knocked back. The victim takes its flag from a freshly built NPC, so "a stock NPC gets swatted" is what runs.
	var stock = load(NPC_PATH).new()
	var stock_immune: bool = stock.immune_to_weapon_knockback
	stock.free()
	var host := _PunchHost.new()
	add_child_autofree(host)
	var combat := NpcCombat.new()
	combat.host = host
	var victim := _PunchVictim.new()
	victim.immune_to_weapon_knockback = stock_immune
	add_child_autofree(victim)
	victim.position = Vector3(0.0, 0.0, 2.0)   # 2 m straight ahead (+Z) of the puncher
	host._target = victim
	combat._punch()
	assert_eq(victim.hits, 1, "the punch lands on the target")
	assert_gt(victim.explosion_velocity.z, 0.0,
		"a stock NPC (immune_to_weapon_knockback at its default) is shoved AWAY from the puncher")
	assert_almost_eq(victim.explosion_velocity.x, 0.0, EPS, "straight along the puncher -> victim line, not sideways")

	var anchored := _PunchVictim.new()
	anchored.immune_to_weapon_knockback = true
	add_child_autofree(anchored)
	anchored.position = Vector3(0.0, 0.0, 2.0)
	host._target = anchored
	combat._punch()
	assert_eq(anchored.hits, 1, "an immune NPC still TAKES the hit — the flag waives the shove, never the damage")
	assert_eq(anchored.explosion_velocity, Vector3.ZERO,
		"a knockback-immune NPC gets no blast impulse at all, so an anchored heavy stays planted")
	combat.free()

func test_npc_build_components_adds_pickpocket_talkable_when_missing() -> void:
	var n = load(NPC_PATH).new()
	n._build_components()
	var t := n.get_node_or_null(NPC.PICKPOCKET_TALKABLE_NAME) as Talkable
	assert_not_null(t,
		"a stock hostile NPC needs a dialogue-less Talkable so crouch-interact can pickpocket it")
	var shape := t.get_node_or_null("CollisionShape3D") as CollisionShape3D
	assert_not_null(shape, "the auto pickpocket Talkable needs a hitbox for PickupRay's talk-layer ray")
	assert_true(shape.shape is BoxShape3D, "the auto pickpocket hitbox uses the same simple box shape as the component prefab")
	var size := (shape.shape as BoxShape3D).size
	assert_true(size.x > 0.0 and size.y > 0.0 and size.z > 0.0,
		"the auto pickpocket hitbox must be a real volume (got %s) — a flat box can never be hit by the look-at ray" % size)
	assert_true(size.y > size.x and size.y > size.z,
		"the hitbox is body-shaped, taller than it is wide (got %s), so aiming anywhere on a standing NPC reaches it" % size)
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

# --- Held-gun anchor: the HANDS first, the authored offset as the fallback ------------------------------
# The weapon view-model hangs off `_muzzle`, a Marker3D on the NPC ROOT, and everything downstream (shot and
# laser origin, tracer, attack.muzzle, the muzzle FX) reads that marker's descendants. Two anchoring rules,
# in priority order, and both are pinned below:
#   1. weapon_in_hands (default) -> the grip the swapped ARMS currently form (BodyModelSwap.weapon_grip_position).
#      The arm pose already bakes in the seated drop, so this supersedes the posture-offset hack for any rig
#      that HAS arms.
#   2. no arms / feature off -> the authored `muzzle_offset`, ridden down by the body's posture offset, which
#      is the pre-hands behaviour a bare mob and every unit-test rig still gets.

## A BodyModelSwap with a real ARM PAIR, off-tree: two bare Node3D "arms" carrying a mesh so the reach measures,
## placed by the swap's own _apply_arm_transform. Returns the swap (already childed to `n`).
func _swap_with_arms(n: Node, arm_pos: Vector3, hold_pitch: float) -> Node:
	var bms = load("res://scripts/components/body_model_swap.gd").new()
	bms.arm_position = arm_pos
	bms.arm_rotation = Vector3(90.0, 0.0, 0.0)   # the shipped rig: the arm model's +Z hand axis is turned DOWN
	bms.arm_scale = 1.0
	bms.arm_hold_pitch = hold_pitch
	n.add_child(bms)
	for side in 2:
		var arm := Node3D.new()
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.1, 0.1, 2.0)
		mi.mesh = box
		mi.position = Vector3(0.0, 0.0, 1.0)     # so the farthest AABB corner (the "hand") is ~2 m down local +Z
		arm.add_child(mi)
		bms.add_child(arm)
		if side == 0:
			bms._arm_left = arm
		else:
			bms._arm_right = arm
	# _apply_arm_transform writes the REST pose (arms hanging); the HOLD pitch only reaches the arms through
	# _animate_limbs, which needs a live _process. Pose them by hand at the hold angle — the same expression
	# _animate_limbs writes — so these off-tree asserts describe the pose a gun is actually carried in.
	bms._apply_arm_transform()
	bms._arm_left.transform = bms._arm_pose(bms.arm_rotation + Vector3(hold_pitch, 0.0, 0.0))
	bms._arm_right.transform = bms._reflect() * bms._arm_pose(bms.arm_rotation + Vector3(hold_pitch, 0.0, 0.0))
	return bms

func test_weapon_anchor_sits_at_the_grip_the_arms_form() -> void:
	var n = load(NPC_PATH).new()
	n.muzzle_offset = Vector3(0.1, 0.2, 0.3)   # deliberately non-zero: with hands available it must be IGNORED
	var muzzle := Marker3D.new()
	n.add_child(muzzle)
	n._muzzle = muzzle
	var bms = _swap_with_arms(n, Vector3(-0.27, 0.155, -0.05), -78.0)
	n._sync_weapon_anchor(0.016)
	var grip: Variant = bms.weapon_grip_position()
	assert_true(grip is Vector3, "a swap with arms must offer a grip point")
	assert_almost_eq(muzzle.position, grip as Vector3, Vector3.ONE * 0.0001,
		"weapon_in_hands -> the anchor IS the arms' grip, not the authored muzzle_offset")
	# The grip is on the body centreline (the two hands mirror across X) and OUT IN FRONT of the shoulders,
	# which is the whole point: the gun stops floating at the belly while the arms reach past it.
	assert_almost_eq((grip as Vector3).x, 0.0, 0.0001, "two mirrored hands meet on the centreline")
	assert_gt((grip as Vector3).z, bms.arm_position.z, "and the grip is forward of the shoulder, in the hands")
	n.free()

func test_weapon_anchor_grip_rises_with_the_hold_pitch() -> void:
	# arm_hold_pitch now decides WHERE THE GUN IS, not just how the arms look: a higher hold must lift the grip.
	var low = load(NPC_PATH).new()
	var low_muzzle := Marker3D.new()
	low.add_child(low_muzzle)
	low._muzzle = low_muzzle
	_swap_with_arms(low, Vector3(-0.27, 0.155, -0.05), -50.0)
	low._sync_weapon_anchor(0.016)
	var high = load(NPC_PATH).new()
	var high_muzzle := Marker3D.new()
	high.add_child(high_muzzle)
	high._muzzle = high_muzzle
	_swap_with_arms(high, Vector3(-0.27, 0.155, -0.05), -90.0)
	high._sync_weapon_anchor(0.016)
	assert_gt(high_muzzle.position.y, low_muzzle.position.y,
		"raising arm_hold_pitch toward level (-90) lifts the grip, and the gun with it")
	low.free()
	high.free()

func test_weapon_anchor_falls_back_to_the_posture_offset_without_arms() -> void:
	# An armless swap (a bare mob, or a swap that has not rebuilt) keeps the pre-hands behaviour EXACTLY: the
	# authored anchor, ridden down by the seated drop so a seated guard's rifle doesn't float at standing height.
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
	assert_null(bms.weapon_grip_position(), "no arm nodes -> no grip to offer")
	n.sitting = false
	n._sync_weapon_anchor(0.016)
	assert_eq(muzzle.position, n.muzzle_offset, "standing -> the gun sits at its authored hand anchor")
	n.sitting = true
	n._sync_weapon_anchor(0.016)
	assert_eq(muzzle.position, n.muzzle_offset + bms.posture_offset(),
		"seated -> the anchor drops by the SAME offset the visible body does, so the gun stays in the hands")
	assert_lt(muzzle.position.y, n.muzzle_offset.y, "and that means it actually moves DOWN onto the seated body")
	n.free()

func test_weapon_in_hands_off_keeps_the_authored_anchor() -> void:
	# The per-NPC escape hatch: a designer who has hand-tuned muzzle_offset can switch the hands off and get
	# byte-identical placement back, even on a rig that HAS arms.
	var n = load(NPC_PATH).new()
	n.muzzle_offset = Vector3(0.1, 0.2, 0.3)
	n.weapon_in_hands = false
	var muzzle := Marker3D.new()
	n.add_child(muzzle)
	n._muzzle = muzzle
	_swap_with_arms(n, Vector3(-0.27, 0.155, -0.05), -78.0)
	n._sync_weapon_anchor(0.016)
	assert_eq(muzzle.position, n.muzzle_offset, "weapon_in_hands off -> the authored anchor, arms or not")
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
	n._sync_weapon_anchor(0.016)
	assert_eq(muzzle.position, n.muzzle_offset, "so the hand anchor is untouched")
	n.free()

# --- The held view-model must render as a WORLD object, not as a view model ------------------------------
# A `view_model` scene is authored for the PLAYER's rig: it draws from a dedicated camera inside its own
# SubViewport (ViewModelCamera.VIEW_MODEL_LAYER = 4, stripped from the main camera's cull_mask) and composites
# over the finished frame — which is exactly what stops your own gun clipping into a wall, and exactly what
# makes an NPC's copy of the same mesh draw THROUGH one. ak_472.tscn authors `layers = 4` on its receiver mesh,
# so every SMG raider was a rifle visible through cover. `_make_held_model_world_renderable` is the correction,
# the twin of `WorldItem._make_world_renderable` for the dropped copy. Pure static -> testable off-tree.

func _no_depth_mesh(layer: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.no_depth_test = true
	bm.material = mat
	mi.mesh = bm
	mi.layers = layer
	return mi

func test_held_model_is_moved_to_the_world_layer_and_depth_tested() -> void:
	var root := _no_depth_mesh(4)          # the view-model layer, as ak_472.tscn authors it
	var child := _no_depth_mesh(4)
	root.add_child(child)
	NPC._make_held_model_world_renderable(root)
	for mi in [root, child]:
		assert_eq(mi.layers, 1, "every visible mesh of a held view-model must draw on the WORLD layer")
		var active: Material = mi.get_active_material(0)
		assert_false((active as BaseMaterial3D).no_depth_test,
			"...and must depth-test level geometry, or the gun draws through walls")
	root.free()

func test_held_model_fix_does_not_mutate_the_shared_material() -> void:
	# These materials are shared with the PLAYER's own view model and every other instance of the weapon.
	# Clearing no_depth_test in place would strip the no-depth draw off the gun in your hands too.
	var mi := _no_depth_mesh(4)
	var shared: BaseMaterial3D = mi.mesh.surface_get_material(0)
	NPC._make_held_model_world_renderable(mi)
	assert_true(shared.no_depth_test,
		"the shared material is untouched — the fix duplicates it onto a surface override instead")
	assert_true(mi.get_surface_override_material(0) != null, "and the override is what carries the corrected copy")
	mi.free()

func test_held_model_fix_leaves_ink_outline_tint_duplicates_alone() -> void:
	# InkOutline's tint duplicate must keep its ACTOR_TINT_LAYER bit: on layer 1 the main camera would draw
	# ink_tint.gdshader's raw R/G log-depth bytes as moving yellow/green stripe bands over the weapon.
	var dup := _no_depth_mesh(512)
	dup.set_meta(&"npc_tint_dup", true)
	NPC._make_held_model_world_renderable(dup)
	assert_eq(dup.layers, 512, "a tint duplicate keeps its own layer — it is not a visible mesh")
	dup.free()

# --- Held-gun AIM PITCH ---------------------------------------------------------------------------------
# _face_point turns the body in YAW ONLY, so before this the barrel stayed level while the bullets pitched.
# The elevation now lives on the hand anchor's local X rotation (pivoting the gun IN the grip) and is
# published to the arm rig via aim_pitch_degrees() so the hands swing with it. Two invariants matter more
# than the angle itself: it must ease (never snap), and it must be a LIE-FREE tell — zero unless the gun is
# out AND perception has actually sensed the foe.

func test_aim_pitch_is_zero_without_a_drawn_gun_or_a_sensed_foe() -> void:
	# The NPC stays off-tree (no _ready); only its hand anchor and the foe live in a small in-tree rig, because the
	# goal measures from the anchor's global position. Every gate is opened first (a drawn gun, a Perception that
	# was alerted to a foe well above the barrel) so the CONTROL goal is a real upward pitch, and then each gate
	# the name claims is closed ON ITS OWN — so a goal that stopped checking either one would stay pitched.
	var rig := Node3D.new()
	add_child_autofree(rig)
	var muzzle := Marker3D.new()
	rig.add_child(muzzle)
	var foe := Node3D.new()
	rig.add_child(foe)
	foe.position = Vector3(0.0, 20.0, 20.0)  # 45 degrees up, far outside any point-blank band
	var n = load(NPC_PATH).new()
	n._muzzle = muzzle
	n._target = foe
	var perception := Perception.new()
	n.add_child(perception)
	n._perception = perception
	var weapon := Weapon.new()
	var attack := Attack.new()
	weapon.add_child(attack)
	weapon.attack = attack
	n.add_child(weapon)
	n._weapon = weapon
	perception.alert_to(foe.position, foe)
	assert_true(n.is_holding_gun() and n.has_sensed_foe(),
		"precondition: the gun is out and perception has sensed the foe")
	assert_gt(n._aim_pitch_goal(), 0.0, "control: a drawn gun on a sensed foe above the barrel pitches it UP")

	attack.set_holstered(true)
	assert_almost_eq(n._aim_pitch_goal(), 0.0, 0.0001,
		"the same foe, still sensed, but the gun is HOLSTERED -> the barrel stays level (nothing is drawn to point)")
	attack.set_holstered(false)
	assert_gt(n._aim_pitch_goal(), 0.0, "control: drawing the gun again pitches it back up at the sensed foe")

	perception.forget()
	assert_true(n.is_holding_gun(), "precondition: the gun is still drawn")
	assert_almost_eq(n._aim_pitch_goal(), 0.0, 0.0001,
		"the gun is drawn and the foe still stands there, but perception FORGOT it -> level: the pitch is no tell for a foe it has not sensed")
	n.free()

func test_aim_pitch_eases_toward_its_goal_and_publishes_degrees() -> void:
	# The ease is the same exponential shape the body turn uses; step it by hand and assert it CONVERGES rather
	# than jumping, and that the public degrees read tracks the stored radians (the arm rig reads that seam).
	var n = load(NPC_PATH).new()
	var muzzle := Marker3D.new()
	n.add_child(muzzle)
	n._muzzle = muzzle
	n._aim_pitch = deg_to_rad(40.0)
	n._sync_weapon_anchor(0.05)   # goal is 0 here (no gun / no foe), so this must decay toward level
	assert_lt(n._aim_pitch, deg_to_rad(40.0), "the pitch eases DOWN toward the goal")
	assert_gt(n._aim_pitch, 0.0, "and it eases — it does not snap to the goal in one step")
	assert_almost_eq(n.aim_pitch_degrees(), rad_to_deg(n._aim_pitch), 0.0001,
		"aim_pitch_degrees() is the same angle the anchor carries, in degrees")
	assert_almost_eq(muzzle.rotation.x, -n._aim_pitch, 0.0001,
		"the anchor pitches by MINUS the elevation: the model faces +Z, so a negative X rotation tilts it UP")
	n.free()

func test_aim_elevation_is_signed_clamped_and_degenerate_safe() -> void:
	# Pure static, so the angle itself is testable without a weapon hub, a Perception or a tree.
	var origin := Vector3(0.0, 1.5, 0.0)
	assert_almost_eq(NPC.aim_elevation(origin, origin + Vector3(0.0, 0.0, 5.0), 75.0), 0.0, 0.0001,
		"a target dead level is zero elevation")
	assert_almost_eq(NPC.aim_elevation(origin, origin + Vector3(0.0, 5.0, 5.0), 75.0), deg_to_rad(45.0), 0.0001,
		"5 m up and 5 m out is 45 degrees UP, and up is POSITIVE")
	assert_almost_eq(NPC.aim_elevation(origin, origin + Vector3(0.0, -5.0, 5.0), 75.0), deg_to_rad(-45.0), 0.0001,
		"and 5 m down is the same angle negated")
	assert_almost_eq(NPC.aim_elevation(origin, origin + Vector3(0.0, 40.0, 0.5), 75.0), deg_to_rad(75.0), 0.0001,
		"a foe almost straight overhead clamps, so the barrel never folds back through the chest")
	assert_almost_eq(NPC.aim_elevation(origin, origin + Vector3(0.0, -40.0, 0.5), 75.0), deg_to_rad(-75.0), 0.0001,
		"and the clamp is symmetric downward")
	assert_almost_eq(NPC.aim_elevation(origin, origin, 75.0), 0.0, 0.0001,
		"a target standing exactly on the muzzle is level, never a NaN written into the anchor")

func test_point_blank_fade_is_zero_behind_the_barrel_and_full_past_the_band() -> void:
	# Pure static: the fade the laser beam (distance = aim point ahead of the barrel tip) and the barrel pitch
	# (distance = flat run from the grip) both ease out over. A target AT or BEHIND the tip must give exactly
	# zero — that is the case that used to spin the beam — and anything past the band must be untouched.
	assert_almost_eq(NPC.point_blank_fade(-1.0, 0.75), 0.0, 0.0001, "behind the barrel tip: no beam at all")
	assert_almost_eq(NPC.point_blank_fade(0.0, 0.75), 0.0, 0.0001, "exactly on the tip: still nothing")
	assert_almost_eq(NPC.point_blank_fade(0.75, 0.75), 1.0, 0.0001, "at the band edge the fade is complete")
	assert_almost_eq(NPC.point_blank_fade(10.0, 0.75), 1.0, 0.0001, "far out the beam is at full brightness")
	var mid := NPC.point_blank_fade(0.375, 0.75)
	assert_true(mid > 0.0 and mid < 1.0, "mid-band is a partial fade, not a pop (got %s)" % mid)
	assert_true(NPC.point_blank_fade(0.2, 0.75) < NPC.point_blank_fade(0.5, 0.75),
		"the fade is monotonic across the band")
	assert_almost_eq(NPC.point_blank_fade(1.0, 0.0), 1.0, 0.0001,
		"a zero band never divides by zero: anything ahead is simply full")

func test_point_blank_beam_fade_is_full_off_tree() -> void:
	# A bare .new() NPC has no hand anchor in a tree, so there is no barrel to judge "ahead" against: the beam
	# path must keep the old full-brightness behaviour rather than hide the laser on every off-tree NPC.
	var n = load("res://scripts/npc/npc.gd").new()
	assert_almost_eq(n._point_blank_beam_fade(Vector3.ZERO, Vector3(0.0, 0.0, 5.0)), 1.0, 0.0001,
		"no anchor -> full brightness (the old path)")
	n.free()

func test_npc_weapon_pitch_defaults_are_sane() -> void:
	var n = load(NPC_PATH).new()
	assert_true(n.weapon_in_hands, "SHIP DECISION: NPCs carry their weapon in their hands by default")
	assert_true(n.weapon_aim_pitch, "SHIP DECISION: and point it at what they are aiming at by default")
	assert_true(n.weapon_aim_pitch_limit > 0.0 and n.weapon_aim_pitch_limit < 90.0,
		"the pitch clamp must be a real angle short of vertical (got %s): at 90+ the barrel folds back through the chest" % n.weapon_aim_pitch_limit)
	assert_gt(n.weapon_aim_pitch_speed, 0.0, "a zero ease rate would freeze the barrel level forever")
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
# run scripts/tools/probes/muzzle_smoke_qa_shots.gd (its NPC section prints QA_NPC_SCALE and shoots the barrel).
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
	# A stand-in for WeaponData.npc_held_display_scale (currently 2.6 by default, retuned per weapon), which
	# _build_weapon_mesh multiplies onto the MESH. The exact number does not matter here — what is being pinned
	# is that _unscale_muzzle_fx cancels WHATEVER the chain composes — but keep it above 1 so the correction it
	# has to make is a real one.
	var boost := 2.6
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

func test_build_muzzle_fx_hangs_every_emitter_at_world_scale_one() -> void:
	# The regression the unit tests above cannot see: a FOURTH emitter added to _build_muzzle_fx without its
	# _unscale_muzzle_fx line (or a cancel handed the wrong node). Nothing would complain at runtime — it would
	# simply be born the wrong size on every weapon. So drive the REAL builder over a real barrel chain and judge
	# EVERY node it hangs on the anchor, whatever it is and however many there are. Two anchors: the gun's own
	# Muzzle marker (baking a scale of its own on top of the mesh, like the spray can) and the mesh-root fallback
	# for a model with no marker (the pistol's millimetre root x the display boost). The NPC stays off-tree; its
	# weapon hub is a bare Weapon + Attack (the builder only reads `_weapon.attack` and connects its signals).
	for with_marker in [true, false]:
		var n = load(NPC_PATH).new()
		var weapon := Weapon.new()
		var attack := Attack.new()
		weapon.attack = attack
		n._weapon = weapon
		var hand := Node3D.new()
		add_child_autofree(hand)
		var mesh := Node3D.new()
		mesh.scale = Vector3.ONE * 2.6 if with_marker else Vector3.ONE * (0.001 * 2.6)
		hand.add_child(mesh)
		n._weapon_mesh = mesh
		var anchor: Node3D = mesh
		if with_marker:
			var marker := Marker3D.new()
			marker.scale = Vector3.ONE * 0.015
			mesh.add_child(marker)
			n._gun_muzzle = marker
			anchor = marker
		var label := "Muzzle marker anchor" if with_marker else "mesh-root fallback anchor"
		n._build_muzzle_fx()
		assert_gt(anchor.get_child_count(), 0, "%s: _build_muzzle_fx must hang its emitters on the barrel" % label)
		for c in anchor.get_children():
			var s: Vector3 = (c as Node3D).global_transform.basis.get_scale()
			assert_true(absf(s.x - 1.0) < EPS and absf(s.y - 1.0) < EPS and absf(s.z - 1.0) < EPS,
				"%s: '%s' must come out at WORLD scale 1.0 (got %s) — otherwise it inherits the gun's display scale, which on the pistol is ~0.0026x and invisible" % [label, c.name, s])
		assert_true(attack.shell_drop != null and attack.shell_drop.get_parent() == anchor,
			"%s: Attack's casing hook must point at the casing hung on THIS gun, so casing_size_scale resizes what the player sees" % label)
		n._weapon = null
		n.free()
		attack.free()
		weapon.free()

func test_build_muzzle_fx_builds_nothing_without_a_weapon_hub() -> void:
	# The guard: with no Weapon there is no Attack to fire the effects, so nothing may be half-wired onto the barrel.
	# Control: the same rig WITH a hub gets emitters (see the test above), so the empty anchor is the guard's doing.
	var n = load(NPC_PATH).new()
	var hand := Node3D.new()
	add_child_autofree(hand)
	var marker := Marker3D.new()
	hand.add_child(marker)
	n._gun_muzzle = marker
	n._build_muzzle_fx()
	assert_eq(marker.get_child_count(), 0, "no weapon hub -> no muzzle FX are built onto the barrel")
	var weapon := Weapon.new()
	var attack := Attack.new()
	weapon.attack = attack
	n._weapon = weapon
	n._build_muzzle_fx()
	assert_gt(marker.get_child_count(), 0, "control: the same barrel with a weapon hub does get its emitters")
	n._weapon = null
	n.free()
	attack.free()
	weapon.free()

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

# --- Assist thanks ("Hey, thanks!") ------------------------------------------------------------------------
# NPC.thank_for_assist() -> NpcVoice.thank_for_assist() gates the speaker, resolves the line (BarkSet.thanks over
# the THANKS_LINES fallback) and round-trips through NPC._emit_bark -> NpcVoice.emit. Only emit() is replaced here:
# it is the awaited body (reaction delay -> bubble -> TTS) that needs a tree and a player. Everything upstream of
# it is the real code, driven on an off-tree NPC.

const THANKS_LINE := "Owe you one."

## Records what the NPC was asked to say instead of floating a bubble.
class _RecordingVoice:
	extends NpcVoice
	var said: Array[String] = []
	var voices: Array[VoiceData] = []
	func emit(line: String, voice: VoiceData) -> void:
		said.append(line)
		voices.append(voice)

## A living, FRIENDLY off-tree NPC with a Talkable (the thanks needs one to speak through) and a recording voice
## whose BarkSet carries `thanks`. Returns [npc, voice, talkable]; freeing the npc frees all three.
func _thankful_npc(thanks: Array[String]) -> Array:
	var n = load(NPC_PATH).new()
	n.disposition = Disposition.Kind.FRIENDLY
	n.hp = n.max_hp
	var talkable := Talkable.new()
	talkable.voice = VoiceData.new()
	n.add_child(talkable)
	var voice := _RecordingVoice.new()
	voice.host = n
	var barks := BarkSet.new()
	barks.thanks = thanks
	voice._bark_set = barks
	n.add_child(voice)
	n._voice = voice
	return [n, voice, talkable]

## A typed line pool for BarkSet.thanks: one line, or none for "".
func _lines(line: String) -> Array[String]:
	var out: Array[String] = []
	if not line.is_empty():
		out.append(line)
	return out

func test_assist_thanks_speaks_the_authored_line_in_the_talkables_voice() -> void:
	var rig := _thankful_npc(_lines(THANKS_LINE))
	var n = rig[0]
	var voice: _RecordingVoice = rig[1]
	var talkable: Talkable = rig[2]
	n.thank_for_assist()
	assert_true(voice.said.size() == 1 and voice.said[0] == THANKS_LINE,
		"a friendly NPC the player just helped says the line its BarkSet authors for thanks (said %s)" % [voice.said])
	assert_true(voice.voices.size() == 1 and voice.voices[0] == talkable.voice,
		"and says it in its Talkable's voice, so the thanks sounds like the same person the player talks to")
	n.free()

func test_assist_thanks_with_nothing_authored_is_silent() -> void:
	# Speech is authored content (a BarkSet .tres), never a code literal: with an EMPTY BarkSet the code-side
	# fallback must contribute no words, and the emitter must turn that empty line into no bubble at all.
	var rig := _thankful_npc(_lines(""))
	var n = rig[0]
	var voice: _RecordingVoice = rig[1]
	n.thank_for_assist()
	assert_true(voice.said.size() == 1 and voice.said[0] == "",
		"SHIP DECISION: with no BarkSet line authored the thanks resolves to an empty line — no hardcoded speech in npc.gd (said %s)" % [voice.said])
	var real = NpcVoice.new()
	real.host = n
	add_child_autofree(real)   # in-tree only for the control's reaction-delay timer below
	n._bark_until_msec = -100000
	real.emit("", null)
	assert_eq(n._bark_until_msec, -100000,
		"an empty line is dropped before the bubble latch, so an unauthored thanks shows no empty balloon and speaks nothing")
	# Control: the same emitter DOES arm the one-bubble latch for a real line, so the untouched latch above is the
	# empty-line guard's doing. hp 0 makes the post-delay lifecycle guard drop it before any bubble / TTS / player read.
	n.hp = 0.0
	real.emit(THANKS_LINE, null)
	assert_gt(n._bark_until_msec, -100000, "control: a non-empty line arms the bubble latch")
	await wait_seconds(0.2)   # let the reaction-delay coroutine run out (it bails on hp 0) before the NPC is freed
	n.free()

func test_assist_thanks_never_comes_from_a_hostile_dead_or_talkable_less_npc() -> void:
	var control := _thankful_npc(_lines(THANKS_LINE))
	control[0].thank_for_assist()
	assert_eq((control[1] as _RecordingVoice).said.size(), 1,
		"control: a living friendly NPC with a Talkable does thank the player")
	control[0].free()

	var hostile := _thankful_npc(_lines(THANKS_LINE))
	hostile[0].disposition = Disposition.Kind.HOSTILE
	hostile[0].thank_for_assist()
	assert_eq((hostile[1] as _RecordingVoice).said.size(), 0,
		"a HOSTILE NPC never thanks the player for an assist — it is still an enemy")
	hostile[0].free()

	var dead := _thankful_npc(_lines(THANKS_LINE))
	dead[0]._dead = true
	dead[0].thank_for_assist()
	assert_eq((dead[1] as _RecordingVoice).said.size(), 0, "a dead NPC says nothing")
	dead[0].free()

	var mute := _thankful_npc(_lines(THANKS_LINE))
	var t: Talkable = mute[2]
	mute[0].remove_child(t)
	t.free()
	mute[0].thank_for_assist()
	assert_eq((mute[1] as _RecordingVoice).said.size(), 0,
		"an NPC with no Talkable has no voice to thank through, so it stays silent instead of erroring")
	mute[0].free()

func test_npc_has_assist_and_bark_methods() -> void:
	# Named-surface pin that NpcVoice's header points at: thank_for_assist is the assist-thanks entry point and
	# _emit_bark the single emitter every NpcVoice trigger round-trips through. The test_assist_thanks_* tests above
	# DRIVE both off-tree; this stays as the cheap has_method pin CLAUDE.md allows for NPC surfaces.
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
