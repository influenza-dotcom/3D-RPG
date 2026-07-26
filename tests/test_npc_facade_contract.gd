extends GutTest

## M2: the NPC host-facade contract (see scripts/npc/README.md). Components attach to an NPC and read/write host
## members; the 9 Node-typed ones do so DYNAMICALLY (no compile signal on a host rename), so these pin the seam:
## every component's `host` defaults null (bound by NPC._build_components at spawn, never at construction), the public
## write seams (_set_target, set_last_attacker) exist on NPC, and NpcTargeting routes its _last_attacker writes through
## the setter rather than poking the private. Components are built by NPC via .new(); a bare .new() with no add_child
## runs only _init (no _ready), so it's safe headless.

const COMPONENTS := [
	"res://scripts/npc/npc_targeting.gd",
	"res://scripts/npc/npc_locomotion.gd",
	"res://scripts/npc/npc_voice.gd",
	"res://scripts/npc/npc_scavenge.gd",
	"res://scripts/npc/npc_combat.gd",
	"res://scripts/npc/npc_bark_ui.gd",
	"res://scripts/npc/companion_follow.gd",
	"res://scripts/npc/weapon_stance.gd",
	"res://scripts/npc/talk_approach.gd",
	"res://scripts/npc/npc_outline.gd",
	"res://scripts/npc/npc_laser.gd",
	"res://scripts/npc/npc_audio_cues.gd",
	"res://scripts/npc/npc_mortality.gd",
	"res://scripts/npc/npc_senses.gd",
	"res://scripts/npc/npc_home_return.gd",
]


func test_components_host_defaults_null() -> void:
	# host is bound by NPC._build_components at spawn — a bare .new() must leave it null (a non-null default would
	# double-bind / strand a stale host).
	for path in COMPONENTS:
		var c = load(path).new()
		assert_true("host" in c, "%s should expose a `host` field" % path)
		assert_null(c.get("host"), "%s.host must default null (bound by NPC._build_components, not at construction)" % path)
		c.free()


func test_npc_exposes_the_write_seams() -> void:
	var npc = load("res://scripts/npc/npc.gd").new()
	assert_true(npc.has_method("_set_target"), "NPC._set_target binds the combat target (the NpcTargeting seam)")
	assert_true(npc.has_method("set_last_attacker"), "NPC.set_last_attacker is the M2 write seam for the _last_attacker lock")
	npc.free()


func test_targeting_routes_last_attacker_through_the_setter() -> void:
	# NpcTargeting must clear the attacker-lock via host.set_last_attacker(null), NOT a raw host._last_attacker = poke,
	# so the write seam stays greppable + rename-safe (the host is Node-typed there — no compile signal otherwise).
	var src := FileAccess.get_file_as_string("res://scripts/npc/npc_targeting.gd")
	assert_true(src.contains("host.set_last_attacker("), "NpcTargeting should clear the lock via host.set_last_attacker(...)")
	assert_false(src.contains("host._last_attacker ="), "NpcTargeting must not WRITE host._last_attacker directly (route through the setter; the read at :42 is fine)")


func test_distraction_sensing_runs_in_both_branches() -> void:
	# P0-4: a hostile locks the player as a proximity target while still perception-UNAWARE, so noise/corpse sensing
	# must run in the HAS-target branch too (not just _react_unaware) or thrown decoys / hidden bodies do nothing in
	# range. This is the same both-branches shape as _react_music. Pin it by source (the scan is in-tree/LOS-driven).
	var src := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
	assert_true(src.contains("func _scan_distractions("), "the shared throttled scan is extracted")
	assert_true(src.contains("func _react_distraction("), "the has-target distraction feeler exists")
	assert_true(src.contains("_react_distraction(delta)"), "the has-target branch calls _react_distraction (the P0-4 regression guard)")
	assert_true(src.contains("Perception.State.UNAWARE"), "_react_distraction self-gates on UNAWARE like _react_music")


func test_react_distraction_is_null_safe_off_tree() -> void:
	# A bare NPC (.new(), no _ready) has no _perception; the early-return guard must make _react_distraction inert.
	var npc = load("res://scripts/npc/npc.gd").new()
	assert_true(npc.has_method("_react_distraction"), "NPC exposes _react_distraction")
	assert_true(npc.has_method("_scan_distractions"), "NPC exposes _scan_distractions")
	npc._react_distraction(0.1)  # must not error with _perception null (short-circuit guard)
	npc.free()


func test_weapon_stance_gates_out_of_combat_reload_on_supply() -> void:
	# C5: the out-of-combat auto-reload branch must gate on _has_reload_supply() — otherwise a partial-clip gun with an
	# EMPTY reserve dry-clicks reload() every frame (SFX spam) and never reaches the holster branch. Source-string pin
	# (the reconcile() draw/holster loop is in-tree -> playtest); has_reload_supply's own truth table is covered by
	# tests/test_ammo_reserve.gd. Mirrors the contains("host.set_last_attacker(") idiom above.
	var src := FileAccess.get_file_as_string("res://scripts/npc/weapon_stance.gd")
	assert_true(src.contains("func _has_reload_supply()"), "WeaponStance exposes the _has_reload_supply() gate helper")
	assert_true(src.contains("current_ammo < max_ammo and _has_reload_supply()"), "the out-of-combat reload branch gates on _has_reload_supply() before drawing/reloading (C5)")
