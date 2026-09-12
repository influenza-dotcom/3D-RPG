# Godot Text to Speech

## Instructions

Once the plugin is installed the node types **TextToSpeech1D**, **TextToSpeech2D** & **TextToSpeech3D** should appear in the Godot engine. Add one of them to your scene and use the example below as a guideline.

```
extends Node2D

func _ready():
	await $TextToSpeech1.say("Text to speech is a really neat thing.")
	await $TextToSpeech2.say("We can also speak in different voices.", "cmu_us_slt")
	await $TextToSpeech1.say("And slower too.", "cmu_us_awb", 0.75)
	$TextToSpeech1.say("And we can both speak at the same time.", "cmu_us_fem")
	$TextToSpeech2.say("And we can both speak at the same time.", "cmu_us_eey")
```

## Keep in mind

- The current implementation is intended to have a small number of **TextToSpeech1D/2D/3D** nodes as the dynamic library and the voice file is loaded for each instance
- Voices for this text to speech plugin are located under **addons/text_to_speech/voices/**. The voices are plain `.flitevox` files (Flite voice databases). They are deliberately NOT named `.res`: Godot treats `.res` as its own binary-resource format and its editor scan / exporter open every `.res` to read dependencies, which fails on a Flite header with "Unrecognized binary resource file". An unknown extension is still packed into the .pck on export. Additional voices can be added to this directory and used with this plugin.
- It is a good practice to only keep the voices you use in the game, as all .flitevox files in the directory are shipped with the game and extracted to **user://** at runtime.

## Voices included

- cmu_us_aew
- cmu_us_ahw
- cmu_us_awb
- cmu_us_eey
- cmu_us_fem
- cmu_us_slp
- cmu_us_slt