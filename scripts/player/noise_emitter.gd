class_name NoiseEmitter
extends Node

## Computes how far the player's noise currently carries and writes it back to the host each frame —
## the stealth signal enemies hear. THREE channels, and the LOUDEST of them wins each frame:
##   • a decaying GUNFIRE spike (gunfire(), from Player.on_weapon_fired);
##   • a decaying IMPACT spike — the jump push-off and the landing thud (jump() / land(), see below);
##   • continuous ground-speed FOOTSTEP noise.
## Crouch-walking and creeping below the footstep cutoff stay silent, and being airborne is silent on the
## FOOTSTEP channel only — the jump that put you there and the landing that ends it are both heard.
## Built in code under the Player and given a host ref right after .new().
##
## noise_radius (the value enemy Perception.can_hear() reads via player.get("noise_radius")) and the
## noise_* tuning exports stay ON THE PLAYER — this component only WRITES host.noise_radius from
## tick(delta).

var host: Player

var _gunfire_noise: float = 0.0
## The jump/landing THUD spike — the impact channel, decayed the same way the gunfire one is but with its own
## radius + decay tuning, because a body hitting the ground is a different sound from a shot. Held at full radius
## for host.noise_impact_hold seconds first; see _spike() for why that hold is load-bearing rather than feel.
var _impact_noise: float = 0.0
## Seconds of full-radius HOLD still owed to _impact_noise. Counts down in tick(); the decay only starts once it
## reaches 0.
var _impact_hold_t: float = 0.0
## The player's LIVE entry in the shared &"noise" channel — a persistent NoiseSource at the player whose
## radius we mirror from noise_radius each frame, so NPCs that haven't yet acquired the player can still hear
## gunshots / footsteps and investigate (the same channel a thrown decoy uses). Lazily created the first
## in-tree tick; nothing reads it unless GameSettings.npc_ai.hearing_initiates is on, so it's inert by default.
var _source: NoiseSource = null

## Register a gunshot — the loud spike that nearby enemies hear, which then decays back to silence.
## `mult` is the weapon's noise_radius_mult (a suppressor scales this down) — the ONE weapon-side stealth
## lever, and the only reason this takes an argument at all. Default 1.0 keeps every existing caller intact:
## Player.on_weapon_fired is the only gameplay one, and scripts/tools/noise_ring_qa_shots.gd (the dev radius
## probe) deliberately stays at the default so the ring it draws is the host's authored radius, unscaled.
## Clamped at 0 so a negative authored mult silences the shot rather than inverting the decay in tick().
func gunfire(mult: float = 1.0) -> void:
	_gunfire_noise = host.noise_gunfire_radius * maxf(0.0, mult)

## Register a JUMP — the push-off grunt and the shove against the floor. A flat, impact-independent spike
## (host.noise_jump_radius): you always leave the ground with the same shove, and unlike the landing there is no
## fall to measure. Called from the one gameplay jump site in player.gd, INSIDE the stamina-spend branch — a jump
## that never fires makes no sound and must make no noise.
##
## ⭐It is deliberately NOT scaled by crouch, and neither is land(). Crouch buys silent MOVEMENT (the 1 - crouch_t
## on the footstep channel below); it does not buy a silent hop. That also keeps this channel honest against what
## the world can actually hear: Player's jump_sound and Landing's land SFX both play at FULL volume while crouched
## (on_land's crouch softening is explicitly presentation-only — camera/gun/shake/HUD), so a crouch-silenced noise
## radius would mean a thud the player hears and the guard beside them does not.
func jump() -> void:
	_spike(host.noise_jump_radius)

## Register a LANDING — the touchdown thud. `impact` is Landing.impact_for()'s 0..1 landing strength (the SAME
## number the camera dip, the land SFX and the dust read), so one touchdown is one loudness across every channel.
## Radius is a BASE thud plus an impact bonus (host.noise_land_radius + impact * host.noise_land_impact_bonus):
## the base is there because a thud has a body to it at all, and the bonus is what makes a rooftop drop carry
## nearly as far as a gunshot while a hop off a crate does not.
##
## ⭐GATED ON THE SAME CUTOFF AS THE LAND SFX (GameSettings.audio.land_sfx_min_impact_to_play): under it no
## landing thump PLAYS, so there is nothing for an enemy to hear either — the NoiseEmitter house rule already used
## for the footstep deadzone (footstep_min_horizontal_speed, below). Sharing the cutoff is what stops "I heard a
## thud" and "an NPC heard a thud" from ever drifting apart, and it keeps stepping down a kerb free.
##
## Takes the RAW impact, not on_land's crouch-dampened one — see the ⭐ on jump(), and note that fall damage reads
## the raw fall too: crouching changes how a landing LOOKS, never how far you fell.
func land(impact: float) -> void:
	if impact < GameSettings.audio.land_sfx_min_impact_to_play:
		return
	_spike(host.noise_land_radius + clampf(impact, 0.0, 1.0) * host.noise_land_impact_bonus)

## Arm the impact channel at `radius` and re-arm its full-radius hold. maxf against the live value so a chain of
## impacts reports the LOUDEST of them rather than the LAST — a bunny-hop lands and jumps a frame apart, and the
## quieter push-off must not cut the landing thud short.
##
## ⭐WHY THE HOLD EXISTS, and why it is correctness rather than feel: an idle NPC only walks the &"noise" group
## every GameSettings.npc_ai.distraction_scan_interval seconds (0.3 s as shipped). A spike whose radius/decay
## lifetime is shorter than that window can EXPIRE BETWEEN SCANS and be missed entirely — while a hostile that
## already holds you as a target still hears it, because Perception.can_hear() runs every frame. That failure mode
## is invisible in a playtest (the feature looks half-working, never broken) and it couples two knobs in different
## files. Holding full radius for host.noise_impact_hold guarantees every scan window contains the event, whatever
## a designer does to the radii. Keep the hold above distraction_scan_interval — tests/test_player_jump_noise.gd
## pins that relationship.
func _spike(radius: float) -> void:
	var r := maxf(0.0, radius)
	if r <= 0.0:
		return  # a designer zeroed the radius: this event is silent, and must not re-arm a hold over a live spike
	_impact_noise = maxf(_impact_noise, r)
	_impact_hold_t = maxf(0.0, host.noise_impact_hold)

## GO SILENT NOW, and stay silent until something ticks again — zero every channel AND the live &"noise" source.
##
## ⭐Called from Player.die(), and it is not cosmetic: die() ends with set_physics_process(false), so tick() STOPS
## and whatever radius was last written stays frozen on host.noise_radius and on the live NoiseSource forever — a
## dead player who keeps ringing the neighbourhood from the spot they fell. The impact channel is what made that
## reachable in practice: a FALL death always runs Landing.on_land first (that is where _apply_fall_damage is
## called from), so without this every death-by-falling would leave a ~25 m siren at the body. Dying mid-sprint or
## mid-gunshot had the same shape and simply never came up. The revive (_respawn_at_checkpoint) turns physics back
## on and tick() recomputes from live state, so nothing here needs to latch.
func silence() -> void:
	_gunfire_noise = 0.0
	_impact_noise = 0.0
	_impact_hold_t = 0.0
	if is_instance_valid(host):
		host.noise_radius = 0.0
	if _source != null and is_instance_valid(_source):
		_source.radius = 0.0

## One frame of noise: age the gunfire + impact spikes, take the LOUDEST of them and the ground-speed footstep
## noise, and write the result back to host.noise_radius (0 = silent) AND into the shared &"noise" channel.
## ⭐The loudest-wins max is why a quiet event is free: a landing thud while sprinting is swallowed by the run's
## own (larger) radius, so the impact channel only ever CHANGES what an enemy hears when you were otherwise quiet
## — airborne, or standing still. That is exactly the hole this channel exists to close.
func tick(delta: float) -> void:
	_gunfire_noise = maxf(0.0, _gunfire_noise - host.noise_gunfire_decay * delta)
	# The impact spike HOLDS at full radius first, then decays. Both events are registered earlier in the same
	# physics frame than this tick (the jump block and Landing.on_land both run before Player._update_noise), so
	# the frame an impact lands is always a full-radius one.
	if _impact_hold_t > 0.0:
		_impact_hold_t = maxf(0.0, _impact_hold_t - delta)
	else:
		_impact_noise = maxf(0.0, _impact_noise - host.noise_impact_decay * delta)
	var move_noise := 0.0
	if host.is_on_floor():
		var ground_speed := Vector2(host.velocity.x, host.velocity.z).length()
		# STANDING-STILL DEADZONE — the same cutoff that gates the footstep SOUND (footstep_min_horizontal_speed,
		# Landing.tick_footsteps' `on_foot` test): under it no footfall plays, so there is nothing for an enemy to
		# hear either. Only the CUTOFF is shared, deliberately not the rest of that gate — a slide makes no footstep
		# sound but is fast movement an enemy should still hear, so it must not buy silence. It also keeps the stop
		# tail tidy: player.gd decelerates with an exponential lerp that asymptotes toward zero and never arrives, and
		# at the louder noise_move_per_speed that residual sliver is big enough to trickle out through the minimap
		# ring's 0.25 m snap for several frames after you stop. Under the cutoff we write a hard 0 instead.
		if ground_speed > GameSettings.player_movement.footstep_min_horizontal_speed:
			move_noise = ground_speed * host.noise_move_per_speed * (1.0 - host.crouch.crouch_t)
	host.noise_radius = maxf(move_noise, maxf(_gunfire_noise, _impact_noise))
	# Publish the same radius into the &"noise" group via a live source at the player. Off-tree (unit-test
	# stub host) this stays null and is skipped; in-tree it's created once and then just tracks noise_radius.
	if _source == null and is_instance_valid(host) and host.is_inside_tree():
		_source = NoiseSource.new()
		_source.emitter = host  # this noise IS the player — an NPC that investigates it has noticed THEM (2D "!" sting)
		host.add_child(_source)
	if _source != null:
		_source.radius = host.noise_radius
