extends GutTest

## GUT suite for the NPC hostility resolution + aggro-on-attack layer (scripts/npc/npc.gd) and
## the Perception/RangedEnemy hostility gate. Enemies are built off-tree (load().new() WITHOUT
## add_child) so _ready never runs — matching test_npc.gd / test_enemies.gd construction.

const ENEMY_PATH := "res://scripts/npc/npc.gd"
const RANGED_PATH := "res://scripts/npc/npc.gd"
const FACTION_PATH := "res://scripts/faction/faction.gd"

class TutorialPlayer extends Node3D:
	var tutorial_calls: int = 0
	func show_holster_forgiveness_tutorial(_force: bool = false) -> bool:
		tutorial_calls += 1
		return true

## A bare off-tree NPC with its ProvokeOnAttack drop-in wired by hand — mirrors what NPC._build_components
## auto-adds in-game, so the _on_damaged_by player-attack provoke path (which delegates to the component since
## 690239b) runs without a full _ready. add_child parents it under e so e.free() releases it (no orphan).
func _npc_with_provoke(path: String):
	var e = load(path).new()
	var pa := ProvokeOnAttack.new()
	e.add_child(pa)
	e._provoke_on_attack = pa
	return e

func before_each() -> void:
	Reputation.reset()  # the autoload is global; wipe standing so tests don't bleed into each other

func after_all() -> void:
	Reputation.reset()

# --- THE DEFAULT THAT KEEPS EXISTING ENEMIES HOSTILE ------------------------

func test_unaligned_enemy_defaults_to_hostile() -> void:
	# The load-bearing default: a plain Enemy sets neither faction nor disposition, so it must be
	# unaligned (faction==null) + disposition==HOSTILE => is_hostile() true. This is why every
	# existing enemy scene keeps fighting exactly as before with zero scene edits.
	var e = load(ENEMY_PATH).new()
	assert_null(e.faction,
		"NPC.faction must default null (UNALIGNED) so an enemy uses its standalone disposition")
	assert_eq(e.disposition, Disposition.Kind.HOSTILE,
		"NPC.disposition must default HOSTILE so an unaligned enemy is aggressive on sight like today")
	assert_true(e.is_hostile(),
		"A default Enemy must resolve is_hostile()==true so existing scenes never go passive")
	e.free()

func test_provoked_starts_false() -> void:
	var e = load(ENEMY_PATH).new()
	assert_false(e._provoked,
		"_provoked must start false — nothing has aggroed the NPC yet")
	e.free()

# --- Resolution priority: provoked > faction(+rep) > standalone disposition ---

func test_unaligned_neutral_is_not_hostile() -> void:
	var e = load(ENEMY_PATH).new()
	e.faction = null
	e.disposition = Disposition.Kind.NEUTRAL
	assert_false(e.is_hostile(),
		"An unaligned NEUTRAL NPC must not be hostile — it uses its standalone disposition")
	e.free()

func test_faction_overrides_standalone_disposition() -> void:
	# With a faction set, the standalone disposition is IGNORED; Reputation decides.
	var e = load(ENEMY_PATH).new()
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	f.default_disposition = Disposition.Kind.NEUTRAL
	e.faction = f
	e.disposition = Disposition.Kind.HOSTILE  # would be hostile if unaligned — but faction wins
	assert_false(e.is_hostile(),
		"A factioned NPC must resolve via Reputation (NEUTRAL here), ignoring its standalone HOSTILE disposition")
	e.free()

func test_low_rep_makes_factioned_npc_hostile() -> void:
	var e = load(ENEMY_PATH).new()
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	f.default_disposition = Disposition.Kind.NEUTRAL
	e.faction = f
	var rep_settings := ReputationSettings.new()
	Reputation.add_reputation(f, rep_settings.hostile_threshold - 1.0)
	assert_true(e.is_hostile(),
		"Tanking reputation below HOSTILE_THRESHOLD must make a factioned NPC hostile")
	e.free()

func test_provoked_overrides_friendly_faction() -> void:
	var e = load(ENEMY_PATH).new()
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	f.default_disposition = Disposition.Kind.FRIENDLY
	e.faction = f
	Reputation.add_reputation(f, ReputationSettings.new().friendly_threshold + 100.0)  # very friendly
	assert_false(e.is_hostile(),
		"Sanity: a very-high-rep FRIENDLY faction NPC is not hostile before provocation")
	e.provoke()
	assert_true(e.is_hostile(),
		"provoke() must force HOSTILE even over a FRIENDLY high-rep faction — a direct attack always aggros")
	e.free()

# --- Aggro-on-attack: player hit provokes; faction rep drops ----------------

func test_player_attack_provokes_unaligned_neutral() -> void:
	var e = _npc_with_provoke(ENEMY_PATH)
	e.faction = null
	e.disposition = Disposition.Kind.NEUTRAL
	var fake_player := Node3D.new()
	fake_player.add_to_group(&"Player")
	add_child_autofree(fake_player)
	assert_false(e.is_hostile(), "precondition: neutral NPC starts non-hostile")
	e._on_damaged_by(fake_player, false)
	assert_true(e._provoked,
		"A hit from the player must set _provoked")
	assert_true(e.is_hostile(),
		"A provoked NPC must resolve hostile (aggro-on-attack)")
	e.free()

func test_player_attack_marks_holster_tutorial_reminder_for_that_npc() -> void:
	var e = _npc_with_provoke(ENEMY_PATH)
	e.faction = null
	e.disposition = Disposition.Kind.NEUTRAL
	var fake_player := TutorialPlayer.new()
	fake_player.add_to_group(&"Player")
	add_child_autofree(fake_player)
	e._on_damaged_by(fake_player, false)
	assert_eq(fake_player.tutorial_calls, 1,
		"the first player attack that aggros a neutral NPC shows the holster-forgiveness tutorial")
	assert_true(e.should_remind_holster_forgiveness_tutorial_on_player_death(),
		"that same provoked NPC is eligible to redisplay the tutorial if it kills the player")
	e.forgive_provoke()
	assert_false(e.should_remind_holster_forgiveness_tutorial_on_player_death(),
		"once holstering forgives the NPC, dying to it no longer queues the reminder")
	e.free()

func test_non_player_attack_does_not_provoke() -> void:
	var e = _npc_with_provoke(ENEMY_PATH)
	e.faction = null
	e.disposition = Disposition.Kind.NEUTRAL
	var other := Node3D.new()  # NOT in the Player group (e.g. friendly fire)
	add_child_autofree(other)
	e._on_damaged_by(other, false)
	assert_false(e._provoked,
		"A hit from a non-player must NOT provoke — only the player aggros a neutral NPC")
	e.free()

func test_provoke_drops_faction_reputation() -> void:
	var e = load(ENEMY_PATH).new()
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	f.default_disposition = Disposition.Kind.NEUTRAL
	e.faction = f
	var before := Reputation.get_reputation(f)
	e.provoke()
	assert_eq(Reputation.get_reputation(f), before - ReputationSettings.new().provoke_penalty,
		"Provoking a factioned NPC must drop the player's reputation with that faction by PROVOKE_REP_PENALTY")
	e.free()

func test_already_hostile_does_not_double_drop_rep() -> void:
	var e = _npc_with_provoke(ENEMY_PATH)
	var f = load(FACTION_PATH).new()
	f.id = &"raiders"
	f.default_disposition = Disposition.Kind.HOSTILE  # already hostile
	e.faction = f
	var fake_player := Node3D.new()
	fake_player.add_to_group(&"Player")
	add_child_autofree(fake_player)
	e._on_damaged_by(fake_player, false)  # already hostile -> early return, no provoke
	assert_eq(Reputation.get_reputation(f), 0.0,
		"Attacking an already-hostile factioned NPC must NOT drop reputation (it was already fighting you)")
	e.free()

func test_holstering_forgives_the_provoke_rep_hit() -> void:
	# Holstering (forgive_provoke) must EXACTLY reverse the rep the provoke dropped, so a factioned NPC
	# that only went hostile because the provoke pushed rep below hostile_threshold truly stands down.
	# Before F-C32 forgive cleared _provoked but left rep at -provoke_penalty, so disposition_for() still
	# resolved HOSTILE and the faction could never be de-escalated by holstering.
	var e = load(ENEMY_PATH).new()
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	f.default_disposition = Disposition.Kind.NEUTRAL
	e.faction = f
	var before := Reputation.get_reputation(f)  # before_each Reputation.reset() -> 0.0
	e.provoke()
	assert_true(e.is_hostile(),
		"provoke() drops rep below hostile_threshold + sets _provoked, so the NPC is hostile")
	e.forgive_provoke()
	assert_false(e._provoked, "forgive clears the transient provoked flag")
	assert_eq(Reputation.get_reputation(f), before,
		"forgive restores the exact rep the provoke dropped (no live player -> unscaled round-trip to 0)")
	assert_false(e.is_hostile(),
		"flag cleared + rep restored above threshold -> the factioned NPC stands down")
	e.free()

func test_holster_forgiveness_spent_starts_false() -> void:
	var e = load(ENEMY_PATH).new()
	assert_false(e._holster_forgiveness_spent,
		"the betrayal one-shot latch must start unspent — nothing has holster-pardoned this NPC yet")
	e.free()

func test_successful_pardon_cue_always_has_art() -> void:
	# A pardon that LANDS pops the "+friend" cue, mirroring the POPUP_NEGATIVE a refused pardon pops. That art
	# must never be null on a plain NPC: NpcBarkUi.show_icon silently no-ops on a null texture, so a missing
	# fallback would make the de-escalation cue vanish and holstering look broken. popup_positive being empty
	# opts out of the separate RESCUE cue ONLY.
	var e = load(ENEMY_PATH).new()
	assert_null(e.popup_positive,
		"a plain NPC authors no popup_positive — this is the fallback case the cue must survive")
	assert_eq(e._pardon_popup_texture(), NPC.POPUP_POSITIVE,
		"with no authored art the successful-pardon cue falls back to the shipped POPUP_POSITIVE")
	e.free()

func test_successful_pardon_cue_prefers_authored_art() -> void:
	# A designer who drops custom "+friend" art on popup_positive gets it at BOTH "+friend" moments — the
	# rescue popup and the holster pardon — so one NPC never shows two different friend icons.
	var e = load(ENEMY_PATH).new()
	var custom := PlaceholderTexture2D.new()
	e.popup_positive = custom
	assert_eq(e._pardon_popup_texture(), custom,
		"an authored popup_positive re-skins the successful-pardon cue too, not just the rescue cue")
	e.free()
	custom = null

func test_holster_forgiveness_is_one_shot_per_life() -> void:
	# THE FREE-KILL FIX: holstering pardons a provoked NPC at most ONCE per life. Re-attacking a pardoned NPC
	# (which re-provokes it) and holstering AGAIN must NOT stand it down — otherwise the player could spam the
	# hold-R holster toggle to keep de-aggroing a mob they keep shooting and kill it for free.
	assert_true(GameSettings.npc_ai.holster_forgiveness_once,
		"this test assumes the one-shot toggle is on (the shipped default)")
	var e = load(ENEMY_PATH).new()
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	f.default_disposition = Disposition.Kind.NEUTRAL
	e.faction = f
	e.provoke()
	e.forgive_provoke()
	assert_false(e._provoked, "the FIRST holster pardon still works — forgive clears _provoked")
	assert_false(e.is_hostile(), "...and the neutral stands down")
	assert_true(e._holster_forgiveness_spent, "the one-shot latch is now spent for this life")
	e.provoke()  # the player re-attacks -> react() re-provokes it
	assert_true(e.is_hostile(), "re-attack re-provokes: hostile again")
	e.forgive_provoke()  # holster AGAIN — must be refused now
	assert_true(e._provoked,
		"the SECOND holster is REFUSED: a re-attacked NPC won't fall for it twice")
	assert_true(e.is_hostile(),
		"...so it stays hostile to the death — the spam-holster free-kill loop is closed")
	e.free()

func test_holster_forgiveness_once_off_restores_infinite_pardons() -> void:
	# The escape hatch: with the toggle OFF, holstering forgives every time (the old, exploitable behaviour) —
	# proves the fix is gated on GameSettings.npc_ai.holster_forgiveness_once and a designer can opt back out.
	var prev: bool = GameSettings.npc_ai.holster_forgiveness_once
	GameSettings.npc_ai.holster_forgiveness_once = false
	var e = load(ENEMY_PATH).new()
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	f.default_disposition = Disposition.Kind.NEUTRAL
	e.faction = f
	e.provoke()
	e.forgive_provoke()
	e.provoke()
	e.forgive_provoke()  # second pardon ALSO works when the toggle is off
	assert_false(e._provoked, "toggle off -> a re-provoked NPC is forgiven again (old behaviour)")
	assert_false(e.is_hostile(), "...and stands back down")
	e.free()
	GameSettings.npc_ai.holster_forgiveness_once = prev  # restore the shared autoload for other tests

## A bare off-tree NPC in the only state the holster pardon applies to: a NEUTRAL factioned townsperson (genuinely
## hostile NPCs are never provoked, so forgive_provoke no-ops on them). Caller frees it.
func _provokable_neutral():
	var e = load(ENEMY_PATH).new()
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	f.default_disposition = Disposition.Kind.NEUTRAL
	e.faction = f
	return e

func test_fleeing_npc_is_always_holster_forgivable() -> void:
	# THE MERCY EXEMPTION: the betrayal one-shot exists to close the free-kill farm on a mob that keeps SHOOTING
	# BACK. An NPC that is running away never fires, so refusing its stand-down buys no balance — it only strands a
	# terrified townsperson sprinting from the player for the rest of its life with no way to call it off.
	assert_true(GameSettings.npc_ai.holster_forgiveness_once,
		"this test assumes the one-shot toggle is on (the shipped default)")
	assert_true(GameSettings.npc_ai.fleeing_always_forgivable,
		"this test assumes the flee exemption is on (the shipped default)")
	var e = _provokable_neutral()
	e.provoke()
	e.forgive_provoke()
	assert_true(e._holster_forgiveness_spent,
		"the first pardon still spends the one-shot latch, exactly as before")
	e.provoke()  # the player re-attacks: a FIGHTER would now be unforgivable to the death
	e.threat_response = NPC.ThreatResponse.FLEE  # ...but this one runs instead of fighting back
	e.forgive_provoke()
	assert_false(e._provoked,
		"a FLEEING NPC is pardoned even with the one-shot spent — holstering always calls off a runner")
	assert_false(e.is_hostile(),
		"...so it stands back down instead of fleeing the player forever")
	e.free()

func test_break_and_flee_reopens_a_spent_holster_pardon() -> void:
	# The real runtime route into the exemption: PanicOnDamage's fear roll trips mid-fight and calls break_and_flee(),
	# flipping threat_response to FLEE. A coward the player already forgave once must become forgivable again the
	# moment it breaks — same rule as an authored FLEE civilian, reached through the panic path instead.
	var e = _provokable_neutral()
	e.provoke()
	e.forgive_provoke()
	e.provoke()
	assert_true(e.is_hostile(), "re-attacked after its pardon: hostile again")
	e.break_and_flee()  # _voice is null off-tree, so this is just the threat_response flip (no bark)
	assert_true(e.is_fleeing(), "break_and_flee flips the NPC onto the FLEE response")
	e.forgive_provoke()
	assert_false(e._provoked,
		"a fighter that BROKE and ran is forgivable again — the free-kill farm it guarded no longer exists")
	assert_false(e.is_hostile(), "...and it stops being hostile, so the chase ends")
	e.free()

func test_break_and_flee_stashes_the_authored_threat_response_for_pooling() -> void:
	# threat_response is an AUTHORED @export that break_and_flee MUTATES, which quietly makes it PER-LIFE state under
	# NPC pooling — reset_for_reuse restores it from this stash. Without it a reused body that panicked last life comes
	# back a permanent coward: it never fires again (the GOAP Fire actions are gated on `not is_fleeing()`) and is
	# permanently holster-forgivable. The full reset_for_reuse is in-tree-only (transforms/inventory), so pin the stash.
	var e = load(ENEMY_PATH).new()
	assert_eq(e._pre_panic_threat_response, -1,
		"nothing has panicked this NPC yet, so no authored response is stashed")
	e.break_and_flee()
	assert_eq(e._pre_panic_threat_response, int(NPC.ThreatResponse.FIGHT),
		"the first break stashes the AUTHORED response so pooling can put the fighter back")
	e.break_and_flee()  # PanicOnDamage early-returns on is_fleeing(), but a re-entry must not corrupt the stash
	assert_eq(e._pre_panic_threat_response, int(NPC.ThreatResponse.FIGHT),
		"a second break must NOT overwrite the stash with FLEE — that would make the restore a no-op")
	e.free()

func test_fleeing_always_forgivable_off_restores_the_strict_one_shot() -> void:
	# The escape hatch: with the exemption OFF, a fleer obeys holster_forgiveness_once like anyone else — proves the
	# mercy rule is gated on GameSettings.npc_ai.fleeing_always_forgivable and a designer can opt back out.
	var prev: bool = GameSettings.npc_ai.fleeing_always_forgivable
	GameSettings.npc_ai.fleeing_always_forgivable = false
	var e = _provokable_neutral()
	e.provoke()
	e.forgive_provoke()
	e.provoke()
	e.threat_response = NPC.ThreatResponse.FLEE
	e.forgive_provoke()  # refused now: fleeing no longer buys a second pardon
	assert_true(e._provoked,
		"exemption off -> even a fleeing NPC is held to the betrayal one-shot")
	e.free()
	GameSettings.npc_ai.fleeing_always_forgivable = prev  # restore the shared autoload for other tests

func test_fleeing_exemption_does_not_pardon_an_unprovoked_hostile() -> void:
	# Guard rail: the exemption widens WHO can be pardoned, never WHAT gets pardoned. A genuinely-hostile raider
	# that breaks and runs was never _provoked, so forgive_provoke must still no-op — holstering can't turn a real
	# enemy friendly just because it's low on HP and running.
	var e = load(ENEMY_PATH).new()
	e.disposition = Disposition.Kind.HOSTILE
	e.threat_response = NPC.ThreatResponse.FLEE
	assert_true(e.is_hostile(), "an unaligned HOSTILE NPC is hostile by disposition, not by provoke")
	e.forgive_provoke()
	assert_true(e.is_hostile(),
		"forgive_provoke still no-ops on a never-provoked enemy — the flee exemption sits ABOVE the _provoked guard")
	assert_false(e._holster_forgiveness_spent,
		"...and never even reaches the latch, so nothing is spent")
	e.free()

# --- Death settlement: an NPC that KILLS the player squares a provoked grudge ---

## Duck-typed stand-in for an NPC in the death-settlement sweep. HostilityHelpers.settle_provoked_grudges is
## list-injected + duck-typed, so it unit-tests without building real NPCs — this mirrors exactly the two
## methods it calls.
class SettleStub extends Node:
	var hostile: bool = true    ## what is_hostile() reports — the killer gate reads this
	var provoked: bool = true   ## whether we still have a grudge to settle
	var stand_downs: int = 0    ## how many times the sweep ASKED us to stand down
	func is_hostile() -> bool:
		return hostile
	func stand_down_on_player_death() -> bool:
		stand_downs += 1
		if not provoked:
			return false
		provoked = false
		return true

func test_npc_exposes_the_death_settlement_hook() -> void:
	var n = load(ENEMY_PATH).new()
	assert_true(n.has_method("stand_down_on_player_death"),
		"NPC must expose stand_down_on_player_death — settle_provoked_grudges calls it DUCK-TYPED, so a rename would silently disable the whole death settlement with no compile error")
	n.free()

func test_killing_the_player_settles_a_provoked_grudge() -> void:
	# The player shot at a neutral townsperson, it fought back and WON: the grudge is square, so it stands down
	# instead of hunting the respawned player forever. Same de-escalation as a holster pardon — including the
	# faction-rep restore, without which the soured faction would just resolve HOSTILE again.
	var e = _provokable_neutral()
	var before := Reputation.get_reputation(e.faction)  # before_each Reputation.reset() -> 0.0
	e.provoke()
	assert_true(e.is_hostile(), "the provoke turns the neutral townsperson hostile and sours its faction")
	assert_true(e.stand_down_on_player_death(),
		"killing the player settles the grudge and reports that it actually stood down")
	assert_false(e._provoked, "the provoked flag is dropped, exactly as a holster pardon drops it")
	assert_eq(Reputation.get_reputation(e.faction), before,
		"the settlement restores the EXACT rep the provoke took — leave it soured and disposition_for() re-reads HOSTILE, making the pardon a no-op")
	assert_false(e.is_hostile(), "flag cleared + rep restored -> a neutral townsperson again by the time you respawn")
	assert_false(e._holster_forgiveness_spent,
		"dying must NOT spend the one-shot holster pardon: the player never talked anyone down here, so it can't cost them the pardon they may still need")
	e.free()

func test_death_settlement_leaves_the_holster_pardon_intact() -> void:
	# The consequence of not spending the latch: the fresh life can still de-escalate the normal way.
	assert_true(GameSettings.npc_ai.holster_forgiveness_once,
		"this test assumes the one-shot toggle is on (the shipped default)")
	var e = _provokable_neutral()
	e.provoke()
	e.stand_down_on_player_death()
	e.provoke()  # the respawned player shoots at them again
	e.forgive_provoke()
	assert_false(e._provoked,
		"holstering still pardons after a death settlement — the death didn't burn the betrayal one-shot")
	e.free()

func test_death_settlement_never_pardons_a_predisposed_hostile() -> void:
	# Guard rail, same shape as the flee exemption's: the settlement clears PROVOKES, never authored hostility.
	var e = load(ENEMY_PATH).new()
	e.disposition = Disposition.Kind.HOSTILE
	assert_false(e.stand_down_on_player_death(),
		"a never-provoked enemy has no grudge to settle, so it reports false")
	assert_true(e.is_hostile(),
		"...and a raider that kills you is still hunting you when you respawn")
	e.free()

func test_settle_provoked_grudges_sweeps_every_provoked_npc() -> void:
	# The respawn-side half: the sweep is deliberately group-wide, not killer-only, because the provoke rep hit is
	# a SHARED faction pool — pardoning just the killer would leave the faction soured below hostile_threshold and
	# resolve HOSTILE anyway. Eligibility was already decided at death by death_settles_grudges(), so the sweep
	# itself takes no killer and re-checks nothing.
	var killer := SettleStub.new()
	var mate := SettleStub.new()
	var calm := SettleStub.new()
	calm.provoked = false  # never provoked — nothing to settle
	add_child_autofree(killer)
	add_child_autofree(mate)
	add_child_autofree(calm)
	assert_eq(HostilityHelpers.settle_provoked_grudges([killer, mate, calm, null]), 2,
		"both PROVOKED NPCs stand down (killer + mate); the unprovoked one answers false and a null entry is skipped")
	assert_false(killer.provoked, "the killer drops its own grudge — it got what it was fighting for")
	assert_false(mate.provoked,
		"...and so does every other provoked NPC, or the shared faction rep would keep the whole group hostile")
	assert_eq(calm.stand_downs, 1, "the unprovoked NPC is still ASKED; it simply has nothing to settle")

func test_death_settles_grudges_needs_a_hostile_npc_killer() -> void:
	# The rule is JUDGED at death (while the killer is live) and APPLIED on the respawn. Nobody won the fight when
	# you fall off a ledge, cook yourself with your own grenade, or eat a friendly companion's stray round — so
	# none of those arm the settlement at all.
	var killer := SettleStub.new()
	add_child_autofree(killer)
	assert_true(HostilityHelpers.death_settles_grudges(killer),
		"a live, HOSTILE NPC killer squares the score — the respawn will stand the provoked group down")
	assert_false(HostilityHelpers.death_settles_grudges(null),
		"no killer (a fall, a hazard, self-inflicted) settles nothing")
	var ally := SettleStub.new()
	ally.hostile = false
	add_child_autofree(ally)
	assert_false(HostilityHelpers.death_settles_grudges(ally),
		"a NON-hostile killer — a friendly companion's stray shot — doesn't settle anything either")
	var hazard := Node.new()
	add_child_autofree(hazard)
	assert_false(HostilityHelpers.death_settles_grudges(hazard),
		"a non-NPC killer (a hazard node, a trap) has no stand_down hook, so it can't settle a grudge")
	assert_eq(killer.stand_downs, 0,
		"judging the rule must never stand anyone down — that is the respawn sweep's job, not this predicate's")

func test_deaggro_on_player_death_off_settles_nothing() -> void:
	# The escape hatch: proves the rule is gated on GameSettings.npc_ai.deaggro_on_player_death and a designer
	# can opt back out to the old behaviour (holstering is then the only way to call a provoked mob off).
	var prev: bool = GameSettings.npc_ai.deaggro_on_player_death
	GameSettings.npc_ai.deaggro_on_player_death = false
	var killer := SettleStub.new()
	add_child_autofree(killer)
	assert_false(HostilityHelpers.death_settles_grudges(killer),
		"toggle off -> even a hostile NPC killer never arms the settlement, so the respawn sweep never runs")
	assert_true(killer.provoked, "...and the provoked NPC keeps its grudge through your death")
	GameSettings.npc_ai.deaggro_on_player_death = prev  # restore the shared autoload for other tests

func test_attack_focuses_the_attacker_over_the_nearest() -> void:
	# Being hit must lock the attacker as the target immediately (and remember it as _last_attacker so
	# _acquire_target keeps favouring it), so a closer bystander can't distract the NPC off its aggressor.
	var e = load(RANGED_PATH).new()
	e.disposition = Disposition.Kind.HOSTILE
	var fake_player := Node3D.new()
	fake_player.add_to_group(&"Player")
	add_child_autofree(fake_player)
	e._on_damaged_by(fake_player, false)
	assert_eq(e._last_attacker, fake_player,
		"A hit must record the attacker as _last_attacker so re-scans favour it over the nearest hostile")
	assert_eq(e._target, fake_player,
		"A hit must immediately focus the attacker, not wait for the retarget throttle")
	e.free()

# --- Perception hostility gate ----------------------------------------------

func test_perception_has_hostility_gate_defaulting_true() -> void:
	var p := Perception.new()
	assert_true(p.is_hostile,
		"Perception.is_hostile must default true so a bare/old-style enemy senses exactly as before")
	p.free()

func test_perception_non_hostile_cannot_see_or_hear() -> void:
	var p := Perception.new()
	p.is_hostile = false
	assert_false(p.can_see(),
		"A non-hostile Perception must never see the player — the gate short-circuits can_see()")
	assert_false(p.can_hear(),
		"A non-hostile Perception must never hear the player — the gate short-circuits can_hear()")
	p.free()

# --- RangedEnemy still exposes the aggro hook + legacy handler --------------

func test_ranged_enemy_has_aggro_and_legacy_handlers() -> void:
	var n = load(RANGED_PATH).new()
	assert_true(n.has_method("_on_damaged_by"),
		"RangedEnemy must expose _on_damaged_by — the attacker-aware aggro/turn-toward-shooter path")
	assert_true(n.has_method("_on_damaged"),
		"RangedEnemy must keep _on_damaged — the damaged-signal freeze-frame handler wired in enemy.tscn")
	assert_true(n.has_method("is_hostile"),
		"RangedEnemy must inherit is_hostile() so the AI can gate on it")
	n.free()

# --- Co-aligned alliance (HostilityHelpers.npc_vs_npc_allied) — drives the "Murderer!" death reaction ---

func test_same_faction_npcs_are_allied() -> void:
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	assert_true(HostilityHelpers.npc_vs_npc_allied(f, f),
		"Two NPCs sharing the SAME faction must be co-aligned (allies)")

func test_same_faction_id_counts_as_allied() -> void:
	var a = load(FACTION_PATH).new()
	var b = load(FACTION_PATH).new()
	a.id = &"townsfolk"
	b.id = &"townsfolk"
	assert_true(HostilityHelpers.npc_vs_npc_allied(a, b),
		"Distinct faction resources that share an id must still count as co-aligned")

func test_positive_relation_is_allied() -> void:
	var a = load(FACTION_PATH).new()
	var b = load(FACTION_PATH).new()
	a.id = &"caravans"
	b.id = &"townsfolk"
	a.relations = {&"townsfolk": 1.0}
	assert_true(HostilityHelpers.npc_vs_npc_allied(a, b),
		"A positive (>0) faction-vs-faction relation must count as allied")

func test_enemy_or_neutral_relation_is_not_allied() -> void:
	var a = load(FACTION_PATH).new()
	var b = load(FACTION_PATH).new()
	a.id = &"raiders"
	b.id = &"townsfolk"
	a.relations = {&"townsfolk": -1.0}
	assert_false(HostilityHelpers.npc_vs_npc_allied(a, b),
		"An enemy (negative) relation must NOT count as allied")
	a.relations = {}
	assert_false(HostilityHelpers.npc_vs_npc_allied(a, b),
		"An unlisted (zero) relation must NOT count as allied")

func test_unaligned_faction_has_no_allies() -> void:
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	assert_false(HostilityHelpers.npc_vs_npc_allied(null, f),
		"A null (unaligned) faction has no allies")
	assert_false(HostilityHelpers.npc_vs_npc_allied(f, null),
		"Nothing is allied with a null (unaligned) faction")

# --- Death-witness reaction API + lines (npc.gd) ---------------------------

func test_npc_exposes_death_witness_api() -> void:
	var n = load(ENEMY_PATH).new()
	assert_true(n.has_method("_witness_death"),
		"NPC must expose _witness_death — a nearby NPC reacts when the player kills another")
	assert_true(n.has_method("_announce_death_to_witnesses"),
		"NPC must expose _announce_death_to_witnesses — the dying NPC notifies nearby witnesses")
	assert_true(n.has_method("_is_ally_of"),
		"NPC must expose _is_ally_of — the co-aligned check behind the 'Murderer!' reaction")
	n.free()

func test_death_witness_pools_ship_unauthored() -> void:
	# Speech is authored content: witness reaction pools ship EMPTY (silent) until a designer fills
	# BarkSet death_ally/death_approve/death_question (react_remark guards lines.is_empty()).
	assert_eq(NPC.DEATH_ALLY_LINES.size(), 0, "DEATH_ALLY_LINES ships unauthored (empty = silent)")
	assert_eq(NPC.DEATH_APPROVE_LINES.size(), 0, "DEATH_APPROVE_LINES ships unauthored (empty = silent)")
	assert_eq(NPC.DEATH_QUESTION_LINES.size(), 0, "DEATH_QUESTION_LINES ships unauthored (empty = silent)")

# --- Reputation bounds + kill penalty --------------------------------------

func test_reputation_clamps_to_bounds() -> void:
	var f = load(FACTION_PATH).new()
	f.id = &"townsfolk"
	var rep_settings := ReputationSettings.new()
	Reputation.add_reputation(f, 10000.0)
	assert_eq(Reputation.get_reputation(f), rep_settings.rep_max,
		"Reputation must clamp UP to REP_MAX, not run away to +infinity")
	Reputation.add_reputation(f, -100000.0)
	assert_eq(Reputation.get_reputation(f), rep_settings.rep_min,
		"Reputation must clamp DOWN to REP_MIN")

func test_kill_rep_penalty_and_clamp_range_are_sane() -> void:
	var rep_settings := ReputationSettings.new()
	assert_gt(rep_settings.kill_penalty, 0.0,
		"KILL_REP_PENALTY must be a positive amount of reputation lost per faction kill")
	assert_lt(rep_settings.rep_min, rep_settings.rep_max,
		"REP_MIN must be below REP_MAX (a valid clamp range)")

# --- Protector / bodyguard + wounded-ally + temperament API ----------------

func test_npc_exposes_protector_and_wounded_api() -> void:
	var n = load(ENEMY_PATH).new()
	assert_true(n.has_method("guard"),
		"NPC must expose guard() — bodyguard ANY character, not just the player")
	assert_true(n.has_method("stop_guarding"),
		"NPC must expose stop_guarding()")
	assert_true(n.has_method("_protectee"),
		"NPC must expose _protectee() — the generic 'who do I defend' hook")
	assert_true(n.has_method("_cry_wounded"),
		"NPC must expose _cry_wounded() — the wounded-ally bark")
	assert_eq(n.temperament, 0.0,
		"temperament default 0.0 = fearless (never flees from being hurt) until tuned")
	assert_null(n._protectee(),
		"a fresh NPC defends nobody (no leader, no guard target)")
	n.free()

func test_npc_greet_api() -> void:
	assert_eq(NPC.GREET_LINES.size(), 0,
		"GREET_LINES ships unauthored (empty = silent) — greeting text is designer content")
	var n = load(ENEMY_PATH).new()
	assert_true(n.has_method("greet"),
		"NPC must expose greet() — the FNV-style look-at hover greeting")
	n.greet()  # safe off-tree: a hostile-by-default bare NPC early-returns, and no talkable -> no-op
	assert_true(true, "greet() must be safe to call off-tree")
	n.free()

func test_npc_combat_bark_api() -> void:
	# The combat call-out pools ship unauthored (empty = silent); the API surface below is what's load-bearing.
	assert_eq(NPC.RELOAD_LINES.size(), 0, "RELOAD_LINES ships unauthored (empty = silent)")
	assert_eq(NPC.COMBAT_END_LINES.size(), 0, "COMBAT_END_LINES ships unauthored (empty = silent)")
	assert_eq(NPC.LOST_INTEREST_LINES.size(), 0, "LOST_INTEREST_LINES ships unauthored (empty = silent)")
	var n = load(ENEMY_PATH).new()
	assert_true(n.has_method("_try_reload_bark"),
		"NPC must expose _try_reload_bark() — the reload shout, fired from _act_alerted on reload")
	assert_true(n.has_method("_try_combat_end_bark"),
		"NPC must expose _try_combat_end_bark() — the combat-over shout, fired on the return to UNAWARE")
	assert_true(n.has_method("_try_lost_interest_bark"),
		"NPC must expose _try_lost_interest_bark() — the gave-up-searching shout, fired on the return to UNAWARE")
	n._try_reload_bark()       # safe off-tree: bare NPC has hp 0 (no _ready) -> early-returns, no talkable
	n._try_combat_end_bark()
	n._try_lost_interest_bark()
	assert_true(true, "all three combatant/sentry barks must be safe to call off-tree")
	n.free()

func test_npc_unarmed_fist_fallback_surface() -> void:
	# With nothing equipped, an NPC falls back to a weak "fists" melee. The swing (the _act_unarmed facade ->
	# NpcCombat.act_unarmed -> _punch) needs a live target + take_damage, so it's manual-verify; here we pin the FISTS
	# weapon + the surface. H2: the NPC keeps the _act_unarmed FACADE, but the fist hit (_punch) moved to NpcCombat.
	assert_not_null(NPC.FISTS, "NPC.FISTS must be the fallback fists weapon for unarmed attacks")
	assert_gt(NPC.FISTS.damage, 0.0, "fists deal some (weak) damage")
	var n = load(ENEMY_PATH).new()
	assert_true(n.has_method("_act_unarmed"),
		"NPC must expose the _act_unarmed() facade — the close-in-and-punch loop when it has no usable gun")
	n.free()
	var combat = NpcCombat.new()
	assert_true(combat.has_method("_punch"),
		"NpcCombat must expose _punch() — lands one weak fist hit on the current target (moved off npc.gd in H2)")
	combat.free()

func test_unarmed_attack_paces_to_fist_cadence_and_damage() -> void:
	# So a punch winds up on its own cadence, an unarmed NPC's timer + damage readout use the FISTS weapon
	# (not a stale/absent gun). Off-tree -> _can_fight_with_gun() is false (no equipped weapon).
	var n = load(ENEMY_PATH).new()
	var expected_interval: float = maxf(0.05, NPC.FISTS.attack_speed * n.rate_of_fire_factor)
	assert_almost_eq(n._shot_interval(), expected_interval, 0.0001,
		"an unarmed NPC's attack interval is the fists' cadence, so the charge wind-up paces to the punch")
	assert_almost_eq(n._attack_damage(), NPC.FISTS.damage, 0.0001,
		"an unarmed NPC reports the fists' damage on the player's threat indicator, not a stale gun's")
	n.free()

func test_melee_weapons_do_not_use_ranged_attack_telegraphs() -> void:
	var melee: WeaponData = load("res://resources/weapons/melee.tres")
	var fists: WeaponData = NPC.FISTS
	var authored_sniper: WeaponData = load("res://resources/weapons/sniper_wep.tres")
	var unsighted_sniper: WeaponData = authored_sniper.duplicate(true)
	unsighted_sniper.has_laser_sight = false
	assert_false(melee.has_laser_sight,
		"the authored melee weapon keeps its visible laser sight disabled")
	assert_false(NPC._weapon_uses_ranged_attack_telegraphs(melee),
		"a melee weapon should not schedule charge stings, incoming beeps, aim radials, or sniper glints")
	assert_false(NPC._weapon_uses_ranged_attack_telegraphs(fists),
		"fists are the same close-range warning profile as melee weapons")
	assert_false(unsighted_sniper.has_laser_sight,
		"the test sniper hides the visible beam independently from ranged warning audio")
	assert_true(NPC._weapon_uses_ranged_attack_telegraphs(unsighted_sniper),
		"an unsighted sniper still keeps ranged attack telegraphs like the charge sting")

func test_engage_range_scales_with_weapon() -> void:
	# The standoff distance (how close the NPC wants to be) scales with the equipped weapon's effective_range
	# — a long-range weapon holds far, a short one closes in — and is NOT hard-capped by fire_range. A
	# range-less weapon (effective_range 0, e.g. the thrown rock) falls back to fire_range.
	var n = load(ENEMY_PATH).new()
	var sniper := WeaponData.new()
	sniper.effective_range = 500.0
	var shotgun := WeaponData.new()
	shotgun.effective_range = 5.0
	var rangeless := WeaponData.new()
	rangeless.effective_range = 0.0
	assert_almost_eq(n._engage_range_for(sniper), 500.0, 0.0001,
		"a long-range weapon engages at its full effective_range (not capped by fire_range)")
	assert_almost_eq(n._engage_range_for(shotgun), 5.0, 0.0001,
		"a short-range weapon closes right in")
	assert_almost_eq(n._engage_range_for(rangeless), minf(n.fire_range, NpcAiSettings.new().unranged_aim_fallback), 0.0001,
		"a range-less weapon falls back to fire_range (held to npc_ai.unranged_aim_fallback)")
	n.free()
	sniper = null
	shotgun = null
	rangeless = null

func test_engage_range_unarmed_is_fist_reach() -> void:
	var n = load(ENEMY_PATH).new()  # off-tree: no _weapon -> _can_fight_with_gun() false -> unarmed branch
	assert_almost_eq(n._engage_range(), NPC.FISTS.effective_range, 0.0001,
		"unarmed, the engage distance is the fists' reach — the standoff still scales with the 'weapon'")
	n.free()

func test_entering_dialogue_clears_the_bark_bubble() -> void:
	# Entering a conversation force-clears any live bark balloon (so it doesn't hang over the dialogue) and its
	# no-overlap gate. The bubble itself now lives on the NpcBarkUi child (covered below); here we pin the gate
	# clear, the off-tree-testable side effect _clear_bark_bubble performs through set_in_dialogue.
	var n = load(ENEMY_PATH).new()
	n._bark_until_msec = Time.get_ticks_msec() + 100000  # pretend a bark is currently on screen
	n.set_in_dialogue(true)
	assert_eq(n._bark_until_msec, 0,
		"entering dialogue clears the bark's no-overlap gate")
	assert_null(n._bark_ui, "off-tree NPC has no NpcBarkUi child, so the facade's bubble-clear is a safe no-op")
	n.free()

## A minimal stand-in for the BodyModelSwap child: it exposes character_parts() so NPC._find_body_swap()
## finds it (that's the duck-typed marker), and records whether lower_arms() was called.
class _StubSwap extends Node:
	var lowered := false
	func character_parts() -> Array: return []
	func lower_arms() -> void: lowered = true

func test_entering_dialogue_lowers_raised_arms() -> void:
	# An NPC you talk to always puts its arms down: dialogue pauses the world (freezing the BodyModelSwap gait), so
	# a raised gun-hold / fists / airborne pose would hang for the whole chat. set_in_dialogue(true) forwards to the
	# swap child's lower_arms(). Verified with a stub swap (a real BodyModelSwap needs _ready, which CLAUDE.md bars).
	var n = load(ENEMY_PATH).new()
	var swap := _StubSwap.new()
	n.add_child(swap)  # parented so n.free() releases it
	n.set_in_dialogue(true)
	assert_true(swap.lowered, "entering dialogue drops the NPC's arms via the swap child's lower_arms()")
	n.free()

func test_bark_ui_clear_drops_the_bubble() -> void:
	# The bark speech-bubble lifecycle now lives on NpcBarkUi (split off npc.gd). show_text builds + stores it;
	# clear() (what _clear_bark_bubble delegates to on entering dialogue) frees it + drops the handle.
	var ui := NpcBarkUi.new()
	add_child_autofree(ui)
	ui.show_text("Contact!")
	assert_not_null(ui._bark_bubble, "show_text builds a live bark bubble")
	ui.clear()
	assert_null(ui._bark_bubble, "clear() drops the bubble handle")

func test_bark_duration_scales_with_line_length() -> void:
	# _emit_bark suppresses a new bark while the previous bubble is still up (no talking over itself); the
	# window is _bark_duration_ms, which tracks _popup_text's on-screen time. The suppression itself needs a
	# live tree (await + tween), so it's manual-verify; here we pin the duration math it relies on.
	var n = load(ENEMY_PATH).new()
	var short_ms: int = n._bark_duration_ms("Hi")
	var long_ms: int = n._bark_duration_ms("This is a much, much longer call-out that lingers on screen.")
	assert_gt(short_ms, 0, "a bark bubble has a positive on-screen duration")
	assert_gt(long_ms, short_ms, "a longer line stays up longer, so its no-overlap window is longer too")
	n.free()
