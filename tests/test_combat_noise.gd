extends GutTest

## NPC combat noise on the shared &"noise" channel (GA-2): an NPC's gunfire + death drop a one-shot NoiseSource
## so a listening guard (GameSettings.npc_ai.hearing_initiates) can hear the firefight and investigate — combat
## is no longer silent to off-screen allies. The SPAWN + throttle now live in the generic NoisePulser drop-in
## (scripts/components/noise_pulser.gd) — see tests/test_noise_pulser.gd for that mechanism. Here we only pin the
## NPC's own designer knobs (the noise-radius / interval exports) and that the NpcCombat -> host gunfire-noise
## facade survives the extraction. The in-tree wiring (_build_components builds the pulser; _act_alerted / _on_died
## call it through the facades; the hearing_initiates gate) is playtested.

const NPC_PATH := "res://scripts/npc/npc.gd"


func test_combat_noise_export_defaults_are_sane() -> void:
	var n = load(NPC_PATH).new()
	assert_gt(n.gunfire_noise_radius, 0.0, "gunfire is audible by default (the channel is still inert until a listener opts in)")
	assert_gt(n.death_noise_radius, 0.0, "a death is audible by default")
	assert_gt(n.combat_noise_interval, 0.0, "the gunfire throttle interval is positive (so full-auto pulses, not per-bullet)")
	assert_gt(n.combat_noise_lifetime, 0.0, "the burst lifetime is positive so the source self-frees (never leaks)")
	n.free()


func test_gunfire_noise_facade_exists_for_npccombat() -> void:
	# npc_combat.gd calls host._emit_gunfire_noise() after firing; the facade must survive the NoisePulser extraction
	# (off-tree it no-ops — no _noise_pulser until _ready — but the method surface NpcCombat dispatches into stays).
	var n = load(NPC_PATH).new()
	assert_true(n.has_method("_emit_gunfire_noise"), "NPC keeps the _emit_gunfire_noise facade NpcCombat dispatches into")
	n.free()
