extends Node
## StarSky (autoload) — gives the level's sky stars at runtime, NON-destructively (the saved scene is
## untouched). The level's WorldEnvironment renders its sky black (background_energy_multiplier 0), so
## this swaps in a procedural starry-night sky shader and lifts the background energy so the stars show.
## Listens for a WorldEnvironment to enter the tree (it's in group "world_environment"), so it re-applies
## on every scene load (e.g. New Game) without any scene editing.

const STAR_SHADER := preload("res://resources/shaders/starry_sky.gdshader")

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
	if env.sky == null:
		env.sky = Sky.new()
	# Skip if we've already applied our shader (avoids reasserting every node_added during a load).
	var existing := env.sky.sky_material as ShaderMaterial
	if existing != null and existing.shader == STAR_SHADER:
		return
	var mat := ShaderMaterial.new()
	mat.shader = STAR_SHADER
	env.sky.sky_material = mat
	if env.background_mode != Environment.BG_SKY:
		env.background_mode = Environment.BG_SKY
	if env.background_energy_multiplier <= 0.0:
		env.background_energy_multiplier = 1.0  # the sky was drawn black — lift it so the stars are visible
