@tool
class_name BodyModelSwap
extends Node3D

const ModelResourceUtil = preload("res://scripts/components/model_resource.gd")
## Planar-projection shader for the player-DRAWN t-shirt (see body_texture_planar): the shipped torso's UV atlas
## would shred a drawing, so drawn shirts project flat onto the chest instead of sampling the mesh UVs.
const ShirtPlanarShader := preload("res://resources/shaders/shirt_planar.gdshader")
## Backs the apply_*_part PICK dropdowns below: a folder scan of res://resources/parts/<slot>/ that turns
## "change this NPC's head" from a file-explorer drag + three hand-dialled numbers into choosing a name.
const PartLibrary := preload("res://scripts/components/part_library.gd")

## Seated ground-snap probe plumbing (see seated_snap_to_ground). Mask: layer 1 = the WORLD (brush geometry,
## StaticBody props/chairs); deliberately excludes layer 2 characters so a seated NPC never "sits on" a body
## walking under it. Re-probe distance: how far the host must move before the cached probe refreshes (covers
## spawn gravity-settling / a pool-reuse teleport). The probe's DEPTH is the seated_max_snap_depth export.
const SEATED_PROBE_MASK := 1
const SEATED_REPROBE_DISTANCE := 0.02

## Drop-in CUSTOM CHARACTER swap with a LIVE EDITOR PREVIEW. Set body_model + head_model to your .glb files and
## they appear as the NPC's body + head RIGHT IN THE EDITOR (@tool) -- both at FULL SCALE
## in the SAME frame (under this node), so you tune their size / position / rotation and watch the head sit on the
## torso in real time, no playtest. This node IS the visible body: the shipped enemy.tscn no longer carries a
## default Man.glb "Body" node (removed as a vestigial hidden placeholder), so the enemy root's `mesh` export
## points HERE and the damage-flash + combat outline walk these swapped parts. If a base body node IS present
## (a "Body" sibling, or a wired `default_body`), its meshes are hidden behind the swap. At runtime the NPC's
## head-look + sniper glint retarget to the swapped head.
##
## SETUP: drop it under the NPC (the Enemy root). Set body_model (+ optionally head_model). Dial *_scale /
## *_position / *_rotation until it lines up. The same node does the swap at runtime, so what you see in the
## editor is what ships.

# --- Body --------------------------------------------------------------------------------------------------------
## Tick this any time the editor preview looks stale (after a .glb reimport or a script reload) to force a rebuild.
@export var refresh_preview: bool = false:
	set(value):
		refresh_preview = false  # momentary: snaps back so it always re-triggers
		_rebuild()
## PICK a seated BODY by name from res://resources/parts/bodies/ instead of dragging a model in. A MOMENTARY
## action, not stored state: choosing an id STAMPS that part's model + scale + position + rotation + texture into
## the body_model_* fields below and snaps this row back to empty. Everything stays hand-editable afterwards, the
## id is NOT remembered, and nothing new resolves at runtime -- the .tscn keeps the plain model reference it
## always had. A whole_body part also clears the composed head/arm/leg models, and any body pick clears
## body_texture_planar (that projection is for a player-DRAWN shirt only).
## NO UNDO: the previous values are PRINTED to the Output panel before they are overwritten -- copy them back if
## you mis-pick. If the host NPC has a `look` that sets this part's model, the LOOK WINS: pick on the look instead.
@export var apply_body_part: String = "":
	set(value):
		apply_body_part = ""  # momentary: snaps back so re-picking the SAME part re-stamps
		if PartLibrary.stamp(self, PartLibrary.HOST_SWAP, PartLibrary.SLOT_BODIES, value):
			notify_property_list_changed()  # the stamp moved five other rows -- make the inspector re-read them
@export var body_model: Resource:
	set(value):
		body_model = value
		_rebuild()
## Uniform scale of the swapped body -- it spawns at FULL scale (not the Man.glb Body's 0.335), so start near 1.0.
@export var body_model_scale: float = 1.0:
	set(value):
		body_model_scale = value
		_apply_body_transform()
## Local position of the body under this node -- nudge Y so the feet meet the ground.
@export var body_model_position: Vector3 = Vector3.ZERO:
	set(value):
		body_model_position = value
		_apply_body_transform()
## Rotation (degrees, per axis) of the body -- yaw to face the NPC's +Z forward; pitch/roll if it came in tipped.
@export var body_model_rotation: Vector3 = Vector3.ZERO:
	set(value):
		body_model_rotation = value
		_apply_body_transform()
## Optional texture to skin the body with (applied as an albedo material override over ALL its meshes). Null -> keep the model's own baked material.
@export var body_texture: Texture2D:
	set(value):
		body_texture = value
		_apply_body_texture()
## PLANAR mode for body_texture: project it flat onto the torso (chest print) instead of sampling the mesh's own
## UVs. Made for the character creator's player-DRAWN shirt — the shipped torso carries a Blender atlas unwrap that
## scatters a drawing into unreadable scraps, so configure_swap turns this ON exactly when a custom shirt is set
## (and OFF for authored/baked textures, which are painted FOR that atlas and must keep the mesh UVs).
@export var body_texture_planar: bool = false:
	set(value):
		body_texture_planar = value
		_apply_body_texture()
## Flat colour for the body (tints body_texture if one's set, else a solid skin). Leave it WHITE for no override; pick any other colour to tint.
@export var body_color: Color = Color(1, 1, 1, 1):
	set(value):
		body_color = value
		_apply_body_texture()
## See-through amount for the BODY part only (0 = solid, 1 = invisible), rendered as a DITHERED screen-door
## (alpha-hash — depth-writes stay on, no transparency sorting, and it reads as the retro stipple) rather than
## smooth alpha blending. The player's first-person torso drives this (its resting see-through + the crouch
## fade-out); NPCs leave it 0 and take a zero-cost early-out. Applied over WHATEVER material path the body
## took — the _skin override or the model's own baked surface materials — via per-instance duplicates, so the
## shared originals (other NPCs, icon bakes) are never mutated.
@export_range(0.0, 1.0, 0.01) var body_transparency: float = 0.0:
	set(value):
		body_transparency = value
		_apply_body_transparency()
		_apply_outline_uniforms()  # the actor rim dissolves WITH the chest it wraps — see _outline_color_for

# --- Head (sits on the torso; the head-look tracks it) -----------------------------------------------------------
## PICK a seated HEAD by name from res://resources/parts/heads/ -- the fastest way to change an NPC's face. See
## apply_body_part above for the full contract (momentary, stamps model + seat, no undo, a look wins). Every head
## model has its OWN native size / origin / facing, which is exactly why picking beats dragging: the shipped four
## seat at scale 0.205 / 0.4183 / 0.1199 / 0.2436 with OPPOSING yaws, and the part file carries the fitted numbers.
@export var apply_head_part: String = "":
	set(value):
		apply_head_part = ""  # momentary: snaps back so re-picking the SAME part re-stamps
		if PartLibrary.stamp(self, PartLibrary.HOST_SWAP, PartLibrary.SLOT_HEADS, value):
			notify_property_list_changed()
@export var head_model: Resource:
	set(value):
		head_model = value
		_rebuild()
## Uniform scale of the swapped head -- size it to the torso.
@export var head_scale: float = 1.0:
	set(value):
		head_scale = value
		_apply_head_transform()
## Local position of the head under this node -- raise Y to sit it on the neck of the torso.
@export var head_position: Vector3 = Vector3.ZERO:
	set(value):
		head_position = value
		_apply_head_transform()
## Rotation (degrees) of the head's REST pose -- face it forward; the head-look adds its look-rotation on top.
@export var head_rotation: Vector3 = Vector3.ZERO:
	set(value):
		head_rotation = value
		_apply_head_transform()
## Optional texture to skin the head with (albedo material override over its meshes). Null -> keep the model's own material.
@export var head_texture: Texture2D:
	set(value):
		head_texture = value
		_apply_head_texture()
## Flat colour for the head (tints head_texture if set, else a solid skin). WHITE = no override; pick any other colour to tint.
@export var head_color: Color = Color(1, 1, 1, 1):
	set(value):
		head_color = value
		_apply_head_texture()

# --- Arms (a PAIR from one model: placed as the LEFT arm, mirrored across the body centre for the RIGHT) ----------
## PICK a seated ARM pair by name from res://resources/parts/arms/ -- same contract as apply_body_part above.
@export var apply_arm_part: String = "":
	set(value):
		apply_arm_part = ""  # momentary: snaps back so re-picking the SAME part re-stamps
		if PartLibrary.stamp(self, PartLibrary.HOST_SWAP, PartLibrary.SLOT_ARMS, value):
			notify_property_list_changed()
@export var arm_model: Resource:
	set(value):
		arm_model = value
		_rebuild()
## Uniform scale of each arm.
@export var arm_scale: float = 1.0:
	set(value):
		arm_scale = value
		_apply_arm_transform()
## Local position of the LEFT arm (its shoulder); the RIGHT arm is mirrored across X automatically. Set X to one side of the torso.
@export var arm_position: Vector3 = Vector3.ZERO:
	set(value):
		arm_position = value
		_apply_arm_transform()
## Rotation (degrees) of the LEFT arm; the RIGHT arm's rotation is mirrored to match.
@export var arm_rotation: Vector3 = Vector3.ZERO:
	set(value):
		arm_rotation = value
		_apply_arm_transform()
## Optional texture to skin both arms with (albedo override). Null -> keep the model's own material.
@export var arm_texture: Texture2D:
	set(value):
		arm_texture = value
		_apply_arm_texture()
## Flat colour for both arms (tints arm_texture if set, else a solid skin). WHITE = no override; pick any other colour to tint.
@export var arm_color: Color = Color(1, 1, 1, 1):
	set(value):
		arm_color = value
		_apply_arm_texture()
## See-through amount for the ARMS only (0 = solid, 1 = invisible) — the exact same dithered screen-door
## body_transparency gives the torso, on the same per-instance-duplicate machinery. Its reason for existing is
## the player's first-person BODY arms: they hang off the FP torso, so they must dissolve WITH it (the look-down
## fade, the crouch hide) or a vanished chest leaves disembodied arms floating under the camera. NPCs leave it 0
## and take the same zero-cost early-out body_transparency does, so no existing rig changes.
@export_range(0.0, 1.0, 0.01) var arm_transparency: float = 0.0:
	set(value):
		arm_transparency = value
		_apply_arm_transparency()
		_apply_outline_uniforms()  # ...and so does the arms' — same reason, their own curve
## Build only the LEFT arm (skip the mirrored right) -- for a first-person view-model arm, where you see one hand on the weapon.
@export var single_arm: bool = false:
	set(value):
		single_arm = value
		_rebuild()
## Render-layer bitmask to force ALL spawned meshes onto (0 = leave them on their own layer). Set it to the view-model
## layer (4) for a first-person part so it draws in the gun's dedicated camera pass -- over the world, no clipping.
@export var view_model_layer: int = 0:
	set(value):
		view_model_layer = value
		_apply_view_model_layer()

# --- Legs (a PAIR from one model, mirrored across the body centre like the arms; they swing with the gait) --------
## PICK a seated LEG pair by name from res://resources/parts/legs/ -- same contract as apply_body_part above.
@export var apply_leg_part: String = "":
	set(value):
		apply_leg_part = ""  # momentary: snaps back so re-picking the SAME part re-stamps
		if PartLibrary.stamp(self, PartLibrary.HOST_SWAP, PartLibrary.SLOT_LEGS, value):
			notify_property_list_changed()
@export var leg_model: Resource:
	set(value):
		leg_model = value
		_rebuild()
## Uniform scale of each leg.
@export var leg_scale: float = 1.0:
	set(value):
		leg_scale = value
		_apply_leg_transform()
## Local position of the LEFT leg (its hip); the RIGHT leg is mirrored across X automatically. Set X to one side of the torso, lower Y to the hip.
@export var leg_position: Vector3 = Vector3.ZERO:
	set(value):
		leg_position = value
		_apply_leg_transform()
## Rotation (degrees) of the LEFT leg; the RIGHT leg's rotation is mirrored to match.
@export var leg_rotation: Vector3 = Vector3.ZERO:
	set(value):
		leg_rotation = value
		_apply_leg_transform()
## Optional texture to skin both legs with (albedo override). Null -> keep the model's own material.
@export var leg_texture: Texture2D:
	set(value):
		leg_texture = value
		_apply_leg_texture()
## Flat colour for both legs (tints leg_texture if set, else a solid skin). WHITE = no override; pick any other colour to tint.
@export var leg_color: Color = Color(1, 1, 1, 1):
	set(value):
		leg_color = value
		_apply_leg_texture()
## See-through amount for the LEGS only (0 = solid, 1 = invisible) — the third sibling of body_transparency /
## arm_transparency, on the same dithered screen-door machinery and the same zero-cost early-out.
##
## ⭐It exists because the legs were the one part of the player's first-person body with NO way to get out of the
## view. The chest and arms already dissolved on look-down and crouch; the legs did neither, so anything that
## drops the camera toward them — a crouch (0.61 m), a stair step-smooth (up to 0.7 m), a landing dip (up to
## 1.0 m) — put your own thighs on screen with nothing able to hide them. NPCs leave it 0 and change nothing.
@export_range(0.0, 1.0, 0.01) var leg_transparency: float = 0.0:
	set(value):
		leg_transparency = value
		_apply_leg_transparency()
		_apply_outline_uniforms()  # ...and the legs' rim dissolves with them, like the chest's and the arms'
## Whether the swapped meshes CAST SHADOWS. Default true (NPCs cast normal shadows). Set false for the Player's
## FIRST-PERSON legs — a shadow cast from under the camera looks wrong. Applied to every spawned mesh on each rebuild.
@export var casts_shadow: bool = true:
	set(value):
		casts_shadow = value
		_apply_cast_shadow()

# --- Actor rim (the inverted-hull outline + its ink-mask registration, which are ONE thing) ------------------------
## Wear the ACTOR RIM: the inverted-hull outline every NPC, prop and view model in this game wears, stamped as
## material_overlay on every spawned part — AND, inseparably, register those meshes with InkOutline's actor mask so
## the world's screen-space ink pass SKIPS them. The two halves are one contract, not two features: a hull with no
## mask draws BOTH lines (the doubled outline the whole ink system exists to prevent), and a mask with no hull
## draws none at all. See scripts/effects/ink_outline.gd — "hull owns actors, ink owns the world".
##
## Applied on every rebuild beside casts_shadow / view_model_layer, and that placement IS the point: this rig RESETS
## the `layers` of the meshes it spawns, so a swap dressed from OUTSIDE strands its next set of parts inked with no
## error anywhere (the trap NpcOutline.apply_part_overlays exists to work around).
##
## OFF by default because on an NPC the rim is not ours to own — NpcOutline builds a DISPOSITION-coloured one
## (hostile red / friendly green) into this same material_overlay slot and the two would fight over it. This switch
## is for a rig nobody else dresses: the player's own first-person body, which hangs off a bare BodyModelSwap with
## no Character `mesh` walk to ride.
@export var actor_outline: bool = false:
	set(value):
		actor_outline = value
		_apply_actor_outline()
## Colour of that rim. BLACK is the house look, shared with NPC.outline_color, Throwable.OUTLINE_HIDDEN_COLOR and
## GunVisuals. Its ALPHA is DRIVEN rather than authored: the rim fades with body_transparency / arm_transparency
## (see _outline_color_for) so a dissolving chest can never leave a solid black silhouette of itself hanging.
@export var actor_outline_color: Color = Color(0.0, 0.0, 0.0, 1.0):
	set(value):
		actor_outline_color = value
		_apply_outline_uniforms()
## Rim thickness, fed to the outline shader's `outline_width` uniform (which scales it x4 in clip space). 2.0 is
## NPC parity (NPC.outline_width) — match it for anything drawn at real world depth.
@export var actor_outline_width: float = 2.0:
	set(value):
		actor_outline_width = value
		_apply_outline_uniforms()

# --- Arm + leg animation (RUNTIME only -- the editor shows the static rest pose for placement) --------------------
## Animate the arms in-game: swing while walking unarmed, raise to hold a drawn weapon, rest by the side otherwise. Off -> arms stay at their static rest pose.
@export var animate_arms: bool = true
## How far (degrees) the arms swing forward/back while walking unarmed. Left + right swing OPPOSITE (the mirror handles it) -- Minecraft-style.
@export var arm_swing_amplitude: float = 35.0
## How fast the arms swing while walking.
@export var arm_swing_rate: float = 9.0
## Pitch (degrees) the arms raise to when the NPC has a weapon drawn (holding it forward). Flip the sign if your arm model points the wrong way.
@export var arm_hold_pitch: float = -65.0
## Hold the weapon in a two-handed READY stance the WHOLE time it's DRAWN — the natural "armed enemy" look. On
## (default) a hostile that keeps its gun permanently out has both hands ON the gun, instead of letting the arms
## hang at its sides while the weapon floats at the hand anchor (the disconnected look this fixes). Stealth-safe:
## the hold pose is symmetric and points the gun along the TORSO, whose facing is perception-gated (GOAP) — so
## hands-on-the-gun never means "aiming at a player it hasn't seen"; the honest "I noticed you" tells stay the
## torso swivel + head-look. Turn it OFF for the wary/stealth telegraph instead: the gun stays drawn but the arms
## hang LOW until the foe is within arm_raise_range AND the NPC has actually SENSED it (has_sensed_foe), so the arms
## coming UP is itself the tell. Ignored by a host with no is_holding_gun() (a non-NPC rig — arms never hold).
@export var arms_hold_when_drawn: bool = true
## Only used when arms_hold_when_drawn is OFF. How close (m) the foe must be before the NPC raises its weapon into
## the hold pose. Farther than this it keeps a weapon DRAWN but its arms DOWN (hanging / walk-swing) — so an enemy
## only "takes aim" when you get close, not the instant it draws across the map. Purely cosmetic: it never changes
## when the NPC actually fires. 0 -> raised the moment the gun is out. Read off the host's aim_distance(); no target
## -> arms stay down. The arms ALSO only come up once the host has genuinely SENSED the foe (has_sensed_foe(),
## Perception past UNAWARE) — so a predisposed-hostile enemy doesn't aim at a player it hasn't actually seen
## (through a wall / in the dark). A host lacking has_sensed_foe() (a non-NPC rig) keeps the proximity-only behaviour.
@export var arm_raise_range: float = 10.0
## Pitch (degrees) the arms hold FORWARD when the NPC is squared up to fight UNARMED (fists out) — held up so a fist enemy reads as armed-with-fists, with a gentle ALTERNATING sway on top (arm_fists_*_sway) instead of the normal walk swing. Driven by the host's is_fists_out(); drops back to the side when it's not fighting. Flip the sign if your arm model points the wrong way.
@export var arm_fists_pitch: float = -75.0
## Degrees the fists-out arms gently sway (arms ALTERNATE — one forward, one back) while STANDING — a small idle motion so the squared-up reach isn't frozen. 0 = perfectly still.
@export var arm_fists_idle_sway: float = 5.0
## Degrees the fists-out arms sway while WALKING — bigger than the idle sway, so the arms swing more as it advances on you.
@export var arm_fists_walk_sway: float = 16.0
## Cadence of the fists-out IDLE sway. Walking uses the normal arm_swing_rate so the sway locks to the gait.
@export var arm_fists_idle_rate: float = 3.5
## Planar speed (m/s) above which the NPC counts as walking. The arms + legs share this ONE gait threshold (and arm_swing_rate as the cadence) so they stay locked into a single walk cycle.
@export var arm_move_threshold: float = 0.4
## Animate the LEGS: swing them with the walk cycle whether or not a weapon is drawn (the legs always carry the body). Off -> legs stay at their static rest pose.
@export var animate_legs: bool = true
## How far (degrees) the legs swing forward/back while walking. They swing OPPOSITE each other AND opposite the same-side arm -- a natural contralateral (Minecraft) gait.
@export var leg_swing_amplitude: float = 28.0
## How much WIDER + FASTER the legs kick in the AIR vs the ground walk -- their mid-air FLAIL (a frantic bicycle kick). 1 = same as walking; higher = more frantic.
@export var leg_air_flail_scale: float = 1.8
## Drive the legs off ACTUAL VELOCITY instead of the NPC mid-air flail. Off (NPC default): legs do the wide bicycle
## flail while airborne. On (the Player's FP legs): the legs run their normal speed-gated walk gait on the ground
## AND in the air, so they track your real movement -- still when you're not moving horizontally, striding when you
## are -- instead of thrashing.
@export var velocity_driven_legs: bool = false
## With velocity_driven_legs on, the speed (m/s) at which the legs cycle at their base cadence (arm_swing_rate).
## Below it the stride slows; above it (bhop / dash) it quickens — so the walk-cycle SPEED tracks how fast you move.
## Set near the host's run speed.
@export var velocity_leg_ref_speed: float = 5.0
## Steer the LEGS to face the direction the NPC is actually MOVING, independent of the torso (which keeps facing
## its aim/look). So an enemy strafing or backpedalling around you has its hips pointed along its path while its
## chest stays trained on you — a natural run-and-gun. Off -> legs stay square with the torso (the old behaviour).
@export var legs_follow_movement: bool = true
## How fast (higher = snappier) the legs swivel toward the movement direction. Lower = a lazier, sliding turn.
@export var leg_turn_rate: float = 9.0
## When the character STOPS, swivel the legs back SQUARE with the torso — an NPC's idle combat stance, feet under
## the hips facing its aim (the shipped NPC default). Off -> the legs HOLD their last movement facing: the feet
## stay pointed where you were actually going instead of snapping back to face the torso/camera. That's what the
## Player's first-person legs want (stopping after a strafe shouldn't rotate the feet to camera-forward). Only has
## any effect with legs_follow_movement on.
@export var legs_square_when_idle: bool = true
## Pitch (degrees) the arms snap to when AIRBORNE and not holding a gun -- both straight up, roller-coaster / Roblox style. Tune to point your arm model overhead (more negative usually raises them further back).
@export var arm_air_pitch: float = -160.0
## Pitch (degrees) the arms FLAIL up to on a fist strike (NPC._punch), on top of the by-side rest pose, then ease back down. Set so the arms swing up and over toward the target.
@export var arm_strike_pitch: float = -120.0
## Seconds the fist-strike flail takes to rise and settle back to the side. ~1s reads as "wind up and strike".
@export var arm_strike_duration: float = 1.0
## Amplitude shape over the strike's ELAPSED fraction: x 0 = the instant of the punch, x 1 = fully recovered;
## y = how much of arm_strike_pitch / arm_strike_thrust to apply. NULL (default) = the legacy snap-to-full
## then ease-out, which is what every NPC punch uses -- note that means FULL amplitude on frame one, i.e. a
## follow-through with no wind-up. Author a curve for a real punch: dip y BELOW zero near x 0 for the
## anticipation pull-back, spike to 1 for the snap out, then fall to 0 for the recovery. Because the curve is
## sampled on the elapsed FRACTION, one curve re-times itself when arm_strike_duration changes.
@export var arm_strike_curve: Curve = null
## Extra local translation at full amplitude, in the same space and units as arm_position (the right arm's
## copy is mirrored across X automatically, so a forward/up thrust stays forward/up). ZERO (default) = the
## NPC's rotation-only flail; give it a forward value to turn the strike into a JAB that actually extends.
@export var arm_strike_thrust: Vector3 = Vector3.ZERO
## Alternate which fist LEADS on each strike() -- left, right, left. False (default) = both arms flail
## together, the two-fisted NPC swing.
@export var arm_strike_alternate: bool = false
## Amplitude multiplier for the NON-leading arm. 1.0 (default) = both arms move identically (the NPC flail);
## 0 = a single fist punches while the other holds still, which is what reads as a jab rather than a shove.
@export var arm_strike_offhand_scale: float = 1.0
## Live ANTISYMMETRIC stride for the arm pair (degrees of pitch: the LEFT arm gets +this, the RIGHT gets
## MINUS this) — the walking arm-pump for the player's first-person fists rig. Host-driven per frame (the
## Player eases it from its own _process — the arm_scale ordering idiom, so a mid-punch frame is still
## re-posed by the strike path afterwards); NPCs leave it 0. Composed into BOTH the rest re-apply and the
## strike path, so punching mid-walk neither pops the stride off nor doubles it.
@export var arm_stride_deg: float = 0.0:
	set(value):
		arm_stride_deg = value
		_apply_arm_transform()

# --- Sitting pose (host-driven; NPC.sitting toggles it) ---------------------------------------------------------
## Visual offset applied to the body/head/limbs while the host reports is_sitting(). The Y here is only the LAST
## resort — the drop is normally derived from the seat plane under the host (the runtime ground probe, or in the
## editor the host's own capsule bottom; see _seat_plane_y), so the seat height always matches the actual ground.
## It is used only by a host with NO capsule and no probe hit — chiefly an off-tree unit-test rig. X/Z always
## apply as authored.
@export var seated_visual_offset: Vector3 = Vector3(0.0, -0.28, 0.04):
	set(value):
		seated_visual_offset = value
		_apply_posture_transforms()
## RUNTIME ground-snap for the seated pose: probe straight DOWN from the host and drop the seated visual so the
## hips land flush ON whatever surface is below — the floor for a ground-sitter, the seat for an NPC parked on a
## chair — instead of trusting the fixed seated_visual_offset.y (which only fits one seat height). The probe
## re-runs only after the host actually moves (spawn gravity-settling, a pool-reuse teleport), so a parked sitter
## costs a distance check per physics tick, not a ray. Turning it OFF (or a probe MISS, or the editor, where
## there is no stepped physics to ray) falls back to the host's CAPSULE BOTTOM, which is the same plane for any
## settled character — so the seated pose is placed sanely either way. NOTE the seat must be a real LAYER-1
## collider the capsule can stand on — a decorative colliderless chair drops the capsule (and so both estimates)
## through to the floor.
@export var seated_snap_to_ground: bool = true
## How far (m) below the host origin the ground probe reaches — the ray length, so it is ALSO the plausibility
## gate: a surface deeper than this cannot be the seat. The origin rests ~1 m over the capsule bottom on the
## shipped rig, so ~1.2 accepts any settled support with margin, while a sitter whose origin overhangs a ledge
## REJECTS the cliff-bottom hit (and keeps the authored offset) instead of rendering the pose into the drop.
@export var seated_max_snap_depth: float = 1.2
## Height (m) the LEG HIP (leg_position) rests above the seat plane. The hip joint is the legs' centreline, so
## this is roughly half the leg's thickness — trim it until the outstretched legs and the torso's butt visibly
## rest ON the surface instead of floating over or sinking through it. Judge it in the VIEWPORT: the editor
## preview resolves the same seat plane off the host capsule, so it shows the in-game drop.
@export var seated_hip_clearance: float = 0.06
## Minimum height (m) the seated HANDS keep above the seat plane. The seated arm pitch auto-RAISES past
## seated_arm_pitch (never lowers) until the arm's measured reach clears the surface by this much — so the hands
## come to rest on the lap instead of hanging through the floor a ground-level seat would otherwise put them in.
## The editor preview clamps too (the seat plane falls back to the host CAPSULE BOTTOM when there's no runtime
## probe — see _seat_plane_y), so the viewport pose is the pose you get.
@export var seated_hand_clearance: float = 0.05
## Torso pitch (degrees) while seated: a sagittal lean PRE-multiplied about swap-space X (the _leg_pose idiom), so
## it stays a lean whatever yaw the body model is authored with. POSITIVE tips the torso toward the rig's +Z
## front; a slight forward lean keeps the pose from reading as a sunken standing rig.
@export var seated_body_pitch: float = 8.0:
	set(value):
		seated_body_pitch = value
		_apply_posture_transforms()
## Arm pitch (degrees) while seated and idle — the PREFERRED pose, and a FLOOR, not the runtime truth: the clamp's
## available room is constant BY CONSTRUCTION (the seat plane pins the shoulder a fixed height above it:
## arm_position.y - leg_position.y + seated_hip_clearance - seated_hand_clearance), so a sitter's arms always
## settle at acos(room / (reach * arm_scale)) from vertical — ~55° hands-on-lap on the shipped rig — and values
## authored SHALLOWER than that only ever show when the seat plane can't be resolved at all. Author STEEPER than
## the clamp floor to actually change the pose. IDLE ONLY: a seated NPC holding a DRAWN gun uses arm_hold_pitch
## instead (same gates as standing — see _seated_preferred_arm_pitch), so its hands stay on the weapon.
@export var seated_arm_pitch: float = -25.0:
	set(value):
		seated_arm_pitch = value
		_apply_posture_transforms()
## Leg pitch (degrees) while seated and idle. NEGATIVE swings the legs forward out in front of the seat (the swing
## rotates a down-hanging limb about swap-space X, so negative = toward the rig's +Z front — the same
## negative-is-forward convention as the arm pitches); positive folds them backward through the seat.
## -90 = a right angle at the hip: the legs sit straight out, flush/level with the seat.
@export var seated_leg_pitch: float = -90.0:
	set(value):
		seated_leg_pitch = value
		_apply_posture_transforms()
## Hide the host's blob-shadow "Shadow" Decal while seated: the seated visual drops away from the host capsule
## the Decal is authored around, so a chair-sitter's blob reads as a detached puddle and a ground-snapped floor-
## sitter would wear a blob sized/placed for the STANDING silhouette. Untick it if your floor-sitter looks better
## keeping one. Resolved null-safe from a host child named "Shadow" (the Player.tscn / enemy.tscn idiom) — a host
## without one just skips it.
@export var seated_hide_shadow: bool = true

# --- Breathing (RUNTIME only) — a subtle, slow CHEST rise/fall on the torso, Deus Ex idle style -----------------
## Breathe: scale the BODY (torso only — head/arms/legs are separate) up and down on a slow sine so a standing
## NPC looks alive. Off -> the torso holds its static scale.
@export var breathe: bool = true
## Peak scale delta of the breath [fraction]: 0.03 = the chest swells ~3% at the top of the inhale. Keep it small.
@export var breathe_amount: float = 0.03
## Breaths per ~6.3s of phase (a sine rate): ~1.6 ≈ one calm breath every ~4s. Lower = slower, heavier breathing.
@export var breathe_rate: float = 1.6

# --- Talking (dialogue) — head bob + a Tomodachi-style mouth, active ONLY on the NPC you're talking to ----------
## Bob the head up/down while THIS NPC is delivering a dialogue line (it's the one you're talking to). Heads read
## as too static otherwise. Needs a head node (a head_model swapped in). Off -> static head.
@export var talk_head_bob: bool = true
## Height (m) of the talking head bob.
@export var talk_bob_height: float = 0.03
## Head bobs per ~6.3s (a sine rate) while talking — higher = a chattier, more animated nod.
@export var talk_bob_rate: float = 9.0
## How fast the bob eases in/out as the NPC starts/stops delivering a line.
@export var talk_bob_ease: float = 8.0
## Show a Tomodachi-style MOUTH (a black line that flaps open into a black circle, over and over) on the face
## while this NPC is speaking a line or a bark; it hides between utterances. A billboard, so it always faces the
## camera (never oriented away). Needs a head node (a head_model swap). Off -> no mouth.
@export var show_mouth: bool = true
## Radius (m) of the mouth circle at full open. The mouth rides the head, so it scales with the head.
@export var mouth_size: float = 0.06
## Mouth position in HEAD-LOCAL space (+Z is the face front). Tune it to sit on the model's mouth — if you don't
## see it, it may be inside the head; push Z out (more forward) and adjust Y to taste.
@export var mouth_position: Vector3 = Vector3(0.0, -0.03, 0.14)
## Mouth flaps per ~6.3s (a sine rate) — the open/close chatter speed while speaking.
@export var mouth_flap_rate: float = 22.0

# --- Hide target -------------------------------------------------------------------------------------------------
## The base body instance whose meshes get hidden behind the swap. Empty -> auto-find a sibling "Body" node under
## the NPC. NOTE: the shipped enemy.tscn no longer ships a default "Body" (removed as a vestigial hidden
## placeholder), so this resolves to null and the hide is a harmless no-op by default; set it only if you add a
## base mesh you deliberately want hidden.
@export var default_body: Node3D:
	set(value):
		default_body = value
		_rebuild()

var _body: Node3D = null       ## live body instance (unowned -> never baked into the .tscn)
var _body_transp_touched: bool = false  ## a non-zero body_transparency has been applied — 0 must then RESTORE solid, not early-out
var _head: Node3D = null       ## live head instance (the head-look's target at runtime)
var _arm_left: Node3D = null   ## live left-arm instance
var _arm_right: Node3D = null  ## live right-arm instance (a mirror of the left)
var _arm_transp_touched: bool = false  ## same latch as _body_transp_touched, for arm_transparency
var _leg_left: Node3D = null   ## live left-leg instance
var _leg_right: Node3D = null  ## live right-leg instance (a mirror of the left)
var _leg_transp_touched: bool = false  ## same latch as _body_transp_touched, for leg_transparency
var _outline_mats: Dictionary = {}  ## part key -> its own actor-rim ShaderMaterial; survives rebuilds (see _outline_material)
var _outline_touched: bool = false  ## the actor rim has been applied at least once — off must then STRIP, not early-out
var _swing_phase: float = 0.0    ## walk-cycle phase, advanced only while moving (shared by arms + legs -> one gait)
var _mode_pitch: float = 0.0     ## smoothed SYMMETRIC pitch (both arms): raised to hold a weapon, else 0
var _swing_blend: float = 0.0    ## smoothed 0..1 fade for the arms' ANTISYMMETRIC walk swing (left +swing, right -swing)
var _leg_blend: float = 0.0      ## smoothed 0..1 fade for the legs' walk swing (left -swing, right +swing -> contralateral to the arms)
var _leg_world_yaw: float = 0.0  ## smoothed WORLD-space facing of the legs (tracks movement dir; when still, eases to the torso yaw — or HOLDS this last facing if legs_square_when_idle is off)
var _leg_yaw_ready: bool = false ## once true, _leg_world_yaw has been seeded to the body yaw (avoids a spawn-frame swivel from 0)
var _bob_phase: float = 0.0      ## talking head-bob sine phase
var _bob_amt: float = 0.0        ## smoothed 0..1 talking bob envelope (eases in/out as line delivery starts/stops)
var _bob_head: Node3D = null     ## the head node currently being bobbed (re-resolved if it rebuilds)
var _bob_rest_y: float = 0.0     ## that head's rest local Y, captured so the bob oscillates AROUND it
var _mouth: MeshInstance3D = null  ## the Tomodachi mouth (a billboarded black-circle quad on the face); lazily built
var _mouth_phase: float = 0.0    ## mouth-flap sine phase
var _talk_t: float = 0.0         ## talking-envelope countdown (seconds): the head bobs + mouth flaps while >0; pulsed by talk_for() per spoken utterance

static var _mouth_texture: Texture2D = null  ## the shared black-circle texture for every mouth (built once)
var _strike_t: float = 0.0       ## 1 -> 0 fist-strike flail envelope, set by strike() on a punch, decays over arm_strike_duration
var _strike_side: float = 1.0    ## which fist LEADS the current strike (+1 = left); flipped per strike when arm_strike_alternate
var _fists_sway: float = 0.0     ## smoothed fists-out alternating-sway amplitude (eases to 0 when not squared up)
var _breathe_phase: float = 0.0  ## breathing sine phase (advances at breathe_rate while alive)
var _body_base_scale: float = 1.0  ## the torso's authored uniform scale; breathing modulates AROUND it (cached so _process doesn't re-resolve _eff_body each frame)
var _sitting_pose_active: bool = false  ## last host is_sitting() state applied to base transforms
var _seat_ground_y: float = 0.0        ## swap-LOCAL Y of the surface under the seated host (valid only while _seat_ground_valid)
var _seat_ground_valid: bool = false   ## the seated ground probe has a hit; false standing / in editor / probe miss
var _seat_probe_from: Vector3 = Vector3.INF  ## host global position at the last probe — re-probe only after real movement
var _arm_reach: float = -1.0           ## measured shoulder->fingertip reach of the arm model (swap m, pre-arm_scale; -1 = unmeasured)
var _host_model_sig: String = ""  ## editor live-preview: last seen host body/head MODEL signature (rebuild on change)
var _host_xf_sig: String = ""     ## editor live-preview: last seen host transform/skin signature (re-place on change)

func _ready() -> void:
	# Keep processing the idle breathing even while the world is PAUSED for dialogue and the host NPC is frozen:
	# DialogueManager does get_tree().paused = true AND sets the speaker to PROCESS_MODE_DISABLED. An EXPLICIT
	# process mode is independent of the tree-pause and of the parent's mode, so the NPC you're talking to keeps
	# breathing (its frozen state is still readable). Runtime only -- the editor preview is unaffected.
	if not Engine.is_editor_hint():
		process_mode = Node.PROCESS_MODE_ALWAYS
		_breathe_phase = randf() * TAU  # random start across the breath cycle so NPCs don't all inhale in lockstep
	_rebuild()

func _validate_property(property: Dictionary) -> void:
	if property.name in [&"body_model", &"head_model", &"arm_model", &"leg_model"]:
		property.hint = PROPERTY_HINT_RESOURCE_TYPE
		property.hint_string = ModelResourceUtil.HINT
	# The pick dropdowns are a LIVE folder scan (the Factions.ids_csv idiom), so dropping a part .tres into
	# res://resources/parts/<slot>/ lists it with no editor restart. SUGGESTION, not ENUM: the box stays editable,
	# and PartLibrary.stamp no-ops on an id that doesn't resolve, so free text can never blank a working part.
	elif property.name == &"apply_body_part":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = PartLibrary.ids_csv(PartLibrary.SLOT_BODIES)
	elif property.name == &"apply_head_part":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = PartLibrary.ids_csv(PartLibrary.SLOT_HEADS)
	elif property.name == &"apply_arm_part":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = PartLibrary.ids_csv(PartLibrary.SLOT_ARMS)
	elif property.name == &"apply_leg_part":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = PartLibrary.ids_csv(PartLibrary.SLOT_LEGS)

func _process(delta: float) -> void:
	# The editor preview is the STATIC rest pose (so you can place the limbs); the swing/hold animation is runtime.
	if Engine.is_editor_hint():
		_editor_poll_host()  # live-preview the NPC root's body/head model overrides as you edit them
		return
	# Skip the gait animation while the world is PAUSED (dialogue): the speaker (and every other NPC) is frozen,
	# and its last velocity would still read as "walking" and keep swinging the arms. Breathing runs regardless
	# (below), so the NPC you're talking to stays alive without the limbs animating mid-freeze.
	var sitting := _host_sitting()
	_sync_posture_transforms(sitting)
	# `or _strike_t > 0.0` so a rig with BOTH animation flags off still ticks long enough to play out a strike
	# (and, just as importantly, to DECAY the envelope -- otherwise a stray strike() latches _strike_t at 1.0
	# forever and the arms snap up the moment anyone later enables animate_arms).
	if not get_tree().paused and (animate_arms or animate_legs or _strike_t > 0.0):
		_animate_limbs(delta, sitting)
	if breathe:
		# Only the NPC you're TALKING TO breathes during a conversation — every other NPC holds still. (Without
		# this they'd all keep breathing through the dialogue pause, since this node is PROCESS_MODE_ALWAYS.)
		if not (DialogueManager.is_active() and not _is_dialogue_speaker()):
			_breathe(delta)
	_animate_talk(delta)  # talking head-bob + mouth flap (active only on the NPC currently delivering a line)

## Seated ground-snap driver (see seated_snap_to_ground): while the host sits, keep _seat_ground_y tracking the
## surface straight below it. Physics-frame because direct_space_state queries belong there; the cached probe only
## refreshes after the host really moves (spawn gravity-settling, a pool-reuse teleport), so a parked sitter costs
## one distance check per tick. Standing (or snap off) just invalidates the cache — the fixed-offset path returns.
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not (seated_snap_to_ground and _host_sitting()):
		_seat_ground_valid = false
		_seat_probe_from = Vector3.INF
		return
	var host := get_parent() as Node3D
	if host == null or not host.is_inside_tree():
		return
	if _seat_probe_from.is_finite() and host.global_position.distance_squared_to(_seat_probe_from) < SEATED_REPROBE_DISTANCE * SEATED_REPROBE_DISTANCE:
		return
	_probe_seated_ground(host)

## One downward ray from the host origin: seated_max_snap_depth of world (SEATED_PROBE_MASK) below, excluding the
## host's own body so the ray never lands on the NPC's capsule. The ray length doubles as the plausibility gate —
## a surface deeper than a settled capsule's support can't be the seat, so a ledge-overhang sitter misses rather
## than snapping into the drop. A hit caches the surface in swap-LOCAL Y (to_local, so any host yaw / an offset
## swap node stay exact) and re-applies the posture when the drop actually moved; a miss invalidates the cache so
## the pose falls back to the host capsule bottom (_seat_plane_y).
func _probe_seated_ground(host: Node3D) -> void:
	_seat_probe_from = host.global_position
	var world := host.get_world_3d()
	if world == null:
		return
	var query := PhysicsRayQueryParameters3D.create(
		host.global_position, host.global_position + Vector3.DOWN * seated_max_snap_depth, SEATED_PROBE_MASK)
	if host is CollisionObject3D:
		query.exclude = [(host as CollisionObject3D).get_rid()]
	var hit := world.direct_space_state.intersect_ray(query)
	var was_y := _seat_ground_y
	var was_valid := _seat_ground_valid
	_seat_ground_valid = not hit.is_empty()
	if _seat_ground_valid:
		var p: Vector3 = hit["position"]
		_seat_ground_y = to_local(p).y
	if _seat_ground_valid != was_valid or absf(_seat_ground_y - was_y) > 0.005:
		# The drop changed (first probe, or the host settled onto the floor): snap the arms' eased pitch onto the
		# re-clamped pose too, so they don't visibly dip through the floor while the lerp catches up.
		if _sitting_pose_active:
			_mode_pitch = _seated_arm_pitch_eff()
		_apply_posture_transforms()

## A subtle, slow CHEST rise/fall: scale the torso (the body mesh only — head/arms/legs are separate children,
## so they don't grow with it) on a sine around its authored scale, Deus Ex idle style. Rests at the base scale
## once the host is dead (no breathing corpse) — duck-typed HP read, per the duck-typed-read rule.
func _breathe(delta: float) -> void:
	if not is_instance_valid(_body):
		return
	var host := get_parent()
	var raw: Variant = host.get(&"hp") if host != null else null
	var alive := not (raw is float or raw is int) or float(raw) > 0.0
	if not alive:
		_body.scale = Vector3.ONE * _body_base_scale  # rest at the authored scale; a corpse doesn't breathe
		return
	_breathe_phase += delta * breathe_rate
	_body.scale = Vector3.ONE * (_body_base_scale * (1.0 + sin(_breathe_phase) * breathe_amount))

## True when the NPC this body belongs to is the one currently in dialogue with the player (so the talking
## head-bob / mouth + the speaker-only breathing apply to it alone). is_ancestor_of covers any nesting depth.
func _is_dialogue_speaker() -> bool:
	var sp: Node = DialogueManager.current_speaker()
	return sp != null and sp.is_ancestor_of(self)

## The head node the talk bob + mouth ride on: this component's own swapped head if present, else the host's
## resolved visible head (head_visual()). Null -> no separate head node (bob/mouth are no-ops).
func _talk_head() -> Node3D:
	if is_instance_valid(_head):
		return _head
	var host := get_parent()
	if host != null and host.has_method(&"head_visual"):
		var h: Variant = host.call(&"head_visual")
		if h is Node3D:
			return h
	return null

## Talking presentation, runtime-only (called every frame). The head BOBS and a Tomodachi MOUTH flaps while this
## NPC is the active speaker delivering a line; both ease/close otherwise. Keyed off DialogueManager so no
## NPC-side wiring is needed; non-speakers fall through cheaply (current_speaker() != us -> talking false).
func _animate_talk(delta: float) -> void:
	if _talk_t > 0.0:
		_talk_t = maxf(0.0, _talk_t - delta)
	var talking := _talk_t > 0.0
	# Steady-state fast path: not talking, bob already settled, mouth already hidden -> nothing to do. Skips the
	# work for every silent NPC on every frame (the common case), while still letting the bob ease back out.
	if not talking and _bob_amt < 0.001 and not (is_instance_valid(_mouth) and _mouth.visible):
		return
	_talk_head_bob(delta, talking)
	_talk_mouth(delta, talking)

## Pulse the talking envelope: the head bobs + the mouth flaps for `seconds` (the utterance length). Pushed by
## the host NPC (NPC.note_speaking) whenever it speaks a dialogue line OR a bark, so the animation tracks ACTUAL
## utterances, not the whole dialogue turn. maxf so an overlapping pulse never cuts an in-flight one short.
func talk_for(seconds: float) -> void:
	_talk_t = maxf(_talk_t, seconds)

## End the talking envelope NOW instead of letting the last utterance's ESTIMATED duration run out: the head-bob
## eases back to rest and the mouth closes (both via _animate_talk next frame). Pushed by the host NPC
## (NPC.note_speaking_stop) when it's no longer delivering a spoken line — the dialogue response menu opened, or the
## conversation ended — so the head doesn't keep bobbing while the player reads the choices, or for a beat after the
## box closes as the NPC returns to idle (the "head bobbing when it isn't talking" tell). No-op if not in an envelope.
func stop_talking() -> void:
	_talk_t = 0.0

## Bob the head up/down (position only, so it composes with the head-look's basis writes) around its rest Y while
## talking, easing the amplitude in/out. Re-caches the rest Y if the head node is rebuilt.
func _talk_head_bob(delta: float, talking: bool) -> void:
	if not talk_head_bob:
		return
	var head := _talk_head()
	if head == null:
		return
	if head != _bob_head:
		_bob_head = head
		_bob_rest_y = head.position.y
	_bob_amt = lerpf(_bob_amt, 1.0 if talking else 0.0, 1.0 - exp(-talk_bob_ease * delta))
	if talking:
		_bob_phase += delta * talk_bob_rate
	head.position.y = _bob_rest_y + sin(_bob_phase) * talk_bob_height * _bob_amt

## Flap the mouth (a billboarded black circle on the face) between a thin line and a full circle while talking;
## hide it otherwise. Built lazily on the current head (rebuilt if the head node changes — e.g. a model swap).
func _talk_mouth(delta: float, talking: bool) -> void:
	if not show_mouth:
		return
	var head := _talk_head()
	if head == null:
		return
	if not is_instance_valid(_mouth) or _mouth.get_parent() != head:
		_build_mouth(head)
	if not talking:
		if _mouth.visible:
			_mouth.visible = false
		_mouth_phase = 0.0
		return
	_mouth.visible = true
	_mouth_phase += delta * mouth_flap_rate
	var open := 0.5 - 0.5 * cos(_mouth_phase)         # 0 = a thin line, 1 = a full circle
	_mouth.scale = Vector3(1.0, lerpf(0.1, 1.0, open), 1.0)  # squash vertically -> the line<->circle flap

## Create the mouth: a black-circle QuadMesh parented to the head's face, billboarded toward the camera so it
## can never be oriented away / hidden by a model whose face isn't +Z. Uses a MESH + StandardMaterial3D billboard
## with billboard_keep_scale=true (NOT a Sprite3D / node billboard) — the flap is driven by the node's scale.y,
## which a plain billboard DISCARDS (see ambient_dust.gd / sky_title.gd). Unshaded black, alpha-cut to the circle.
func _build_mouth(head: Node3D) -> void:
	if is_instance_valid(_mouth):
		_mouth.queue_free()
	_mouth = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(mouth_size * 2.0, mouth_size * 2.0)
	_mouth.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _mouth_circle_texture()           # white circle on transparent; tinted black below
	mat.albedo_color = Color.BLACK
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # flat black regardless of lighting
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA     # the circle's alpha cuts the quad corners
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED             # visible from both sides
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true                         # CRITICAL: keep the node scale so scale.y can flap it
	_mouth.material_override = mat
	_mouth.position = mouth_position
	_mouth.visible = false
	head.add_child(_mouth)

## The shared circle texture every mouth uses — a filled WHITE disc on transparent (the material tints it via
## albedo_color, so it stays recolourable). Built once (static), shared across all mouths.
static func _mouth_circle_texture() -> Texture2D:
	if _mouth_texture != null:
		return _mouth_texture
	var px := 64
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 0.0))
	var c := px * 0.5
	var r := px * 0.5 - 1.0
	for y in range(px):
		for x in range(px):
			var dx := float(x) + 0.5 - c
			var dy := float(y) + 0.5 - c
			if dx * dx + dy * dy <= r * r:
				img.set_pixel(x, y, Color.WHITE)
	_mouth_texture = ImageTexture.create_from_image(img)
	return _mouth_texture

## Runtime limb motion driven by the host NPC's state, on ONE shared gait phase so the arms and legs stay locked.
## ARMS pick a symmetric mode pose -- hold a GUN forward (is_holding_gun), or straight UP when airborne+unarmed
## (roller-coaster / Roblox), else by the side -- with the fist-strike FLAIL added on top, and the antisymmetric
## walk swing when moving unarmed on the ground. LEGS swing while walking on the ground (contralateral to the
## arms) and FLAIL (faster + wider) in the air; they rest only when grounded and still. Each pair mirrors L/R
## across the body centre. Duck-typed host reads.
## SITTING short-circuits all of that (_apply_seated_limb_pose): a seated NPC eases into the static seated_*_pitch
## pose instead, so a chair-bound NPC never walk-swings or air-flails its limbs while parked. The one mode pose
## that DOES survive sitting down is the weapon hold — a seated NPC with its gun drawn keeps its hands on it (see
## _seated_preferred_arm_pitch), because the gun anchor rides the seated drop with the body.
func _animate_limbs(delta: float, sitting: bool) -> void:
	var host := get_parent()
	if host == null:
		return
	if sitting:
		_apply_seated_limb_pose(delta)
		return
	var gun_out := HostMethodHelper.try_call_bool(host, &"is_holding_gun")
	# ARMS onto the weapon. Default (arms_hold_when_drawn): the moment the gun is OUT the hands come up onto it, so an
	# armed enemy always reads as holding its gun rather than letting the arms hang while the weapon floats at the
	# fixed hand anchor. Stealth-safe — the pose is symmetric and points the gun along the TORSO, whose facing is
	# perception-gated (GOAP), so hands-on-the-gun never telegraphs "aiming at a you it hasn't seen".
	var raised := gun_out
	if gun_out and not arms_hold_when_drawn:
		# Stealth-telegraph mode: keep the gun drawn but the arms LOW until the foe is within arm_raise_range AND the
		# host has genuinely SENSED it — so the arms coming up is itself the honest "I noticed you" tell, never a
		# proximity reflex at an unseen player (through a wall / behind its back / in the dark). arm_raise_range <= 0
		# or a host without aim_distance() skips the range gate; a host without has_sensed_foe() defaults true.
		if arm_raise_range > 0.0 and host.has_method(&"aim_distance"):
			raised = float(host.call(&"aim_distance")) <= arm_raise_range
		if raised:
			raised = HostMethodHelper.try_call_bool(host, &"has_sensed_foe", true)
	var fists_out := HostMethodHelper.try_call_bool(host, &"is_fists_out")
	var airborne := not HostMethodHelper.try_call_bool(host, &"is_on_floor", true)  # default true: no method -> not airborne
	var climbing := HostMethodHelper.try_call_bool(host, &"is_climbing")
	# The NPC you're TALKING TO holds its arms DOWN for the whole conversation, whatever its (frozen) combat pose.
	# This gait still ticks on the speaker through the UNPAUSED dialogue intro beat (this node is
	# PROCESS_MODE_ALWAYS even as the host freezes at PROCESS_MODE_DISABLED), so without forcing the arms to rest
	# here a gun-out / fists-out speaker would re-raise them right as the box opens. NPC.set_in_dialogue also snaps
	# them down at once via lower_arms(); this keeps them there. ARMS only — legs / breathing / head-bob unaffected.
	var in_dialogue := _is_dialogue_speaker()
	if in_dialogue:
		raised = false
		fists_out = false
	# On a wall (wall-climb) the host isn't on the floor but isn't free-falling either — treat it as grounded so the
	# legs stride against the wall instead of doing the airborne bicycle-flail. (The host pitches the rig onto the
	# wall separately.)
	if climbing:
		airborne = false
	# velocity_driven_legs (the Player's FP legs): the legs run their normal speed-gated walk gait in the AIR too,
	# tracking real velocity, instead of the NPC mid-air "bicycle" flail. airborne_flail keeps the NPC behaviour.
	var airborne_flail := airborne and not velocity_driven_legs
	var speed := 0.0
	var planar := 0.0
	var v: Variant = host.get(&"velocity")
	if v is Vector3:
		planar = Vector2((v as Vector3).x, (v as Vector3).z).length()
		speed = planar
		if climbing:
			speed = maxf(planar, absf((v as Vector3).y))  # scaling a wall: stride off the VERTICAL climb speed — going "up" IS moving
	var moving := (not airborne or velocity_driven_legs) and speed > arm_move_threshold  # walk cycle: grounded, or anytime when velocity-driven
	# Fists-out holds the forward pose with its OWN alternating sway (below), which replaces the normal walk swing.
	var arms_walking := animate_arms and not raised and not fists_out and not in_dialogue and moving  # arms swing when moving with arms NOT raised (unarmed, or armed-but-far); never while being talked to
	var legs_active := animate_legs and (moving or airborne_flail)  # legs swing while walking AND (NPC) flail while airborne
	# ONE gait phase, advanced whenever a limb is moving AND while fists are out (so the squared-up reach bobs even
	# standing still). FASTER in the air so the legs flail (a quick bicycle kick); a slow lurch when squared up +
	# standing; else the walk rate. The arms don't swing mid-air, so the air rate only ever drives the legs + bob.
	if arms_walking or legs_active or fists_out:
		var phase_rate := arm_swing_rate
		if velocity_driven_legs and legs_active:
			# Stride CADENCE tracks real speed: cycle at arm_swing_rate at velocity_leg_ref_speed, slower below,
			# quicker above (bhop/dash). So the walk animation's speed is dictated by how fast you're actually going.
			phase_rate = arm_swing_rate * clampf(speed / maxf(velocity_leg_ref_speed, 0.01), 0.3, 3.0)
		elif airborne_flail:
			phase_rate *= leg_air_flail_scale
		elif fists_out and not moving:
			phase_rate = arm_fists_idle_rate
		_swing_phase += delta * phase_rate
	var swing := sin(_swing_phase)
	# ARMS: symmetric mode pose (hold / up-in-air / side) + the fist-strike flail + the antisymmetric walk swing.
	if animate_arms and is_instance_valid(_arm_left):
		var mode_target := 0.0  # by the side
		if raised:
			mode_target = arm_hold_pitch        # holding the gun forward — whenever it's drawn (see `raised`)
		elif airborne and not in_dialogue:
			mode_target = arm_air_pitch          # both arms straight up (roller coaster); suppressed while being talked to
		elif fists_out:
			mode_target = arm_fists_pitch        # arms out — squared up to punch
		_mode_pitch = lerpf(_mode_pitch, mode_target, 1.0 - exp(-12.0 * delta))
		_strike_t = maxf(0.0, _strike_t - delta / maxf(arm_strike_duration, 0.01))
		# Strike amplitude, split per arm so one fist can LEAD (arm_strike_alternate / arm_strike_offhand_scale).
		# At the shipped defaults (no alternation, off-hand 1.0) both sides get the same value, which is exactly
		# the old single symmetric `flail` — every existing NPC punch is byte-identical.
		var amp := strike_amplitude(_strike_t, arm_strike_curve) if not gun_out else 0.0
		var amp_lead := amp if _strike_side >= 0.0 else amp * arm_strike_offhand_scale
		var amp_off := amp * arm_strike_offhand_scale if _strike_side >= 0.0 else amp
		_swing_blend = lerpf(_swing_blend, 1.0 if arms_walking else 0.0, 1.0 - exp(-10.0 * delta))
		var a := swing * arm_swing_amplitude * _swing_blend  # antisymmetric walk swing (0 while fists are out)
		# Fists-out: an ANTISYMMETRIC sway (arms ALTERNATE -- one forward, one back, like a natural stride) on top
		# of the forward hold -- small standing, bigger walking -- so the reach looks alive. Smoothed to ease in.
		var sway_target := (arm_fists_walk_sway if moving else arm_fists_idle_sway) if fists_out else 0.0
		_fists_sway = lerpf(_fists_sway, sway_target, 1.0 - exp(-8.0 * delta))
		var s := swing * _fists_sway  # left +s / right -s -> the arms alternate (same shape as the walk swing)
		_arm_left.transform = _arm_pose(arm_rotation + Vector3(_mode_pitch + arm_strike_pitch * amp_lead + a + s, 0.0, 0.0), arm_strike_thrust * amp_lead)
		if is_instance_valid(_arm_right):
			_arm_right.transform = _reflect() * _arm_pose(arm_rotation + Vector3(_mode_pitch + arm_strike_pitch * amp_off - a - s, 0.0, 0.0), arm_strike_thrust * amp_off)
	# STRIKE-ONLY path — how an animate_arms-OFF rig punches. The player's unarmed view-model hands
	# (FirstPersonBody._build_first_person_arms, animate_arms = false) live here: they must NOT walk-swing, mode-pitch or fists-sway just
	# because they can throw a punch, so instead of enabling all of that we write rest pose + the strike terms
	# and nothing else. Reachable only when animate_arms is false, so no NPC ever takes it.
	#
	# Self-terminating: the envelope decays FIRST (unconditionally, so an arm-less rig cannot leak it), and the
	# frame it reaches 0 the amplitude is 0, which writes exactly the authored rest pose — the same expression
	# _apply_arm_transform() uses — before the branch stops running.
	elif _strike_t > 0.0:
		_strike_t = maxf(0.0, _strike_t - delta / maxf(arm_strike_duration, 0.01))
		if is_instance_valid(_arm_left):
			var s_amp := strike_amplitude(_strike_t, arm_strike_curve)
			var s_lead := s_amp if _strike_side >= 0.0 else s_amp * arm_strike_offhand_scale
			var s_off := s_amp * arm_strike_offhand_scale if _strike_side >= 0.0 else s_amp
			var s_base := arm_rotation + Vector3(_seated_arm_pitch_eff() if sitting else 0.0, 0.0, 0.0)
			_arm_left.transform = _arm_pose(s_base + Vector3(arm_strike_pitch * s_lead + arm_stride_deg, 0.0, 0.0), arm_strike_thrust * s_lead)
			if is_instance_valid(_arm_right):
				_arm_right.transform = _reflect() * _arm_pose(s_base + Vector3(arm_strike_pitch * s_off - arm_stride_deg, 0.0, 0.0), arm_strike_thrust * s_off)
	# LEGS: swing forward/back -- a walk on the ground, a faster + WIDER flail in the air. Left -swing / right
	# +swing -> opposite each other (and contralateral to the arms while walking).
	if animate_legs and is_instance_valid(_leg_left):
		_leg_blend = lerpf(_leg_blend, 1.0 if legs_active else 0.0, 1.0 - exp(-10.0 * delta))
		var leg_amp := leg_swing_amplitude
		if airborne_flail:
			leg_amp = leg_swing_amplitude * leg_air_flail_scale
		elif climbing:
			leg_amp = leg_swing_amplitude * 0.5  # gentler steps while scaling a wall — less foot-into-wall on the forward swing
		var l := swing * leg_amp * _leg_blend
		# Decouple the leg yaw from the torso: ease the legs' WORLD facing toward the movement direction while
		# moving on the ground, back to the body's own yaw when still / airborne. The LOCAL turn applied to the
		# legs is the gap to the body's current yaw, recomputed each frame, so the legs hold the movement line
		# even as the torso swivels to keep its aim on you. Pre-multiplied so it rotates the whole hip about UP.
		var leg_turn := Transform3D.IDENTITY
		if legs_follow_movement:
			var body_yaw := global_transform.basis.get_euler().y
			if not _leg_yaw_ready:
				_leg_world_yaw = body_yaw
				_leg_yaw_ready = true
			# Idle target: square back with the torso (the NPC combat stance), OR — with legs_square_when_idle
			# off — HOLD the last steered facing so the feet stay pointed where you were going instead of snapping
			# to the torso/camera (the Player's FP legs). Movement below always overrides this idle target.
			var target_yaw := body_yaw if legs_square_when_idle else _leg_world_yaw
			if moving and planar > arm_move_threshold:  # only HORIZONTAL movement steers the leg facing (a vertical climb shouldn't swivel them)
				target_yaw = atan2(v.x, v.z)
			_leg_world_yaw = lerp_angle(_leg_world_yaw, target_yaw, 1.0 - exp(-leg_turn_rate * delta))
			leg_turn = Transform3D(Basis(Vector3.UP, wrapf(_leg_world_yaw - body_yaw, -PI, PI)))
		_leg_left.transform = leg_turn * _leg_pose(-l)
		if is_instance_valid(_leg_right):
			_leg_right.transform = leg_turn * _reflect() * _leg_pose(l)

func _apply_seated_limb_pose(delta: float) -> void:
	_mode_pitch = lerpf(_mode_pitch, _seated_arm_pitch_eff(), 1.0 - exp(-12.0 * delta))
	_swing_blend = lerpf(_swing_blend, 0.0, 1.0 - exp(-10.0 * delta))
	_leg_blend = lerpf(_leg_blend, 0.0, 1.0 - exp(-10.0 * delta))
	_fists_sway = lerpf(_fists_sway, 0.0, 1.0 - exp(-8.0 * delta))
	_strike_t = 0.0
	if animate_arms and is_instance_valid(_arm_left):
		_arm_left.transform = _arm_pose(arm_rotation + Vector3(_mode_pitch, 0.0, 0.0))
		if is_instance_valid(_arm_right):
			_arm_right.transform = _reflect() * _arm_pose(arm_rotation + Vector3(_mode_pitch, 0.0, 0.0))
	if animate_legs and is_instance_valid(_leg_left):
		_leg_left.transform = _leg_pose(seated_leg_pitch)
		if is_instance_valid(_leg_right):
			_leg_right.transform = _reflect() * _leg_pose(seated_leg_pitch)

func _host_sitting() -> bool:
	var host := get_parent()
	if host == null:
		return false
	if host.has_method(&"is_sitting"):
		return bool(host.call(&"is_sitting"))
	var raw: Variant = host.get(&"sitting")
	return raw is bool and raw

func _posture_offset() -> Vector3:
	if not _host_sitting():
		return Vector3.ZERO
	return Vector3(seated_visual_offset.x, _seated_drop_y(), seated_visual_offset.z)

## PUBLIC posture seam: the live visual offset EVERY swapped part rides (the seated drop + its ground snap; ZERO
## while standing), in this node's LOCAL space. head_rest_position() is the same seam narrowed to the head's rest
## placement; this one exists for host-owned nodes that must stay glued to the visible BODY rather than to the
## capsule — the NPC's held-weapon hand anchor (NPC._sync_muzzle_to_posture) is the one that ships. ANY new
## absolute writer of a body-relative position has the same requirement, or it floats when the NPC sits down.
func posture_offset() -> Vector3:
	return _posture_offset()

## The seated pose's Y drop (swap-local): the leg HIP (leg_position) lands seated_hip_clearance above the seat
## plane, so a ground-sitter's butt meets the floor and a chair-sitter's meets the seat. Falls back to the
## authored seated_visual_offset.y only when the seat plane can't be resolved at all (see _seat_plane_y).
func _seated_drop_y() -> float:
	var plane := _seat_plane_y()
	if is_nan(plane):
		return seated_visual_offset.y
	return plane + seated_hip_clearance - leg_position.y

## Swap-LOCAL Y of the surface this sitter's hips rest on, or NAN when it can't be resolved (the authored
## seated_visual_offset.y then stands). Two sources, both gated behind seated_snap_to_ground — with the snap OFF
## the designer has taken ownership of the drop, so neither may override it:
##   1. The runtime ground PROBE (_probe_seated_ground) — the truth while the game is running.
##   2. The host's own CAPSULE BOTTOM. A settled character's capsule rests ON whatever supports it (the floor for
##      a ground-sitter, the seat for one parked on a chair), so its bottom IS the seat plane — and unlike the ray
##      it needs no stepped physics, which is what makes the EDITOR PREVIEW truthful. Before this the viewport
##      only ever showed the fixed seated_visual_offset (-0.28 on the shipped rig), so a floor-sitter placed in
##      the editor hovered ~0.4 m above the ground in a sitting pose and dropped onto it only in game — the
##      "the seated body is misaligned" report. It doubles as the right RUNTIME fallback on a probe MISS (nothing
##      within seated_max_snap_depth), which is the same "supported by something we couldn't ray" case.
func _seat_plane_y() -> float:
	if _seat_ground_valid:
		return _seat_ground_y
	if not seated_snap_to_ground:
		return NAN
	return _host_capsule_bottom_y()

## Swap-LOCAL Y of the bottom of the host's capsule collider (its feet plane), or NAN off-tree / when the host has
## no direct CollisionShape3D child holding a CapsuleShape3D. A LOCAL scan on purpose rather than Locomotor's
## collision_bottom_y: this component also rides the PLAYER rig, and must not pull in the NPC nav stack.
func _host_capsule_bottom_y() -> float:
	if not is_inside_tree():
		return NAN
	var host := get_parent() as Node3D
	if host == null:
		return NAN
	for c in host.get_children():
		var col := c as CollisionShape3D
		if col == null:
			continue
		var cap := col.shape as CapsuleShape3D
		if cap == null:
			continue
		# Global point at the capsule's bottom cap, brought into swap space (a host YAW leaves Y untouched, so this
		# is exact on any facing) — the same to_local() conversion the ground probe caches its hit with.
		return to_local(col.global_position - col.global_basis.y * (cap.height * 0.5)).y
	return NAN

## The seated arms' EFFECTIVE pitch: the PREFERRED seated pose (the lap rest, or the GUN HOLD while the weapon is
## up — see _seated_preferred_arm_pitch) run through the seat clearance clamp below.
func _seated_arm_pitch_eff() -> float:
	return _seated_pitch_clamped(_seated_preferred_arm_pitch())

## `preferred` auto-RAISED (pitched further forward, never lowered) whenever hanging at that angle would push the
## hands through the seat plane — the hands come to rest on the lap instead of clipping the floor. Uses the arm
## model's measured reach; no resolvable seat plane or no measurable arm -> `preferred` unchanged.
func _seated_pitch_clamped(preferred: float) -> float:
	var plane := _seat_plane_y()
	if is_nan(plane):
		return preferred
	var room := (arm_position.y + _seated_drop_y()) - (plane + seated_hand_clearance)
	return seated_pitch_to_clear(preferred, room, _arm_reach_measured() * arm_scale)

## The arms' preferred pitch while seated, BEFORE that clamp: the GUN-HOLD pose whenever this NPC has its weapon
## up, else the authored lap rest. The STANDING hold angle is the right one seated because the held view-model
## hangs off a hand anchor the host keeps in step with the seated drop (NPC._sync_muzzle_to_posture) — the gun
## sits at the same place ON THE BODY in both postures. Without this a seated guard folded its hands into its lap
## while the rifle it is holding hovered beside them (the armed half of "sitting doesn't mesh with hostile NPCs",
## and hostiles are exactly the NPCs that have a gun out).
## The gates MIRROR _animate_limbs' standing `raised` logic so the stealth tells read identically in both
## postures: arms_hold_when_drawn (the default) holds the moment the gun is drawn; with it OFF the hands stay in
## the lap until the foe is inside arm_raise_range AND has genuinely been SENSED. A seated dialogue speaker drops
## to the lap either way — lower_arms() clamps seated_arm_pitch directly, and this agrees once the world unpauses.
func _seated_preferred_arm_pitch() -> float:
	return arm_hold_pitch if _seated_holds_gun() else seated_arm_pitch

func _seated_holds_gun() -> bool:
	var host := get_parent()
	# Short-circuits on the gun BEFORE any other host read, so a host that can't hold one (a civilian, the Player
	# rig, an off-tree unit-test NPC) never reaches the dialogue / perception queries at all.
	if host == null or not HostMethodHelper.try_call_bool(host, &"is_holding_gun"):
		return false
	if _is_dialogue_speaker():
		return false
	if arms_hold_when_drawn:
		return true
	if arm_raise_range > 0.0 and host.has_method(&"aim_distance") \
			and float(host.call(&"aim_distance")) > arm_raise_range:
		return false
	return HostMethodHelper.try_call_bool(host, &"has_sensed_foe", true)

## Pure clamp math (static for GUT): the from-vertical pitch (degrees; sign = swing direction, the shipped rig's
## forward is negative) a seated arm must hold so its vertical extent reach*cos(pitch) fits inside `room` — the
## metres of clear air between the shoulder and the surface (already minus the hand clearance). Keeps `preferred`
## when it already clears; zero/negative room pins the arm horizontal (90); zero reach means nothing to clamp.
static func seated_pitch_to_clear(preferred_deg: float, room: float, reach: float) -> float:
	if reach <= 0.0:
		return preferred_deg
	var needed := 90.0 if room <= 0.0 else rad_to_deg(acos(clampf(room / reach, 0.0, 1.0)))
	var side := -1.0 if preferred_deg <= 0.0 else 1.0
	return side * maxf(absf(preferred_deg), needed)

## Shoulder->fingertip reach of the swapped arm model (swap-space metres, BEFORE arm_scale — the pose's basis
## scaling applies it), measured lazily once per rebuild from the instanced meshes' AABB corners: the arm pivots
## at its own origin (the shoulder), so the farthest corner from it IS the reach. Girth pads it slightly — that
## errs safe (hands end a touch higher, never lower).
func _arm_reach_measured() -> float:
	if _arm_reach < 0.0 and is_instance_valid(_arm_left):
		_arm_reach = _part_reach(_arm_left, Transform3D.IDENTITY)
	return maxf(_arm_reach, 0.0)

## Farthest mesh-AABB corner from `node`'s own origin, in `node`'s local space (xf accumulates child transforms;
## the root's OWN transform is excluded on purpose — _arm_pose overwrites it every frame).
func _part_reach(node: Node, xf: Transform3D) -> float:
	var best := 0.0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var aabb: AABB = (node as MeshInstance3D).get_aabb()
		for i in 8:
			best = maxf(best, (xf * aabb.get_endpoint(i)).length())
	for c in node.get_children():
		if c is Node3D:
			best = maxf(best, _part_reach(c, xf * (c as Node3D).transform))
	return best

func _sync_posture_transforms(sitting: bool) -> void:
	if _sitting_pose_active == sitting:
		return
	_sitting_pose_active = sitting
	if sitting:
		# Seed the arms' eased pitch straight onto the seated pose so sitting down never routes them through the
		# hang-at-the-side angle (which, at a ground-level seat, points them into the floor mid-ease).
		_mode_pitch = _seated_arm_pitch_eff()
	_apply_posture_transforms()
	_sync_shadow(sitting)

## Hide/restore the host's blob-shadow Decal on the seated-posture transition (see seated_hide_shadow). Editor-
## guarded so a @tool preview can never bake a hidden shadow into the authored scene; null-safe when the host has
## no "Shadow" child.
func _sync_shadow(sitting: bool) -> void:
	if not seated_hide_shadow or Engine.is_editor_hint():
		return
	var host := get_parent()
	if host == null:
		return
	var sh := host.get_node_or_null(^"Shadow") as Node3D
	if sh != null:
		sh.visible = not sitting

func _apply_posture_transforms() -> void:
	_apply_body_transform()
	_apply_head_transform()
	_apply_arm_transform()
	_apply_leg_transform()
	_bob_head = null

## Kick off the fist strike: the arms swing through arm_strike_pitch / arm_strike_thrust, shaped by
## arm_strike_curve, then settle back to their rest pose over arm_strike_duration.
##
## TWO callers, deliberately sharing one envelope: the NPC punch (scripts/npc/npc_combat.gd) on an
## animate_arms-ON rig, and the PLAYER's unarmed view-model hands (via GunMesh.fire) on an animate_arms-OFF
## one. Takes no arguments so both can call it duck-typed by name.
##
## `lead` picks the fist: +1 LEFT, -1 RIGHT, 0 (the default) = let arm_strike_alternate decide. The player
## binds it to the mouse — left click throws the left fist, right click the right — while the NPC calls
## strike() bare and keeps the shipped alternating/two-fisted behaviour.
##
## Suppressed while a gun is out on an animated rig (an NPC holding a rifle should not throw hands); the
## strike-only path has no such gate, because a rig that reaches it has no gun to be holding.
func strike(lead: float = 0.0) -> void:
	if lead > 0.0:
		_strike_side = 1.0    # LEFT fist leads
	elif lead < 0.0:
		_strike_side = -1.0   # RIGHT fist leads
	elif arm_strike_alternate:
		_strike_side = -_strike_side
	_strike_t = 1.0


## The strike envelope's amplitude at `t` (1 = the instant of the punch, 0 = fully recovered), shaped by an
## optional authored Curve. Pure + static so the shape can be unit-tested without a node or a scene.
##
## The curve is sampled on ELAPSED fraction (1 - t), so x reads left-to-right as time since the punch. y is
## unclamped on purpose: below 0 is anticipation (the fist pulls back), above 1 is overshoot.
static func strike_amplitude(t: float, curve: Curve) -> float:
	if curve == null:
		return smoothstep(0.0, 1.0, t)  # legacy NPC shape: full amplitude immediately, then ease out
	return curve.sample_baked(clampf(1.0 - t, 0.0, 1.0))

## Drop the arms to their by-side REST pose NOW and clear every raised-arm state (weapon-hold pitch, walk swing,
## fists-out sway, strike flail). Called by the host NPC on entering dialogue (NPC.set_in_dialogue): the world
## PAUSES for the conversation, which halts _animate_limbs, so a gun-hold / fists-out / airborne pose would
## otherwise FREEZE raised for the whole chat. Snapping the arms down here means an NPC you talk to always lowers
## its arms; once the conversation ends and _animate_limbs resumes, it eases them back up if still armed + close.
## Safe with no arms swapped in (the _apply_arm_transform writes are is_instance_valid-guarded).
## A SEATED speaker instead holds the seated arm pose: the world-pause freezes _animate_limbs, so snapping to the
## standing by-the-side rest would leave a ground-level sitter's arms stabbed through the floor for the whole
## conversation. _apply_arm_transform is posture-aware, so the seated pitch is what the static write lands on.
## Deliberately the LAP pitch (_seated_pitch_clamped of seated_arm_pitch), never _seated_arm_pitch_eff(): an armed
## NPC you strike up a conversation with must put the gun down out of the way, and this runs from
## NPC.set_in_dialogue() — possibly before DialogueManager has published the speaker, so the gun-hold pose's own
## dialogue gate can't be relied on for this one call.
func lower_arms() -> void:
	_mode_pitch = _seated_pitch_clamped(seated_arm_pitch) if _host_sitting() else 0.0
	_swing_blend = 0.0
	_fists_sway = 0.0
	_strike_t = 0.0
	_apply_arm_transform()

## The Man.glb instance to hide: the wired override, else the NPC's "Body" sibling.
func _target_body() -> Node3D:
	if is_instance_valid(default_body):
		return default_body
	var p := get_parent()
	return p.get_node_or_null(^"Body") as Node3D if p != null else null

## The mesh subtree to KEEP visible: nothing once we own the head (an effective head model -> hide all Man.glb
## meshes), else the Man.glb's own "Head" subtree under the body -- so a BODY-ONLY swap keeps the default head.
func _keep() -> Node:
	if _eff_head()["model"] != null:
		return null
	var b := _target_body()
	return b.get_node_or_null(^"Head") if b != null else null

# --- Per-NPC appearance override (the BodyModelSwap reads its host NPC root's body/head model fields) -----------

## The SOURCE of per-NPC appearance overrides: the host NPC's assigned `look` (an NpcLook resource) when it has
## one, else the host node itself (its inline flat fields). NpcLook MIRRORS the host's field names, so _host_part
## and _eff_*_color read whichever is in play uniformly via .get(field). Null host -> null (no override).
func _look_src() -> Object:
	var h := get_parent()
	if h == null:
		return null
	var lk: Variant = h.get(&"look")
	return lk if lk is NpcLook else h

## A part's effective look: the host's assigned `look` resource when it has one (see _look_src), else THIS node's
## own fields. The NPC root declares none of the mirrored names itself -- its 14 inline appearance fields were
## folded into NpcLook -- so "no look assigned" always resolves to this node's own defaults.
##
## THE LOOK WINS: when the look sets this part's MODEL, its model AND scale / position / rotation replace this
## node's for that part. That is why a pick made with apply_*_part on THIS node looks like a no-op on an NPC whose
## look overrides the same part -- PartLibrary.stamp_option pushes a warning naming the look when it sees that.
## The TEXTURE / COLOUR resolve INDEPENDENTLY of the model, so you can re-skin the default body without swapping
## its mesh; a swapped model with no look tex/colour shows its OWN material. Lets a designer retune an NPC's look
## by clicking it in the level (no "Editable Children"), with this @tool preview live.
func _host_part(model_f: StringName, scale_f: StringName, pos_f: StringName, rot_f: StringName, tex_f: StringName, col_f: StringName,
		own_model: Resource, own_scale: float, own_pos: Vector3, own_rot: Vector3, own_tex: Texture2D, own_col: Color) -> Dictionary:
	var h := _look_src()
	var ht: Variant = h.get(tex_f) if h != null else null
	var hc: Variant = h.get(col_f) if h != null else null
	var overridden := h != null and ModelResourceUtil.is_model(h.get(model_f))
	# Texture / colour resolve INDEPENDENTLY of the model: the host's when it sets one, else the swapped model's
	# OWN material (null / white) if the MODEL was overridden, else this node's own default skin.
	var tex: Texture2D = ht if ht is Texture2D else (null if overridden else own_tex)
	var col: Color = hc if (hc is Color and hc != Color.WHITE) else (Color.WHITE if overridden else own_col)
	if overridden:
		return {"model": h.get(model_f), "scale": float(h.get(scale_f)), "pos": h.get(pos_f), "rot": h.get(rot_f), "tex": tex, "col": col}
	return {"model": own_model, "scale": own_scale, "pos": own_pos, "rot": own_rot, "tex": tex, "col": col}

func _eff_body() -> Dictionary:
	return _host_part(&"body_model", &"body_model_scale", &"body_model_position", &"body_model_rotation", &"body_texture", &"body_color",
			body_model, body_model_scale, body_model_position, body_model_rotation, body_texture, body_color)

func _eff_head() -> Dictionary:
	return _host_part(&"head_model", &"head_model_scale", &"head_model_position", &"head_model_rotation", &"head_texture", &"head_color",
			head_model, head_scale, head_position, head_rotation, head_texture, head_color)

## Effective ARM / LEG tint: the host NPC's colour when it sets a non-white one, else this node's own (the shared
## default tint). The arm/leg MODEL + placement always stay this node's -- they're gait-animated, not host-swappable.
func _eff_arm_color() -> Color:
	var h := _look_src()
	var hc: Variant = h.get(&"arm_color") if h != null else null
	return hc if hc is Color and hc != Color.WHITE else arm_color

func _eff_leg_color() -> Color:
	var h := _look_src()
	var hc: Variant = h.get(&"leg_color") if h != null else null
	return hc if hc is Color and hc != Color.WHITE else leg_color

## Live-preview the host's body/head overrides while editing: re-instance on a MODEL change, just re-place on a
## transform / skin change (so dragging an offset doesn't thrash a full rebuild every editor frame).
func _editor_poll_host() -> void:
	var eb := _eff_body()
	var eh := _eff_head()
	if str(eb["model"]) + "|" + str(eh["model"]) != _host_model_sig:
		_rebuild()  # re-snapshots the signatures at its end
		return
	var xsig := _xf_sig(eb, eh)
	if xsig != _host_xf_sig:
		_host_xf_sig = xsig
		_apply_body_transform()
		_apply_body_texture()
		_apply_head_transform()
		_apply_head_texture()
		_apply_arm_transform()
		_apply_leg_transform()
		_apply_arm_texture()  # arm/leg COLOUR is host-overridable too (model/placement aren't)
		_apply_leg_texture()

## A string fingerprint of the resolved body+head transforms/skins + arm/leg tints, to detect a skin/placement
## edit without a full rebuild. The seated DROP is folded in (only while seated, so a standing rig never pays the
## capsule scan) because the editor preview now derives it from the host capsule — dragging a seated NPC onto a
## crate has to re-place the pose, and nothing else in this signature moves when the host does.
func _xf_sig(eb: Dictionary, eh: Dictionary) -> String:
	var sitting := _host_sitting()
	return str(eb["scale"]) + str(eb["pos"]) + str(eb["rot"]) + str(eb["tex"]) + str(eb["col"]) + \
		str(eh["scale"]) + str(eh["pos"]) + str(eh["rot"]) + str(eh["tex"]) + str(eh["col"]) + \
		str(_eff_arm_color()) + str(_eff_leg_color()) + str(sitting) + \
		str(_seated_drop_y() if sitting else 0.0)

## Re-instance the body + head previews and (un)hide the Man.glb meshes; re-point the NPC's head reference at our
## head (runtime). Tree-guarded so a setter firing during scene load (before children exist) is a no-op.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	for n in [_body, _head, _arm_left, _arm_right, _leg_left, _leg_right]:
		if is_instance_valid(n):
			n.queue_free()
	_body = null
	_head = null
	_arm_left = null
	_arm_right = null
	_leg_left = null
	_leg_right = null
	_arm_reach = -1.0  # a new arm model means a new reach — remeasure lazily on the next seated clamp
	_body_transp_touched = false  # fresh instances carry pristine materials — a 0-transparency rig skips the walk again
	_arm_transp_touched = false   # ...same for the arm pair
	_leg_transp_touched = false   # ...and the leg pair
	_set_meshes_visible(_target_body(), true)  # restore first, so clearing a model un-hides the Man.glb mesh
	var eb := _eff_body()
	var eh := _eff_head()
	if eb["model"] != null:
		var b: Node3D = ModelResourceUtil.instantiate(eb["model"], "BodyModel")
		if b != null:
			_body = b
			add_child(_body)  # UNOWNED on purpose: a live preview that isn't saved into the .tscn
			_apply_body_transform()
			_apply_body_texture()
	if eh["model"] != null:
		var h: Node3D = ModelResourceUtil.instantiate(eh["model"], "HeadModel")
		if h != null:
			_head = h
			add_child(_head)
			_apply_head_transform()
			_apply_head_texture()
	if arm_model != null:
		var arms := _instance_pair(arm_model, 1 if single_arm else 2)  # single_arm: LEFT only (a first-person view-model arm)
		_arm_left = arms[0]
		_arm_right = arms[1]
		_apply_arm_transform()
		_apply_arm_texture()
	if leg_model != null:
		var legs := _instance_pair(leg_model)
		_leg_left = legs[0]
		_leg_right = legs[1]
		_apply_leg_transform()
		_apply_leg_texture()
	# Hide the Man.glb meshes once a body or head is swapped in. NOTE: Man.glb is ONE skinned mesh (BaseHuman); its
	# head is a "Head" BONE, not a toggleable node -- so we can't node-hide just the head. Every shipped NPC swaps
	# in a body_model (torso.tscn), so eb.model is non-null and the whole rig hides cleanly; a head-only swap with
	# NO body_model isn't a supported config on this rig (it'd hide the body too -- there's no head mesh to keep).
	if eb["model"] != null or eh["model"] != null:
		_set_meshes_visible(_target_body(), false)
	_register_head()
	_apply_cast_shadow()  # re-instanced meshes inherit the current casts_shadow setting
	_apply_view_model_layer()  # ...and the view-model render layer, if this rig is a first-person part
	_apply_actor_outline()  # ...and the actor rim + its ink-mask bit, which a fresh mesh's reset `layers` just lost
	if Engine.is_editor_hint():  # snapshot the resolved look so the editor poll only rebuilds on an ACTUAL change
		_host_model_sig = str(eb["model"]) + "|" + str(eh["model"])
		_host_xf_sig = _xf_sig(eb, eh)
		update_configuration_warnings()  # the head-only-no-body warning depends on the resolved eb/eh models

## Editor warning: the rig can't do a head-only swap. Man.glb is ONE skinned mesh whose head is a BONE, so
## swapping in a head with no body hides the body too (there's no separate head mesh to keep). Flags the case
## where the EFFECTIVE head model is set but the EFFECTIVE body model is null -- resolving the host NPC's
## overrides exactly like the live preview (_eff_body / _eff_head), so a body supplied on the NPC root counts.
func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if _eff_head()["model"] != null and _eff_body()["model"] == null:
		w.append("Head model set with no body model — unsupported on this rig (Man.glb's head is a bone, so this hides the whole body). Set a body_model (here or on the NPC root), or clear the head model.")
	return w

## Instantiate a mirrored PAIR (arms or legs) from one model resource: returns [left, right], each a Node3D added as our
## child, or null when the resource cannot produce a Node3D. The caller mirrors [1].
func _instance_pair(model: Resource, count: int = 2) -> Array:
	var pair: Array = [null, null]
	for i in count:
		var n: Node3D = ModelResourceUtil.instantiate(model, "ModelPart")
		if n != null:
			pair[i] = n
			add_child(n)  # UNOWNED on purpose: a live preview that isn't saved into the .tscn
	return pair

func _apply_body_transform() -> void:
	if is_instance_valid(_body):
		var e := _eff_body()
		var sitting := _host_sitting()
		var pos: Vector3 = e["pos"]
		var rot: Vector3 = e["rot"]
		# _posture_offset (NOT the raw seated_visual_offset): the torso must ride the SAME ground-snapped drop as
		# the head/arms/legs, or a runtime sitter's body floats over its own hips at the old fixed offset.
		_body.position = pos + _posture_offset()
		_body.basis = _body_posture_basis(rot, sitting)
		_body_base_scale = float(e["scale"])  # cache the authored scale so runtime breathing pulses around it
		_body.scale = Vector3.ONE * _body_base_scale

## The torso's rotation for the current posture: the authored rotation, with the seated lean PRE-multiplied about
## swap-space X (the _leg_pose idiom). Euler-ADDING the pitch to rotation_degrees would pitch about the model's
## pre-yaw X axis instead — on a yawed torso (the shipped body is authored (0, -90, 0)) that reads as a sideways
## ROLL, not a lean.
func _body_posture_basis(rot_deg: Vector3, sitting: bool) -> Basis:
	var rest := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	return (Basis(Vector3.RIGHT, deg_to_rad(seated_body_pitch)) * rest) if sitting else rest

func _apply_head_transform() -> void:
	if is_instance_valid(_head):
		var e := _eff_head()
		var pos: Vector3 = e["pos"]
		_head.position = pos + _posture_offset()
		_head.rotation_degrees = e["rot"]
		_head.scale = Vector3.ONE * float(e["scale"])

## Where _apply_head_transform currently RESTS the swapped head (swap-local, posture-aware): the authored
## placement plus the live posture offset (seated drop / ground snap included). The head-look mount's neck-pivot
## hinge recomputes its origin shift around THIS every frame instead of a one-shot capture — without the live
## read, any posture change after the capture pins the head at a stale height (a seated head floating over the
## snapped body, a stood-up fighter's head sunk into its torso).
func head_rest_position() -> Vector3:
	var e := _eff_head()
	return (e["pos"] as Vector3) + _posture_offset()

## Place the LEFT arm from the exports, then make the RIGHT arm its mirror across the body centre (X=0) -- one arm
## model becomes a matched pair. The reflection (a negative-X basis) flips the geometry so it reads as the other hand.
## POSTURE-AWARE: a seated host's static rest is the seated pitch, not the standing hang — this is what an
## animate_arms-off rig, the editor's seated preview, and lower_arms() (a seated dialogue speaker) all land on.
func _apply_arm_transform() -> void:
	var rot := arm_rotation + Vector3(_seated_arm_pitch_eff() if _host_sitting() else 0.0, 0.0, 0.0)
	if is_instance_valid(_arm_left):
		_arm_left.transform = _arm_pose(rot + Vector3(arm_stride_deg, 0.0, 0.0))
	if is_instance_valid(_arm_right):
		_arm_right.transform = _reflect() * _arm_pose(rot + Vector3(-arm_stride_deg, 0.0, 0.0))

## One arm's local transform from its rotation (degrees) at the shoulder, sized by arm_scale.
## `extra_pos` is an additive local translation (the strike thrust); the RIGHT arm's copy is mirrored by the
## caller's _reflect(), which negates X only -- so a forward/up thrust stays forward/up on both hands.
func _arm_pose(rot_deg: Vector3, extra_pos: Vector3 = Vector3.ZERO) -> Transform3D:
	var b := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	return Transform3D(b.scaled(Vector3.ONE * arm_scale), arm_position + _posture_offset() + extra_pos)

## Place the LEFT leg at its rest pose, then mirror it across the body centre (X=0) for the RIGHT leg -- the same
## one-model-becomes-a-pair trick as the arms. POSTURE-AWARE: a seated host rests at seated_leg_pitch (legs out in
## front) instead of standing straight — so an animate_legs-off rig and the editor's seated preview never show a
## ground-snapped sitter with its standing legs jammed through the floor.
func _apply_leg_transform() -> void:
	var swing := seated_leg_pitch if _host_sitting() else 0.0
	if is_instance_valid(_leg_left):
		_leg_left.transform = _leg_pose(swing)
	if is_instance_valid(_leg_right):
		_leg_right.transform = _reflect() * _leg_pose(swing)

## One leg's local transform: the rest orientation (leg_rotation) SWUNG forward/back by swing_deg about the body's
## hip (X) axis, applied in BODY space (pre-multiplied) -- so the swing stays forward/back however leg_rotation
## yaws the model to point down. (Baking the swing into the model's local euler, like the arms do, sways the leg
## SIDEWAYS once it's yawed.) Sized by leg_scale at leg_position; the swing pivots about the model origin, so
## author leg.blend's origin at the hip.
func _leg_pose(swing_deg: float) -> Transform3D:
	var rest := Basis.from_euler(Vector3(deg_to_rad(leg_rotation.x), deg_to_rad(leg_rotation.y), deg_to_rad(leg_rotation.z)))
	var swung := Basis(Vector3.RIGHT, deg_to_rad(swing_deg)) * rest
	return Transform3D(swung.scaled(Vector3.ONE * leg_scale), leg_position + _posture_offset())

## Reflection across the body's centre plane (X=0) -- turns a left-arm pose into the mirrored right arm.
func _reflect() -> Transform3D:
	return Transform3D(Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0)), Vector3.ZERO)

func _apply_body_texture() -> void:
	var e := _eff_body()
	# A drawn shirt (body_texture_planar) projects flat onto the chest instead of sampling the mesh's atlas UVs.
	# Only the swap's OWN texture takes the planar path — a host-look override is an authored atlas texture.
	if body_texture_planar and e["tex"] != null and e["tex"] == body_texture:
		_skin_planar(_body, e["tex"], e["col"])
	else:
		_skin(_body, e["tex"], e["col"])  # skins the swapped body model (every shipped NPC has one; texture re-skins it in place)
	_apply_body_transparency()  # LAST: _skin may have swapped the override, so the see-through re-wraps whatever won

## Push body_transparency onto every mesh under the body instance as DITHERED (alpha-hash) see-through. Zero
## with no prior application is a pure no-op (the every-NPC path). Each touched material is a per-instance
## duplicate tagged with meta, so repeat applications mutate OUR copy instead of stacking duplicates, and a
## return to 0 RESTORES solid on those same copies.
func _apply_body_transparency() -> void:
	if body_transparency <= 0.0 and not _body_transp_touched:
		return
	if not is_instance_valid(_body):
		return
	_body_transp_touched = _body_transp_touched or body_transparency > 0.0
	_see_through_walk(_body, body_transparency)

## The same, for the ARM pair (arm_transparency) — so the player's first-person body arms dissolve with the
## torso they hang off instead of floating on after it fades. Same early-out, same latch, same duplicates.
func _apply_arm_transparency() -> void:
	if arm_transparency <= 0.0 and not _arm_transp_touched:
		return
	_arm_transp_touched = _arm_transp_touched or arm_transparency > 0.0
	for arm in [_arm_left, _arm_right]:
		if is_instance_valid(arm):
			_see_through_walk(arm, arm_transparency)

## ...and for the LEG pair (leg_transparency). Third verse, same as the second — see the export's own note for
## why the legs needed a fade channel of their own.
func _apply_leg_transparency() -> void:
	if leg_transparency <= 0.0 and not _leg_transp_touched:
		return
	_leg_transp_touched = _leg_transp_touched or leg_transparency > 0.0
	for leg in [_leg_left, _leg_right]:
		if is_instance_valid(leg):
			_see_through_walk(leg, leg_transparency)

## Stamp `amount` of dithered see-through onto every MeshInstance3D under `root`, over WHATEVER material path
## that mesh took — the _skin override or the model's own baked surface materials.
func _see_through_walk(root: Node, amount: float) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.push_back(child)
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		if mi.material_override != null:
			mi.material_override = _see_through_variant(mi.material_override, amount)
		elif mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var base := mi.get_surface_override_material(s)
				if base == null:
					base = mi.mesh.surface_get_material(s)
				var variant := _see_through_variant(base, amount)
				if variant != null:
					mi.set_surface_override_material(s, variant)

## A per-instance duplicate of `mat` carrying `amount` of see-through (alpha-hash + albedo alpha). The
## planar drawn-shirt override is special-cased: it is a ShaderMaterial (already per-mesh, no duplication
## needed) whose shader carries a matching `see_through` dither uniform — without this branch a custom-shirt
## player's torso would silently stay OPAQUE through the crouch fade. FOREIGN ShaderMaterials (e.g. a
## PS1-pass shader) are left alone, and null stays null. The meta tag marks OUR BaseMaterial3D duplicates so
## they're mutated in place on later applications.
##
## ⭐The tag name is `bms_body_transp` but it tags ARM copies too, and that is LOAD-BEARING, not laziness:
## BodyPartGib._walk_strip finds every faded material by exactly this tag to force a flying limb back to solid
## (a crouched death would otherwise fling near-invisible parts). Giving arms their own tag name would silently
## exempt them from that strip. If you ever rename it, rename it there in the same change.
func _see_through_variant(mat: Material, amount: float) -> Material:
	var sm := mat as ShaderMaterial
	if sm != null:
		if sm.shader == ShirtPlanarShader:
			sm.set_shader_parameter(&"see_through", amount)
		return mat
	var bm := mat as BaseMaterial3D
	if bm == null:
		return mat
	if not bm.has_meta(&"bms_body_transp"):
		bm = bm.duplicate() as BaseMaterial3D
		bm.set_meta(&"bms_body_transp", true)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH if amount > 0.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	bm.albedo_color.a = clampf(1.0 - amount, 0.0, 1.0)
	return bm

func _apply_head_texture() -> void:
	var e := _eff_head()
	_skin(_head, e["tex"], e["col"])

func _apply_arm_texture() -> void:
	var c := _eff_arm_color()
	_skin(_arm_left, arm_texture, c)
	_skin(_arm_right, arm_texture, c)
	_apply_arm_transparency()  # LAST, the _apply_body_texture rule: _skin just swapped the override, so re-wrap whatever won

func _apply_leg_texture() -> void:
	var c := _eff_leg_color()
	_skin(_leg_left, leg_texture, c)
	_skin(_leg_right, leg_texture, c)
	_apply_leg_transparency()  # LAST, the _apply_body_texture rule: _skin just swapped the override, so re-wrap whatever won

## Apply casts_shadow to every spawned part's meshes, so re-instanced meshes inherit it after a rebuild.
func _apply_cast_shadow() -> void:
	var mode: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for root in [_body, _head, _arm_left, _arm_right, _leg_left, _leg_right]:
		_set_cast_shadow(root, mode)

## Recursively set cast_shadow on every GeometryInstance3D (MeshInstance3D etc.) under `node`.
func _set_cast_shadow(node: Node, mode: GeometryInstance3D.ShadowCastingSetting) -> void:
	if not is_instance_valid(node):
		return
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = mode
	for c in node.get_children():
		_set_cast_shadow(c, mode)

## Force every spawned mesh onto `view_model_layer` (a render-layer bitmask) when it's set (> 0), so a first-person
## body part (e.g. the player's left arm) draws in the dedicated view-model camera pass ON TOP of the world, with no
## wall clipping -- exactly like the gun. 0 (the default) leaves the models on their own layers, unchanged.
func _apply_view_model_layer() -> void:
	if view_model_layer <= 0:
		return
	for root in [_body, _head, _arm_left, _arm_right, _leg_left, _leg_right]:
		_set_render_layer(root, view_model_layer)

func _set_render_layer(node: Node, layers: int) -> void:
	if not is_instance_valid(node):
		return
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for c in node.get_children():
		_set_render_layer(c, layers)

## Stamp (or strip) the actor rim + its ink-mask layer bit on every spawned part. Called from _rebuild beside
## _apply_cast_shadow / _apply_view_model_layer, so freshly instanced parts are dressed before they are ever drawn,
## and from the toggle so the editor preview follows the tick box. See `actor_outline` for why the rim and the
## mask bit are ONE operation and can never be separated.
##
## The strip path is deliberate rather than "leave it to the next rebuild": this is a @tool component, so a
## designer un-ticking the box has to SEE the rim go. It only clears an overlay it recognises as its own (the
## `bms_actor_rim` meta — the bms_body_transp idiom), so it can never wipe an outline another system owns.
func _apply_actor_outline() -> void:
	# The _body_transp_touched idiom: a rig that has never worn the rim has nothing to strip either, so every NPC
	# (actor_outline off, forever) takes a zero-cost early-out on each of its rebuilds instead of walking its whole
	# mesh set to un-set a bit it never had — and can never have its overlay slot touched by this code at all.
	if not actor_outline and not _outline_touched:
		return
	_outline_touched = _outline_touched or actor_outline
	for entry in character_parts():
		var key: String = entry["key"]
		var root: Node3D = entry["node"]
		var mat: ShaderMaterial = _outline_material(key) if actor_outline else null
		for m in TalkHelpers.collect_meshes(root, null, true):
			if actor_outline:
				m.layers |= InkOutline.ACTOR_INK_MASK_LAYER
				m.material_overlay = mat
			else:
				m.layers &= ~InkOutline.ACTOR_INK_MASK_LAYER
				if m.material_overlay != null and m.material_overlay.has_meta(&"bms_actor_rim"):
					m.material_overlay = null

## Get-or-create the rim material for one part key. ONE PER PART rather than one shared, because their alphas
## diverge: the torso dissolves on the player's look-down / crouch fade, the arms take a third curve of their own
## (they also hide when the view model owns your hands), and the legs never fade at all. Persistent across
## rebuilds, like NpcOutline's per-part flash materials, so a model swap doesn't churn materials.
func _outline_material(key: String) -> ShaderMaterial:
	var mat: ShaderMaterial = _outline_mats.get(key, null)
	if mat == null:
		mat = TalkHelpers.make_outline_material(_outline_color_for(key), actor_outline_width)
		mat.set_meta(&"bms_actor_rim", true)  # so the strip path above can tell OUR overlay from anyone else's
		_outline_mats[key] = mat
	return mat

## The rim's live colour for one part: the authored tint with its alpha scaled by that part's OWN see-through, so
## the outline dissolves exactly in step with the geometry it wraps. Without this a crouched player would keep a
## solid black outline of the chest and arms that just dithered away — strictly worse than either extreme, the
## same failure the arm_transparency field was added to prevent for the geometry itself.
func _outline_color_for(key: String) -> Color:
	var solid := 1.0
	if key == "torso" or key == "head":
		solid = 1.0 - body_transparency
	elif key == "arm_l" or key == "arm_r":
		solid = 1.0 - arm_transparency
	elif key == "leg_l" or key == "leg_r":
		solid = 1.0 - leg_transparency
	var c := actor_outline_color
	c.a *= clampf(solid, 0.0, 1.0)
	return c

## Push the authored tint/width and the live see-through alpha onto every rim material. Idempotent and cheap (a
## couple of uniform writes over at most six materials); called from the two transparency setters, which is what
## keeps a fading part's outline fading with it. Zero cost on every rig that leaves actor_outline off.
func _apply_outline_uniforms() -> void:
	if not actor_outline:
		return
	for key in _outline_mats:
		var mat: ShaderMaterial = _outline_mats[key]
		if mat == null:
			continue
		mat.set_shader_parameter("outline_color", _outline_color_for(String(key)))
		mat.set_shader_parameter("outline_width", actor_outline_width)

## Override every MeshInstance3D under `root` with an albedo material from `tex` and/or `color` -- a texture OR any
## NON-WHITE colour builds the override (the colour tints the texture, or is a flat skin on its own). No texture +
## plain WHITE -> clear the override, restoring the model's own baked material (so WHITE is the "leave it" default).
func _skin(root: Node3D, tex: Texture2D, color: Color) -> void:
	if not is_instance_valid(root):
		return
	var tinted := color != Color.WHITE
	var mat: Material = null
	if tex != null or tinted:
		var sm := StandardMaterial3D.new()
		if tex != null:
			sm.albedo_texture = tex
		if tinted:
			sm.albedo_color = Color(color.r, color.g, color.b, 1.0)
		mat = sm
	_set_mesh_material(root, mat)

func _set_mesh_material(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for c in node.get_children():
		_set_mesh_material(c, mat)

## Skin `root` with the planar-projection shirt shader (a player-DRAWN texture pressed flat onto the chest — see
## body_texture_planar). Per-mesh materials: each MeshInstance3D gets its OWN ShaderMaterial parameterised by that
## mesh's local AABB, so VERTEX normalises into the drawing's 0..1 square whatever the mesh's size/origin.
func _skin_planar(root: Node3D, tex: Texture2D, color: Color) -> void:
	if not is_instance_valid(root):
		return
	_walk_planar(root, tex, Color(color.r, color.g, color.b, 1.0))

func _walk_planar(node: Node, tex: Texture2D, color: Color) -> void:
	var mi := node as MeshInstance3D
	if mi != null:
		mi.material_override = _planar_shirt_material(mi.mesh, tex, color) if mi.mesh != null else null
	for c in node.get_children():
		_walk_planar(c, tex, color)

func _planar_shirt_material(mesh: Mesh, tex: Texture2D, color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ShirtPlanarShader
	var aabb := mesh.get_aabb()
	# Height is local +Y; of the two horizontal axes, the WIDER one is shoulder-to-shoulder (a torso is wider than
	# deep) and the other points chest<->back. front_sign picks which side of the depth axis is the chest — the
	# shipped torso.tscn faces its local -X (it seats with yaw -90 onto the rig's +Z front), hence -1.0 on the
	# Z-wide branch. A different torso that prints mirrored/backwards tunes ONLY this pick, not the shader.
	var width_is_x := aabb.size.x >= aabb.size.z
	m.set_shader_parameter(&"aabb_min", aabb.position)
	m.set_shader_parameter(&"aabb_size", aabb.size.max(Vector3.ONE * 0.0001))
	m.set_shader_parameter(&"width_dir", Vector3(1, 0, 0) if width_is_x else Vector3(0, 0, 1))
	m.set_shader_parameter(&"depth_dir", Vector3(0, 0, 1) if width_is_x else Vector3(1, 0, 0))
	m.set_shader_parameter(&"front_sign", 1.0 if width_is_x else -1.0)
	m.set_shader_parameter(&"shirt_tex", tex)
	m.set_shader_parameter(&"tint", color)
	return m

## Point the NPC's head-look + sniper glint at our swapped head (runtime only -- npc.gd isn't @tool, so its
## methods don't run in the editor). Null when we own no head (the NPC's glint then uses the Man.glb head bone).
func _register_head() -> void:
	if Engine.is_editor_hint():
		return
	var host := get_parent()
	if host != null and host.has_method(&"register_swapped_head"):
		host.register_swapped_head(_head)

func _set_meshes_visible(root: Node, vis: bool) -> void:
	if root == null:
		return
	_walk_meshes(root, _keep(), vis)

func _walk_meshes(node: Node, keep: Node, vis: bool) -> void:
	if node == keep:
		return
	if node is MeshInstance3D:
		(node as MeshInstance3D).visible = vis
	for c in node.get_children():
		_walk_meshes(c, keep, vis)

## The custom model PARTS as {key, node} entries -- so the NPC can (a) rim each with the combat-outline overlay
## (the Man.glb meshes that carry the rim are hidden once we swap) and (b) flash the SPECIFIC part that's hit.
## Only valid (instanced) parts are returned. Keys: torso / head / arm_l / arm_r / leg_l / leg_r; the _l entries
## are the un-mirrored instance, the _r entries the mirrored side.
func character_parts() -> Array:
	var parts: Array = []
	if is_instance_valid(_body):
		parts.append({"key": "torso", "node": _body})
	if is_instance_valid(_head):
		parts.append({"key": "head", "node": _head})
	if is_instance_valid(_arm_left):
		parts.append({"key": "arm_l", "node": _arm_left})
	if is_instance_valid(_arm_right):
		parts.append({"key": "arm_r", "node": _arm_right})
	if is_instance_valid(_leg_left):
		parts.append({"key": "leg_l", "node": _leg_left})
	if is_instance_valid(_leg_right):
		parts.append({"key": "leg_r", "node": _leg_right})
	return parts
