extends AudioStreamPlayer3D

## Enemy hurt SFX. Connected to the enemy's `damaged` signal (in the enemy scene);
## plays a positional pain/impact sound on every damage tick.
##
## ⭐⭐IT PLAYS ON EVERY DAMAGE TICK, which makes it the single worst machine-gun case in the mix: a shotgun
## blast is one tick per pellet and a full-auto burst is one per round, so a bare play() retriggers the SAME
## byte-identical yell many times a second and the NPC reads as a stuck sample rather than a person being hurt.
## Hence AudioManager.play_varied — a fresh small pitch per tick. A cry of pain is an EXERTION, not a voice
## IDENTITY (the thing that must never be re-pitched is e.g. Throwable.sound_pitch_mult, an animal's rolled body
## size); see AudioManager.vary_pitch for that boundary.

func _on_enemy_damaged(_current_hp: float, _max_hp: float) -> void:
	AudioManager.play_varied(self)
