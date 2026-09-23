extends GutTest

## GUT suite for per-instance COMPONENT tuning @exports: the designer knobs that used to be hardcoded consts
## (Throwable's grace/probe/confetti group and carry fade, Ragdoll's corpse-light fade, flash_light's follow rate,
## LootableCorpse's loot-hitbox radius, Character's encumbrance ramp).
##
## THE RULE THIS FILE FOLLOWS. A knob exists so a designer can RETUNE it, so no test here pins a shipped number.
## Each knob gets two kinds of check instead:
##   * HONOURED — the component is driven with a deliberately retuned value and the observable result (a credit that
##     expires, a ray that hits, a light that dims, an emitter that fires) must follow THAT value. A regression that
##     re-hardcodes the old const, or wires the knob into the wrong slot, fails here while a rebalance passes.
##   * THE DESIGN INVARIANT on the shipped default — the relation the mechanic needs to work at all (a positive fade
##     rate actually dims, a positive probe sees the floor under a resting gib, the default hitbox can be looked at).
##     Stated as behaviour or as a relation, never as `== <literal>`.
##
## SCOPE — angles already covered elsewhere are NOT repeated:
##   * Throwable.held_visibility_mode INHERIT deferring to ThrowableData.fade_while_held: test_combat_systems.gd.
##   * Throwable carry fade at the live default + the OPAQUE opt-out: test_interact_prompts.gd.
##   * build_confetti_burst's static feature set (sphere emission, ramp, turbulence) + confetti_amount > 0:
##     test_preload_prewarm.gd. The stale-gib half of the confetti window: test_combat_systems.gd.
##   * Character's heaviness / multiplier MATH against the live fields: test_character.gd.
##
## HOW EACH HOST IS BUILT:
##   * Throwable grace + carry fade: off-tree Throwable.new(). _physics_process is safe to call bare (no stuck part,
##     no mesh_instance, no held loop), and on_picked_up / on_dropped is the test_interact_prompts.gd precedent.
##   * Throwable airborne probe / confetti window / confetti spawn: IN-TREE (add_child_autofree, frozen), the
##     test_throwable_inert_gore.gd precedent — those paths read get_world_3d() or parent to get_tree().root.
##   * Ragdoll: off-tree. Its @onready corpse_light never resolves off-tree, so the test hands it a light directly and
##     drives _process; _ready (bone sim, timers) never runs.
##   * flash_light (no class_name): IN-TREE under a Node3D pivot that stands in for the camera, because _process reads
##     get_parent().global_rotation and writes global_rotation. The authored FlashlightClick child is supplied (its
##     `$` lookup would error without it), and automatic processing is switched off the instant _ready returns so only
##     the test's own _process calls move the beam.
##   * LootableCorpse: IN-TREE, because the SphereShape3D that trigger_radius sizes is built in _ready; the hitbox is
##     then probed with a real physics ray on TalkHelpers.TALK_LAYER, the layer PickupRay looks along.
##   * Character: @abstract, so load(path).new() off-tree (the test_character.gd precedent); _ready never runs.

const FLASH_LIGHT_PATH := "res://scenes/player/flash_light.gd"
const CHARACTER_PATH := "res://scripts/player/character.gd"

## Far from the origin so an in-tree physics probe here can never meet a body another test left in the space.
const PROBE_Y := 400.0


# ---------------------------------------------------------------------------
# Throwable (scripts/components/Throwable.gd) — Tuning group
# ---------------------------------------------------------------------------

func _tick_throwable(t: Throwable, seconds: float, step: float = 0.25) -> void:
	var elapsed := 0.0
	while elapsed < seconds - 0.0001:
		t._physics_process(step)
		elapsed += step


func test_throwable_thrown_credit_lasts_as_long_as_thrown_credit_grace() -> void:
	var thrower: Node = autofree(Node.new())
	var quick := Throwable.new()
	quick.thrown_credit_grace = 0.5
	var lingering := Throwable.new()
	lingering.thrown_credit_grace = 2.0
	quick.mark_thrown_by(thrower)
	lingering.mark_thrown_by(thrower)

	_tick_throwable(quick, 1.0)
	_tick_throwable(lingering, 1.0)
	assert_true(quick._credited_attacker() == null,
		"a prop tuned to a 0.5 s thrown_credit_grace must stop blaming its thrower 1 s after the throw, or a crate bumped at rest still aggros NPCs at the player")
	assert_true(lingering._credited_attacker() == thrower,
		"a prop tuned to a 2.0 s thrown_credit_grace must STILL credit its thrower 1 s after the throw, so beaning an NPC after a bounce aggros it at the player")

	_tick_throwable(lingering, 1.25)
	assert_true(lingering._credited_attacker() == null,
		"once its own 2.0 s thrown_credit_grace has run out the prop must go inert and credit nobody")

	# The shipped default must open a real window: a prop that lands a frame after the throw still credits you.
	var shipped := Throwable.new()
	shipped.mark_thrown_by(thrower)
	shipped._physics_process(1.0 / 60.0)
	assert_true(shipped._credited_attacker() == thrower,
		"with the default thrown_credit_grace a prop hitting someone one frame after the throw must credit the thrower; a zero grace would make every thrown crate an anonymous hit")
	quick.free()
	lingering.free()
	shipped.free()


func test_throwable_grapple_credit_lasts_as_long_as_grapple_damage_grace() -> void:
	var grappler: Node = autofree(Node.new())
	var quick := Throwable.new()
	quick.grapple_damage_grace = 0.5
	var lingering := Throwable.new()
	lingering.grapple_damage_grace = 2.0
	quick.mark_grappled_by(grappler)
	lingering.mark_grappled_by(grappler)

	_tick_throwable(quick, 1.0)
	_tick_throwable(lingering, 1.0)
	assert_true(quick._credited_attacker() == null,
		"a prop tuned to a 0.5 s grapple_damage_grace must release its grappler 1 s after the tether lets go")
	assert_true(lingering._credited_attacker() == grappler,
		"a prop tuned to a 2.0 s grapple_damage_grace must still belong to its grappler 1 s after release, so a just-released crate can't chip the player's own HP")

	_tick_throwable(lingering, 1.25)
	assert_true(lingering._credited_attacker() == null,
		"once its own 2.0 s grapple_damage_grace has run out the prop must forget the grappler")

	var shipped := Throwable.new()
	shipped.mark_grappled_by(grappler)
	shipped._physics_process(1.0 / 60.0)
	assert_true(shipped._credited_attacker() == grappler,
		"with the default grapple_damage_grace the grappler must still own the prop one frame after release; a zero grace lets the slam you just let go of hurt you")
	quick.free()
	lingering.free()
	shipped.free()


func _floor_at(top_y: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 0.2, 6.0)
	shape.shape = box
	body.add_child(shape)
	add_child_autofree(body)
	body.global_position = Vector3(0.0, top_y - 0.1, 0.0)
	return body


func _frozen_throwable_at(pos: Vector3) -> Throwable:
	var t := Throwable.new()
	t.freeze = true  # no collider and no gravity drift: the probe must measure from exactly where we put it
	add_child_autofree(t)
	t.global_position = pos
	return t


func test_throwable_airborne_probe_sets_how_close_the_ground_must_be() -> void:
	_floor_at(PROBE_Y)
	var hovering := _frozen_throwable_at(Vector3(0.0, PROBE_Y + 0.4, 0.0))
	var resting := _frozen_throwable_at(Vector3(1.5, PROBE_Y + 0.05, 1.5))
	await wait_physics_frames(2)

	hovering.airborne_probe = 0.2
	assert_true(hovering._is_airborne(),
		"with airborne_probe 0.2 m a gib 0.4 m above the floor must read as mid-air (the ray stops short of the ground)")
	hovering.airborne_probe = 1.0
	assert_false(hovering._is_airborne(),
		"with airborne_probe 1.0 m the same gib 0.4 m above the floor must read as grounded (the ray now reaches it) — the knob, not a hardcoded length, decides")

	assert_false(resting._is_airborne(),
		"a gib lying on the floor must NOT count as airborne with the default airborne_probe; a zero-length probe would make every resting gib a confetti trick-shot")


func test_throwable_confetti_window_is_measured_against_confetti_fresh_window_ms() -> void:
	# A mid-air gib (nothing below it) shot by the player: only the freshness window decides, so flipping the
	# window across the gib's age must flip the answer. This also reaches the TRUE path the off-tree tests in
	# test_combat_systems.gd cannot (it ends in the _is_airborne world query).
	var gib := _frozen_throwable_at(Vector3(0.0, PROBE_Y + 200.0, 0.0))
	var gib_data := ThrowableData.new()
	gib_data.is_gib = true
	gib.data = gib_data
	var shooter: Node = autofree(Node.new())
	shooter.add_to_group(Groups.PLAYER)  # off-tree: is_in_group answers, but no global group scan can see it
	var shipped_window: int = gib.confetti_fresh_window_ms

	gib._spawn_msec = Time.get_ticks_msec() - 3000  # the gib burst out 3 s ago
	gib.confetti_fresh_window_ms = 1000
	assert_false(gib._is_confetti_kill(shooter),
		"a 3 s old gib must be refused when confetti_fresh_window_ms is tuned to 1 s — lying-around gibs are not trick-shots")
	gib.confetti_fresh_window_ms = 60000
	assert_true(gib._is_confetti_kill(shooter),
		"the SAME 3 s old mid-air gib must qualify once confetti_fresh_window_ms is tuned to 60 s — the gate has to read the knob")

	gib.confetti_fresh_window_ms = shipped_window
	gib._spawn_msec = Time.get_ticks_msec()
	assert_true(gib._is_confetti_kill(shooter),
		"with the default window a gib shot mid-air the instant it burst out must confetti; a non-positive window would make the trick-shot impossible")
	gib_data = null


func test_throwable_spawned_confetti_carries_the_designer_tuning() -> void:
	var t := _frozen_throwable_at(Vector3(3.0, PROBE_Y + 50.0, -2.0))
	t.confetti_amount = 13
	t.confetti_lifetime = 0.9
	t.confetti_velocity_min = 1.5
	t.confetti_velocity_max = 9.0
	t.confetti_scale_min = 0.25
	t.confetti_scale_max = 2.0
	var root := get_tree().root
	var before := root.get_children()
	t._spawn_confetti()
	var burst: GPUParticles3D = null
	for child in root.get_children():
		if child is GPUParticles3D and not before.has(child):
			burst = child as GPUParticles3D
	assert_true(burst != null, "_spawn_confetti must put a GPUParticles3D burst into the scene")
	if burst == null:
		return
	autofree(burst)
	assert_eq(burst.amount, 13, "the fired burst must spawn confetti_amount flecks, not a baked-in count")
	assert_almost_eq(burst.lifetime, 0.9, 0.0001, "each fleck must live confetti_lifetime seconds")
	assert_true(burst.emitting, "the burst must actually fire when spawned")
	assert_true(burst.global_position.is_equal_approx(t.global_position),
		"the burst must pop where the gib was shot, not at the world origin")
	var ppm := burst.process_material as ParticleProcessMaterial
	assert_true(ppm != null, "the fired burst must carry its ParticleProcessMaterial")
	if ppm == null:
		return
	assert_almost_eq(ppm.initial_velocity_min, 1.5, 0.0001,
		"confetti_velocity_min must land on the SLOW edge of the launch-speed range")
	assert_almost_eq(ppm.initial_velocity_max, 9.0, 0.0001,
		"confetti_velocity_max must land on the FAST edge of the launch-speed range")
	assert_almost_eq(ppm.scale_min, 0.25, 0.0001,
		"confetti_scale_min must land on the SMALL edge of the per-fleck scale range")
	assert_almost_eq(ppm.scale_max, 2.0, 0.0001,
		"confetti_scale_max must land on the LARGE edge of the per-fleck scale range")


func test_throwable_default_confetti_burst_is_visible() -> void:
	var t := Throwable.new()
	assert_gt(t.confetti_lifetime, 0.0,
		"confetti_lifetime must be positive — a zero-lifetime fleck dies on the frame it spawns and the trick-shot shows nothing")
	assert_true(t.confetti_velocity_min >= 0.0,
		"confetti_velocity_min must not be negative — a launch speed below zero is meaningless for the burst")
	t.free()


func test_throwable_confetti_ranges_are_ascending() -> void:
	# Cross-field ORDERING invariants — these hold for any retune, not just today's defaults:
	# ParticleProcessMaterial treats each pair as a randomized [min, max] range.
	var t := Throwable.new()
	assert_lt(t.confetti_velocity_min, t.confetti_velocity_max,
		"confetti_velocity_min must be < confetti_velocity_max — they bound ParticleProcessMaterial's randomized launch-speed range; inverted, every fleck launches at one degenerate speed (or the spread silently flips)")
	assert_lt(t.confetti_scale_min, t.confetti_scale_max,
		"confetti_scale_min must be < confetti_scale_max — they bound the randomized per-fleck scale range; inverted, the size variety that sells the burst collapses")
	t.free()


func test_throwable_carry_fade_uses_carried_transparency_and_stays_visible() -> void:
	var shipped := Throwable.new()
	var shipped_mesh := MeshInstance3D.new()
	shipped.add_child(shipped_mesh)
	shipped.on_picked_up(null)
	assert_gt(shipped_mesh.transparency, 0.0,
		"a default prop must go see-through while carried, or it walls off the screen at arm's length")
	assert_lt(shipped_mesh.transparency, 1.0,
		"a default prop must stay VISIBLE while carried — fully transparent means the player can't see what they hold")
	shipped.free()

	var ghostly := Throwable.new()
	ghostly.carried_transparency = 0.75
	var ghostly_mesh := MeshInstance3D.new()
	ghostly.add_child(ghostly_mesh)
	ghostly.on_picked_up(null)
	assert_almost_eq(ghostly_mesh.transparency, 0.75, 0.0001,
		"a prop retuned to carried_transparency 0.75 must fade to exactly that while held — the knob, not a baked-in alpha")
	ghostly.on_dropped()
	assert_almost_eq(ghostly_mesh.transparency, 0.0, 0.0001,
		"dropping the retuned prop must restore full opacity")
	ghostly.free()


# ---------------------------------------------------------------------------
# Ragdoll (scripts/components/ragdoll.gd) — corpse-light fade
# ---------------------------------------------------------------------------

func _ragdoll_with_light(range_m: float) -> Ragdoll:
	var r := Ragdoll.new()
	var light := OmniLight3D.new()
	light.omni_range = range_m
	r.add_child(light)
	r.corpse_light = light  # what the @onready NodeFinder lookup resolves on tree entry
	return r


func test_ragdoll_corpse_light_dims_only_once_the_fade_starts() -> void:
	var r := _ragdoll_with_light(8.0)
	r._process(0.2)
	assert_almost_eq(r.corpse_light.omni_range, 8.0, 0.0001,
		"a corpse that is not fading yet must keep its light at full range")
	r._fading = true
	r._process(0.2)
	assert_lt(r.corpse_light.omni_range, 8.0,
		"once the fade starts, the default fade_speed must actually dim the corpse light; a zero rate freezes it lit forever")
	assert_gt(r.corpse_light.omni_range, 0.0,
		"the corpse light must EASE out over frames, not blink off in a single one")
	r.free()


func test_ragdoll_fade_is_frame_rate_independent() -> void:
	var one_step := _ragdoll_with_light(8.0)
	one_step._fading = true
	one_step._process(0.2)
	var two_steps := _ragdoll_with_light(8.0)
	two_steps._fading = true
	two_steps._process(0.1)
	two_steps._process(0.1)
	assert_almost_eq(two_steps.corpse_light.omni_range, one_step.corpse_light.omni_range, 0.0001,
		"the corpse light must dim the same amount over 0.2 s whether that is one frame or two — the fade must scale with delta")
	one_step.free()
	two_steps.free()


func test_ragdoll_higher_fade_speed_dims_faster() -> void:
	var slow := _ragdoll_with_light(8.0)
	slow.fade_speed = 1.0
	slow._fading = true
	var fast := _ragdoll_with_light(8.0)
	fast.fade_speed = 6.0
	fast._fading = true
	slow._process(0.1)
	fast._process(0.1)
	assert_lt(fast.corpse_light.omni_range, slow.corpse_light.omni_range,
		"a ragdoll tuned to a higher fade_speed must dim its light faster over the same frame")
	slow.free()
	fast.free()


# ---------------------------------------------------------------------------
# flash_light (scenes/player/flash_light.gd) — aim follow
# ---------------------------------------------------------------------------

## A lit torch parented to a Node3D pivot (the camera stand-in), with automatic processing OFF.
func _lit_torch(pivot: Node3D) -> SpotLight3D:
	var torch: SpotLight3D = load(FLASH_LIGHT_PATH).new()
	var click := AudioStreamPlayer3D.new()
	click.name = "FlashlightClick"
	torch.add_child(click)
	torch.set("start_on", true)
	pivot.add_child(torch)
	torch.set_process(false)  # only this test's explicit _process calls may move the beam
	return torch


func _new_pivot() -> Node3D:
	var pivot := Node3D.new()
	add_child_autofree(pivot)
	return pivot


func test_flash_light_beam_turns_toward_the_aim_with_a_lag() -> void:
	var pivot := _new_pivot()
	var torch := _lit_torch(pivot)
	pivot.rotation = Vector3(0.0, 1.0, 0.0)
	torch.call("_process", 1.0 / 60.0)
	assert_gt(torch.global_rotation.y, 0.0,
		"a lit torch with the default follow_rate must turn toward where the camera now looks; a zero rate freezes the beam")
	assert_lt(torch.global_rotation.y, 1.0 - 0.01,
		"the torch must TRAIL the aim by a frame rather than weld to the camera — that lag is the hand-held feel")


func test_flash_light_follow_is_frame_rate_independent() -> void:
	var pivot := _new_pivot()
	var torch := _lit_torch(pivot)
	pivot.rotation = Vector3(0.0, 1.0, 0.0)
	torch.global_rotation = Vector3.ZERO
	torch.call("_process", 0.05)
	var one_frame: float = torch.global_rotation.y
	torch.global_rotation = Vector3.ZERO
	torch.call("_process", 0.025)
	torch.call("_process", 0.025)
	assert_almost_eq(torch.global_rotation.y, one_frame, 0.0001,
		"the beam must cover the same turn over 50 ms at 20 fps or 40 fps — the follow must scale with delta")


func test_flash_light_higher_follow_rate_tracks_the_aim_tighter() -> void:
	var pivot := _new_pivot()
	var torch := _lit_torch(pivot)
	pivot.rotation = Vector3(0.0, 1.0, 0.0)
	torch.set("follow_rate", 4.0)
	torch.global_rotation = Vector3.ZERO
	torch.call("_process", 0.05)
	var heavy: float = torch.global_rotation.y
	torch.set("follow_rate", 30.0)
	torch.global_rotation = Vector3.ZERO
	torch.call("_process", 0.05)
	assert_gt(torch.global_rotation.y, heavy,
		"a torch tuned to a higher follow_rate must close more of the gap to the aim in the same frame")


func test_flash_light_switched_off_snaps_to_the_aim() -> void:
	var pivot := _new_pivot()
	var torch := _lit_torch(pivot)
	torch.set("_light_on", false)
	pivot.rotation = Vector3(0.0, 1.0, 0.0)
	torch.call("_process", 1.0 / 60.0)
	assert_almost_eq(torch.global_rotation.y, 1.0, 0.0001,
		"an unlit torch must snap to the aim, so switching it on mid-turn never swings the beam in from a stale direction")


# ---------------------------------------------------------------------------
# LootableCorpse (scripts/components/lootable_corpse.gd) — loot hitbox radius
# ---------------------------------------------------------------------------

func _corpse_at(pos: Vector3, radius: float = -1.0) -> LootableCorpse:
	var corpse := LootableCorpse.new()
	if radius > 0.0:
		corpse.trigger_radius = radius
	add_child_autofree(corpse)
	corpse.global_position = pos
	return corpse


## What the interaction ray finds between two points in `world_of`'s space: the object on the talk layer, or null.
func _look_hits(world_of: Node3D, from: Vector3, to: Vector3) -> Object:
	var space := world_of.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, TalkHelpers.TALK_LAYER)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit: Dictionary = space.intersect_ray(q)
	return hit.get("collider") as Object


func test_lootable_corpse_default_hitbox_can_be_looked_at() -> void:
	var at := Vector3(-30.0, PROBE_Y, 0.0)
	var corpse := _corpse_at(at)
	await wait_physics_frames(2)
	assert_true(_look_hits(corpse, at + Vector3(0.0, 0.0, 3.0), at - Vector3(0.0, 0.0, 3.0)) == corpse,
		"a look straight at a default corpse must hit its loot hitbox on the talk layer; a zero trigger_radius makes every corpse unlootable")


func test_lootable_corpse_trigger_radius_sets_how_wide_the_hitbox_reaches() -> void:
	var wide_at := Vector3(0.0, PROBE_Y, 0.0)
	var narrow_at := Vector3(30.0, PROBE_Y, 0.0)
	var wide := _corpse_at(wide_at, 1.5)
	var narrow := _corpse_at(narrow_at, 0.3)
	await wait_physics_frames(2)
	var off_centre := Vector3(0.8, 0.0, 0.0)
	var along := Vector3(0.0, 0.0, 3.0)
	assert_true(_look_hits(wide, wide_at + off_centre + along, wide_at + off_centre - along) == wide,
		"a corpse tuned to trigger_radius 1.5 m must catch a look passing 0.8 m off the body")
	assert_true(_look_hits(narrow, narrow_at + along, narrow_at - along) == narrow,
		"control: the corpse tuned to 0.3 m is lootable when looked at dead centre")
	assert_true(_look_hits(narrow, narrow_at + off_centre + along, narrow_at + off_centre - along) == null,
		"a corpse tuned to trigger_radius 0.3 m must NOT catch a look passing 0.8 m off the body — the sphere must be sized by the knob")


# ---------------------------------------------------------------------------
# Character (scripts/player/character.gd) — @abstract, so load(path).new()
# ---------------------------------------------------------------------------

func test_character_encumbrance_defaults() -> void:
	# Character's gradual-encumbrance knobs (replaced the old flat encumbered_speed_mult). test_character.gd
	# proves the heaviness/multiplier MATH; here the shipped defaults must form a sane ramp, off-tree per the
	# test_character.gd export-default precedent (load().new(), no add_child, _ready never runs).
	var c = load(CHARACTER_PATH).new()
	assert_true(c.encumbrance_free_fraction >= 0.0,
		"encumbrance_free_fraction must not be negative — below zero an actor carrying NOTHING would already be slowed")
	assert_gt(c.encumbrance_full_fraction, c.encumbrance_free_fraction,
		"encumbrance_full_fraction must exceed the free fraction, or the linear penalty ramp would divide by ~zero")
	for field in ["min_load_speed_mult", "min_load_jump_mult", "min_load_launch_mult"]:
		var v: float = c.get(field)
		assert_gt(v, 0.0, "%s must be > 0 — a fully loaded actor must still move/jump/launch SOMETHING, never freeze solid" % field)
		assert_lt(v, 1.0, "%s must be < 1 — a full load has to be an actual penalty, or carry weight stops mattering" % field)
	c.free()
