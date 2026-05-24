extends MeshInstance3D

var base_position: Vector3
var base_rotation: Vector3

@export var sway_amount: float = 0.02
@export var sway_speed: float = 8.0
@export var player: Character

func _ready():
	base_position = position
	base_rotation = rotation_degrees

var tween 

func _process(delta: float) -> void:
	if !is_instance_valid(player) or !player:
		return
	var sway_x = -player.input_dir.x * sway_amount
	var sway_y = player.input_dir.y * sway_amount * 0.5
	var target = base_position + Vector3(sway_x, sway_y, 0)
	position = position.lerp(target, delta * sway_speed)

func fire():
	if tween:
		tween.kill()
	position = base_position
	rotation_degrees = base_rotation
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	
	tween.tween_property(self, "position", base_position + Vector3(0, 0.1, 0.4), 0.05)
	tween.tween_property(self, "rotation_degrees", base_rotation + Vector3(-5, 0, 0), 0.05)
	
	tween.chain().tween_property(self, "position", base_position, 0.1)
	tween.chain().tween_property(self, "rotation_degrees", base_rotation, 0.1)

func reload():
	if tween:
		tween.kill()
	position = base_position
	rotation_degrees = base_rotation
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	
	tween.tween_property(self, "position", base_position + Vector3(0, -.9, 0.4), .5)
	tween.tween_property(self, "rotation_degrees", base_rotation + Vector3(-25, 0, 0), .5)
	

func _on_ammo_finished_reloading() -> void:
	print("hello")
	if tween:
		tween.kill()
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	
	tween.tween_property(self, "position", base_position, 0.5)
	tween.tween_property(self, "rotation_degrees", base_rotation, 0.5)
