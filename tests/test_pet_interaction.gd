extends GutTest

## Pure-logic tests for PetInteraction.held_blocks — the "you can't pet an object you're currently carrying" gate.
## Bare Nodes parented off-tree (add_child needs no SceneTree for plain Nodes, and Node._ready is a no-op), so no
## Player _ready runs (per CLAUDE.md). The aim raycast + the live host.held_prop() read are left to manual playtest.

const PetInteraction := preload("res://scripts/player/pet_interaction.gd")


func test_nothing_held_never_blocks() -> void:
	var pet := Node.new()
	assert_false(PetInteraction.held_blocks(pet, null),
		"empty-handed (held == null) never blocks petting")
	pet.free()


func test_held_object_itself_blocks() -> void:
	var obj := Node.new()
	assert_true(PetInteraction.held_blocks(obj, obj),
		"the held object itself can't be petted")
	obj.free()


func test_pettable_under_held_object_blocks() -> void:
	var obj := Node.new()   # the carried prop (e.g. a Throwable root)
	var pet := Node.new()   # its Pettable child
	obj.add_child(pet)
	assert_true(PetInteraction.held_blocks(pet, obj),
		"a Pettable whose ancestor is the held prop is blocked — you're holding that object")
	obj.free()              # frees the child too


func test_unrelated_pettable_not_blocked() -> void:
	var held := Node.new()
	var other := Node.new()
	var pet := Node.new()
	other.add_child(pet)
	assert_false(PetInteraction.held_blocks(pet, held),
		"a Pettable on a DIFFERENT object than the one you're holding stays pettable")
	held.free()
	other.free()            # frees pet
