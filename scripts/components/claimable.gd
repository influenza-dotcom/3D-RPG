class_name Claimable
extends Area3D


## Drop-in "you can CLAIM this" component (designer-first: drag onto any object — a stray dog, a drone, a robot — set
## it up in the Inspector, no scripting). While the player is aimed at this object, pressing the Claim key (default B)
## adopts it: the player names it, and the object starts FOLLOWING the player. The one-time, ownership twin of the
## petting verb — pet for affection (repeatable), claim to make it YOURS (once).
##
## What claiming does (claim()):
##   1. Renames the object to the chosen name (pushed onto the host's `display_name` so the look-at readout + the pet
##      prompt now read the dog's NAME).
##   2. Switches on a [[prop_follow.gd]] so the object teleport-follows the player. If the designer pre-placed a
##      PropFollow child (so they could tune its blink distance / cooldown in the Inspector) we just ENABLE it;
##      otherwise we add a default one. This is the "claiming the dog gives it the follow component" wiring.
##   3. Fires `claimed(by, chosen_name)` so the designer can hook a reaction (a quest flag, a bark, an affinity bump).
##
## How it's driven: the player-side ClaimInteraction node ([[claim_interaction.gd]], built in Player._ready like the
## pet/takedown verbs) polls the aim ray, resolves the aimed Claimable, and on the Claim key opens the name dialog
## (or claims straight away if ask_for_name is off) then calls claim() here. This component just holds the config +
## performs the claim.
##
## Like Pettable, this is a SENSOR on its own dedicated physics layer so the player's E-interact / pet rays never see
## it (no stray prompt); ClaimInteraction's ray finds it on CLAIM_LAYER. An Area3D never blocks bodies or bullets.

## Editor physics layer 20 (bit value 1<<19). Distinct from Pettable's PET_LAYER (1<<18) and the talk layer, so the
## claim ray, the pet ray, and the E-interact ray each see only their own targets.
const CLAIM_LAYER: int = 1 << 19

## Item metadata keys: whether the prop was BEFRIENDED when it was stashed into the inventory (a bool) and the NAME it
## was given. Written by DogPickup on stash, read by WorldItem.build on drop into preset_claimed / preset_claim_name —
## so a re-dropped dog is still yours (follows you, keeps its name + blue rim) instead of reverting to an unclaimed
## stray. See the RE-DROP FIDELITY note in [[random_coat.gd]] for the sibling coat-colour case.
const CLAIMED_META := &"claimable_claimed"
const CLAIMED_NAME_META := &"claimable_name"

## Fired once, when the object is claimed, with the claimer (the Player) and the final chosen name. Wire a reaction
## in-editor: a happy bark, a "now follows you" quest flag, a faction shift, …
signal claimed(by: Node, chosen_name: String)
## Fired once when a claimed object is RELEASED (the player held the Claim key to unclaim it), with the releaser.
## Wire the inverse reaction here (drop a "follows you" quest flag, a sad bark, …).
signal unclaimed(by: Node)

@export_group("Claim")
## Master switch. Off => this object can never be claimed (the prompt never shows).
@export var enabled: bool = true
## Max reach (m) from the camera to this object: the crosshair must be on it within this range to claim.
## ClaimInteraction probes its aim ray to this slider's max (8.0), so any authored value up to the ceiling is
## reachable — keep the two in sync if the ceiling changes (raise ClaimInteraction.RAY_REACH to match a higher ceiling).
@export_range(0.5, 8.0, 0.1) var max_range: float = 3.0
## Verb shown in the prompt: "[B] <verb> <name>". "Befriend" by default (friendlier than "Claim" for adopting a
## stray); could be "Adopt", "Tame", "Recruit", "Claim", …
@export var prompt_verb: String = PlayerText.PROMPT_BEFRIEND
## Name shown after the verb in the prompt. Empty => the host's resolved name (a Throwable's "Dog") or its node name.
@export var display_name: String = ""

@export_group("Naming")
## When true (default), claiming opens a real-time text box to NAME the object; the typed name is applied. When false,
## claiming is instant and uses default_name (or the resolved name) — no dialog.
@export var ask_for_name: bool = true

@export_group("Preset (drop-restore)")
## PRE-BEFRIEND this object as soon as it spawns — used to restore a dog you'd befriended, then stashed and dropped,
## back into the "yours" state (follows you, named, blue rim, loyal) without you re-befriending it. Not usually
## hand-authored: WorldItem.build sets it from CLAIMED_META when it rebuilds a dropped prop. Off => spawns unclaimed.
@export var preset_claimed: bool = false
## The name to restore when preset_claimed is on (the name you gave the dog before stashing it). Blank falls back to
## default_name / the resolved object name, exactly like a live claim.
@export var preset_claim_name: String = ""
## Pre-filled in the name box, and the name used outright when ask_for_name is off. Empty => the resolved object name
## (so an unnamed claim of the "Dog" still reads "Dog").
@export var default_name: String = ""

@export_group("Feel")
## OPT-IN: pop a small player toast ("Claimed <name>") on claim. Off by default.
@export var show_toast: bool = false
## Toast tint (also a pleasant default for any UI echo). Warm gold by default.
@export var toast_color: Color = Color(1.0, 0.86, 0.3)
## Optional one-shot sound played AT the object on claim (a happy bark / chirp / power-up). Leave null for silence.
@export var claim_sound: AudioStream

@export_group("Claimed look")
## Mark a CLAIMED prop with a persistent outline so it reads as "yours" at a glance. Default ON. Only applies if the
## host prop supports a persistent outline (a Throwable does, via set_persistent_outline); other hosts skip it
## silently. Lifted automatically on unclaim.
@export var show_claimed_outline: bool = true
## The claimed rim colour. Blue by default to match the recruited-companion convention — an NPC following you wears
## NPC.OUTLINE_FOLLOWING (the same blue), so a claimed dog and a recruited guard read alike.
@export var claimed_outline_color: Color = Color(0.15, 0.45, 1.0)

@export_group("Unclaim")
## Allow RELEASING a claimed object — HOLD the Claim key while aimed at it to unclaim. Off => claiming is permanent
## (a claimed object then shows no prompt at all, since it's neither claimable nor releasable).
@export var allow_unclaim: bool = true
## Seconds the Claim key must be HELD over a CLAIMED object to release it — a deliberate beat so a stray tap can't
## un-adopt your dog. Matches the pet/takedown hold feel.
@export_range(0.0, 3.0, 0.05) var unclaim_hold_time: float = 0.6
## Show the "Hold to Release" prompt + fill bar while aimed at a befriended object. OFF by default — releasing still
## works (hold the key the same `unclaim_hold_time`), it's just a HIDDEN gesture so the prompt doesn't clutter the HUD.
@export var show_release_prompt: bool = false

@export_group("Befriended combat")
## When befriended, a THROWN prop (like the dog) becomes LOYAL: it won't damage your FRIENDLY/NEUTRAL NPCs and hits
## HOSTILE NPCs harder. On by default. Only affects hosts that support it (a Throwable does); cleared on release.
@export var loyal_when_befriended: bool = true
## A befriended prop spares the player's friends — no thrown damage to FRIENDLY/NEUTRAL NPCs (only hostiles). On by
## default (a loyal dog won't bite your allies). Off makes it hit everyone (hostiles still take the multiplier).
@export var befriended_spares_allies: bool = true
## Extra THROWN damage a befriended prop deals to ENEMY (hostile) NPCs vs a regular throw. 2.0 = double damage.
@export_range(0.5, 10.0, 0.1) var befriended_damage_multiplier: float = 2.0

@export_group("Hitbox")
## OPT-IN (on by default): if you didn't author a CollisionShape3D child, auto-build one at runtime fitted to the
## parent's meshes, so a bare decorative mesh is claimable without hand-sizing a collider. Mirrors Pettable.
@export var auto_fit_collider: bool = true
## Fallback hitbox radius (m) used when auto_fit_collider is on but the parent has no meshes to fit.
@export var fallback_radius: float = 0.6

var _claimed: bool = false  ## set true the instant this object is claimed; claiming is one-shot
## The host's display_name BEFORE it was befriended — captured in claim(), restored in unclaim() so releasing a dog
## also strips the name you gave it (an unbefriended dog is just "Dog" again). null = nothing captured (host has no
## display_name); a Variant so a blank original ("") stays distinct from "not captured".
var _original_name: Variant = null


## Become a sensor-only hitbox on our dedicated layer (so ClaimInteraction's ray hits us; we sense nothing), then
## auto-build a fallback collider if asked and none was authored. Mirrors Pettable._ready.
func _ready() -> void:
	collision_layer = CLAIM_LAYER
	collision_mask = 0
	if auto_fit_collider and _find_shape() == null:
		_build_fallback_shape()
	# Restore a re-dropped, previously-befriended prop. DEFERRED so the parent's _ready has run first — claim() calls
	# set_persistent_outline / set_loyal_combat on the host (a Throwable sets those up in ITS _ready, which runs AFTER
	# this child's) and adds a PropFollow child (needs us in-tree). A self-method Callable is dropped safely if we're
	# freed before the flush. Guarded by can_claim() inside claim(), so a double-fire is a harmless no-op.
	if preset_claimed and not Engine.is_editor_hint():
		_apply_preset_claim.call_deferred()


## Auto-claim from the preset (deferred out of _ready, see there). Uses null `by`: no player drove this claim, so the
## toast is skipped (claim() guards `by != null`) and the `claimed` signal fires with a null claimer — a designer
## reaction wired to it must tolerate that (mirrors an unclaim's null releaser).
func _apply_preset_claim() -> void:
	if not is_inside_tree():
		return
	claim(null, preset_claim_name)


## Whether this object is CURRENTLY befriended — the live read DogPickup uses to stash the claim state onto the dog's
## Item, so a re-dropped dog stays yours. Public accessor for the one-shot `_claimed` latch.
func is_claimed() -> bool:
	return _claimed


## Whether this object can be claimed RIGHT NOW — the live gate the driver checks before showing the prompt.
func can_claim() -> bool:
	return eligible(enabled, _claimed)


## Pure eligibility half (no distance — the driver adds the range check from the ray hit). Static + tiny so it's
## unit-testable with literal booleans, mirroring Pettable.eligible.
static func eligible(is_enabled: bool, already_claimed: bool) -> bool:
	return is_enabled and not already_claimed


## Whether this object can be RELEASED right now: it's claimed AND releasing is allowed. The driver shows the
## HOLD-to-unclaim prompt only while this is true (a permanently-claimed object — allow_unclaim off — shows nothing).
func can_unclaim() -> bool:
	return _claimed and allow_unclaim


## The prompt name shown as "[B] Claim <name>": our explicit display_name override; else the HOST's resolved/authored
## name; else its node name. Same resolution order as Pettable.pet_name so "Claim Dog" reads identically.
func claim_name() -> String:
	var host := get_parent()
	# Once CLAIMED, the chosen name lives on the host and is AUTHORITATIVE — so the prompt, the look-at readout, and the
	# release toast all agree. The `display_name` export is only a PRE-claim prompt label (for a prop with no good name
	# of its own), so it's consulted first only before the claim — after which the host's name wins.
	if _claimed:
		var claimed_host_name := _host_name(host)
		if not claimed_host_name.is_empty():
			return claimed_host_name
	if not display_name.is_empty():
		return display_name
	if host == null:
		return ""
	var hn := _host_name(host)
	return hn if not hn.is_empty() else String(host.name)


## The host's own human name: its resolved_display_name() (a Throwable folds in data.display_name) else a plain
## display_name export, else "". Shared by both branches of claim_name().
func _host_name(host: Node) -> String:
	if host == null:
		return ""
	if host.has_method(&"resolved_display_name"):
		var resolved: Variant = host.call(&"resolved_display_name")
		if resolved is String and not (resolved as String).is_empty():
			return resolved as String
	var raw: Variant = host.get(&"display_name")
	if raw is String and not (raw as String).is_empty():
		return raw as String
	return ""


## Commit the claim (called by ClaimInteraction once a name is chosen). `chosen_name` is the typed/auto name; blank
## falls back to default_name, then the resolved object name. Renames the host, switches on the follow, plays the
## feel, fires the signal. Guarded by can_claim() so a double-call is a harmless no-op.
func claim(by: Node, chosen_name: String = "") -> void:
	if not can_claim():
		return
	_claimed = true
	var final_name := chosen_name.strip_edges()
	if final_name.is_empty():
		final_name = default_name.strip_edges()
	if final_name.is_empty():
		final_name = claim_name()
	var host_for_capture := get_parent()
	_original_name = host_for_capture.get(&"display_name") if host_for_capture != null else null  # remember the pre-befriend name to restore on release
	_apply_name(final_name)
	_enable_follow()
	_apply_claimed_outline()
	_apply_loyal_combat()
	if claim_sound != null:
		_play_sound()
	if show_toast and by != null and by.has_method(&"notify_toast"):
		by.notify_toast(PlayerText.befriend(final_name), toast_color)
	claimed.emit(by, final_name)


## Push the chosen name onto the host's display_name so the look-at readout + the pet prompt now show the dog's NAME.
## set() is a no-op on a host without that property, so this is safe on any parent. A blank name leaves the host as-is.
func _apply_name(final_name: String) -> void:
	if final_name.is_empty():
		return
	var host := get_parent()
	if host != null:
		host.set(&"display_name", final_name)


## Switch on the follow: enable a designer-placed PropFollow on the host (so its Inspector tuning is honoured), else
## add a default one. reset_cooldown() so the prop doesn't blink the instant it's claimed.
func _enable_follow() -> void:
	var host := get_parent()
	if host == null:
		return
	var follow := _find_follow(host)
	if follow == null:
		follow = PropFollow.new()
		follow.name = "PropFollow"
		host.add_child(follow)
	follow.enabled = true
	follow.reset_cooldown()


## An existing PropFollow child of `host`, or null. Lets the designer pre-place + tune one (shipped disabled).
func _find_follow(host: Node) -> PropFollow:
	for c in host.get_children():
		if c is PropFollow:
			return c as PropFollow
	return null


## Release a claimed object (called by ClaimInteraction once an unclaim HOLD completes): stop it following, drop the
## claimed rim, STRIP the name you gave it (revert to its original — an unbefriended dog is just "Dog" again), and make
## it befriendable again. Guarded by can_unclaim() so a stray call is a harmless no-op.
func unclaim(by: Node = null) -> void:
	if not can_unclaim():
		return
	var released_name := claim_name()  # the name we gave it — captured for the toast BEFORE we strip it (still _claimed)
	_claimed = false
	_disable_follow()
	_clear_claimed_outline()
	_clear_loyal_combat()
	_restore_original_name()  # un-name: revert to whatever it was called before being befriended
	if show_toast and by != null and by.has_method(&"notify_toast"):
		by.notify_toast(PlayerText.released(released_name), toast_color)
	unclaimed.emit(by)


## Revert the host's display_name to whatever it was BEFORE befriending (captured in claim()), so releasing a dog
## strips the name you gave it. Only touches a host that actually has the property; _original_name is null when nothing
## was captured (a host with no display_name), in which case there's nothing to revert.
func _restore_original_name() -> void:
	if not (_original_name is String):
		return
	var host := get_parent()
	if host != null:
		host.set(&"display_name", _original_name)
	_original_name = null


## Switch OFF the host's PropFollow (it stops blinking after you). We disable rather than free it so a pre-placed,
## designer-tuned follow survives a release→re-claim round-trip with its settings intact.
func _disable_follow() -> void:
	var host := get_parent()
	if host == null:
		return
	var follow := _find_follow(host)
	if follow != null:
		follow.enabled = false


## Pin the blue claimed rim on the host (if it supports a persistent outline — a Throwable does). Duck-typed so
## Claimable works on any prop; a host without the outline system just skips it.
func _apply_claimed_outline() -> void:
	if not show_claimed_outline:
		return
	var host := get_parent()
	if host != null and host.has_method(&"set_persistent_outline"):
		host.call(&"set_persistent_outline", claimed_outline_color)


## Lift the claimed rim on release (duck-typed, mirrors _apply_claimed_outline).
func _clear_claimed_outline() -> void:
	var host := get_parent()
	if host != null and host.has_method(&"clear_persistent_outline"):
		host.call(&"clear_persistent_outline")


## Push "loyal" thrown-combat onto the host (duck-typed; a Throwable supports set_loyal_combat) so the befriended prop
## spares your friendly/neutral NPCs and hits hostiles harder when thrown. Called on befriend; no-op if disabled or the
## host doesn't support it.
func _apply_loyal_combat() -> void:
	if not loyal_when_befriended:
		return
	var host := get_parent()
	if host != null and host.has_method(&"set_loyal_combat"):
		host.call(&"set_loyal_combat", true, befriended_damage_multiplier, befriended_spares_allies)


## Clear "loyal" thrown-combat on release — the prop reverts to a normal throwable (damages everyone normally again).
## Duck-typed; mirrors _apply_loyal_combat.
func _clear_loyal_combat() -> void:
	var host := get_parent()
	if host != null and host.has_method(&"set_loyal_combat"):
		host.call(&"set_loyal_combat", false, 1.0, true)


## Play the optional claim_sound once at the object on the "sfx" bus, then free the transient player. Mirrors
## Pettable._play_sound.
func _play_sound() -> void:
	if not is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = claim_sound
	p.bus = &"sfx"
	add_child(p)
	AudioManager.play_varied(p)  # base 1.0 — this does not read the host's sound_pitch_mult; see Pettable._play_sound
	p.finished.connect(p.queue_free)


## Our authored CollisionShape3D child, or null.
func _find_shape() -> CollisionShape3D:
	for c in get_children():
		if c is CollisionShape3D:
			return c as CollisionShape3D
	return null


## Auto-build a look-at hitbox when the designer didn't author one: a BoxShape3D fitted to the PARENT's combined mesh
## bounds, or a fallback sphere when the parent has no meshes. Runtime only. Mirrors Pettable._build_fallback_shape.
func _build_fallback_shape() -> void:
	var cs := CollisionShape3D.new()
	add_child(cs)
	var meshes: Array = []
	var parent := get_parent()
	if parent != null:
		meshes = TalkHelpers.collect_meshes(parent, self)
	var combined := AABB()
	var have := false
	for m in meshes:
		if m == null or m.mesh == null:
			continue
		var mesh_to_self := global_transform.affine_inverse() * (m as MeshInstance3D).global_transform
		var local_aabb := mesh_to_self * (m as MeshInstance3D).mesh.get_aabb()
		combined = local_aabb if not have else combined.merge(local_aabb)
		have = true
	if have:
		var box := BoxShape3D.new()
		box.size = combined.size
		cs.shape = box
		cs.position = combined.position + combined.size * 0.5
	else:
		var sph := SphereShape3D.new()
		sph.radius = fallback_radius
		cs.shape = sph
