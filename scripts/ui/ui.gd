extends CanvasLayer

@export var player: Character
@export var ammo_count: Node3D

@onready var hp: Label = $HP
@onready var ammo: Label = $AMMO

func _process(_delta: float) -> void:
	hp.text = "%d" % player.hp
	ammo.text = "%d" % ammo_count.current_ammo
