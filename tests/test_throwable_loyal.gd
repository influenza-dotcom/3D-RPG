extends GutTest

## Tests for Throwable.loyal_scale — the "befriended (loyal) thrown-combat" damage policy: a befriended prop spares
## the player's FRIENDLY/NEUTRAL NPCs (0× damage) and hits HOSTILE NPCs harder (the multiplier), while every NORMAL
## (non-befriended) prop is unchanged (1×). Pure static + literal args (mirrors Pettable.eligible) — no tree, no
## Character; the per-hit NPC-ness/hostility resolution (_loyal_damage_scale) and the in-place damage application are
## manual-playtest / covered by the live path.

const Throwable := preload("res://scripts/components/Throwable.gd")


func test_normal_prop_unchanged() -> void:
	# loyal=false -> always 1.0, so a regular thrown crate damages every character exactly as before (no regression).
	assert_eq(Throwable.loyal_scale(false, true, true, 2.0, true), 1.0,
		"a non-befriended prop never changes damage, even vs a hostile NPC")
	assert_eq(Throwable.loyal_scale(false, true, false, 2.0, true), 1.0,
		"a non-befriended prop deals normal damage to a friendly/neutral NPC too")


func test_loyal_spares_friendly_and_neutral() -> void:
	assert_eq(Throwable.loyal_scale(true, true, false, 2.0, true), 0.0,
		"a befriended prop deals NO damage to a non-hostile (friendly/neutral) NPC")


func test_loyal_extra_vs_hostile() -> void:
	assert_eq(Throwable.loyal_scale(true, true, true, 2.0, true), 2.0,
		"a befriended prop deals multiplier (extra) damage to a HOSTILE NPC")


func test_loyal_leaves_non_npc_alone() -> void:
	# A non-NPC character (the human player) has no resolved_disposition -> is_npc false -> unchanged; the
	# data.damages_player guard governs the player, not loyalty.
	assert_eq(Throwable.loyal_scale(true, false, false, 2.0, true), 1.0,
		"loyalty doesn't alter a non-NPC character (the player)")


func test_loyal_without_sparing_hits_everyone() -> void:
	assert_eq(Throwable.loyal_scale(true, true, false, 2.0, false), 1.0,
		"with sparing off, a loyal prop deals NORMAL damage to non-hostiles")
	assert_eq(Throwable.loyal_scale(true, true, true, 2.0, false), 2.0,
		"with sparing off, hostiles still take the multiplier")
