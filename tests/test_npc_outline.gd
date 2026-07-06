extends GutTest

## H2b (Wave 6): the per-swapped-part hit-flash machinery moved off npc.gd into NpcOutline — _build_part_overlay,
## _part_flash_material, _hit_part_key/_nearer_side_key, _flash_part + the _part_flash state, behind the entry points
## apply_part_overlays / flash_damage / flash_all_parts. The 3 virtual overrides Character dispatches BY NAME
## (_apply_overlay_to_meshes / _flash_damage / flash_red) MUST stay defined on NPC as thin shells that keep their
## super() base pass and delegate here — these pin that split + the pure helper logic. The in-tree overlay/tween
## application is playtest-verified; here we pin the parts that don't need a live mesh tree.

const OutlineScript := preload("res://scripts/npc/npc_outline.gd")


## A BodyModelSwap stand-in: only the character_parts() the part-key helpers duck-scan.
class _SwapStub extends Node:
	var parts: Array = []
	func character_parts() -> Array:
		return parts


func test_part_flash_material_is_idempotent_per_key() -> void:
	# Get-or-create: the same part key returns the SAME persistent ShaderMaterial (so an in-flight pulse survives an
	# outline re-apply / model rebuild); a different key gets its own instance.
	var o = OutlineScript.new()
	var head = o._part_flash_material("head")
	assert_not_null(head, "a new part key creates its flash material")
	assert_true(head is ShaderMaterial, "the part flash material is a ShaderMaterial")
	assert_eq(o._part_flash_material("head"), head, "the same key returns the SAME instance (persistent across re-applies)")
	assert_true(o._part_flash_material("torso") != head, "a different part key gets its own instance")
	o.free()


func test_build_part_overlay_chains_or_passes_through() -> void:
	# With no outline (overlay == null, or overlay == the bare host flash material) the part just wears its own flash
	# material; a real outline is DUPLICATED so its flash next_pass is per-part (one limb flashing never lights others).
	var npc = load("res://scripts/npc/npc.gd").new()  # host is NPC-typed; a bare .new() has _flash_material == null
	var o = OutlineScript.new()
	o.host = npc
	var pf := ShaderMaterial.new()
	assert_eq(o._build_part_overlay(null, pf), pf, "a null overlay -> the part wears its own flash material directly")
	var outline := StandardMaterial3D.new()  # any real Material != host._flash_material (null here)
	var combined = o._build_part_overlay(outline, pf)
	assert_true(combined != outline, "a real overlay is DUPLICATED (so each part's flash next_pass is independent)")
	assert_eq(combined.next_pass, pf, "the copy chains the part's flash material as its next_pass")
	npc.free()
	o.free()


func test_nearer_side_key_picks_the_closer_mirrored_part() -> void:
	# For a mirrored pair (arm_l / arm_r), the hit resolves to whichever instance is physically closer — frame-agnostic
	# (by world distance), so it stays right however the body is posed.
	var o = OutlineScript.new()
	var swap := _SwapStub.new()
	var arm_l := Node3D.new()
	var arm_r := Node3D.new()
	add_child_autofree(arm_l)
	add_child_autofree(arm_r)
	arm_l.global_position = Vector3(0.0, 0.0, 0.0)
	arm_r.global_position = Vector3(10.0, 0.0, 0.0)
	swap.parts = [{"key": "arm_l", "node": arm_l}, {"key": "arm_r", "node": arm_r}]
	assert_eq(o._nearer_side_key(swap, Vector3(1.0, 0.0, 0.0), "arm_l", "arm_r"), "arm_l", "a hit near arm_l resolves to arm_l")
	assert_eq(o._nearer_side_key(swap, Vector3(9.0, 0.0, 0.0), "arm_l", "arm_r"), "arm_r", "a hit near arm_r resolves to arm_r")
	# Only one side modelled -> that side (never "").
	swap.parts = [{"key": "arm_r", "node": arm_r}]
	assert_eq(o._nearer_side_key(swap, Vector3(0.0, 0.0, 0.0), "arm_l", "arm_r"), "arm_r", "only arm_r modelled -> arm_r regardless of distance")
	o.free()


func test_npc_keeps_the_virtual_override_shells() -> void:
	# The 3 methods Character dispatches BY NAME must stay DEFINED on NPC (as shells), or the base's calls to
	# _apply_overlay_to_meshes / _flash_damage / flash_red would hit only the base and the per-part flash would vanish.
	var npc = load("res://scripts/npc/npc.gd").new()
	assert_true(npc.has_method("_apply_overlay_to_meshes"), "NPC keeps the _apply_overlay_to_meshes virtual override")
	assert_true(npc.has_method("_flash_damage"), "NPC keeps the _flash_damage virtual override")
	assert_true(npc.has_method("flash_red"), "NPC keeps the flash_red virtual override")
	npc.free()


func test_outline_exposes_the_delegation_entry_points() -> void:
	var o = OutlineScript.new()
	assert_true(o.has_method("apply_part_overlays"), "NpcOutline.apply_part_overlays (NPC._apply_overlay_to_meshes delegates here)")
	assert_true(o.has_method("flash_damage"), "NpcOutline.flash_damage (NPC._flash_damage delegates here)")
	assert_true(o.has_method("flash_all_parts"), "NpcOutline.flash_all_parts (NPC.flash_red delegates here)")
	o.free()


func test_setup_registers_per_limb_flash_even_with_has_outline_off() -> void:
	# REGRESSION (H2b): the per-swapped-part flash must register for a body-swap NPC REGARDLESS of has_outline.
	# Pre-extraction, Character's flash-only pass (_apply_overlay_to_meshes(_flash_material)) populated _part_flash
	# gated ONLY on _find_body_swap(). The extraction moved that population onto NpcOutline; its setup() must NOT
	# hang the part pass off the has_outline rim gate — else an outline-less NPC with a swapped body loses per-limb
	# flash (a limb hit falls back to whole-body). We drive setup() off-tree (bare NPC host, no _ready) with a swap
	# stub child so _find_body_swap() finds it, and assert _part_flash got the key with has_outline OFF.
	var npc = load("res://scripts/npc/npc.gd").new()
	npc.has_outline = false
	npc._flash_material = ShaderMaterial.new()  # Character builds this in _setup_overlay_chain; stub it (no mesh needed)
	var swap := _SwapStub.new()
	var head := Node3D.new()
	add_child_autofree(head)
	swap.parts = [{"key": "head", "node": head}]
	npc.add_child(swap)  # _find_body_swap() scans host children for a character_parts() provider (off-tree: no _ready)
	var o = OutlineScript.new()
	o.host = npc
	o.setup()
	assert_true(o._part_flash.has("head"), "has_outline=false + body swap STILL registers the per-limb flash (HEAD parity)")
	assert_true(o._part_flash["head"] is ShaderMaterial, "the registered part flash is a ShaderMaterial")
	npc.free()  # frees the swap child too
	o.free()
