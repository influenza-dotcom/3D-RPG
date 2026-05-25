extends CanvasLayer

@export var player: Character
@export var ammo_count: Ammo
@export var hp: Label
@export var ammo: Label

func _process(_delta: float) -> void:
	hp.text = "%d" % player.hp
	ammo.text = "%d" % ammo_count.current_ammo
