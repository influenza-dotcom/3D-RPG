extends GutTest

## GUT suite for per-instance COMPONENT tuning @exports — the designer knobs a refactor just
## converted from hardcoded consts (Throwable's grace/confetti group, Ragdoll's fade rate,
## flash_light's follow rate, LootableCorpse's hitbox radius, Character's encumbrance penalty).
## Each is pinned at its SCRIPT default — the value every freshly drag-dropped instance gets —
## so an accidental default drift in the .gd (the exact regression a const->@export conversion
## invites) is caught, while per-scene .tscn overrides stay completely free: no scene is ever
## read here. Assert messages state WHY each invariant matters, so this file doubles as
## documentation of the knobs' contracts.
##
## SCOPE — only angles NOT already asserted elsewhere:
##   * Throwable.carried_transparency: its APPLICATION (meshes fade on pickup, restore on drop)
##     is covered by test_interact_prompts.gd — but that test compares mesh transparency to the
##     live field RELATIVELY, never pinning the default. The 0.4 default + alpha range live here.
##   * Throwable.confetti_fresh_window_ms: the staleness GATE logic is covered by
##     test_combat_systems.gd (which stamps _spawn_msec relative to the field) — the 8000 value
##     and its int TYPE (it's compared against Time.get_ticks_msec() deltas) are pinned here.
##   * flash_light.follow_rate: test_smoke.gd pins the SOURCE TEXT ("@export var follow_rate",
##     "exp(-follow_rate") — a text pin proves the mechanism exists in the file, but not what a
##     live instance actually defaults to. Both are valid, different artifacts; the live script
##     default off an instance is pinned here.
##   * Character's gradual-encumbrance knobs: test_character.gd exercises the heaviness/multiplier MATH
##     (relative to the live fields) — the export defaults (free_fraction 0.25, the min_load_* floors) and
##     their (0,1) ranges are pinned here.
##   * Everything else (Throwable grace/probe + Confetti Burst group, Ragdoll.fade_speed,
##     LootableCorpse.trigger_radius) had no prior pins anywhere in tests/.
##
## TESTABILITY NOTES:
##   * NO script in this file's reach defines _init (grepped scripts/ — zero hits), and _ready
##     never fires off-tree (nothing is add_child'ed), so every .new() below is side-effect-free:
##     Throwable's preload consts resolve at script-compile time (per test_combat_systems.gd),
##     Ragdoll's @onready corpse-light path resolves only on tree entry, LookAtInteractable's
##     talk-layer/_build_outline work is all in _ready (LootableCorpse.new() precedent:
##     test_loot_drop.gd) — so the get_script_property_list() fallback was NOT needed anywhere.
##   * flash_light.gd has no class_name -> load(path).new(); Character is @abstract -> the same
##     load(path).new() route test_character.gd's export-default tests use. Both are plain
##     `var x =` (a load().new() chain is Variant — `:=` inference off it is the analyzer trap).
##   * All five hosts are Nodes (RigidBody3D / Node3D / SpotLight3D / Area3D / CharacterBody3D),
##     so each is released with .free(), never `= null`. No global_transform / to_local is ever
##     touched off-tree (GUT 9.6 fails the test on that engine error).


# ---------------------------------------------------------------------------
# Throwable (scripts/components/Throwable.gd) — Tuning group
# ---------------------------------------------------------------------------

func test_throwable_grace_and_probe_defaults() -> void:
	var t := Throwable.new()
	assert_eq(t.thrown_credit_grace, 4.0,
		"thrown_credit_grace must default to 4.0 s — long enough to credit the thrower through the prop's flight plus a bounce (so beaning an NPC aggros it at you), short enough that a crate later bumped at rest can't still blame the thrower")
	assert_eq(t.grapple_damage_grace, 1.5,
		"grapple_damage_grace must default to 1.5 s — the post-release window in which a reeled/tethered prop can't hurt the grappler; drift shorter and slamming a just-released crate chips your own HP, drift longer and the prop is unfairly harmless to you")
	assert_eq(t.airborne_probe, 0.6,
		"airborne_probe must default to 0.6 m — the downward ray length that defines 'mid-air' for the confetti trick-shot; longer would count a gib skimming the floor as airborne, shorter would deny shots on a gib just above the ground")
	assert_gt(t.airborne_probe, 0.0,
		"airborne_probe must be > 0 or the _is_airborne() ray has zero length and EVERY gib reads as airborne — the trick-shot's whole 'in flight' requirement would vanish")
	t.free()


func test_throwable_confetti_fresh_window_default_and_int_type() -> void:
	# test_combat_systems.gd uses this field RELATIVELY (stamps _spawn_msec into the past by
	# window+1000) to prove the staleness gate — it never pins the value or the type. Both here.
	var t := Throwable.new()
	assert_eq(typeof(t.confetti_fresh_window_ms), TYPE_INT,
		"confetti_fresh_window_ms must be an int — it is subtracted against Time.get_ticks_msec() (int milliseconds) in _is_confetti_kill, so the freshness comparison's semantics depend on integer msec")
	assert_eq(t.confetti_fresh_window_ms, 8000,
		"confetti_fresh_window_ms must default to 8000 ms — a gib older than ~8 s since spawn is 'stale' and can't confetti; drift larger and lying-around gibs become farmable trick-shots, drift smaller and legitimate just-burst gibs stop qualifying")
	t.free()


func test_throwable_carried_transparency_default_is_partial_alpha() -> void:
	# The APPLICATION (meshes fade on pickup / restore on drop) is test_interact_prompts.gd's —
	# it asserts mesh.transparency == the live field, so it would pass at ANY default. The
	# default VALUE and its open (0,1) alpha range are this test's job.
	var t := Throwable.new()
	assert_eq(t.carried_transparency, 0.4,
		"carried_transparency must default to 0.4 — the shipped Deus Ex carry-fade strength applied to held props")
	assert_gt(t.carried_transparency, 0.0,
		"carried_transparency must be > 0 — it is GeometryInstance3D.transparency while carried; 0 would mean no fade at all and the held prop walls off the screen at arm's length")
	assert_lt(t.carried_transparency, 1.0,
		"carried_transparency must be < 1 — 1.0 is fully invisible, and the player must still SEE the prop they are carrying")
	t.free()


func test_throwable_confetti_burst_defaults() -> void:
	var t := Throwable.new()
	assert_eq(typeof(t.confetti_amount), TYPE_INT,
		"confetti_amount must be an int — it is assigned to GPUParticles3D.amount, an integer particle count")
	assert_eq(t.confetti_amount, 48,
		"confetti_amount must default to 48 flecks — the shipped trick-shot burst density; drift down and the celebration reads as a fizzle, drift up and it costs GPU for no design reason")
	assert_eq(t.confetti_lifetime, 1.7,
		"confetti_lifetime must default to 1.7 s — long enough for the flecks to arc and tumble visibly, short enough that the one-shot emitter frees itself promptly")
	assert_eq(t.confetti_velocity_min, 3.0,
		"confetti_velocity_min must default to 3.0 m/s — the slow edge of the launch-speed spread (ParticleProcessMaterial.initial_velocity_min)")
	assert_eq(t.confetti_velocity_max, 6.5,
		"confetti_velocity_max must default to 6.5 m/s — the fast edge of the launch-speed spread (ParticleProcessMaterial.initial_velocity_max)")
	assert_eq(t.confetti_scale_min, 0.6,
		"confetti_scale_min must default to 0.6 — the smallest per-fleck multiplier on the base flake mesh size")
	assert_eq(t.confetti_scale_max, 1.3,
		"confetti_scale_max must default to 1.3 — the largest per-fleck multiplier on the base flake mesh size")
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


# ---------------------------------------------------------------------------
# Ragdoll (scripts/components/ragdoll.gd)
# ---------------------------------------------------------------------------

func test_ragdoll_fade_speed_default() -> void:
	# Off-tree .new(): no _init; the @onready corpse_light path only resolves on tree entry and
	# _ready (animation stop / bone sim / timers) never fires without add_child.
	var r := Ragdoll.new()
	assert_eq(r.fade_speed, 3.0,
		"Ragdoll.fade_speed must default to 3.0 — the shipped corpse-light fade rate (higher fades faster)")
	assert_gt(r.fade_speed, 0.0,
		"fade_speed must be > 0 — it drives the per-frame ratio '1 - exp(-fade_speed * delta)' in _process; at 0 the ratio is permanently 0 and the dead corpse's omni light never dims (the fade freezes)")
	r.free()


# ---------------------------------------------------------------------------
# flash_light (scenes/player/flash_light.gd) — no class_name, so load(path).new()
# ---------------------------------------------------------------------------

func test_flash_light_follow_rate_default() -> void:
	# test_smoke.gd's pins on this script are SOURCE-TEXT checks ("@export var follow_rate",
	# "exp(-follow_rate") — they prove the export and the exp-smoothing exist in the file, not
	# what a live instance defaults to. This pins the LIVE default off .new() (no _init; the
	# @onready laser/attack paths resolve only on tree entry, so off-tree construction is safe).
	var fl = load("res://scenes/player/flash_light.gd").new()
	assert_eq(fl.follow_rate, 15.0,
		"flash_light.follow_rate must default to 15.0 — the shipped 'snappy but visibly lagging' chase rate that gives the light its slight drag behind the gun's aim")
	assert_gt(fl.follow_rate, 0.0,
		"follow_rate must be > 0 — it drives '1 - exp(-follow_rate * delta)' in _process; at 0 the lerp ratio is permanently 0 and the flashlight never turns to follow the aim (frozen beam)")
	fl.free()


# ---------------------------------------------------------------------------
# LootableCorpse (scripts/components/lootable_corpse.gd, extends LookAtInteractable)
# ---------------------------------------------------------------------------

func test_lootable_corpse_trigger_radius_default() -> void:
	# Route taken: direct LootableCorpse.new() — the whole inheritance chain (LootableCorpse ->
	# LookAtInteractable -> Area3D) defines NO _init, and every side effect (talk-layer setup,
	# outline build, the SphereShape3D this radius sizes) lives in _ready, which never fires
	# off-tree. test_loot_drop.gd already builds LootableCorpse this way; the
	# get_script_property_list() fallback was unnecessary.
	var corpse := LootableCorpse.new()
	assert_eq(corpse.trigger_radius, 1.2,
		"LootableCorpse.trigger_radius must default to 1.2 m — the shipped loot-hitbox sphere size at the death spot, roughly a sprawled body's reach")
	assert_gt(corpse.trigger_radius, 0.0,
		"trigger_radius must be > 0 — _ready assigns it to the SphereShape3D radius of the loot interaction hitbox; at 0 the sphere is a point the PickupRay can never hit, making every corpse unlootable")
	corpse.free()


# ---------------------------------------------------------------------------
# Character (scripts/player/character.gd) — @abstract, so load(path).new()
# ---------------------------------------------------------------------------

func test_character_encumbrance_defaults() -> void:
	# Character's gradual-encumbrance knobs (replaced the old flat encumbered_speed_mult). test_character.gd
	# proves the heaviness/multiplier MATH; here we pin the shipped defaults + the (0,1) penalty ranges, off-tree
	# per the test_character.gd export-default precedent (load().new(), no add_child, _ready never runs).
	var c = load("res://scripts/player/character.gd").new()
	assert_almost_eq(c.encumbrance_free_fraction, 0.25, 0.0001,
		"encumbrance_free_fraction must default to 0.25 — you haul up to ¼ of capacity with no penalty before the ramp begins")
	assert_gt(c.encumbrance_full_fraction, c.encumbrance_free_fraction,
		"encumbrance_full_fraction must exceed the free fraction, or the linear penalty ramp would divide by ~zero")
	for field in ["min_load_speed_mult", "min_load_jump_mult", "min_load_launch_mult"]:
		var v: float = c.get(field)
		assert_gt(v, 0.0, "%s must be > 0 — a fully loaded actor must still move/jump/launch SOMETHING, never freeze solid" % field)
		assert_lt(v, 1.0, "%s must be < 1 — a full load has to be an actual penalty, or carry weight stops mattering" % field)
	c.free()
