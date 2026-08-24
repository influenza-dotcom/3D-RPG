class_name AudioSettings
extends Resource

## Audio tuning, grouped below: the global per-play pitch variation for WORLD sound, landing thump,
## falling/fast-move wind swell, bullet/muzzle whiz pitch, impact pitch (incl. enemy-hit-by-HP), and the
## ammo-driven fire pitch. Consumed by AudioManager, player.gd, attack.gd, projectile.gd, and muzzle_whiz.gd.

@export_group("Pitch Variation")
## ⭐THE ONE "no world sound plays at the same pitch twice" knob. Every sound the GAME WORLD makes — footsteps,
## gunfire, reloads, bullet and melee impacts, explosions, gore, screams and death cries, doors, switches — has its
## pitch MULTIPLIED by a fresh random factor in [1 - spread, 1 + spread] on each play, so a retriggered clip
## never lands on the byte-identical sample twice. That machine-exactness is the single most fatiguing thing a
## mix can do — it is why the player's footsteps, NPC locomotion, bullet impacts and the muzzle whiz each
## already hand-rolled their own spread; this generalises the trick to the rest of the world instead of adding
## a 20th copy of it.
##
## ⭐⭐IT IS FOR DIEGETIC SOUND ONLY. Deliberately excluded, at any value of this knob: menu and UI chrome (a
## click must sound like the SAME button every press); non-diegetic stings and HUD cues (the MGS "!" alert, the
## aim sting, the incoming-shot beep, the hitmarker ding); reward jingles (cha-ching, the pickup chime, the
## applause); and all music/ambience/loops. The reasons differ, which is why the test is "is the world MAKING
## this?" and not "is it repeated?": on UI a random wobble reads as a BUG rather than as life; on a melodic
## jingle it just sounds out of tune; on a loop (which restarts itself on `finished`) it would re-tune the bed
## every lap. The exclusion is enforced at the call sites — `AudioManager.play_sfx` / `play_2d_sfx` take a
## `vary` flag those callers pass `false` to, and MenuStyle's own pooled voices never route through
## AudioManager at all.
##
## ⭐VOICES ARE IN, INCLUDING ONES WITH AN AUTHORED PITCH, because this MULTIPLIES around whatever base the
## site asks for. A creature's `Throwable.sound_pitch_mult` (its rolled BODY SIZE) stays the CENTRE of the
## roll, so a big dog still yaps low — it just never fires the identical sample twice. Hurt cries, death
## screams and falling yells vary for the same reason, and matter most: the NPC hurt cry fires on EVERY damage
## tick (one per shotgun pellet), so unvaried it reads as a stuck sample.
##
## ⭐NOTE the ENEMY-HIT impact is the site where this is most load-bearing, and the least obvious. Its base
## pitch is the HP lerp (`enemy_hit_pitch_low_hp`..`enemy_hit_pitch_full_hp`), which is DETERMINISTIC for a
## given remaining HP — so shooting a high-HP target with a weak weapon barely moves it and every hit landed
## on the byte-identical pitch. This variation is the only thing separating those hits.
##
## It MULTIPLIES rather than replaces, which is what makes it safe across every world site: a sound whose pitch
## MEANS something keeps that meaning — the ammo-driven fire sag (`fire_pitch_*`), the HP-driven enemy-hit
## deepening (`enemy_hit_pitch_*`), and the wider per-site spreads above all still read exactly as authored,
## just no longer machine-exact.
##
## ⭐SIZE IT AGAINST THIS PROJECT'S OWN SPREADS, not against intuition. The default 0.15 is deliberately the
## same number as `PhysicsDamageSettings.interactable_impact_pitch_spread`, i.e. exactly what this codebase
## already uses for a physical impact, and it sits mid-range among the hand-rolled spreads that predate it:
##     footsteps 0.08  |  paint splat ±0.10  |  throwable impact 0.15  |  generic impact / muzzle whiz ±0.17
##     NPC aim + beep ±0.22  |  landing 0.25  |  blood drop ±0.35
## An earlier cut of this shipped at 0.04 and was INAUDIBLE — six consecutive hits spanned about 1.2 semitones
## in total, most neighbouring pairs far less, which on a short percussive clip is below the threshold you can
## actually hear. At 0.15 the same six span ~2.9 semitones. If you want a number, measure it: the log2 ratio of
## the extremes times 12 is the semitone spread.
## 0.0 = off (every world sound at exactly the pitch its caller asked for).
@export_range(0.0, 0.5, 0.005) var global_pitch_spread: float = 0.15

@export_group("Landing")
## Impact strength (0..1, fall speed / landing_impact_divisor) below which the landing thump stays silent — a soft step-down plays nothing.
@export var land_sfx_min_impact_to_play: float = 0.08
## How many dB a SOFT landing is cut by (full subtraction at impact 0, none at impact 1) — bigger = gentler landings get quieter.
@export var land_sfx_volume_db_reduction: float = 18.0
## Random pitch wobble (±) on the landing thump so repeated landings don't sound identical — 0 = every landing same pitch.
@export var land_sfx_pitch_spread: float = 0.25

@export_group("Footsteps")
## Random pitch wobble (±) on every PLAYER footstep, so a stride isn't one clip retriggered at you two or three
## times a second. The same trick `land_sfx_pitch_spread` plays for landings and `LocomotionFx` plays for every
## NPC in the game — the player was the only actor without it. 0 = identical pitch every step.
@export var footstep_pitch_spread: float = 0.08
## dB offset on every player footstep, on top of whatever `WalkingSFX` authors. 0 = the shipped loudness;
## negative = quieter steps.
## ⭐THIS IS THE KNOB THAT ACTUALLY WORKS. An AudioStreamPlayer3D outputs `min(volume_db + distance attenuation,
## max_db)`, and at the ~80 dB base this project authors on `WalkingSFX` the sum is pinned to the CEILING at any
## range — so turning `WalkingSFX.volume_db` down in the Inspector changes nothing you can hear. This offset is
## applied to the ceiling as well as the volume (`Landing.step_db`), which is why it bites.
@export var footstep_volume_db: float = 0.0

@export_group("Falling Air")
## Vertical fall speed (m/s) where the wind swell STARTS — below this the wind is silent (a normal jump barely clears it).
@export var falling_air_min_fall_speed: float = 4.0
## Vertical fall speed (m/s) where the wind reaches FULL volume — terminal-velocity roar.
@export var falling_air_max_fall_speed: float = 18.0
## Horizontal speed (m/s) where the SAME wind swell starts, so blitzing flat-out (bhop/dash/blast) rushes like a fall. Keep above base run speed (5.0) so ordinary walking stays silent. Sliding is excluded (it drives its own loop).
@export var falling_air_min_move_speed: float = 6.5
## Horizontal speed (m/s) where the speed-driven wind reaches full volume.
@export var falling_air_max_move_speed: float = 14.0
## Wind volume (dB) at the quiet end of the swell — where the rush is just becoming audible.
@export var falling_air_min_db: float = -40.0
## Wind volume (dB) at full fall/move speed — the loudest the swell gets. Keep above min_db so it swells UP with speed.
@export var falling_air_max_db: float = -6.0
## How fast the wind volume eases toward its target each frame (higher = snappier swell, lower = laggier).
@export var falling_air_fade_rate: float = 8.0
## Swell intensity (0..1) above which the wind loop is allowed to start playing — a tiny floor so it doesn't toggle on at a standstill.
@export var falling_air_audible_t: float = 0.01

@export_group("Bullet/Muzzle")
## Falloff distance (m) of the positional bullet-whiz crack — past this the whiz is inaudible. Bigger = bullets are
## heard from further. Stamped onto every projectile scene's WhizSFX in Projectile._ready (volume is NOT global —
## it stays authored per-scene: the pistol round's loud crack vs the lobbed variants' quiet whoosh).
@export var bullet_whiz_max_distance: float = 6.0
## Low end of the random pitch range for the muzzle whiz so repeated shots vary — must stay below pitch_max.
@export var muzzle_whiz_pitch_min: float = 0.85
## High end of the muzzle-whiz random pitch range.
@export var muzzle_whiz_pitch_max: float = 1.2

@export_group("Impact")
## Low end of the random pitch range for generic bullet-impact sounds (each hit picks between min..max) — must stay below pitch_max.
@export var impact_pitch_min: float = 0.85
## High end of the impact-sound random pitch range.
@export var impact_pitch_max: float = 1.2
## Pitch of an enemy-hit sound at FULL HP — the bright high end. Hit pitch scales with the target's remaining HP fraction so you hear how hurt they are.
@export var enemy_hit_pitch_full_hp: float = 1.15
## Pitch of an enemy-hit sound at NEAR-DEATH HP — the deep/low end. Set below full_hp so wounded enemies sound progressively lower.
@export var enemy_hit_pitch_low_hp: float = 0.6
## Volume (dB) an NPC-fired impact one-shot plays at, so 3D distance attenuation applies (the .tscn authors the impact nodes very loud — volume_db 80 — for always-audible PLAYER feedback, which from a distant NPC reads as a flat 2D blast). The player's own shots keep the authored volume.
@export var npc_impact_volume_db: float = 0.0

@export_group("Fire Pitch")
## Fire-sound pitch with a FULL magazine — the gun's normal voice. The shot deepens as the mag empties (Cruelty Squad style).
@export var fire_pitch_full_ammo: float = 1.0
## Fire-sound pitch on the LAST round before empty — the deep/strained end. Set below full_ammo so the gun sags as it runs dry.
@export var fire_pitch_empty_ammo: float = 0.7
