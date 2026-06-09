extends GutTest

## CBPalette — the central gameplay-cue colour source (NPC name / outline tints, rep toasts). All pure
## statics, so tested OFF-TREE with no nodes. Focus:
##   - ally() — the companion BLUE added alongside friendly/hostile (blue-dominant, distinct).
##   - disposition_color() — the name-colour DECISION shared by the hover readout (player.gd) and the
##     dialogue speaker name (dialogue_manager.gd): ally wins, else friendly/hostile by disposition, else
##     the caller's neutral fallback.
## Colours are compared against ally()/friendly()/hostile() themselves, so the asserts hold regardless of
## the colorblind-safe toggle's current state (no Settings mutation, nothing to leak).


func test_ally_is_blue_and_distinct() -> void:
	var c := CBPalette.ally()
	assert_true(c.b > c.r and c.b > c.g,
		"ally() is blue-dominant (a companion reads BLUE) in both the normal and colorblind-safe sets")
	assert_ne(c, CBPalette.friendly(),
		"the ally blue is distinct from the friendly colour so allies and friendlies don't blur together")
	assert_ne(c, CBPalette.hostile(),
		"the ally blue is distinct from the hostile colour")


func test_disposition_color_ally_wins_over_disposition() -> void:
	# A companion is usually FRIENDLY by disposition, but the ally (blue) tint must take precedence.
	assert_eq(CBPalette.disposition_color(true, Disposition.Kind.FRIENDLY, Color.WHITE), CBPalette.ally(),
		"an ally (companion) reads ally-blue even though its disposition is FRIENDLY")
	assert_eq(CBPalette.disposition_color(true, Disposition.Kind.HOSTILE, Color.WHITE), CBPalette.ally(),
		"is_ally wins regardless of the underlying disposition")


func test_disposition_color_maps_friendly_and_hostile() -> void:
	assert_eq(CBPalette.disposition_color(false, Disposition.Kind.FRIENDLY, Color.WHITE), CBPalette.friendly(),
		"a non-ally FRIENDLY NPC reads the friendly colour (green / cyan)")
	assert_eq(CBPalette.disposition_color(false, Disposition.Kind.HOSTILE, Color.WHITE), CBPalette.hostile(),
		"a HOSTILE NPC reads the hostile colour (red / orange) — the 'enemies are red' rule")


func test_disposition_color_neutral_falls_back_to_caller_default() -> void:
	var neutral := Color(0.92, 0.92, 0.95)  # the hover readout's near-white default
	assert_eq(CBPalette.disposition_color(false, Disposition.Kind.NEUTRAL, neutral), neutral,
		"a NEUTRAL (non-ally) NPC keeps the caller's fallback — near-white on the hover readout, white in dialogue")
