class_name NpcAiSettings
extends Resource

## Global NPC BRAIN tuning — the behaviour numbers shared by every NPC, on one inspector page
## (resources/tuning/NpcAiSettings.tres), read as GameSettings.npc_ai.<field>. Per-NPC variety
## (sight ranges, move speeds, dispositions, voices, loot) stays on the NPC / Perception / NpcData
## exports; THIS page is the species-wide dials.

@export_group("Targeting & engagement")
## Seconds between full target re-acquisition scans (invalidation still retargets immediately).
@export var retarget_interval: float = 0.5
## Fallback engage range (m) for a weapon with no effective_range.
@export var unranged_aim_fallback: float = 15.0
## PROJECTILE GRACE BAND (m): how far BEYOND its weapon-scaled engage range an armed NPC still ATTEMPTS
## (and telegraphs) shots — only with a weapon that spawns physical rounds (WeaponData.projectile_scene)
## AND authors a positive effective_range. An unranged lob (the rock, effective_range 0) gets no band: it
## engages at the unranged_aim_fallback guess already and its flat ballistic arc grounds inside it.
## Why it exists: holding fire at the nominal engage range made a kiting player untouchable — a shotgunner
## (effective_range 5) simply never fired at a backpedaling target. Inside the band the NPC fires WHILE
## still closing (the engage standoff itself is unchanged), so the pressure is dodgeable projectile fire
## instead of a silent chase. Since the 2026-08-25 "enemies never hitscan" rule EVERY ranged AI shot is a
## live round (ShotResolver.ai_fires_live_projectile) that flies projectile_speed x life_time metres, so
## effective_range no longer caps AI damage anywhere — this band only decides how far past the engage
## standoff the TRIGGER still pulls. Melee weapons get no band (their reach really is the trace).
## 0 disables the band.
@export var fire_grace_range: float = 8.0
## Base AIM-ERROR cone (degrees) for every RANGED shot an NPC fires — the "NPCs are not aimbots" dial. Each
## pellet deflects by an independent roll in [-error, +error] on both aim axes (the same math as weapon
## pellet_spread; attack.gd sums the two, so it widens spread rather than replacing it). Scaled PER NPC by
## the same gunplay steadiness formula the player's aim wander uses (CharacterStats.sway_mult — 8% tighter
## per gunplay point over baseline, floored at perfectly accurate), so an NpcData stat sheet is what makes a
## marksman a marksman: a sheetless mook sprays the full cone, the sniper archetype (gunplay 2) shoots 16%
## tighter, gunplay 12.5+ never misses. For scale: at 2.5 deg a stationary man-sized target ~10 m out is
## roughly a coin flip per bullet; point-blank shots still land. 0 = every NPC is back to perfect aim.
@export var aim_error_deg: float = 2.5
## TARGET LEADING (0..1): how much of the computed INTERCEPT offset an NPC aims ahead of a MOVING target —
## the "stop strafing forever" dial. Before this every AI round was fired at where the target IS, so once the
## 2026-08-25 "enemies never hitscan" rule gave those rounds travel time, a player who simply held a strafe
## walked out of every bullet: at 15 m an SMG round (40 m/s for AI) takes 0.375 s to arrive and a 4 m/s strafe
## carries you 1.5 m in that time — two body-widths clear of a perfectly-aimed shot. The NPC now solves for
## where you WILL be (NpcCombat.lead_aim_point: a real quadratic intercept against your HORIZONTAL velocity,
## using the round's own AI-scaled speed) and aims there instead. 1.0 = a perfect intercept solution, so a
## CONSTANT-velocity strafe never dodges anything again; 0 = the old shoot-at-your-navel behaviour.
## The default deliberately UNDER-leads: the residual (0.15 x your drift) plus the aim_error_deg cone above
## keeps a straight strafe a coin flip rather than a death sentence, and leaves headroom for the gunplay
## scaling below to mean something. Vertical velocity is NOT led (a jump/fall is aimed at flat), so hopping
## still throws aim off — and because the solve reads your velocity at the instant the trigger pulls, CHANGING
## DIRECTION is the counterplay it cannot predict. That is the intended dodge: juke, don't hold a strafe.
## Scaled PER NPC by the SAME gunplay steadiness the aim cone uses (divided by CharacterStats.sway_mult, then
## clamped to 1.0), so WHO the NPC is decides how well it predicts: a sheetless mook leads at this value, the
## sniper archetype (gunplay 2) at 0.92, and a gunplay 12.5+ elite solves the intercept exactly.
@export_range(0.0, 1.0) var aim_lead_fraction: float = 0.85
## Hard cap (seconds) on the flight time the lead solve is allowed to predict over. A target further out than
## its round can usefully reach — or one whose ground speed makes the intercept solve degenerate — would
## otherwise be led metres into a wall. At the shipped ranges nothing comes close to this (a 40 m/s AI SMG
## round covers the whole grace band in ~0.4 s), so it is purely a sanity clamp; lower it to blunt leading at
## long range only. Irrelevant when aim_lead_fraction is 0.
@export var aim_lead_max_time: float = 1.5
## AIM INERTIA (degrees per second): the fastest an NPC's SHOT DIRECTION may swing across the world. The
## "stop snapping onto me" dial. Before this the fired direction was solved fresh from geometry at the instant
## the trigger pulled, so an NPC's aim was wherever it needed to be with no transition at all: step out of
## cover and the first round was already on your chest, dash past a guard and its muzzle teleported with you.
## The aim is now a tracked vector that has to TURN — it starts on the body's own facing, and every frame it
## rotates toward the ideal (led) aim point by at most this many degrees, so a big correction costs real time.
## For scale at the default: a 90 deg swing takes ~0.55 s (about one min_shot_interval — the NPC gets roughly
## one shot off mid-turn, and it goes wide), a full 180 deg about-face ~1.1 s.
## ⭐It deliberately does NOT re-open the infinite strafe [[aim_lead_fraction]] was added to close. A rate CAP
## has zero steady-state error: while tracking needs less than this many deg/s the aim sits exactly on the
## intercept, so a held strafe is punished as before (10 m out, a 5 m/s sidestep needs only ~29 deg/s). It
## bites on CHANGE — appearing, dashing, an about-face, a close-range circle strafe — which is the counterplay
## the design already asks for: juke, don't hold a line. An exponential ease would have leaked a permanent
## tracking lag into the steady case and undone that, which is why this is a hard cap and not a smoothing.
## While an NPC cannot SEE its target the aim holds on the last-known position instead of tracking through the
## wall, so re-peeking a DIFFERENT angle costs the full swing and re-peeking the same hole does not.
## Scaled PER NPC by the same gunplay steadiness the cone and the lead use (divided by CharacterStats.sway_mult),
## so a marksman whips on faster; a gunplay 12.5+ elite swings instantly. 0 = no cap, i.e. the old snap-on aim.
@export var aim_turn_rate_deg: float = 160.0
## AIM INERTIA, second half (seconds): how long an NPC's READ of your velocity takes to catch up, as the time
## constant of an exponential ease. The intercept solve above is only as good as the velocity it is fed, and
## feeding it your instantaneous velocity meant the predicted point snapped the moment you moved — start a
## strafe and the aim jumped a body-width ahead of you in the same frame it began. The NPC now believes a
## LAGGED velocity, so starting, stopping and reversing all under-lead for a beat before the prediction
## catches up (a held strafe still converges to the full intercept within ~2-3x this, so it is not a way back
## to dodging forever). Eases toward ZERO while the target is out of sight — you cannot predict motion you
## cannot see — so a shot taken the instant someone re-peeks is barely led at all.
## Scaled PER NPC by gunplay (multiplied by CharacterStats.sway_mult), so a steadier shooter reads you sooner;
## a gunplay 12.5+ elite reads you instantly. 0 = the raw instantaneous velocity, i.e. the pre-inertia solve.
@export var aim_velocity_lag: float = 0.25
## Within this (m) a combatant treats its shot as CLEAR even when the LOS ray self-occludes
## (a target crowded onto the muzzle starts the ray inside its own collider) — fire anyway.
@export var point_blank_range: float = 2.0
## Smallest angle (degrees) a deliberately-missed warning shot deflects by — the low end of the miss spread.
@export var miss_deflect_min_deg: float = 5.0
## Largest angle (degrees) a warning shot deflects by — the high end of the miss spread. Keep above min.
@export var miss_deflect_max_deg: float = 12.0
## How many seconds before a shot lands the incoming-shot warning beep plays (it also gates the in-sync
## aim-radial blink) — part of the NPC's firing cadence. Higher = more warning before the hit lands.
@export var beep_lead_time: float = 0.5
## BREATHING ROOM (seconds): the SHORTEST gap an NPC may leave between two RANGED shots, whatever its gun's
## authored attack_speed says. A floor, not an offset — a weapon already slower than this is untouched, so
## only the fast guns are paced down and the slow ones keep their authored rhythm.
## Why it exists: every ranged shot drags a full telegraph package behind it (the lock-on charge sting, the
## laser/aim-radial ramp from 0 to 1, and the incoming-shot BEEP a beep_lead_time beat before impact), and
## that package is sized by the SHOT CADENCE. A gun whose cadence is at or under beep_lead_time therefore
## telegraphs continuously: the shipped pistol (attack_speed 0.44) beeps every 0.44 s with a ~0.04 s gap and
## re-locks its aim ramp just as fast, and the SMG (0.125) is a flat strobe. A warning that never stops is
## not a warning, and the run-up to "he is about to shoot" has no room to read. Flooring the cadence gives
## the whole package an audible/visible OFF beat between shots — fire, breathe, wind up, fire.
## ⭐ Keep this comfortably ABOVE beep_lead_time or the beep has no silence to sit in (the difference between
## the two IS the quiet gap: 0.9 − 0.5 = 0.4 s). npc.gd additionally caps the aim-radial blink at 90% of the
## live cadence, so an under-tuned value degrades to a strobe rather than a stuck-on light.
## RANGED ONLY — melee/fists/spray-paint cadences are untouched (they carry no beep or radial to space out),
## keyed off the same NPC._weapon_uses_ranged_attack_telegraphs predicate that gates the telegraphs.
## Applied AFTER the per-NPC rate_of_fire_factor, so it is a hard species-wide ceiling on rate of fire: a
## profile cannot author its way under the floor. 0 = no floor, i.e. every NPC is back to firing at its
## weapon's raw authored cadence.
@export var min_shot_interval: float = 0.9

@export_group("Self care")
## An NPC reaches for a medkit below this HP fraction...
@export var medkit_hp_frac: float = 0.5
## ...at most once per this many ms.
@export var medkit_cooldown_ms: int = 4000
## Combat over: seconds of calm before the weapon goes back in the holster.
@export var holster_delay: float = 2.5

@export_group("Companion follow")
## Following allies hold position this far (m) from the leader.
@export var follow_standoff: float = 3.0
## Fallen this far behind (m) AND off-screen -> the catch-up blink may fire...
@export var follow_teleport_distance: float = 14.0
## ...at most once per this many seconds.
@export var follow_teleport_cooldown: float = 3.0

@export_group("Home return (leash)")
## Do NPCs go back to the spot they were authored at when the world should settle? These seed every auto-built
## NpcHomeReturn (scripts/npc/npc_home_return.gd) — the drop-in that owns the behaviour — so this page is the
## species-wide default and a CONFIGURED NpcHomeReturn dropped under one NPC overrides it per instance. OFF -> no
## NPC ever leashes home: a chase that ends two districts away leaves the guard standing there for good, and dying
## leaves the whole cast scattered wherever the fight ended (the pre-leash behaviour).
@export var home_return: bool = true
## Send every NPC home when the PLAYER DIES. The default CHECKPOINT_RESPAWN death mode is a Dark-Souls in-place
## revive that leaves the world untouched, so without this an encounter never resets — you come back to enemies
## parked wherever they killed you. The reset is timed to the death cinematic's FULLY BLACK frame (the beat the
## "You were killed by X" card fades in on), so it is never visible.
@export var home_return_on_player_death: bool = true
## EXTRA seconds to wait after that fully-black beat before the return fires. 0 (the default) is right for almost
## everything — the screen is already covered, so there is nothing left to hide behind. Raise it only to push the
## reset later still, e.g. past the death card's fade-out. Real seconds, not slow-mo-scaled.
@export var home_return_death_delay: float = 0.0
## Also restore every surviving NPC to FULL HP (and clear its limb damage) on that same player-death beat — the
## other half of the encounter reset. Without it, CHECKPOINT_RESPAWN hands you a second attempt against enemies
## still carrying every wound from the first, so a fight you lost gets easier each time you die at it (and that
## damage never heals for the rest of the session). THE DEAD ARE NOT REVIVED — an NPC you killed stays killed.
## Applies to the whole cast, companions and shopkeepers included. OFF -> damage persists (the pre-heal
## behaviour); per-NPC overrides live on `heal_on_player_death` in a hand-placed NpcHomeReturn.
@export var home_return_heal_on_player_death: bool = true
## Also hand every surviving NPC back the AMMO it BURNED on that same player-death beat — magazines refilled and
## every spare clip its reloads spent returned to its backpack. The third piece of the encounter reset, for the
## same reason as the heal: under CHECKPOINT_RESPAWN spent ammo persists for the rest of the session, so dying at
## the same fight over and over leaves the enemy progressively more disarmed until it runs dry and drops to fists
## — a fight that gets easier every time you lose it. ONLY WHAT WAS FIRED comes back: the count is booked as each
## clip is spent, so ammo the player PICKPOCKETED off an NPC stays stolen and stripping a guard to disarm him
## still works. THE DEAD ARE NOT RESTOCKED — a corpse's backpack is the loot you earned. OFF -> spent ammo
## persists (the pre-restock behaviour); per-NPC overrides live on `restore_ammo_on_player_death` in a
## hand-placed NpcHomeReturn.
@export var home_return_restore_ammo_on_player_death: bool = true
## Send an NPC home once the player hasn't been able to SEE it for a while (the leash for a chase that wandered
## off the map). Never moves a body in view: the blink is refused while the NPC or its post is on screen.
@export var home_return_off_screen: bool = true
## Seconds unobserved before that leash pulls. The clock resets the moment the NPC is visible again.
@export var home_return_off_screen_delay: float = 15.0
## Only run the off-screen clock while the NPC is CALM (perception UNAWARE, no live target). ON = the leash never
## yanks an enemy out of a running fight because you ducked behind a wall — it waits for perception to give up
## first. OFF = a hard leash: break line of sight long enough and the encounter resets outright. Either way an NPC
## that currently has AGGRO on you is never TELEPORTED by the off-screen leash — that is a hard rule in the
## component, not a knob; the most it will do is stand down and walk back.
@export var home_return_requires_calm: bool = true
## How far (m) an NPC must be from the player before the off-screen leash may TELEPORT it rather than walk it home.
## Out of the view cone isn't the same as unnoticeable — a body vanishing a few metres behind you is felt, and
## you're one turn away from looking right at where it was. Mirrors the companion blink's own distance gate.
@export var home_return_min_blink_distance: float = 8.0
## How far (m) an NPC may be from its post before a return is worth doing. A wanderer additionally gets its whole
## wander_radius as slack, so the leash never fights its roam disc.
@export var home_return_slack: float = 3.0
## TELEPORT home (the hidden blink the dogs / companions use to catch up, aimed at the spawn spot instead) rather
## than only standing down and letting the NPC walk back. OFF -> the walk-back alone, which can't recover an NPC
## stranded off the navmesh. (A SEATED NPC walks back fine: it stays standing until it is within
## seat_return_radius of its post, so the idle return-to-post drives it home before the seat re-applies.)
@export var home_return_blink: bool = true

@export_group("Seated posture")
## How close (m, horizontal) a `sitting` NPC must be to its post before the seated pose applies again. The seat is
## a POST behaviour: a sitter that stood up to fight and chased you across the level has to WALK BACK before it
## drops onto the floor, or every firefight ends with a raider sitting down in the middle of the corridor. While
## it is further out than this it stays standing, which is what lets the GOAP Idle floor's return-to-post walk run
## at all (NpcLocomotion._idle short-circuits for a seated NPC). Keep it comfortably ABOVE the Locomotor's
## arrival_distance (1.0 by default) — that walk stops within arrival_distance of the post, so a smaller radius
## here would leave the NPC standing at its own chair forever; npc.gd floors it against the live value anyway.
@export var seat_return_radius: float = 1.25

@export_group("Scavenging")
## Seconds between an NPC's raid-a-container scans — how often it looks for loot nearby.
@export var scavenge_scan_interval: float = 1.5
## How far (m) a scavenge scan reaches for raidable containers.
@export var scavenge_scan_radius: float = 12.0

@export_group("Loadout")
## Spare clips an armed NPC spawns with (drives reloads and what their corpse yields).
@export var starting_clips: int = 4

@export_group("Stealth")
## Do dead bodies raise the alarm? When ON, every NPC death leaves a discoverable Corpse marker at the spot,
## and a nearby UNAWARE NPC that SEES it gets spooked -- it investigates the body and calls out, so a quiet
## kill risks blowing your cover. OFF (default) -> no markers spawn and the corpse scan is a no-op, so the
## FSM is byte-identical to before. Turn it on to make stealth kills consequential, then playtest.
@export var body_discovery: bool = false
## Can a NOISE pull an NPC that has NOT yet acquired an enemy into investigating it? ON -> any NPC with
## `hearing` walks toward the loudest nearby &"noise" source (the player emits one live; thrown decoys /
## machines add more), regardless of disposition -- a guard hears your shot through a wall, a townsperson
## looks up when something crashes (companions following a leader are exempt). OFF (default) -> noise only
## matters once an NPC already has you as a target (today's behaviour), so the no-target idle path is
## byte-identical. Pairs with body_discovery: both share the no-enemy "investigate a point" path.
@export var hearing_initiates: bool = false
## Seconds between a no-target NPC's noise + corpse group scans (the &"noise" / &"corpse" walk + LOS rays),
## throttled like scavenging so an idle crowd doesn't rescan every frame. The walk-to-the-spot motion still
## runs every frame off the last result; only the (re)scan is paced. 0 = scan every frame. Only matters when
## hearing_initiates or body_discovery is on.
@export var distraction_scan_interval: float = 0.3
## Do WALLS muffle sound? When ON, a noise an NPC hears (a heard target's noise OR a &"noise" decoy) is
## attenuated when solid geometry sits between the enemy's eye and the source -- so a decoy through a doorway
## carries while one behind a wall doesn't. OFF (default) -> sound rounds corners exactly as before
## (behaviour-preserving). Makes interiors tactical; pairs with hearing_initiates / the thrown decoy.
@export var hearing_occlusion: bool = false
## How much a wall between the listener and a noise cuts its audible RADIUS (0..1) when hearing_occlusion is on.
## 0.5 = heard at half range behind a wall; 1.0 = a walled-off noise is silenced. Only matters with occlusion on.
@export_range(0.0, 1.0) var hearing_wall_attenuation: float = 0.5
## How far (m) before a noise source the occlusion ray stops, so the source's OWN body (the player's ~0.5 m
## capsule carrying the live noise, a thrown decoy's collider) is never mistaken for an occluding wall. Must
## exceed the widest noise-carrier's radius -- 1.0 clears the player capsule with headroom. A real wall within
## this distance of the source (on the listener's side) won't muffle. Only matters with occlusion on.
@export var hearing_source_skip: float = 1.0

@export_group("Music reactions")
## Do nearby NPCs react to a PLAYING radio they can hear (within the radio's audible_radius)? When ON, an idle
## non-hostile NPC turns its head toward the radio and comments once, keyed to the song/playlist QUALITY (a
## deterministic score of the radio's text). OFF (default) -> a playing radio is inert to NPCs, byte-identical to
## before. Applies to BOTH friendly and hostile idle NPCs (a raider chilling by its own radio comments too). It is a
## passive notice + turn + bark, NOT an investigate -- the NPC does not walk over. The head turns via head_look; the
## BODY turns via music_turn_body below; the comment fires regardless of either. Pairs with the radio's audible_radius.
@export var music_reactions: bool = false
## When music_reactions is on, does an attending idle NPC TURN ITS BODY to face the radio (and hold still to listen)?
## ON (default) -> a visible "look at the radio" body yaw — head_look alone is cone-clamped, so a radio BEHIND an NPC
## would never be looked at without the body turning. OFF -> the reaction is the head glance + comment only (no body
## turn, no stop), for a level where idle NPCs should keep moving. Either way it yields to an active schedule/patrol
## route (a guard on patrol keeps walking). Only matters when music_reactions is on.
## INTENDED STEALTH KNOCK-ON: an NPC's view cone is its body's forward, so a HOSTILE posted sentry that turns to face
## a radio swings its detection cone off its authored watch spot — a deliberate "distracted by music" opening the
## player can create by switching a radio on behind a guard. Turn this OFF to keep guards watching their posts.
@export var music_turn_body: bool = true
## Quality score (0..1) below which a song reads AWFUL (the lowest comment tier). Below music_tier_good -> MEH.
@export_range(0.0, 1.0) var music_tier_meh: float = 0.25
## Quality at/above music_tier_meh and below this -> MEH; at/above this and below music_tier_great -> GOOD.
@export_range(0.0, 1.0) var music_tier_good: float = 0.5
## Quality at/above this -> GREAT (the NPC loves it). Keep above music_tier_good.
@export_range(0.0, 1.0) var music_tier_great: float = 0.8

@export_group("De-escalation")
## Holster de-escalation (put the gun away to stand a PROVOKED neutral/friendly back down, FNV-style) works at most
## ONCE per NPC per life. After it forgives you and you RE-ATTACK it, holstering no longer pardons that NPC — it
## "won't fall for it twice" and stays hostile to the death (its aggro icon flashes to tell you why). This closes the
## free-kill farm where the player spams the hold-R holster toggle to repeatedly pardon a mob they keep shooting. OFF
## -> the OLD behaviour: a provoked NPC is infinitely holster-forgivable (exploitable). Genuinely/predisposed-hostile
## factions are never provoked, so this never touches them either way. The latch is per-life — a fresh scene reload
## or pool reuse clears it. Default ON.
@export var holster_forgiveness_once: bool = true
# (No flee exemption to the one-shot above — deliberately. A `fleeing_always_forgivable` knob shipped here
# briefly (2026-07-28) and was REMOVED after playtest: break_and_flee() is one-way within a life, so any
# coward-temperament fighter shot until it panicked became a PERMANENT fleer — permanently exempt, infinitely
# holster-pardonable — and even pure FLEE civilians became a consequence-free assault loop (beat, holster,
# rep round-trips to zero, repeat). Post-mortem: npc.gd _holster_forgiveness_available(). Don't re-add it.)
## DEATH SETTLES THE SCORE: when a hostile NPC KILLS the player, every NPC that is hostile ONLY because the player
## PROVOKED it stands back down AS THEY RESPAWN (judged at death while the killer is still live, applied on the
## revive so the world calms down in front of the player) — the provoked flag clears and the rep each provoke took
## is restored,
## the same pardon holstering grants (but WITHOUT spending the one-shot latch above: dying isn't the player talking
## anyone down, so it can't burn a pardon they may still need). The grudge was "you shot at me"; they shot back and
## won, so it's settled. Without this, a CHECKPOINT_RESPAWN revives the player in an untouched world where the town
## is hostile FOREVER once the one-shot holster pardon is spent, and every retry re-provokes it — a death spiral.
## Only a PROVOKE is settled: a faction soured by KILLS (kill_penalty is never reversed) stays hostile, and
## genuinely/predisposed-hostile factions were never provoked, so raiders keep hunting you either way. The player
## also has to have been killed BY a hostile NPC — a fall, a hazard, your own grenade or a friendly's stray shot
## settles nothing. OFF -> a provoked NPC stays provoked through your death and holstering is the only way back
## down. Default ON.
@export var deaggro_on_player_death: bool = true

@export_group("Head look")
## Do NPC heads track what they're attending to INDEPENDENTLY of the body (Fallout-3/NV style)? When ON, any NPC
## carrying a NpcHeadLookMount rotates its VISIBLE head toward its foe / a nearby player / a noise it's
## investigating -- smoothly, clamped to a neck cone -- instead of only swivelling the whole body (which reads as
## lifeless). OFF (default) -> the mount no-ops and the head sits at its rest pose, byte-identical to before. Flip
## it on, then playtest (the head aim axis/sign can need a per-rig tweak).
@export var head_look: bool = false

@export_group("AI level of detail")
## Species-wide seeds for the AiLod drop-in (scripts/components/ai_lod.gd) every NPC auto-builds — how often a
## DISTANT, UNAWARE NPC re-runs its brain. A configured AiLod dropped under one NPC overrides these for it.
##
## Measured on the shipped map (2026-08-13, GTX 1660 / i5-9400F): at 40 NPCs, npc.gd's own _physics_process was
## ~54 ms of a 66.7 ms frame (81%). It is the tick CADENCE that costs, not navigation (0.1-0.4 ms), not RVO
## avoidance, and not sight_range — all three were measured and refuted. Movement is never throttled (gravity
## and move_and_slide run every tick at every band), so a throttled NPC still walks smoothly; it only DECIDES
## less often. NPCs that are fighting, investigating, in dialogue, or following you are exempt entirely.
##
## OFF -> every NPC thinks every physics tick, exactly as before this existed.
@export var lod_enabled: bool = true
## Metres. Inside this the NPC always thinks every tick. Raise it if throttled NPCs read as sluggish up close.
@export var lod_near_distance: float = 20.0
## Metres. Between near and this the NPC thinks every lod_mid_interval; beyond it, every lod_far_interval.
@export var lod_far_distance: float = 45.0
## Seconds between thinks in the middle band (0.1 = 10 Hz).
@export var lod_mid_interval: float = 0.1
## Seconds between thinks in the far band (0.25 = 4 Hz).
@export var lod_far_interval: float = 0.25
