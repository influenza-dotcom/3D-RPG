class_name UI
extends CanvasLayer

@export var player: Character
@export var ammo_count: Ammo
@export var hp: Label
@export var ammo: Label

func _process(_delta: float) -> void:
	if is_instance_valid(player):
		hp.text = "%d" % player.hp
	if is_instance_valid(ammo_count):
		ammo.text = "%d" % ammo_count.current_ammo
