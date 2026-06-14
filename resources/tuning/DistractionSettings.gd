class_name DistractionSettings
extends Resource

## Global defaults for thrown-decoy NOISE (stealth distraction), read as GameSettings.distraction.<field>. A
## Throwable whose ThrowableData has `noise_on_land` ON drops a one-shot NoiseSource at its landing spot using
## these (each field overridable per ThrowableData via resolved_decoy). It's the "lob a rock to lure a guard"
## verb. The decoy is INERT unless an NPC has GameSettings.npc_ai.hearing_initiates on, so these only matter
## for stealth play.

@export_group("Thrown decoy")
## Default audible radius (m) of a thrown decoy's landing noise -- how far it pulls a hearing NPC to investigate.
@export var decoy_radius: float = 12.0
## Default radius lost per second after landing (0 = stays full-loud until lifetime expires).
@export var decoy_decay: float = 0.0
## Default seconds the decoy noise lasts before it fades out and frees itself. Keep > 0 so a decoy never leaks
## a permanent NoiseSource into the level.
@export var decoy_lifetime: float = 4.0
