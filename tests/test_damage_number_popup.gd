extends GutTest

const DamageNumberPopupScript := preload("res://scripts/combat/damage_number_popup.gd")

## DamageNumberPopup's two policy statics (should_show / text_for) are pinned bare, off-tree. The runtime show()
## path is DRIVEN through a real thrown-prop strike: Throwable._on_body_entered against an in-tree Character (the
## tests/test_throwable_inert_gore.gd idiom — no physics step, `_pre_step_velocity` written directly), and what the
## player reads is asserted on the Label3D that strike actually spawns. The warm-variant match between gameplay's
## label and the EffectPrewarmer's lives in tests/test_effect_prewarm.gd.

class _ConcreteChar extends Character:
	pass


class _ConcretePlayer extends Player:
	pass


## Travel speed handed to every strike: well above GameSettings.physics_damage.interactable_damage_min_velocity (6 m/s
## shipped), the top-of-gib-range speed tests/test_throwable_inert_gore.gd strikes with.
const STRIKE_SPEED := 14.0
## Where a prop lands relative to its victim's origin. Off the origin in x AND z on purpose, so a number spawned over
## the VICTIM instead of over the strike is visible; |x| stays inside Character.arm_local_x so a weapon strike at
## this offset still reads as torso.
const STRIKE_OFFSET := Vector3(0.1, 0.0, 0.3)
const VICTIM_HP := 50.0

## The human player credited with every throw below. Off-tree: only `is Player` and its group are read, its _ready
## never runs (and on_damaged_target bails on its null HUD).
var _thrower: Player = null
## Damage numbers the driven strikes spawned — parented under the running scene, not the victim, so they are freed here.
var _spawned: Array[Label3D] = []


func before_each() -> void:
	_thrower = _ConcretePlayer.new()
	_thrower.add_to_group(Groups.PLAYER)
	_spawned = []


func after_each() -> void:
	for label in _spawned:
		if is_instance_valid(label):
			label.free()
	_spawned = []
	if is_instance_valid(_thrower):
		_thrower.free()
	_thrower = null


func _char() -> _ConcreteChar:
	var c := _ConcreteChar.new()
	add_child_autofree(c)
	return c


## An in-tree enemy with room to survive every strike, optionally wearing flat armour (Character.armor_flat).
func _victim_at(pos: Vector3, armor: float) -> _ConcreteChar:
	var c := _char()
	c.global_position = pos
	c.max_hp = VICTIM_HP
	c.hp = VICTIM_HP
	c.armor_flat = armor
	return c


## A prop the player just threw, parked at `at` with last frame's travel latched — exactly what the solver hands
## _on_body_entered one frame later. `weapon` null = a bludgeon prop (velocity damage, no contact point); non-null =
## a thrown weapon (weapon damage, located strike, can crit). Indestructible so the prop's own impact self-damage can
## never break it: a break spawns debris and decals this file has nothing to say about.
func _thrown_prop(at: Vector3, weapon: WeaponData) -> Throwable:
	var t := Throwable.new()
	t.destructible = false
	t.thrown_weapon = weapon
	add_child_autofree(t)
	t.global_position = at
	t._pre_step_velocity = Vector3(0.0, 0.0, STRIKE_SPEED)
	t.mark_thrown_by(_thrower)
	return t


## Run the real contact callback and return ONLY the damage numbers this one strike spawned.
func _strike(prop: Throwable, victim: Character) -> Array[Label3D]:
	var before := get_tree().root.find_children("*", "Label3D", true, false)
	prop._on_body_entered(victim)
	var spawned: Array[Label3D] = []
	for n in get_tree().root.find_children("*", "Label3D", true, false):
		if not before.has(n):
			spawned.append(n as Label3D)
			_spawned.append(n as Label3D)
	return spawned


# --- the pure policy ------------------------------------------------------------------------------------------------

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


func test_a_loss_of_exactly_min_loss_is_numbered_and_a_hair_less_is_not() -> void:
	# MIN_LOSS is documented as the post-mitigation loss BELOW which no number shows at all: the threshold itself is a
	# real hit the player gets feedback for, and only a strictly smaller chip stays quiet.
	var victim := _char()
	var player := _ConcretePlayer.new()
	assert_true(DamageNumberPopupScript.should_show(victim, DamageNumberPopupScript.MIN_LOSS, player),
		"a hit that takes exactly MIN_LOSS off the enemy must show its number — the rule silences losses BELOW the threshold, not the threshold itself")
	assert_false(DamageNumberPopupScript.should_show(victim, DamageNumberPopupScript.MIN_LOSS - 0.0001, player),
		"a loss a hair under MIN_LOSS must stay quiet — the threshold is the smallest hit that earns a number")
	player.free()


# --- show(), driven through a real thrown-prop strike ---------------------------------------------------------------

func test_a_thrown_prop_numbers_the_hp_its_victim_actually_lost_after_armour() -> void:
	# The SAME throw (same prop, same speed, same thrower) into a bare enemy and an armoured one: the raw impact damage is
	# identical, so the two numbers can only differ if each reads its OWN victim's post-mitigation HP loss. A popup fed
	# the pre-armour damage would paint the armoured enemy the bare one's number.
	var bare := _victim_at(Vector3.ZERO, 0.0)
	var armoured := _victim_at(Vector3(6.0, 0.0, 0.0), 1.0)

	var bare_numbers := _strike(_thrown_prop(bare.global_position + STRIKE_OFFSET, null), bare)
	var bare_loss := VICTIM_HP - bare.hp
	var armoured_numbers := _strike(_thrown_prop(armoured.global_position + STRIKE_OFFSET, null), armoured)
	var armoured_loss := VICTIM_HP - armoured.hp

	assert_gt(armoured_loss, 0.0,
		"precondition: one point of armour must leave some of a %s m/s throw behind, or there is no number to read" % STRIKE_SPEED)
	assert_lt(armoured_loss, bare_loss,
		"precondition: the armour must soak part of the strike, or the two victims can't tell raw damage from real loss")
	assert_eq(bare_numbers.size(), 1, "one thrown strike on an enemy must spawn exactly one damage number, got %d" % bare_numbers.size())
	assert_eq(armoured_numbers.size(), 1, "one thrown strike on an armoured enemy must spawn exactly one damage number, got %d" % armoured_numbers.size())
	if bare_numbers.size() != 1 or armoured_numbers.size() != 1:
		return
	# Prop damage is roundf'd and the armour is a whole point, so both losses are whole HP.
	assert_eq(bare_numbers[0].text, "%d" % roundi(bare_loss),
		"the thrown prop's number must read the %s HP the enemy lost" % bare_loss)
	assert_eq(armoured_numbers[0].text, "%d" % roundi(armoured_loss),
		"the armoured enemy's number must read the %s HP it actually lost, not the damage the prop dealt before armour" % armoured_loss)
	assert_ne(armoured_numbers[0].text, bare_numbers[0].text,
		"the armoured and unarmoured enemies lost different HP to the same throw, so the player must read different numbers")


func test_a_thrown_prop_the_armour_fully_soaks_shows_no_number() -> void:
	var soaked := _victim_at(Vector3.ZERO, 1000.0)
	var control := _victim_at(Vector3(6.0, 0.0, 0.0), 0.0)
	var soaked_numbers := _strike(_thrown_prop(soaked.global_position + STRIKE_OFFSET, null), soaked)
	var control_numbers := _strike(_thrown_prop(control.global_position + STRIKE_OFFSET, null), control)

	assert_lt(control.hp, VICTIM_HP, "control: the throw must hurt an unarmoured enemy")
	assert_eq(control_numbers.size(), 1,
		"control: the same throw into an unarmoured enemy must show a number, or the silence below proves nothing")
	assert_almost_eq(soaked.hp, VICTIM_HP, 0.0001, "precondition: 1000 armour must soak the whole strike")
	assert_eq(soaked_numbers.size(), 0,
		"a throw the enemy's armour soaked entirely took no HP, so it must show no number — painting the raw impact tells the player they hurt something they didn't")


func test_a_thrown_prop_number_rises_from_where_the_prop_struck() -> void:
	var victim := _victim_at(Vector3(3.0, 0.0, -2.0), 0.0)
	var prop := _thrown_prop(victim.global_position + STRIKE_OFFSET, null)
	var numbers := _strike(prop, victim)
	assert_eq(numbers.size(), 1, "one thrown strike must spawn exactly one damage number, got %d" % numbers.size())
	if numbers.size() != 1:
		return
	var at := numbers[0].global_position
	var struck := prop.global_position
	assert_almost_eq(at.x, struck.x, 0.001,
		"the number must spawn over the spot the prop hit (x %s), not over the victim's origin (x %s)" % [struck.x, victim.global_position.x])
	assert_almost_eq(at.z, struck.z, 0.001,
		"the number must spawn over the spot the prop hit (z %s), not over the victim's origin (z %s)" % [struck.z, victim.global_position.z])
	assert_true(at.y >= struck.y, "the number must start at or above the strike point, not inside the floor (y %s vs %s)" % [at.y, struck.y])


func test_a_thrown_weapon_headshot_paints_the_crit_colour_and_a_body_hit_does_not() -> void:
	var fx: EffectsSettings = GameSettings.effects
	assert_ne(fx.damage_number_crit_color, fx.damage_number_body_color,
		"precondition: the live crit and body tints must differ, or a crit's number can't be told apart")
	var weapon := WeaponData.new()
	weapon.damage = 4.0
	var head_victim := _victim_at(Vector3.ZERO, 0.0)
	var body_victim := _victim_at(Vector3(6.0, 0.0, 0.0), 0.0)
	# Character.head_local_y splits head from torso: one strike well above it, one well below (still above the legs).
	var head_numbers := _strike(_thrown_prop(head_victim.global_position + Vector3(0.0, head_victim.head_local_y + 0.4, 0.0), weapon), head_victim)
	var body_numbers := _strike(_thrown_prop(body_victim.global_position + Vector3(0.0, body_victim.head_local_y - 0.4, 0.0), weapon), body_victim)

	assert_gt(VICTIM_HP - head_victim.hp, VICTIM_HP - body_victim.hp,
		"precondition: the head strike must have been dealt as a crit (headshot multiplier), or its colour proves nothing")
	assert_eq(head_numbers.size(), 1, "a thrown-weapon headshot must spawn exactly one damage number, got %d" % head_numbers.size())
	assert_eq(body_numbers.size(), 1, "a thrown-weapon body hit must spawn exactly one damage number, got %d" % body_numbers.size())
	if head_numbers.size() == 1:
		assert_eq(head_numbers[0].modulate, fx.damage_number_crit_color,
			"a thrown-weapon headshot was dealt as a crit, so its number must wear the crit colour — the same flag take_damage was given")
	if body_numbers.size() == 1:
		assert_eq(body_numbers[0].modulate, fx.damage_number_body_color,
			"a thrown-weapon body hit is no crit, so its number must wear the ordinary body tint")
	weapon = null


# --- the label's look ------------------------------------------------------------------------------------------------

func test_build_label_takes_its_look_from_the_designer_resource_and_crit_picks_the_payoff() -> void:
	# Every knob tuned to a value no other knob shares, so a label reading the wrong field shows up as a mismatch.
	var fx := EffectsSettings.new()
	fx.damage_number_font_size = 31
	fx.damage_number_outline_size = 7
	fx.damage_number_pixel_size = 0.013
	fx.damage_number_start_scale = 1.6
	fx.damage_number_body_color = Color(0.1, 0.8, 0.3, 1.0)
	fx.damage_number_crit_color = Color(0.9, 0.2, 0.7, 1.0)
	fx.damage_number_outline_color = Color(0.2, 0.2, 0.9, 0.5)
	var plain := DamageNumberPopupScript.build_label("7", false, fx)
	var crit := DamageNumberPopupScript.build_label("7", true, fx)

	assert_eq(plain.text, "7", "the label must carry the formatted number it was given")
	assert_eq(plain.font_size, 31, "a designer's damage_number_font_size must size the number")
	assert_eq(plain.outline_size, 7, "a designer's damage_number_outline_size must size the readability rim")
	assert_almost_eq(plain.pixel_size, 0.013, 0.00001, "a designer's damage_number_pixel_size must set the world scale of a font pixel")
	assert_eq(plain.outline_modulate, fx.damage_number_outline_color, "a designer's damage_number_outline_color must tint the rim")
	assert_eq(plain.modulate, fx.damage_number_body_color, "an ordinary hit's number must wear the designer's body colour")
	assert_eq(crit.modulate, fx.damage_number_crit_color, "a crit's number must wear the designer's crit colour")
	assert_true(plain.scale.is_equal_approx(Vector3.ONE),
		"an ordinary hit's number must pop in at unit scale, got %s" % plain.scale)
	assert_true(crit.scale.is_equal_approx(Vector3.ONE * 1.6),
		"a crit's number must pop in at the designer's damage_number_start_scale (1.6), got %s" % crit.scale)
	plain.free()
	crit.free()
	fx = null
