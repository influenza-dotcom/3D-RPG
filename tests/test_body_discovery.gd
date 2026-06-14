extends GutTest

## Stealth body-discovery (flag-gated, default OFF): a dead NPC leaves a discoverable Corpse marker, and a
## nearby UNAWARE NPC that SEES it investigates + calls out. Covers the unit-testable surface:
##  - Corpse: the &"corpse" group tag, the `discovered` one-shot flag, and noticeable() (the pure range gate).
##  - The bark surface: CHECK_BODY_LINES defaults, the BarkSet.check_body override, off-tree safety.
##  - The NpcAiSettings.body_discovery master switch defaults off (so the FSM stays byte-identical).
## The live scan + LOS ray (NPC._nearest_visible_corpse / _react_unaware) and spawn-on-death (NPC._spawn_corpse_marker) touch the tree
## and are manual-playtest, per the no-_ready-in-tests rule.

const NPC_PATH := "res://scripts/npc/npc.gd"


# --- Corpse marker ---

func test_corpse_group_and_flags_default() -> void:
	assert_eq(Corpse.GROUP, &"corpse", "the scan group tag is the canonical &\"corpse\"")
	var c := Corpse.new()
	assert_false(c.discovered, "a fresh body is undiscovered (it can still draw an investigator)")
	assert_eq(c.who, "", "no name until a spawner sets it")
	c.free()

func test_corpse_ready_joins_the_scan_group() -> void:
	var c := Corpse.new()
	add_child_autofree(c)  # in-tree so _ready runs
	assert_true(c.is_in_group(&"corpse"), "_ready registers the marker in the &\"corpse\" scan group")

func test_noticeable_is_a_range_gate() -> void:
	var body := Vector3(10.0, 0.0, 0.0)
	var near := Vector3(2.0, 0.0, 0.0)   # 8 m away
	var far := Vector3(40.0, 0.0, 0.0)   # 30 m away
	assert_true(Corpse.noticeable(body, near, 25.0), "a body 8 m off, 25 m sight -> noticed")
	assert_false(Corpse.noticeable(body, far, 25.0), "a body 30 m off, 25 m sight -> unnoticed")

func test_noticeable_includes_the_exact_edge_and_guards_zero_range() -> void:
	var body := Vector3.ZERO
	var at_edge := Vector3(25.0, 0.0, 0.0)
	assert_true(Corpse.noticeable(body, at_edge, 25.0), "exactly at sight range still counts (<=)")
	assert_false(Corpse.noticeable(body, Vector3(0.1, 0.0, 0.0), 0.0), "zero sight range -> never (a blind/edge NPC)")


# --- Bark surface ---

func test_check_body_default_lines_exist() -> void:
	assert_gt(NPC.CHECK_BODY_LINES.size(), 0, "the check-body pool must be non-empty -- a witness always has a line")
	assert_true(NPC.CHECK_BODY_LINES.has("Hey — a body!"), "CHECK_BODY_LINES must contain the canonical \"Hey -- a body!\" line")

func test_bark_set_gains_check_body_category() -> void:
	var b := BarkSet.new()
	assert_eq(b.check_body.size(), 0, "BarkSet.check_body defaults empty -> the NPC's default CHECK_BODY_LINES are used")
	b = null

func test_check_body_override_wins_over_default() -> void:
	var override: Array[String] = ["Stay sharp -- a corpse."]
	var empty: Array[String] = []
	assert_eq(NPC._pick_bark(NPC.CHECK_BODY_LINES, override), "Stay sharp -- a corpse.", "a non-empty override is used over the default")
	assert_true(NPC.CHECK_BODY_LINES.has(NPC._pick_bark(NPC.CHECK_BODY_LINES, empty)), "empty override -> falls back to a default line")

func test_bark_check_body_is_offtree_safe() -> void:
	# A bare NPC (no _ready) has hp 0, so bark_check_body early-returns before touching Talkable / the tree.
	var n = load(NPC_PATH).new()
	var v := NpcVoice.new()
	v.host = n
	v.bark_check_body()
	assert_true(true, "bark_check_body must be safe to call on a bare (off-tree, hp 0) host")
	v.free()
	n.free()


# --- Master switch ---

func test_body_discovery_defaults_off() -> void:
	var s := NpcAiSettings.new()
	assert_false(s.body_discovery, "body_discovery defaults OFF -> no markers spawn and the corpse scan no-ops (byte-identical FSM)")
	s = null
