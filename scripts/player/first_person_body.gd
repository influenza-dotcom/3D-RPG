class_name FirstPersonBody
extends Node

## The player's FIRST-PERSON BODY — everything of yourself you can SEE from behind the camera — lifted off
## player.gd as a scene-wired drop-in (the Landing idiom). Owns three things:
##   • the LEGS + TORSO rig (body-awareness): the NPC leg model + walk gait and the catalog's body-only torso
##     slice, rendered with real world depth on the main camera, wall-pitched while climbing.
##   • the carry HANDS / bare FISTS rig: the mirrored arm pair on the gun's view-model layer — the same hands
##     that hold a carried prop AND stand in as the unarmed "weapon" — with the whole draw/stow/guard/punch
##     machinery and its latches.
##   • the fists' procedural MOTION: the speed-and-direction-aware walk-bob, the idle breathing, and the four
##     pure statics behind them (fp_arm_stow_target / bob_cadence / bob_lean / advance_bob_phase).
##
## ⚠ It deliberately does NOT own the weapon half of the carry dance. Player._on_carry_changed keeps the
## GAMEPLAY half — the `_carrying` latch, the holster capture/restore, `draw_locked`, the stale-reservation
## release — and TAILS into on_carry_changed() here. ONE connection on PickupRay.carry_changed, on the Player:
## the cosmetic half's _unarmed_hands_wanted() reads `attack.holstered`, which the gameplay half restores
## SYNCHRONOUSLY first, so two separate connections would make the whole handoff connection-order dependent
## (this project has been burned by exactly that). The FISTS fallback const, `_rewield_in_flight` and the rest
## of the carry bookkeeping stay host-owned gameplay state; this component only READS them.
##
## THREE ORDERING CONTRACTS a refactor must not break:
##   1. build() is called from Player._ready, never from our own _ready — a child's _ready runs BEFORE its
##      parent's, and `host.appearance` is only mirrored from GameState inside Player._ready, so self-building
##      would tint the legs and stamp the torso from an empty appearance dict.
##   2. process_priority = -1 (see _ready): our pose ease must land BEFORE the arms rig's own
##      BodyModelSwap._process re-poses a mid-punch arm, an ordering the monolith got free as the rig's parent.
##   3. update_leg_wall_pose() is HOST-called from Player._physics_process — after the shadow blend is written,
##      and frozen by die()'s set_physics_process(false). A self-ticked _physics_process here would keep
##      pitching the legs through the death cinematic.
##
## Wiring: a `FirstPersonBody` child of Player.tscn with `host = NodePath("..")`, dragged onto the Player's
## `fp_body` export. The 11 authored fp_* overrides (the probe-tuned guard/carry pose) are authored on THIS
## node now — tests/test_first_person_body_wiring.gd pins them, because every historic FP bug was invisible at
## script defaults. Every host-reading entry point is null-guarded so an off-tree Player or a bare component
## built in a unit test never crashes.

## The Player this dresses. Wire to `..` in the scene; typed so `host.head` / `host.weapon_system` resolve
## statically. Null (a bare component in a test) makes every entry point a no-op.
@export var host: Player

@export_group("First-Person Body")
## Show your own legs in first person (body-awareness). They reuse the NPC leg model + walk gait, rendered with
## REAL world depth on the main camera (the gun keeps its separate view-model layer). Tune the offset/scale
## live on this node. The TORSO rides this same rig (first_person_torso below); the HEAD is never shown — it
## sits exactly where the camera is.
@export var first_person_legs: bool = true
## The leg model shown in first person (defaults to the same leg mesh the NPCs use).
@export var fp_leg_model: PackedScene = preload("res://assets/models/leg.blend")
## Uniform scale of each first-person leg.
@export var fp_leg_scale: float = 0.44
## Uniform scale of the WHOLE first-person body rig — every part, and every mount offset between them, together.
##
## ⭐⭐THIS EXISTS BECAUSE THE CAST DOES NOT FIT UNDER THIS CAMERA, and the arithmetic is worth keeping: the parts
## are the NPC's (that is the point — see first_person_body_arms), and an NPC's body measures **1.226 m** from the
## soles of its feet to the top of its chest. The player's eye sits **1.0 m** above the floor (Player.tscn authors
## Head at y ~0.014, i.e. on the player origin, and the capsule bottom is at exactly -1.0). 1.226 does not fit in
## 1.0 at ANY mount height: push the feet down to the floor and the chest closes over the lens; drop the chest
## clear of the lens and the feet go through the floor. Every previous attempt to fix one end by moving a single
## offset simply moved the failure to the other end — the legs ended up mounted 0.19 m ABOVE the top of the chest,
## which is what "my legs are drawn on top of my body" was.
##
## So the rig is scaled instead of re-stacked, which keeps the NPC's own part-to-part layout intact BY
## CONSTRUCTION (a scale can't reorder anything) rather than by three offsets agreeing with each other. The hard
## ceiling is k ≤ (1.0 − margin) / 1.226 ≈ 0.73, but 0.60 is what SHIPPED and the reason is framing, not fit: it
## reproduces the chest's old on-screen size and its old ~70° entry angle almost exactly, so the fix reads as
## "the parts are stacked right now" and not as "my whole body changed size". Measured at 0.60: chest top 0.245 m
## below the lens, feet 0.019 m above the floor, hip 0.017 m under the chest's bottom edge.
## Raise it and the chest climbs toward the near plane; lower it and you shrink into a doll.
## Re-run `scripts/tools/preview_fp_body_frame.gd` after ANY change here — it prints all three of those numbers
## (floor clearance, the hip-vs-chest stack, the forward reach) and renders the frame.
@export_range(0.3, 1.2, 0.01) var fp_body_scale: float = 0.60
## Where the WHOLE FP body rig sits relative to the player origin (the eye) — the mount every part hangs off.
##
## ⭐This is a MEASURED value, not a taste one, and it is the one knob here you should not eyeball. The rig's feet
## sit 0.984 m below its origin AT FULL SIZE (the NPC body model's own proportions), so scaled they sit
## `0.984 × fp_body_scale` below it; the player's floor is the capsule bottom at exactly -1.0. That makes the
## whole formula `-1.0 + 0.984 × fp_body_scale + clearance`, and -0.39 is that at the shipped 0.60 with ~2 cm of
## clearance — which is what you want over a slope or a stair riser rather than feet welded to the plane.
## **It is paired with fp_body_scale: retuning the scale without recomputing this buries the feet or floats them.**
@export var fp_leg_offset: Vector3 = Vector3(0.0, -0.39, 0.0)
## Show your own TORSO under the camera too — look down and you see your chest, not just legs. Resolved from
## your character-creation appearance through the SAME catalog slice the customizer uses (chosen body model;
## a drawn shirt planar-projects untinted, else the skin tint), but BODY-ONLY: no head (it would sit inside
## the camera) and no catalog arms (the hands are the separate view-model rig). A whole_body appearance skips
## the FP torso — a one-piece character model can't have its head chopped off. Rides the legs rig.
@export var first_person_torso: bool = true
## FP-specific nudge ADDED to the catalog body's authored position (rig-local metres, so it is scaled by
## fp_body_scale along with everything else; the rig itself already hangs fp_leg_offset below the camera).
## LIVE-tunable: tracked every frame, so drag it in the editor's Remote inspector while playing.
##
## ⭐ZERO is the right default and means "wear the chest exactly where an NPC wears it". It used to carry -0.65,
## which sank the torso until its top was 0.19 m BELOW the leg hips — your own legs rendered on top of your chest.
## The fix for a body that doesn't fit under the lens is fp_body_scale, NOT a nudge here: this offset moves ONE
## part out of the arrangement the catalog authored, so anything it buys at the chest it takes from the join.
@export var fp_torso_offset: Vector3 = Vector3(0.0, 0.0, 0.0)
## See-through of the FP torso once it IS revealed (0 = solid, the shipped look; raise it for a permanent
## Odyssey-style ghost). Draws as a DITHERED screen-door — the retro stipple, never smooth alpha.
@export_range(0.0, 1.0, 0.01) var fp_torso_transparency: float = 0.0
## ⭐⭐THE WHOLE VISIBILITY RULE, and it is deliberately the dumbest one that works: **your body is INVISIBLE
## until you look down at it.** Above this many degrees below the horizon it is simply not drawn; from here it
## dithers in, and by fp_body_reveal_full_deg it is solid.
##
## This replaced a much cleverer scheme and the reason is worth keeping. The rule used to be the other way up —
## solid by default, dissolving only once you buried your look — which is correct ONLY if the body is out of
## frame whenever you are not looking at it. It is not. Your eyes are 1.0 m off the floor, the chest tops out
## 0.245 m below them, and at a wide FOV that chest sits barely outside the frustum edge at level pitch; then
## the landing dip (up to 1.0 m), the stair step-smoothing (up to 0.7 m), the crouch (0.61 m) and the walk-bob
## (0.075 m) each drop the LENS toward a body that has not moved. Two rounds went into chasing those four
## sources with sinks and metre-sized dissolve bands, and the player still saw their own chest while running,
## crouching and climbing stairs. **A gate on the LOOK cannot be defeated by anything that moves the camera**,
## which is why it is the pragmatic answer: there is no threshold to size, no FOV to track, and no fourth
## offset that can be forgotten later.
##
## Tune with the Remote inspector while playing — the reveal tracks these every frame.
@export_range(0.0, 89.0, 0.5, "degrees") var fp_body_reveal_start_deg: float = 50.0
## ...and FULLY visible by this angle. The band between eases it in with the look itself, so there is no pop.
## Applies to the whole body — torso, arms AND legs — so they can never disagree about whether you are looking.
@export_range(0.0, 89.0, 0.5, "degrees") var fp_body_reveal_full_deg: float = 70.0
## Show your own ARMS on your own BODY — the pair every character in the cast wears, hanging off the FP torso at
## REAL world depth on the main camera, so looking down shows arms attached to your chest and world geometry
## occludes them correctly. Body AWARENESS, and a completely separate rig from the view-model hands below
## (first_person_arms): those live under the camera on the gun's render layer and are the carry hold / the bare
## fists. These just hang there being your arms. They ride the legs rig, so they inherit body yaw (never camera
## pitch — your arms must not swing up when you look up) and the same shadow suppression.
##
## The MOUNT is not authored here: it comes from the appearance catalog's own arm_model / arm_scale /
## arm_position / arm_rotation — the exact rows CharacterAppearanceCatalog.configure_swap stamps onto every NPC.
## That is what makes this "arms like an NPC has arms" by construction rather than by a copied number that
## silently drifts the first time the cast's proportions are retuned. Tune the mount in
## resources/characters/PlayerAppearanceCatalog.tres (it moves everyone, which is correct — they are the same
## arms on the same body) and use fp_body_arm_offset below for anything first-person-specific.
@export var first_person_body_arms: bool = true
## FP-specific nudge ADDED to the catalog's authored arm_position (rig-local metres, so fp_body_scale scales it
## too) — the fp_torso_offset idiom, and zero because the catalog mount already sits these arms on this torso.
## Reach for it only when the first-person view needs the shoulders somewhere the third-person/portrait body does
## not. LIVE-tunable — tracked every frame, so drag it in the editor's Remote inspector while playing. Spelled as
## a LITERAL rather than Vector3.ZERO on purpose: the frame probe reads these defaults as .tscn-style text and
## str_to_var can't parse a constant name — the same rule the rest of this file's Vector3 exports already follow.
##
## ⭐It used to carry -0.55 as a counterweight to a leg-offset change; that is gone with the whole compensate-one-
## part-against-another approach. See fp_torso_offset and fp_body_scale.
@export var fp_body_arm_offset: Vector3 = Vector3(0.0, 0.0, 0.0)
## FP-only MULTIPLIER on the catalog's arm_scale — a length knob kept because the catalog's own scale is shared
## with every NPC and must not move for a first-person framing decision.
##
## ⭐1.0 (NPC parity) is now correct and was not before. It sat at 0.78 because at full catalog length the hanging
## hands reached 0.13 m BELOW the floor — but that was the whole rig being too big for this camera, which
## fp_body_scale now handles for every part at once. Shortening the arms alone made them the one part of you that
## wasn't NPC-proportioned. Re-run the frame probe if you move it; the clearance must stay ≥ 0.
@export_range(0.3, 1.5, 0.01) var fp_body_arm_scale_mult: float = 1.0
## How far (degrees at the shoulder) your arms SWING as you walk — the antisymmetric arm-pump every NPC does,
## at a cadence the legs rig already matches to your real speed (velocity_driven_legs), fading to a dead hang
## when you stop. Defaults to BodyModelSwap's own value, so your arms walk like everyone else's; this knob exists
## because the whole FP body rig is code-built, so its motion has no Inspector row of its own. 0 = arms that
## hang perfectly still, which reads as a mannequin from first person — lower it, don't kill it.
@export_range(0.0, 60.0, 0.5, "degrees") var fp_body_arm_swing_deg: float = 35.0
## Hide the body arms whenever the VIEW-MODEL rig owns your hands, so only one pair of arms is ever on screen.
## That means: a weapon DRAWN (the gun or the raised fists are what your arms are doing now), and also a carried
## prop (hands full — the view-model hands are visibly holding it). Holster the weapon and put the prop down and
## your real arms fade back in at your sides. Off = the arms are always present, which double-arms you the moment
## you look down with anything drawn. They dissolve on the same dithered screen-door as the torso, not a pop.
@export var fp_body_arms_hide_when_drawn: bool = true
## How fast that hide/reveal dissolves (per-second exponential rate; higher = snappier). The default is paced to
## read alongside the weapon's own ~0.35 s holster swing rather than racing it.
@export var fp_body_arms_hide_fade: float = 8.0
## Wear the black ACTOR OUTLINE — InkOutline's screen-space ring, the one outline every NPC, prop and view model
## in this game wears — on your own first-person body, and (the same switch, inseparably) keep the world's
## screen-space INK outline off it. Both halves live on the rig itself (BodyModelSwap.actor_outline), because that
## component RESETS the render layers of the meshes it spawns and so is the only place a stamp survives a model
## swap.
##
## ⭐OFF is not "no outline", it is THE WRONG outline. Your body is an actor at real world depth, so InkOutline's
## edge detect finds its silhouette exactly like a wall's and draws the world's line on it; the ring is what tells
## the ink pass "an actor already owns this pixel". Turning this off gives you the world line ALONE — a scribbly
## per-crease treatment where every NPC beside you wears a clean constant-width one. See
## scripts/effects/ink_outline.gd, "the ring owns actors, ink owns the world".
##
## ⭐ There is no colour or width knob beside this any more (the `fp_body_outline_color` / `fp_body_outline_width`
## exports went with the inverted hull on 2026-08-27). A ring resolves one id to one global LUT slot, so your
## body's line is InkOutline.highlight_neutral at InkOutline.highlight_width_px — the same black, at the same
## weight, as the NPC standing next to you, which is what it was always pinned to by hand anyway.
@export var first_person_body_outline: bool = true
## Tint for both legs (WHITE = the model's own colour). Character creation will override this per-save later.
@export var fp_leg_color: Color = Color(0.486, 0.184, 0.224)
## How far (degrees) the first-person legs LEAN toward the wall they're clinging to, at a full wall-climb cling.
## Keep it SMALL — the rig pivots at the hip, so a big angle drives the FEET through the wall (75° buried them).
## The direction comes from the actual wall normal, so they angle at the real surface no matter which way you look;
## this only sets how far. Lower it toward 0 if the feet still clip into the wall. PLAYTEST + TUNE.
@export var fp_leg_wall_pitch: float = 20.0
var _fp_legs: BodyModelSwap = null
## Show your own HANDS holding a carried object in first person. They appear ONLY while you're carrying a physics
## prop (PickupRay.held_object): grabbing one HOLSTERS the weapon first, then the hands come out; dropping it hides
## the hands and restores the weapon. Rendered in the gun's view-model camera pass (no wall clipping), parented to
## the camera. PLAYTEST + TUNE the offset/spread/rotation/scale below to frame the held object.
@export var first_person_arms: bool = true
## The arm model for the hands (defaults to the same arm mesh the NPCs use).
@export var fp_arm_model: PackedScene = preload("res://assets/models/arm.blend")
## Uniform scale of each hand/arm.
@export var fp_arm_scale: float = 1.0
## Where the arm rig sits relative to the camera -- forward + down, toward where a held prop floats. This is the
## CARRY rest; while the bare fists are up the rig rests fp_arm_unarmed_nudge away from here instead. TUNE.
@export var fp_arm_offset: Vector3 = Vector3(0.0, -0.16, -0.4)
## Sideways spread of the pair (the LEFT hand's shoulder X; the RIGHT mirrors across X). Bigger = hands further apart.
@export var fp_arm_spread: float = 0.2
## Rotation (degrees) of the arms -- pitch the forearms forward to reach the object. TUNE alongside the offset.
@export var fp_arm_rotation: Vector3 = Vector3(-35.0, 0.0, 0.0)
## Tint for the arms (WHITE = the model's own colour). Defaults to match the first-person legs' skin.
@export var fp_arm_color: Color = Color(0.486, 0.184, 0.224)
## Seconds to wait after the weapon holsters before the hands appear, so the holster reads first. TUNE.
@export var fp_arm_draw_delay: float = 0.18
## Seconds the hands take to SLIDE up into frame on draw (and back down out of frame on stow), instead of popping
## in/out instantly. Paired with fp_arm_draw_rise below. 0 -> effectively instant. TUNE.
@export var fp_arm_draw_time: float = 0.22
## How far (m) BELOW the carry rest (fp_arm_offset — the LOWER of the two rests) the hands start a hidden draw and
## end the stow — the bottom of the slide, just out of frame under the camera. Bigger = they rise from / sink to
## further down. TUNE with fp_arm_draw_time.
@export var fp_arm_draw_rise: float = 0.35
## Show the SAME hands as your permanent UNARMED "weapon" — bare fists when nothing is equipped, instead of a
## mounted weapon mesh. Off = unarmed shows nothing in first person. The punch knobs below shape the swing.
@export var fp_arm_unarmed: bool = true
## How the hands' REST moves off fp_arm_offset while the bare fists are up (camera-local metres). The guard's
## geometry is counter-intuitive and was tuned by RENDERING it (the fists-frame probe, 2026-08-05): the
## shoulders DROP (negative Y) while fp_arm_unarmed_tilt_deg swings the arms steeply up, so the fists rise into
## the lower third FORESHORTENED — which is what actually reads as "fists close to your face". Raising Y
## instead lifts the whole extended arm and reads as reaching into the distance (the mistake this replaces).
## RELATIVE on purpose — re-tuning the carry rest moves both poses together. Framed so the fists FLANK the
## crosshair just below it, aim always visible in the gap between them.
@export var fp_arm_unarmed_nudge: Vector3 = Vector3(0.0, -0.13, 0.12)
## Upward pitch (degrees, about the camera's X axis) of the whole rig while the bare fists are up. THE load-
## bearing "closer" knob: at steep angles the arms FORESHORTEN and the fists swing up toward the lens — big,
## near, knuckles-first. Shallow values (~10) read as reaching, not guarding. Zero while carrying a prop.
## LIVE-TUNABLE: the up pose tracks this every frame (see _update_fp_arm_bob), so drag it in the editor's
## REMOTE inspector while playing and the guard follows — same for the nudge/scale/spread knobs around it.
@export_range(0.0, 80.0, 0.5, "degrees") var fp_arm_unarmed_tilt_deg: float = 45.0
## Uniform scale MULTIPLIER on the arms while the bare fists are up — a final size boost on top of the
## foreshortening. Eased at the slide's pace from _update_fp_arm_bob (never property-tweened — the setter
## ordering would stomp punches). 1 = same size as the carry hands.
@export_range(0.7, 2.0, 0.01) var fp_arm_unarmed_scale_mult: float = 1.15
## Sideways spread of the fist pair while the bare fists are up (the carry hold keeps fp_arm_spread). Wider
## than the carry reach, so the two fists read as distinct and the crosshair stays visible in the gap between
## them. Eased alongside the scale — same setter-ordering rule, see _update_fp_arm_bob.
@export_range(0.05, 0.5, 0.005, "suffix:m") var fp_arm_unarmed_spread: float = 0.28
## Walk-bob travel (metres) for the bare fists — how far they trace the footstep figure-eight AT THE FULL RUN
## TIER (it scales down with your speed from there), the same motion GunPose gives every mounted weapon and
## behind the same view_bob_enabled accessibility gate. The two knobs below make this rig's bob speed- and
## direction-aware in ways GunPose's is not. Fists-only: the carry hold stays planted on the held prop.
## 0 = rock steady and moots the two knobs below — zero amplitude hides the cadence knob (a pure rate ratio,
## no travel term), and the lean (the only one expressed relative to this travel) collapses to zero.
@export var fp_arm_unarmed_bob_pos: float = 0.007
## How much the walk-bob's CADENCE follows your speed: 0 = the flat authored rate at every speed (exactly the
## behaviour this replaced), 1 = fully proportional, so the footstep rate is bob_speed × your fraction of the
## run tier. Amplitude has always scaled with speed, but on its own it only changed the SIZE of the pump — a
## walk and a sprint traced the same figure-eight at the same rate, which reads as one gait at two volumes.
## A bhop-boosted sprint pumps FASTER than the run tier; the rate is clamped in proportion to this knob so it
## can never strobe. See FirstPersonBody.bob_cadence.
@export_range(0.0, 1.0, 0.05) var fp_arm_unarmed_bob_speed_gain: float = 0.7
## How far the fists LEAN AGAINST the direction you're moving, as a MULTIPLE of fp_arm_unarmed_bob_pos:
## x = sideways at a full-speed strafe (strafe right, the pair drifts left), y = depth at a full-speed run
## (run forward and they trail back toward the lens; backpedal and they press away from it). Inertia — the
## same read the corner HUD gets from HudSway.velocity_target. RELATIVE to the bob travel on purpose (the
## fp_arm_unarmed_nudge idiom): every travel knob on this rig is DEPTH-COUPLED to the guard pose, so a lean
## authored in absolute metres would quietly stop reading the next time the guard or the bob is retuned.
## Tops out at the run tier. 0 = direction-blind (the bob before this knob existed).
@export var fp_arm_unarmed_lean_mult: Vector2 = Vector2(0.6, 0.4)
## Walk-bob roll (degrees): how much the fists rock left/right with each footstep. Scales with speed, like the travel.
@export var fp_arm_unarmed_bob_roll_deg: float = 0.6
## ASYMMETRIC walk-stride (degrees): the fists ALTERNATE — left rises as right falls, the natural arm-pump —
## on top of the whole-rig bob, at the footstep cadence. Scales with speed like the bob; 0 = the pair moves
## strictly together. Fists-only (the carry hold stays planted on the prop).
@export_range(0.0, 30.0, 0.5, "degrees") var fp_arm_unarmed_stride_deg: float = 7.0
## How fast the bob's amplitude blends in on a fists draw and back out on a stow / carry grab (per-second
## exponential rate; higher = snappier). Also paces the walk↔idle crossfade between the bob and the breathing.
@export var fp_arm_unarmed_bob_fade: float = 8.0
## Idle BREATHING rise/fall (metres) for the fists while you stand still — the hands lift and settle with the
## breath, plus a slower quarter-strength sideways drift at an offset frequency so they wander a little instead
## of pumping like a metronome. Fades out while walking (the walk-bob takes over) and back in when you stop.
## Runs even with View Bobbing off, exactly like the gun's breathing — micro-motion, not travel. 0 = statue hands.
@export var fp_arm_unarmed_breath_pos: float = 0.006
## Breathing pitch (degrees): how much the fists tip forward/back with each breath cycle.
@export var fp_arm_unarmed_breath_deg: float = 1.0
## Breathing pace (phase advance per second — GunPose's breath_speed idiom). Higher = quicker, more worked-up.
@export var fp_arm_unarmed_breath_speed: float = 1.6
## Pitch (degrees) the punching fist swings through, on top of fp_arm_rotation. Negative throws it forward/up.
@export var fp_arm_punch_pitch: float = -35.0
## Seconds one punch takes, start to fully settled. Must stay under the weapon's attack_speed (fists: 1.2 s) or
## spamming attack restarts the swing before it ever completes.
## ⭐ Since 2026-09-02 the cadence to compare against is the WIELDER'S, not the weapon's: AGILITY compresses a melee
## swing (Attack.effective_attack_speed), so the real lower bound is GameSettings.weapon_general
## .min_melee_attack_speed — authored at 0.35 s precisely to sit above this field's 0.32 s default. Retune the two
## TOGETHER; tests/test_managers_tuning.gd::test_weapon_general_settings_agility_floors pins the relationship.
@export var fp_arm_punch_duration: float = 0.32
## How far the punching fist THRUSTS, in camera space: -Z is forward (AWAY from the lens), -X pulls it inward
## toward screen centre. From the steep guard the swing pitches the fist down-forward toward the crosshair.
## Keep the reach PROPORTIONATE to the guard's rig depth (fp_arm_offset.z + fp_arm_unarmed_nudge.z, ~1.75 m
## on the authored Player.tscn pose): deep as that shoulder sits, the fists still ride only ~1 m in front of
## the lens (docs/AUTHORING_GUIDE.md "depth-coupled"), so an over-deep lunge can swing arm geometry through
## the near clip plane. This DEFAULT is the old ~0.23 m guard's tuning — the FirstPersonBody child's override
## is the live reach. After any big guard retune, sanity-check a punch by eye (or re-run the frame probe)
## rather than trusting the numbers.
@export var fp_arm_punch_thrust: Vector3 = Vector3(-0.03, 0.02, -0.14)
## Amplitude shape over the punch's ELAPSED fraction (x 0 = the swing's start, x 1 = settled; y = amplitude,
## and y BELOW zero is an anticipation pull-back). Null = a flat snap-out-then-ease with no wind-up.
@export var fp_arm_punch_curve: Curve = preload("res://resources/tuning/punch_strike_curve.tres")
## Auto-alternate the leading fist. OFF by default because the MOUSE picks the hand — left click throws the
## left fist, right click the right. Turn it on only if you unbind the second attack button.
@export var fp_arm_punch_alternate: bool = false
## How much the NON-punching hand joins in (0 = it holds its guard, 1 = both fists swing together).
@export var fp_arm_punch_offhand: float = 0.12
var _fp_arms: BodyModelSwap = null
var _unarmed_hands_up: bool = false  ## latch: the fists are up as the unarmed "weapon" (NOT the carry hold — see refresh_unarmed_hands)
var _fp_arm_tween: Tween = null  ## the in-flight hands slide (draw up / stow down); killed before starting a new one
var _fp_arm_stowing: bool = false  ## a stow slide is running: FREEZE the pose ease (tilt/scale/spread) so the fists sink out AS fists instead of morphing into the carry reach on screen
var _fp_arm_bob_mount: Node3D = null  ## camera-child wrapper the fists' walk-bob writes — the rig's OWN position stays the tweens'
var _fp_bob_time: float = 0.0  ## footstep bob phase, advanced while moving at the SPEED-SCALED cadence (bob_cadence); WRAPPED to TAU*2 — see _update_fp_arm_bob
var _fp_bob_amp: float = 0.0   ## eased walk-bob amplitude (speed × grounded). EASED, never stepped: a one-frame is_on_floor() blip must not snap the arm-pump
var _fp_bob_gate: float = 0.0  ## eased 0→1 "fists are up" amplitude gate so the bob fades in/out instead of snapping
var _fp_breath_time: float = 0.0  ## breathing sine phase, advanced at fp_arm_unarmed_breath_speed (GunPose parity)
var _fp_breath_t: float = 0.0  ## eased 0→1 idle-breathing blend — fades out while walking/airborne, like GunPose's
var _fp_torso_catalog_pos: Vector3 = Vector3.ZERO  ## the catalog body's authored position — fp_torso_offset and the crouch sink ADD to it
var _fp_arm_catalog_pos: Vector3 = Vector3.ZERO  ## ...and the catalog's authored arm_position, the same way for fp_body_arm_offset
var _fp_body_arm_hide_t: float = 0.0  ## eased 0→1 "the view model owns my hands" dissolve for the BODY arms (see _fp_body_arms_hidden)
var _fp_head_standing_y: float = 0.0  ## Head's standing local Y, cached at rig build — the live delta below it IS the crouch drop the torso mirrors


func _ready() -> void:
	# TICK BEFORE THE ARMS RIG — the strike-vs-ease ordering contract. The pose ease in _update_fp_arm_bob
	# writes arm_scale / arm_position / the rest transform through setters that re-pose the arms to REST, and
	# the punch's strike envelope (BodyModelSwap._process on the arms rig) must run AFTER those writes each
	# frame so a mid-punch arm wins — this is the setter-ordering fix documented at the ease site. On the
	# monolith that ordering came FREE (a parent's _process runs before its descendants', and the rig hung off
	# the Player); as a sibling component it has to be bought explicitly: process_priority = -1 beats every
	# default-0 node regardless of authored tree order (the node is ALSO authored before Head in Player.tscn —
	# belt and braces, since priority alone already guarantees it). This _process deliberately keeps ticking
	# through death, exactly as Player._process always did: die() stops only the PLAYER's physics processing,
	# and the death stow slide + torso fade need the frames.
	process_priority = -1


## The two per-frame drivers, in the monolith's exact order. Runs on the RENDER tick, after that frame's
## physics wrote host.velocity — any node's _process runs after the physics step, so "the bob reads velocity
## AFTER physics wrote it" is preserved by construction.
func _process(delta: float) -> void:
	_update_fp_arm_bob(delta)
	_update_fp_torso(delta)


## Build both rigs. Called by the HOST from Player._ready — never from our own _ready — because a child's
## _ready runs BEFORE its parent's, and `host.appearance` is only mirrored from GameState inside Player._ready:
## self-building here would tint the legs and stamp the torso from an empty appearance dict.
func build() -> void:
	if host == null:
		return
	_build_first_person_legs()
	_build_first_person_arms()


## Build the first-person BODY rig (legs + optional torso, never a head): a BodyModelSwap parented to the
## PLAYER BODY (host) so it reads the host's `velocity` / `is_on_floor()` for the walk gait and inherits body
## yaw (not camera pitch, which lives on Head). Rendered on the default layer with real depth, so looking down
## shows your own body and world geometry occludes it correctly. The gun's separate view-model layer is
## untouched. Per-leg hip pose comes from the shipped NPC rig; the whole rig's drop is the tunable
## `fp_leg_offset`; the torso is stamped by _configure_fp_torso and crouch-follows in _update_fp_torso.
func _build_first_person_legs() -> void:
	if (not first_person_legs or fp_leg_model == null) and not first_person_torso and not first_person_body_arms:
		return
	var legs := BodyModelSwap.new()
	legs.name = "FirstPersonLegs"
	legs.casts_shadow = false  # FP body would cast a shadow from under the camera — looks wrong; suppress it
	# The ACTOR RIM + the ink mask, set BEFORE any model so the rig's very first build already dresses its parts
	# (every later rebuild re-applies them itself — that is why they live on the rig and not on a walk out here).
	legs.actor_outline = first_person_body_outline
	legs.leg_model = fp_leg_model if first_person_legs else null  # torso can show without legs, and vice versa
	legs.leg_scale = fp_leg_scale
	legs.leg_position = Vector3(0.095, -0.265, -0.02)  # per-leg hip offset, from scenes/enemies/enemy.tscn
	legs.leg_rotation = Vector3(0.0, -90.0, 0.0)
	# Tint the first-person legs with the character customizer's chosen LEG colour so the body parts you actually
	# see in first person (looking down) reflect your customisation — falling back to the authored fp_leg_color when
	# un-customised. Never run the catalog's whole configure_swap here — it would also mount a HEAD, which sits
	# exactly where the camera is. The torso gets the catalog's body-only slice in _configure_fp_torso instead.
	# See CharacterAppearanceCatalog / [[character customizer]].
	legs.leg_color = _appearance_fp_color("leg", fp_leg_color)
	legs.animate_legs = true
	legs.legs_follow_movement = true
	legs.legs_square_when_idle = false  # on STOP, the feet HOLD your last travel direction instead of snapping back to camera-forward
	legs.velocity_driven_legs = true  # your legs track your velocity (run gait in the air), not the NPC mid-air flail
	legs.velocity_leg_ref_speed = GameSettings.player_movement.max_speed  # walk-cycle cadence matches your real run speed
	host.add_child(legs)  # a child of the PLAYER, not this component — the gait reads body yaw + velocity off its parent chain
	legs.position = fp_leg_offset
	# ONE uniform scale for the whole body instead of a per-part diet: the cast's proportions are 1.226 m of body
	# under a 1.0 m eye, and scaling the mount keeps the NPC's own part-to-part layout by construction. See
	# fp_body_scale. Everything rig-local (the catalog mounts, the crouch sink) is in this scaled frame from here on.
	legs.scale = Vector3.ONE * fp_body_scale
	_fp_legs = legs
	if host.head != null:
		_fp_head_standing_y = host.head.position.y  # built from Player._ready, before any crouch — this IS the standing Y
	# Arms BEFORE the torso: _configure_fp_torso deliberately assigns body_model last so the rig rebuilds ONCE
	# with everything already stamped, and that only holds if the arm mount is in place before it.
	_configure_fp_body_arms(legs)
	_configure_fp_torso(legs)
	if legs.leg_model == null and legs.body_model == null and legs.arm_model == null:
		# Nothing resolved (legs off + arms off + a whole_body / catalog-less look): don't tick an empty rig for
		# the whole life of the Player — free it and let the FP body simply be absent.
		legs.queue_free()
		_fp_legs = null


## Build the first-person HANDS (a mirrored arm pair) for carrying objects: a BodyModelSwap parented to the CAMERA
## and forced onto the view-model render layer so the gun's dedicated camera draws it over the world with no wall
## clipping. Built HIDDEN -- the hands only show while a physics prop is held (see on_carry_changed), and grabbing
## one holsters the weapon first. Held STEADY (no NPC walk/flail swing). No-op if disabled / no model / no camera yet.
## (The PickupRay.carry_changed connection deliberately does NOT live here — Player._ready makes it, unconditionally,
## because the weapon-lock half of the carry dance must work whether or not this cosmetic rig ever built.)
func _build_first_person_arms() -> void:
	if not first_person_arms or fp_arm_model == null or host.camera_effects == null:
		return
	var arms := BodyModelSwap.new()
	arms.name = "FirstPersonArms"
	arms.casts_shadow = false  # view-model hands under the camera shouldn't cast a world shadow
	arms.animate_arms = false  # held steady on the object, not the NPC walk/flail swing
	arms.view_model_layer = ViewModelCamera.VIEW_MODEL_LAYER  # draw in the gun pass: over the world, no clipping
	arms.arm_model = fp_arm_model
	arms.arm_scale = fp_arm_scale
	arms.arm_position = Vector3(fp_arm_spread, 0.0, 0.0)  # LEFT shoulder offset; the RIGHT arm mirrors across X
	arms.arm_rotation = fp_arm_rotation
	arms.arm_color = _appearance_fp_color("arm", fp_arm_color)  # carry-hands reflect the customizer's ARM colour (colour only — see the FP-legs note)
	# Punch shaping. These ride the SAME rig, because unarmed reuses the carry hands rather than mounting a
	# copy under the gun: that is what keeps the fists on the character's arm colour, centred on the camera
	# instead of offset to the gun's side, and out of the holster park's 45° tip.
	arms.arm_strike_pitch = fp_arm_punch_pitch
	arms.arm_strike_duration = fp_arm_punch_duration
	arms.arm_strike_thrust = fp_arm_punch_thrust
	arms.arm_strike_curve = fp_arm_punch_curve
	arms.arm_strike_alternate = fp_arm_punch_alternate
	arms.arm_strike_offhand_scale = fp_arm_punch_offhand
	# Mount the rig on a dedicated bob node: _update_fp_arm_bob writes the MOUNT's transform each frame while the
	# draw/stow tweens own the rig's own position, so the two never fight over a single property.
	var bob_mount := Node3D.new()
	bob_mount.name = "FirstPersonArmsBobMount"
	host.camera_effects.add_child(bob_mount)
	bob_mount.add_child(arms)
	arms.position = fp_arm_offset
	arms.visible = false  # hands appear only while carrying an object
	_fp_arms = arms
	_fp_arm_bob_mount = bob_mount
	# The WEAPON look on your bare hands: the same GunVisuals dress pass every view model gets — shadows off,
	# rim light chained per-surface (or onto the tint override), and InkOutline's view-model outline id — so
	# the fists read as first-class view-model gear beside an outlined gun, for the carry hold and the guard
	# alike. Code-built child; tune its rim live on the Remote tree (FirstPersonArms/FistVisuals), and the
	# outline itself on the InkOutline node (highlight_view_model / highlight_width_px), which is what keeps
	# the hands from ever drifting from the gun beside them — they now literally share one knob.
	# (Until 2026-08-27 this pinned visuals.outline_width = 2.0 before add_child, because GunVisuals baked
	# the width into a shared hull material in _ready. Both the width and that ordering trap are gone.)
	var visuals := GunVisuals.new()
	visuals.name = "FistVisuals"
	visuals.host = arms  # duck-typed: the rig exposes no `layers`, so meshes keep the view-model layer it forced
	arms.add_child(visuals)  # _ready builds the shared rim material...
	visuals.dress(arms)  # ...then the dress stamps it (and the outline id) onto the already-instanced arm pair


## Hang your own ARMS off the FP body rig — the same mirrored pair an NPC wears, at real world depth, so looking
## down shows arms attached to your chest rather than a torso with stumps. Deliberately NOT the catalog's arm
## slice: the catalog arms are authored for a third-person/portrait body, and the FP shoulders have to be framed
## against the CAMERA (see fp_body_arm_position) — but the customizer's chosen arm COLOUR is honoured, the same
## way the legs take its leg colour, so your first-person body matches your portrait.
##
## ⭐The mode pitches are all zeroed on purpose. BodyModelSwap's arm animation reads the HOST duck-typed, and an
## NPC host answers `is_holding_gun` / `is_fists_out` to pose its arms forward, plus airborne throws them
## straight overhead (arm_air_pitch, the roller-coaster flail). The Player implements neither weapon method, so
## those two are already inert here — but `airborne` is just `not is_on_floor()`, which the Player very much
## does answer, so WITHOUT zeroing arm_air_pitch every jump would fling your own arms up over your face. What
## survives is exactly what should: the antisymmetric walk swing, cadence-matched to real speed by the legs'
## velocity_driven_legs, so your arms swing as you walk and hang still when you stop.
func _configure_fp_body_arms(rig: BodyModelSwap) -> void:
	if not first_person_body_arms:
		return
	var catalog := CharacterAppearanceCatalog.get_catalog()
	if catalog == null or catalog.arm_model == null:
		return
	# A whole_body look already HAS arms baked into its one-piece model — mounting a second pair would grow you
	# four. Same reason _configure_fp_torso skips those looks entirely.
	var body := catalog.body_option(String(host.appearance.get("body", "")))
	if body == null:
		body = catalog.default_body()
	if body != null and body.whole_body:
		return
	rig.arm_scale = catalog.arm_scale * fp_body_arm_scale_mult
	_fp_arm_catalog_pos = catalog.arm_position
	rig.arm_position = _fp_arm_catalog_pos + fp_body_arm_offset  # LEFT shoulder; the RIGHT mirrors across X
	rig.arm_rotation = catalog.arm_rotation
	rig.arm_color = _appearance_fp_color("arm", catalog.default_arm_color)
	rig.animate_arms = true
	rig.arm_swing_amplitude = fp_body_arm_swing_deg
	# ⭐ZERO ALL THREE MODE PITCHES — the arms only ever hang and walk-swing. See the note above for why: these
	# are the poses BodyModelSwap strikes when its host answers `is_holding_gun` / `is_fists_out` / goes airborne.
	# `airborne` is the live one today (the Player answers is_on_floor), and it would throw your own arms straight
	# over your face on every single jump. The weapon two are inert only because the Player happens not to
	# implement those methods — zeroed anyway, deliberately, so that adding one later (for the AI, the portrait
	# host, anything) can't silently swing your body arms forward through the view model you are already holding.
	rig.arm_air_pitch = 0.0
	rig.arm_hold_pitch = 0.0
	rig.arm_fists_pitch = 0.0
	rig.arm_model = catalog.arm_model  # LAST: the setter rebuilds, so everything above is already stamped


## Stamp the player's OWN torso onto the FP body rig — the catalog's BODY slice only (the same resolution
## configure_swap runs for the customizer/portrait: chosen body model + authored transform; a player-DRAWN
## shirt planar-projects UNTINTED, else the skin colour tints the body) — deliberately without the head (it
## sits exactly where the camera is) or the catalog arms (the hands are the separate view-model rig). Skips
## whole_body appearances: a one-piece character model can't have its head chopped off, so those stay
## legs-only. body_model is set LAST so the rig rebuilds once with everything above already stamped.
func _configure_fp_torso(rig: BodyModelSwap) -> void:
	if not first_person_torso:
		return
	var catalog := CharacterAppearanceCatalog.get_catalog()
	if catalog == null:
		return
	var body := catalog.body_option(String(host.appearance.get("body", "")))
	if body == null:
		body = catalog.default_body()
	if body == null or body.whole_body:
		return
	var shirt := CharacterAppearanceCatalog.shirt_texture(host.appearance)
	rig.body_model_scale = body.scale
	# +180 yaw on the catalog rotation: body options are authored to face the NPC's +Z forward (see
	# body_model_rotation's own doc), but the player faces -Z — without the flip you wear the torso backwards.
	rig.body_model_rotation = body.rotation + Vector3(0.0, 180.0, 0.0)
	rig.body_texture_planar = shirt != null  # BEFORE body_texture — the texture setter reads the projection mode
	rig.body_texture = shirt if shirt != null else body.texture
	var skin: Variant = host.appearance.get("skin")
	rig.body_color = Color.WHITE if shirt != null else (skin if skin is Color else catalog.default_skin_color)
	_fp_torso_catalog_pos = body.position
	rig.body_model_position = _fp_torso_catalog_pos + fp_torso_offset
	rig.body_model = body.model
	# The rig's default breathe stays ON deliberately: the chest pulses gently (±3% scale, the NPC torso's
	# idle breath) — it pairs with the fists' breathing sway, and the pulse sits well inside the probed
	# near-clip margin. Set legs.breathe = false here if a dead-still chest is ever wanted.


## Keep the FP torso AND the body arms glued to their authored rests + the LIVE fp_torso_offset (Remote-
## inspector tunable) and sunk by the head's CURRENT drop below its standing height — so chest-to-eye spacing
## stays constant while the camera lowers. Crouching ALSO fades them out entirely (dithered, riding the
## already-eased crouch_t) and back in on stand: crouched, your chest would fill the whole lowered view, so it
## hides for your ease of viewing; the resting state keeps fp_torso_transparency's see-through. The arms take
## BOTH the sink and the fade off the same values as the chest — they hang off it, so they must never outlive
## it. Runs for whichever parts exist (torso-only, arms-only, both). Epsilon-skipped writes throughout.
func _update_fp_torso(delta: float) -> void:
	if host == null or not is_instance_valid(_fp_legs):
		return
	var has_torso := first_person_torso and _fp_legs.body_model != null
	var has_arms := first_person_body_arms and _fp_legs.arm_model != null
	var has_legs := _fp_legs.leg_model != null
	if not has_torso and not has_arms and not has_legs:
		return
	# The crouch sink is measured in PLAYER metres (how far the Head dropped) but written as a RIG-LOCAL offset,
	# and the rig is scaled by fp_body_scale — so it has to be divided back out or the chest follows the camera
	# down by only fp_body_scale of the drop and creeps up into the lowered view. Guarded against a zero scale.
	var sink := 0.0
	if host.head != null:
		sink = maxf(0.0, _fp_head_standing_y - host.head.position.y) / maxf(fp_body_scale, 0.001)
	if has_torso:
		var target := _fp_torso_catalog_pos + fp_torso_offset - Vector3(0.0, sink, 0.0)
		if _fp_legs.body_model_position.distance_squared_to(target) > 0.000001:
			_fp_legs.body_model_position = target
	# The ARMS take the same crouch sink, so the shoulders stay glued to the chest through the whole transition
	# rather than the arms hanging in place while the torso drops out from under them. Written through
	# arm_position's setter, which re-poses the pair to REST — safe by ordering, not by luck: this component
	# ticks at process_priority -1 (see _ready), so the rig's own BodyModelSwap._process re-applies the live walk
	# swing AFTER us every frame. Same rule as the view-model rig's eased arm_scale.
	if has_arms:
		var arm_target := _fp_arm_catalog_pos + fp_body_arm_offset - Vector3(0.0, sink, 0.0)
		if _fp_legs.arm_position.distance_squared_to(arm_target) > 0.000001:
			_fp_legs.arm_position = arm_target
	# ⭐⭐THE REVEAL — the one rule that decides whether any of this is on screen: hidden until you LOOK DOWN at
	# yourself, eased in across the band, solid past it. Head owns the look pitch (rotate_x; negative = down).
	# Keyed on the LOOK and nothing else on purpose — see fp_body_reveal_start_deg for why the previous
	# camera-relative schemes could not hold. Crouching then overrides back toward hidden regardless: crouched,
	# the lens is 0.61 m down among your own knees and a revealed body just fills the lowered view.
	var down_deg := (maxf(0.0, -host.head.rotation_degrees.x) if host.head != null else 90.0)
	var reveal := clampf(
		inverse_lerp(fp_body_reveal_start_deg, maxf(fp_body_reveal_full_deg, fp_body_reveal_start_deg + 0.1), down_deg),
		0.0, 1.0)
	var crouch_t := (host.crouch.crouch_t if host.crouch != null else 0.0)
	# 1 = fully invisible, so an un-revealed body is 1 and the reveal eases DOWN to its resting see-through.
	var see := lerpf(1.0, fp_torso_transparency, reveal)
	see = lerpf(see, 1.0, crouch_t)
	if has_torso and absf(_fp_legs.body_transparency - see) > 0.002:
		_fp_legs.body_transparency = see
	# ⭐The LEGS ride the SAME reveal, on their own channel (BodyModelSwap.leg_transparency, which they gained for
	# this). They used to have no fade channel at all — which is precisely why, whatever the torso did, a pair of
	# thighs stayed on screen. One gate, every part, so they can never disagree about whether you are looking.
	# Their revealed state is always fully solid: fp_torso_transparency is the CHEST's ghost knob, not the body's.
	if has_legs:
		var leg_see := lerpf(1.0, 0.0, reveal)
		leg_see = lerpf(leg_see, 1.0, crouch_t)
		if absf(_fp_legs.leg_transparency - leg_see) > 0.002:
			_fp_legs.leg_transparency = leg_see
	# ⭐The arms dissolve on the SAME curve as the chest they hang off. Without this the crouch hide (and the
	# deep look-down fade) would delete your torso and leave two disembodied arms floating under the camera —
	# strictly worse-looking than either extreme. One `see` value, both parts, so they can never disagree.
	#
	# ...and then the arms get ONE MORE term the torso doesn't: they also dissolve while the VIEW-MODEL rig owns
	# your hands (see _fp_body_arms_hidden), so you never see two pairs of arms at once. Eased here rather than
	# in the predicate because the holster is a binary flip, unlike the crouch and look-down terms which arrive
	# already smooth. Composed with lerpf toward fully-invisible, exactly like the crouch term above, so whichever
	# reason is strongest wins and they can't fight.
	if has_arms:
		var hide_target := 1.0 if (fp_body_arms_hide_when_drawn and _fp_body_arms_hidden()) else 0.0
		_fp_body_arm_hide_t = lerpf(_fp_body_arm_hide_t, hide_target, 1.0 - exp(-fp_body_arms_hide_fade * delta))
		var arm_see := lerpf(see, 1.0, _fp_body_arm_hide_t)
		if absf(_fp_legs.arm_transparency - arm_see) > 0.002:
			_fp_legs.arm_transparency = arm_see


## True when the VIEW-MODEL rig owns your hands, so the BODY arms must get out of the way — the "only one pair of
## arms on screen" rule. Two reasons, and they are deliberately different questions:
##   • the weapon is DRAWN (`not attack.holstered`) — the gun, or the raised fists, IS what your arms are doing.
##     Asked of the holster rather than of the view model because a drawn weapon's mesh lives on the GUN rig,
##     which this component doesn't own and can't see.
##   • the view-model ARMS rig is on screen — a carried prop (hands visibly full). Carrying force-holsters the
##     weapon, so the holster question alone answers "put them away" there and would leave your body arms hanging
##     at your sides while your other hands hold a crate.
##
## Asking the rig's live `visible` (not a latch) is what gives the nice sequencing: it stays true for the length
## of the stow slide, so the view-model hands finish sinking out of frame BEFORE your real arms fade back in,
## instead of both being half-present at once.
##
## Null-safe in every direction: no weapon system reads as holstered (nothing drawn), no view-model rig reads as
## nothing held. A bare component with no host hides nothing.
func _fp_body_arms_hidden() -> bool:
	if host == null:
		return false
	if host.weapon_system != null and host.weapon_system.attack != null \
			and not host.weapon_system.attack.holstered:
		return true
	return is_instance_valid(_fp_arms) and _fp_arms.visible


## The customizer's chosen colour for a first-person limb (`&"arm"` / `&"leg"`) from the mirrored appearance dict,
## or `fallback` (the authored fp_*_color) when un-customised or the stored value isn't a Colour. Keeps the FP
## view-model tint in step with the Stats/creation portrait for the same character.
func _appearance_fp_color(key: String, fallback: Color) -> Color:
	if host == null:
		return fallback
	var c: Variant = host.appearance.get(key)  # String keys throughout (GameState/creation/configure_swap all use "arm"/"leg")
	return c if c is Color else fallback


## The COSMETIC half of a carry grab/drop — the view-model hands' show/hide dance. The GAMEPLAY half (the
## `_carrying` latch, the holster capture/restore, `draw_locked`, the release bookkeeping) stays in
## Player._on_carry_changed, which TAILS into this — ONE connection on the signal, so the holster restore has
## always landed synchronously by the time _unarmed_hands_wanted() reads `attack.holstered` below. On grab:
## wait the draw-delay beat (so the holster reads first) then slide the hands up. On drop: stow — or hand off
## seamlessly to the bare fists when unarmed, or hide instantly mid-death.
func on_carry_changed(holding: bool) -> void:
	if host == null or not is_instance_valid(_fp_arms):
		return
	if holding:
		await get_tree().create_timer(fp_arm_draw_delay).timeout
		# Still holding after the holster beat AND not dead — don't pop hands into the death cinematic
		# (dying mid-carry would otherwise show the FP arms over the keel-over/fade-to-black).
		if host._carrying and not host._dying and not host._dead and is_instance_valid(_fp_arms):
			_slide_fp_arms(true)  # RISE up into frame instead of popping in
	else:
		# Dropped: mid-death-cinematic hide INSTANTLY (a slide-down would linger over the keel-over/fade); otherwise
		# lower the hands back out of frame, then hide once they're fully down (see _slide_fp_arms).
		if host._dying or host._dead:
			_kill_fp_arm_tween()
			_fp_arms.visible = false
			_unarmed_hands_up = false
		elif _unarmed_hands_wanted():
			# UNARMED: these are the same hands. Don't stow them — they simply stop holding a prop and become
			# your fists, so the transition is seamless instead of a stow followed immediately by a re-draw.
			_unarmed_hands_up = true
			_ease_fp_arms_to_rest()  # ...but the fists REST closer than the carry hold — pull them into the guard
		else:
			_unarmed_hands_up = false
			_slide_fp_arms(false)


## Slide the first-person carry hands into frame (into_view true) or out of it (false) with a vertical tween, so they RISE into
## view on draw and LOWER back out on stow rather than popping. Rest is _fp_arm_rest() — the carry hold, or the
## closer unarmed guard while the fists are up.
##
## THE STOW SINKS STRAIGHT DOWN FROM THE LIVE POSE — fp_arm_draw_rise below wherever the rig currently is, x/z
## untouched. It must NOT be anchored to a named rest: by the time this runs the _unarmed_hands_up latch has
## already flipped to the mode we're leaving FOR, so _fp_arm_rest() answers for the wrong pose, and the old
## hardcoded `fp_arm_offset - draw_rise` anchor assumed the carry hold was "the lower of the two rests", which
## stopped being true the moment the guard nudge went negative-Y (see fp_arm_unarmed_nudge). Sinking from the
## live pose is correct for every rest by construction and gives them all the same travel.
##
## A draw only RESETS to the off-frame bottom when the rig is currently hidden — hands already on screen (the
## carry→fists handoff, where the synchronous holster-restore refresh lands here, or a mid-stow re-draw) tween
## from where they are, so they never teleport off-frame mid-view. On hide the arms
## switch off only once they've slid all the way down (a tween_callback), so you never catch them vanishing
## mid-frame. Any in-flight slide is killed first so a fast grab/drop can't leave two tweens fighting over the
## position. No-op with no arms rig.
func _slide_fp_arms(into_view: bool) -> void:
	if not is_instance_valid(_fp_arms):
		return
	_kill_fp_arm_tween()
	var rest := _fp_arm_rest()  # read live so an inspector tune of the rest offsets is honoured
	if into_view:
		_fp_arm_stowing = false
		if not _fp_arms.visible:
			# Hidden: start just out of frame, below the CARRY rest. Safe to anchor here (unlike the stow
			# below) precisely because the rig is hidden — this is a teleport nobody sees, and the untilted /
			# carry-scale reset it sits alongside is what makes a guard draw GROW in rather than slide in.
			_fp_arms.position = fp_arm_offset - Vector3(0.0, fp_arm_draw_rise, 0.0)
			_fp_arms.rotation_degrees.x = 0.0  # ...untilted, so the guard's pitch reads as part of the raise...
			_fp_arms.arm_scale = fp_arm_scale  # ...and at the carry baseline, so a guard draw GROWS in (and a death mid-guard can't leak the guard scale into the next carry draw)
			_fp_arms.arm_position = Vector3(fp_arm_spread, 0.0, 0.0)  # same for the guard's wider fist spread
		_fp_arms.visible = true
		_fp_arm_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_fp_arm_tween.tween_property(_fp_arms, ^"position", rest, fp_arm_draw_time)  # ...rise to rest
		_fp_arm_tween.parallel().tween_property(_fp_arms, ^"rotation_degrees:x", _fp_arm_rest_tilt(), fp_arm_draw_time)  # tipping up into the guard (0 for the carry hold)
	else:
		# Stow: sink in the CURRENT pose. No tilt/scale/spread retarget here and the per-frame pose ease is
		# frozen (_fp_arm_stowing) — the latch has already flipped to the next mode, and easing toward it
		# while still on screen morphed the sinking fists into the flat carry reach for a beat (the reported
		# "holding-items arm flash" on holster). The next draw's hidden-reset re-poses from scratch.
		# The TARGET is the live position minus the rise, NOT a rest-derived point — see the header. This was
		# `fp_arm_offset - draw_rise`, which at the authored guard (fp_arm_unarmed_nudge (0, -0.705, 1.49))
		# sits 0.355 m ABOVE the guard and 1.49 m toward the lens: holstering the fists RAISED them and threw
		# them 1.49 m forward, so the "stow" played as the arms extending out toward the crosshair and then
		# blinking off at peak size. Render-proven (scripts/tools/preview_fists_frame.gd idiom). Identical to
		# the old behaviour for the carry hold, whose rest IS fp_arm_offset — only the guard was mis-anchored.
		_fp_arm_stowing = true
		var sink := fp_arm_stow_target(_fp_arms.position, fp_arm_draw_rise)
		_fp_arm_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		_fp_arm_tween.tween_property(_fp_arms, ^"position", sink, fp_arm_draw_time)  # sink from wherever it is...
		_fp_arm_tween.tween_callback(_hide_fp_arms)  # ...then switch off, fully out of frame


## Where a stow slides TO: `rise` metres STRAIGHT DOWN from wherever the rig is, x/z untouched. Pure + static
## so the anchor rule is testable without a rig — and the test must be able to drive an ARBITRARY pose, because
## the mis-anchor this replaced was invisible at the script-default nudge and only showed at the one authored
## in Player.tscn. Any future "anchor it to rest X instead" must answer that: by stow time the _unarmed_hands_up
## latch has already flipped, and no named rest is reliably below every pose the hands can stow from.
static func fp_arm_stow_target(from: Vector3, rise: float) -> Vector3:
	return from - Vector3(0.0, rise, 0.0)


## The hands' current rest offset: the carry hold (fp_arm_offset), or — while the bare fists are the thing on
## screen — that hold nudged toward the lens (fp_arm_unarmed_nudge) so the fists frame as a dropped-shoulder
## guard. Keyed on the _unarmed_hands_up latch, which every caller settles BEFORE sliding.
func _fp_arm_rest() -> Vector3:
	return fp_arm_offset + fp_arm_unarmed_nudge if _unarmed_hands_up else fp_arm_offset


## The rig's rest pitch (degrees about the camera's X axis): tipped up into the guard while the bare fists are
## up, flat for the carry hold. Same latch key as _fp_arm_rest, settled by every caller before sliding.
func _fp_arm_rest_tilt() -> float:
	return fp_arm_unarmed_tilt_deg if _unarmed_hands_up else 0.0


## The arms' rest scale: the authored carry scale, multiplied up while the bare fists are up so they read
## bigger/closer without the rig moving into the near plane. Same latch key as the other _fp_arm_rest_* helpers.
func _fp_arm_rest_scale() -> float:
	return fp_arm_scale * fp_arm_unarmed_scale_mult if _unarmed_hands_up else fp_arm_scale


## The fist pair's rest spread (the LEFT shoulder X; the right mirrors): wider for the guard so the fists read
## distinct and never cover the crosshair, the authored carry spread otherwise. Same latch key as the others.
func _fp_arm_rest_spread() -> float:
	return fp_arm_unarmed_spread if _unarmed_hands_up else fp_arm_spread


## Ease the already-visible hands to their current rest WITHOUT the full off-frame draw slide — the carry→fists
## handoff, where the rig stays on screen but the fists' guard rests closer to the lens than the carry hold it
## just left. Also retargets (harmlessly, same destination) any draw slide the holster-restore refresh started.
func _ease_fp_arms_to_rest() -> void:
	if not is_instance_valid(_fp_arms):
		return
	_kill_fp_arm_tween()
	_fp_arm_stowing = false
	_fp_arms.visible = true
	_fp_arm_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_fp_arm_tween.tween_property(_fp_arms, ^"position", _fp_arm_rest(), fp_arm_draw_time)
	_fp_arm_tween.parallel().tween_property(_fp_arms, ^"rotation_degrees:x", _fp_arm_rest_tilt(), fp_arm_draw_time)


## True when the bare fists should be up: nothing but the FISTS fallback equipped, not carrying a prop (those
## are the SAME hands, driven by the carry slide), not holstered, alive, and no REAL weapon mid-draw. All of
## that weapon/carry state is the HOST's — this component holds zero gameplay state, it only reads.
##
## Compared by resource identity first with a resource_path fallback — the same test
## CharacterInspectScreen._is_unarmed_fallback uses, because a duplicated resource still means "unarmed".
func _unarmed_hands_wanted() -> bool:
	if host == null:  # a bare component (no host wired) wants nothing on screen — the null-guard contract
		return false
	if not fp_arm_unarmed or host._carrying or host._dying or host._dead:
		return false
	# A REAL weapon is mid-draw: the H put-back reads "FISTS equipped, unholstered" for the beat between the
	# carry release and its rewield landing (Attack's swap unholsters BEFORE it swaps the weapon hub), and the
	# fists would flash up into the weapon's own raise. _rewield_in_flight spans stash_held_item's
	# release→equip call; the BACKPACK's optimistic equipped_item (set before the combat inventory switches,
	# and held through a request QUEUED behind a mid-flight swap) covers the draw until equipped_weapon stops
	# reading FISTS. Neither is ever set on a genuine drop/throw — that handoff still raises the fists below.
	if host._rewield_in_flight or (host.inventory != null and host.inventory.equipped_item != null):
		return false
	if host.weapon_system == null or not is_instance_valid(_fp_arms):
		return false
	var wd: WeaponData = host.weapon_system.inventory.equipped_weapon if host.weapon_system.inventory != null else null
	if wd == null or not (wd == Player.FISTS or wd.resource_path == Player.FISTS.resource_path):
		return false
	return host.weapon_system.attack == null or not host.weapon_system.attack.holstered


## Bring the bare fists up / put them away to match the current weapon + holster + carry state. PUBLIC — the
## host calls it from its holster_changed / swap_finished wiring, the deferred first-equip refresh, die() and
## the in-place revive. Latched on _unarmed_hands_up rather than on `visible`, because during the stow slide
## the rig is still visible for the length of the tween — comparing against `visible` would re-fire the slide
## every time this is called.
func refresh_unarmed_hands() -> void:
	if not is_instance_valid(_fp_arms):
		return
	var want := _unarmed_hands_wanted()
	if want == _unarmed_hands_up:
		return
	_unarmed_hands_up = want
	_slide_fp_arms(want)


## Punch: throw the fists' own strike (host-wired to Attack.play_animation). Gated on the fists actually being
## the thing on screen — while CARRYING, the same rig is holding a prop and must not swing, and with a real
## weapon out the gun's recoil is the swing.
func on_attack_play_animation() -> void:
	if host == null or not (_unarmed_hands_up and is_instance_valid(_fp_arms)):
		return
	# Which fist threw it: the ALT button (right click) leads with the RIGHT hand, the primary with the LEFT.
	# Attack banks the button on the swing that actually got through its gates, so a refused click never poses
	# the arms. -1 = right, +1 = left (see BodyModelSwap.strike).
	_fp_arms.strike(-1.0 if host.weapon_system.attack.last_attack_alt else 1.0)


## Switch the FP carry hands off — the tail of the stow slide (a tween_callback), fired only once they're fully out
## of frame. A bound method Callable (NOT a lambda) so a freed player never fires a dangling capture.
func _hide_fp_arms() -> void:
	_fp_arm_stowing = false  # the stow finished — pose easing may resume (the next draw re-poses from hidden anyway)
	if is_instance_valid(_fp_arms):
		_fp_arms.visible = false


## Kill any in-flight hands slide so a new draw/stow (or a death hide) doesn't get overwritten by the old tween.
func _kill_fp_arm_tween() -> void:
	if _fp_arm_tween != null and _fp_arm_tween.is_valid():
		_fp_arm_tween.kill()
	_fp_arm_tween = null


## Per-frame procedural motion for the bare fists: the footstep walk-bob GunPose gives every mounted weapon
## (cos-half-rate X / sin-full-rate Y / half-rate roll, climbing counting as walking, behind the
## view_bob_enabled accessibility toggle) CROSSFADED with
## an idle BREATHING sway while you stand still (GunPose's breath envelope + a slight lateral hand-wander).
##
## TWO WAYS THIS RIG'S BOB GOES BEYOND GunPose's, both driven off one speed_ratio (fraction of the run tier):
## the CADENCE scales with speed (bob_cadence — GunPose's phase rate is flat, so its walk and sprint differ
## only in size), and the pair LEANS AGAINST the direction of travel (bob_lean). Deliberate divergence, not
## drift: the fists sit on a ~2.9 m lever where a mounted gun sits ~0.4 m out, so the same motion reads an
## order of magnitude larger here and can afford — and needs — the extra articulation.
## Needed for the same reason GunPose exists: the rig is a CHILD of the camera, so it inherits the head-bob and
## reads glued to the screen without its own counter-motion. Written onto the rig's dedicated MOUNT, never the rig — the
## draw/stow tweens own the rig's position, and the two must not fight over one property. Fists-only by design
## (the carry hold stays planted on the held prop): amplitude rides a gate eased at fp_arm_unarmed_bob_fade on
## _unarmed_hands_up — so a carry grab fades the bob out through the hand-off (a sub-millimetre remnant decays
## over the first second) rather than snapping — and once the gate fully closes the mount parks exactly at zero.
func _update_fp_arm_bob(delta: float) -> void:
	if host == null:
		return  # bare component — nothing to animate (the rigs only ever build with a host)
	# GUARD SCALE, eased per-frame from HERE rather than tweened. Deliberate ordering fix: a property tween's
	# setter runs AFTER node _process each frame, and BodyModelSwap.arm_scale's setter re-poses the arms to
	# REST — so a tween stomped any punch whose strike envelope overlapped a slide. This component ticks at
	# process_priority -1 (see _ready), BEFORE the descendant rig's _process — so easing from here lets the
	# strike path re-pose a mid-punch arm afterwards, every frame. Rate is derived from fp_arm_draw_time
	# (~settled in one slide), and converged scale skips the write entirely so a steady-state punch is never
	# touched at all.
	if is_instance_valid(_fp_arms) and not _fp_arm_stowing:
		var pace := 1.0 - exp(-delta * 3.0 / maxf(fp_arm_draw_time, 0.01))
		var scale_target := _fp_arm_rest_scale()
		if absf(_fp_arms.arm_scale - scale_target) > 0.0005:
			_fp_arms.arm_scale = lerpf(_fp_arms.arm_scale, scale_target, pace)
		# The guard's wider fist spread, eased under the same ordering rule (arm_position's setter also re-poses).
		var spread_target := _fp_arm_rest_spread()
		if absf(_fp_arms.arm_position.x - spread_target) > 0.0005:
			_fp_arms.arm_position = Vector3(lerpf(_fp_arms.arm_position.x, spread_target, pace), 0.0, 0.0)
		# Rest position + tilt track their exports CONTINUOUSLY while the hands are on screen and no slide is
		# in flight (a live tween owns the transform during draw/stow). This is what makes the pose knobs
		# LIVE-tunable from the editor's Remote inspector mid-game — drag fp_arm_unarmed_* and the guard
		# follows — and it converges to the same rest the slide would have landed on, so it is invisible in
		# normal play (epsilon-skipped once settled).
		if _fp_arms.visible and (_fp_arm_tween == null or not _fp_arm_tween.is_valid()):
			var rest := _fp_arm_rest()
			if _fp_arms.position.distance_squared_to(rest) > 0.000001:
				_fp_arms.position = _fp_arms.position.lerp(rest, pace)
			var tilt := _fp_arm_rest_tilt()
			if absf(_fp_arms.rotation_degrees.x - tilt) > 0.01:
				_fp_arms.rotation_degrees.x = lerpf(_fp_arms.rotation_degrees.x, tilt, pace)
	if not is_instance_valid(_fp_arm_bob_mount):
		return
	var want := 1.0 if (_unarmed_hands_up and is_instance_valid(_fp_arms) and _fp_arms.visible) else 0.0
	_fp_bob_gate = lerpf(_fp_bob_gate, want, 1.0 - exp(-fp_arm_unarmed_bob_fade * delta))
	if _fp_bob_gate < 0.001:
		_fp_arm_bob_mount.position = Vector3.ZERO
		_fp_arm_bob_mount.rotation_degrees = Vector3.ZERO
		if is_instance_valid(_fp_arms) and absf(_fp_arms.arm_stride_deg) > 0.01:
			_fp_arms.arm_stride_deg = 0.0  # park the arm-pump too — the carry hold's hands stay planted
		_fp_bob_amp = 0.0  # and drop the eased amplitude, so the next draw fades the pump back IN from rest
		return
	var horizontal_speed := Vector2(host.velocity.x, host.velocity.z).length()
	# Climbing counts as walking for the bob (vertical motion while scaling a wall) — the GunPose parity rule.
	var climbing := host.is_climbing()
	if climbing:
		horizontal_speed = maxf(horizontal_speed, absf(host.velocity.y))
	var moving := horizontal_speed > GameSettings.player_movement.footstep_min_horizontal_speed
	# ONE speed ratio drives BOTH halves of "the bob scales with how fast you move": 1.0 is the authored run
	# tier (PlayerMovementSettings.max_speed), a walk sits at walk_speed_mult of it, a crouch-creep lower, and
	# a bhop-boosted sprint runs PAST 1. The cadence below reads it UNCAPPED, the amplitude clamps it: travel
	# is a budget (these fists hang off a ~2.9 m lever, so metres here are decimetres of screen), cadence is free.
	var speed_ratio := horizontal_speed / maxf(GameSettings.player_movement.max_speed, 0.01)
	# AMPLITUDE is EASED, never stepped — this is the fix for the 2026-08-08 "fists jitter while walking" report.
	# `is_on_floor()` blips false for single frames all the time while actually walking (brush seams, the 0.5 m
	# stair risers, any bump), and horizontal_speed dips under the threshold between strides. Taking the raw gate
	# as the amplitude meant one such frame drove the arm-pump to ZERO and the next drove it back to full: a
	# ±fp_arm_unarmed_stride_deg snap, which on this rig's ~2.9 m arm swinging from a shoulder ~2 m behind the
	# lens is ~0.35 m of fist travel in ONE FRAME. The mount's own bob hid it (it is lerped below, so it only
	# ever moved 15% of the step) — the STRIDE was written raw, so the whole pair popped.
	var amp_target := 0.0
	if Settings.view_bob_enabled and (host.is_on_floor() or climbing) and moving:
		amp_target = clampf(speed_ratio, 0.0, 1.0)
	_fp_bob_amp = lerpf(_fp_bob_amp, amp_target, 1.0 - exp(-fp_arm_unarmed_bob_fade * delta))
	# PHASE only ever advances (while moving) and is WRAPPED — never eased toward zero. Easing a phase is what
	# turned the blip above into a random jump: the phase grows without bound while you walk (bob_speed rad/s, so
	# hundreds of radians within a minute), and lerping THAT toward 0 moves it tens of radians in one frame —
	# several whole bob cycles, i.e. the fists teleport to an unrelated point in the walk cycle. The settle-to-
	# centre this used to serve is already done properly by the eased amplitude above plus the mount lerp below.
	# TAU * 2 is the period of the HALF-rate terms (cos/sin of _fp_bob_time * 0.5), so the wrap is continuous for
	# every consumer — the full-rate sin, the half-rate bob/roll, and the stride.
	#
	# ...and the RATE it advances at now follows your speed (fp_arm_unarmed_bob_speed_gain). Amplitude alone
	# only ever changed the SIZE of the pump, so a walk and a sprint traced the same figure-eight at the same
	# footstep rate — one gait at two volumes. Driving a RATE from a raw per-frame value is safe in a way that
	# driving the PHASE never is (the 10b bug): a rate is a derivative, so the phase stays continuous and a
	# speed blip can't teleport the hands mid-stride. No easing needed, and none wanted — the cadence should
	# answer the sprint key on the frame you press it.
	_fp_bob_time = advance_bob_phase(_fp_bob_time,
			bob_cadence(GameSettings.camera.bob_speed, speed_ratio, fp_arm_unarmed_bob_speed_gain),
			delta, amp_target > 0.0)
	var amp := _fp_bob_amp * _fp_bob_gate
	# BREATHING — the idle half of the motion, GunPose's exact envelope (sin Y + half-rate pitch, fading out
	# while moving or airborne so the walk-bob takes over), plus a slower quarter-strength lateral drift at an
	# offset frequency so the hands wander organically instead of pumping like a metronome. Deliberately NOT
	# behind view_bob_enabled: the gun breathes with bobbing off too — comfort-safe micro-motion, not travel.
	var idle_target := 0.0 if (moving or not host.is_on_floor()) else 1.0
	_fp_breath_t = lerpf(_fp_breath_t, idle_target, 1.0 - exp(-fp_arm_unarmed_bob_fade * delta))
	_fp_breath_time += delta * fp_arm_unarmed_breath_speed
	var breath := _fp_breath_t * _fp_bob_gate
	var breath_x := sin(_fp_breath_time * 0.63) * fp_arm_unarmed_breath_pos * 0.25 * breath
	var breath_y := sin(_fp_breath_time) * fp_arm_unarmed_breath_pos * breath
	var breath_pitch := sin(_fp_breath_time * 0.5) * fp_arm_unarmed_breath_deg * breath
	# WHICH DIRECTION you're moving, not just how fast: the pair LEANS AGAINST the body's velocity — strafe
	# right and the fists drift left, run forward and they trail back toward the lens, backpedal and they press
	# away from it. Inertia; the same read HudSway.velocity_target gives the corner HUD, and the same sign
	# rule — the minus lives in the formula so the knob stays positive-means-natural.
	#
	# Measured in the BODY's yaw frame, NOT the camera's. Under pure pitch the two share an X axis, so the
	# strafe term is identical either way; the DEPTH term is not — off the camera basis, "forward" would fade
	# out as you looked at your feet and the fists would stop leaning for no reason the player can see.
	# Rides the fists gate (fades out with a stow) but NOT `amp`: it is proportional to velocity already, and
	# unlike the pump it stays honest mid-air, where a strafe still has inertia but there are no footfalls.
	var lean := Vector3.ZERO
	if Settings.view_bob_enabled:
		var body := host.global_transform.basis
		var inv_max := 1.0 / maxf(GameSettings.player_movement.max_speed, 0.01)
		lean = bob_lean(host.velocity.dot(body.x) * inv_max, -host.velocity.dot(body.z) * inv_max,
				fp_arm_unarmed_bob_pos * _fp_bob_gate, fp_arm_unarmed_lean_mult)
	var target_pos := Vector3(
		cos(_fp_bob_time * 0.5) * fp_arm_unarmed_bob_pos * amp + breath_x + lean.x,
		sin(_fp_bob_time) * fp_arm_unarmed_bob_pos * amp + breath_y,
		lean.z)
	var target_rot := Vector3(breath_pitch, 0.0, sin(_fp_bob_time * 0.5) * fp_arm_unarmed_bob_roll_deg * amp)
	# Smooth toward the target (GunPose's motion_smooth-default feel) so a hard stop mid-stride settles instead
	# of snapping the fists to dead centre.
	var s := 1.0 - exp(-10.0 * delta)
	# ASYMMETRIC stride: ± pitch on the arm PAIR (left +, right − inside the rig) at the half-rate footstep
	# cadence — one full left-right alternation per two footfalls, the natural arm-pump. Written through the
	# rig's arm_stride_deg setter under the arm_scale ordering idiom (our write lands before the rig's strike
	# re-pose, so punches stay authoritative over a mid-walk swing).
	# SMOOTHED with the same `s` as the mount, and for the same reason: this drives a LEVER (the arm swings from
	# a shoulder ~2 m behind the lens), so degrees here are decimetres of fist on screen. Writing it raw made the
	# pair pop on any single-frame amplitude change — the mount, being lerped, never showed it. Keep the two on
	# one smoothing constant: they are the same motion, and a stride that leads or lags the bob reads as a limp.
	if is_instance_valid(_fp_arms):
		var stride_target := sin(_fp_bob_time * 0.5) * fp_arm_unarmed_stride_deg * amp
		if absf(_fp_arms.arm_stride_deg - stride_target) > 0.01:
			_fp_arms.arm_stride_deg = lerpf(_fp_arms.arm_stride_deg, stride_target, s)
	_fp_arm_bob_mount.position = _fp_arm_bob_mount.position.lerp(target_pos, s)
	_fp_arm_bob_mount.rotation_degrees = _fp_arm_bob_mount.rotation_degrees.lerp(target_rot, s)


## The walk-bob's footstep CADENCE (rad/s) at `speed_ratio` (1.0 = the authored run tier, PlayerMovementSettings.
## max_speed; a walk is ~0.7, a bhop sprint > 1). `base` is the authored flat rate (GameSettings.camera.bob_speed)
## and `gain` is how much of the cadence follows speed.
##
## The clamp is symmetric AROUND the gain, which buys two properties worth keeping: gain 0 returns `base` at
## every speed — the flat-rate behaviour this replaced, bit for bit, so the knob has a true off position — and
## the ceiling rises only as fast as a designer opens the knob, so no boost stack can strobe the arms into a
## blur. Pure + static: the off position and the bhop ceiling are pinned in tests/test_fists_view_model.gd.
static func bob_cadence(base: float, speed_ratio: float, gain: float) -> float:
	var g := clampf(gain, 0.0, 1.0)
	return base * clampf(lerpf(1.0, speed_ratio, g), 1.0 - g, 1.0 + g * 2.0)


## The velocity LEAN (rig-local metres) for a body moving at `lateral_ratio` / `forward_ratio` fractions of the
## run tier (+ = right / forward). `travel` is the bob amplitude the lean is expressed relative to, `mult` its
## x = sideways, y = depth multipliers. Leans AGAINST the motion (inertia — the sign lives HERE so the designer
## knob stays positive-means-natural, the HudSway.velocity_target rule).
##
## Ratios are clamped to ±1: the lean tops out at the run tier. A bhop-boosted sprint buys a faster cadence, not
## more travel — this rig's fists sit on a ~2.9 m lever, so extra metres here leave the frame, and an unclamped
## lean is exactly how the 08-08 stride pop got its reach. Pure + static so both rules pin off-tree.
static func bob_lean(lateral_ratio: float, forward_ratio: float, travel: float, mult: Vector2) -> Vector3:
	return Vector3(
		-clampf(lateral_ratio, -1.0, 1.0) * travel * mult.x,
		0.0,
		clampf(forward_ratio, -1.0, 1.0) * travel * mult.y)


## One step of the fists' walk-bob PHASE — pure + static so the anti-jitter contract is unit-testable without a
## Player, a rig, a floor or a physics tick (tests/test_fists_view_model.gd). `advancing` is "the walk-bob has
## amplitude this frame" (grounded/climbing AND moving AND View Bobbing on).
##
## THE CONTRACT, and why it is shaped like this — this function IS the 2026-08-08 "the fists jitter while
## walking" fix:
##   - The phase ONLY EVER ADVANCES; when not advancing it HOLDS. It must NEVER be eased toward zero. A phase
##     grows without bound while you walk (bob_speed rad/s — ~240 rad after 30 s), so `lerpf(phase, 0, ~0.15)`
##     moves it ~37 radians in ONE FRAME: six whole bob cycles, i.e. the hands teleport to an unrelated point
##     in the walk cycle. Settling to centre is the AMPLITUDE's job (see _fp_bob_amp), not the phase's.
##   - It is WRAPPED to TAU * 2 — the period of the HALF-rate consumers (the cos/sin of phase * 0.5 that drive
##     the horizontal bob, the roll and the arm stride). Wrapping there is continuous for the full-rate sin too,
##     and keeps the value small forever instead of drifting into the thousands.
static func advance_bob_phase(phase: float, bob_speed: float, delta: float, advancing: bool) -> float:
	if not advancing:
		return phase
	return fposmod(phase + delta * bob_speed, TAU * 2.0)


## Point the first-person legs AT the wall they're clinging to (not just "ahead") while climbing, so they press the
## real surface instead of dangling. Takes the WALL DIRECTION (-wall_normal) into the rig's local frame, flattens it,
## and pitches the whole rig from straight-DOWN toward it — eased by the wall-climb blend the shadow already computes
## (host._shadow_wall_blend: 0 grounded -> 1 clinging). So it orients to the actual wall regardless of where you're
## looking. The gait is separately told (via is_climbing()) not to air-flail. Null-safe.
##
## HOST-CALLED from Player._physics_process, deliberately NOT a _physics_process here: it must run AFTER
## _update_wall_shadow wrote _shadow_wall_blend that frame, and it must FREEZE with the death cinematic —
## die()'s set_physics_process(false) stops the host's whole step, where a self-ticked callback would keep
## pitching the legs through the keel-over.
##
## ⭐⭐EVERY BASIS WRITE HERE MUST CARRY fp_body_scale — route them all through _fp_legs_basis(). A Basis holds
## rotation AND scale in the same three columns, so assigning a bare `Basis()` does not mean "no rotation", it
## means "no rotation, AND scale 1". This function runs UNCONDITIONALLY every physics frame and takes the rest
## branch on every grounded one, so a scale-less write here silently resets the whole body to full size on the
## first frame of every session — see 2026-08-16 in the header notes.
func update_leg_wall_pose() -> void:
	if host == null or _fp_legs == null:
		return
	# Off the wall (or no real wall normal this frame -- it reads ~zero as contact drops): legs rest (hang down).
	var wn := host.get_wall_normal()
	if host._shadow_wall_blend <= 0.001 or not host.is_on_wall() or wn.length_squared() < 0.0001:
		_fp_legs.transform.basis = _fp_legs_basis()
		return
	# Bring the wall direction into the rig's local frame. The player basis is an orthonormal yaw, so
	# orthonormalized().transposed() equals its inverse() but can NEVER raise a det==0 invert on a transient
	# degenerate transform (the engine error this guards against).
	var into_local := host.global_transform.basis.orthonormalized().transposed() * (-wn.normalized())  # toward the wall, local space
	into_local.y = 0.0  # flatten — pitch the legs toward the wall horizontally, not up/down it
	var axis := Vector3.DOWN.cross(into_local)  # horizontal pitch axis, perpendicular to the wall direction
	if axis.length() < 0.001:
		_fp_legs.transform.basis = _fp_legs_basis()
		return
	# Swing the rig's local-DOWN (where the legs extend) toward the wall by up to fp_leg_wall_pitch, eased by the cling.
	_fp_legs.transform.basis = _fp_legs_basis(
		Basis(axis.normalized(), deg_to_rad(fp_leg_wall_pitch) * host._shadow_wall_blend))


## The rig's basis for a given ROTATION, carrying the whole-body scale — the single place that knows a basis write
## to this rig owes fp_body_scale. `scaled()` post-multiplies, which for a UNIFORM scale commutes with the
## rotation, so the wall pitch is unaffected by the order.
##
## ⭐This exists because the scale was silently lost for a day. `legs.scale = ...` is written ONCE at build, and
## `transform.basis = Basis()` in the rest branch above overwrote it 60 times a second — so the shipped game ran
## the body at FULL NPC size with its feet 0.37 m through the floor and its chest 45.6° below the horizon, i.e.
## INSIDE a 120° FOV frustum while standing still and looking straight ahead. Nothing caught it: the frame probe
## and every geometry test build their own rig and set the scale themselves, so all of them measured a rig this
## call had never touched. If you add another basis write, route it through here.
func _fp_legs_basis(rotation: Basis = Basis()) -> Basis:
	return rotation.scaled(Vector3.ONE * fp_body_scale)


## Death/revive beat: hide the FP legs for the death cinematic, show them again on the in-place revive. The
## HOST owns the order (die() / _respawn_at_checkpoint author the full death choreography and its comments);
## this just wraps the rig access so the host never reaches into component internals.
func set_legs_visible(v: bool) -> void:
	if is_instance_valid(_fp_legs):
		_fp_legs.visible = v
