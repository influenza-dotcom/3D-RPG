class_name MuzzleSmoke
extends GPUParticles3D

## Barrel smoke: a handful of small white CARTOON puffs that appear a beat AFTER the shot, billow up off the
## muzzle and peter out. Fired from Attack.flash_muzzle, the same signal the flash mesh, the sparks and the
## whiz already ride, so the firing pipeline gains no new call site.
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
## ⭐WHY IT READS AS CARTOON PUFFS AND NOT AS HAZE OR AS BEADS. All authored on the material / scene, not here:
##  * DISCRETE, ROUNDED, OPAQUE-ISH. ~70 puffs at `muzzle_smoke_alpha` 0.42 — few enough and solid enough to
##    read INDIVIDUALLY. The material's albedo is a radial `GradientTexture2D` whose alpha holds at 1.0 out to
##    55% of the radius before falling off, i.e. a defined disc with a soft rim, not a gaussian smudge. A
##    gentle falloff plus hundreds of near-transparent puffs is the opposite look (a connected realistic
##    haze) and was what shipped before this pass — if you want that back, the two knobs are this gradient
##    and `amount`/alpha together, never one of them alone.
##  * BILLOW. Gravity is +Y 1.15 (buoyancy, not weight) and the `scale_curve` grows each puff ~3x over its
##    life, so the cluster visibly swells as it climbs off the barrel.
##  * ⭐⭐ALIGNED WITH THE MUZZLE, ALWAYS — `local_coords = true`. This one was arrived at the hard way and
##    is easy to "fix" back into a bug. World-space particles (`local_coords` off) look right standing still
##    and are GONE the moment you advance: at run speed the whole cluster is behind the camera within a few
##    tenths of a second. `inherit_velocity_ratio` is the world-space remedy and it is NOT sufficient — 0.75
##    still lost the cluster at 3.2 m/s, and even at 1.0 the damping that shapes the puff bleeds the
##    inherited speed right back off, so the smoke strings out behind you. Simulating in LOCAL space welds
##    the puffs to the barrel, which is what "pretty much always aligned with the muzzle" actually requires.
##    The trade is real and deliberate: there is no world-space trail left behind when you turn. The cost of
##    local space is that `gravity` is a LOCAL vector, so the +Y buoyancy tilts with the gun's pitch — small
##    and short-lived enough not to read here, but it is why the rise is gentle. `inherit_velocity_ratio` is
##    pinned to 0 because in local space the emitter's own motion is already accounted for.
##  * `fixed_fps = 0`. At the default 30 Hz the emitter drops beads along a fast-swinging barrel.
## The rest is likewise authored: per-particle fade is the `color_ramp`, girth at the muzzle is the small
## SPHERE emission shape, and the drift/curl is damping + turbulence — all in the Inspector on the scene.
## This script only writes what a designer CANNOT bake into the resource: the opacity knob, the taper, and
## the per-weapon size, onto a PRIVATE duplicate of the process material (the ShellDrop idiom) so one gun's
## tuning never bleeds into another's.
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
func _process(delta: float) -> void:
	if _delay_left > 0.0:
		_delay_left -= delta
		if _delay_left <= 0.0:
			_begin_emitting()
		return
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
	set_process(false)


## Open the tap from zero. Emission always starts at amount_ratio 0 and swells, so the first thing you see is
## one wisp rather than the whole cluster arriving at once — the difference between smoke welling up out of
## the barrel and smoke being switched on. `_emit_age` is only reset HERE, never on a later shot, so sustained
## fire stays at full flow instead of re-swelling from nothing on every round.
func _begin_emitting() -> void:
	_emit_age = 0.0
	amount_ratio = 0.0
	emitting = true


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
