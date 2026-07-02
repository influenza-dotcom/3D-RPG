extends GutTest

## M2: the NPC host-facade contract (see scripts/npc/README.md). Components attach to an NPC and read/write host
## members; the 5 Node-typed ones do so DYNAMICALLY (no compile signal on a host rename), so these pin the seam:
## every component's `host` defaults null (bound by NPC._build_components at spawn, never at construction), the public
## write seams (_set_target, set_last_attacker) exist on NPC, and NpcTargeting routes its _last_attacker writes through
## the setter rather than poking the private. Components are built by NPC via .new(); a bare .new() with no add_child
## runs only _init (no _ready), so it's safe headless.

const COMPONENTS := [
	"res://scripts/npc/npc_targeting.gd",
	"res://scripts/npc/npc_locomotion.gd",
	"res://scripts/npc/npc_voice.gd",
	"res://scripts/npc/npc_scavenge.gd",
	"res://scripts/npc/npc_bark_ui.gd",
	"res://scripts/npc/companion_follow.gd",
	"res://scripts/npc/weapon_stance.gd",
	"res://scripts/npc/talk_approach.gd",
	"res://scripts/npc/npc_outline.gd",
	"res://scripts/npc/npc_laser.gd",
	"res://scripts/npc/npc_audio_cues.gd",
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
