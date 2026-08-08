class_name PlayerFeedbackSettings
extends Resource


## The player's HIT/DEATH/SPAWN feel — every feedback number on one inspector page
## (resources/tuning/PlayerFeedbackSettings.tres), read as GameSettings.player_feedback.<field>.
## These were consts scattered across player.gd / player_hud.gd / character.gd; now a designer
## tunes the whole "getting rocked -> keeling over -> fading back in" arc without touching code.

@export_group("Hurt (getting rocked)")
## time_scale at the hit's slow-mo dip (lower = more brutal).
@export var hurt_freeze_scale: float = 0.15
## Real-time hold at the dip before easing back.
@export var hurt_freeze_hold: float = 0.12
## Real-time ease back to normal (slow-mo + muffle + screen drain recover in lockstep).
@export var hurt_recovery: float = 0.55
## Master-bus low-pass cutoff (Hz) at full hurt — lower = more muffled.
@export var hurt_lpf_cutoff: float = 350.0
## Cutoff when clear (effectively no filtering).
@export var hurt_lpf_clear: float = 20500.0
## Screen-shake punch the instant you're hit.
@export var hurt_shake: float = 0.4

@export_group("Hurt flash (HUD)")
## Peak opacity (0..1) of the full-screen red flash the instant the player takes damage — bigger = a more blinding hit.
@export var hurt_flash_peak_alpha: float = 0.4
## Seconds the damage red-flash takes to fade out.
@export var hurt_flash_time: float = 0.32
## The full-screen damage flash tint.
@export var hurt_flash_color: Color = Color(0.85, 0.0, 0.0)

@export_group("Damage thud")
## Min gap (ms) between damage thuds so a pellet burst plays ONE low body-blow, not a drumroll.
@export var damage_thud_cooldown_ms: int = 250
## How loud the thud sits under the hit.
@export var damage_thud_volume_db: float = -4.0

@export_group("Death & spawn")
## What death MEANS — branched in Player._on_death_sequence_done (ML-2):
##  CHECKPOINT_RESPAWN: come back in place at the last checkpoint, the world UNTOUCHED (Dark Souls — the default).
##  RELOAD_LAST_SAVE: reload from the last autosave on disk (reverts unsaved progress; the world resets).
##  RELOAD_CHECKPOINT_FRESH: reload the current scene fresh (the world resets) but keep your in-memory profile.
enum DeathMode { CHECKPOINT_RESPAWN, RELOAD_LAST_SAVE, RELOAD_CHECKPOINT_FRESH }
@export var death_mode: DeathMode = DeathMode.CHECKPOINT_RESPAWN
## The death-card line for an UNATTRIBUTED death (a fall, a stray blast, drowning — no killer to credit).
## Designer-editable + themeable; set it to "" to show no card at all for these.
@export var death_message: String = PlayerText.DEATH_MESSAGE
## The death-card line when fall damage is the killing blow. `[mph]` is replaced with the impact speed
## (a legacy `%d`/`%s`/`%f` is also accepted, but ALL render the same whole number — `%f` does NOT
## float-format; substitution is token-replace, so a literal '%' never errors).
@export var death_message_fall: String = "You hit the ground at [mph] miles per hour."
## The death-card line when the KILLER is known but not their weapon — `%s` is filled with the killer's name.
@export var death_message_killed_by: String = PlayerText.DEATH_MESSAGE_KILLED_BY
## The death-card line when BOTH the killer AND their weapon are known — first `%s` = the killer's name,
## second `%s` = the weapon's name (its inventory display label). Keep both `%s` in whatever you rewrite this to.
@export var death_message_killed_by_weapon: String = PlayerText.DEATH_MESSAGE_KILLED_BY_WEAPON
## Name shown in the "killed by" line when the killer NPC has no authored display_name (a blank name would
## read "You were killed by ."). Keeps the line grammatical.
@export var death_unknown_killer: String = "someone"
## Name shown in the "killed by" line when the killer is a real character the player was never introduced to
## (the "Stranger until introduced" mask). The proper-noun placeholder reads wrong mid-sentence ("You were
## killed by Stranger."), so the card swaps in this indefinite form: "You were killed by a stranger."
## Lowercase on purpose — it sits inside a sentence, unlike the label-context "Stranger" placeholder.
@export var death_stranger_killer: String = "a stranger"
## The death card's text colour.
@export var death_message_color: Color = Color(0.85, 0.1, 0.1)
## The death card's font size (the small 396x216 viewport — keep it modest).
@export var death_message_size: int = 28
## Beat (seconds) of PURE BLACK between the vignette fully covering the screen and the death card starting
## to fade in. Without it the card arrives on the very frame the fade completes — which still READS as
## mid-fade, so the text lands on top of the closing vignette (information overload at the death moment).
## The beat lets the black settle first, then the card arrives as its own beat. 0 = the old
## card-on-the-black-frame timing. Folded into DeathMix.card_hold_seconds' sting-sync arithmetic, so the
## respawn still lands exactly on death_sting_sync_point.
@export var death_card_delay: float = 1.0
## Seconds the death card takes to fade IN (once the screen is black) and, later, to fade OUT (before the
## respawn). One knob for both ends of the card's fade.
@export var death_card_fade_time: float = 0.6
## Beat (seconds) held on a fully-black, text-gone screen AFTER the card fades out, before the world fades back up.
@export var death_card_gap: float = 0.35
## Wall-clock seconds of the death cinematic phase 1: the vignette closes to black + audio fades out + keel-over.
@export var death_sequence_time: float = 1.6
## Slow-mo target the world eases down to as you die.
@export var death_time_scale: float = 0.3
## Radians the camera rolls onto its side (~83 degrees at 1.45) — the keel-over.
@export var death_camera_roll: float = 1.45
## Seconds the death card stays FULLY visible (held on the black screen) after it fades in, before it fades out.
@export var respawn_delay: float = 1.0
## Fade-up-from-black duration on a fresh spawn / respawn -- a longer, cinematic emerge (the game-start intro
## the in-sky game title is timed to). Dial this for a snappier / slower entrance.
@export var spawn_fade_in_time: float = 2.5
## Seconds into the respawn fade-up before the HUD comes back and the respawn receipts pop (the wallet
## toast, the grudge-settlement reputation toasts, the holster tutorial reminder). At 0 everything used to
## land on the revive's FIRST frame — a full HUD plus a toast burst popping over a still-black screen while
## the world fades in behind it (information overload). The delay lets the world emerge first; the player
## keeps control from frame one — only the HUD visuals and the receipts wait. Keep it under
## spawn_fade_in_time so the HUD is back before the fade finishes.
@export var respawn_hud_delay: float = 1.0

@export_group("Death sting (the cinematic's soundtrack)")
## The clip that plays when YOU die, riding OVER the cinematic while the world ducks out from under it.
## Owned by DeathMix (scripts/player/death_mix.gd), which is the only thing that plays it.
## null = no sting, and the cinematic then sounds exactly as it did before this feature existed — that is
## the one-field rollback. The shipped default is a placeholder (a CS:GO music-kit round-loss track); swap
## it for a bespoke sting before any public build, the way character.gd's borrowed wooden thud is flagged.
@export var death_sting: AudioStream = null
## Trim for the sting clip itself, on top of whatever level it was mastered at.
@export_range(-40.0, 12.0, 0.5) var death_sting_volume_db: float = 0.0
## Wall-clock seconds after you die before the sting begins — just enough that it does NOT land on the same
## frame as the killing blow (which reads as part of the gunshot rather than as a reaction to it). A SLIGHT
## offset on purpose: the sting still opens under the keel-over, while the world is draining away beneath it.
## 0 = fire on the killing blow. Push it past death_sequence_time and the sting starts on a black screen.
@export_range(0.0, 10.0, 0.05) var death_sting_start_delay: float = 0.2
## Seconds the sting SWELLS up from silence once it starts. 0 = full volume on its first sample, which reads
## as a jolt: the world is ducking AWAY underneath it, so a hard-edged entry snatches the mix instead of being
## handed it. The swell is a linear-AMPLITUDE ramp (not a dB ramp, which would sit inaudible then rush in).
## Keep it short enough that the clip's own opening still lands — this shapes the entry, not the whole track.
@export_range(0.0, 4.0, 0.05) var death_sting_fade_in: float = 0.5
## Hold the death card long enough that the sting plays out and is STILL RINGING as the world comes back.
## When on, `respawn_delay` becomes a MINIMUM: the cinematic stretches the card's fully-visible beat so the
## screen starts fading back in exactly ON `death_sting_sync_point` — the sting's final chord — so the game
## returns underneath a chord that is still ringing, instead of after silence or by cutting the clip short.
## The hold is RE-SOLVED every death from the clip and the surrounding beat lengths, so retuning any other
## cinematic timing (death_sequence_time / death_card_fade_time / death_card_gap) keeps the chord aligned
## automatically — `death_sting_sync_point` is the one value you must re-measure by ear if you swap the clip.
## Turn it OFF to run the short cinematic on `respawn_delay` alone.
@export var death_card_holds_for_sting: bool = true
## The bus the sting plays on. MUST NOT appear in death_cinematic_buses — that is the whole trick, and
## DeathMix pushes a warning at boot if you break it. `sting` sends straight to Master and carries no
## effects (unlike `sfx`, which is -6.6 dB into a distortion, and `radio`, which is a lo-fi chain).
@export var death_sting_bus: StringName = &"sting"
## Which Options volume slider governs the sting. `sting` has no slider of its own, so DeathMix folds the
## named bus's slider into the sting player's volume_db at play time (0% = the sting is skipped entirely).
## Default `music` because the clip IS music. Set to "" to make it a full-mix event only Master can quiet.
@export var death_sting_slider_bus: StringName = &"music"
## OPTIONAL forced fade-out for the sting when you respawn. **0 (the default) = don't touch it — let the clip
## ring out to its own natural end**, even though the player is already back in control. That is deliberate:
## any forced fade competes with the clip's own decay and reads as the audio being CUT, because a ramp to
## silence is perceptually done long before it mathematically finishes. Set a value here only if a particular
## clip genuinely outstays its welcome. The RELOAD_* death modes always cut it dead regardless (fresh scene).
@export_range(0.0, 8.0, 0.05) var death_sting_release: float = 0.0
## The moment INSIDE the clip (seconds from the clip's own start) that should land exactly as the screen
## begins fading back in. For the shipped sting that is its FINAL SYNTH CHORD, measured at 6.32 s — the last
## real attack in the track, after which it is pure decay to silence at ~7.95 s. The cinematic solves the
## death card's hold so the respawn lands on this instant, so the chord hits as the world returns and then
## rings out (~1.6 s) underneath the fade-up.
##
## CLIP-SPECIFIC — the one number here that does NOT re-derive itself, because nothing can detect a chord for
## you. Re-measure it if you swap `death_sting`, or set it to 0 to stop aligning to anything (the cinematic
## then runs on `respawn_delay` alone and the sting simply plays on into the new life). Clamped to the clip's
## length, so an over-long value can never push the respawn past the end of the audio.
@export_range(0.0, 30.0, 0.01) var death_sting_sync_point: float = 6.32
## The buses the death cinematic ducks — i.e. everything that counts as "the world". These four cover 100%
## of authored audio: `radio` sends into `music` and `ambient_bed` into `ambient`, so ducking a parent takes
## its children with it. In Godot EVERY bus chain terminates at Master, so a sound cannot dodge a bus that
## is on this list by hiding on a child of it — which is exactly why the sting needs a bus that ISN'T.
## Setting this to [&"Master"] restores the old global fade exactly (and silences the sting along with it).
@export var death_cinematic_buses: Array[StringName] = [&"ambient", &"sfx", &"music", &"voice"]
## How much of the world survives underneath the sting (0..1 of its configured level). 0 = the pre-existing
## behaviour, a total drain to silence. Try 0.05-0.10 if the dead vacuum reads as a bug rather than a beat.
@export_range(0.0, 1.0, 0.01) var death_world_residue: float = 0.0

@export_group("Air-dash recharge flash")
## Peak opacity (0..1) of the white flash when the air-dash recharges — the "ready again" pop.
@export var dash_flash_peak_alpha: float = 0.5
## Seconds the dash-recharge white flash takes to fade out.
@export var dash_flash_time: float = 0.18

@export_group("Kill flash (HUD)")
## Peak opacity (0..1) of the full-screen pop when YOU land a kill — the Hotline-Miami flash. Sky-independent, so it shows over the skybox too.
@export var kill_flash_peak_alpha: float = 0.45
## Seconds the kill flash takes to fade out.
@export var kill_flash_time: float = 0.22
## The full-screen kill-flash tint.
@export var kill_flash_color: Color = Color(1.0, 1.0, 1.0)

@export_group("Toasts")
## Min gap (ms) between sneak-result toasts so a multi-pellet sneak shot shows one line.
@export var sneak_toast_cooldown_ms: int = 1200
## "Sneak Attack!" toast colour — a successful off-guard hit (was the player.gd SNEAK_HIT_COLOR const).
@export var sneak_toast_color: Color = Color(0.4, 1.0, 0.45)
## Limb-cripple toast colour — e.g. "Your head is crippled!" (was the player.gd CRIPPLE_TOAST_COLOR const).
@export var cripple_toast_color: Color = Color(1.0, 0.42, 0.38)
## Colour of the death wallet-settlement toast (death_purse_loss_fraction) shown on the in-place respawn — the one
## that tells you whether your killer pocketed the purse or it spilled on the ground where you fell.
@export var death_wallet_toast_color: Color = Color(1.0, 0.78, 0.32)
