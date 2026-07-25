extends GutTest

## Player-attack reactions + the on-floor dialogue gate.
## - WARN_ATTACK_LINES / AGGRO_LINES back the NpcVoice triggers (warn_attack / bark_aggro), fired from
##   NPC._on_damaged_by: an under-threshold hit on a FRIENDLY warns; the hit that actually provokes snaps.
##   The pools ship UNAUTHORED (empty = silent) — speech is designer content via BarkSet/consts.
## - TalkApproach must NEVER open dialogue while the NPC is airborne: the close-range shortcut is gated on
##   is_on_floor() (checked FIRST, so the off-tree test below never touches global_position), and an airborne
##   prompt defers to the tick() wait (is_approaching) until the landing.

const NPC_PATH := "res://scripts/npc/npc.gd"


func test_warn_and_aggro_pools_ship_unauthored() -> void:
	# Speech is AUTHORED content: every built-in pool ships EMPTY (= silent) until a designer fills a
	# BarkSet .tres or the consts. An empty pool is a valid configuration (_pick_bark -> "" -> _emit_bark skips).
	assert_eq(NPC.WARN_ATTACK_LINES.size(), 0, "WARN_ATTACK_LINES ships unauthored (empty = silent)")
	assert_eq(NPC.AGGRO_LINES.size(), 0, "AGGRO_LINES ships unauthored (empty = silent)")


func test_bark_set_gains_warn_and_aggro_categories() -> void:
	var b := BarkSet.new()
	assert_eq(b.warn_attack.size(), 0, "BarkSet.warn_attack defaults empty -> the NPC's default lines are used")
	assert_eq(b.aggro.size(), 0, "BarkSet.aggro defaults empty")
	b = null


func test_voice_triggers_are_offtree_safe() -> void:
	# A bare NPC (no _ready) has hp 0, so both triggers early-return before touching Talkable / the tree —
	# the damage handler can fire them on any host without crashing.
	var n = load(NPC_PATH).new()
	var v := NpcVoice.new()
	v.host = n
	v.warn_attack()
	v.bark_aggro()
	assert_true(true, "warn_attack / bark_aggro must be safe to call on a bare (off-tree, hp 0) host")
	v.free()
	n.free()


## --- Flee bark: fired from _on_damaged_by the moment temperament flips a fighter to FLEE (Survive/Flee work) ---

func test_flee_pool_ships_unauthored() -> void:
	assert_eq(NPC.FLEE_LINES.size(), 0, "FLEE_LINES ships unauthored (empty = silent until a designer fills it)")

func test_bark_set_gains_flee_category() -> void:
	var b := BarkSet.new()
	assert_eq(b.flee.size(), 0, "BarkSet.flee defaults empty -> the NPC's default FLEE_LINES are used")
	b = null

func test_flee_bark_set_override_wins_over_default() -> void:
	# _pick_bark resolves the per-archetype BarkSet.flee over the default FLEE_LINES (override-or-default).
	var override: Array[String] = ["Bugging out!"]
	var empty: Array[String] = []
	assert_eq(NPC._pick_bark(NPC.FLEE_LINES, override), "Bugging out!", "a non-empty flee override is used over the default")
	assert_eq(NPC._pick_bark(NPC.FLEE_LINES, empty), "", "empty override + unauthored default -> \"\" (silent; _emit_bark skips it)")

func test_bark_flee_is_offtree_safe() -> void:
	# A bare NPC (no _ready) has hp 0, so bark_flee early-returns before touching Talkable / the tree -- the
	# damage handler can fire it on any host without crashing.
	var n = load(NPC_PATH).new()
	var v := NpcVoice.new()
	v.host = n
	v.bark_flee()
	assert_true(true, "bark_flee must be safe to call on a bare (off-tree, hp 0) host")
	v.free()
	n.free()


func test_prompt_talk_defers_to_approach_while_airborne() -> void:
	# Off-tree is_on_floor() is false (no physics tick) — standing in for "airborne". The close-range
	# shortcut must NOT fire: the prompt becomes a pending approach (is_approaching), whose tick() opens the
	# dialogue only once grounded + facing. The floor gate short-circuits BEFORE any global_position read,
	# so this runs off-tree without tracked engine errors.
	var n = load(NPC_PATH).new()
	n.disposition = Disposition.Kind.FRIENDLY  # prompt_talk refuses hostile NPCs; the bare default is HOSTILE
	var ta := TalkApproach.new()
	ta.host = n
	var player := Node3D.new()
	ta.prompt_talk(player, Callable(self, &"_noop_ready"))
	assert_true(ta.is_approaching(),
		"an airborne NPC must not open dialogue from the close-range shortcut — the prompt defers to the grounded tick() wait")
	ta.free()
	player.free()
	n.free()

func test_sitting_prompt_talk_stays_seated_instead_of_approaching() -> void:
	var n = load(NPC_PATH).new()
	n.disposition = Disposition.Kind.FRIENDLY
	n.sitting = true
	var ta := TalkApproach.new()
	ta.host = n
	var player := Node3D.new()
	ta.prompt_talk(player, Callable(self, &"_noop_ready"))
	assert_false(ta.is_approaching(),
		"a seated NPC must not enter the walk-up talk approach; it speaks in place and keeps the seated pose")
	ta.free()
	player.free()
	n.free()


func _noop_ready() -> void:
	pass
