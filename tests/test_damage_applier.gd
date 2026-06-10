extends GutTest

## DamageApplier (Wave 3 #7) — the shared hit-application sequence both shot paths route through. Golden
## tests pin the crit rule (incl. the player's immunity to NPC headshots), the type gates, the pre-hit HP
## capture, and the take_damage dispatch (Character 4-arg vs strict 3-arg). Character is @abstract, so an
## inner concrete stub is used (the test_character.gd idiom).
##
## The stubs go IN-TREE (add_child_autofree): is_headshot/body_part_at call to_local, which on an OFF-TREE
## node raises an engine error — and GUT 9.6's error tracker fails any test that triggers one, even when the
## fallback values would pass. A mesh-less stub's _ready only seeds hp = max_hp (+ a no-op overlay setup),
## proven side-effect-safe by test_character.gd — so max_hp is set BEFORE add_child and hp overridden after.
## All damage stays NON-LETHAL (huge hp, tiny damage) so take_damage never reaches the gore()/die() branch.

class _ConcreteChar extends Character:
	pass


## A concrete Character stub, in-tree and autofreed, at `hp_now` (max 1000 so every hit is non-lethal).
func _char(hp_now: float = 1000.0) -> _ConcreteChar:
	var c := _ConcreteChar.new()
	c.max_hp = 1000.0
	add_child_autofree(c)  # _ready seeds hp = max_hp; in-tree so to_local (is_headshot / limb hits) is clean
	c.hp = hp_now
	return c


# --- crit_for: headshot zone x crit_allowed (is_headshot is to_local(pos).y >= head_local_y, so a stub at
# --- the origin reads y=+100 as a headshot and y=-100 as a body shot) ---

func test_crit_for_headshot_from_player_shooter_is_a_crit() -> void:
	var c := _char()
	assert_true(DamageApplier.crit_for(c, Vector3(0.0, 100.0, 0.0), false),
		"a headshot from a non-AI (player) shooter crits")
	assert_false(DamageApplier.crit_for(c, Vector3(0.0, -100.0, 0.0), false),
		"a body shot never crits, whoever fired it")


func test_crit_for_player_is_immune_to_npc_headshots() -> void:
	# The feel rule crit_allowed encodes: an AI wielder's headshot ON THE PLAYER lands as a body shot.
	var player := _char()
	player.add_to_group(&"Player")
	assert_false(DamageApplier.crit_for(player, Vector3(0.0, 100.0, 0.0), true),
		"an NPC's headshot on the player must NOT crit (no cheap one-shots)")
	var bystander := _char()
	assert_true(DamageApplier.crit_for(bystander, Vector3(0.0, 100.0, 0.0), true),
		"NPC-vs-NPC headshots still crit — the immunity is the player's alone")


func test_crit_for_non_character_never_crits() -> void:
	# Short-circuits at the `is Character` gate, so it never reaches to_local — safe off-tree.
	var crate := Node3D.new()
	assert_false(DamageApplier.crit_for(crate, Vector3(0.0, 100.0, 0.0), false),
		"only Characters have a head — props/crates never crit")
	crate.free()


# --- off_guard_for: the type gate + pass-through ---

func test_off_guard_for_gates_on_character() -> void:
	var crate := Node3D.new()
	assert_false(DamageApplier.off_guard_for(crate), "non-Characters can't be snuck up on")
	var c := _char()
	assert_eq(DamageApplier.off_guard_for(c), c.is_off_guard(),
		"for a Character it defers to the victim's own is_off_guard()")
	crate.free()


# --- hp_before: the overkill base for each collider family ---

func test_hp_before_reads_character_throwable_and_other() -> void:
	var c := _char(12.5)
	assert_almost_eq(DamageApplier.hp_before(c), 12.5, 0.0001, "a Character's hp reads directly")
	var t := Throwable.new()
	t.hp = 7
	assert_almost_eq(DamageApplier.hp_before(t), 7.0, 0.0001, "a Throwable's int hp reads as float")
	var other := Node3D.new()
	assert_almost_eq(DamageApplier.hp_before(other), 0.0, 0.0001, "anything else has no HP -> 0")
	t.free()
	other.free()


# --- apply: the dispatch (Character 4-arg with hit_pos; strict 3-arg for everything else) ---

func test_apply_deals_damage_to_a_character_with_and_without_a_hit_position() -> void:
	var c := _char()
	DamageApplier.apply(c, 7.0, false, null, Vector3(0.0, 1.0, 0.0))
	assert_almost_eq(c.hp, 993.0, 0.0001, "with a hit position, the 4-arg Character path deals the damage")
	DamageApplier.apply(c, 5.0, false, null)  # the projectile path: no surface point (hit_pos = Vector3.INF)
	assert_almost_eq(c.hp, 988.0, 0.0001, "without one, the Vector3.INF sentinel still deals the damage")


func test_apply_uses_the_strict_3_arg_form_for_a_throwable() -> void:
	# Throwable.take_damage accepts no 4th argument — a uniform 4-arg dynamic call would be a runtime
	# error, which is exactly what the dispatch exists to prevent. Non-lethal so it never queue_frees;
	# bare .new() is safe (its non-lethal path touches only hp + a null-guarded flash).
	var t := Throwable.new()
	t.hp = 100
	DamageApplier.apply(t, 3.0, false, null, Vector3(0.0, 1.0, 0.0))
	assert_eq(t.hp, 97, "a Throwable is damaged through the 3-arg form (the hit position is dropped)")
	t.free()
