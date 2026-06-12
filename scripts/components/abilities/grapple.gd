class_name Grapple
extends Ability

## GRAPPLE ability — drop under a Player to grant the Cruelty-Squad grappling hook (an UpgradePickup grants it
## at runtime by adding this node; it's deliberately NOT a starting ability — you must FIND it).
##
## OWNS the GrappleHook (scripts/player/grapple_hook.gd — the fired hook head, rope + tip visuals, tether-swing
## and yank physics): when registered on an in-tree player this builds the hook as its child, wired to the host's
## camera (aim) + grapple_hook_origin (rope origin). The Player calls apply_pull() at its physics beat (after the
## velocity build, before the move). No Grapple node = no hook in the tree at all; a DISABLED node keeps an inert
## hook — it refuses to FIRE (GrappleHook._try_fire's has_mechanic gate reads `enabled` through
## Player.has_mechanic), while a rope already out keeps its physics until released, like the old always-built hook.

## Optional one-stop config (.tres) for the rope / hook tip / SFX / feel. Null = the host Player's
## grapple_resource (the scene-wired slot), so a runtime-granted Grapple still picks up the authored config.
@export var config: GrappleHookResource = null

var _hook: GrappleHook = null

func ability_id() -> StringName:
	return &"grapple"

func setup(player: Node) -> void:
	super.setup(player)
	# Build the hook only in-tree (mirrors Slide's sfx build): a bare off-tree grant in a unit test gets the
	# GATE (has_mechanic true) without the rope/visual build, which needs the live camera/muzzle rig.
	if is_inside_tree() and _hook == null:
		_build_hook()

func _ready() -> void:
	# Late build: granted OFF-tree (setup ran with no tree -> no hook) and then entered the tree — build now so
	# the grapple isn't silently dead. Editor-placed nodes hit this with host still null (discovery runs later,
	# in Player._ready) and skip; their build happens in setup().
	if host != null and _hook == null:
		_build_hook()

func _build_hook() -> void:
	_hook = GrappleHook.new()
	# Hand over the config BEFORE add_child so the hook's _ready() builds the rope + tip sprite from it.
	var cfg: GrappleHookResource = config
	if cfg == null:
		cfg = host.grapple_resource
	_hook.config = cfg
	add_child(_hook)
	_hook.setup(host as Character, host.camera_effects, host.grapple_hook_origin)

## The physics-beat hook: forward the tether/yank pull. Deliberately NOT gated on `enabled` — disabling only
## stops NEW fires (the has_mechanic gate in _try_fire); a rope already out keeps pulling until released,
## matching the old always-built hook's semantics.
func apply_pull(delta: float) -> void:
	if _hook != null:
		_hook.apply_pull(delta)

## True while the rope is attached (a swing or yank in progress).
func is_attached() -> bool:
	return _hook != null and _hook.is_attached()

## Let go of anything the hook holds, with no slingshot (a SNAP, not a deliberate release) — death hygiene:
## the dying hand drops the rope, which retracts through the cinematic instead of spanning the respawn
## teleport. Safe when idle / no hook.
func detach() -> void:
	if _hook != null:
		_hook.detach(false)
