extends GutTest

## Tests for Pettable. The eligibility predicate (Pettable.eligible) is pure logic — no tree, no nodes, literal
## booleans (mirrors test_silent_takedown). The pet_name() resolution chain needs an in-tree PARENT (it reads
## get_parent()), so those tests parent a Pettable under a tiny stub host via add_child_autofree — still no
## Player/NPC _ready (per CLAUDE.md). The in-tree raycast + heart spawn remain manual-playtest only.

const Pettable := preload("res://scripts/components/pettable.gd")


## A host that exposes the Throwable's verb-less resolver — pet_name() must prefer this over the node name.
class _ResolverHost extends Node:
	var noun := "Dog"
	func resolved_display_name() -> String:
		return noun


## A host that exposes only a plain display_name property (the NPC / Talkable shape).
class _DisplayNameHost extends Node:
	var display_name := "Kyle"


func test_disabled_never_eligible() -> void:
	assert_false(Pettable.eligible(false, false),
		"A disabled Pettable can never be petted, even off cooldown")


func test_enabled_off_cooldown_is_eligible() -> void:
	assert_true(Pettable.eligible(true, false),
		"Enabled + not on cooldown = pettable")


func test_cooldown_gate() -> void:
	assert_false(Pettable.eligible(true, true),
		"On cooldown (just petted) = not pettable yet")


func test_applause_and_cooldown_on_by_default() -> void:
	# The requested defaults: the clap cheer plays on a pet, and petting is gated by a real cooldown so the heart +
	# applause can't be machine-gunned. Off-tree field reads — Pettable.new() with no add_child runs no _ready.
	var p = Pettable.new()
	assert_true(p.applause_on_pet,
		"the crowd-clap cheer (AudioManager.play_applause) plays on a pet by default")
	assert_gt(p.cooldown, 0.0,
		"petting has a re-pet cooldown by default so the heart + applause can't be spammed")
	p.free()


## Build a Pettable with auto-fit off (we only exercise pet_name here — no need to build a runtime hitbox).
## Untyped (the file's load().new() idiom) so the Pettable-only members resolve via dynamic dispatch.
func _make_pettable():
	var pet = Pettable.new()
	pet.auto_fit_collider = false
	return pet


func test_pet_name_prefers_host_resolved_display_name() -> void:
	# A pettable Throwable: the node is named "Throwable" but its resolved_display_name() is "Dog" → "Pet Dog".
	var host := _ResolverHost.new()
	host.name = "Throwable"
	add_child_autofree(host)
	var pet = _make_pettable()
	host.add_child(pet)
	assert_eq(pet.pet_name(), "Dog",
		"pet_name uses the host's resolved_display_name (Throwable folds in data), NOT the node name 'Throwable'")


func test_pet_name_uses_host_display_name_property() -> void:
	# Any host exposing a plain display_name (NPC, Talkable) wins over the node name.
	var host := _DisplayNameHost.new()
	host.name = "NPC"
	add_child_autofree(host)
	var pet = _make_pettable()
	host.add_child(pet)
	assert_eq(pet.pet_name(), "Kyle",
		"pet_name falls back to a plain display_name export over the node name")


func test_pet_name_falls_back_to_node_name() -> void:
	# No host display name at all → the node name is the last resort (unchanged old behavior).
	var host := Node.new()
	host.name = "Statue"
	add_child_autofree(host)
	var pet = _make_pettable()
	host.add_child(pet)
	assert_eq(pet.pet_name(), "Statue",
		"with no host display name, pet_name uses the host node name as the last resort")


func test_pet_name_own_override_wins() -> void:
	# The Pettable's own display_name beats the host's name entirely.
	var host := _ResolverHost.new()
	host.name = "Throwable"
	add_child_autofree(host)
	var pet = _make_pettable()
	pet.display_name = "Good Boy"
	host.add_child(pet)
	assert_eq(pet.pet_name(), "Good Boy",
		"the Pettable's own display_name override beats the host's resolved name")
