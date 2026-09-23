extends GutTest

## M9: blast DAMAGE is per-weapon (WeaponData.explosion_damage) forwarded onto the Explosion, with a -1 sentinel that
## falls back to the global GameSettings.physics_damage.explosion_damage. Force + radius were already per-weapon;
## damage was the last blast field stuck on the global knob, so a rocket and a grenade dealt identical blast damage.
##
## Judged by what a body in the blast actually TAKES. The forward chain is run for real: a ProjectileSpawner armed
## with a rocket weapon fires the real rock_projectile.tscn, the round's scene-wired `queued_for_deletion` reaches its
## explosion.gd bridge, the bridge spawns the real explosion_area.tscn, and Explosion._on_body_entered is handed a
## damage sink inside the radius. The global knob is set to a value no weapon authors, so "fell back to the global"
## and "carried the weapon's own number" can never be confused.
##
## HARNESS RULES (the tests/test_projectiles.gd idiom):
##   - Rounds get SAFE_LIFE_TIME so Projectile._ready's life-timer await never resumes during the run.
##   - Every Projectile / Explosion the code under test (or a test) puts in the tree, and every impact SFX the bridge
##     reparents to the root, is recorded through SceneTree.node_added and freed in after_each — then the off-tree
##     wielder stubs (a spawned round holds its wielder as shooter + collision exception).
##   - No Player / NPC _ready runs: the wielder is a bare OFF-TREE Character subclass.
##   - GameSettings.physics_damage.explosion_damage is restored in after_each.
##
## COVERED ELSEWHERE: the bridge's other blast tuning (force / radius / bias / bloom) and the bullet spark being
## harmless whatever the rock tuning: tests/test_effects.gd. A rocket impact on world geometry reaching the bridge:
## tests/test_rocket_world_impact.gd.

const ExplosionScript := preload("res://scripts/components/explosion_area.gd")
const ROCK_SCENE := "res://scenes/projectiles/rock_projectile.tscn"

## Far longer than any run: see HARNESS RULES.
const SAFE_LIFE_TIME: float = 600.0
## Far from the origin so nothing another suite leaves near it overlaps a blast.
const ARENA := Vector3(-70.0, 90.0, 70.0)
## The global blast damage the tests run under — deliberately not a number any weapon or the shipped tuning uses.
const GLOBAL_BLAST: int = 23
## A second global value, to show a fallback blast re-reads the knob rather than a copy of it.
const RETUNED_GLOBAL_BLAST: int = 41
## A weapon's own authored blast damage, distinct from both globals.
const ROCKET_BLAST: float = 55.0


## Off-tree wielder stand-in: Character has no abstract funcs, so a bare subclass instantiates. Never added to the tree.
class _ConcreteChar extends Character:
	pass


## The smallest body Explosion._on_body_entered damages: a Node3D with take_damage (not a Character, not a
## RigidBody3D, so no hitmarker and no push branch runs). Records every amount it is dealt.
class _DamageSink extends Node3D:
	var hits: Array[float] = []

	func take_damage(amount: float, _was_crit: bool = false, _attacker: Node = null) -> void:
		hits.append(amount)


var _spawned: Array[Node] = []
var _off_tree: Array[Object] = []
var _saved_global_blast: int = 0


func before_each() -> void:
	_spawned = []
	_off_tree = []
	_saved_global_blast = GameSettings.physics_damage.explosion_damage
	GameSettings.physics_damage.explosion_damage = GLOBAL_BLAST
	get_tree().node_added.connect(_on_node_added)


func after_each() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	for n in _spawned:
		if is_instance_valid(n):
			n.free()
	_spawned = []
	for o in _off_tree:
		if is_instance_valid(o):
			o.free()
	_off_tree = []
	GameSettings.physics_damage.explosion_damage = _saved_global_blast


func _on_node_added(node: Node) -> void:
	if node is Projectile or node is Explosion:
		_spawned.append(node)
	elif node is AudioStreamPlayer3D and node.get_parent() == get_tree().root:
		_spawned.append(node)


## What a body standing 1 m from `blast`'s centre takes from it (-1.0 = no damage at all, after failing the count).
func _damage_dealt_by(blast: Explosion) -> float:
	var sink := _DamageSink.new()
	add_child_autofree(sink)
	sink.global_position = blast.global_position + Vector3(1.0, 0.0, 0.0)
	blast._on_body_entered(sink)
	assert_eq(sink.hits.size(), 1, "a damaging blast must hit a damageable body 1 m inside its radius exactly once")
	return sink.hits[0] if sink.hits.size() == 1 else -1.0


func _explosions_since(mark: int) -> Array[Explosion]:
	var out: Array[Explosion] = []
	for i in range(mark, _spawned.size()):
		if is_instance_valid(_spawned[i]) and _spawned[i] is Explosion:
			out.append(_spawned[i] as Explosion)
	return out


## Wire a spawner the way WeaponSystem.setup does, equip `weapon`, fire one round, then run that round's death path
## (the scene-wired queued_for_deletion its bridge listens to). Returns the ONE blast it produced, or null (after
## failing the count).
func _rocket_blast_for(weapon: WeaponData) -> Explosion:
	var wielder := _ConcreteChar.new()
	_off_tree.append(wielder)
	var inv := Inventory.new()
	add_child_autofree(inv)
	var spawner := ProjectileSpawner.new()
	spawner.inventory = inv
	spawner.player = wielder
	add_child_autofree(spawner)
	inv.equip(weapon)
	var mark := _spawned.size()
	spawner.spawn_projectile(ARENA, Vector3.FORWARD, false)
	var rounds: Array[Projectile] = []
	for i in range(mark, _spawned.size()):
		if is_instance_valid(_spawned[i]) and _spawned[i] is Projectile:
			rounds.append(_spawned[i] as Projectile)
	assert_eq(rounds.size(), 1, "harness: the armed spawner must fire exactly one rocket")
	if rounds.size() != 1:
		return null
	var blast_mark := _spawned.size()
	rounds[0].queued_for_deletion.emit(rounds[0].global_position)
	var blasts := _explosions_since(blast_mark)
	assert_eq(blasts.size(), 1, "a fired rocket's death must spawn exactly one blast through its explosion bridge")
	return blasts[0] if blasts.size() == 1 else null


func _rocket_weapon() -> WeaponData:
	var w := WeaponData.new()
	w.projectile_scene = load(ROCK_SCENE) as PackedScene
	w.projectile_life_time = SAFE_LIFE_TIME
	w.bullet_gravity_scale = 0.0
	w.explosion_radius = 3.0
	return w


# ---------------------------------------------------------------------------

func test_resolve_damage_override_wins_and_negative_falls_back() -> void:
	assert_almost_eq(ExplosionScript.resolve_damage(7.0, 40.0), 7.0, 0.001, "a per-instance override (>= 0) wins over the global")
	assert_almost_eq(ExplosionScript.resolve_damage(0.0, 40.0), 0.0, 0.001, "an override of 0 is a real value (a shove-only blast), not 'unset'")
	assert_almost_eq(ExplosionScript.resolve_damage(-1.0, 40.0), 40.0, 0.001, "-1 falls back to the global explosion_damage")


func test_a_blast_nobody_configured_deals_the_global_damage_and_an_authored_one_deals_its_own() -> void:
	var blast := Explosion.instantiate_recovering()
	assert_true(blast != null, "harness: explosion_area.tscn must instantiate")
	if blast == null:
		return
	add_child(blast)  # recorded by the harness, freed in after_each
	blast.global_position = ARENA
	assert_almost_eq(_damage_dealt_by(blast), float(GLOBAL_BLAST), 0.001,
		"an Explosion no one gave a blast damage must deal the global GameSettings.physics_damage.explosion_damage")
	GameSettings.physics_damage.explosion_damage = RETUNED_GLOBAL_BLAST
	assert_almost_eq(_damage_dealt_by(blast), float(RETUNED_GLOBAL_BLAST), 0.001,
		"...and follow that knob when a designer retunes it, rather than a value captured earlier")
	blast.explosion_damage = 7.0
	assert_almost_eq(_damage_dealt_by(blast), 7.0, 0.001,
		"CONTROL: the same blast given its own damage deals that instead of the global")


func test_a_weapon_that_never_sets_explosion_damage_blasts_for_the_global_amount() -> void:
	# A weapon opts IN to custom blast damage; one that does not must behave exactly as every blast did before M9.
	var blast := _rocket_blast_for(_rocket_weapon())
	if blast == null:
		return
	assert_almost_eq(_damage_dealt_by(blast), float(GLOBAL_BLAST), 0.001,
		"a rocket weapon with no authored explosion_damage must blast for the global explosion damage")


func test_a_fired_rocket_blasts_for_its_own_weapons_explosion_damage() -> void:
	# The M9 forward end to end: WeaponData -> ProjectileSpawner -> the round's explosion.gd bridge -> the Explosion.
	var w := _rocket_weapon()
	w.explosion_damage = ROCKET_BLAST
	var blast := _rocket_blast_for(w)
	if blast == null:
		return
	assert_almost_eq(_damage_dealt_by(blast), ROCKET_BLAST, 0.001,
		"a rocket weapon authored with explosion_damage 55 must deal 55 to a body in its blast — dealing the global 23 means the value was lost somewhere between the weapon, the spawner, the bridge and the blast")


func test_an_explosive_barrel_blasts_for_the_global_damage() -> void:
	# ExplosiveBarrel is an ENVIRONMENTAL blast (no WeaponData): it tunes force / radius / bias but must never pin a
	# damage of its own, so a barrel always hurts exactly what the global knob says.
	var barrel := ExplosiveBarrel.new()
	add_child_autofree(barrel)
	barrel.global_position = ARENA
	var blast := barrel._detonate()
	assert_true(blast != null, "harness: an in-tree barrel must spawn its blast")
	if blast == null:
		return
	assert_almost_eq(_damage_dealt_by(blast), float(GLOBAL_BLAST), 0.001,
		"a barrel's blast must deal the global explosion damage")
	GameSettings.physics_damage.explosion_damage = RETUNED_GLOBAL_BLAST
	assert_almost_eq(_damage_dealt_by(blast), float(RETUNED_GLOBAL_BLAST), 0.001,
		"...and a retuned global must reach barrels too — a barrel that authors its own damage would ignore it")
