class_name NpcOutline
extends Node

## The NPC's combat OUTLINE pass — built in code (no .tscn) and chained IN FRONT of Character's
## damage-flash overlay (outline.next_pass = flash) so a single material_overlay produces both the
## inflated-hull rim and the hit-flash. Split off NPC so the root stays a thin coordinator: NPC owns
## the appearance STATE (the outline_* exports + OUTLINE_* consts + has_outline switch) and the colour
## resolver (_outline_color_for_disposition — the LASER's colour source; the ring maps the same
## predicates to a tint ID instead, see _disposition_id); this child stamps that id onto the tint
## duplicates and polls for a live attitude change.
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

## The lock-on fade, 0..1: how far into "this enemy is TARGETING the player" the ring currently is.
## Driven toward is_alerted_on_player() every poll() at 1/outline_target_fade_s per second, and stamped
## into the tint duplicates as the fractional part of the 7..8 engaged-hostile band
## (InkOutline.TINT_ID_HOSTILE_ENGAGED + mix) — the ink shader floors the close-range color bloom by it,
## so a locked-on hostile blooms to full red AT ANY DISTANCE and eases back when the lock breaks.
## Per-life state: reset_for_reuse zeroes it or a pooled body would respawn mid-red.
var _engaged_mix: float = 0.0

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

## Rebuild the NPC's outline state from the host's CURRENT disposition. SCREEN-SPACE ERA (2026-08-25):
## the inverted-hull rim is RETIRED for NPCs — a constant-screen-width shell's world thickness grows
## with distance until it out-thickens the ~10 cm Lego limbs and the per-part shells shatter into
## confetti, which no cap/fade tuning could fully save (probed at 13 m on a real NPC). The replacement
## is the shipped-game architecture (L4D2 glow buffer / Deep Rock stencil-ID family): each part carries
## an invisible flat DUPLICATE on InkOutline.ACTOR_TINT_LAYER encoding depth + a disposition id
## (resources/shaders/ink_tint.gdshader), and ink_outline.gdshader ring-dilates that buffer into a
## constant-PIXEL-width colored ring at any distance — all parts merge into ONE silhouette, so per-part
## confetti is structurally impossible. The overlay chain now carries ONLY the flash (the pre-outline
## "no-rim" shape). NPCs stay ON ACTOR_INK_MASK_LAYER — the world ink must never draw on an actor (the
## original contract, re-affirmed by the user 2026-08-25) — so the tint RING is the NPC's ONLY outline,
## which is why NEUTRAL gets an id too (4, a black ring) instead of falling back to ink.
## Safe to call repeatedly — re-applied on provoke and on a rep-driven attitude change (the poll);
## recoloring is one instance-uniform restamp per duplicate, no material churn.
## NOTE: the look-at talk highlight (TalkHelpers) still stashes/swaps the OVERLAY slot for its white
## close-range hull — that mechanism is untouched and composes fine over the ring.
func apply() -> void:
	if not host.has_outline or host._flash_material == null:
		return
	host._apply_overlay_to_meshes(host._flash_material)
	_sync_tint_duplicates()
	_last_outline_kind = host.resolved_disposition()  # seed so the poll only rebuilds on a real change

## The ink_tint disposition id for the host's CURRENT attitude — resolved off the SAME predicates
## _outline_color_for_disposition() reads (the follow override first, then resolved_disposition()), so
## the two stay one rule. ⭐ NEVER map this by comparing that resolver's COLOR against the NPC consts:
## the resolver rides CBPalette, which shifts hostile/friendly to orange/cyan under
## Settings.colorblind_safe_cues, and an exact-color compare matched nothing in safe mode — every
## hostile/friendly fell to the neutral BLACK ring (and the engaged-band promotion below, keyed on
## TINT_ID_HOSTILE, never fired) for exactly the players the safe palette serves (the 2026-08-27 gap;
## InkOutline's _params swaps the LUT to CBPalette's SAFE_* pair, so the ID is palette-agnostic and the
## COLOR is the ink pass's business). NEUTRAL (including any authored custom rim color, which the fixed
## LUT cannot carry — see InkOutline.highlight_hostile's doc) maps to TINT_ID_NEUTRAL, the BLACK ring:
## with NPCs excluded from the world ink, the ring is their ONLY outline, so every disposition must
## paint one.
func _disposition_id() -> int:
	if host.is_following():
		return InkOutline.TINT_ID_COMPANION
	match host.resolved_disposition():
		Disposition.Kind.HOSTILE:
			return InkOutline.TINT_ID_HOSTILE
		Disposition.Kind.FRIENDLY:
			return InkOutline.TINT_ID_FRIENDLY
	return InkOutline.TINT_ID_NEUTRAL

## Build / retint / remove the tint duplicates so they mirror the CURRENT swapped parts and disposition.
## A duplicate is a child of its source part mesh (transform + visibility follow for free — never the
## jazzfool transform-mirroring hazard), wears the ONE shared tint material, and carries its id as a
## per-instance uniform. Skinned meshes are skipped (a skin-bound duplicate needs skeleton plumbing and
## every real NPC body is rigid swapped parts — the bare Man.glb fallback simply gets ink-only).
## The mechanism itself lives on InkOutline (apply_tint / clear_tint) — shared with world props, which
## carry the same duplicates under different ids. This method is only the NPC-shaped scaffolding around
## it: resolve the swapped parts, resolve the disposition, hand each part root over.
func _sync_tint_duplicates() -> void:
	var id := _disposition_id()
	var swap := host._find_body_swap()
	if swap == null:
		return
	var parts: Variant = swap.call(&"character_parts")
	if not (parts is Array):
		return
	# THE LOCK-ON PROMOTION: a hostile with any engaged mix rides the continuous 7..8 band instead of
	# plain id 1 — same red, but the fraction past 7 floors the distance bloom in the ink shader. Only
	# hostile promotes: a friendly/companion/neutral NPC alerted on the player (a provoked ally mid-flip,
	# a brawl bystander) keeps its own colour until the disposition itself turns hostile.
	var blend := 0.0
	if id == InkOutline.TINT_ID_HOSTILE and _engaged_mix > 0.0:
		id = InkOutline.TINT_ID_HOSTILE_ENGAGED
		blend = _engaged_mix
	for entry in parts:
		if not (entry is Dictionary) or not (entry.get("node", null) is Node3D):
			continue
		InkOutline.apply_tint(entry["node"], id, blend)

## Drop this NPC's tint duplicates outright — the removal path an id-0 apply cannot reach, because
## apply() early-returns while `has_outline` is off. Called when the ring must stop existing rather than
## change colour: a pooled NPC reconfigured with outlines off would otherwise wear the previous life's
## ring forever (its duplicates live under part nodes that the pool reuses).
func clear_tint_duplicates() -> void:
	var swap := host._find_body_swap()
	if swap == null:
		return
	var parts: Variant = swap.call(&"character_parts")
	if not (parts is Array):
		return
	for entry in parts:
		if entry is Dictionary and entry.get("node", null) is Node3D:
			InkOutline.clear_tint(entry["node"])

## Re-tint the rim if the host's attitude changed with no provoke (a faction-rep shift — Reputation has
## no signal, so it must be polled). O(1); the material only rebuilds on a real change. Called once per
## think from the host with the BANKED AiLod delta (npc.gd's decision-layer contract: a throttled NPC
## reacts less OFTEN, nothing runs in slow motion — reading the raw physics step here instead made a
## far NPC's fade-out crawl 6-15x slow). Skipped entirely when there's no outline to retint (outlines
## off / no mesh -> no _flash_material), mirroring the old in-line guard. Also drives the lock-on fade
## (below), which deliberately rides the SAME guard: no outline, no engagement ring to animate.
func poll(delta: float) -> void:
	if not host.has_outline or host._flash_material == null:
		return
	if host.resolved_disposition() != _last_outline_kind:
		apply()
	_drive_engaged_mix(delta)

## Step _engaged_mix toward "is this NPC locked onto the player?" and restamp the tint duplicates when
## it actually moved. `delta` is the caller's banked think delta (real seconds since the last think, NOT
## the raw physics step — see poll). At rest (mix parked at 0 or 1) this is one predicate read per think
## — the restamp walk only runs during the fade window (~outline_target_fade_s per lock flip).
## move_toward lands EXACTLY on the goal, so the == park test is sound. A transiently invalid _target
## (the one-frame gap before _acquire_target re-locks) reads as goal 0 for a frame; at fade speeds
## that's a ~4% dip the next frame undoes — invisible, so not worth debouncing.
func _drive_engaged_mix(delta: float) -> void:
	var goal := 1.0 if host.is_alerted_on_player() else 0.0
	if _engaged_mix == goal:
		return
	var fade: float = maxf(host.outline_target_fade_s, 0.0)
	if fade <= 0.0:
		_engaged_mix = goal  # authored snap
	else:
		_engaged_mix = move_toward(_engaged_mix, goal, delta / fade)
	_sync_tint_duplicates()


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
			# Same ink-mask registration as Character._apply_overlay_to_meshes, for the SWAPPED parts —
			# BodyModelSwap resets `layers` on the models it spawns, so the whole-body stamp alone would
			# leave a freshly swapped limb inked. ⭐ NPCs stay EXCLUDED from the world ink (the original
			# "the ring owns actors, ink owns world" contract, re-affirmed by the user 2026-08-25 after a brief
			# ink-outlines-NPCs experiment): the NPC's outline is the screen-space tint RING alone — every
			# disposition has an id now, NEUTRAL included (a black ring), so exclusion never leaves an NPC
			# outline-less. See apply().
			m.layers |= InkOutline.ACTOR_INK_MASK_LAYER
			# Unconditional since 2026-08-27 — see Character._apply_overlay_to_meshes for why the look-at
			# highlight no longer needs a stash here.
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


## NPC-pooling reuse reset (NpcPool): clear the per-part combat flash so a reused NPC doesn't wear a stuck red
## limb tint, and force the rim to rebuild on the next poll(). The persistent per-part ShaderMaterials in
## _part_flash SURVIVE by design (get-or-create, expensive to rebuild + re-register) — we only zero their
## flash_strength; we do NOT clear the dict or re-run setup()/apply_part_overlays (that would duplicate overlays).
## Setting _last_outline_kind = -1 (never a valid Kind) forces the first post-reuse poll() to re-tint the rim to
## the reused life's disposition, exactly like the first build. The WHOLE-body flash lives on Character's reset.
func reset_for_reuse() -> void:
	_last_outline_kind = -1
	# Per-life: the reused life hasn't locked onto anyone. Without this a pooled body that died mid-fight
	# would respawn wearing the previous life's full-red engaged ring until its own first lock-on flip.
	_engaged_mix = 0.0
	# ⭐ The ring is NODE state living under the reused part meshes, not material state, so it survives a
	# pooling round-trip on its own. _last_outline_kind = -1 forces the next poll() to re-stamp the new
	# life's colour — but poll() is gated on `has_outline`, so a life configured with outlines OFF would
	# keep wearing the previous life's ring. Drop the duplicates outright in that case.
	if not host.has_outline:
		clear_tint_duplicates()
	else:
		# Restamp NOW, not at the first poll: AiLod's staggered first think can be ~0.25 s away, and a
		# body that died mid-lock still carries the ENGAGED band (~8.0) on its duplicates — which, unlike
		# the old plain-id staleness (black at range), renders full red at ANY distance. With the mix
		# zeroed above this re-stamps the plain disposition id, restoring the invisible-at-range window.
		_sync_tint_duplicates()
	for key in _part_flash_tweens:
		var t: Tween = _part_flash_tweens[key]
		if t != null and t.is_valid():
			t.kill()  # a freeze-paused pulse would otherwise resume driving flash_strength back up on reuse
	_part_flash_tweens.clear()
	for key in _part_flash:
		var pf: ShaderMaterial = _part_flash[key]
		if pf != null:
			pf.set_shader_parameter("flash_strength", 0.0)
