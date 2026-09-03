class_name EffectPrewarmer
extends Node3D

## In-level warm-up of every combat spawnable — stage TWO of the first-kill / first-hit hitch fix (stage one is the
## boot-time PreloadManager._prewarm_gpu_particles SubViewport pass, which stays: it front-loads the particle
## PROCESS-shader DXC compiles during the boot screen, which no later pass can hide). GameRoot.load_level drives
## this one right after a level enters the tree, while the start-menu -> game swap is still on black: warm(camera)
## instances every WARM_PATHS scene ONCE inside the live World3D — frozen, muted, collision-less — parks the lot
## ~spawn_distance m in front of the live camera (a few per frame — scenes_per_frame) for frames_visible frames
## after the last one entered, then hides them and KEEPS them, hidden and process-disabled, for its own lifetime
## (never freed under a possibly in-flight compile). It also draws the code-built feedback nothing else can
## precompile: the damage number
## (DamageNumberPopup.build_label), the "!" alert icon (NpcBarkUi.build_icon), the confetti burst
## (Throwable.build_confetti_burst) and, for one frame, the 2D hit feedback (hurt flash, on-camera blood splatter,
## crosshair hitmarker) at a near-invisible alpha.
##
## WHY IN-LEVEL AND NOT THE BOOT SubViewport (the 2026-09-01 investigation; a real-renderer probe measured the
## first-kill frame at ~+45 ms and the first hit at ~+20 ms over a warm repeat in the same process, with `surface` /
## `spec` pipeline compiles appearing ONLY in the first-use phases; a cold shader cache adds DXC compiles on top):
##  * A draw pipeline (PSO) is keyed on the RENDERER-GLOBAL requirement set — the InkOutline normal-roughness
##    prepass, the 16-bit shadow atlases, cubemap shadows — which only exists once game.tscn (player rig + level) is
##    live. The boot viewport runs before any of that, and its instances are freed before those requirements flip,
##    so nothing it compiled matches the keys the first kill actually draws with.
##  * Lighting / soft-shadow / fog SPECIALIZATION compiles in the background and never stalls, but the FIRST draw of
##    a material under the live keys waits on its ubershader PSO synchronously — that is the residual stall, and
##    only a draw in the real World3D, inside the real camera's frustum, pays it early.
##  * The decal atlas is global: the first Decal carrying `bullet hole.png` (bullet holes AND blood splats share it)
##    repacks the whole atlas mid-combat, and the texture is evicted again when the last such decal fades. One
##    hidden bullet_hole_decal.tscn instance is kept alive under this node for its whole lifetime (the atlas KEEPER,
##    _ensure_decal_keeper) so the texture stays registered and the atlas never rebuilds mid-fight.
##  * 2D / canvas pipelines have NO precompilation in Godot at all — a near-transparent draw is the only warm.
##
## PROCESS-LIFETIME LATCH: PipelineHashMapRD keeps every PSO for the life of the process, so the draw pass runs ONCE
## per process (`_warmed`) — a death reload_current_scene (which rebuilds game.tscn and this node) and a LevelDoor
## swap never re-pay the frames. The atlas keeper is the exception: it dies with game.tscn, so warm() re-creates it
## on every call, latched or not.
##
## NOT A DESIGNER DROP-IN in the usual sense: GameRoot builds one BY SCRIPT PATH (its @tool root must not depend on
## this class_name being in the editor's class cache) as a child of the game root — never under the LevelRoot, so
## the Ps1Warp applier that walks the level never touches the warm instances' materials. A hand-placed child named
## "EffectPrewarmer" beside the Player in game.tscn is reused instead, so the @exports below stay Inspector-tunable.
## Skipped entirely on the headless DisplayServer (nothing renders, so nothing compiles — the boot warm skips the
## same way), and never calls Settings.set_*.

## Every combat spawnable the FIRST kill / hit can draw, instanced once in the live world by warm(). A CONST list on
## purpose (the PreloadManager.PATHS idiom), NOT an @export: this is a COVERAGE CONTRACT, not a designer tunable —
## tests/test_effect_prewarm.gd ratchets it (every PreloadManager.PARTICLE_WARM_PATHS entry and every drawable
## PreloadManager.PATHS scene must be here, every entry must exist on disk) and fails naming the exact path to add,
## which an Inspector array could silently drift away from. Paths, not uid://, so it stays human-readable.
const WARM_PATHS: Array[String] = [
	# GPU-particle effects — their PROCESS shader was compiled by the boot pass; this pass builds the DRAW pipelines
	# of each draw-pass mesh + material (bloodmat, the dust / smoke sprites) under the live renderer keys.
	"res://scenes/effects/blood.tscn",
	"res://scenes/effects/bloody_mess.tscn",
	"res://scenes/effects/dust.tscn",
	"res://scenes/effects/dust_large.tscn",
	"res://scenes/effects/muzzle_smoke.tscn",
	"res://scenes/effects/shell_drop.tscn",
	"res://scenes/effects/spark_attack.tscn",
	# The death burst's 24 physics drops (a bare RigidBody3D; warmed for its _ready-time physics + audio setup).
	"res://scenes/effects/blood_drop.tscn",
	# The hit spark / blast: ExplosionMesh builds its cull-disabled emissive StandardMaterial3D in _ready, so this is
	# the ONE place that material's shader + PSO exist before the first shot. Configured harmless in _warm_scene.
	"res://scenes/effects/explosion_area.tscn",
	# Gore chassis: the meat chunk (model.obj is drawn by NO other scene) and the body-part chassis (a runtime load()
	# on the first death — pinned in PreloadManager.PATHS, drawn here).
	"res://scenes/effects/gore_gib.tscn",
	"res://scenes/effects/body_part_gib.tscn",
	# The death floor splat KEEPS its shadow-casting BloodLight on purpose: the first kill is otherwise the first
	# omni shadow pass (cubemap / dual-paraboloid depth pipelines over every caster in range) the level ever renders.
	"res://scenes/decals/blood_splat_decal.tscn",
	"res://scenes/decals/bullet_hole_decal.tscn",
	# Thrown-prop chassis + the projectile family (rounds, rock, sphere, the ejected casing) first drawn on the first shot.
	"res://scenes/throwable/cube.tscn",
	"res://scenes/projectiles/Projectile.tscn",
	"res://scenes/projectiles/rock_projectile.tscn",
	"res://scenes/projectiles/sphere_projectile.tscn",
	"res://scenes/projectiles/bullet_casing.tscn",
	# The shipped NPC "ragdoll" (NPC.tscn ragdoll_scene): bag.glb is never on screen before the first kill.
	"res://scenes/props/loot_bag.tscn",
]

## The hidden decal kept alive for the node's lifetime so `bullet hole.png` stays registered in the decal atlas.
const DECAL_KEEPER_PATH := "res://scenes/decals/bullet_hole_decal.tscn"
const DECAL_KEEPER_NODE := &"DecalAtlasKeeper"
## load(), not a class_name / preload reference, so this component never adds a parse-time edge onto Throwable.gd
## (the class_name<->preload cycle trap) — the same idiom PreloadManager uses for the same static.
const THROWABLE_SCRIPT_PATH := "res://scripts/components/Throwable.gd"
## The digits the damage-number warm rasterises: every glyph a damage number can show, at the live size + outline.
## Not player-facing copy — the label is drawn once, near-invisibly, on the black fade-in, then freed.
const WARM_DIGITS := "0123456789"
## Alpha the 2D pass draws at. ⭐Deliberately ABOVE 0.007: the canvas culler drops any item whose effective modulate
## alpha is below that, so a "safer" 0.004 would be culled and compile nothing. At 0.01 on the black fade-in it is
## invisible. (The hurt-flash ColorRect gets this on its `color`, not its modulate, so it is never culled either way.)
const WARM_2D_ALPHA: float = 0.01
## Effectively silent, and a real value the audio server accepts (a negative floor, not a dead positive knob).
const MUTE_DB: float = -80.0
## Warm instances are laid out in a grid this many columns wide, centred on the camera's forward axis.
const GRID_COLUMNS: int = 6

## How many WARM_PATHS scenes enter the tree per frame. ⭐Spread on purpose, never one burst: every first-drawn
## material queues its pipeline compiles on the WorkerThreadPool, and on THIS dev machine's NVIDIA D3D12 driver a
## burst of concurrent first-time compiles is the known heap-corruption crash class (WorkerThread N, ~90 KB stack of
## nvgpucomp frames — memory: hard-crash-is-nvidia-particle-shader-compile). A cold-cache probe run with all 19
## scenes instanced in ONE frame crashed twice at load, ~1 s after the compile batch; spreading them thins the
## concurrent compiles the driver has to survive at once. It also keeps each load frame short. The whole pass still
## finishes inside the fade-from-black.
@export_range(1, 19) var scenes_per_frame: int = 2
## Frames the warm instances stay VISIBLE in front of the camera AFTER the last one entered. The surface caches are
## built and the ubershader PSOs compiled on each instance's first drawn frame; these extra frames let the background
## specialization compiles queue up behind them while the instances (and their surface caches) still exist.
@export_range(1, 30) var frames_visible: int = 3
## Frames the instances stay in the tree HIDDEN after that. ⭐They are then NOT freed: the pass keeps them alive,
## hidden and process-disabled, for this node's lifetime (they die with game.tscn). Freeing a material whose
## background compile is still in flight is a use-after-free the engine cannot defend against on a slow (cold-cache)
## compile, and a handful of hidden nodes costs nothing — plus their materials/shaders can never be evicted and
## recompiled mid-fight. Set to 0 only if you want the hide to happen immediately after the visible hold.
@export_range(0, 30) var frames_hidden: int = 2
## Metres in front of the camera the warm instances are parked — inside the frustum, on the black fade-in. If a
## level's spawn faces a wall the draws are still issued (depth-rejected fragments still bind the pipeline).
@export_range(0.5, 10.0, 0.1) var spawn_distance: float = 2.0
## Metres between neighbouring warm instances in the grid — spread so several are in frame at once, not one pile.
@export_range(0.05, 2.0, 0.05) var spawn_spread: float = 0.35
## Also draw the 2D hit feedback (hurt flash, on-camera blood splatter, hitmarker) once at WARM_2D_ALPHA.
@export var warm_2d: bool = true

## Process-lifetime latch (see the class doc): the draw pass runs once per process, not once per game.tscn.
static var _warmed: bool = false

## Everything the current pass instanced; freed together after the hidden hold (the atlas keeper is NOT in here).
var _warm_nodes: Array[Node] = []


## The entry point GameRoot.load_level fires (through a small async helper) once the level, the Player and its
## camera rig are in the tree and the renderer-global requirements have been learned. `camera` = the live
## Camera3D the instances are parked in front of; null degrades to this node's own transform (draws may then fall
## outside the frustum and warm less — a dev warning says so). Async: awaits the visible + hidden holds.
func warm(camera: Camera3D) -> void:
	if DisplayServer.get_name() == "headless" or Engine.is_editor_hint() or not is_inside_tree():
		return
	# The keeper is per-game.tscn (it dies with the root on a death reload), so it is re-created on EVERY call —
	# before the latch, which only guards the once-per-process draw pass.
	_ensure_decal_keeper()
	if _warmed:
		return
	_warmed = true
	if camera == null and OS.is_debug_build():
		push_warning("EffectPrewarmer: no active Camera3D — warm instances are parked at the node's own transform (may fall outside the frustum)")
	var surface_before := int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE))
	var draw_before := int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW))
	var canvas_before := int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS))
	var slot := 0
	var scenes_warmed := 0
	var in_frame := 0
	for path in WARM_PATHS:
		# Cache hit: PreloadManager pinned every one of these at boot (its PATHS + PARTICLE_WARM_PATHS lists), so
		# this is a dictionary lookup, not disk I/O. A missing / mid-reimport scene is skipped with a warning rather
		# than aborting the pass — tests/test_effect_prewarm.gd is what keeps the list pointing at real files.
		var ps := load(path) as PackedScene
		if ps == null or not ps.can_instantiate():
			push_warning("EffectPrewarmer: could not load '%s' for the in-level warm (skipped)" % path)
			continue
		var inst := ps.instantiate()
		if inst == null:
			continue  # empty-PackedScene reimport transient -> instantiate() can return null; skip instead of crashing
		_warm_scene(inst, camera, slot)
		slot += 1
		scenes_warmed += 1
		in_frame += 1
		if in_frame >= scenes_per_frame:
			# Spread: let this frame draw (and queue its compiles) before the next batch enters — see scenes_per_frame.
			in_frame = 0
			if not await _hold_frames(1):
				return
	var built := _warm_code_built(camera, slot)
	if warm_2d:
		_warm_2d()
	# Hold VISIBLE: each instance's first drawn frame builds its surface cache + ubershader PSOs; then HIDDEN: the
	# instances (and their surface caches) outlive the background specialization compiles they queued — and stay
	# alive, hidden, from here on (see frames_hidden: nothing is freed while a compile could still be in flight).
	if not await _hold_frames(frames_visible):
		return
	visible = false
	if not await _hold_frames(frames_hidden):
		return
	var surface_delta := int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)) - surface_before
	var draw_delta := int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)) - draw_before
	var canvas_delta := int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS)) - canvas_before
	_park_warm_nodes()
	visible = true  # the parked instances stay hidden on their own flags; the node itself returns to its resting state
	if OS.is_debug_build():
		# The one dev read-out: `surface` is what this pass exists to move off the first kill; a non-zero `draw`
		# AFTER this pass (on the first real kill / hit) is a pipeline the warm missed — F3's Pipelines line shows it.
		print("EffectPrewarmer: warmed %d scenes + %d code-built effects (%d per frame, %d visible / %d hidden frames) — pipeline compiles during the pass: surface +%d, draw +%d, canvas +%d" % [
				scenes_warmed, built, scenes_per_frame, frames_visible, frames_hidden, surface_delta, draw_delta, canvas_delta])


## Await `count` process frames; false if this node left the tree meanwhile (a reload mid-warm — the instances
## were freed with us, there is nothing left to hide or free).
func _hold_frames(count: int) -> bool:
	for _i in count:
		if not is_inside_tree():
			return false
		await get_tree().process_frame
	return is_inside_tree()


## Instance one warm scene: neutralise it BEFORE it enters the tree (autoplay audio and physics bodies act on
## _ready / enter-world, so a post-add mute would be one frame late), add it, neutralise again for anything _ready
## built, arm its particles, and park it in the camera's grid.
func _warm_scene(inst: Node, camera: Camera3D, slot: int) -> void:
	# DISABLED kills everything the scene would otherwise DO through the process loop: autostart Timer NODES (the
	# decals' fade-out, the explosion's self-free), the explosion's body_entered / ScreenShakeArea, every _process
	# countdown, and — through CollisionObject3D's default DISABLE_MODE_REMOVE — every body / area never enters the
	# physics space at all. It does NOT gate SceneTreeTimers: blood_drop's 6 s despawn and the blood splat's
	# BloodLight self-free (0.15 s, `await create_timer`) still tick on the wall clock — both simply outlive the
	# frame-counted hold (5 frames) in any playable frame rate, so they never fire before the free below; a longer
	# hold would have to account for them. _ready still runs (it is not a process callback), which is exactly what
	# we want: that is where the runtime materials, outline duplicates and audio setup the first spawn would pay
	# are built.
	inst.process_mode = Node.PROCESS_MODE_DISABLED
	_configure_explosion(inst)
	_configure_decal(inst)
	_neutralise(inst)
	add_child(inst)
	_neutralise(inst)  # anything _ready built (a reparented SFX player, a spawned light) gets the same treatment
	_arm_particles(inst)
	_place(inst, camera, slot)
	_warm_nodes.append(inst)


## explosion_area.tscn is authored as a REAL blast (deals_damage true, force 20, a screen-shake opt-in, a bloom
## that starts at scale ZERO and grows in _process). Duck-typed on the Explosion exports (`get` null = not one) so
## this component names no Explosion / Character type: no damage, no shove, no shake, and speed_to_scale 0 so the
## flash pops at full size — a DISABLED node never runs the _process that would grow it from nothing.
static func _configure_explosion(inst: Node) -> void:
	if inst.get(&"deals_damage") == null:
		return
	inst.set(&"deals_damage", false)
	inst.set(&"max_explosion_force", 0.0)
	inst.set(&"allowed_shake_screen", false)
	inst.set(&"speed_to_scale", 0.0)


## blood_splat_decal.tscn spawns at 1 mm and eases up to `target_size` on a tween a DISABLED node never runs —
## start it at the final size so the decal projects onto something during the hold instead of staying a point.
static func _configure_decal(inst: Node) -> void:
	if not (inst is Decal):
		return
	var target: Variant = inst.get(&"target_size")
	if target is Vector3:
		(inst as Decal).size = target


## Freeze, un-collide and mute a whole subtree. Idempotent, so it runs both before and after add_child.
static func _neutralise(node: Node) -> void:
	if node is RigidBody3D:
		(node as RigidBody3D).freeze = true
	if node is CollisionObject3D:
		# Belt and braces over DISABLE_MODE_REMOVE: even if a scene opts into DISABLE_MODE_KEEP_ACTIVE, nothing
		# collides with a body on no layers that masks nothing.
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).autoplay = false
		(node as AudioStreamPlayer3D).volume_db = MUTE_DB
	elif node is AudioStreamPlayer:
		(node as AudioStreamPlayer).autoplay = false
		(node as AudioStreamPlayer).volume_db = MUTE_DB
	elif node is AudioStreamPlayer2D:
		(node as AudioStreamPlayer2D).autoplay = false
		(node as AudioStreamPlayer2D).volume_db = MUTE_DB
	for child in node.get_children():
		_neutralise(child)


## Make every GPUParticles3D in the subtree actually emit for the hold. ⭐PROCESS_MODE_DISABLED propagates
## NOTIFICATION_PAUSED down the subtree, and GPUParticles3D answers it by zeroing its SERVER speed scale — nothing
## would ever emit, and the draw pass would be issued over an empty buffer. Flipping just the emitter to ALWAYS
## re-enables the simulation; none of the authored emitters' scripts drive a timer or a despawn from _process, so
## the rest of the instance stays DISABLED. ⭐ALWAYS is right HERE (a warm frame is not gameplay) and WRONG on a
## gameplay emitter: blood.tscn / bloody_mess.tscn used to carry a ParticleTimeBind script that pinned them to
## ALWAYS permanently, so they alone kept flying through the pauses (dialogue, FreezeFrame.pause_briefly's hard
## pause-on-kill) that hold every other effect still. That script is deleted; do not set the flag outside this prewarm.
## one_shot off so a burst keeps emitting across every warm frame instead of finishing before it is drawn.
static func _arm_particles(node: Node) -> void:
	if node is GPUParticles3D:
		var p := node as GPUParticles3D
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.one_shot = false
		p.emitting = true
	for child in node.get_children():
		_arm_particles(child)


## Park a warm instance at its grid slot. Non-spatial roots (none today) are left where they are.
func _place(node: Node, camera: Camera3D, slot: int) -> void:
	var spatial := node as Node3D
	if spatial == null:
		return
	spatial.global_position = _slot_position(camera, slot)


## World position of grid slot `slot`: spawn_distance ahead of the camera, spread across GRID_COLUMNS columns
## (spawn_spread apart) with successive rows stepping DOWN from just above the eye line, so a dozen-plus instances
## all sit inside the frustum without stacking on one point. No camera -> the same grid off this node's transform.
func _slot_position(camera: Camera3D, slot: int) -> Vector3:
	var cam_basis := camera.global_transform.basis if camera != null else global_transform.basis
	var origin := camera.global_position if camera != null else global_position
	var col := slot % GRID_COLUMNS
	var row := int(float(slot) / float(GRID_COLUMNS))
	var x := (float(col) - float(GRID_COLUMNS - 1) * 0.5) * spawn_spread
	var y := (1.0 - float(row)) * spawn_spread
	return origin - cam_basis.z * spawn_distance + cam_basis.x * x + cam_basis.y * y


## The code-built effects — nothing on disk lists them, so they are built through the SAME statics gameplay uses
## (the warmed object can never drift from the spawned one) and parked in the grid after the scenes. Returns how
## many were built.
func _warm_code_built(camera: Camera3D, first_slot: int) -> int:
	var slot := first_slot
	# The damage number: one Label3D with every digit at the live font size / outline / billboard / no-depth flags —
	# its 2D-material variant and the glyph raster (the font cache is global; it survives the free).
	var fx: EffectsSettings = GameSettings.effects
	var label := DamageNumberPopup.build_label(WARM_DIGITS, false, fx)
	add_child(label)
	label.global_position = _slot_position(camera, slot)
	_warm_nodes.append(label)
	slot += 1
	# The "!" alert icon (and by the same material key the turn-hostile cue, the pet heart, the radio note).
	var icon := NpcBarkUi.build_icon(NPC.POPUP_EXCLAMATION, NpcBarkUi.POPUP_WORLD_HEIGHT)
	add_child(icon)
	icon.global_position = _slot_position(camera, slot)
	_warm_nodes.append(icon)
	slot += 1
	# The confetti trick-shot burst — exactly the PreloadManager idiom: the six tuning defaults are read off a
	# throwaway off-tree Throwable (no duplicated literals), the emitter built by the static _spawn_confetti uses.
	var throwable_script: GDScript = load(THROWABLE_SCRIPT_PATH)
	if throwable_script != null:
		var defaults: Object = throwable_script.new()  # off-tree: just the export defaults, _ready never runs
		var confetti: GPUParticles3D = throwable_script.build_confetti_burst(
				defaults.confetti_amount, defaults.confetti_lifetime,
				defaults.confetti_velocity_min, defaults.confetti_velocity_max,
				defaults.confetti_scale_min, defaults.confetti_scale_max)
		defaults.free()
		add_child(confetti)
		_arm_particles(confetti)
		confetti.global_position = _slot_position(camera, slot)
		_warm_nodes.append(confetti)
		slot += 1
	return slot - first_slot


## Draw the 2D hit feedback once at WARM_2D_ALPHA. The hurt flash + hitmarker live on the PlayerHud the Player
## builds as its own child; the on-camera splatter is the UI layer's `blood_splatter` export. Both are reached
## DUCK-TYPED (get / has_method) so this component names no Player-side type, and a level with no Player (a bare
## test tree) simply skips the pass. Each target's warm_draw restores itself after one drawn frame.
func _warm_2d() -> void:
	var player := Groups.human_player(get_tree())
	if player == null:
		return
	for child in player.get_children():
		if child.has_method(&"warm_draw"):
			child.call(&"warm_draw", WARM_2D_ALPHA)
	var ui: Variant = player.get(&"ui")
	if ui is Node:
		var splatter: Variant = (ui as Node).get(&"blood_splatter")
		if splatter is Node and (splatter as Node).has_method(&"warm_draw"):
			(splatter as Node).call(&"warm_draw", WARM_2D_ALPHA)


## Keep ONE hidden bullet_hole_decal.tscn alive under this node for its whole lifetime: a Decal's texture is
## registered in the global decal atlas for as long as the Decal exists (visible or not), so this pins
## `bullet hole.png` — shared by the bullet hole AND the blood splat — and the atlas repacks once here, on black,
## instead of on the first wall hit and again every time the last decal fades. DISABLED so its fade _process and
## TimeTilFadeout never run: the keeper must never free itself. Idempotent (a hand-placed / earlier keeper wins).
func _ensure_decal_keeper() -> void:
	if get_node_or_null(NodePath(DECAL_KEEPER_NODE)) != null:
		return
	var ps := load(DECAL_KEEPER_PATH) as PackedScene
	if ps == null or not ps.can_instantiate():
		push_warning("EffectPrewarmer: could not load '%s' for the decal-atlas keeper (skipped)" % DECAL_KEEPER_PATH)
		return
	var keeper := ps.instantiate()
	if keeper == null:
		return
	keeper.name = DECAL_KEEPER_NODE
	keeper.process_mode = Node.PROCESS_MODE_DISABLED
	if keeper is Node3D:
		(keeper as Node3D).visible = false
	add_child(keeper)


## Park every instance the pass drew: hidden, process-disabled, and KEPT for this node's lifetime (they are freed
## with game.tscn). Deliberately not queue_free'd — see frames_hidden: on a cold shader cache the background
## specialization compiles these materials queued can still be in flight after the hold, and freeing a material
## under an in-flight compile is a use-after-free the engine cannot defend against; a couple of dozen hidden nodes
## cost nothing, and their materials/shaders can never be evicted and recompiled mid-fight either. Hidden with
## `visible = false` per node (not only via this node's own flag) so a later `visible = true` on the component —
## e.g. the resting-state restore in warm() — never re-shows them. GPUParticles3D emitters are switched off too, so
## nothing keeps simulating behind the scenes.
func _park_warm_nodes() -> void:
	for n in _warm_nodes:
		if not is_instance_valid(n):
			continue
		if n is Node3D:
			(n as Node3D).visible = false
		_stop_particles(n)
	# _warm_nodes keeps the refs on purpose (a readable record of what was warmed; nothing iterates it later).


## Switch every GPUParticles3D in a parked subtree off (the pass armed them to emit for the hold).
static func _stop_particles(node: Node) -> void:
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = false
	for child in node.get_children():
		_stop_particles(child)
