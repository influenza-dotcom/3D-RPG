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

## Initial build from _ready (via NPC._setup_outline). Two independent concerns, split so the per-limb hit-flash
## does NOT hang off `has_outline`:
##   * the disposition RIM — built only when has_outline is on (apply(), which also registers the per-part flash);
##   * the per-swapped-part FLASH materials — registered for ANY body-swap NPC even with has_outline OFF, so a hit
##     on a specific limb flashes only that limb (the pre-extraction behaviour: Character's flash-only setup pass
##     populated _part_flash gated only on _find_body_swap(), never on has_outline).
## Character's flash-only pass (_setup_overlay_chain -> _apply_overlay_to_meshes(_flash_material)) runs during
## super(), BEFORE this child is built, so it can't populate _part_flash then — we do it here off the same bare
## flash material (overlay == _flash_material makes each part wear its own flash pass directly, no rim). Nothing
## reads _part_flash between super() and now, so the deferral is invisible. No-op if the flash overlay was never
## built (no `mesh` -> _flash_material == null).
func setup() -> void:
	if host._flash_material == null:
		return
	if host.has_outline:
		apply()  # disposition rim chained in front of the flash; its re-apply also registers the per-part flash
	else:
		apply_part_overlays(host._flash_material)  # no rim, but still register per-limb flash (HEAD behaviour)

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


# --- Per-swapped-part hit-flash (moved off npc.gd in H2b) ---------------------------------------------------------
## The per-swapped-part flash machinery. The WHOLE-body flash stays on Character (its _flash_material + _build_flash_tween);
## these drive a PER-LIMB flash so hitting one arm lights only that arm. NPC keeps thin virtual-override shells
## (_apply_overlay_to_meshes / _flash_damage / flash_red — Character dispatches those BY NAME) that delegate here after
## their super() base pass. Keyed by part key ("head"/"torso"/"arm_l"/"arm_r"/"leg_l"/"leg_r").
var _part_flash: Dictionary = {}          ## part key -> its persistent ShaderMaterial (survives outline re-applies)
var _part_flash_tweens: Dictionary = {}   ## part key -> its in-flight pulse Tween (killed + restarted on a rapid re-hit)


## Apply the per-swapped-part overlays. Called by NPC._apply_overlay_to_meshes AFTER its super() whole-body pass, so
## each modelled part wears the combat outline chained in front of its OWN flash material (one limb flashing never
## lights the others). No-op with no BodyModelSwap (a bare Man.glb body just wears the whole-body overlay from super).
func apply_part_overlays(overlay: Material) -> void:
	var swap := host._find_body_swap()
	if swap == null:
		return
	var parts: Variant = swap.call(&"character_parts")
	if not (parts is Array):
		return
	for entry in parts:
		if not (entry is Dictionary):
			continue
		var key: String = entry.get("key", "")
		var root = entry.get("node", null)
		if key == "" or not (root is Node3D):
			continue
		var part_overlay := _build_part_overlay(overlay, _part_flash_material(key))
		var targets := TalkHelpers.collect_meshes(root, null, true)
		for m in targets:
			if m.has_meta(&"talk_prev_overlay"):
				m.set_meta(&"talk_prev_overlay", part_overlay)
			else:
				m.material_overlay = part_overlay


## Flash the SPECIFIC swapped part the shot hit (head / torso / nearer arm / leg), reusing the same body_part_at
## classifier the limb-damage system uses. An unlocated hit (explosion / fall) or a non-swapped body falls back to the
## host's whole-body flash_red (the NPC virtual: Character super + flash_all_parts here).
func flash_damage(hit_pos: Vector3) -> void:
	if hit_pos.is_finite():
		var key := _hit_part_key(hit_pos)
		if key != "" and _part_flash.has(key):
			_flash_part(key)
			return
	host.flash_red()


## Pulse EVERY swapped part. Called by NPC.flash_red AFTER its super() whole-body flash — an unlocated hit lights up
## the whole CUSTOM body, whose parts carry their own flash materials rather than the (hidden) Man.glb's shared one.
func flash_all_parts() -> void:
	for key in _part_flash:
		_flash_part(key)


## The overlay a swapped PART wears: the combat outline (a COPY, so its flash next_pass is per-part) chained in front
## of that part's own flash material -- so flashing one limb never lights the others. When there's no outline (the
## incoming overlay IS the bare host._flash_material -- outlines disabled, or the initial flash-only setup pass), the
## part just wears its own flash material directly.
func _build_part_overlay(overlay: Material, pf: ShaderMaterial) -> Material:
	if overlay == null or overlay == host._flash_material:
		return pf
	var copy := overlay.duplicate() as Material
	copy.next_pass = pf
	return copy


## Get-or-create the persistent flash material for a swapped part. Keyed by a stable string so it survives outline
## re-applies and model rebuilds (an in-flight pulse isn't lost). Same shader/params as Character's whole-body flash,
## just one instance PER part so each can be driven on its own.
func _part_flash_material(key: String) -> ShaderMaterial:
	var pf: ShaderMaterial = _part_flash.get(key, null)
	if pf == null:
		pf = ShaderMaterial.new()
		pf.shader = Character.FLASH_OVERLAY_SHADER
		pf.set_shader_parameter("flash_strength", 0.0)
		_part_flash[key] = pf
	return pf


## Map a world-space hit to the swapped-part KEY it struck. Head / torso map directly; arms / legs resolve to the
## nearer of the two mirrored instances by WORLD distance. "" when there's no swap (caller falls back to whole-body).
func _hit_part_key(hit_pos: Vector3) -> String:
	var swap := host._find_body_swap()
	if swap == null:
		return ""
	match host.body_part_at(hit_pos):
		Character.BodyPart.HEAD:
			return "head"
		Character.BodyPart.TORSO:
			return "torso"
		Character.BodyPart.ARMS:
			return _nearer_side_key(swap, hit_pos, "arm_l", "arm_r")
		Character.BodyPart.LEGS:
			return _nearer_side_key(swap, hit_pos, "leg_l", "leg_r")
	return ""


## Of two mirrored parts (left/right arm or leg), the key of whichever is physically closer to the hit. Falls back to
## the modelled side if only one exists, or "" if neither does.
func _nearer_side_key(swap: Node, hit_pos: Vector3, key_l: String, key_r: String) -> String:
	var nl := _swap_part_node(swap, key_l)
	var nr := _swap_part_node(swap, key_r)
	if nl == null:
		return key_r if nr != null else ""
	if nr == null:
		return key_l
	return key_l if nl.global_position.distance_squared_to(hit_pos) <= nr.global_position.distance_squared_to(hit_pos) else key_r


## The swapped part NODE for a key (from the component's character_parts()), or null if that part isn't modelled.
func _swap_part_node(swap: Node, key: String) -> Node3D:
	var parts: Variant = swap.call(&"character_parts")
	if parts is Array:
		for entry in parts:
			if entry is Dictionary and entry.get("key", "") == key:
				var n = entry.get("node", null)
				return n if n is Node3D else null
	return null


## Pulse one swapped part's flash material. Kills any in-flight pulse on the SAME part (a rapid second hit restarts
## it); different parts flash independently. The tween itself is built by Character (host._build_flash_tween).
func _flash_part(key: String) -> void:
	var pf: ShaderMaterial = _part_flash.get(key, null)
	if pf == null:
		return
	var prev: Tween = _part_flash_tweens.get(key, null)
	if prev != null and prev.is_valid():
		prev.kill()
	_part_flash_tweens[key] = host._build_flash_tween(pf)
