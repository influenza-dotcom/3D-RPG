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
