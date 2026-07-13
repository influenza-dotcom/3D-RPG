extends GutTest

const DamageNumberPopupScript := preload("res://scripts/combat/damage_number_popup.gd")

## DamageNumberPopup policy stays pure-testable; the runtime show() path is a
## Label3D/Tween side effect exercised through the weapon hit paths.

class _ConcreteChar extends Character:
	pass


class _ConcretePlayer extends Player:
	pass


func _char() -> _ConcreteChar:
	var c := _ConcreteChar.new()
	add_child_autofree(c)
	return c


func test_text_for_rounds_real_loss_and_keeps_tiny_visible_hits_at_one() -> void:
	assert_eq(DamageNumberPopupScript.text_for(12.4), "12", "damage numbers round the actual HP loss")
	assert_eq(DamageNumberPopupScript.text_for(12.6), "13", "larger fractions round up")
	assert_eq(DamageNumberPopupScript.text_for(0.2), "1", "a displayed hit never shows 0 damage")


func test_should_show_requires_player_shooter_non_player_character_and_real_loss() -> void:
	var victim := _char()
	var player := _ConcretePlayer.new()
	var npc_shooter := _char()

	assert_true(DamageNumberPopupScript.should_show(victim, 5.0, player),
		"the human player's shots on non-player Characters get damage-number feedback")
	assert_false(DamageNumberPopupScript.should_show(victim, DamageNumberPopupScript.MIN_LOSS - 0.01, player),
		"sub-threshold chip hits stay quiet")
	assert_false(DamageNumberPopupScript.should_show(victim, 5.0, npc_shooter),
		"NPC, ally, or companion firefights don't spawn the player's damage numbers")

	victim.add_to_group(&"Player")
	assert_false(DamageNumberPopupScript.should_show(victim, 5.0, player),
		"shots against the player use the existing damage-indicator HUD instead")
	player.free()


func test_throwable_impacts_route_real_loss_into_damage_numbers() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/components/Throwable.gd")
	assert_true(src.contains("DamageNumberPopupScript.show(character, real_loss, global_position, false, attacker)"),
		"thrown prop impacts (zorkmids, dogs, crates) should show the same post-mitigation damage numbers")
