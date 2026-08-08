extends GutTest

## Contract for "a revived player does not leave its own remains behind" — the ownership tag that lets
## Player._respawn_at_checkpoint destroy the gore ITS death flung without touching a single NPC's.
##
## The seam is three pieces, and this file pins each one:
##   1. Character.death_gore_group() — the overridable tag. The base (and so every NPC) answers &"": tag NOTHING,
##      because an NPC's gore is world dressing that stays where it fell forever. The PLAYER answers
##      Groups.PLAYER_GORE.
##   2. GoreSpawner stamps that group onto every world node it spawns, and clear_tagged_gore() frees exactly the
##      nodes carrying it — the SURGICAL half. A blanket "free every gib" sweep would also erase the gore of
##      whoever the player killed on the way down, which is the bug this shape exists to avoid.
##   3. GameSettings.effects.clear_player_gore_on_respawn gates the call (designer-first: not a hardcoded const),
##      and its default is ON.
##
## HOW THE ACTORS ARE BUILT. Character is @abstract, so the in-tree work uses inner concrete stubs — the
## test_character.gd idiom. A stub's _ready is side-effect-safe off-world (it builds the code-built children,
## including the real GoreSpawner this file drives, and _setup_overlay_chain no-ops on a mesh-less actor). The
## real Player is built with .new() and NEVER add_child'ed: its _ready instantiates weapon.tscn, nav and audio and
## mutates shared statics (the no-_ready rule in CLAUDE.md), so only its pure method surface is asserted here.
## The swept "gore" is plain Node3Ds: clear_tagged_gore is a group query + queue_free and cares nothing for what
## a gib actually is, while a real gib would drag in Throwable._ready (physics, overlay chain, collider autofit).

const PLAYER_SCRIPT_PATH := "res://scripts/player/player.gd"

## Stands in for an NPC / the abstract base: tags nothing.
class _Stub extends Character:
	pass

## Stands in for the Player inside the tree — the ONE override that matters here, so the spawner can be driven
## for real without ever running Player._ready. test_player_tags_its_death_gore... pins that the real Player
## returns this same group, which is what ties the two halves together.
class _TaggedStub extends Character:
	func death_gore_group() -> StringName:
		return Groups.PLAYER_GORE


## A stub actor live in the test's tree, with the GoreSpawner its _ready built.
func _actor(tagged: bool) -> Character:
	var c: Character = _TaggedStub.new() if tagged else _Stub.new()
	add_child_autofree(c)
	return c


## Stand-in for one spawned piece of gore, parented under `host` so it dies with the test.
func _gore_node(host: Node, group: StringName) -> Node3D:
	var n := Node3D.new()
	host.add_child(n)
	if group != &"":
		n.add_to_group(group)
	return n


# --- 1. the tag itself -------------------------------------------------------------------------------------

func test_base_character_tags_nothing() -> void:
	var c := _Stub.new()
	assert_eq(c.death_gore_group(), &"",
		"the BASE actor (so every NPC) must tag no gore — its chunks and stains are world dressing that has to stay lying where it fell, and a tag would sweep them into the player's revive")
	c.free()


func test_player_tags_its_death_gore_with_the_player_gore_group() -> void:
	# Off-tree .new(), no add_child: Player._ready is not safe in a unit run (see the header).
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_eq(p.death_gore_group(), Groups.PLAYER_GORE,
		"the PLAYER is the one actor whose death is REVERSED (the in-place checkpoint revive), so it is the one actor that must tag its remains — Groups.PLAYER_GORE is exactly what _respawn_at_checkpoint sweeps")
	p.free()


func test_player_gore_group_is_distinct_from_the_generic_gib_group() -> void:
	assert_ne(Groups.PLAYER_GORE, Groups.GIB,
		"the ownership tag must NOT be the &\"gib\" group — that one holds every gib in the world (and drives the oldest-first world cap), so sweeping it would erase the gore of whoever the player killed on the way down")


# --- 2. the sweep ------------------------------------------------------------------------------------------

func test_sweep_frees_only_the_tagged_gore() -> void:
	var host := _actor(true)
	var mine := _gore_node(host, Groups.PLAYER_GORE)   # our own chunk
	var theirs := _gore_node(host, Groups.GIB)          # an NPC's chunk, killed on the way down
	var bystander := _gore_node(host, &"")              # anything else in the world

	assert_eq(host.clear_death_gore(), 1, "exactly the one tagged node is reported freed")
	assert_true(mine.is_queued_for_deletion(),
		"the player's own gore is destroyed on the revive — else you are brought back to life standing in your own guts")
	assert_false(theirs.is_queued_for_deletion(),
		"an NPC's gib must SURVIVE the player's revive: the Dark-Souls respawn leaves the world untouched, and the kills you made on the way down are part of that world")
	assert_false(bystander.is_queued_for_deletion(), "untagged world nodes are never touched")


func test_sweep_is_a_no_op_for_an_actor_that_tags_nothing() -> void:
	# The whole reason clear_death_gore() is safe to call blind: an untagged actor's sweep can't reach anyone's
	# gore, not even its own, because it never tagged any.
	var host := _actor(false)
	var players_gore := _gore_node(host, Groups.PLAYER_GORE)

	assert_eq(host.clear_death_gore(), 0,
		"an actor with an empty death_gore_group() sweeps nothing at all")
	assert_false(players_gore.is_queued_for_deletion(),
		"and it must not reach ANOTHER actor's tagged gore — the group is an ownership tag, not a global gore bin")


func test_sweep_does_not_double_count_gore_that_is_already_going_away() -> void:
	# A gib can expire on its own gib_lifetime in the same frame the revive lands, and a second death sweeps
	# again; neither may be reported as a fresh free.
	var host := _actor(true)
	var expiring := _gore_node(host, Groups.PLAYER_GORE)
	expiring.queue_free()

	assert_eq(host.clear_death_gore(), 0,
		"gore already queued for deletion (an expired gib, or a second sweep) is skipped, not re-freed")


func test_clear_death_gore_is_a_safe_no_op_off_tree() -> void:
	# Matches every other gore facade: a bare .new() actor never ran _ready, so there is no GoreSpawner child.
	var c := _Stub.new()
	assert_eq(c.clear_death_gore(), 0,
		"off-tree (no _ready, so no GoreSpawner) the facade must no-op like gore()/spawn_gibs() do, not crash")
	c.free()


# --- 3. the designer knob ----------------------------------------------------------------------------------

func test_respawn_gore_wipe_is_a_designer_knob_and_defaults_on() -> void:
	var fx = EffectsSettings.new()
	assert_true(fx.clear_player_gore_on_respawn,
		"clear_player_gore_on_respawn must default ON — the shipped feel is a clean revive; the knob exists so a designer can keep the remains without touching code")
	fx = null


func test_live_effects_resource_carries_the_knob() -> void:
	# The registry copy is what the game actually reads (Player._clear_own_death_gore gates on it), so a knob that
	# existed only on the class would be a dead switch.
	assert_true(&"clear_player_gore_on_respawn" in GameSettings.effects,
		"GameSettings.effects must expose clear_player_gore_on_respawn — Player._clear_own_death_gore reads it on every revive")
