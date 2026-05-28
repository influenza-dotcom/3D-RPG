class_name UI
extends CanvasLayer

## HUD layer. Polls the player's HP and the Ammo clip each frame to refresh the
## labels, and owns the BloodSplatter overlay that Player.on_nearby_death drives.
## The is_instance_valid guards below matter: player/ammo can be freed during a
## death/scene reload while this layer briefly persists.

@export var player: Character
@export var ammo_count: Ammo
@export var hp: Label
@export var ammo: Label
@export var blood_splatter: BloodSplatter

func _process(_delta: float) -> void:
	if is_instance_valid(player):
		hp.text = "%d" % player.hp
	
	if is_instance_valid(ammo_count):
		ammo.text = "%d" % ammo_count.current_ammo
