class_name PlayerMovementSettings
extends Resource

## Core ground/air locomotion tuning consumed by player.gd and the jump-forgiveness nodes: speeds +
## directional multipliers, jump velocity, coyote/jump-buffer windows, accel/air smoothing, footstep
## cadence, and the landing-impact divisor that scales camera dip / FOV / land SFX.

@export_group("Speed")
## Base ground run speed (m/s) — the speed forward movement tops out at (bhop boosts stack above it).
@export var max_speed: float = 5.0
## Speed multiplier when moving BACKWARD (0.6 = 60% of run speed) — keeps backpedalling slower than advancing.
@export var backward_mult: float = 0.6
## Speed multiplier when STRAFING sideways (0.8 = 80% of run speed).
@export var strafe_mult: float = 0.8
## Speed multiplier for the default walk tier when Run is not held. Noise scales with ground speed, so walking is
## automatically quieter than running. Lower = slower + quieter; 1.0 = off.
@export var walk_speed_mult: float = 0.7

@export_group("Jump")
## Upward launch velocity (m/s) on a jump — higher = a taller jump.
@export var jump_velocity: float = 4.5
## Gravity multiplier applied only once the player is descending. 1.0 = symmetric jump arc; >1 makes falls snap down faster.
@export var fall_gravity_mult: float = 1.75
## MOMENTUM LAUNCH — the fraction of your horizontal speed ADDED at the instant a jump fires, so a run-up is
## actively rewarded rather than merely preserved. 0.15 = a 5.0 m/s sprint leaves the ground at 5.75 and covers
## 4.60 m instead of 4.00. It is a MULTIPLIER on the speed you already carry, so it scales continuously with the
## run-up and pays a standing jump exactly nothing — which is the whole point.
## ⭐HARD BOUND, test-pinned: max_speed x (1 + this) must stay under the 6.5 m/s that BOTH the wind loop
## (AudioSettings.falling_air_min_move_speed) and the bunny-hop look-sensitivity falloff
## (BunnyhopSettings.sens_reduction_threshold) trigger on. At max_speed 5.0 that caps this at 0.30; 0.15 leaves
## 0.75 m/s of headroom. Cross it and a plain sprint jump silently starts howling wind and damping your aim.
## (AGILITY can already push ground speed past 6.5 on its own; that is pre-existing and unchanged.)
## The BUNNY-HOP chip is deliberately exempt — its chain stamp overwrites this on the same frame, because a
## chain is its own momentum economy and 12.0 x 1.15 would clear every threshold in the game at once.
@export var jump_momentum_boost: float = 0.15
## Grace window (s) after walking off a ledge during which you can still jump — forgiveness for late presses. 0 = must jump while grounded.
@export var coyote_time: float = 0.12
## Window (s) before landing in which a jump press is remembered and fires the instant you touch down. 0 = no buffering.
@export var jump_buffer_time: float = 0.15

@export_group("Acceleration")
## Ground move smoothing — the fraction the velocity closes toward target per reference frame. Higher = snappier starts/stops; lower = more glide.
@export var smoothing: float = 0.135
## Divisor that WEAKENS smoothing in the air (settle rate = ground smoothing / this): how fast horizontal speed
## ABOVE your air ceiling — an air dash, a rocket shove, a slide-jump, a ram bounce, a grapple fling — settles
## back toward it. Speed at or BELOW the ceiling is never touched, so plain jump momentum is kept whole.
## Bigger = launched momentum lingers longer (10.0 leaves ~52% of the excess after a 0.81 s jump).
## ⭐This is the air BRAKE, not the accelerator — steering is air_accel / air_steer_accel below. It reads the
## SAME value it always has on purpose: apply_velocity adds explosion_velocity for the move and gives back only
## 1/blast_damp_divisor of it, so `velocity` permanently gains ~10.7% of a live blast every frame, and this is
## the rate that has always damped that leak. Retune it and every launch in the game carries further.
## Must be >= 1 (tests/test_managers_tuning.gd): 0 divides by zero, and under 1 the air would brake harder than
## the ground, inverting the whole floaty-air contract.
@export var air_smoothing_divisor: float = 10.0
## AIR ACCELERATION (m/s^2) along the direction you are holding — how fast you BUILD speed off the ground.
## Quake-shaped and purely additive: it only ever supplies the wish speed you are not already carrying that
## way, so it switches itself off at the ceiling and NEVER claws back a bhop chain, a grapple fling or a dash.
## Doubles as the counter-thrust when you hold a direction against your own travel (killing your own momentum
## has to be possible). 12.0 saturates the standing-jump wish (1.75 m/s) in 0.15 s — the first fifth of a full
## 0.81 s jump, and well inside a jump_cut_factor TAP's 0.32 s, so short hops steer too. 0 = no air build at all.
@export var air_accel: float = 12.0
## AIR STEERING — lateral acceleration (m/s^2) rotating your existing horizontal velocity toward the direction
## you are holding. A PURE ROTATION: your speed does not change, only your heading, which is why this can be
## generous without devaluing a paid movement chip. Expressed as an acceleration rather than a turn rate so
## authority scales inversely with momentum for free — the rate is this / your speed rad/s, i.e. 252 deg/s at a
## 5 m/s running jump (a 90-degree correction costs 44% of the airtime) but 105 deg/s on a 12 m/s bunny-hop
## chain (~84 degrees per hop), so a fast line still has to be planned. 0 = the vector you launch is the vector
## you land.
@export var air_steer_accel: float = 22.0
## Fraction of THIS frame's ground target speed a jump may build up to in the air. The real ceiling is
## max(the speed you left the ground with, ground target x this), so it only ever sets the FLOOR — it can never
## slow you down, and a running or bunny-hop takeoff always keeps its own speed as the ceiling. Because it
## scales the ground target, crouch / ADS / a drawn heavy weapon / encumbrance / crippled legs / AGILITY shape
## how hard you can BUILD in the air, and can never take away what you banked before you scoped.
## ⭐Keep it at or below walk_speed_mult (test-pinned): jumping repeatedly must never be a faster way to travel
## than walking — and, since noise_emitter gates the movement noise radius on is_on_floor(), a faster air tier
## would also be a QUIETER one.
## ⭐⭐IT IS ALSO THE FLAT SPOT IN THE MOMENTUM CURVE, which is why it is this low. Air travel is
## max(the speed you took off with, this tier) x airtime, so every ground speed BELOW the tier lands the same
## distance and a run-up buys nothing there. At 0.6 the tier was 3.0 m/s and a standing jump carried 2.05 m
## against a sprint's 4.00 — barely 2x for a full run-up. At 0.35 the tier is 1.75, a standing jump carries
## 1.29 m, and (with jump_momentum_boost) a sprint carries 4.60: a 3.6x spread. RAISING this flattens the
## reward for running; it does not make the air more controllable, because STEERING is a pure rotation and is
## not scaled by it at all.
## The tier it scales is whichever one the ground chain reports THIS frame, so holding Run in the air asks for
## 5.0 x 0.35 = 1.75 while the default walk tier asks for 3.5 x 0.35 = 1.23. That is deliberate — Run costs no
## stamina off the floor because _wants_sprint gates on is_on_floor, so it reads as "lean into the jump", not
## as a second speed economy — and the Player latches the tier as a per-airtime HIGH-WATER, so letting go of
## Run mid-flight stops you building further without clawing back what you built.
@export var air_speed_mult: float = 0.35
## FPS the smoothing values are tuned for; movement is rescaled to this so accel feels identical at any framerate. Don't change unless retuning all smoothing.
@export var smoothing_reference_fps: float = 60.0

@export_group("Footsteps")
## Seconds between footstep sounds at full run speed — the step cadence (faster movement shortens it). Smaller = quicker footfalls.
@export var footstep_base_interval: float = 0.4
## Horizontal speed (m/s) below which footsteps stop playing — the standing-still cutoff.
@export var footstep_min_horizontal_speed: float = 0.5
## dB cut applied to footstep loudness at the SLOW end (a creep near footstep_min_horizontal_speed), eased to 0
## (full authored loudness) at max_speed — so a sprint is loud and a slow sneak is quiet. Stacks on top of the
## crouch cut (PlayerCrouchSettings.quiet_footstep_db). Negative = quieter when moving slowly; 0 disables the effect.
@export var footstep_slow_volume_db: float = -8.0

@export_group("Landing")
## Divisor turning landing fall-speed into a 0..1 impact strength (speed / this, clamped) that scales camera dip, FOV kick and land SFX. Bigger = only very fast falls read as a hard landing.
@export var landing_impact_divisor: float = 20.0
## Seconds of continuous DESCENDING airtime before the player dies. 0 disables the environmental long-fall kill.
@export var max_continuous_fall_time: float = 4.0

@export_group("Stairs")
## Maximum vertical ledge height (m) the player can auto-step up while grounded. This lets brush stairs / curbs act like walkable terrain without turning every staircase into a ramp collider. 0 disables step assist.
@export var step_up_height: float = 0.6
## Extra downward snap distance (m) after a successful step-up, and the CharacterBody floor snap length while walking. Keep this at least as high as step_up_height so descending stairs stay grounded.
@export var step_down_snap: float = 0.65
## Minimum horizontal speed (m/s) before step assist runs. Prevents idle wall contacts / tiny collision recovery from lifting the player.
@export var step_min_horizontal_speed: float = 0.2

@export_group("Stamina")
## Maximum stamina points available for special movement abilities.
@export var max_stamina: float = 100.0
## Stamina restored per second while standing still on the ground.
@export var stamina_regen_idle: float = 24.0
## Stamina restored per second while moving on the ground.
@export var stamina_regen_moving: float = 12.0
## Stamina restored per second while airborne.
@export var stamina_regen_airborne: float = 8.0
## Stamina restored per second while in a special movement state that is not actively draining.
@export var stamina_regen_active: float = 4.0
## Seconds after spending stamina before natural recovery resumes. Applies to the MOVEMENT verbs (jump, slide,
## dash, grapple, and the per-frame sprint / wall-climb drains); a SHOT holds regen for the longer
## stamina_regen_delay_after_shot below instead. Every spend re-FLOORS this countdown rather than adding to it,
## so holding a drain down keeps regen frozen for as long as it lasts plus this tail.
## ⚠ Raising this is felt hardest by BUNNYHOPPING, where a chain of jumps re-arms it on every launch.
@export var stamina_regen_delay_after_spend: float = 0.35
## Seconds a RANGED SHOT holds off recovery — deliberately much longer than the movement delay above, and the
## knob that decides whether shooting can deplete you at all.
##
## ⭐ THE RULE: keep this ABOVE the slowest weapon's attack_speed (the shotgun's 1.4s), or that weapon
## regenerates between its own shots and can never run you down however much its shot costs. At 0.35s the pistol
## refunded 24.0 x (0.44 - 0.35) = 2.16 standing still against a 1.8 cost — it literally paid for itself, and no
## amount of firing depleted the pool. At 1.5s NO shipped weapon earns a refund between consecutive shots, so
## sustained fire is pure drain and the magazine sizes above become the real budget.
## tests/test_combat_data.gd fails if a weapon is ever authored slower than this.
@export var stamina_regen_delay_after_shot: float = 1.5
## Stamina drained per second while moving at the full run tier.
@export var stamina_sprint_drain: float = 18.0
## Seconds sprint stays unavailable after running drains stamina to empty.
@export var stamina_sprint_lockout: float = 3.0
## One-time stamina cost when a buffered/coyote jump actually launches.
@export var stamina_jump_cost: float = 10.0
## One-time stamina cost to fire the grappling hook, including a miss.
@export var stamina_grapple_fire_cost: float = 18.0
## Stamina drained per second while the grappling hook is attached.
@export var stamina_grapple_attached_drain: float = 10.0
## Stamina drained per second while actively wall-climbing.
@export var stamina_wall_climb_drain: float = 16.0
## One-time stamina cost for the air dash.
@export var stamina_air_dash_cost: float = 25.0
## One-time stamina cost when a fast crouched landing starts a slide.
@export var stamina_slide_start_cost: float = 12.0
## One-time stamina cost when a melee weapon swing actually starts.
@export var stamina_melee_attack_cost: float = 14.0
## Stamina charged per UNIT OF PER-SHOT EFFORT when a ranged shot actually leaves the barrel (after the ammo is
## consumed). The weapon's effort comes from WeaponData.stamina_effort() — damage, pellets and blast payload —
## normalised so a plain 1.0-damage single-projectile round scores exactly 1.0, so this number reads as "what one
## baseline shot costs". A grenade launcher (effort 8.0) therefore costs 8x a baseline round without anyone hand-
## pricing it; WeaponData.stamina_cost_mult is only a trim on the result. 0 = shooting is free for every gun.
##
## Unlike a melee swing this NEVER refuses the attack, so an exhausted player is never left with no way to fight
## back: a pool ALREADY at/below zero makes the shot free, and a pool that is positive but short pays in full and
## OVERDRAWS into debt (the same Dark-Souls overdraw jump/melee/slide already have). The bite is that sustained
## fire holds off regen and eats the sprint budget — and that the debt itself briefly refuses every GATED verb,
## fists included.
##
## ⭐ The one bound to respect: too HIGH and the heaviest weapon rails against stamina_shot_drain_ceiling below
## (the launcher's 15.39 / effort 8.0 = 1.92) where the price stops tracking the weapon and it gets silently
## CHEAPER as it grows stronger. There is no longer a lower bound from regen — stamina_regen_delay_after_shot now
## outlasts every weapon's cadence, so nothing earns a refund between its own shots and any positive cost really
## depletes. (Before that hold existed this dial was boxed into a ~16% band, because the launcher had to out-cost
## the 13.2 it regenerated during its own 0.9s cadence.) Retune the whole roster together here rather than
## reaching for per-weapon trims.
@export var stamina_shot_cost: float = 1.8
## Hard cap on a shot's cost, as a FRACTION of stamina_sprint_drain x the weapon's attack_speed — so no weapon,
## however it is authored, can ever drain more than this share of the sprint rate on a held trigger. This is what
## makes "shooting never costs more per second than running" a THEOREM rather than a thing a designer can break by
## pairing a big payload with a fast cadence. Keep it under 1.0; the shipped 0.95 leaves the invariant strictly
## true (0.95 x 18.0 = 17.1/s < 18.0/s) while leaving the grenade launcher 6% of headroom under its own cap.
## ⚠ A weapon that HITS this cap gets silently CHEAPER as it grows more powerful, because the derived price is
## discarded — tests/test_combat_data.gd pins that no shipped weapon is clamped, so that failure is loud.
@export var stamina_shot_drain_ceiling: float = 0.95
