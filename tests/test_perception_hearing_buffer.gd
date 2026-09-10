extends GutTest

## The HEARING REACTION BUFFER (GameSettings.npc_ai.hearing_reaction_time / _jitter): a cold enemy that hears
## something BANKS the reaction and fires it a beat later, instead of escalating on the frame the sound landed.
##
## Everything here runs on a bare off-tree Perception. That is possible at all because the front door,
## Perception.hear_noise(pos, seed_radius, source), takes a plain Vector3 and never reads a transform -- unlike
## can_hear(), which reads global_position and is why the hearing path has never had a unit test before.
##
## The tuning is a GLOBAL mutable resource, so every test that touches it saves and restores SYNCHRONOUSLY
## (GUT asserts don't halt, so the restore always runs) -- a leaked value here would poison every later test file
## in the full-suite run, which is exactly the cross-test pollution trap this suite has been bitten by before.

func _perc() -> Perception:
	return Perception.new()


func _with_delay(time: float, jitter: float, body: Callable) -> void:
	var prior_t: float = GameSettings.npc_ai.hearing_reaction_time
	var prior_j: float = GameSettings.npc_ai.hearing_reaction_jitter
	GameSettings.npc_ai.hearing_reaction_time = time
	GameSettings.npc_ai.hearing_reaction_jitter = jitter
	body.call()
	GameSettings.npc_ai.hearing_reaction_time = prior_t
	GameSettings.npc_ai.hearing_reaction_jitter = prior_j


# --- reaction_delay: the pure per-NPC resolve -----------------------------------------------------------------

func test_zero_dials_resolve_to_zero_delay() -> void:
	assert_eq(Perception.reaction_delay(0.0, 0.0, 12345), 0.0,
		"both dials off -> no delay at all, which is what makes the class default byte-identical to the pre-buffer behaviour")

func test_no_jitter_resolves_to_exactly_the_base_for_every_npc() -> void:
	assert_eq(Perception.reaction_delay(0.35, 0.0, 111), 0.35, "jitter 0 -> this NPC reacts on exactly hearing_reaction_time")
	assert_eq(Perception.reaction_delay(0.35, 0.0, 999999), 0.35, "...and so does every other NPC, whatever its instance id")

func test_jitter_stays_inside_the_authored_band() -> void:
	for id in [1, 2, 3, 5000, 123456, 987654321]:
		var d := Perception.reaction_delay(0.35, 0.15, id)
		assert_between(d, 0.20, 0.50,
			"a jittered delay must stay within +/- jitter of the base (id %d resolved %f)" % [id, d])

func test_jitter_decorrelates_neighbouring_instance_ids() -> void:
	# The whole point of hashing rather than a modulo: Godot hands CONSECUTIVE instance ids to a wave spawned
	# together, and that cohort is exactly the one that must not turn in unison.
	var seen := {}
	for id in range(1000, 1040):
		seen[Perception.reaction_delay(0.35, 0.15, id)] = true
	assert_gt(seen.size(), 20,
		"40 consecutive instance ids must spread across many distinct delays -- a modulo would bunch them into a convoy")

func test_jitter_wider_than_the_base_never_goes_negative() -> void:
	for id in [7, 42, 31337, 555555]:
		assert_gte(Perception.reaction_delay(0.1, 0.5, id), 0.0,
			"authoring jitter wider than the base is safe -- the delay is floored at 0, never negative (id %d)" % id)

func test_reaction_delay_is_stable_for_one_npc() -> void:
	# A per-NPC CONSTANT is why no fifth latch field is needed to store the roll (and so no fifth reset obligation),
	# and why a pooled body keeps its slot across reuse instead of re-rolling into the convoy.
	var a := Perception.reaction_delay(0.35, 0.15, 24680)
	assert_eq(Perception.reaction_delay(0.35, 0.15, 24680), a, "the same NPC resolves the same delay every time it is asked")


# --- the buffer: arm, drain, fire -----------------------------------------------------------------------------

func test_zero_delay_reacts_on_the_very_same_statement() -> void:
	# THE PARITY REGRESSION GUARD. The dials' class default is 0, and "0 = the old same-frame reaction" is a
	# promise the export doc makes. If this ever goes red the buffer has stopped being opt-in.
	_with_delay(0.0, 0.0, func() -> void:
		var p := _perc()
		watch_signals(p)
		var spot := Vector3(4.0, 0.0, -1.0)
		p.hear_noise(spot, 3.0)
		assert_eq(p.state, Perception.State.INVESTIGATING, "delay 0 -> hear_noise escalates on the spot, exactly as investigate_point used to")
		assert_eq(p.last_known_position, spot, "at the noise")
		assert_false(p.hearing_pending(), "and nothing is left banked")
		assert_signal_emitted(p, "just_spotted", "the '!' fires on the same statement")
		p.free())

func test_a_real_delay_banks_the_reaction_without_reacting() -> void:
	_with_delay(0.4, 0.0, func() -> void:
		var p := _perc()
		watch_signals(p)
		p.hear_noise(Vector3(2.0, 0.0, 2.0), 3.0)
		assert_eq(p.state, Perception.State.UNAWARE, "the sound landed but the enemy has NOT reacted yet -- that beat is the whole feature")
		assert_true(p.hearing_pending(), "the reaction is committed to, just not delivered")
		assert_almost_eq(p.hearing_pending_time(), 0.4, 0.001, "with jitter 0 the countdown starts at exactly hearing_reaction_time")
		assert_signal_not_emitted(p, "just_spotted", "and NOTHING is telegraphed at the stimulus -- the '!' IS the reaction")
		p.free())

func test_the_banked_reaction_fires_once_the_buffer_drains() -> void:
	_with_delay(0.4, 0.0, func() -> void:
		var p := _perc()
		var spot := Vector3(6.0, 0.0, -3.0)
		p.hear_noise(spot, 5.0)
		watch_signals(p)  # after the arm, so only the FIRE's signal is counted
		p.sense(0.2)
		assert_eq(p.state, Perception.State.UNAWARE, "half a buffer in, still no reaction")
		p.sense(0.3)
		assert_eq(p.state, Perception.State.INVESTIGATING, "the buffer drained -> the enemy reacts")
		assert_eq(p.last_known_position, spot, "at the spot latched when the noise was HEARD")
		assert_eq(p._search.seed_radius, 5.0, "and with the search ring sized by how loud it was, not the generic tuning base")
		assert_signal_emitted(p, "just_spotted", "the '!' sting fires with the reaction")
		assert_signal_emit_count(p, "just_spotted", 1, "EXACTLY once -- sense()'s own edge block must not double-emit on top of investigate_point's")
		assert_false(p.hearing_pending(), "the latch is spent")
		p.free())

func test_a_persisting_noise_still_fires_after_one_buffer() -> void:
	# THE RESTART TRAP. Path A re-hears every think and Path B re-scans every 0.3 s, so any implementation that
	# re-sets the clock whenever a noise is present would never react at all while the player kept walking.
	_with_delay(0.3, 0.0, func() -> void:
		var p := _perc()
		for i in 3:
			p.hear_noise(Vector3(1.0 + i, 0.0, 0.0), 2.0)  # the noise is still going, and MOVING
			p.sense(0.1)
		assert_eq(p.state, Perception.State.INVESTIGATING,
			"a continuous noise reacts one buffer after it FIRST became audible -- it must not push its own reaction away forever")
		assert_eq(p.last_known_position, Vector3(3.0, 0.0, 0.0),
			"and it reacts to the FRESHEST spot: a re-arm refreshes what we react to, never the clock")
		p.free())

func test_a_noise_that_stops_mid_buffer_still_produces_a_reaction() -> void:
	# A gunshot, a thrown decoy, a landing thud: the source decays and self-frees long before the reaction is due.
	# Cancel-on-silence would invert the feature -- the short sharp noises are the whole point of the channel.
	_with_delay(0.3, 0.0, func() -> void:
		var p := _perc()
		var burst := Node3D.new()  # stands in for a one-shot NoiseSource's emitter
		p.hear_noise(Vector3(9.0, 0.0, 9.0), 4.0, burst)
		burst.free()  # the source is gone before the buffer drains
		p.sense(0.4)
		assert_eq(p.state, Perception.State.INVESTIGATING, "the reaction still happens -- the stimulus was latched BY VALUE at arm time")
		assert_eq(p.last_known_position, Vector3(9.0, 0.0, 9.0), "at the latched point, with no transform read on the freed emitter")
		assert_null(p.noticed, "a freed emitter re-sanitizes to null at FIRE time, so investigate_point's typed param never sees a dead handle")
		p.free())

func test_the_emitter_is_published_as_noticed_when_it_survives() -> void:
	_with_delay(0.3, 0.0, func() -> void:
		var p := _perc()
		var who := Node3D.new()
		p.hear_noise(Vector3(1.0, 0.0, 1.0), 2.0, who)
		p.sense(0.4)
		assert_eq(p.noticed, who, "a live emitter reaches the '!' handler, so it can tell 'I heard YOU' from 'I heard a can rattle'")
		who.free()
		p.free())


# --- Path A: armed from INSIDE sense() ------------------------------------------------------------------------
# The other tests all arm by calling hear_noise() directly, which is Path B's shape (NpcDistraction scans, then
# sense() drains on a later think). Path A arms from WITHIN sense() itself, off the target's own noise_radius --
# a different ordering, and the one where the think delta can be a whole banked AI-LOD interval.
# These go IN-TREE because can_hear() reads global_position, which is not a legal read on an off-tree Node3D.

class NoisyTarget extends Node3D:
	var noise_radius: float = 30.0


func _in_tree_pair() -> Array:
	var p := Perception.new()
	var t := NoisyTarget.new()
	add_child_autofree(p)
	add_child_autofree(t)
	t.global_position = Vector3(5.0, 0.0, 0.0)  # well inside noise_radius, so can_hear() is true
	p.target = t
	return [p, t]


func test_a_noise_heard_inside_sense_banks_instead_of_escalating() -> void:
	_with_delay(0.4, 0.0, func() -> void:
		var pair := _in_tree_pair()
		var p: Perception = pair[0]
		watch_signals(p)
		p.sense(0.1)
		assert_eq(p.state, Perception.State.UNAWARE, "Path A buffers too: hearing the target no longer escalates on the frame the sound lands")
		assert_true(p.hearing_pending(), "it banks a reaction instead")
		assert_signal_not_emitted(p, "just_spotted", "and stays silent until the reaction actually happens"))

func test_the_arming_think_does_not_spend_its_own_delta() -> void:
	# ⭐THE AI-LOD REGRESSION GUARD. Under AiLod a throttled NPC hands sense() the whole banked think interval, and
	# every second of it elapsed BEFORE the noise was heard. Draining the latch on the think that armed it would make
	# the buffer shrink with distance -- and vanish outright wherever the interval reaches the delay, restoring the
	# same-frame snap this feature exists to remove, silently and only at range.
	_with_delay(0.2, 0.0, func() -> void:
		var pair := _in_tree_pair()
		var p: Perception = pair[0]
		p.sense(0.25)  # a far-band banked delta, LONGER than the whole reaction time
		assert_eq(p.state, Perception.State.UNAWARE,
			"a throttled NPC must NOT react on the very think it first heard the noise, however large its banked delta")
		assert_almost_eq(p.hearing_pending_time(), 0.2, 0.001,
			"the countdown starts at the full authored reaction time -- it is not pre-charged with time that elapsed before the noise existed"))

func test_path_a_reacts_after_its_buffer() -> void:
	_with_delay(0.2, 0.0, func() -> void:
		var pair := _in_tree_pair()
		var p: Perception = pair[0]
		var t: Node3D = pair[1]
		p.sense(0.05)  # arms
		p.sense(0.25)  # drains past the delay
		assert_eq(p.state, Perception.State.INVESTIGATING, "and then it does react")
		assert_eq(p.noticed, t, "at the target it heard, so the '!' reads as 'I heard YOU'"))


# --- pre-emption: a hunch never outranks something better ------------------------------------------------------

func test_sight_drops_a_pending_reaction() -> void:
	_with_delay(0.5, 0.0, func() -> void:
		var p := _perc()
		p.hear_noise(Vector3(3.0, 0.0, 0.0), 2.0)
		# As if can_see() went true mid-buffer: the meter is filling, so the enemy is DETECTING. `detection` is
		# seeded above zero because a DETECTING enemy with an EMPTY meter is one whose sighting has already
		# drained away -- that is the "sight is over" case, not the "sight wins" one this test is about.
		p.state = Perception.State.DETECTING
		p.detection = 0.5
		watch_signals(p)
		p.sense(0.1)
		assert_eq(p.state, Perception.State.DETECTING, "the sighting is still live")
		assert_false(p.hearing_pending(), "seeing the target outranks a hunch about a noise -- the banked reaction is dropped, not queued")
		assert_signal_not_emitted(p, "just_spotted", "and no stale '!' fires for a reaction that never happened")
		p.sense(0.6)
		assert_eq(p.last_known_position, Vector3.ZERO, "the dropped hunch never steers the search at the noise, even later")
		p.free())

func test_a_higher_authority_stimulus_drops_a_pending_reaction() -> void:
	_with_delay(0.5, 0.0, func() -> void:
		var p := _perc()
		var noise := Vector3(3.0, 0.0, 0.0)
		var shot_from := Vector3(0.0, 0.0, 7.0)
		p.hear_noise(noise, 2.0)
		p.alert_to(shot_from)  # shot in the back mid-buffer
		assert_eq(p.state, Perception.State.ALERTED, "being shot wins outright, on the spot")
		p.sense(0.6)
		assert_false(p.hearing_pending(), "and the stale hunch is dropped rather than re-pointing the enemy a beat later")
		# The alert winds DOWN to INVESTIGATING here only because this bare Perception has no live target to keep
		# seeing (pursuit grace was never armed) -- that is the pre-existing ALERTED arm, not the buffer. What
		# matters is WHERE it is looking: the spot it was shot from, never the noise the dropped hunch was about.
		assert_eq(p.last_known_position, shot_from, "the alert's spot stands; the discarded reaction never steals it")
		p.free())

func test_an_already_reacting_enemy_re_points_instantly() -> void:
	# Once the enemy HAS reacted it is tracking, not reacting: a moving decoy must re-point the live search on the
	# very scan it moved, with no second buffer.
	_with_delay(0.5, 0.0, func() -> void:
		var p := _perc()
		p.investigate_point(Vector3(1.0, 0.0, 1.0))
		var moved := Vector3(8.0, 0.0, 2.0)
		p.hear_noise(moved, 3.0)
		assert_eq(p.last_known_position, moved, "the search re-points on the same statement")
		assert_false(p.hearing_pending(), "and nothing is banked -- the buffer is for a COLD stimulus only")
		p.free())


# --- lifecycle -------------------------------------------------------------------------------------------------

func test_forget_clears_a_pending_reaction() -> void:
	_with_delay(0.5, 0.0, func() -> void:
		var p := _perc()
		p.hear_noise(Vector3(2.0, 0.0, 2.0), 2.0)
		p.forget()
		assert_false(p.hearing_pending(), "forgetting means we are not acting on any hunch")
		assert_eq(p.hearing_pending_time(), -1.0, "the countdown is back to its idle sentinel")
		p.sense(1.0)
		assert_eq(p.state, Perception.State.UNAWARE, "and no phantom reaction fires afterwards")
		p.free())

func test_reset_for_reuse_clears_a_pending_reaction() -> void:
	# NpcPool PARKS a dead body off-tree instead of freeing it, so a countdown simply FREEZES at its death value;
	# NPC.reset_for_reuse then re-acquires a target on its very last line. A survivor would fire a phantom '!'
	# from last life's noise on the reused body's first think.
	_with_delay(0.5, 0.0, func() -> void:
		var p := _perc()
		p.hear_noise(Vector3(2.0, 0.0, 2.0), 2.0)
		p.reset_for_reuse()
		assert_false(p.hearing_pending(), "a pooled body must never inherit the previous life's pending reaction")
		p.free())
