extends GutTest

## Progression exports that used to be inert, now wired or warned: Quest.reward_reputation grants standing (and
## an unresolvable faction id is skipped without eating the rest of the reward), Perk.validate() warns on unknown
## stat keys, GoapProfile.validate() gates on override rows AND the goals[] allow-list (goals[] is enforced — see
## npc._build_goap_goals / GoapProfile.pursues), and Cutscene.auto_end is gone.

const Factions = preload("res://scripts/faction/factions.gd")

func test_quest_reward_reputation_grants_standing() -> void:
	var fac: Faction = Factions.by_id("raiders")
	assert_not_null(fac, "the raiders faction resolves on disk")
	var snapshot := Reputation.all_standings()  # restore global rep after, so other tests are unaffected
	Reputation.reset()  # start from a known zero (independent of test ordering)
	var q := Quest.new()
	q.reward_reputation = {"raiders": 5.0}
	QuestTracker._grant_quest_rewards(q)
	assert_gt(Reputation.get_reputation(fac), 0.0, "completing the quest raised raiders standing")
	Reputation.restore(snapshot)
	q = null

## A typo'd faction id in a quest's reward table must be SKIPPED, not fatal and not contagious: no phantom pool
## is minted for it, the standing already earned elsewhere is untouched, and a real faction listed AFTER the typo
## in the same reward still pays (an early-out on the first unresolvable id would silently eat it). Unknown id
## first on purpose — Dictionary iteration follows insertion order. No live player exists here, so the raiders
## delta lands unscaled by streetwise.
func test_quest_reward_reputation_ignores_unknown_faction() -> void:
	var fac: Faction = Factions.by_id("raiders")
	var snapshot := Reputation.all_standings()
	Reputation.restore({"townsfolk": 7.0})  # standing already earned before this quest completes
	var q := Quest.new()
	q.reward_reputation = {"no_such_faction": 5.0, "raiders": 2.0}
	QuestTracker._grant_quest_rewards(q)
	var after := Reputation.all_standings()
	assert_false(after.has(&"no_such_faction") or after.has("no_such_faction"),
		"an unresolvable faction id must not mint a reputation pool of its own")
	assert_almost_eq(float(after.get(&"townsfolk", 0.0)), 7.0, 0.0001,
		"a skipped faction id must leave every existing standing exactly where it was")
	assert_almost_eq(Reputation.get_reputation(fac), 2.0, 0.0001,
		"the real faction listed after the typo must still be paid in full — one bad id may not void the rest of the reward")
	assert_eq(after.size(), 2, "exactly the pre-existing pool plus the one real reward faction — nothing else was touched")
	Reputation.restore(snapshot)
	q = null

func test_perk_validate_flags_unknown_stat_key() -> void:
	var p := Perk.new()
	p.id = &"test_perk"
	p.stat_bonuses = {"strength": 2}
	assert_true(p.validate(), "a known CharacterStats key validates")
	p.stat_bonuses = {"nonexistent_stat": 2}
	assert_false(p.validate(), "an unknown stat key fails validation (and warns)")
	p = null

func test_goap_validate_enforces_goals_allow_list() -> void:
	var gp := GoapProfile.new()
	# A KNOWN goals[] entry validates fine (it names a real goal the NPC can pursue)...
	var known: Array[String] = ["Survive"]
	gp.goals = known
	assert_true(gp.validate(PackedStringArray(["Survive"]), PackedStringArray()),
		"a goals[] entry naming a real goal validates")
	# ...but an UNKNOWN entry now FAILS: goals[] is an enforced allow-list, so a typo would silently narrow the
	# pursued goal set (the NPC would never pursue the mistyped goal) — validate() must catch it at boot.
	var typo: Array[String] = ["Survvie"]
	gp.goals = typo
	assert_false(gp.validate(PackedStringArray(["Survive"]), PackedStringArray()),
		"a typo'd goals[] entry fails validate()")

func test_cutscene_has_no_auto_end() -> void:
	var c := Cutscene.new()
	var names := PackedStringArray()
	for prop in c.get_property_list():
		names.append(prop["name"])
	assert_false(names.has("auto_end"), "the inert auto_end export was removed")
	c = null
