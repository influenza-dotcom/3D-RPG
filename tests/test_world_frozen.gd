extends GutTest

## F-C34 — the cinematic damage-immunity predicate seam. InputManager.world_frozen() is the SINGLE source of
## truth for immunity: Player.take_damage, HazardZone._process, and StatusEffectManager._process all gate on it so a
## control-locked player (cutscene playing OR a conversation engaged) takes no hazard/DoT/NPC-fire damage and no effect
## duration burns. Here we pin the seam + the at-rest default only. The actual damage-immunity BEHAVIOUR is playtest-
## gated: we cannot flip CutscenePlayer._active (private static, no setter) or drive Player.take_damage off-tree (the
## no-Player-_ready() rule), so "stand in a HazardZone / under fire, trigger a cutscene, confirm HP stops dropping"
## stays a manual check. This reads the live InputManager autoload directly — no add_child, no fixture.


func test_world_frozen_method_exists() -> void:
	assert_true(InputManager.has_method(&"world_frozen"),
		"InputManager must expose world_frozen() — the shared cinematic-immunity predicate the damage sources gate on")


func test_world_frozen_returns_bool() -> void:
	var v = InputManager.world_frozen()
	assert_eq(typeof(v), TYPE_BOOL,
		"world_frozen() must return a bool (an OR of CutscenePlayer.is_active() and DialogueManager.is_engaged())")


func test_world_frozen_false_at_rest() -> void:
	# A fresh GUT session has no cutscene playing and no conversation engaged, so the player is NOT control-locked
	# and takes normal damage. If this trips, some earlier test left a cutscene/dialogue active without tearing it down.
	assert_false(InputManager.world_frozen(),
		"world_frozen() must be false at rest — no cutscene or dialogue is active")
