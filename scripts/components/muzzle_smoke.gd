class_name MuzzleSmoke
extends GPUParticles3D

## Barrel smoke: a white CARTOON CURL — a serpentine strand of overlapping puffs that appears a beat AFTER the
## shot, billows UP off the muzzle in a lazy S and peters out. Fired from Attack.flash_muzzle, the same signal
## the flash mesh, the sparks and the whiz already ride, so the firing pipeline gains no new call site.
##
## DROP-IN: instance scenes/effects/muzzle_smoke.tscn under any muzzle marker and connect
## Attack.flash_muzzle to _on_attack_flash_muzzle. Give it the wielder's weapon source for the per-weapon
## gate — EITHER the `inventory` (the player's gun rig sets it in GunMesh.setup) OR the firing `attack`
## (the NPC's in-hand gun sets it in npc.gd _build_muzzle_fx), exactly like SparkAttack. With NEITHER set
## it still smokes at the authored size, so a wiring miss degrades to "always smokes", never to "never smokes".
##
## ⭐THE SHOT AND THE SMOKE ARE TWO EVENTS, NOT ONE. Smoke that blooms on the same frame as the muzzle flash
## reads as part of the flash and the shot loses its punch — that was the first version's worst tell. So a
## shot only ARMS `muzzle_smoke_delay`. ⭐But the delay has to stay SHORT and the onset SOFT, or you trade one
## bad read for another: a long delay plus emission snapping to full flow pops a cluster of puffs into
## existence out of nowhere, which is jarring in a different way than blooming on the flash. So the delay is a
## beat (~0.05 s), and the envelope rides the emitter's `amount_ratio`: SWELL IN over `muzzle_smoke_attack`,
## hold for `muzzle_smoke_hold`, PETER OUT over `muzzle_smoke_taper`. All in `delta` so they pause with the tree.
##
## ⭐WHY THIS IS A HOT-BARREL GATE AND NOT A ONE-SHOT PUFF. The sparks and the casing use `restart()`, which
## re-fires their emitter from frame zero — right for a burst that must land ON the shot. Smoke is the
## opposite shape: it has to KEEP being made, so `restart()` is exactly wrong here (on full-auto it would
## wipe the puffs 10x a second and you would never see more than one). The emitter is CONTINUOUS (`one_shot`
## off, explosiveness 0) and a shot mid-stream only refreshes the hold — and must NOT re-arm the delay, or a
## held trigger would smoke only after you stopped firing.
##
## ⭐WHY IT READS AS A CURVING LINE AND NOT AS A ROW OF BEADS OR A FAT ROPE. Mostly authored on the material /
## scene; the sweep itself is `_drive_wave` below:
##  * CONNECTED, NOT DISCRETE. 112 puffs at `muzzle_smoke_alpha` 0.24, strung ~4 mm apart along a strand whose
##    own puffs are 15-28 mm across — so every point of the line is 4-7 puffs deep and they SUM into one body.
##    That inverts the previous pass, which wanted ~40 fat puffs at 0.42 reading INDIVIDUALLY. Count and alpha
##    are one knob in two halves and must move together: 112 at 0.42 accumulates to ~0.98 and photographs as a
##    solid white cotton rope with no shape in it; 40 at 0.24 photographs as a dotted line.
##  * The material's albedo is a radial `GradientTexture2D` whose alpha now falls away from just 22% of the
##    radius with a long shoulder. ⭐This is the beads-vs-line knob and it is easy to get backwards: the old
##    solid core out to 55% gave every disc a VISIBLE RIM, and at 4-7 deep overlap you read the rims, i.e. the
##    beads, instead of the strand.
##  * BILLOW. Buoyancy is a gentle +0.08 m/s² (`gravity` on the process material, re-aimed at true world up
##    every frame by `_drive_wave`) on top of a flat 0.24 m/s launch, so the strand stretches as it climbs.
##  * ⭐A SPINDLE, NOT A GROWTH CURVE — this is what gives the curl a SHARP TIP. `scale_curve` runs
##    0.35 -> 1.0 at 42% of life -> 0.20, so a puff swells as it leaves the barrel and then shrinks again as it
##    ages. Because the OLDEST puffs are the ones at the TOP of the strand, a plain monotonic growth curve
##    (which is what shipped first) makes the tip the single fattest, most diffuse part of the whole effect —
##    it ends in a blunt rounded blob. Bringing the curve back down means the strand narrows to a point at the
##    top instead. ⭐Tune the tip on the curve's value around 0.6-0.9 of life, NOT its value at 1.0: emission
##    stops when `muzzle_smoke_hold` runs out, so at the moment the curl is fully grown the oldest puff alive
##    is only `hold / lifetime` (~0.85) of the way through its life and never reaches the final point at all.
##  * ⭐NO RANDOMNESS ANYWHERE. `spread`, `randomness`, `damping`, the `angle` range, the velocity min/max
##    spread and turbulence's strength are ALL zeroed, and that is load-bearing rather than lazy authoring: a
##    coherent line exists only because every puff traces the SAME path, so each of those is a way to fray it
##    back into a cloud. In particular `initial_velocity_min` must EQUAL `max`, or puffs of equal age sit at
##    different heights and the line thickens into a band.
##  * ⭐AND `damping` MUST STAY 0. Godot's damping is a LINEAR speed decay, not a proportional one, so the old
##    2.0-3.2 against a 0.35 buoyancy drove every puff's velocity to zero within ~0.1 s and re-clamped it there
##    for the rest of its life. Total travel was 0.5-13 mm — less than one puff's own diameter. That is the
##    real reason the old effect read as "a handful of balls of smoke": the puffs were not billowing anywhere,
##    they were sitting on the muzzle swelling in place.
##  * ⭐⭐ALIGNED WITH THE MUZZLE, ALWAYS — `local_coords = true`. This one was arrived at the hard way and
##    is easy to "fix" back into a bug. World-space particles (`local_coords` off) look right standing still
##    and are GONE the moment you advance: at run speed the whole cluster is behind the camera within a few
##    tenths of a second. `inherit_velocity_ratio` is the world-space remedy and it is NOT sufficient — 0.75
##    still lost the cluster at 3.2 m/s, and even at 1.0 the damping that shapes the puff bleeds the
##    inherited speed right back off, so the smoke strings out behind you. Simulating in LOCAL space welds
##    the puffs to the barrel, which is what "pretty much always aligned with the muzzle" actually requires.
##    The trade is real and deliberate: there is no world-space trail left behind when you turn. The cost of
##    local space is that `direction` and `gravity` are LOCAL vectors, so buoyancy tilts with the gun —
##    `_drive_wave` rewrites both at true world up every frame to buy back the rise without giving up the weld.
##    `inherit_velocity_ratio` is pinned to 0 because in local space the emitter's own motion is already
##    accounted for.
##  * `fixed_fps = 0`. At the default 30 Hz the emitter drops beads along a fast-swinging barrel — and it would
##    also halve the rate at which the swept birth offset gets sampled, which is what draws the curve.
## The rest is likewise authored: per-particle fade is the `color_ramp`, girth at the muzzle is the small
## SPHERE emission shape — all in the Inspector on the scene. This script only writes what a designer CANNOT
## bake into a resource: the opacity knob, the taper, the per-weapon size, and the three vectors that depend on
## where world up and the camera are — onto a PRIVATE duplicate of the process material (the ShellDrop idiom)
## so one gun's tuning never bleeds into another's.
##
## ⭐⭐JUDGE THIS BY EYE, NEVER BY TEST. --headless does not compile a particle shader at all, so every
## property here can round-trip perfectly and still render as garbage — this effect shipped twice on green
## tests and looked wrong both times. `scripts/tools/muzzle_smoke_qa_shots.gd` is the harness: it boots the
## real game, equips a gun, fires, and photographs the barrel from the eye and through a zoom lens.
##
## ⭐That authored ramp/curve/turbulence/emission-shape combination generates its OWN ParticlesShaderRD
## variant, and on this machine a FIRST-TIME particle-pipeline compile is what the NVIDIA D3D12 shader
## compiler has been crashing inside. That is why PreloadManager warms this scene at boot — the compile
## happens once, during load, and is cached from then on. Do not remove it from that list.
##
## ⭐⭐AND IT IS WHY `turbulence_enabled` IS STILL TRUE WITH ITS STRENGTH AT 0. The curl wants no turbulence at
## all, but `turbulence_enabled` is one of the handful of properties that GENERATES SHADER CODE rather than
## feeding a uniform — flipping it off would have made the whole pipeline first-time-new again and bought a
## fresh roll of that crash for a change with no visual gain. Neutralising it by VALUE is visually identical
## and keeps the variant byte-identical, so this entire pass ships without a single recompile. The others that
## generate code rather than feeding a uniform, all deliberately untouched here: the `emission_shape` enum, the
## particle flags, and assigning or clearing any curve/ramp slot. Retune the numbers freely; think hard before
## flipping one of those switches, and warm it at boot if you do.
##
## ⭐⭐BUT NEUTRALISE IT WITH `turbulence_influence`, NEVER WITH `turbulence_noise_strength`. This one is a trap
## and it cost a photograph pass. Turbulence is applied as a LERP OF VELOCITY TOWARD the noise vector scaled by
## the strength — so `strength = 0` does not mean "no turbulence", it means "every frame, pull this particle's
## velocity 2% of the way toward ZERO". That is an exponential brake with a time constant of dt/influence, and
## it is frame-rate dependent on top. At influence 0.02 and 111 fps it cut the column from the arithmetic's
## 23 cm to a measured ~5 cm and the curl flattened into a horizontal smear. `influence = 0` makes the mix a
## genuine no-op whatever the strength is. Same shape of bug as the `damping` one above: the two knobs that
## look like "amount of wobble" are both really "how fast do I kill the motion".

## The player's equipped-weapon source for the per-weapon smoke gate — read on each shot for
## has_muzzle_flash + WeaponData.muzzle_smoke_scale. Leave unset on an NPC gun (it uses the code-set `attack`).
@export var inventory: Inventory
## The firing Attack, set in code by the NPC's muzzle-FX builder. The `inventory` equivalent for a held NPC gun.
var attack: Attack = null

var _proc_mat: ParticleProcessMaterial  ## private copy of process_material — the only thing this script writes
var _base_scale_min: float = 1.0        ## authored particle draw scale, captured so the weapon size is relative
var _base_scale_max: float = 1.0
var _delay_left: float = 0.0            ## seconds until the barrel STARTS smoking; the beat after the bang
var _hot_left: float = 0.0              ## seconds of "barrel still smoking" left; only counted once it starts
var _emit_age: float = 0.0              ## seconds since emission actually began; drives the swell-in
var _size_mult: float = 0.0             ## last size written to the material, so a repeat shot touches nothing
var _wave_phase: float = 0.0            ## sweep phase in radians; zeroed when a FRESH stream opens so the curl always leaves the muzzle CENTRED
var _cool_left: float = 0.0             ## seconds of puffs still in the air after emission stopped — their buoyancy must keep being re-aimed at world up
var _rise_accel: float = 0.0            ## magnitude of the AUTHORED gravity vector; this script only ever re-aims it, the designer still owns how strong it is


## Take a private copy of the process material (the ShellDrop idiom) so the per-weapon size can never bleed
## into another emitter sharing the authored resource, and capture the authored draw scale as the 1.0
## baseline. Idle until the first shot: nothing emits and _process does not run.
func _ready() -> void:
	var pm := process_material as ParticleProcessMaterial
	if pm != null:
		_proc_mat = pm.duplicate() as ParticleProcessMaterial
		process_material = _proc_mat
		_base_scale_min = pm.scale_min
		_base_scale_max = pm.scale_max
		# The designer owns the buoyancy STRENGTH on the material; this script owns only its DIRECTION (see
		# _drive_wave). Capture the authored magnitude once so re-aiming can never change how fast the smoke
		# climbs — retuning `gravity` in the Inspector still bites, it just always ends up pointing at world up.
		_rise_accel = pm.gravity.length()
		_proc_mat.emission_shape_offset = Vector3.ZERO
	emitting = false
	set_process(false)


## One shot -> arm the barrel. Deliberately does NOT restart the emitter (see the class doc): a shot mid-stream
## only re-arms the countdown, so sustained fire produces one continuous trail rather than ten truncated ones.
##
## ⭐The smoke does NOT start here. A round leaves the barrel long before anything smokes, so smoke that blooms
## on the same frame as the muzzle flash reads as part of the flash — one event instead of two, and the shot
## loses its punch. `muzzle_smoke_delay` is the beat between them: this call only ARMS the delay, and emission
## begins when that runs out. On sustained fire the delay is armed once (a second shot mid-delay must not push
## the start back, or a held trigger would smoke only after you stopped firing) while the hold keeps refreshing.
func _on_attack_flash_muzzle() -> void:
	if _proc_mat == null:
		return  # off-tree / bare instance (no _ready) — nothing to drive
	var size_mult := puff_scale(_weapon(), Settings.muzzle_smoke_scale)
	if size_mult <= 0.0:
		return  # melee/fists/spray (no muzzle flash), a weapon authored to muzzle_smoke_scale 0, or the player's dial at 0
	_apply_size(size_mult)
	# Opacity is a live designer knob rather than a baked ramp value, so a retune bites without re-authoring
	# the gradient. It multiplies the ramp, which owns the per-particle fade IN and OUT.
	_proc_mat.color.a = clampf(GameSettings.effects.muzzle_smoke_alpha, 0.0, 1.0)
	_hot_left = maxf(0.0, GameSettings.effects.muzzle_smoke_hold)
	if not emitting and _delay_left <= 0.0:
		_delay_left = maxf(0.0, GameSettings.effects.muzzle_smoke_delay)
		if _delay_left <= 0.0:
			_begin_emitting()   # delay authored to 0 -> smoke on the firing frame itself, no dead frame
	set_process(true)


## Two countdowns, in order: the DELAY after the bang before anything smokes, then the HOLD while the barrel
## streams. Both counted in `delta` rather than against a wall clock so they pause with the tree, and the node
## stops processing itself the moment it is done — the smoke already in the air needs nothing from this script
## to finish fading. The hold is deliberately NOT ticked during the delay, so `hold` always means "this long of
## actual smoke" no matter how the delay is tuned.
## ⭐Plus a COOL-DOWN that keeps this node processing until the last puff has died. That is not bookkeeping:
## `_drive_wave` re-aims the process material's `gravity` at TRUE world up every frame, and `gravity` is
## applied to every puff ALREADY IN THE AIR — so dropping out of _process the instant emission stops would let
## the whole tail of the curl swing over sideways the moment the player lowers or turns the gun.
func _process(delta: float) -> void:
	_drive_wave(delta)
	if _delay_left > 0.0:
		_delay_left -= delta
		if _delay_left <= 0.0:
			_begin_emitting()
		return
	if emitting:
		_emit_age += delta
		_hot_left -= delta
		# amount_ratio scales how many particles are actually emitted without reallocating the pool, so the whole
		# envelope rides it: SWELL IN over `muzzle_smoke_attack`, then PETER OUT over `muzzle_smoke_taper`. Both
		# ends matter for the same reason — emission that snaps to full flow POPS a cluster of puffs into existence
		# in one frame, and emission cut at full flow switches them off mid-puff. The min() of the two envelopes
		# means a short hold simply never reaches full flow, instead of fighting itself.
		var fx := GameSettings.effects
		var swell: float = clampf(_emit_age / maxf(0.001, fx.muzzle_smoke_attack), 0.0, 1.0)
		var fade: float = clampf(_hot_left / maxf(0.001, fx.muzzle_smoke_taper), 0.0, 1.0)
		amount_ratio = minf(swell, fade)
		if _hot_left > 0.0:
			return
		emitting = false
		_cool_left = lifetime   # the curl is still in the air; keep steering it until the last puff dies
		return
	_cool_left -= delta
	if _cool_left <= 0.0:
		set_process(false)


## Open the tap from zero. Emission always starts at amount_ratio 0 and swells, so the first thing you see is
## one wisp rather than the whole cluster arriving at once — the difference between smoke welling up out of
## the barrel and smoke being switched on. `_emit_age` is only reset HERE, never on a later shot, so sustained
## fire stays at full flow instead of re-swelling from nothing on every round.
func _begin_emitting() -> void:
	# A fresh stream always leaves the muzzle CENTRED rather than mid-swing. A shot fired mid-stream never
	# reaches here (the caller gates on `not emitting`), so a held trigger's wave is never snapped back.
	_wave_phase = 0.0
	_emit_age = 0.0
	amount_ratio = 0.0
	emitting = true


## ⭐⭐THIS IS THE WAVE. Sweep the BIRTH POSITION side to side as a sine of time, and puffs of different AGES
## end up at different lateral offsets AND different heights — which IS a sine wave drawn in space, growing up
## out of the barrel. It works because the particles shader writes a particle's position exactly ONCE, in its
## start() branch, from the emission shape + `emission_shape_offset`; process() thereafter only integrates
## velocity. So moving the offset moves ONLY the puffs born this frame and can never teleport the ones already
## in the air. (Contrast `scale_min`/`scale_max`, which process() re-reads EVERY frame — that asymmetry is
## exactly why _apply_size refuses to rewrite them for an unchanged weapon, and why this may rewrite freely.)
##
## ⭐THE EMISSION SHAPE MUST STAY SPHERE. `emission_shape_offset` is applied inside the emission-shape block of
## the generated shader, and a POINT emitter emits no such block. Switching to POINT is the one innocent-looking
## edit that silently switches the whole curl off while every property still round-trips green.
##
## ⭐AND it re-aims the rise at TRUE WORLD UP, which local space otherwise loses. `direction` and `gravity` are
## LOCAL vectors, so a rolled rig or a player looking up tips the whole column over. Before this pass the
## player's emitter carried a copy of the Spark instance's -86 degree roll, so "up" for it was the player's LEFT
## SHOULDER (99.8% world-left, 6.6% world-up) — THAT is why the smoke never billowed upward. The roll is gone
## from view_model.tscn now, but the authored vector still only tracks the gun, so it is rewritten here every
## frame: `direction` is read at BIRTH (it aims each new puff) and `gravity` is applied EVERY FRAME (it keeps
## steering the tail already in the air), which is why this must keep running through the cool-down.
##
## These are the only per-frame material writes in the project. They are here rather than on the resource
## because a resource cannot know where world up or the camera is; all three are plain shader UNIFORMS, so none
## of them can trigger a pipeline recompile — only the emission-shape enum, `turbulence_enabled`, the particle
## flags and assigning/clearing a curve slot do that, and this pass deliberately touches none of those.
func _drive_wave(delta: float) -> void:
	var fx := GameSettings.effects
	_wave_phase = fposmod(_wave_phase + delta * fx.muzzle_smoke_wave_hz * TAU, TAU)
	var binv := global_transform.basis.orthonormalized().inverse()
	var up_local: Vector3 = (binv * Vector3.UP).normalized()

	# The wave has to lie in the plane containing world up AND the axis PERPENDICULAR to the viewer's line of
	# sight, or it presents edge-on and collapses back into a straight line. Built from the ACTIVE camera, so an
	# NPC's plume faces the PLAYER rather than the NPC. For the player's own rig the emitter rides the camera,
	# so this resolves to the same vector every frame and cannot jitter.
	var sweep_local := Vector3(0.0, 0.0, 1.0)   # local +Z is camera-right on this rig; the degrade, not the answer
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var to_eye: Vector3 = cam.global_position - global_position
		to_eye -= Vector3.UP * to_eye.dot(Vector3.UP)     # flatten: the sweep stays level, it never tilts with the look
		var sweep_world: Vector3
		if to_eye.length_squared() > 0.0025:              # >5 cm apart; the player's own muzzle sits ~34 cm out
			sweep_world = Vector3.UP.cross(to_eye).normalized()
		else:
			var r: Vector3 = cam.global_transform.basis.x
			r -= Vector3.UP * r.dot(Vector3.UP)           # strip screen-shake roll out of the degenerate fallback
			sweep_world = r.normalized() if r.length_squared() > 1e-6 else Vector3.RIGHT
		var s: Vector3 = binv * sweep_world
		s -= up_local * s.dot(up_local)                   # strictly perpendicular to the rise, so the plane never shears
		if s.length_squared() > 1e-6:
			sweep_local = s.normalized()

	# Amplitude rides the per-weapon puff size by its SQUARE ROOT: a rock launcher at muzzle_smoke_scale 2.1
	# gets a 1.45x wider serpent, not a 2.1x one that swings clean out of frame.
	var amp: float = fx.muzzle_smoke_wave_amp * sqrt(maxf(_size_mult, 0.0001))
	_proc_mat.emission_shape_offset = sweep_local * (amp * sin(_wave_phase))
	_proc_mat.direction = up_local
	_proc_mat.gravity = up_local * _rise_accel


## Scale the particle DRAW size by the weapon's muzzle_smoke_scale (x the player's dial). Skipped when the
## value is unchanged — the common case is the same gun firing again, and rewriting the uniform would
## needlessly resize the wisp already in the air.
func _apply_size(mult: float) -> void:
	if is_equal_approx(mult, _size_mult):
		return
	_size_mult = mult
	_proc_mat.scale_min = _base_scale_min * mult
	_proc_mat.scale_max = _base_scale_max * mult


## The weapon this muzzle is currently wearing, from whichever source was wired (player Inventory or the
## NPC's own Attack). null = no source wired at all, which puff_scale treats as "smoke at the authored size".
func _weapon() -> WeaponData:
	if inventory != null:
		return inventory.equipped_weapon
	if attack != null:
		return attack.current_weapon
	return null


## PURE size rule for one shot's smoke, split out static so its truth table is unit-testable off-tree (the
## GunMesh.view_model_visible_now idiom). Returns the size multiplier over the authored wisp; 0 = don't
## smoke at all.
##  - `user_scale` is the player's Options dial (Settings.muzzle_smoke_scale), clamped 0..1; 0 turns the
##    whole effect off for everyone, which is why it is checked first.
##  - A null weapon means NO weapon source was wired (a bare rig / a test scene), not "unarmed" — degrade
##    to the authored wisp exactly as MuzzleFlash and SparkAttack degrade to flashing/sparking.
##  - has_muzzle_flash is the project's existing "this is a gun that goes bang" flag (false on melee,
##    fists and the spray can), so it gates the smoke too — no weapon needs re-authoring to stop smoking.
##  - WeaponData.muzzle_smoke_scale is then the per-gun dial: a big bore belches, a small one wisps, 0 = dry.
static func puff_scale(weapon: WeaponData, user_scale: float) -> float:
	var user := clampf(user_scale, 0.0, 1.0)
	if user <= 0.0:
		return 0.0
	if weapon == null:
		return user
	if not weapon.has_muzzle_flash:
		return 0.0
	return maxf(0.0, weapon.muzzle_smoke_scale) * user
