extends GutTest

## Player-attack reactions + the on-floor dialogue gate.
## - WARN_ATTACK_LINES / AGGRO_LINES back the new NpcVoice triggers (warn_attack / bark_aggro), fired from
##   NPC._on_damaged_by: an under-threshold hit on a FRIENDLY warns ("Cut that out!"); the hit that actually
##   provokes snaps ("Alright, that does it!"). BarkSet gains matching per-archetype override categories.
## - TalkApproach must NEVER open dialogue while the NPC is airborne: the close-range shortcut is gated on
##   is_on_floor() (checked FIRST, so the off-tree test below never touches global_position), and an airborne
##   prompt defers to the tick() wait (is_approaching) until the landing.

const NPC_PATH := "res://scripts/npc/npc.gd"


func test_warn_and_aggro_default_lines_exist() -> void:
	assert_true(NPC.WARN_ATTACK_LINES.has("Cut that out!"),
		"WARN_ATTACK_LINES must contain the canonical \"Cut that out!\" warning")
	assert_true(NPC.AGGRO_LINES.has("Alright, that does it!"),
		"AGGRO_LINES must contain the canonical \"Alright, that does it!\" snap")
	assert_gt(NPC.WARN_ATTACK_LINES.size(), 0, "the warn pool must be non-empty")
	assert_gt(NPC.AGGRO_LINES.size(), 0, "the aggro pool must be non-empty")


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


func _noop_ready() -> void:
	pass
