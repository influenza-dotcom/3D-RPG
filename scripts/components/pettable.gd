class_name Pettable
extends Area3D


## Drop-in "you can PET this" component (designer-first: drag onto any object — a cat, a dog, a shrine — set it up
## in the Inspector, no scripting). While the player is aimed at this object, HOLDING the Takedown key (default Q,
## the same verb as the silent takedown) pets it: a ♥ floats up above the object. The friendly twin of the takedown.
##
## How it's driven: the player-side PetInteraction node (built in Player._ready, like SilentTakedown) polls the aim
## ray, resolves the aimed Pettable, runs the hold-to-confirm, and calls pet() here. This component just holds the
## config + the per-object reaction (heart / sound / signal).
##
## Why a DEDICATED layer (not the talk layer): the player's E-interact ray (ray_cast.gd) masks ONLY
## TalkHelpers.TALK_LAYER, so a Pettable on PET_LAYER is invisible to the talk system — no stray "[F]" prompt — while
## PetInteraction's ray (which masks every layer EXCEPT the talk layer, and also hits bodies) still finds us AND is
## occluded by a solid wall between the player and the object, so you can't pet through walls.
##
## Designer surface (all @export): enabled, hold_time, max_range, the prompt verb + name, the heart look/timing, a
## re-pet cooldown, an optional sound, and a toast toggle. React to a pet by connecting the `petted(by)` signal.

## Editor physics layer 19 (bit value 1<<18). NOT the talk layer (bit 5 = 16) so the E-interact ray never sees us;
## an Area3D is a sensor, so this layer never blocks bodies or bullets regardless of which bit it is.
const PET_LAYER: int = 1 << 18

## Fired on each successful pet, with the petter (the Player). Wire a reaction in-editor: a purr sfx, a quest flag,
## a companion-affinity bump, a "this cat now follows you" toggle, …
signal petted(by: Node)

@export_group("Pet")
## Master switch. Off => this object can never be petted (the prompt never shows).
@export var enabled: bool = true
## Seconds the Takedown key must be HELD over this object to pet it — a short beat, matching the takedown's hold.
@export_range(0.0, 3.0, 0.05) var hold_time: float = 0.6
## Max reach (m) from the camera to this object: the crosshair must be on it within this range to pet. PetInteraction
## probes its aim ray to this slider's max (6.0), so any authored value up to the ceiling is reachable — keep the two
## in sync if the ceiling changes (raise PetInteraction.RAY_REACH to match a higher ceiling).
@export_range(0.5, 6.0, 0.1) var max_range: float = 2.5
## Seconds before the SAME object can be petted again — paces the heart AND the applause cheer (default 2.0 s, a
## touch longer than the cheer so two claps never overlap). Lower it for rapid-fire petting, 0 for no cooldown.
@export_range(0.0, 5.0, 0.05) var cooldown: float = 2.0
## Verb shown in the hold prompt: "[Q] <verb> <name>". "Pet" by default; could be "Pat", "Greet", "Scratch", …
@export var prompt_verb: String = PlayerText.PROMPT_PET
## Name shown after the verb in the prompt. Empty => the parent node's name is used (so naming the node is enough).
@export var display_name: String = ""

@export_group("Heart")
## The glyph that floats above the object on a pet. Default ♥ (U+2665) — present in the engine's default font; the
## COLOUR emoji ❤ is not, so we draw this monochrome glyph and tint it with heart_color below.
@export var heart_glyph: String = "♥"
## Heart tint.
@export var heart_color: Color = Color(0.96, 0.27, 0.42)
## Heart spawn height above the object's origin (m). Raise it for a tall object, lower for a small critter.
@export var heart_height: float = 1.4
## How far the heart drifts UP (m) over its lifetime as it fades.
@export var heart_rise: float = 0.6
## Seconds the heart holds at full alpha before it starts fading.
@export_range(0.0, 2.0, 0.05) var heart_hold: float = 0.35
## Seconds the heart fade-out runs.
@export_range(0.05, 2.0, 0.05) var heart_fade: float = 0.7
## Heart glyph size (Label3D font size, scaled to world metres by the pixel_size below). ~0.8 m tall at the default.
@export var heart_font_size: int = 200

@export_group("Feel")
## Play the crowd-applause "clap" cheer on each pet — the SAME reward as an all-headshots NPC kill
## (AudioManager.play_applause). On by default; turn off for a quiet pet. Paced by `cooldown` so it can't spam.
@export var applause_on_pet: bool = true
## OPT-IN: pop a small player toast ("Pet <name>") on a pet, like the takedown's "Takedown" toast. Off by default.
@export var show_toast: bool = false
## Optional one-shot sound played AT the object on each pet (a purr / chirp / coo). Leave null for a silent pet.
@export var pet_sound: AudioStream

@export_group("Hitbox")
## OPT-IN (on by default): if you didn't author a CollisionShape3D child, auto-build one at runtime fitted to the
## parent's meshes, so a bare decorative mesh is pettable without hand-sizing a collider. If the object already has
## its OWN body collider, PetInteraction resolves us through the parent anyway, so this only matters for a
## collider-less mesh. An authored CollisionShape3D is never touched.
@export var auto_fit_collider: bool = true
## Fallback hitbox radius (m) used when auto_fit_collider is on but the parent has no meshes to fit.
@export var fallback_radius: float = 0.6

var _ready_to_pet: bool = true  ## cleared during the cooldown right after a pet, restored by a one-shot timer


## Become a sensor-only hitbox on our dedicated layer (so PetInteraction's ray can hit us; we sense nothing), then
## auto-build a fallback collider if asked and none was authored.
func _ready() -> void:
	# Sense nothing (collision_mask 0); the player's pet RAY finds us via our collision_layer, so leave monitoring at
	# its default — a direct-space raycast must reliably hit our shape, and mask 0 means monitoring does no real work.
	collision_layer = PET_LAYER
	collision_mask = 0
	if auto_fit_collider and _find_shape() == null:
		_build_fallback_shape()


## Whether this object can be petted RIGHT NOW — the live gate the driver checks before showing the prompt / holding.
func can_pet() -> bool:
	return eligible(enabled, not _ready_to_pet)


## Pure eligibility half (no distance — the driver adds the range check from the ray hit). Kept static + tiny so it's
## unit-testable with literal booleans, mirroring SilentTakedown.eligible.
static func eligible(is_enabled: bool, on_cooldown: bool) -> bool:
	return is_enabled and not on_cooldown


## The prompt name shown as "[Q] Pet <name>": our explicit display_name override; else the HOST's authored display
## name (a Throwable resolves its instance→data name, an NPC/Talkable exposes a plain display_name); else the host's
## raw node name; else "". We prefer the host's human name over its node name so a pettable Throwable reads "Pet Dog"
## instead of "Pet Throwable".
func pet_name() -> String:
	if not display_name.is_empty():
		return display_name
	var host := get_parent()
	if host == null:
		return ""
	# Prefer a host-provided resolver FIRST (Throwable.resolved_display_name folds in its data.display_name
	# fallback). This MUST precede the raw get() below: a Throwable with a blank instance display_name but a
	# data.display_name would otherwise read the empty instance string and leak the node name "Throwable".
	if host.has_method(&"resolved_display_name"):
		var resolved: Variant = host.call(&"resolved_display_name")
		if resolved is String and not (resolved as String).is_empty():
			return resolved
	# Generic duck-typed read for any node exposing a plain display_name export (NPC, Talkable, …), guarded with the
	# project's Variant + `is String` pattern (cf. silent_takedown.gd, TalkHelpers.speaker_name).
	var raw: Variant = host.get(&"display_name")
	if raw is String and not (raw as String).is_empty():
		return raw
	return String(host.name)


## Commit a pet (called by PetInteraction once the hold completes): float a heart, the applause cheer, optional
## sound + toast, fire the signal, then start the re-pet cooldown. Guarded by can_pet() so a double-call within the
## cooldown is a no-op — which is also what keeps the applause from overlapping itself.
func pet(by: Node) -> void:
	if not can_pet():
		return
	_ready_to_pet = false
	_spawn_heart()
	if applause_on_pet:
		AudioManager.play_applause()  # the same crowd-clap as an all-headshots kill; paced by the cooldown below
	if pet_sound != null:
		_play_sound()
	if show_toast and by != null and by.has_method(&"notify_toast"):
		var nm := pet_name()
		by.notify_toast(("%s %s" % [prompt_verb, nm]) if nm != "" else prompt_verb, heart_color)
	petted.emit(by)
	# Re-pet cooldown: a one-shot SceneTreeTimer restores eligibility (no per-frame _process on every Pettable).
	if cooldown > 0.0 and is_inside_tree():
		get_tree().create_timer(cooldown).timeout.connect(_clear_cooldown)
	else:
		_ready_to_pet = true


func _clear_cooldown() -> void:
	_ready_to_pet = true


## Float a ♥ up above the object, hold, fade, free — built entirely in code (no texture asset). The glyph is a
## billboarded, depth-test-off Label3D so it reads through our own mesh, exactly like the NPC bark "!" icon. Parented
## to us so it tracks the object if it moves.
func _spawn_heart() -> void:
	if not is_inside_tree():
		return
	var heart := Label3D.new()
	heart.text = heart_glyph
	heart.billboard = BaseMaterial3D.BILLBOARD_ENABLED  # always face the camera
	heart.no_depth_test = true   # read through walls / our own mesh so the cue is never occluded
	heart.shaded = false         # flat, unlit
	heart.modulate = heart_color
	heart.font_size = heart_font_size
	heart.pixel_size = 0.004     # world metres per font pixel
	heart.outline_size = 24
	heart.outline_modulate = Color(0.0, 0.0, 0.0, 0.7)
	heart.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heart.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(heart)
	heart.position = Vector3(0.0, heart_height, 0.0)
	# Rise the whole life; hold at full alpha, THEN fade alpha (+ the separate Label3D outline) and free. NB: the
	# fades use a per-tweener delay so they don't run during the hold.
	var tween := heart.create_tween()
	tween.tween_property(heart, "position:y", heart_height + heart_rise, heart_hold + heart_fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(heart, "modulate:a", 0.0, heart_fade).set_delay(heart_hold)
	tween.parallel().tween_property(heart, "outline_modulate:a", 0.0, heart_fade).set_delay(heart_hold)
	tween.chain().tween_callback(heart.queue_free)


## Play the optional pet_sound once at the object on the "sfx" bus, then free the transient player.
func _play_sound() -> void:
	if not is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = pet_sound
	p.bus = &"sfx"
	add_child(p)
	# NOTE the base pitch here is a flat 1.0: unlike a Throwable's own yap this does NOT read the host's
	# `sound_pitch_mult`, so a big dog purrs at the same pitch as a small one. Pre-existing; wire the host's
	# multiplier in as the base if that ever matters.
	AudioManager.play_varied(p)
	p.finished.connect(p.queue_free)


## Our authored CollisionShape3D child, or null.
func _find_shape() -> CollisionShape3D:
	for c in get_children():
		if c is CollisionShape3D:
			return c as CollisionShape3D
	return null


## Auto-build a look-at hitbox when the designer didn't author one: a BoxShape3D fitted to the PARENT's combined mesh
## bounds (so the whole object is pettable), or a fallback sphere when the parent has no meshes. Runtime only.
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
		var mesh_to_local := global_transform.affine_inverse() * (m as MeshInstance3D).global_transform
		var local_aabb := mesh_to_local * (m as MeshInstance3D).mesh.get_aabb()
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
