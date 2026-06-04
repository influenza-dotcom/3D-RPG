class_name NpcOutline
extends Node

## The NPC's combat OUTLINE pass — built in code (no .tscn) and chained IN FRONT of Character's
## damage-flash overlay (outline.next_pass = flash) so a single material_overlay produces both the
## inflated-hull rim and the hit-flash. Split off NPC so the root stays a thin coordinator: NPC owns
## the appearance STATE (the outline_* exports + OUTLINE_* consts + has_outline switch) and the colour
## resolver (_outline_color_for_disposition, shared with the laser); this child just (re)builds the
## ShaderMaterial from that colour and polls for a live attitude change.
##
## Host-coupled: NPC builds it in _ready (after the flash overlay exists) and sets `host` right after
## .new(). It READS the host's resolved_disposition() (via the colour resolver) + chains off the host's
## _flash_material, and re-applies the overlay through Character._apply_overlay_to_meshes(). Off-tree
## (a unit-test NPC built via .new() with no add_child) this child never exists, so NPC's facades guard
## on it being null — matching the old `if not has_outline or _flash_material == null: return` no-ops.

## The NPC this rim belongs to — set right after .new() in NPC._ready. READ-only here (we pull its
## resolved disposition + flash material); the canonical state stays on the host.
var host: NPC

## Last Disposition.Kind the outline was tinted for, so the host's _physics_process poll only rebuilds
## the rim material on an actual attitude CHANGE (a rep shift with no provoke), not every frame. -1 is
## never a Kind, so the first sync always rebuilds. Cached as int (Disposition.Kind is int-backed).
var _last_outline_kind: int = -1

## Chain the configured outline pass in front of the flash material and re-apply the combined overlay
## to the mesh tree. No-op if outlines are disabled or the flash overlay wasn't built (no `mesh`).
## Built once from _ready; toggling appearance later would re-run _apply_overlay_to_meshes.
func setup() -> void:
	if not host.has_outline or host._flash_material == null:
		return
	apply()  # initial build from the current disposition

## Rebuild the outline pass from the host's CURRENT _outline_color_for_disposition() (HOSTILE red /
## FRIENDLY green / NEUTRAL the export, or the blue companion rim) and chain it in front of the flash
## overlay. Safe to call repeatedly — re-applied on provoke and on a rep-driven attitude change (the
## host's Kind-compare poll). Each call builds a fresh ShaderMaterial; the old overlay is simply
## replaced (Godot frees it).
## NOTE: if the player is currently look-at-highlighting this NPC, TalkHelpers has stashed the real
## outline in meta and put a white highlight in the overlay slot; re-applying here would be clobbered
## on look-away. That's a rare provoke-mid-conversation case and self-heals on the next Kind-compare.
func apply() -> void:
	if not host.has_outline or host._flash_material == null:
		return
	var outline := TalkHelpers.make_outline_material(host._outline_color_for_disposition(), host.outline_width)
	outline.next_pass = host._flash_material
	host._apply_overlay_to_meshes(outline)
	_last_outline_kind = host.resolved_disposition()  # seed so the poll only rebuilds on a real change

## Re-tint the rim if the host's attitude changed with no provoke (a faction-rep shift — Reputation has
## no signal, so it must be polled). O(1); the material only rebuilds on a real change. Called once per
## frame from the host. Skipped entirely when there's no outline to retint (outlines off / no mesh ->
## no _flash_material), mirroring the old in-line guard.
func poll() -> void:
	if not host.has_outline or host._flash_material == null:
		return
	if host.resolved_disposition() != _last_outline_kind:
		apply()
