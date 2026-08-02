class_name EnemyHealthBar
extends Control

## The top-centre "who am I shooting" meter: a slim, allegiance-tinted HP bar that pops the instant the
## player damages a Character and self-expires a beat after the last hit on that target. Built by PlayerHud
## onto the player's UI layer (player_hud.gd build()), driven by ONE push per hit — Character.take_damage
## notifies its ATTACKER duck-typed (on_damaged_target), the Player forwards it here. That single seam
## covers every ATTRIBUTED damage path in the game at once: hitscan pellets and melee (damage_trace.gd),
## fired rounds (projectile.gd), explosions (explosion_area.gd), thrown props and thrown weapons
## (Throwable.gd), the pinball ram (ram_reactor.gd), and a silent takedown. Ambient damage (hazard zones,
## status DoT, fall damage) carries a null attacker by design — nobody to attribute it to — so it never
## raises the bar, which is correct: this readout answers "what am I fighting", not "what is hurting".
##
## CONTRACTS
## - PINNED to the HUD layer, never on the diegetic HUD-weight carrier (ui.gd `_weighted`). That's ui.gd's
##   moved-vs-pinned rule (corner readouts carry mass; combat truth does not), and mechanically the carrier's
##   8 px sway spring PLUS its FOV "lens breath" scale would drift this bar down into the stealth badge that
##   sits ~5 px below it.
## - It NEVER retains a reference to the target. show_for() copies hp / max_hp / tint by VALUE and keeps only
##   the instance ID, purely as a same-target test. That is deliberate, not laziness: a lethal hit runs die()
##   INSIDE the very take_damage that pushed the final value, and this project POOLS NPCs (npc_pool.gd parks
##   the body out of tree and hands the SAME instance back for a different life, with no generation counter),
##   so a retained ref would be either freed or silently retargeted at full HP. Holding nothing means nothing
##   can dangle.
## - Hold + fade + the chip trail all age on the WALL CLOCK (Time.get_ticks_msec), and the node runs
##   PROCESS_MODE_ALWAYS. Both are load-bearing: the hit that raises this bar is also the hit that fires
##   hitstop (FreezeFrame scales Engine.time_scale), and a conversation pauses the whole tree — a plate aged
##   on `delta` would freeze mid-hold and never expire. Same reason AimIndicators ages its arcs on the clock.
##   Being ALWAYS-processed, this node does only VISUAL work while paused (alpha + a redraw) — no audio, no
##   spawns, no world mutation (the always-node side-effect rule).
##
## Geometry, timings and the neutral tint are HudSettings knobs ("Enemy health bar" group), read LIVE every
## frame so inspector tuning shows without a reload. The FILL colour is deliberately NOT a knob: it encodes
## the target's ALLEGIANCE, so it comes from CBPalette and swaps under Options -> Accessibility ->
## "Colorblind-Safe Cues" in lockstep with that NPC's outline rim, hover name and dialogue name. The whole
## widget is hidden by Options -> Accessibility -> "Enemy Health Bar" (Settings.enemy_health_bar_enabled),
## polled live like the detection meter and the loot beacons.
##
## No name line, by design. This project treats an un-introduced hostile as an ANONYMOUS threat — Talkable
## .look_name_for() returns "" for exactly that case — so a name here would leak identity the hover readout
## deliberately withholds. It also keeps the bar inside the only free band at the top of the canvas (see
## enemy_hp_top).

## Sentinel for "no target" (Object instance IDs are never 0).
const NO_TARGET: int = 0

var _target_id: int = NO_TARGET   ## instance ID of the last-damaged target — a SAME-TARGET TEST ONLY, never dereferenced
var _frac: float = 1.0            ## live HP fraction the fill draws
var _ghost: float = 1.0           ## the delayed "chip" fraction — where the bar WAS, easing down to _frac
var _fill_color: Color = Color.WHITE  ## the target's allegiance tint, resolved ONCE per target (see _color_for)
var _hit_msec: int = 0            ## wall clock of the last push — the hold/fade origin
var _tick_msec: int = 0           ## wall clock of the last _process — the chip trail's own frame delta
var _alpha: float = 0.0           ## 1 through the hold, ramping to 0 across the fade

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat input (HUD gotcha, same as every overlay here)
	# Age through a paused tree — see the wall-clock contract in the header. Visual-only work while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_tick_msec = Time.get_ticks_msec()

## Pure fill math: the 0..1 fraction `hp` of `max_hp` fills. Degrades on a zero/negative max_hp instead of
## dividing (the ui.gd stamina_bar_fill idiom), and clamps a NEGATIVE hp — Character.take_damage floors
## nothing, so an overkill hit really does leave hp below zero. Static so tests pin it off-tree.
static func fill_fraction(hp: float, max_hp: float) -> float:
	if max_hp <= 0.0001:
		return 0.0
	return clampf(hp / max_hp, 0.0, 1.0)

## Pure hold-then-fade opacity: fully lit for `hold` seconds after the last hit, then a linear ramp to 0
## across `fade`, then 0 forever. `elapsed_msec` is wall-clock milliseconds since that hit. Static so tests
## pin it off-tree.
static func plate_alpha(elapsed_msec: int, hold: float, fade: float) -> float:
	var t := float(maxi(elapsed_msec, 0)) / 1000.0
	if t <= hold:
		return 1.0
	if fade <= 0.0:
		return 0.0
	return clampf(1.0 - (t - hold) / fade, 0.0, 1.0)

## Pure chip-trail step: where the ghost sits after `dt` seconds, given the live fill `frac` and `since_hit`
## seconds on the clock since the last hit. The ghost holds still for `delay` (so the shard is READABLE as a
## discrete chunk of damage) and then slides down at `speed` fraction-per-second, never below the live fill.
## A ghost at or under the fill snaps to it — a HEAL (or a fresh target) must not leave an inverted trail.
## Static so tests pin it off-tree.
static func chip_step(ghost: float, frac: float, since_hit: float, delay: float, speed: float, dt: float) -> float:
	if ghost <= frac:
		return frac
	if since_hit < delay:
		return ghost
	return maxf(frac, ghost - maxf(speed, 0.0) * maxf(dt, 0.0))

## The TRACK rect (the bar itself, contrast rim EXCLUDED) on a `canvas_w`-wide canvas: centred horizontally,
## floored to whole pixels. The 792x444 UI canvas is nearest-upscaled ~2.4x, so a fractional edge rasterizes
## the track, the chip and the fill a pixel apart and the bar reads as a ragged triple edge — the same reason
## UI.hp_display_seg_width floors its segment width. Static so tests pin the layout off-tree.
static func bar_rect(canvas_w: float, top: float, bar_size: Vector2) -> Rect2:
	return Rect2(floorf((canvas_w - maxf(bar_size.x, 1.0)) * 0.5), floorf(top),
			maxf(bar_size.x, 1.0), maxf(bar_size.y, 1.0))

## The TRUE ink band this widget paints, CONTRAST RIM INCLUDED. The rim is drawn OUTSIDE the track (grown on
## all four sides), so the real footprint is always bigger than `enemy_hp_size` — every clearance claim and
## every layout test must measure THIS, not the size knob, or it silently under-counts by the rim width on
## each edge. Static so the invariant against the centre-top prompt ladder is pinned off-tree.
static func ink_rect(canvas_w: float, top: float, bar_size: Vector2, outline: float) -> Rect2:
	return bar_rect(canvas_w, top, bar_size).grow(maxf(floorf(outline), 0.0))

## Raise (or refresh) the plate for `target`, whose HP is now `hp` of `max_hp` and was `hp_before` an instant
## ago — Character.take_damage hands us `hp + amount`, i.e. the HP before this hit, with armour/DR already
## accounted for. Called once per landed hit via Player.on_damaged_target.
##
## `hp_before` is what lets EVERY hit show a chip shard, including the FIRST hit on a target — without it a
## fresh target seeds its ghost at the post-hit fraction and the shard is invisible, which bites hardest on an
## explosion: ExplosionArea calls take_damage once per body in the same frame, so the last victim (a new
## target) would be the one on screen and would show no shard at all. Pass anything <= hp (or omit it) and the
## trail simply starts flat.
##
## The allegiance tint re-resolves on EVERY push, not just a target switch: hostility is live state that can
## flip mid-plate. Shooting a companion accumulates aggression until ProvokeOnAttack fires stop_following() +
## provoke() — and that runs INSIDE the same take_damage, a dozen lines BEFORE this notify — so a cached tint
## would leave the bar reading blue/green while the NPC's outline rim, hover name and dialogue name all went
## red. It is one CBPalette lookup per landed hit; correctness beats the micro-optimisation.
##
## Refuses outright while the Options row is off (checked here as well as in _process, so a disabled bar never
## even flickers on the first hit of a fight).
func show_for(target: Node, hp: float, max_hp: float, hp_before: float = -1.0) -> void:
	if not Settings.enemy_health_bar_enabled:
		return
	var frac := fill_fraction(hp, max_hp)
	var id: int = target.get_instance_id() if target != null else NO_TARGET
	var now := Time.get_ticks_msec()
	# A fully-expired plate counts as a fresh engagement even against the same target — its trail already
	# caught up, so there is nothing to preserve.
	if id != _target_id or _alpha <= 0.001:
		_target_id = id
		_ghost = maxf(frac, fill_fraction(hp_before, max_hp))
	# A repeat hit on the SAME live target deliberately leaves the ghost where it is — that standing height is
	# exactly what makes the shard read as the damage this volley has done.
	_fill_color = _color_for(target)
	if not visible:
		_tick_msec = now  # don't hand the chip trail the whole hidden interval as one frame's delta
	_frac = frac
	_hit_msec = now
	_alpha = 1.0
	visible = true
	queue_redraw()

## Force the plate off AND reset its per-target state. Called by Player.die() BEFORE ui.hide_hud_for_death()
## records the visible set — otherwise a plate still up from the kill that traded with our own death is
## remembered and restored STALE onto the fresh life (the clear_stealth_readout / clear_interaction_cues
## contract). Resetting _target_id matters as much as `visible`: the next life's first hit must read as a NEW
## target so it starts a clean chip trail instead of inheriting the dead life's ghost height.
## Named clear_plate(), not clear(), so it can never collide with a future engine method on Control — a
## GDScript method that shadows a native one fails the whole script at PARSE time.
func clear_plate() -> void:
	_target_id = NO_TARGET
	_frac = 1.0
	_ghost = 1.0
	_alpha = 0.0
	visible = false

## The fill tint for `target`: its ALLEGIANCE through CBPalette (companion blue > friendly / hostile), so the
## bar recolours with Options -> Accessibility -> "Colorblind-Safe Cues" exactly like the NPC's outline rim,
## hover name and dialogue speaker name. Duck-typed on `resolved_disposition` rather than `is NPC` — the same
## "is this a person" test Throwable._loyal_damage_scale uses — so a plain Character (or any future
## damageable actor) falls back to the neutral knob instead of erroring.
## The is_instance_valid guard is DEFENCE IN DEPTH, not a live path: today's only caller notifies from inside
## take_damage BEFORE the death branch, so the victim is always alive here. It stays because `is` / property
## access on a freed instance CRASHES, and a future caller (a delayed or deferred notify) would hit exactly
## that — the house rule is is_instance_valid first, always.
static func _color_for(target: Node) -> Color:
	var neutral: Color = GameSettings.hud.enemy_hp_neutral_color
	if target == null or not is_instance_valid(target) or not target.has_method(&"resolved_disposition"):
		return neutral
	# `== true` rather than bool(...): these are Variant returns from a dynamic call, and GDScript 4 has no
	# bool(String) constructor — the house rule for duck-typed reads.
	var ally: bool = target.has_method(&"is_following") and target.call(&"is_following") == true
	return CBPalette.disposition_color(ally, int(target.call(&"resolved_disposition")), neutral)

func _process(_delta: float) -> void:
	if not visible:
		return
	# Live Options poll (the detection-meter / loot-beacon idiom): turning the row off clears the plate the
	# same frame instead of leaving the current one stranded until it expires.
	if not Settings.enemy_health_bar_enabled:
		clear_plate()
		return
	var hud: HudSettings = GameSettings.hud
	# WALL CLOCK, never `_delta` — see the header. The kill that raises this bar fires hitstop on the same
	# frame, and a conversation pauses the tree; a delta-aged plate would stall mid-hold and never fade out.
	var now := Time.get_ticks_msec()
	var dt := float(now - _tick_msec) / 1000.0
	_tick_msec = now
	var since := now - _hit_msec
	_alpha = plate_alpha(since, hud.enemy_hp_hold_time, hud.enemy_hp_fade_time)
	if _alpha <= 0.001:
		clear_plate()
		return
	_ghost = chip_step(_ghost, _frac, float(since) / 1000.0, hud.enemy_hp_chip_delay, hud.enemy_hp_chip_speed, dt)
	queue_redraw()

func _draw() -> void:
	if _alpha <= 0.001:
		return
	var hud: HudSettings = GameSettings.hud
	var track := bar_rect(size.x, hud.enemy_hp_top, hud.enemy_hp_size)
	# Contrast rim UNDER everything, so a dark track over a dark scene still has a readable outer edge — the
	# stamina ring's outline serves the same purpose at the reticle. It grows OUTWARD: ink_rect is the honest
	# footprint the layout knobs are checked against.
	if hud.enemy_hp_outline_width > 0.0:
		var oc := hud.enemy_hp_outline_color
		oc.a *= _alpha
		draw_rect(ink_rect(size.x, hud.enemy_hp_top, hud.enemy_hp_size, hud.enemy_hp_outline_width), oc)
	var bg := hud.meter_bg_color  # shared with the four centre-screen prompt meters — one HUD meter dialect
	bg.a *= _alpha
	draw_rect(track, bg)
	# The chip shard: where the bar stood a beat ago, drawn UNDER the live fill so a burst of damage reads as
	# a bright sliver that then catches up. chip_step guarantees it is never narrower than the fill.
	if _ghost > _frac + 0.0005:
		var cc := hud.enemy_hp_chip_color
		cc.a *= _alpha
		draw_rect(Rect2(track.position, Vector2(floorf(track.size.x * _ghost), track.size.y)), cc)
	if _frac > 0.0005:
		var fc := _fill_color
		fc.a *= _alpha
		draw_rect(Rect2(track.position, Vector2(floorf(track.size.x * _frac), track.size.y)), fc)
