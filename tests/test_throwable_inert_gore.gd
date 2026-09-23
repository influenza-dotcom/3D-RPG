extends GutTest

## Contract for "your own corpse doesn't fight on" — Throwable.gore_spares_characters, the provenance gate that
## stops the PLAYER'S death burst from damaging (and routinely killing) the enemy standing over the body.
##
## THE BUG. Every death runs the same gore burst, the player's included: meat chunks at gib_vel_min..max
## (7-14 m/s) plus its first-person body parts, which also inherit 0.6x the killing blow's velocity. The
## impact-damage floor is 6.0 m/s, so those chunks cleared it and each dealt roundf((speed - 6.0) * 0.4) to
## whatever Character they touched. Against a 6-14 max_hp enemy, eight-odd pieces was lethal — and the kill was
## illegible (no damage number, no cue, no aggro) yet still paid the bounty and the faction penalty, in a world
## the checkpoint revive puts back UNTOUCHED. The failed attempt quietly thinned the fight it failed.
##
## THE SHAPE. Two terms, no arithmetic: the prop is in Groups.PLAYER_GORE (GoreSpawner stamps it on everything
## the PLAYER'S death spawns, never an NPC's) AND nobody is credited for throwing it. The second term is what
## keeps the deliberate verb — picking a severed head up and hurling it goes through PickupRay._release ->
## mark_thrown_by, so _credited_attacker() is the player and the limb hits like any other thrown prop.
##
## WHY A PURE STATIC. Same reason as loyal_scale next door (tests/test_throwable_loyal.gd): the policy is pinned
## with literal args — no tree, no physics, no Character — while the live resolution
## (Throwable._is_inert_player_gore reading is_in_group + _credited_attacker + the GameSettings knob) is one
## unbranching line over it. The DEFAULT of that knob is pinned in tests/test_managers_tuning.gd.
##
## AND A LIVE HALF (bottom of the file), because a policy nobody reaches is worth nothing. Those drive the real
## Throwable._on_body_entered against a real in-tree Character and assert hp — the test_stuck_blade.gd idiom — which
## is what proves the guard is wired in, and wired in the right PLACE (the chunk still breaks, and burns no cooldown).
## No physics is stepped: `_pre_step_velocity` is written directly and the contact callback invoked, which is exactly
## what the solver does one frame later, minus the flakiness.

const Throwable := preload("res://scripts/components/Throwable.gd")

## The gib chassis' own resource — the real one both gore_gib.tscn and body_part_gib.tscn carry, so the live
## tests below inherit its true max_hp / mass / damages_player rather than a hand-built approximation.
const GIB_DATA_PATH := "res://resources/interactables/gore_gib_data.tres"

## The top of the meat-chunk launch range (EffectsSettings.gib_vel_min..max is 7..14). Body parts start slower
## but add 0.6x the killing blow, so this is the middle of the real spread, not its ceiling.
const GIB_SPEED := 14.0

## Character is @abstract, so the live half needs a concrete actor. It adds nothing — the base damage path is the
## subject, deliberately without NPC's weapon hub / nav / perception (whose _ready must never run in a unit test).
class VictimActor extends Character:
	pass


# --- the fix itself ------------------------------------------------------------------------------------------

func test_loose_player_gore_is_spared() -> void:
	# The reported bug, stated as the contract: tagged (it came off the player's corpse) + uncredited (nobody
	# threw it) = deals nothing. This is the ONLY combination that spares.
	assert_true(Throwable.gore_spares_characters(true, false, false),
		"a chunk of the player's own corpse that nobody threw must damage nobody — the enemy standing over your body used to be finished off by your gibs, uncredited and un-undoable by the checkpoint revive")


func test_thrown_player_gore_still_hits() -> void:
	# The verb the fix must not eat: "Pick Up Head" is a shipped, documented prompt (gore_spawner stamps
	# display_name = PlayerText.body_part(key)). A pick-up + release credits the player via mark_thrown_by, so
	# the limb is a weapon again for thrown_credit_grace.
	assert_false(Throwable.gore_spares_characters(true, true, false),
		"a gib the player picked up and THREW is a deliberate attack and must still hurt — the credited thrower is exactly what separates it from a chunk still coasting on the death burst")


func test_npc_gore_is_untouched() -> void:
	# Scope pin. Character.death_gore_group() answers &"" for every NPC, so nothing an NPC's death spawns is ever
	# in Groups.PLAYER_GORE and this gate can never fire on it. An NPC's gore keeps whatever it did before.
	assert_false(Throwable.gore_spares_characters(false, false, false),
		"an NPC's gore is never tagged Groups.PLAYER_GORE, so this rule must leave it exactly as it was — the fix is scoped to the PLAYER'S corpse, not to gibs in general")


func test_ordinary_untagged_prop_is_untouched() -> void:
	# The blast radius, from the other side: a crate resting in the world is untagged, so neither term can make
	# it inert however it got moving. Every non-gore throwable behaves exactly as before this rule existed.
	assert_false(Throwable.gore_spares_characters(false, true, false),
		"an ordinary thrown crate is untagged and credited — nothing here may change what a normal throwable does")


# --- the designer override ------------------------------------------------------------------------------------

func test_the_knob_restores_the_old_behaviour_wholesale() -> void:
	# GameSettings.effects.player_gore_damages_characters is tested FIRST inside the policy, so ON is a clean
	# revert to the pre-fix rule rather than a third, half-way behaviour. A designer who wants a corpse that
	# takes people with it flips one tick and gets exactly what shipped before.
	assert_false(Throwable.gore_spares_characters(true, false, true),
		"with player_gore_damages_characters ON, even loose player gore must damage again — the knob's whole job is to restore the old behaviour, not to soften it")
	assert_false(Throwable.gore_spares_characters(false, false, true),
		"the knob cannot make anything MORE inert than the default does — every other combination already damages")


# --- LIVE: the real damage path, driven against a real Character ----------------------------------------------

var _gib: Throwable
var _victim: Character

func before_each() -> void:
	_victim = VictimActor.new()
	add_child_autofree(_victim)
	_victim.max_hp = 14.0   # a Raider (resources/characters/raider.tres) — mid of the shipped 6-14 enemy range
	_victim.hp = 14.0
	_victim.global_position = Vector3(0.0, 0.0, 2.0)
	_gib = Throwable.new()
	_gib.data = load(GIB_DATA_PATH)
	add_child_autofree(_gib)
	_gib.global_position = Vector3.ZERO
	# What the solver would have latched at the end of last frame (Throwable._physics_process): _on_body_entered
	# reads its LENGTH as `my_speed`, and that is the only speed the damage formula ever sees.
	_gib._pre_step_velocity = Vector3(0.0, 0.0, GIB_SPEED)


func test_live_an_untagged_gib_still_damages() -> void:
	# THE BASELINE, and the proof the bug was real: this is what every gib did, and still does for NPC gore.
	# roundf((14.0 - 6.0) * 0.4) = 3 per strike, against enemies that run 6-14 max_hp.
	var before := _victim.hp
	_gib._on_body_entered(_victim)
	assert_lt(_victim.hp, before,
		"an untagged gib at the top of the launch range must still damage — this is the behaviour the fix is scoped AWAY from, and an NPC's gore keeps it")


func test_live_player_gore_deals_nothing() -> void:
	# The headline, on the real path rather than the policy static.
	_gib.add_to_group(Groups.PLAYER_GORE)
	var before := _victim.hp
	_gib._on_body_entered(_victim)
	assert_almost_eq(_victim.hp, before, 0.0001,
		"a chunk of the player's own corpse must take nothing off the enemy it hits")


func test_live_a_whole_burst_cannot_kill() -> void:
	# The reported symptom itself. A death flings ~3 meat chunks plus the player's first-person body parts, each
	# arriving with its OWN fresh damage cooldown — so the victim eats a strike per piece, not one per 0.5 s.
	# Ten of them against the weakest shipped enemy (Sniper, 6 max_hp) is well past lethal at 3 damage each.
	_victim.max_hp = 6.0
	_victim.hp = 6.0
	_gib.add_to_group(Groups.PLAYER_GORE)
	for _i in 10:
		_gib._damage_cooldown = 0.0  # stand in for ten separate chunks, each with its own untouched cooldown
		_gib._on_body_entered(_victim)
	assert_almost_eq(_victim.hp, 6.0, 0.0001,
		"a point-blank burst from the player's corpse must leave the weakest enemy on full health")
	assert_true(_victim.is_alive(),
		"...and alive: the whole point is that dying no longer kills the enemy standing over you, in a world the checkpoint revive puts back untouched")


func test_live_a_limb_the_player_threw_still_hits() -> void:
	# The verb the fix must not eat, proven live: PickupRay._release calls mark_thrown_by, which is what makes
	# _credited_attacker() non-null and hands the limb back its bite.
	_gib.add_to_group(Groups.PLAYER_GORE)
	var thrower := VictimActor.new()
	add_child_autofree(thrower)
	thrower.add_to_group(Groups.PLAYER)
	_gib.mark_thrown_by(thrower)
	var before := _victim.hp
	_gib._on_body_entered(_victim)
	assert_lt(_victim.hp, before,
		"a severed limb the player picked up and hurled is a deliberate attack and must still wound — 'Pick Up Head' is a shipped prompt, not an accident")


func test_live_the_knob_puts_the_old_behaviour_back() -> void:
	# GameSettings.effects is the live shared resource, so the prior value is restored BEFORE the assert — a
	# failure here must not leak an inverted global into every test that runs after it.
	var prior: bool = GameSettings.effects.player_gore_damages_characters
	GameSettings.effects.player_gore_damages_characters = true
	_gib.add_to_group(Groups.PLAYER_GORE)
	var before := _victim.hp
	_gib._on_body_entered(_victim)
	var after := _victim.hp
	GameSettings.effects.player_gore_damages_characters = prior
	assert_lt(after, before,
		"ticking player_gore_damages_characters must restore the pre-fix behaviour on the real path, not just in the pure policy")


func test_live_player_gore_still_breaks_on_the_strike_it_spares() -> void:
	# The guard lives in _try_damage_character, not at the top of _on_body_entered, so the burst LOOKS identical: the
	# chunk still thuds and still takes its own impact damage, so a fragile chunk bursts. Only the victim is spared.
	_gib.hp = 1  # fragile on purpose: the claim is about the guard's placement, not the gib's authored hp
	_gib.add_to_group(Groups.PLAYER_GORE)
	var before := _victim.hp
	_gib._on_body_entered(_victim)
	assert_almost_eq(_victim.hp, before, 0.0001, "precondition: the player's gore spared the enemy")
	assert_true(_gib._destroyed,
		"the chunk must still burst on the strike it spares — the guard may silence the damage, not the whole contact")


func test_live_an_inert_strike_burns_no_damage_cooldown() -> void:
	# "No damage, no blood, no cooldown": a spared contact leaves the prop exactly as it found it. Proven by what a
	# burned cooldown would break: the player picks the same chunk up and throws it straight back, and it must bite.
	_gib.destructible = false  # the chunk must survive the first contact to be thrown back
	_gib.add_to_group(Groups.PLAYER_GORE)
	_gib._on_body_entered(_victim)
	assert_almost_eq(_victim.hp, 14.0, 0.0001, "precondition: the loose chunk dealt nothing")
	assert_false(_gib._destroyed, "precondition: the chunk survived its first contact, so it can really be thrown again")
	var thrower := VictimActor.new()
	add_child_autofree(thrower)
	thrower.add_to_group(Groups.PLAYER)
	_gib.mark_thrown_by(thrower)
	_gib._on_body_entered(_victim)
	assert_lt(_victim.hp, 14.0,
		"a throw landing right after an inert contact must still wound — the spared contact must not have burned the damage cooldown")
