extends RefCounted

## THE SPEND CHIP behind the stamina readout: the pool you JUST spent stays painted in WHITE where it was,
## sits there for a beat, then slides down to meet the live fill. Without it a spend is invisible in motion
## — the gauge simply *is* shorter next frame, so a dash and one sprint tick read identically and the price
## of a verb is something you infer from the number rather than something you SAW happen. The white shard
## is the receipt: its LENGTH is what that verb just cost, and its slide is the "you're not getting this
## back yet" beat (player_movement.stamina_regen_delay_after_spend genuinely freezes the pool while it sits).
##
## ⭐ SAME IDIOM, SAME LAW as the enemy health bar's damage chip (scripts/ui/enemy_health_bar.gd): this
## delegates to EnemyHealthBar.chip_step, the pure hold-then-slide step already shipped and unit-tested
## there, rather than growing a second easing rule that would drift from it. The game says "a white shard
## marks what a moment ago took away" in ONE voice — on the thing you shoot and on your own stamina — and
## the knobs sit side by side in HudSettings (enemy_hp_chip_* / stamina_chip_*) so they read as a pair.
## What this class adds on top is the part chip_step leaves to its caller: the "when was the last drop"
## clock, which the enemy bar gets for free from its own per-hit push and stamina has to detect itself.
##
## ONE tracker drives BOTH stamina readouts (ui.gd owns it; the ring paints the shard as a white arc past
## the fill's tip, the corner bar as a white rect past the fill's right edge), so the two stamina dialects
## can't drift apart — the same rule that already makes StaminaRing.ring_color the one colour blend for both.
##
## WHY RefCounted with no class_name: pure state + arithmetic, no tree presence and no process of its own
## (ui.gd advances it from ITS _process, so it freezes exactly when the HUD does), and a brand-new
## class_name risks the stale-class-cache cascade — ui.gd preloads it BY PATH, the same guard
## STAMINA_RING_SCRIPT / the StatBudgetRef idiom use.
##
## TUNING: zero knobs here. stamina_chip_color / stamina_chip_delay / stamina_chip_speed live on
## GameSettings.hud and are read LIVE per step, so inspector tuning shows without a scene reload.

## The shard's HEAD, as a 0..1 fraction of the full pool — always >= the live fill, so the white band is
## exactly [fill, value]. Starts full (a fresh HUD on a full pool paints nothing, since value == fill).
var value: float = 1.0
## Seconds since the pool last DROPPED — chip_step's `since_hit`. Reset to zero by every drop (never
## accumulated), so holding a drain down — a sprint, a wall climb — keeps the shard parked at the level you
## started from and it GROWS across the whole drain: one white block for one continuous expenditure, rather
## than a dozen slivers each sliding on their own clock.
var _since_drop: float = 999.0
## Last fill seen, so a drop can be detected at all. A drop is the only thing that restarts the clock; a
## rise (regen) just gets eaten out of the shard's left edge as the fill climbs back into it.
var _prev_fill: float = 1.0
## Has this tracker seen a live frame yet? The initialisers above say "full", which is a DON'T-CARE, not a
## level anyone had — exactly the ring's _fade_primed argument. Without this latch, the first frame of a
## HUD built over a pool that isn't full (a LOAD restoring a half-spent save, a level load mid-run) reads
## as a drop from 1.0 and paints a phantom shard for a spend that never happened. The first advance adopts.
var _primed: bool = false

const EPS := 0.0001

## Adopt `fill` outright — no shard, no hold. The "never animate a change nobody watched" rule the ring's
## _fade_primed latch already enforces: ui.gd calls this on every frame the readout is HIDDEN (dialogue, the
## death cinematic), so a pool that drained off-screen doesn't come back owing a white shard for a spend the
## player never saw.
func sync(fill: float) -> void:
	value = clampf(fill, 0.0, 1.0)
	_prev_fill = value
	_since_drop = 999.0
	_primed = true

## Advance one frame and return the shard's head. The drop clock is stamped FIRST so this frame's spend is
## already covered by the hold, then the shared chip law does the rest: hold still for stamina_chip_delay,
## then slide at stamina_chip_speed fraction-per-second, never below the live fill.
func advance(fill: float, delta: float) -> float:
	var f := clampf(fill, 0.0, 1.0)
	if not _primed:
		sync(f)  # first live frame: ADOPT the pool, never read the initialiser as a spend
		return value
	var dt := maxf(delta, 0.0)
	if f < _prev_fill - EPS:
		_since_drop = 0.0
	else:
		_since_drop += dt
	_prev_fill = f
	var hud: HudSettings = GameSettings.hud
	value = EnemyHealthBar.chip_step(value, f, _since_drop, hud.stamina_chip_delay, hud.stamina_chip_speed, dt)
	return value

## Is there a shard to paint at all? Both readouts skip their white pass on false, so a rested pool costs
## nothing to draw (and the ring keeps its no-track contract: nothing owing = nothing painted).
func has_chip(fill: float) -> bool:
	return value > clampf(fill, 0.0, 1.0) + EPS
