extends GutTest

## Focused GUT suite for the @abstract Character base (scripts/player/character.gd).
##
## COVERS (each assert message states the invariant it guards):
##   - killed_by_only_crits(): fresh=false; latches true through an all-crit kill,
##     false after any non-crit hit, and the false-latch is one-way (crit-then-body).
##   - take_damage() HP arithmetic on the NON-LETHAL path (hp -= amount, no clamp) and
##     its damaged(current_hp, max_hp) signal.
##   - heal() partial restore and clamp-at-max_hp.
##   - hp == max_hp after _ready(); the _dead latch makes take_damage a no-op.
##   - Authored defaults as INVARIANTS, not numbers: a default actor spawns alive with a positive pool, and the
##     default hit zones split the 2 m capsule into head / torso / legs (a retune that keeps that shape passes).
##   - reset_for_reuse(): a pooled body comes back alive, at full HP, carrying no residual blast impulse, and a
##     body shot from its previous life no longer disqualifies it from the all-crit reward.
##   - is_headshot() head-zone threshold; is_off_guard() base false.
##   - Weapon-host aim contract (get_aim_origin/direction/basis) on a MOVED and TURNED body.
##   - get_hit_flash() base null; the base no-op hooks exist and are inert when CALLED (indicate_damage_from,
##     on_dealt_hit, on_scored_kill — the last one driven through the real lethal branch — on_weapon_fired,
##     on_air_dash).
##   - The movement guard reports no live physics space on a bare off-tree actor.
##
## DELIBERATELY SKIPPED (would crash / mutate the world in a unit run, see character.gd):
##   - The LETHAL take_damage branch (hp<=0) -> gore()+die(): spawns physics gibs/decals
##     into get_tree().root, raycasts the world, reads GameSettings, queue_free()s. Every
##     take_damage test below keeps max_hp huge / damage tiny so hp never reaches 0.
##     ONE EXCEPTION, at the bottom of this file: the kill-cue tests DO run the lethal branch,
##     through a _KillSpy subclass that neuters _begin_death() — everything the branch does
##     BEFORE that (bounty, killer resolve, the on_scored_kill cue) is safe off-tree.
##   - gore()/spawn_gibs()/spawn_blood_decal()/spawn_dust()/flash_red() real tween/
##     _setup_overlay_chain with a real mesh/apply_velocity/apply_blast/gravity/
##     _physics_process/_push_interactables/_apply_fall_damage/_notify_nearby_players_of_death:
##     all need a live physics frame, autoloads, particles, or a real ShaderMaterial.
##     (has_method on spawn_dust / _notify_nearby_players_of_death is already in test_smoke.)
##
## Character is @abstract, so it cannot be instantiated directly. A fresh inner concrete
## stub (_Stub, distinct from test_smoke's _ConcreteCharacter to avoid a merge clash) is
## used. _ready() only assigns hp=max_hp and calls _setup_overlay_chain(), which
## early-returns on a mesh-less stub, so add_child_autofree(_Stub) is side-effect-safe;
## exported defaults are read via load(path).new() WITHOUT add_child (so _ready never runs).

const CHARACTER_PATH := "res://scripts/player/character.gd"

## Concrete stand-in for the @abstract Character base. Named _Stub (not _ConcreteCharacter)
## so this file can coexist with test_smoke.gd's stub if the suites are ever merged.
class _Stub extends Character:
	pass

## First entry in get_property_list() whose name matches, else {}.
func _property(obj: Object, prop_name: String) -> Dictionary:
	for p in obj.get_property_list():
		if p.get("name", "") == prop_name:
			return p
	return {}


func test_encumbrance_is_gradual_with_load() -> void:
	# Gradual (not a flat threshold): no penalty under the free fraction, then a LINEAR ramp to the floor
	# multipliers at full load. Built off-tree (no _ready): set the backpack + capacity by hand.
	var c := _Stub.new()
	c.inventory = CharacterInventory.new()
	c.carry_capacity = 20.0  # free up to ratio 0.25 (weight 5); penalties max at ratio 1.0 (weight 20)
	var light := Item.new()
	light.weight = 4.0  # ratio 0.2 — under the ¼ free fraction
	c.inventory.add(light, 1)
	assert_almost_eq(c.heaviness(), 0.0, 0.0001, "ratio 0.2 (< ¼) -> zero heaviness")
	assert_almost_eq(c.encumbrance_move_multiplier(), 1.0, 0.0001, "under the free fraction -> no speed penalty")
	assert_almost_eq(c.encumbrance_jump_multiplier(), 1.0, 0.0001, "under the free fraction -> full jump")
	assert_almost_eq(c.encumbrance_launch_multiplier(), 1.0, 0.0001, "under the free fraction -> full launch")
	assert_false(c.is_encumbered(), "under capacity -> not flagged ENCUMBERED")
	# Midpoint: total 12.5 -> ratio 0.625 -> heaviness exactly 0.5 (halfway from ¼ to full).
	var heavy := Item.new()
	heavy.weight = 8.5  # 4.0 + 8.5 = 12.5
	c.inventory.add(heavy, 1)
	assert_almost_eq(c.heaviness(), 0.5, 0.0001, "ratio 0.625 -> heaviness 0.5 (the linear midpoint)")
	assert_almost_eq(c.encumbrance_move_multiplier(), lerpf(1.0, c.min_load_speed_mult, 0.5), 0.0001, "midpoint -> half the speed penalty")
	# Full load: total 20.0 -> ratio 1.0 -> every penalty at its floor.
	var more := Item.new()
	more.weight = 7.5  # 12.5 + 7.5 = 20.0
	c.inventory.add(more, 1)
	assert_almost_eq(c.heaviness(), 1.0, 0.0001, "at full capacity -> max heaviness")
	assert_almost_eq(c.encumbrance_move_multiplier(), c.min_load_speed_mult, 0.0001, "full load -> slowest move")
	assert_almost_eq(c.encumbrance_jump_multiplier(), c.min_load_jump_mult, 0.0001, "full load -> lowest jump")
	assert_almost_eq(c.encumbrance_launch_multiplier(), c.min_load_launch_mult, 0.0001, "full load -> least launch")
	light = null
	heavy = null
	more = null
	c.inventory.free()
	c.free()


func test_at_capacity_flag_off_but_penalty_maxed() -> void:
	# is_encumbered() stays the strict over-capacity FLAG (a load EQUAL to capacity isn't flagged), but the
	# GRADUAL penalty has already maxed out at capacity.
	var c := _Stub.new()
	c.inventory = CharacterInventory.new()
	c.carry_capacity = 4.0
	var it := Item.new()
	it.weight = 2.0
	c.inventory.add(it, 2)  # exactly 4.0 == capacity
	assert_false(c.is_encumbered(), "weight EQUAL to capacity is not FLAGGED encumbered (strict >)")
	assert_almost_eq(c.encumbrance_move_multiplier(), c.min_load_speed_mult, 0.0001, "but at capacity the gradual penalty is already at its floor")
	c.inventory.free()
	c.free()
	it = null


func test_current_carry_weight_reflects_backpack() -> void:
	var c := _Stub.new()
	assert_eq(c.current_carry_weight(), 0.0,
		"with no backpack (no _ready), carry weight is 0")
	assert_false(c.is_encumbered(), "a backpack-less actor is never encumbered")
	c.inventory = CharacterInventory.new()
	var it := Item.new()
	it.weight = 1.25
	c.inventory.add(it, 2)
	assert_almost_eq(c.current_carry_weight(), 2.5, 0.0001,
		"current_carry_weight mirrors the backpack's total_weight")
	c.inventory.free()
	c.free()
	it = null


# --- Authored defaults, pinned as the shape the design needs (the numbers themselves are designer knobs) ---

## max_hp is retuned freely (it was 10 until 2026-06), so its NUMBER is not the contract. What every retune must keep:
## the default pool is positive, and an actor spawned with it enters the world on exactly that pool —
## _apply_stats floors max_hp at 1, so a non-positive default would silently spawn every un-tuned actor on a 1 HP
## pool nobody authored.
func test_a_default_authored_actor_spawns_alive() -> void:
	var raw = load(CHARACTER_PATH).new()  # no add_child => _ready never runs: the raw exported default
	assert_gt(raw.max_hp, 0.0,
		"Character.max_hp must default to a POSITIVE pool — _apply_stats floors max_hp at 1, so a non-positive default would silently spawn every un-tuned actor on a 1 HP pool nobody authored")
	var authored: float = raw.max_hp
	raw.free()
	var c := _Stub.new()
	add_child_autofree(c)  # the default CharacterStats sheet adds 0 max HP, so the spawned pool is the authored one
	assert_eq(c.hp, authored,
		"a default-authored actor must enter the world with exactly the authored pool - the 1 HP floor in _apply_stats must not have had to rescue it")
	assert_true(c.is_alive(), "a default-authored actor must spawn fightable (is_alive), not as a corpse")


## The zone knobs (head_local_y / leg_local_y / arm_local_x) are per-enemy tuning, so what is pinned is the layout they
## must produce on the 2 m capsule centred on the origin (local y -1..+1) every attacker aims at: the top cap is the
## head, the centre is the torso, the bottom is the legs — and is_headshot agrees with body_part_at about the head.
func test_default_hit_zones_split_the_capsule_into_head_torso_and_legs() -> void:
	var c := _Stub.new()
	add_child_autofree(c)  # identity transform: world y == local y
	assert_gt(c.head_local_y, c.leg_local_y,
		"the head threshold must sit ABOVE the legs threshold, or the torso band is empty and every body shot is a limb/head hit")
	var top_cap := Vector3(0.0, 0.9, 0.0)
	var centre := Vector3.ZERO
	var shins := Vector3(0.0, -0.9, 0.0)
	assert_eq(c.body_part_at(top_cap), Character.BodyPart.HEAD, "a hit on the capsule's top cap (y 0.9) must be a HEAD hit")
	assert_true(c.is_headshot(top_cap),
		"...and is_headshot must agree, or the headshot multiplier and the head weakpoint disagree about the same hit")
	assert_eq(c.body_part_at(centre), Character.BodyPart.TORSO, "centre mass (y 0) must be a TORSO hit")
	assert_false(c.is_headshot(centre), "a centre-mass hit must never earn the headshot multiplier")
	assert_eq(c.body_part_at(shins), Character.BodyPart.LEGS, "a hit near the capsule's bottom (y -0.9) must be a LEGS hit")


## The pool reuse path is where "a fresh actor carries no residual blast impulse" can actually break: a pooled body
## that died mid-rocket-jump must not launch its next life, stay latched dead, or keep the last life's damage.
func test_pooled_reuse_comes_back_alive_with_no_residual_blast() -> void:
	var c := _Stub.new()
	c.max_hp = 10.0
	add_child_autofree(c)
	c.take_damage(3.0, false)
	c.explosion_velocity = Vector3(0.0, 12.0, -4.0)  # blasted...
	c.velocity = Vector3(2.0, 5.0, 0.0)
	c._dead = true                                   # ...and killed, mid-flight
	c.reset_for_reuse()
	assert_eq(c.explosion_velocity, Vector3.ZERO,
		"a reused body must carry NO residual blast impulse, or its next life spawns already flying")
	assert_eq(c.velocity, Vector3.ZERO, "a reused body must not keep the previous life's momentum")
	assert_eq(c.hp, 10.0, "a reused body comes back at full health (max_hp), not with the last life's 7")
	assert_true(c.is_alive(), "a reused body must be fightable again — the death latch has to clear")
	assert_false(c.killed_by_only_crits(),
		"the new life has taken no hits, so it cannot already qualify for the all-crit reward")
	# The setup's body shot disqualified the LAST life from the all-crit bounty. A new life that opens on a headshot
	# must qualify again (hp 10 -> 9 keeps this on the non-lethal branch), or a pooled NPC can never pay it out.
	c.take_damage(1.0, true)
	assert_true(c.killed_by_only_crits(),
		"a reused body's first headshot must count toward the all-crit reward: a body shot from the PREVIOUS life must not disqualify the new one")


func test_offtree_character_has_no_live_physics_space() -> void:
	var c := _Stub.new()
	assert_false(c._has_live_physics_space(),
		"a bare off-tree CharacterBody3D has no body space, so move_and_slide must stay guarded")
	c.free()


func test_mesh_asset_export_accepts_model_scene_or_mesh() -> void:
	var c = load(CHARACTER_PATH).new()
	var prop := _property(c, "mesh_asset")
	assert_false(prop.is_empty(), "Character exposes mesh_asset for imported model files")
	assert_eq(prop.get("hint", -1), PROPERTY_HINT_RESOURCE_TYPE,
		"mesh_asset uses a resource-type hint so model resources can be dropped in the inspector")
	assert_eq(prop.get("hint_string", ""), "PackedScene,Mesh",
		"mesh_asset accepts .glb/.gltf/.blend PackedScene imports and .obj Mesh imports")
	c.free()


func test_mesh_asset_builds_mesh_instance_for_obj_style_mesh() -> void:
	var c := _Stub.new()
	var box := BoxMesh.new()
	c.mesh_asset = box
	c.mesh_asset_position = Vector3(1.0, 2.0, 3.0)
	c.mesh_asset_rotation = Vector3(0.0, 90.0, 0.0)
	c.mesh_asset_scale = Vector3(2.0, 2.0, 2.0)
	add_child_autofree(c)
	assert_true(c.mesh is MeshInstance3D,
		"a Mesh resource, like an imported .obj, is wrapped in a MeshInstance3D and assigned to Character.mesh")
	var mi := c.mesh as MeshInstance3D
	assert_eq(mi.mesh, box, "the generated MeshInstance3D uses the assigned mesh resource")
	assert_eq(mi.position, Vector3(1.0, 2.0, 3.0), "mesh_asset_position is applied to the generated mesh")
	assert_eq(mi.rotation_degrees, Vector3(0.0, 90.0, 0.0), "mesh_asset_rotation is applied to the generated mesh")
	assert_eq(mi.scale, Vector3(2.0, 2.0, 2.0), "mesh_asset_scale is applied to the generated mesh")


func test_mesh_asset_instances_glb_style_packed_scene() -> void:
	var authored_root := Node3D.new()
	var authored_mesh := MeshInstance3D.new()
	authored_mesh.mesh = BoxMesh.new()
	authored_root.add_child(authored_mesh)
	authored_mesh.owner = authored_root
	var scene := PackedScene.new()
	assert_eq(scene.pack(authored_root), OK, "test fixture scene packs cleanly")
	var c := _Stub.new()
	c.mesh_asset = scene
	add_child_autofree(c)
	assert_true(c.mesh is Node3D,
		"a PackedScene resource, like an imported .glb, is instanced and assigned to Character.mesh")
	assert_true(c.mesh != authored_root, "mesh_asset creates a live instance, not the authored fixture node")
	assert_not_null(TalkHelpers.collect_meshes(c.mesh, null, true).front(),
		"the instanced scene carries mesh children for overlays/gore to target")
	authored_root.free()


# --- Base no-op / null hooks (called and checked inert, or a pure return value) ---

## damage_trace.gd and explosion_area.gd call this on every Character they hurt, and projectile.gd does too whenever its
## shooter is still alive, typed as Character, so an NPC victim lands on the base. Only the Player overrides it (the
## directional damage arc on its HUD); on the base it must be inert when actually called — attributed (a shooter
## passed) or not (an explosion) — or every hit on an NPC would double up its damage, kill it early or grow indicator
## nodes nobody sees.
func test_indicate_damage_from_is_base_noop() -> void:
	var c := _Stub.new()
	c.max_hp = 10.0
	add_child_autofree(c)
	var shooter := Node.new()
	watch_signals(c)
	var children_before := c.get_child_count()
	c.indicate_damage_from(Vector3(3.0, 0.0, 4.0))
	c.indicate_damage_from(Vector3(-2.0, 1.0, 0.0), shooter)
	assert_eq(c.hp, 10.0, "the base damage-indicator hook must not touch the victim's health")
	assert_true(c.is_alive(), "the base damage-indicator hook must not kill the victim")
	assert_signal_not_emitted(c, "damaged",
		"the base hook must not report a second hit — the take_damage that preceded it already emitted `damaged`")
	assert_signal_not_emitted(c, "died", "the base hook must not report a death")
	assert_eq(c.get_child_count(), children_before,
		"the base hook must build no indicator node — only the Player overrides it with HUD feedback")
	assert_true(is_instance_valid(shooter), "the base hook must leave the attributed shooter alone")
	shooter.free()


## damage_trace.gd tells EVERY wielder it landed a hit and explosion_area.gd duck-types the name. The base must exist AND
## be inert when actually called — an NPC wielder landing a shot must not lose health, die or grow feedback nodes.
func test_on_dealt_hit_is_base_noop() -> void:
	var c := _Stub.new()
	c.max_hp = 10.0
	add_child_autofree(c)
	assert_true(c.has_method("on_dealt_hit"),
		"Character must expose on_dealt_hit() so any wielder can be told it landed a hit without a Player-specific override")
	var children_before := c.get_child_count()
	c.on_dealt_hit(true, 0.25)
	c.on_dealt_hit(false, 1.0)
	assert_eq(c.hp, 10.0, "the base hit-confirm hook must not touch the WIELDER's health")
	assert_true(c.is_alive(), "the base hit-confirm hook must not kill the wielder")
	assert_eq(c.get_child_count(), children_before,
		"the base hook must spawn no hitmarker/feedback node — only the Player overrides it with HUD feedback")


## The kill-flash cue. take_damage's lethal branch fires it DUCK-TYPED on whoever _resolve_killer picked, and that
## is EVERY killer in the game — so an NPC that kills another NPC lands here too. It must therefore (a) exist on
## the base at all, or the has_method guard misses and the seam quietly stops working for anything that isn't a
## Player, and (b) do NOTHING on the base, or NPC-vs-NPC infighting would pour red across the player's sky.
## Both halves are asserted, through the REAL lethal branch: an NPC-style killer that overrides only reward_kill (so
## the base on_scored_kill is what the cue line reaches) kills a victim; the bounty proves the branch resolved that
## killer, and the killer comes out of it untouched. The behaviour that rides on it (once per victim, never a
## suicide, delayed credit) is pinned by the kill-cue tests at the bottom.
func test_on_scored_kill_is_base_noop() -> void:
	var killer := _BountyOnlyKiller.new()
	killer.max_hp = 50.0
	killer.hp = 50.0
	var victim := _kill_spy()
	assert_true(killer.has_method("on_scored_kill"),
		"Character must expose on_scored_kill() so take_damage's lethal branch (which has_method-gates it) can tell any killer it scored")
	victim.take_damage(999.0, false, killer)
	assert_eq(killer.rewarded, 1,
		"control: the lethal branch must have resolved this killer (it paid the bounty) — so the cue line ran on it too")
	assert_eq(killer.hp, 50.0, "the base kill cue must not touch the killer's health")
	assert_true(killer.is_alive(), "the base kill cue must not kill the killer")
	assert_eq(killer.get_child_count(), 0,
		"the base kill cue must build nothing — NPC-vs-NPC infighting reaches this hook and must never grow a flash")
	killer.free()
	victim.free()


## attack.gd calls on_weapon_fired on every wielder each shot and air_dash.gd duck-types on_air_dash, so both must exist
## on the base AND be inert when actually called: an NPC firing or dashing must not lose health, die or grow a
## feedback node (only the Player overrides them with recoil / camera-shake feedback).
func test_weapon_fire_and_launch_hooks_exist() -> void:
	var c := _Stub.new()
	c.max_hp = 10.0
	add_child_autofree(c)
	assert_true(c.has_method("on_weapon_fired"),
		"Character must expose on_weapon_fired() — a hosted Weapon calls it every shot, so an Enemy wielder needs no override")
	assert_true(c.has_method("on_air_dash"),
		"Character must expose on_air_dash() — the dash feedback hook the AirDash ability calls, as a base no-op")
	var children_before := c.get_child_count()
	c.on_weapon_fired(null)
	c.on_air_dash(0.5)
	assert_eq(c.hp, 10.0, "the base fire / dash hooks must not touch the wielder's health")
	assert_true(c.is_alive(), "the base fire / dash hooks must not kill the wielder")
	assert_eq(c.get_child_count(), children_before,
		"the base fire / dash hooks must build nothing — an NPC firing or dashing must never grow recoil or shake feedback nodes")


func test_get_hit_flash_base_returns_null() -> void:
	var c = load(CHARACTER_PATH).new()
	assert_null(c.get_hit_flash(),
		"get_hit_flash() base must return null so a Weapon skips the camera-space hit-flash for enemies (only the player has one)")
	c.free()


func test_is_off_guard_base_returns_false() -> void:
	var c = load(CHARACTER_PATH).new()
	assert_false(c.is_off_guard(),
		"is_off_guard() base must be false — the player is never an ambush target; only enemies override it for the sneak-attack bonus")
	c.free()


# --- _ready initialization (add_child so _ready runs; safe on a mesh-less stub) ---

func test_hp_equals_max_hp_after_ready() -> void:
	# add_child triggers _ready(), which sets hp = max_hp and calls _setup_overlay_chain()
	# (a no-op here: the stub has no `mesh`, so it early-returns before touching materials).
	var c := _Stub.new()
	add_child_autofree(c)
	assert_eq(c.hp, c.max_hp,
		"_ready() must initialize hp to max_hp so a freshly spawned actor starts at full health")


# --- killed_by_only_crits() state machine (large max_hp keeps every hit non-lethal) ---

func test_killed_by_only_crits_fresh_is_false() -> void:
	# No hits yet => _took_any_hit is false. The all-crit applause reward must NOT fire
	# on an actor that never took damage.
	var c := _Stub.new()
	add_child_autofree(c)
	assert_false(c.killed_by_only_crits(),
		"A fresh actor that took no damage must NOT qualify for the all-crit reward (_took_any_hit is still false)")


func test_killed_by_only_crits_true_after_crit_hit() -> void:
	# Raise max_hp BEFORE add_child so _ready sets hp=1000; a 1.0 crit leaves hp at 999>0,
	# so no die()/gore() branch runs.
	var c := _Stub.new()
	c.max_hp = 1000.0
	add_child_autofree(c)
	c.take_damage(1.0, true)
	assert_true(c.killed_by_only_crits(),
		"After only a crit hit, killed_by_only_crits() must be true — an all-headshot kill earns the applause reward")


func test_killed_by_only_crits_false_after_noncrit_hit() -> void:
	var c := _Stub.new()
	c.max_hp = 1000.0
	add_child_autofree(c)
	c.take_damage(1.0, false)
	assert_false(c.killed_by_only_crits(),
		"Any non-crit (body/fall/explosion) damage must disqualify the all-crit reward by latching _all_crits=false")


func test_killed_by_only_crits_noncrit_latches_after_crit() -> void:
	# Crit first, then a single body shot: the false-latch must be one-way.
	var c := _Stub.new()
	c.max_hp = 1000.0
	add_child_autofree(c)
	c.take_damage(1.0, true)
	c.take_damage(1.0, false)
	assert_false(c.killed_by_only_crits(),
		"A single mixed-in body shot must permanently disqualify the kill even after a prior crit (_all_crits=false is one-way)")


# --- take_damage HP arithmetic + damaged signal (non-lethal path only) ---

func test_take_damage_subtracts_amount_nonlethal() -> void:
	var c := _Stub.new()
	c.max_hp = 1000.0
	add_child_autofree(c)
	c.take_damage(7.0, false)
	assert_eq(c.hp, 993.0,
		"take_damage must subtract exactly the amount from hp (1000 - 7) before the death check, with no clamping on the non-lethal path")


# --- CT-2 mitigation: armour / damage_reduction / weakpoint zone mults ---------------------------------------

func test_mitigation_inert_by_default() -> void:
	var c := _Stub.new()
	c.max_hp = 1000.0
	add_child_autofree(c)
	assert_eq(c.armor_flat, 0.0, "no armour by default")
	assert_eq(c.damage_reduction, 0.0, "no damage reduction by default")
	assert_true(c.zone_damage_mult.is_empty(), "no weakpoints by default")
	c.take_damage(10.0, false)
	assert_almost_eq(c.hp, 990.0, 0.001, "defaults -> full damage (shipped behaviour unchanged)")


func test_armor_then_dr_mitigate_in_order() -> void:
	var c := _Stub.new()
	c.max_hp = 1000.0
	add_child_autofree(c)
	c.armor_flat = 2.0
	c.damage_reduction = 0.5
	c.take_damage(10.0, false)  # (10 - 2) * (1 - 0.5) = 4
	assert_almost_eq(c.hp, 996.0, 0.001, "armour soaks 2 off the top, then DR halves the rest: 10 -> 4 damage")


func test_armor_floors_at_zero_never_heals() -> void:
	var c := _Stub.new()
	c.max_hp = 1000.0
	add_child_autofree(c)
	c.armor_flat = 100.0  # bigger than the hit
	c.take_damage(10.0, false)
	assert_almost_eq(c.hp, 1000.0, 0.001, "armour larger than the hit -> 0 damage, never a heal")


func test_zone_damage_mult_at_weakpoint() -> void:
	var c := _Stub.new()
	add_child_autofree(c)
	assert_almost_eq(c.zone_damage_mult_at(Vector3.INF), 1.0, 0.001, "no weakpoints + an un-located hit -> 1.0")
	assert_almost_eq(c.zone_damage_mult_at(c.global_position), 1.0, 0.001, "empty map -> 1.0 everywhere")
	c.zone_damage_mult = {Character.BodyPart.TORSO: 3.0}
	assert_almost_eq(c.zone_damage_mult_at(c.global_position), 3.0, 0.001, "a torso weakpoint takes 3x (the body centre = torso)")
	assert_almost_eq(c.zone_damage_mult_at(Vector3.INF), 1.0, 0.001, "an un-located hit ignores weakpoints (no transform read)")
	c.zone_damage_mult = {Character.BodyPart.HEAD: 2.0}
	var head_hit := c.to_global(Vector3(0.0, c.head_local_y + 0.1, 0.0))
	assert_almost_eq(c.zone_damage_mult_at(head_hit), 2.0, 0.001, "a head-zone hit takes the head weakpoint mult")
	assert_almost_eq(c.zone_damage_mult_at(c.global_position), 1.0, 0.001, "...but a torso hit isn't the head weakpoint")


# --- CT-3 status-on-hit: the shared apply_status_effect entry point (weapons / consumables / NPCs) -----------

func test_perk_combat_bonus_reads_the_perk_manager() -> void:
	# PD-2: the Character facade sums combat bonuses via its PerkManager child (0 with none).
	var c := _Stub.new()
	add_child_autofree(c)
	assert_almost_eq(c.perk_combat_bonus(&"damage"), 0.0, 0.0001, "no PerkManager child -> 0")
	var pm := PerkManager.new()
	c.add_child(pm)
	var p := Perk.new()
	p.id = &"gunner"
	p.combat_bonuses = {"damage": 0.3}
	pm.unlock_perk(p)
	assert_almost_eq(c.perk_combat_bonus(&"damage"), 0.3, 0.0001, "perk_combat_bonus sums through the PerkManager child")
	p = null


func test_apply_status_effect_creates_manager_and_applies() -> void:
	var c := _Stub.new()
	add_child_autofree(c)
	var fx := StatusEffect.new()
	fx.id = &"poison"
	fx.duration = 5.0
	c.apply_status_effect(fx)
	var mgr: StatusEffectManager = null
	for ch in c.get_children():
		if ch is StatusEffectManager:
			mgr = ch as StatusEffectManager
	assert_not_null(mgr, "apply_status_effect lazily creates a StatusEffectManager child")
	if mgr != null:
		assert_true(mgr.has_effect(&"poison"), "the effect is active on the character")
		c.apply_status_effect(null)
		assert_eq(mgr.active_count(), 1, "a null effect is a no-op")
	fx = null


func test_take_damage_emits_damaged_signal() -> void:
	# watch_signals / assert_signal_emitted are confirmed in test_smoke's test_inventory_* tests.
	var c := _Stub.new()
	c.max_hp = 1000.0
	add_child_autofree(c)
	watch_signals(c)
	c.take_damage(1.0, false)
	assert_signal_emitted(c, "damaged",
		"take_damage must emit damaged(current_hp, max_hp) on every hit so the health UI can update")


func test_dead_latch_makes_take_damage_a_noop() -> void:
	# The multi-hit guard (lines 116-117): once _dead, take_damage early-returns so a
	# shotgun's pellets in one frame can't re-run gore/die. We assert the guard's no-op;
	# this NEVER triggers the real death path.
	var c := _Stub.new()
	add_child_autofree(c)
	c._dead = true
	var hp_before: float = c.hp
	c.take_damage(5.0, false)
	assert_eq(c.hp, hp_before,
		"While _dead, take_damage must early-return and leave hp untouched so multi-hit-in-one-frame can't re-run death bookkeeping")


# --- heal() (add_child so hp is initialized; only side effect is a damaged.emit) ---

func test_heal_clamps_at_max_hp() -> void:
	# max_hp set EXPLICITLY so this clamp test is independent of the authored default;
	# after _ready, hp == max_hp. Healing past the cap must not overheal.
	var c := _Stub.new()
	c.max_hp = 10.0
	add_child_autofree(c)
	c.heal(5.0)
	assert_eq(c.hp, 10.0,
		"heal() must use min(hp + amount, max_hp) so overheal can never exceed the cap")


func test_heal_restores_partial_hp() -> void:
	var c := _Stub.new()
	c.max_hp = 1000.0
	add_child_autofree(c)
	c.take_damage(10.0, false)
	c.heal(4.0)
	assert_eq(c.hp, 994.0,
		"heal() below the cap must add exactly the amount back (1000 - 10 + 4), the inverse of take_damage")


# --- is_headshot() head-zone threshold (to_local at an identity transform is pure math) ---

func test_is_headshot_above_threshold() -> void:
	# Stub stays at the default transform (origin, identity basis), so to_local is identity:
	# the world y maps straight to local y, compared against head_local_y (0.4).
	var c := _Stub.new()
	add_child_autofree(c)
	assert_true(c.is_headshot(Vector3(0.0, 0.5, 0.0)),
		"A hit at local y 0.5 (>= head_local_y 0.4) must count as a headshot for the damage multiplier")


func test_is_headshot_below_threshold() -> void:
	var c := _Stub.new()
	add_child_autofree(c)
	assert_false(c.is_headshot(Vector3(0.0, 0.3, 0.0)),
		"A hit at local y 0.3 (< head_local_y 0.4) must NOT count as a headshot — it's below the head zone")


# --- Weapon-host aim contract (identity transform => deterministic) ---

func test_get_aim_direction_is_forward() -> void:
	# At an identity basis, -global_basis.z is straight forward (0,0,-1). This lets the
	# same Weapon fire correctly without a camera.
	var c := _Stub.new()
	add_child_autofree(c)
	assert_eq(c.get_aim_direction(), Vector3(0.0, 0.0, -1.0),
		"get_aim_direction() must fire straight forward (-global_basis.z) from the body so a camera-less wielder still aims")


## A body that has walked and turned: an aim contract that ignores the transform (returning the origin / identity)
## would still pass at spawn, which is exactly where an NPC never shoots from.
func test_get_aim_basis_turns_with_the_body() -> void:
	var c := _Stub.new()
	add_child_autofree(c)
	c.rotation = Vector3(0.0, PI / 2.0, 0.0)  # turned 90 degrees left
	assert_true(c.get_aim_basis().is_equal_approx(Basis(Vector3.UP, PI / 2.0)),
		"get_aim_basis() must be this body's CURRENT basis (turned 90 degrees here) — the basis projectile spread rotates around")
	assert_true(c.get_aim_direction().is_equal_approx(Vector3(-1.0, 0.0, 0.0)),
		"a body turned 90 degrees left must fire down -X, not the spawn-time -Z")


func test_get_aim_origin_follows_the_body() -> void:
	var c := _Stub.new()
	add_child_autofree(c)
	c.global_position = Vector3(3.0, 1.5, -7.0)
	assert_true(c.get_aim_origin().is_equal_approx(Vector3(3.0, 1.5, -7.0)),
		"get_aim_origin() must return where the body IS now — where its hitscan/projectiles originate — not the world origin")


# --- the KILL CUE: Character.take_damage's lethal branch -> killer.on_scored_kill() -----------
#
# This is the single seam the whole-sky kill flash fires from, so what is pinned here is not the visual
# (that's StarSky's) but the three guarantees the visual leans on: it fires ONCE per victim, never for a suicide,
# and it reaches whoever _resolve_killer picked — including through the DELAYED credit window, which is the only
# reason a silent takedown, a status/DoT tick and a fall the player caused flash at all. Those have no hit site,
# so nothing else could have told the player about them.


## A Character we can drive through its own LETHAL branch and spy on: _begin_death() is neutered (the real one
## calls gore() + die(), which spawn physics gibs/decals into the tree and raycast the world — impossible on a
## bare off-tree instance), and the two killer-side calls just count. Everything the lethal branch does before
## _begin_death() — _award_kill, _resolve_killer, _bequeath_wallet, _on_killed_by, the cue — then runs FOR REAL.
## Character is @abstract with no abstract methods, so a concrete subclass instantiates (the _SpyAttacker idiom).
class _KillSpy extends Character:
	var scored := 0
	var rewarded := 0
	func _begin_death() -> void:
		pass
	func on_scored_kill() -> void:
		scored += 1
	func reward_kill(_bounty: float) -> void:
		rewarded += 1


## An NPC-style killer: it pays out like any Character killer but does NOT override on_scored_kill, so the lethal
## branch's cue line lands on the BASE hook (test_on_scored_kill_is_base_noop).
class _BountyOnlyKiller extends Character:
	var rewarded := 0
	func reward_kill(_bounty: float) -> void:
		rewarded += 1


func _kill_spy() -> _KillSpy:
	var n := _KillSpy.new()
	n.max_hp = 100.0
	n.hp = 100.0
	return n


## The ordinary case, and the ONCE-per-victim guarantee that lets every caller skip a corpse check of its own:
## take_damage's `if _dead: return` latch means a shotgun's remaining pellets, an overkill pierce or a second
## grenade on the same body cannot re-pop the sky. If this ever reports > 1, the flash has started restarting
## itself mid-beat on multi-hit weapons.
func test_lethal_hit_fires_the_kill_cue_exactly_once() -> void:
	var killer := _kill_spy()
	var victim := _kill_spy()
	victim.take_damage(999.0, false, killer)
	assert_eq(killer.scored, 1,
		"a lethal attributed hit must tell the killer on_scored_kill() exactly once — that call IS the kill sky flash")
	assert_eq(killer.rewarded, 1,
		"the same lethal hit must pay the bounty once; the cue rides the SAME resolved killer, so these two must agree")
	victim.take_damage(999.0, false, killer)
	victim.take_damage(999.0, false, killer)
	assert_eq(killer.scored, 1,
		"further hits on the corpse must NOT re-fire the cue — take_damage's _dead latch is what makes the flash once-per-kill")
	killer.free()
	victim.free()


## A non-lethal hit is not a kill: the cue must stay silent or every bullet would flash the sky.
func test_non_lethal_hit_does_not_fire_the_kill_cue() -> void:
	var shooter := _kill_spy()
	var tough := _kill_spy()
	tough.take_damage(1.0, false, shooter)
	assert_eq(shooter.scored, 0,
		"a survivable hit must not fire the kill cue — only the lethal branch reaches it")
	shooter.free()
	tough.free()


## Blowing yourself up must not congratulate you. _resolve_killer returns null on `killer == self`, which is the
## FIRST thing standing between the player's own grenade/fall death and a red sky over their death cinematic
## (Player.on_scored_kill's _dying gate is the second line of defence, not the first).
func test_suicide_does_not_fire_the_kill_cue() -> void:
	var solo := _kill_spy()
	solo.take_damage(999.0, false, solo)
	assert_eq(solo.scored, 0,
		"a self-inflicted kill must never fire the cue — _resolve_killer nulls out killer == self")
	solo.free()


## An unattributed death (a hazard zone, ambient DoT, a plain fall nobody caused) has no killer to congratulate.
func test_unattributed_death_fires_no_kill_cue() -> void:
	var lonely := _kill_spy()
	lonely.take_damage(999.0, false, null)
	assert_eq(lonely.scored, 0,
		"a death with no attacker and no credited attacker must fire no cue — there is nobody whose sky should pop")
	lonely.free()


## ⭐THE ONE THAT MAKES "ALL KILLS" TRUE. A killing blow that carries NO attacker still resolves to whoever hit
## the victim recently, via _credit_attacker + kill_credit_window_ms. That fallback is the entire mechanism behind
## the kills with no hit site: a fall the player knocked them into, a burn/poison tick that finishes them, and any
## delayed blast. Break it and those kills silently stop flashing while every gunshot still does.
func test_delayed_credit_still_fires_the_kill_cue() -> void:
	var sniper := _kill_spy()
	var faller := _kill_spy()
	faller.take_damage(10.0, false, sniper)  # tag them: stamps _credit_attacker
	faller.take_damage(999.0, false, null)   # the fall / DoT tick finishes them, with no attacker of its own
	assert_eq(sniper.scored, 1,
		"an unattributed KILLING blow must still fire the cue on the recently-credited attacker — this is why a caused fall, a DoT tick and a silent takedown flash the sky")
	sniper.free()
	faller.free()
