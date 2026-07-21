@tool
class_name MyLight
extends Node3D

@onready var light_source: OmniLight3D = $LightSource
@onready var spotlight: SpotLight3D = $Spotlight
@onready var light_buzz: AudioStreamPlayer3D = $LightSource/LightBuzz

@export var _color: Color 
@export var _range_omni: float
@export var _range_spotlight: float
@export var _energy: float 

@export var _electric_buzz: bool

func _process(_delta: float) -> void:
	light_source.light_color = _color
	spotlight.light_color = _color
	
	light_source.omni_range = _range_omni
	spotlight.spot_range = _range_spotlight
	
	light_source.light_energy = _energy
	spotlight.light_energy = _energy
	
	if !light_buzz.playing:
		light_buzz.playing = _electric_buzz
