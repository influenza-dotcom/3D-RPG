class_name BunnyhopAbility
extends Ability

## BUNNYHOP ability — install the Bunny-Hop Chip (resources/items/chip_bunnyhop.tres) at a ChipInstaller to
## grant the chained-jump speed boost. A fresh game ships with ZERO abilities (Player.starting_unlocks is
## empty), so the movement tech is EARNED like every other upgrade (grapple / air-dash / slide / wall-climb /
## …). WITHOUT it a jump is just a jump: ground speed stays at PlayerMovementSettings.max_speed (5 m/s) and
## the 12 m/s BunnyhopSettings.max_speed ceiling is unreachable. This is deliberate — the whole movement kit
## is now something you buy into, rather than free tech the player happens to have on the first frame.
##
## Like AirDash and SilentTakedownAbility, this node is a pure GATE: the chain's BEHAVIOUR lives in the
## always-present Bunnyhop state machine (scripts/player/bunnyhop.gd), a Player child that keeps tracking the
## post-landing land_window every frame but is only ever ENGAGED through Player.bhop_chain_allowed(), which
## asks has_mechanic(&"bunnyhop"). Because the chain logic already lives in its own drop-in component (not a
## branch in a big script), there is nothing to re-house here — exactly as air_dash's launch code stays in
## attack.gd and the takedown verb stays in scripts/player/silent_takedown.gd.
##
## NAMING — three names, deliberately all different, because the state machine already owns the obvious one:
##   • class BunnyhopAbility, NOT Bunnyhop — that class_name is the state machine's (scripts/player/bunnyhop.gd),
##     and BunnyhopSettings is the tuning resource's. The AbilityRegistry keys off the FILENAME
##     (bunnyhop.gd -> id bunnyhop), never the class, so the Ability suffix is free. Same split, same reason, as
##     silent_takedown.gd vs scripts/player/silent_takedown.gd.
##   • scene FILE Bunnyhop.tscn — load-bearing: ids() snake-cases it to `bunnyhop` and scene_path_for() pascal-
##     cases back to "Bunnyhop", so renaming the file changes the mechanic id and orphans every save that has it.
##   • scene ROOT NODE "BunnyhopImplant", the ONE place this breaks the every-other-ability habit of naming the
##     root after the file. The Player ALREADY has a child named "Bunnyhop" (the state machine, Player.tscn's
##     `bunnyhop = NodePath("Bunnyhop")`), so a root named "Bunnyhop" would land a designer with two identically
##     named siblings and an auto-renamed "Bunnyhop2". Nothing reads the root's NAME — ids() reads the filename,
##     display_name_for() reads the `display_name` property off node 0 — so this costs nothing.

func ability_id() -> StringName:
	return &"bunnyhop"


## Implants-tab switch-off hygiene: drop any banked chain immediately. Player.bhop_chain_allowed() already
## routes every SUBSEQUENT jump to break_chain(), so a stale boost can never be re-applied — but a chain left
## sitting at 5 while the implant reads "off" is a lie in the debug/ability readouts, and the contract for this
## hook (Slide.end(), Grapple.detach()) is that switching an implant off ends its live state NOW.
##
## ⭐Read through `host.get()`, never `host.bunnyhop`. `host` is typed Node (the base class keeps it dynamic to
## dodge the Player <-> Ability class cycle) and AbilityManager.set_active calls this hook unconditionally, so a
## direct property read would raise "Invalid access to property or key" on any host without that @export — and
## GUT fails a test on any engine error. get() returns null for a missing property instead.
func on_deactivated() -> void:
	if host == null:
		return
	var bh: Variant = host.get(&"bunnyhop")
	if bh != null and is_instance_valid(bh):
		bh.break_chain()
