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
	# The 4th argument was a hardcoded `false` only while a thrown prop COULDN'T crit. It can now: the
	# thrown_weapon branch computes was_crit from is_headshot + ShotResolver.crit_allowed, and this call
	# forwards the SAME flag take_damage was given — matching projectile.gd and damage_trace.gd. Pinning
	# `false` again would make one strike a crit for damage and a non-crit for its number, silently costing a
	# thrown-knife headshot its crit colour.
	assert_true(src.contains("DamageNumberPopupScript.show(character, real_loss, global_position, was_crit, attacker)"),
		"thrown prop impacts (zorkmids, dogs, crates) should show the same post-mitigation damage numbers, and forward the SAME crit flag take_damage was given so a thrown-weapon headshot paints the crit colour")


func test_effects_settings_damage_number_fields_mirror_const_anchors() -> void:
	# PARITY (the NpcBarkSettings idiom): the "Damage Numbers" group on GameSettings.effects is the
	# designer surface show() actually reads; the popup's const bank stays the shipped baseline + these
	# anchors. Every field must DEFAULT to its const so the resource extraction is byte-identical until
	# a designer tunes EffectsSettings.tres. (MIN_LOSS and RENDER_PRIORITY deliberately have NO mirror:
	# gameplay policy and a draw-order contract stay const-only on the popup.)
	var fx := EffectsSettings.new()
	assert_eq(fx.damage_number_hit_offset_y, DamageNumberPopupScript.HIT_OFFSET_Y,
		"damage_number_hit_offset_y mirrors HIT_OFFSET_Y — the lift above the impact point")
	assert_eq(fx.damage_number_body_offset_y, DamageNumberPopupScript.BODY_OFFSET_Y,
		"damage_number_body_offset_y mirrors BODY_OFFSET_Y — the no-impact-point fallback height")
	assert_eq(fx.damage_number_rise, DamageNumberPopupScript.RISE,
		"damage_number_rise mirrors RISE — how far the number floats up over its life")
	assert_eq(fx.damage_number_spread, DamageNumberPopupScript.SPREAD,
		"damage_number_spread mirrors SPREAD — the horizontal anti-overprint drift")
	assert_eq(fx.damage_number_lifetime, DamageNumberPopupScript.LIFETIME,
		"damage_number_lifetime mirrors LIFETIME — the rise + fade duration")
	assert_eq(fx.damage_number_font_size, DamageNumberPopupScript.FONT_SIZE,
		"damage_number_font_size mirrors FONT_SIZE")
	assert_eq(fx.damage_number_pixel_size, DamageNumberPopupScript.PIXEL_SIZE,
		"damage_number_pixel_size mirrors PIXEL_SIZE — world metres per font pixel")
	assert_eq(fx.damage_number_outline_size, DamageNumberPopupScript.OUTLINE_SIZE,
		"damage_number_outline_size mirrors OUTLINE_SIZE — the readability rim")
	assert_eq(fx.damage_number_start_scale, DamageNumberPopupScript.START_SCALE,
		"damage_number_start_scale mirrors START_SCALE — the crit pop-in size")
	assert_eq(fx.damage_number_end_scale, DamageNumberPopupScript.END_SCALE,
		"damage_number_end_scale mirrors END_SCALE — the shrink as it fades")
	assert_eq(fx.damage_number_body_color, DamageNumberPopupScript.BODY_COLOR,
		"damage_number_body_color mirrors BODY_COLOR — the ordinary-hit tint")
	assert_eq(fx.damage_number_crit_color, DamageNumberPopupScript.CRIT_COLOR,
		"damage_number_crit_color mirrors CRIT_COLOR — the crit payoff tint")
	assert_eq(fx.damage_number_outline_color, DamageNumberPopupScript.OUTLINE_COLOR,
		"damage_number_outline_color mirrors OUTLINE_COLOR — the dark rim")
	fx = null
