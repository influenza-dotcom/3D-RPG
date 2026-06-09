class_name GunMesh
extends MeshInstance3D

## The first-person view-model COORDINATOR. The root stays thin: it carries the cross-actor refs, the
## canonical rest + recoil state, and the one-shot pose TWEENS (fire / reload / land / holster / unholster
## — they tween THIS node's _recoil_pos/_recoil_rot), and wires the weapon's combat signals + muzzle FX in
## setup(). Everything with its own responsibility is split into code-built child components, each built in
## _ready with its `host` ref set right after .new() — and every facade below null-guards its child so an
## off-tree unit-test GunMesh (built via .new() with NO add_child, so _ready never runs) behaves exactly as
## the old monolith did:
##   - GunVisuals          — the rim-light + outline materials and the recursive dress passes (look).
##   - MuzzleRig           — snaps the rig muzzle to a weapon's own marker; resolves per-weapon anchors.
##   - WeaponModelSwapper  — instantiates / frees the equipped weapon's view-model; hides the placeholder.
##   - GunPose             — the per-frame procedural sway / bob / breath / ADS pose (writes our transform).

@export var player: Character
@export var inventory: Inventory
@export var attack: Attack

var tween: Tween
## The gun is mid-raise (settling back into view after a swap/reload) until this real-time stamp.
## The laser sight gates on this so it doesn't draw while the gun is still tweening in.
const GUN_RAISE_MS: int = 500
const HOLSTER_TIME: float = 0.35              ## seconds to swing the gun down (holster) / up (draw)
const HOLSTER_POS := Vector3(0.0, -1.4, 0.2)  ## lowered, off-screen rest offset while holstered
const HOLSTER_ROT := Vector3(-70.0, 0.0, 0.0) ## barrel tilted down as the gun is put away
var _raise_until_msec: int = 0
## The procedural rest pose, captured from the editor transform in _ready; the GunPose child reads these to
## seed and centre its sway/ADS solve, and the ADS marker eases off base_position.
var base_position: Vector3
var base_rotation: Vector3
var _aiming: bool = false   ## true while the player holds ADS (driven by ScopeIn.scoped_in); read by GunPose
var _recoil_pos: Vector3 = Vector3.ZERO  ## fire/reload/land kick, added ON TOP of the rest pose by GunPose
var _recoil_rot: Vector3 = Vector3.ZERO

## --- Single-responsibility children, built in _ready (code-built, no .tscn) + the host ref set right after
## .new(). Each owns one slice of the view model; the root stays a thin coordinator + facade and null-guards
## every one (they're absent on an off-tree unit-test GunMesh built via .new() with no _ready). ---
var _visuals: GunVisuals            # rim-light + outline materials and the dress passes
var _muzzle_rig: MuzzleRig          # rig-muzzle alignment + per-weapon anchor lookup
var _swapper: WeaponModelSwapper    # view-model instantiate/free + placeholder hide
var _pose: GunPose                  # per-frame procedural sway / bob / breath / ADS pose

## The weapon muzzle marker (projectile / raycast origin and muzzle-FX anchor), exposed
## read-only so the host can hand it to the weapon component without reaching through
## this scene's child nodes.
var muzzle: Marker3D:
	get:
		return get_node_or_null("Sketchfab_Scene/PlayerMuzzle") as Marker3D

## The ADS target: a Marker3D named "AimPos" placed under Camera3D (a sibling of the gun). While
## aiming, the gun eases to this marker's local position, so the aim pose is placed visually in the
## editor. Matched case-insensitively; falls back to the ads_position export if no marker exists.
var aim_pos_marker: Node3D:
	get:
		var p := get_parent()
		if p:
			for c in p.get_children():
				if c is Node3D and str(c.name).to_lower() == "aimpos":
					return c as Node3D
		return null

func _ready():
	base_position = position
	base_rotation = rotation_degrees
	# Build the children FIRST (GunPose seeds its smoothed pose off base_position above; MuzzleRig captures
	# the rig muzzle's resting spot; GunVisuals builds the rim/outline materials), then dress the rig itself.
	_build_components()
	# Shadows off + rim + outline on the rig (the monolith's _disable_shadows_recursive(self) + _setup_rim_light
	# + _setup_outline, in that order — now all inside GunVisuals.dress).
	_visuals.dress(self)
	# Deferred so the inventory has equipped its first weapon before the swapper reads it.
	_swapper.equip.call_deferred()

## Build the code-built view-model children and wire each one's host ref (and the sibling refs they call
## across) right after .new(), mirroring the NPC's _build_components idiom. These exist only on an in-tree
## GunMesh — an off-tree unit-test GunMesh (.new() with no add_child) never runs _ready, so every facade
## below null-guards its child.
func _build_components() -> void:
	_visuals = GunVisuals.new()
	_visuals.host = self
	add_child(_visuals)
	_muzzle_rig = MuzzleRig.new()
	_muzzle_rig.host = self
	add_child(_muzzle_rig)
	_swapper = WeaponModelSwapper.new()
	_swapper.host = self
	_swapper.visuals = _visuals
	_swapper.muzzle_rig = _muzzle_rig
	add_child(_swapper)
	# The muzzle rig resolves per-weapon anchor markers off the swapper's CURRENT view-model.
	_muzzle_rig.swapper = _swapper
	_pose = GunPose.new()
	_pose.host = self
	add_child(_pose)

## Inject the cross-actor refs the view model needs — its wielder, the equipped-weapon
## Inventory, and the combat Attack/Ammo it animates to — then wire the gun-mesh pose
## animations and the muzzle FX children to them. Called once by the host (player.gd)
## from _enter_tree, so all the view-model wiring lives inside this component instead
## of being spread across the host. Attack/Ammo live in the separate weapon component,
## so the host passes them in.
func setup(p_player: Character, p_inventory: Inventory, p_attack: Attack, p_ammo: Ammo, p_mouse_input: MouseInput, p_scope_in: ScopeIn) -> void:
	player = p_player
	inventory = p_inventory
	attack = p_attack

	# Gun-mesh pose animations, driven by the weapon's combat signals.
	p_attack.play_animation.connect(fire)
	p_attack.reload_started.connect(reload)
	p_attack.swap_started.connect(reload)
	p_attack.swap_finished.connect(_on_swap_finished)
	p_ammo.finished_reloading.connect(_on_ammo_finished_reloading)
	p_mouse_input.rotate.connect(_on_mouse_input_rotate)
	if p_scope_in:
		p_scope_in.scoped_in.connect(_on_aim_changed)

	# Muzzle FX hang under this gun (Sketchfab_Scene/PlayerMuzzle). Give the ones that need
	# the equipped weapon its inventory, and fire them from the Attack signals. Fetched
	# dynamically, hence Callable(node, "method") rather than typed references.
	var muzzle_node := get_node_or_null("Sketchfab_Scene/PlayerMuzzle")
	if muzzle_node:
		var mw := muzzle_node.get_node_or_null("MuzzleWhiz")
		if mw:
			mw.set("inventory", p_inventory)
			p_attack.flash_muzzle.connect(Callable(mw, "_on_flash_muzzle"))
		var mf := muzzle_node.get_node_or_null("MuzzleFlash")
		if mf:
			mf.set("inventory", p_inventory)
			p_attack.flash_muzzle.connect(Callable(mf, "_do_muzzle_flash"))
		var sp := muzzle_node.get_node_or_null("Spark")
		if sp:
			sp.set("inventory", p_inventory)
			p_attack.flash_muzzle.connect(Callable(sp, "_on_attack_flash_muzzle"))
		var sd := muzzle_node.get_node_or_null("ShellDrop")
		if sd:
			p_attack.shell_particle.connect(Callable(sd, "emit"))
			p_attack.shell_drop = sd as GPUParticles3D  # let Attack resize the casing per WeaponData.casing_size_scale before each eject

func fire():
	if tween:
		tween.kill()
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_recoil_pos", Vector3(0.0, 0.1, 0.4), 0.05)
	tween.tween_property(self, "_recoil_rot", Vector3(-5.0, 0.0, 0.0), 0.05)
	tween.chain().tween_property(self, "_recoil_pos", Vector3.ZERO, 0.1)
	tween.chain().tween_property(self, "_recoil_rot", Vector3.ZERO, 0.1)

func reload():
	if tween:
		tween.kill()
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_recoil_pos", Vector3(0.0, -0.9, 0.4), 0.5)
	tween.tween_property(self, "_recoil_rot", Vector3(-25.0, 0.0, 0.0), 0.5)

func land(intensity: float = 1.0) -> void:
	# Brief downward dip + slight barrel rise so the gun "absorbs" the landing
	# impact alongside the camera dip. Intensity is the same impact value the
	# camera uses, so heavier landings dip the gun further.
	# Landing now fires on EVERY touchdown (the host's dip guard was dropped), so
	# suppress it outright while a reload/swap is in flight — its long pose anim
	# would otherwise fight the landing dip (and the dip would clobber it in the
	# tween gaps the is_running() check below can't cover). Normal landings, and
	# the brief between-shots fire cooldown, still dip.
	# A holstered weapon must stay put away. While holstered the gun is parked off-screen via _recoil_pos
	# (= HOLSTER_POS); the landing dip below tweens _recoil_pos back toward zero, which would swing the hidden
	# gun right back into view. Skip the dip entirely while holstered so falling/landing never re-reveals it.
	if attack and attack.holstered:
		return
	if attack and attack.is_reload_or_swap_active():
		return
	# Don't interrupt an active fire/reload/swap tween — a tiny landing from
	# something like a downward shot recoil would otherwise stop those mid-anim.
	if tween and tween.is_running():
		return
	var dip := -0.08 * intensity
	var pitch := 4.0 * intensity
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_recoil_pos", Vector3(0.0, dip, 0.0), 0.08)
	tween.tween_property(self, "_recoil_rot", Vector3(pitch, 0.0, 0.0), 0.08)
	tween.chain().tween_property(self, "_recoil_pos", Vector3.ZERO, 0.18)
	tween.chain().tween_property(self, "_recoil_rot", Vector3.ZERO, 0.18)

func _on_ammo_finished_reloading() -> void:
	_raise_until_msec = Time.get_ticks_msec() + GUN_RAISE_MS
	if tween:
		tween.kill()
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_recoil_pos", Vector3.ZERO, 0.5)
	tween.tween_property(self, "_recoil_rot", Vector3.ZERO, 0.5)

## FNV-style put-away: swing the gun down + barrel-down out of view, then hide it once it's offscreen.
func holster() -> void:
	if tween:
		tween.kill()
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_recoil_pos", HOLSTER_POS, HOLSTER_TIME)
	tween.tween_property(self, "_recoil_rot", HOLSTER_ROT, HOLSTER_TIME)
	tween.chain().tween_callback(func(): visible = false)

## FNV-style draw: show the gun already lowered, then raise it back into the ready pose. Gates the
## laser sight (via _raise_until_msec) until it has settled, like a reload/swap raise.
func unholster() -> void:
	if tween:
		tween.kill()
	visible = true
	_recoil_pos = HOLSTER_POS
	_recoil_rot = HOLSTER_ROT
	_raise_until_msec = Time.get_ticks_msec() + int(HOLSTER_TIME * 1000.0)
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_recoil_pos", Vector3.ZERO, HOLSTER_TIME)
	tween.tween_property(self, "_recoil_rot", Vector3.ZERO, HOLSTER_TIME)

## True once the gun has finished tweening back into view after a swap/reload. The laser sight
## checks this so it only appears with the gun fully out, not mid-raise.
func is_raised() -> bool:
	return Time.get_ticks_msec() >= _raise_until_msec

func _on_swap_finished() -> void:
	_equip_view_model()
	_on_ammo_finished_reloading()

func _on_mouse_input_rotate(amt: Vector2) -> void:
	# Sway tuning + state live on GunPose; the connection stays here. No-op off-tree (no pose child).
	if _pose:
		_pose.add_mouse_sway(amt)

func _on_aim_changed(tf: bool) -> void:
	_aiming = tf
	# The scoped-rifle hide (sniper: disable_dof_while_scoped — look THROUGH the scope, not over the gun) is
	# applied by GunPose off this _aiming flag, NOT written here: GunPose sets host.visible every frame from
	# the view-model accessibility toggle, so a `visible = false` here would be clobbered on the next frame.
	# Other weapons keep their model for iron-sight ADS.

## Pure per-frame visibility decision for the first-person view model — split out static so its truth table
## is unit-testable (GunPose owns the live host.visible write and calls this each frame). The accessibility
## toggle (view_model_setting) gates everything; on top of it a "crisp scope" weapon (the sniper —
## disable_dof_while_scoped) hides its model while AIMING so you sight THROUGH the scope. Every other weapon
## keeps its model out for iron-sight ADS, and a null weapon never hides.
static func view_model_visible_now(view_model_setting: bool, aiming: bool, weapon: WeaponData) -> bool:
	var scope_hidden := aiming and weapon != null and weapon.disable_dof_while_scoped
	return view_model_setting and not scope_hidden

## Show the equipped weapon's own view-model — facade onto the WeaponModelSwapper child. Called from the
## deferred first equip (_ready) and after a weapon swap (_on_swap_finished). No-op off-tree (no child),
## exactly as the monolith's _equip_view_model short-circuited a bare instance (no inventory/equipped_weapon).
func _equip_view_model() -> void:
	if _swapper:
		_swapper.equip()

## Find a per-weapon anchor marker (case-insensitive) on the currently-equipped view-model — facade onto the
## MuzzleRig child. The laser sight reads this each frame. null off-tree (no child) OR when there's no
## view-model / no such marker, matching the monolith's `if not is_instance_valid(_weapon_model): return null`.
func equipped_marker(lower_name: String) -> Node3D:
	if _muzzle_rig:
		return _muzzle_rig.equipped_marker(lower_name)
	return null
