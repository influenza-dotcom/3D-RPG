class_name GunMesh
extends MeshInstance3D

const RIM_LIGHT_SHADER = preload("res://resources/shaders/rim_light.gdshader")

@export var sway_amount: float = 0.02
@export var sway_speed: float = 8.0
@export var player: Character
@export var inventory: Inventory
@export var attack: Attack

@export_group("Readiness Tilt")
# How far the muzzle droops while the weapon can't fire (cooldown/reload/swap).
@export var not_ready_pitch_deg: float = 6.0

@export_group("Motion")
@export var walk_bob_pos: float = 0.004
@export var walk_bob_roll_deg: float = 0.6
@export var strafe_roll_deg: float = 3.0
@export var forward_lag: float = 0.04
@export var vertical_pitch_deg: float = 1.2
@export var max_vertical_pitch_deg: float = 8.0
@export var motion_smooth: float = 10.0

@export_group("Aim Down Sights")
## Where the gun sits while aiming, relative to its resting spot. Aim in-game and nudge this until
## the sights line up with the screen centre.
@export var ads_position: Vector3 = Vector3(-0.03, -0.06, -0.01)
## Extra rotation (degrees) while aiming. Usually leave at zero.
@export var ads_rotation: Vector3 = Vector3.ZERO
## How fast the gun eases in/out of the aim pose.
@export var ads_speed: float = 14.0
## Fraction of the hip-fire sway/bob kept while aiming. 0 = rock steady, 1 = full sway.
@export var ads_sway_mult: float = 0.35

@export_group("Mouse Sway")
@export var mouse_sway_pos: float = 0.04
@export var mouse_sway_roll_deg: float = 0.0
@export var mouse_sway_pitch_deg: float = 0.0
@export var mouse_sway_decay: float = 12.0
@export var mouse_sway_max: float = 0.35

@export_group("Breathing")
@export var breath_pos_amount: float = 0.0035
@export var breath_pitch_deg: float = 0.25
@export var breath_speed: float = 1.6
@export var breath_idle_fade_speed: float = 4.0

@export_group("Rim Light")
@export var rim_color: Color = Color(0.95, 0.88, 0.75)
@export var rim_power: float = 5.0
@export var rim_strength: float = 0.5
@export var rim_top_bias: float = 0.35

var tween: Tween
var base_position: Vector3
var base_rotation: Vector3
var _bob_time: float = 0.0
var _breath_time: float = 0.0
var _breath_t: float = 0.0
var _mouse_sway: Vector2 = Vector2.ZERO
var _aiming: bool = false   ## true while the player holds ADS (driven by ScopeIn.scoped_in)
var _aim_t: float = 0.0     ## eased 0->1 aim-pose blend
var _smoothed_base: Vector3              ## the swayed/aimed rest pose, smoothed
var _smoothed_base_rot: Vector3
var _recoil_pos: Vector3 = Vector3.ZERO  ## fire/reload/land kick, added ON TOP of the rest pose
var _recoil_rot: Vector3 = Vector3.ZERO
var _rim_material: ShaderMaterial
var _weapon_model: Node               ## the equipped weapon's instantiated view-model
var _placeholder_meshes: Dictionary = {} ## stashed built-in rig meshes, so they can be restored
var _muzzle_default_pos: Vector3         ## rig muzzle's resting local position; restored when a weapon has no marker

## The weapon muzzle marker (projectile / raycast origin and muzzle-FX anchor), exposed
## read-only so the host can hand it to the weapon component without reaching through
## this scene's child nodes.
var muzzle: Marker3D:
	get:
		return get_node_or_null("Sketchfab_Scene/Muzzle") as Marker3D

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
	_smoothed_base = base_position
	_smoothed_base_rot = base_rotation
	_disable_shadows_recursive(self)
	_setup_rim_light()
	var sk_muzzle := get_node_or_null("Sketchfab_Scene/Muzzle")
	if sk_muzzle is Node3D:
		_muzzle_default_pos = (sk_muzzle as Node3D).position
	# Deferred so the inventory has equipped its first weapon before we read it.
	_equip_view_model.call_deferred()

func _disable_shadows_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Force every gun mesh onto the gun's render layer (which world decals
		# exclude via cull_mask) so projected decals — e.g. the player's blob
		# shadow when crouching lowers the gun near the floor — don't land on the
		# weapon. The imported model's submeshes default to layer 1 otherwise.
		mi.layers = layers
	for child in node.get_children():
		_disable_shadows_recursive(child)

func _setup_rim_light() -> void:
	_rim_material = ShaderMaterial.new()
	_rim_material.shader = RIM_LIGHT_SHADER
	_rim_material.set_shader_parameter("rim_color", rim_color)
	_rim_material.set_shader_parameter("rim_power", rim_power)
	_rim_material.set_shader_parameter("rim_strength", rim_strength)
	_rim_material.set_shader_parameter("top_bias", rim_top_bias)
	_apply_rim_recursive(self)

func _apply_rim_recursive(node: Node) -> int:
	var n := 0
	if node is MeshInstance3D:
		n += _chain_rim_on_mesh(node as MeshInstance3D)
	for child in node.get_children():
		n += _apply_rim_recursive(child)
	return n

func _chain_rim_on_mesh(mi: MeshInstance3D) -> int:
	if not mi.mesh or not _rim_material:
		return 0
	var applied := 0
	for surface_idx in mi.mesh.get_surface_count():
		var base: Material = mi.get_surface_override_material(surface_idx)
		if not base:
			base = mi.mesh.surface_get_material(surface_idx)
		if not base and mi.material_override:
			base = mi.material_override
		var chained: Material
		if base:
			chained = base.duplicate()
		else:
			chained = StandardMaterial3D.new()
		chained.next_pass = _rim_material
		mi.set_surface_override_material(surface_idx, chained)
		applied += 1
	return applied

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

	# Muzzle FX hang under this gun (Sketchfab_Scene/Muzzle). Give the ones that need
	# the equipped weapon its inventory, and fire them from the Attack signals. Fetched
	# dynamically, hence Callable(node, "method") rather than typed references.
	var muzzle_node := get_node_or_null("Sketchfab_Scene/Muzzle")
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

func _process(delta: float) -> void:
	if !is_instance_valid(player) or !player:
		return

	var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var on_floor := player.is_on_floor()

	var bob_factor := 0.0
	if on_floor and horizontal_speed > GameSettings.player_movement.footstep_min_horizontal_speed:
		_bob_time += delta * GameSettings.camera.bob_speed
		bob_factor = clampf(horizontal_speed / GameSettings.player_movement.max_speed, 0.0, 1.0)
	else:
		_bob_time = lerpf(_bob_time, 0.0, 1.0 - exp(-motion_smooth * delta))

	var bob_x := cos(_bob_time * 0.5) * walk_bob_pos * bob_factor
	var bob_y := sin(_bob_time) * walk_bob_pos * bob_factor
	var bob_roll := sin(_bob_time * 0.5) * walk_bob_roll_deg * bob_factor

	# Breathing: subtle vertical sway + pitch when standing still, fades when moving.
	var idle_target := 0.0 if (horizontal_speed > GameSettings.player_movement.footstep_min_horizontal_speed or not on_floor) else 1.0
	_breath_t = lerpf(_breath_t, idle_target, 1.0 - exp(-breath_idle_fade_speed * delta))
	_breath_time += delta * breath_speed
	var breath_y := sin(_breath_time) * breath_pos_amount * _breath_t
	var breath_pitch := sin(_breath_time * 0.5) * breath_pitch_deg * _breath_t

	_mouse_sway = _mouse_sway.lerp(Vector2.ZERO, 1.0 - exp(-mouse_sway_decay * delta))
	var mouse_off_x := -_mouse_sway.y * mouse_sway_pos
	var mouse_off_y := _mouse_sway.x * mouse_sway_pos
	var mouse_roll := -_mouse_sway.y * mouse_sway_roll_deg
	var mouse_pitch := -_mouse_sway.x * mouse_sway_pitch_deg

	var sway_x = -player.input_dir.x * sway_amount
	var sway_y = player.input_dir.y * sway_amount * 0.5
	var forward_off = -player.input_dir.y * forward_lag

	var roll = player.input_dir.x * strafe_roll_deg
	var pitch := clampf(-player.velocity.y * vertical_pitch_deg, -max_vertical_pitch_deg, max_vertical_pitch_deg)

	# Droop the muzzle while the weapon isn't ready to fire (negative X tilts the
	# barrel down, same convention as reload/land). Eased by the motion lerp below.
	var ready_pitch := -not_ready_pitch_deg if (attack and not attack.can_fire()) else 0.0

	# Aim-down-sights: ease the rest pose toward the centred aim pose, and damp the sway while
	# aiming so the gun holds steady on target.
	_aim_t = lerpf(_aim_t, 1.0 if _aiming else 0.0, 1.0 - exp(-ads_speed * delta))
	var marker := aim_pos_marker
	var aim_target: Vector3 = marker.position if marker else ads_position
	var aim_pos := base_position.lerp(aim_target, _aim_t)
	var aim_rot := base_rotation.lerp(base_rotation + ads_rotation, _aim_t)
	var sway_damp := lerpf(1.0, ads_sway_mult, _aim_t)

	var target_pos := aim_pos + Vector3(sway_x + bob_x + mouse_off_x, sway_y + bob_y + breath_y + mouse_off_y, forward_off) * sway_damp
	var target_rot := aim_rot + Vector3(pitch + mouse_pitch + breath_pitch + ready_pitch, 0.0, roll + bob_roll + mouse_roll) * sway_damp

	var t := 1.0 - exp(-motion_smooth * delta)
	# Smooth the swayed/aimed rest pose, then add the recoil kick ON TOP — so fire/reload/land kicks
	# are relative to wherever the gun is now (hip OR ADS-centred) instead of snapping to the hip.
	_smoothed_base = _smoothed_base.lerp(target_pos, t)
	_smoothed_base_rot = _smoothed_base_rot.lerp(target_rot, t)
	position = _smoothed_base + _recoil_pos
	rotation_degrees = _smoothed_base_rot + _recoil_rot

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
	if tween:
		tween.kill()
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_recoil_pos", Vector3.ZERO, 0.5)
	tween.tween_property(self, "_recoil_rot", Vector3.ZERO, 0.5)

func _on_swap_finished() -> void:
	_equip_view_model()
	_on_ammo_finished_reloading()

func _on_mouse_input_rotate(amt: Vector2) -> void:
	_mouse_sway = (_mouse_sway + amt).limit_length(mouse_sway_max)

func _on_aim_changed(tf: bool) -> void:
	_aiming = tf

## Show the equipped weapon's own view-model. Instantiates its view_model scene under the rig
## (freeing the previous one) so each weapon has its own mesh + material, and hides the rig's
## built-in placeholder gun. A weapon with no view_model falls back to that placeholder, so
## unassigned weapons still show something.
func _equip_view_model() -> void:
	if not inventory or not inventory.equipped_weapon:
		return
	if is_instance_valid(_weapon_model):
		_weapon_model.queue_free()
		_weapon_model = null
	var scene: PackedScene = inventory.equipped_weapon.view_model
	if scene:
		_weapon_model = scene.instantiate()
		add_child(_weapon_model)
		_disable_shadows_recursive(_weapon_model)
		_apply_rim_recursive(_weapon_model)
		_align_muzzle_to(_weapon_model)
		_set_placeholder_hidden(true)
	else:
		# Placeholder weapon (no view_model): still reset the rig muzzle so it doesn't keep the
		# previous weapon's marker spot.
		_align_muzzle_to(null)
		_set_placeholder_hidden(false)

## Hide/restore the rig's built-in placeholder gun (Sketchfab_Scene) by stashing/restoring each of
## its meshes — NOT toggling visibility, because the Muzzle + FX are parented under it and would
## vanish too. The Muzzle subtree is skipped entirely.
func _set_placeholder_hidden(hidden: bool) -> void:
	var sk := get_node_or_null("Sketchfab_Scene")
	var muzzle_node := get_node_or_null("Sketchfab_Scene/Muzzle")
	if sk and muzzle_node:
		_toggle_placeholder_meshes(sk, muzzle_node, hidden)

func _toggle_placeholder_meshes(node: Node, muzzle_node: Node, hidden: bool) -> void:
	if node == muzzle_node:
		return  # never touch the Muzzle + its FX
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if hidden:
			if mi.mesh:
				_placeholder_meshes[mi] = mi.mesh
				mi.mesh = null
		elif _placeholder_meshes.has(mi):
			mi.mesh = _placeholder_meshes[mi]
	for c in node.get_children():
		_toggle_placeholder_meshes(c, muzzle_node, hidden)

## If the equipped view-model contains a node named "Muzzle", snap the rig's muzzle (and the flash /
## sparks / shell / whiz FX parented under it) onto that point — so each weapon defines its own
## muzzle position right in its own model scene. Position only; the FX keep their forward facing.
func _align_muzzle_to(view_model: Node) -> void:
	var rig_muzzle := get_node_or_null("Sketchfab_Scene/Muzzle")
	if not (rig_muzzle is Node3D):
		return
	var vm_muzzle: Node3D = _find_muzzle_marker(view_model) if view_model else null
	if vm_muzzle is Node3D:
		# Weapon defines its own muzzle point — snap the rig muzzle to it.
		(rig_muzzle as Node3D).global_position = (vm_muzzle as Node3D).global_position
	else:
		# No per-weapon marker — restore the rig's default muzzle spot (the original behaviour).
		(rig_muzzle as Node3D).position = _muzzle_default_pos

## Find a muzzle marker anywhere under the view-model, case-insensitively — so "Muzzle", "muzzle",
## etc. all work and the exact capitalisation of the node name doesn't matter.
## Find a named marker (case-insensitive) on the currently-equipped view-model — the per-weapon
## anchor points the laser sight reads. null if there's no view-model or no such marker.
func equipped_marker(lower_name: String) -> Node3D:
	if not is_instance_valid(_weapon_model):
		return null
	return _find_named_marker(_weapon_model, lower_name)

## Find a marker by (lower-cased) name anywhere under a node, case-insensitively.
func _find_named_marker(node: Node, lower_name: String) -> Node3D:
	for c in node.get_children():
		if c is Node3D and str(c.name).to_lower() == lower_name:
			return c as Node3D
		var nested := _find_named_marker(c, lower_name)
		if nested:
			return nested
	return null

func _find_muzzle_marker(node: Node) -> Node3D:
	for c in node.get_children():
		if c is Node3D and str(c.name).to_lower() == "muzzle":
			return c as Node3D
		var nested := _find_muzzle_marker(c)
		if nested:
			return nested
	return null
