class_name PlayerFeedbackSettings
extends Resource


## The player's HIT/DEATH/SPAWN feel — every feedback number on one inspector page
## (resources/tuning/PlayerFeedbackSettings.tres), read as GameSettings.player_feedback.<field>.
## These were consts scattered across player.gd / player_hud.gd / character.gd; now a designer
## tunes the whole "getting rocked -> keeling over -> fading back in" arc without touching code.
## The last group is the TAIL of that arc: once the shooting stops the mix calms down and you start
## knitting back together (Out-of-combat recovery, below).

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
## Peak opacity (0..1) of the full-screen pop when YOU land a kill — the Hotline-Miami flash. Sky-independent,
## so it would show over the skybox too.
##
## SHIPS AT 0 — a kill is a SKY-ONLY cue, and this alpha is the switch that turns the screen half back on.
## Reason: PlayerHud builds this ColorRect as the LAST child of `ui`, so it drew OVER the BloodSplatter overlay
## that Player.on_nearby_death sprays on a close kill, and a 0.45-alpha full-screen wash fading over 0.35 s
## buried the blood — the one piece of kill feedback that reads at exactly the melee range where the sky is not
## in frame. PlayerHud.flash_kill early-outs at 0, so nothing tweens; raise it to bring the screen punch back.
##
## ⭐KNOWN COST of shipping this at 0: the screen punch was the ONLY half of the kill cue that works with no sky
## in frame, and blood_splatter_range is just 3.5 m — so an INDOOR kill past ~3.5 m (a DoT tick finishing someone,
## a fall you caused, a shot down a corridor) now confirms with the camera kick alone. That is the deliberate
## trade for seeing the blood; re-arm this knob (and see kill_flash_color's note on hue) if it reads as too quiet.
@export var kill_flash_peak_alpha: float = 0.0
## Seconds the kill flash takes to FADE OUT — it snaps to peak alpha and eases straight to 0, with no hold beat
## (unlike the sky channel's up → hold → down). Only matters if kill_flash_peak_alpha is raised off 0; it was
## lengthened from 0.22 back when the punch was armed, and is kept so re-arming gives you the tuned fade rather
## than the old snap.
@export var kill_flash_time: float = 0.35
## The full-screen kill-flash tint, kept matched to GameSettings.effects.sky_flash_color (red) so that raising
## kill_flash_peak_alpha off 0 gives you the SAME colour on both halves of the cue rather than two different
## flashes. Retune it with the sky colour, or set Color(1, 1, 1) for the old white screen punch.
## ⭐If you DO re-arm it, note that RED is now the worst possible tint for it: the blood blobs it buried are
## themselves dark red (EffectsSettings.blood_splatter_tint_*), so a red wash hides them by hue as well as by
## alpha, and merely reordering the rect under BloodSplatter will not give the blobs their contrast back.
@export var kill_flash_color: Color = Color(1.0, 0.1, 0.08)

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
@export_group("Out-of-combat recovery")
## Seconds of quiet before the player counts as OUT OF COMBAT — the ONE predicate behind BOTH the passive health
## regen and the heartbeat duck (Player.is_out_of_combat), so the audible cue and the mechanic can never disagree
## about when the fight ended.
## "Combat" is whatever stamps Player.note_combat(): we fired, we lost HP for ANY reason (a hazard, a burn tick, a
## fall with nobody around — being on fire IS combat), or a hostile is drawing a bead on us. That last one re-stamps
## while an alerted enemy holds us as its target, so being HUNTED never opens the window even between shots.
## ⭐ Keep this ABOVE GunPose.idle_combat_grace (5.0, gun_pose.gd:40) so the VISUAL tell lands FIRST: the weapon
## droops, and only then does the mix soften and the HP start climbing. A player who watched the gun come down has
## already been taught what the quieter heartbeat means; below 5.0 the reward arrives with the gun still up.
@export var combat_calm_grace: float = 6.0
## Health regenerated per second while out of combat, as a FRACTION OF MAX HP. 0 = no passive regen at all (the
## whole feature off, no code change).
## A FRACTION rather than flat HP/s because it pins the RECOVERY TIME (1/rate seconds empty->full) regardless of
## max_hp — which LevelUp, PerkManager and PassiveItemBuffs all move at runtime through CharacterStats.restamp_derived
## — so the feel doesn't drift as a run progresses and a high-strength build doesn't silently heal proportionally
## slower. 0.012 = ~83 s for a full refill at baseline endurance; on the shipped 4 HP player that's 0.048 HP/s.
## ⚠ This competes with the shipped healing money-sinks (the Healer prices linearly in missing HP; the Wait screen's
## hourly trickle). Lower this — or health_regen_cap_frac — if paying to be patched up stops mattering.
@export var health_regen_frac_per_sec: float = 0.012
## Ceiling the passive regen climbs to, as a fraction of max HP. ⭐ THE ECONOMY DIAL. 1.0 = all the way to full.
## Set it to ~0.5 for the Souls/New-Vegas shape WaitSettings' header describes: field regen only gets you off the
## floor, and a Bonfire / Healer / health pack still has to finish the job.
@export_range(0.0, 1.0, 0.05) var health_regen_cap_frac: float = 1.0
## Minimum health the regen banks before it COMMITS, as a fraction of max HP. The tick accumulates into a float
## carry and only pays out through Character.heal() once the carry crosses this — because `damaged` is a DISCRETE
## event signal (the player's carried emitting light recolours on it, see _setup_health_light), and firing it 60x a
## second for a sub-milli-HP slice would re-run health_light_color_for every physics frame. Rate-PROPORTIONAL by
## design: the emit count is fixed per HP healed, not per second, so lowering the RATE can't reintroduce the spam —
## and because both the step and the rate scale with max_hp, the commit INTERVAL is the same at every max HP.
## ⭐ KEEP IT SMALL — this is signal hygiene, and it is NOT free feel. The HUD bar polls player.hp every frame and
## fills the live segment CONTINUOUSLY (ui.gd _update_hp_bar), so the step size is directly visible: at 0.05 the bar
## sat frozen for ~4 s and then jumped a fifth of a segment, which reads as a per-tick regen effect rather than the
## continuous knitting-back-together this is meant to be. 0.01 commits roughly once a second — a creep, not a tick.
## 0 = commit every frame (smoothest possible, one `damaged` emit per frame).
@export_range(0.0, 0.5, 0.01) var health_regen_commit_frac: float = 0.01
## dB SUBTRACTED from the low-HP heartbeat while out of combat — the "slight" duck. Authored POSITIVE ("how many dB
## quieter") and absf()'d at the read site, so a designer who types a minus still gets a cut, never a boost.
## Folded into the SAME lerp(heartbeat_db_min, heartbeat_db_max, intensity) the beat already uses, so the near-death
## ramp survives intact: a calm player bleeding out still gets louder as they fall, just quieter than mid-firefight.
## ⭐ VOLUME ONLY. Do NOT express this duck by scaling hb_intensity — that scalar also drives the BEAT INTERVAL and
## the hard-silence gate in Player._update_low_hp, so scaling it would slow the pulse (killing the urgency read — a
## design change wearing a mix change's clothes) or mute the cue outright. And do NOT duck the `sfx` BUS: it carries
## every other SFX plus the diegetic speaker bus, and the death mix already writes its own duck there.
## 4.0 dB reads as released tension without approaching inaudible — against the shipped -16.0/+2.0 range it puts a
## calm threshold beat at -20.0 dB and a calm near-death beat at -2.0 dB, so the cue still reads at every HP level.
@export_range(0.0, 24.0, 0.5) var heartbeat_calm_duck_db: float = 4.0
