extends GutTest

## Pure-logic tests for ClaimInteraction. A bare .new() with no host is inert (_can_run false) — a unit stub never
## touches the Player / dialog. _resolve_claimable walks the hit collider's family for a Claimable; bare Nodes parented
## off-tree exercise that walk with no Player _ready (per CLAUDE.md). The aim raycast + the name dialog are
## manual-playtest only. (held_blocks is shared with PetInteraction and covered by test_pet_interaction.)

const ClaimInteraction := preload("res://scripts/player/claim_interaction.gd")
const Claimable := preload("res://scripts/components/claimable.gd")


func test_inert_without_host() -> void:
	var ci = ClaimInteraction.new()
	assert_false(ci._can_run(),
		"a ClaimInteraction with no host (a bare unit stub) is inert — it never polls or claims")
	ci.free()


func test_resolve_finds_claimable_child_of_hit_body() -> void:
	# The aim ray usually hits the prop's SOLID body; the Claimable is authored as its child — resolve must find it.
	var body := Node.new()
	var claimable = Claimable.new()
	claimable.auto_fit_collider = false
	body.add_child(claimable)
	var ci = ClaimInteraction.new()
	assert_eq(ci._resolve_claimable(body), claimable,
		"resolve walks the hit body's children and finds the Claimable authored there")
	ci.free()
	body.free()  # frees the claimable child too


func test_resolve_returns_null_for_unrelated_node() -> void:
	var lonely := Node.new()
	var ci = ClaimInteraction.new()
	assert_null(ci._resolve_claimable(lonely),
		"a hit on an object with no Claimable in its family resolves to null (no claim prompt)")
	ci.free()
	lonely.free()
