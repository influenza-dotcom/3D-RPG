extends GutTest

## C36: the give-up bark at the END of an engagement comes from ONE shared settle helper
## (NPC._settle_engagement_barks), reached from both the has-target perception-drop path and the no-target branch
## (a target that died / freed mid-fight). The helper decides WHICH line the NPC says and clears the engagement
## latches (_saw_combat / _was_aware / _alerted_allies) so the next engagement can't open with a phantom
## "combat over" bark:
##   - a fighter that went ALERTED (_saw_combat)          -> the combat-over taunt ("Lost 'em.")
##   - an NPC that only noticed / searched (_was_aware)   -> the softer lost-interest line ("Must be gone now.")
##   - an NPC that never noticed anything                 -> silence, and nothing changes
## Built off-tree via load(...).new() WITHOUT _ready (per CLAUDE.md — _ready instantiates weapon.tscn/nav/audio and
## mutates statics). The NPC's bark facades forward into its NpcVoice child, so a counting NpcVoice double stands
## in for the one _build_components would make: it records which give-up line was requested without starting
## the in-tree bubble / TTS path (no transforms touched -> GUT 9.6-safe).

const NPC_PATH := "res://scripts/npc/npc.gd"


## Counts the two give-up call-outs the settle helper chooses between.
class _GiveUpVoice extends NpcVoice:
	var combat_over: int = 0
	var lost_interest: int = 0

	func _try_combat_end_bark() -> void:
		combat_over += 1

	func _try_lost_interest_bark() -> void:
		lost_interest += 1


func _npc_with_voice(voice: NpcVoice, was_aware: bool, saw_combat: bool, alerted_allies: bool):
	var e = load(NPC_PATH).new()
	e._voice = voice
	e._was_aware = was_aware
	e._saw_combat = saw_combat
	e._alerted_allies = alerted_allies
	return e


func _free(e, voice: NpcVoice) -> void:
	e._voice = null
	voice.free()
	e.free()


func test_fighter_that_lost_its_target_says_combat_over_and_clears_latches() -> void:
	var voice := _GiveUpVoice.new()
	var e = _npc_with_voice(voice, true, true, true)
	e._settle_engagement_barks()
	assert_eq(voice.combat_over, 1, "an NPC that went ALERTED gives the combat-over taunt once the fight ends")
	assert_eq(voice.lost_interest, 0, "a real fighter must not ALSO mutter the softer lost-interest line")
	assert_false(e._saw_combat, "_saw_combat clears, or the NEXT engagement opens with a phantom combat-over bark")
	assert_false(e._was_aware, "_was_aware clears with the rest of the engagement")
	assert_false(e._alerted_allies, "_alerted_allies clears, re-arming the ally broadcast for the next engagement")
	_free(e, voice)


func test_npc_that_only_noticed_says_lost_interest_and_clears_latches() -> void:
	var voice := _GiveUpVoice.new()
	var e = _npc_with_voice(voice, true, false, true)
	e._settle_engagement_barks()
	assert_eq(voice.lost_interest, 1,
		"an NPC that noticed / searched but never went ALERTED gives the lost-interest line when it gives up")
	assert_eq(voice.combat_over, 0, "it never fought, so it must not claim 'combat over'")
	assert_false(e._was_aware, "_was_aware clears, so the next give-up is decided afresh")
	assert_false(e._alerted_allies, "_alerted_allies clears for the next engagement")
	_free(e, voice)


func test_npc_that_never_noticed_anything_stays_silent() -> void:
	# The no-target branch calls the helper EVERY frame for the whole idle cast, so the never-aware case must be a
	# true no-op: no bark (a townsperson would otherwise mutter "must be gone now" on every think).
	var voice := _GiveUpVoice.new()
	var e = _npc_with_voice(voice, false, false, false)
	e._settle_engagement_barks()
	e._settle_engagement_barks()
	assert_eq(voice.lost_interest, 0, "an idle NPC that never noticed a threat says nothing")
	assert_eq(voice.combat_over, 0, "an idle NPC that never fought says nothing")
	_free(e, voice)


func test_give_up_bark_fires_once_per_engagement() -> void:
	# Both give-up paths can run on consecutive frames (perception drops, then the target frees), so the second
	# settle of the same engagement must be silent.
	var voice := _GiveUpVoice.new()
	var e = _npc_with_voice(voice, true, true, false)
	e._settle_engagement_barks()
	e._settle_engagement_barks()
	assert_eq(voice.combat_over, 1, "the combat-over taunt fires once per engagement, not once per settle call")
	assert_eq(voice.lost_interest, 0, "the repeat settle must not fall through to the lost-interest line either")
	_free(e, voice)
