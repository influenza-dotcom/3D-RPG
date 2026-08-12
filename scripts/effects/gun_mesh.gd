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

## The Character wielding this view-model (the player). Injected by setup() from the host; the pose/recoil read it to know whose gun this is. Usually left blank in-scene and wired in code.
@export var player: Character
## The equipped-weapon Inventory this view-model reads to know which gun to show and animate. Injected by setup(); blank in-scene.
@export var inventory: Inventory
## The weapon's Attack component whose combat signals (fire / reload / swap) drive this view-model's pose tweens. Injected by setup(); blank in-scene.
@export var attack: Attack

var tween: Tween
## The gun is mid-raise (settling back into view after a swap/reload) until this real-time stamp.
## The laser sight gates on this so it doesn't draw while the gun is still tweening in.
## BASELINE + test anchor (pinned in test_effects.gd), no longer the live read: the raise window AND
## the raise tween both derive from the ONE designer knob GameSettings.effects.gun_raise_time (which
## defaults to this / 1000 — test_effects.gd asserts the pair) via the same `int(t * 1000.0)`
## derivation unholster() uses, so the laser gate can never drift apart from the raise animation.
const GUN_RAISE_MS: int = 500
# Every one-shot pose tween's numbers are designer knobs on GameSettings.effects: the holster swing
# + put-away pose (gun_holster_*), the reload/swap dip (gun_reload_dip_*), the post-reload raise
# (gun_raise_time — see GUN_RAISE_MS above), and the landing dip (gun_land_*).
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

func _ready() -> void:
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

## The ONE visual reaction to attacking, for every weapon: kick the whole rig out and back. A mounted view
## model is a CHILD of this node, so it rides the kick for free — which is why no weapon needs its own
## animation to feel like it fired.
##
## A PUNCH is the same tween with the opposite sign: `WeaponData.view_model_punch` swaps the gun's backward
## recoil for a forward extension (GameSettings.effects punch_kick_*), because a fist that recoils into your
## own face while the arm thrusts out reads as mush. That flag ALSO asks the mounted model to play its own
## strike, if it has one — the unarmed hands do (BodyModelSwap.strike), a gun mesh doesn't, and the
## has_method() guard is what lets one call site serve both.
func fire() -> void:
	if tween:
		tween.kill()
	var fx := GameSettings.effects
	var wd: WeaponData = inventory.equipped_weapon if inventory != null else null
	var punch: bool = wd != null and wd.view_model_punch
	var kick_pos: Vector3 = fx.punch_kick_position if punch else fx.view_model_kick_position
	var kick_rot: Vector3 = fx.punch_kick_rotation if punch else fx.view_model_kick_rotation
	var in_time: float = fx.punch_kick_in_time if punch else fx.view_model_kick_in_time
	var out_time: float = fx.punch_kick_out_time if punch else fx.view_model_kick_out_time
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_recoil_pos", kick_pos, in_time)
	tween.tween_property(self, "_recoil_rot", kick_rot, in_time)
	tween.chain().tween_property(self, "_recoil_pos", Vector3.ZERO, out_time)
	tween.chain().tween_property(self, "_recoil_rot", Vector3.ZERO, out_time)
	# Re-resolve the mounted model every time, never cache it: WeaponModelSwapper frees and re-instantiates it
	# on every equip, so a stored ref would be freed the first time you swap weapons.
	if not punch:
		return
	var vm: Node = _swapper.current_model() if _swapper != null else null
	if vm != null and vm.has_method(&"strike"):
		vm.call(&"strike")

func reload() -> void:
	# A holstered weapon must stay parked off-screen (same invariant as land() / _on_ammo_finished_reloading()).
	# reload() is wired to swap_started too, and a swap fired while the draw is LOCKED — carrying a prop — keeps
	# holstered=true (Attack refuses the set_holstered(false)) yet still emits swap_started. Without this guard the
	# swap down-swing tweens _recoil_pos out of the holster park into partial view, and nothing re-parks it (the
	# swap_finished raise now bails while holstered). The real-reload path can't reach here holstered — Attack.reload
	# bails while holstered — so this only bites the refused-draw-during-carry case, exactly the reveal to suppress.
	if attack and attack.holstered:
		return
	if tween:
		tween.kill()
	# Down-and-back "hands are busy" dip; pose + timing are designer knobs on GameSettings.effects.
	var fx := GameSettings.effects
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_recoil_pos", fx.gun_reload_dip_position, fx.gun_reload_dip_time)
	tween.tween_property(self, "_recoil_rot", fx.gun_reload_dip_rotation, fx.gun_reload_dip_time)

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
	# (= gun_holster_position_offset); the landing dip below tweens _recoil_pos back toward zero, which would swing the hidden
	# gun right back into view. Skip the dip entirely while holstered so falling/landing never re-reveals it.
	if attack and attack.holstered:
		return
	if attack and attack.is_reload_or_swap_active():
		return
	# Don't interrupt an active fire/reload/swap tween — a tiny landing from
	# something like a downward shot recoil would otherwise stop those mid-anim.
	if tween and tween.is_running():
		return
	# Dip depth/pitch (per unit of impact) + in/out timing are designer knobs on GameSettings.effects.
	var fx := GameSettings.effects
	var dip: float = fx.gun_land_dip * intensity
	var pitch: float = fx.gun_land_pitch * intensity
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_recoil_pos", Vector3(0.0, dip, 0.0), fx.gun_land_in_time)
	tween.tween_property(self, "_recoil_rot", Vector3(pitch, 0.0, 0.0), fx.gun_land_in_time)
	tween.chain().tween_property(self, "_recoil_pos", Vector3.ZERO, fx.gun_land_out_time)
	tween.chain().tween_property(self, "_recoil_rot", Vector3.ZERO, fx.gun_land_out_time)

func _on_ammo_finished_reloading() -> void:
	# A holstered weapon must stay put away (same invariant as land()): this raise tweens _recoil_pos back to zero,
	# which would swing the gun — parked off-screen via the holster offset — right back into view. It fires on a
	# reload finish (can't happen while holstered — reload() bails) but ALSO on a SWAP finish, and a swap started
	# with the gun out can complete a beat AFTER a holster (the spawn "begin holstered" sets it away mid-raise; a
	# dialogue that opens mid-swap does the same). Skip the raise while holstered so the swap's view-model re-equip
	# in _on_swap_finished still lands, but the pose stays stowed until an explicit unholster() draws it.
	if attack and attack.holstered:
		return
	# The laser-gate window and the raise tween share the ONE designer knob (gun_raise_time, default
	# GUN_RAISE_MS / 1000 — the const stays as the baseline/test anchor), derived the same way
	# unholster() derives its window, so the laser unlocks exactly as the gun settles even after a retune.
	var t: float = GameSettings.effects.gun_raise_time
	_raise_until_msec = Time.get_ticks_msec() + int(t * 1000.0)
	if tween:
		tween.kill()
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_recoil_pos", Vector3.ZERO, t)
	tween.tween_property(self, "_recoil_rot", Vector3.ZERO, t)

## FNV-style put-away: swing the gun down + barrel-down out of view, then hide it once it's offscreen.
func holster() -> void:
	if tween:
		tween.kill()
	var t: float = GameSettings.effects.gun_holster_animation_time
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_recoil_pos", GameSettings.effects.gun_holster_position_offset, t)
	tween.tween_property(self, "_recoil_rot", GameSettings.effects.gun_holster_rotation_offset, t)
	tween.chain().tween_callback(func(): visible = false)

## FNV-style draw: show the gun already lowered, then raise it back into the ready pose. Gates the
## laser sight (via _raise_until_msec) until it has settled, like a reload/swap raise.
func unholster() -> void:
	if tween:
		tween.kill()
	visible = true
	var t: float = GameSettings.effects.gun_holster_animation_time
	_recoil_pos = GameSettings.effects.gun_holster_position_offset
	_recoil_rot = GameSettings.effects.gun_holster_rotation_offset
	_raise_until_msec = Time.get_ticks_msec() + int(t * 1000.0)
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_recoil_pos", Vector3.ZERO, t)
	tween.tween_property(self, "_recoil_rot", Vector3.ZERO, t)

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
