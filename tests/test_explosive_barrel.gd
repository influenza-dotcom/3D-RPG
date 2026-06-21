extends GutTest

## SE-1 ExplosiveBarrel: a CanDestroy that detonates on destruction, spawning a damaging blast (the chaining
## hazard). The blast's reach + the attacker-credit forwarding are pinned here; the actual CHAIN (one barrel's
## Area3D blast destroying the next) is in-tree physics, playtested.

const BARREL_PATH := "res://scripts/components/explosive_barrel.gd"


func test_blast_defaults_are_sane() -> void:
	var b = load(BARREL_PATH).new()
	assert_gt(b.blast_force, 0.0, "a barrel has a real blast by default")
	assert_gt(b.blast_radius, 0.0, "...with a positive radius")
	b.free()


func test_take_damage_records_the_attacker() -> void:
	var b := ExplosiveBarrel.new()
	b.hp = 5  # off-tree _ready didn't run, so seed hp by hand to avoid an instant destroy
	var shooter := Node.new()
	b.take_damage(1.0, false, shooter)
	assert_eq(b._last_attacker, shooter, "the shooter is remembered for blast attribution")
	assert_eq(b.hp, 4, "a non-lethal hit just chips hp")
	b.free()
	shooter.free()


func test_detonate_offtree_is_a_noop() -> void:
	var b := ExplosiveBarrel.new()  # not in the tree
	assert_null(b._detonate(), "off-tree (a unit test) detonation spawns nothing and doesn't crash")
	b.free()


func test_detonation_forwards_blast_config_and_instigator() -> void:
	var b := ExplosiveBarrel.new()
	add_child_autofree(b)
	b.global_position = Vector3(5.0, 0.0, -2.0)
	b.blast_force = 12.0
	b.blast_radius = 3.0
	var shooter := Node.new()
	add_child_autofree(shooter)
	b._last_attacker = shooter
	var ex := b._detonate()
	assert_not_null(ex, "in-tree detonation spawns an Explosion")
	if ex != null:
		assert_almost_eq(ex.max_explosion_force, 12.0, 0.01, "blast_force -> the explosion's force")
		assert_almost_eq(ex.explosion_radius, 3.0, 0.01, "blast_radius -> the explosion's radius")
		assert_eq(ex.instigator, shooter, "the attacker rides as the blast instigator (player kill-credit through a chain)")
		ex.queue_free()
