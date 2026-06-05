extends Node
## Night-sky painter (autoload, kept under the project's existing "StarSky" entry) — paints the level's
## sky as a dim, flat LIGHT-POLLUTION haze at runtime, NON-destructively (the saved scene is untouched).
## The level's WorldEnvironment renders its sky black (background_energy_multiplier 0); a populated place
## like this would have enough light pollution to wash the stars out, so instead of a starfield we lift the
## sky to a faint, slightly-warm glow. Re-applies whenever a WorldEnvironment (group "world_environment")
## enters the tree, so it covers every scene load (e.g. New Game) without any scene editing.

## The flat light-pollution sky colour — a dim, desaturated warm grey (a faint city glow, no stars).
const LIGHT_POLLUTION_COLOR := Color(0.08, 0.072, 0.06)

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	# Cover the case where the environment is already in the tree when this autoload initialises.
	for n in get_tree().get_nodes_in_group(&"world_environment"):
		_apply_to(n)

func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment or node.is_in_group(&"world_environment"):
		_apply_to(node)

func _apply_to(node: Node) -> void:
	var we := node as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment
	# Idempotent: skip if we've already painted our flat light-pollution background (avoids reasserting
	# on every node_added during a load).
	if env.background_mode == Environment.BG_COLOR and env.background_color.is_equal_approx(LIGHT_POLLUTION_COLOR):
		return
	env.sky = null  # drop any star / procedural sky material — there are no visible stars under light pollution
	env.background_mode = Environment.BG_COLOR
	env.background_color = LIGHT_POLLUTION_COLOR
	if env.background_energy_multiplier <= 0.0:
		env.background_energy_multiplier = 1.0  # the sky was drawn black — lift it so the faint glow shows
