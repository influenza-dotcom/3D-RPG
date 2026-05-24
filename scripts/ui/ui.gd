extends CanvasLayer

@export var player: Character
@export var weapon_system: WeaponSystem
@export var hp: Label
@export var ammo: Label

func _process(_delta: float) -> void:
	if !weapon_system:
		return
	#hp.text = "%d" % player.hp
	#weapon_system.ammo.text = "%d" % weapon_system.ammo
