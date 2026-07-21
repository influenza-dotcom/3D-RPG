extends GutTest

## Pins the talking-envelope seam on BodyModelSwap. talk_for pulses the head-bob + mouth for an utterance and never
## shortens an in-flight pulse; stop_talking ENDS it now so both settle to rest. DialogueManager calls stop_talking
## (via NPC.note_speaking_stop) the instant the speaker stops delivering a line — the response menu opened, or the
## conversation ended — so the head doesn't keep bobbing while the player reads choices / as the NPC returns to idle.
## Off-tree (.new(), no add_child -> no _ready / no _rebuild), so it touches no meshes / autoloads and is headless-safe.

func test_talk_for_pulses_envelope() -> void:
	var swap := BodyModelSwap.new()
	swap.talk_for(2.0)
	assert_almost_eq(swap._talk_t, 2.0, 0.0001, "talk_for sets the talking envelope to the utterance length")
	swap.talk_for(1.0)  # a shorter overlapping pulse must NOT cut the in-flight one short (maxf)
	assert_almost_eq(swap._talk_t, 2.0, 0.0001, "an overlapping shorter pulse keeps the longer in-flight envelope")
	swap.free()

func test_stop_talking_ends_envelope() -> void:
	var swap := BodyModelSwap.new()
	swap.talk_for(5.0)
	swap.stop_talking()
	assert_eq(swap._talk_t, 0.0, "stop_talking ends the envelope so the head-bob + mouth settle back to rest")
	swap.free()
