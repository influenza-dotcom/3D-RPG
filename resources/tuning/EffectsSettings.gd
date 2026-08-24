class_name EffectsSettings
extends Resource

## Visual-FX tuning, grouped below: decal fade/placement, dust puffs (jump/land/slide),
## the on-screen blood overlay (BloodSplatter), the gore/body-part gibs and the PIN kill,
## the thrown-weapon trail, explosion / muzzle-flash / barrel-smoke visuals, the floating damage numbers,
## and the first-person view-model pose feel (kick / holster / reload / landing). Consumed
## across the effects scripts, bloody_mess, the decals, Explosion, DamageNumberPopup,
## ThrowTrail, MuzzleSmoke, and GunMesh.

@export_group("Decals")
## How fast a bullet-hole / blood decal fades its alpha toward 0 each frame (higher = decals vanish sooner).
@export var decal_fade_rate: float = 0.9
## Alpha at which a fading decal is removed from the world — the cleanup threshold (lower = it lingers fainter for longer).
@export var decal_fade_min_alpha: float = 0.01
## How far (metres) a decal is pushed off the hit surface along its normal so it doesn't z-fight the wall.
@export var decal_normal_offset: float = 0.02
## How far (metres) the raycast looks for a surface to stick a decal onto at the impact point. Bigger = decals attach across wider gaps.
@export var decal_probe_distance: float = 0.5

@export_group("Dust")
## Size/density (0..1) of the dust puff kicked up on a jump. Higher = a bigger jump cloud.
@export var dust_jump_intensity: float = 0.7
## Baseline dust puff size on ANY landing, before the impact bonus — the floor of a landing cloud.
@export var dust_land_base_intensity: float = 0.15
## Extra dust scaled by landing impact strength (added on top of the base) — bigger = harder landings throw much more dust.
@export var dust_land_impact_bonus: float = 0.85
## Landing impact strength (0..1) below which NO landing dust spawns — soft step-downs stay clean.
@export var dust_land_min_impact_to_spawn: float = 0.08
## How far down (metres) to raycast for the ground to spawn dust on. Bigger = dust still finds the floor from higher up.
@export var dust_ground_probe_distance: float = 3.0
## How far above the found ground (metres) the dust spawns so it sits on the surface, not buried in it.
@export var dust_ground_offset: float = 0.05
## Floor on a dust burst's particle-emission ratio so even a tiny puff shows some particles — clamps intensity from below.
@export var dust_amount_ratio_min: float = 0.1

@export_group("Blood Splatter (UI overlay)")
## How close (metres) a death must be to splash blood on the player's SCREEN overlay; closer kills splash harder. Bigger = gorier from further away.
@export var blood_splatter_range: float = 3.5
## Seconds each screen-overlay blood blob takes to fade out.
@export var blood_splatter_fade_time: float = 1.5
## Fewest blobs a faint (distant) splatter draws — the low end, used at intensity 0.
@export var blood_splatter_min_blobs: float = 3.0
## Most blobs a point-blank splatter draws — the high end, used at intensity 1. Keep above min_blobs.
@export var blood_splatter_max_blobs: float = 8.0
## Smallest random size multiplier a blob can roll — the low end of per-blob scale variety.
@export var blood_splatter_min_scale: float = 0.6
## Largest random size multiplier a blob can roll — the high end of per-blob scale variety.
@export var blood_splatter_max_scale: float = 1.8
## Base blob size (pixels, before the random scale) for the screen overlay — the overall splatter footprint.
@export var blood_splatter_base_size: float = 60.0
## Red channel (0..1) of the screen-overlay blood tint.
@export var blood_splatter_tint_r: float = 0.6
## Green channel (0..1) of the blood tint — small, keeps it dark.
@export var blood_splatter_tint_g: float = 0.04
## Blue channel (0..1) of the blood tint — small, keeps it dark/red.
@export var blood_splatter_tint_b: float = 0.02

@export_group("Gore gibs")
## How many gibs a bloody-mess death bursts into. More = a gorier explosion (and more physics bodies).
@export var gib_count: int = 6
## Horizontal random scatter (metres) of gib spawn points around the victim.
@export var gib_spawn_offset_xz: float = 0.3
## Lowest a gib can spawn above the victim's origin (metres) — the bottom of the spawn-height spread.
@export var gib_spawn_offset_y_min: float = 0.4
## Highest a gib can spawn above the victim's origin (metres) — the top of the spawn-height spread.
@export var gib_spawn_offset_y_max: float = 1.0
## Slowest a gib launches (m/s) — the low end of the burst speed range.
@export var gib_vel_min: float = 7.0
## Fastest a gib launches (m/s) — the high end of the burst speed range. Keep above vel_min.
@export var gib_vel_max: float = 14.0
## Least extra upward fling (m/s) added to a gib so they pop UP, not just outward — low end of the up-bias range.
@export var gib_up_bias_min: float = 0.8
## Most extra upward fling (m/s) added to a gib — high end of the up-bias range.
@export var gib_up_bias_max: float = 2.2
## Max random tumble (rad/s per axis) spun onto each gib as it launches — bigger = wilder spinning.
@export var gib_angular_range: float = 18.0
## Fewest shots it takes to pop a gib — the low end of a gib's random HP.
@export var gib_hp_min: int = 1
## Most shots it takes to pop a gib — the high end of a gib's random HP.
@export var gib_hp_max: int = 2
## World cap on simultaneously-live gibs; spawning past it reclaims the oldest first (keeps a gory scene from tanking framerate). Counts BODY-PART gibs too — a part-burst death spawns up to 6 limbs plus body_part_gib_meat_count chunks, so this was raised from 24 when body parts landed.
@export var gib_max_active: int = 36
## Seconds a gib lingers in the world before it begins fading out.
@export var gib_lifetime: float = 12.0
## Seconds a gib takes to fade out once its lifetime expires.
@export var gib_fade_time: float = 1.0
## Wipe the PLAYER'S OWN remains when it revives at a checkpoint — the gibs and body parts its death flung, the
## floor blood splat, the blood drops and their stains, and the corpse if one was authored. On (the default) the
## Dark-Souls in-place respawn brings you back to a clean spot instead of standing over yesterday's body; off
## leaves the whole burst lying where you died. Only the player's gore is ever tagged, so NPC gore is untouched
## either way, and the RELOAD_* death modes rebuild the world regardless. See Character.death_gore_group().
@export var clear_player_gore_on_respawn: bool = true

@export_group("Body-part gibs")
## Master switch: on death a character comes apart into its OWN head / torso / arms / legs (the LEGO / Roblox
## read) as well as spraying meat chunks. Needs a BodyModelSwap on the actor — that component's live part
## models are what fly. Off = the old meat-chunks-only burst. A BodyPartGibs drop-in on an actor OVERRIDES
## this switch for that actor, both ways.
@export var body_part_gibs_enabled: bool = true
## How many ordinary MEAT chunks still burst alongside the body parts. Deliberately lower than gib_count (the
## chunks-only count) because up to 6 limbs already fly. 0 = a clean, toy-like break-up with no loose gore.
@export var body_part_gib_meat_count: int = 3
## Slowest a body part is flung (m/s) — the low end of the burst speed range. Lower than the meat-chunk range
## on purpose: a whole limb reads better arcing off the body than rocketing across the room.
@export var body_part_gib_vel_min: float = 3.5
## Fastest a body part is flung (m/s) — the high end of the burst speed range. Keep above vel_min.
@export var body_part_gib_vel_max: float = 8.0
## Least extra upward fling (m/s) added to a part so the burst pops UP rather than skidding along the floor — low end of the up-bias range.
@export var body_part_gib_up_bias_min: float = 1.5
## Most extra upward fling (m/s) added to a part — high end of the up-bias range.
@export var body_part_gib_up_bias_max: float = 3.5
## How much the launch direction is randomly jittered off "straight out from the body's centre" (0 = parts fly
## exactly outward from where they sat, so the body opens up like a flower; 1 = fully scattered).
@export_range(0.0, 1.0, 0.05) var body_part_gib_spread: float = 0.35
## Max random tumble (rad/s per axis) spun onto each part as it launches — bigger = wilder cartwheeling limbs.
@export var body_part_gib_angular_range: float = 10.0
## Fraction of the killing blow's knockback (the victim's velocity + explosion_velocity) the parts inherit, so
## a rocket blows the body apart DOWNRANGE instead of straight up. 0 = ignore how it died; 1 = full inherit.
@export_range(0.0, 2.0, 0.05) var body_part_gib_launch_inherit: float = 0.6
## Fewest shots it takes to pop a flying body part — the low end of its random HP. Above the meat-chunk range:
## a limb should survive a stray round and be shootable out of the air on purpose.
@export var body_part_gib_hp_min: int = 2
## Most shots it takes to pop a flying body part — the high end of its random HP.
@export var body_part_gib_hp_max: int = 4
## Mass (kg) of a flying body part. Heavier than a meat chunk so limbs land and stay put instead of skittering.
@export var body_part_gib_mass: float = 0.9
## Seconds a body part lingers before it begins fading out. Longer than gib_lifetime on purpose — the pieces of
## the guy you just killed are worth leaving on the floor.
@export var body_part_gib_lifetime: float = 20.0
## Seconds a body part takes to fade out once its lifetime expires.
@export var body_part_gib_fade_time: float = 1.5

@export_group("Pinned body parts")
## Master switch for the PIN kill: a THROWN WEAPON that lands the killing blow carries the body part it struck
## into the wall behind and staples it there, blade still through it, while the rest of the body slumps. Needs
## body-part gibs (it re-routes ONE of the limbs that already fly) and a wall behind the victim — with no
## surface in range the death falls back to the ordinary burst, silently. Off = every kill bursts as before.
@export var pinned_parts_enabled: bool = true
## Pin a HEAD hit. The best-reading part by a distance — a head is a big solid blob at eye height, and the
## silhouette is unmistakable across a room.
@export var pinned_part_head: bool = true
## Pin a TORSO hit. The other one that reads: the biggest part, and where most thrown hits land.
@export var pinned_part_torso: bool = true
## Pin an ARM hit. OFF by default and worth leaving off: at this game's internal resolution an arm on a wall is
## a few pixels wide, and with the PS1 vertex snap on top it reads as a mesh poking through the geometry rather
## than a trophy. Turn it on if you want every hit to pin.
@export var pinned_part_arms: bool = false
## Pin a LEG hit. OFF by default for the same reason as arms, though a leg is the chunkier of the two.
@export var pinned_part_legs: bool = false
## How far past the victim (metres, along the throw) to look for something to staple to. Nothing solid within
## this range = no pin, and the death plays as a normal burst. Bigger = the trick fires in more rooms; too big
## and a limb flies implausibly far to reach the back wall.
@export var pinned_part_probe_distance: float = 3.5
## Which physics layers count as a surface worth pinning to. Layer 1 (the world / static geometry) is the
## intent; adding more lets a limb staple to props or other actors, which nothing here follows if they move.
@export_flags_3d_physics var pinned_part_probe_mask: int = 1
## How far off straight-on (degrees) the surface may face and still take the staple. This rejects a GRAZE — a
## downward throw catching the floor — because a limb lying flat on the ground is what an ordinary gib that
## failed to bounce already looks like, so pinning there reads as a bug, not a trick shot. 90 accepts anything.
@export_range(0.0, 90.0, 1.0) var pinned_part_max_surface_angle: float = 55.0
## Speed (m/s) the struck limb flies to the wall at. It travels in a STRAIGHT line with gravity off, so this is
## purely how long the flight reads for — the whole point is that the player SEES it carried there rather than
## finding it already stuck. Too fast and there is no flight to see; too slow and it floats.
@export var pinned_part_flight_speed: float = 16.0
## How far the limb sinks into the surface, as a fraction of its OWN half-depth (not metres — a head and a
## forearm are different sizes and the same absolute sink would swallow one and barely mark the other).
## 0 = resting against the wall; 1 = half the limb inside it.
@export_range(0.0, 1.0, 0.05) var pinned_part_bury: float = 0.35
## How far (metres) the blade's TIP ends up inside the surface. Only has to be enough that the knife reads as
## driven in rather than balanced on the limb.
@export var pinned_part_blade_embed: float = 0.1
## Seconds the limb stays stapled before it comes off the wall. Longer than body_part_gib_lifetime on purpose:
## this one is the trophy, and it is also what eventually hands the player's knife back if they never fetch it.
@export var pinned_part_lifetime: float = 30.0
## Seconds the limb tumbles on the ground after it drops off the wall, before it fades out (the fade itself
## reuses body_part_gib_fade_time). The "it slid down the wall eventually" beat — 0 fades it the moment it falls.
@export var pinned_part_drop_linger: float = 3.0
## Multiplier on how hard the OTHER body parts are flung on a pin kill. The pin only reads if it is the one
## thing happening: at the normal 1.0 the wall gets its limb inside a cloud of five more, and nobody sees which
## one behaved differently. Low values make the rest of the body crumple in place instead. 1.0 = no quieting.
@export_range(0.0, 1.0, 0.05) var pinned_part_burst_speed_scale: float = 0.2
## How many MEAT chunks a pin kill sprays, instead of body_part_gib_meat_count. Same reason as the speed scale
## above — loose gore competes with the thing you want looked at. -1 inherits body_part_gib_meat_count.
@export var pinned_part_meat_count: int = 0

@export_group("Thrown weapon trail")
## Master switch for the white STREAK a thrown weapon drags behind it in flight — the thrown-weapon tracer.
## Off = thrown props fly bare, as they did before the effect existed. Only props carrying a `ThrowTrail`
## child are involved at all (a weapon drop gets one from `WeaponData.thrown_trail`, which is ON for EVERY
## weapon by default — knife, guns and all), so this is the global kill switch for that whole family, not a
## per-prop toggle.
@export var throw_trail_enabled: bool = true
## Ribbon width (metres) at the head — the end still attached to the prop, where the streak is widest before
## it tapers to a point behind. Sized for a KNIFE and deliberately left there when the streak went game-wide:
## wide enough to read across a room at this game's internal resolution, narrow enough that it stays a streak of
## light rather than a flag — and a width that reads as a tracer on a blade does NOT want scaling up for a
## shotgun, because the ribbon is a light source, not a silhouette. A prop can override it with its own
## `ThrowTrail.width`.
@export var throw_trail_width: float = 0.05
## Distance (metres) at which the streak is drawn at exactly `throw_trail_width`. Past it the ribbon is widened
## in proportion, so a knife thrown down a long street still reads as a line instead of thinning to a flickering
## sub-pixel dotted trail — the same perspective compensation, and the same never-thinner-than-authored clamp,
## that `tracer_reference_dist` gives bullet tracers. Closer than this nothing changes. Bigger = distant streaks
## stay thinner (and eventually break up); smaller = they fatten sooner.
@export var throw_trail_reference_dist: float = 6.0
## Seconds a point of streak lingers before it fades out — the tail's length in TIME, not in metres, so a
## harder throw automatically draws a longer streak. Long values turn the tracer into a lingering rope that
## marks where the knife has been; short ones read as a glint on the blade.
@export var throw_trail_lifetime: float = 0.22
## Speed (m/s) a prop must be moving to keep laying new streak — a FLOOR, so faster is what streaks. This is
## what ends the effect on landing (the tail then ages out over `throw_trail_lifetime`), and what keeps a slow
## lob or a bounced knife rolling across the floor from scribbling.
## KEEP THIS UNDER `PhysicsDamageSettings.pickup_throw_impulse` (12 m/s — the speed an ORDINARY throw leaves
## the hand at). Above it the streak silently reverts to knife-only: the knife's 2.5x `thrown_impulse_mult` puts
## it at ~30 m/s and clears any plausible floor, while every gun — which throws at the flat 12 — would draw
## nothing at all, and a designer retuning this knob would have no way to tell the effect had half broken. That
## ordering is pinned by `tests/test_managers_tuning.gd`. (Clearing the floor at RELEASE is enough for the whole
## arc: a thrown prop tends to speed UP, since gravity adds vertical speed while the horizontal component barely
## decays — which is also why the streak never gaps mid-flight.)
@export var throw_trail_min_speed: float = 7.0
## Cap on live samples per streak — the effect's whole cost, since the ribbon is 2 vertices per sample and is
## rebuilt every physics frame. Reached only when the lifetime is long enough to hold more than this many
## ticks (at 60 Hz, 24 samples ≈ 0.4 s of flight), after which the tail stops growing rather than the streak
## breaking.
@export_range(2, 128, 1) var throw_trail_max_points: int = 24

@export_group("Death freeze")
## Seconds an enemy holds its pose — frozen in place — after the killing blow BEFORE it bursts into gore (the
## gib + ragdoll "explosion"). A short beat that makes a kill read as a punchy freeze-then-pop instead of an
## instant vanish. NPCs only (the player death is its own sequence); a per-archetype opt-out lives on
## NpcData.freeze_on_death. 0 disables it entirely (the body gores immediately, the pre-freeze behaviour).
## Suppressed in headless/tests via GameSettings.allow_timescale_changes, like the other death "juice".
@export var death_freeze_duration: float = 0.15

@export_group("Blood drops (world)")
## How many physics blood drops a bloody-mess death bursts into (spread over a few frames).
@export var blood_drop_count: int = 24
## Drops spawned per frame while the burst empties — caps the per-frame spawn spike.
@export var blood_drop_per_frame: int = 8
## How many blood drops a destroyed gib flings (the confetti-pop bleed).
@export var gib_destroy_drops: int = 3
## How wide (metres) wound droplets scatter from the hit point — bigger = a messier spray cone.
@export var blood_drop_scatter: float = 1.8
## Slowest a wound droplet flies (m/s) — the low end of the random launch speed.
@export var blood_drop_vel_min: float = 3.0
## Fastest a wound droplet flies (m/s) — the high end of the random launch speed. Keep above vel_min.
@export var blood_drop_vel_max: float = 9.0
## Seconds the blood DECAL a landed drop leaves takes to grow to full size — higher = a slower bloom-in of the splat on the surface.
@export var blood_decal_grow_time: float = 0.4
## Seconds a landed blood decal stays at full before it begins fading out — higher = blood lingers longer on the world surface.
@export var blood_decal_fadeout_delay: float = 4.0

@export_group("Explosion (visual)")
## How fast the explosion light scales up to full size (higher = a snappier flash bloom).
@export var explosion_light_grow_speed: float = 8.0
## Flicker frequency of the explosion flash mesh — how fast its brightness pulses (higher = a faster, more frantic flash).
@export var explosion_flash_speed: float = 20.0
## Radius (metres) of the small spark/paint burst used for hit sparks and paint splats — the mini-explosion size.
@export var explosion_spark_radius: float = 0.3
## Floor (metres) on the explosion flash-light radius so even a small blast lights the area noticeably.
@export var explosion_min_flash_radius: float = 4.0
## Flash-light brightness per metre of flash radius — scales the omni light's energy with blast size (bigger blast = brighter flash).
@export var explosion_flash_energy_per_radius: float = 4.0

@export_group("Sky FX")
## Colour the whole sky pops to when the player kills an NPC — StarSky.flash_kill writes it onto the horizon
## shader's `flash_color` uniform every kill, so it is live-tunable in the Remote inspector while playing.
## Ships RED. At sky_flash_peak = 1 the sky becomes SOLID this colour, so choose it for the silhouette read
## (buildings/wires against a flat field) rather than for subtlety. Alpha is ignored (the uniform is a vec3).
## Deliberately a HOTTER, brighter red than sky_hurt_color's darker blood red: both cues are red now, so what
## keeps them apart is the SHAPE (this one goes solid and holds ~1 s; the hurt wash is partial and half as long)
## plus that brightness gap. Shift one of the two if you ever want them to read as different colours again.
@export var sky_flash_color: Color = Color(1.0, 0.1, 0.08)
## How far the flash pushes the sky TOWARD sky_flash_color at its peak: 1 = solid sky_flash_color (the shipped
## Hotline-Miami pop), lower = the authored sky tinted that far. Clamped 0..1 at the read site.
@export_range(0.0, 1.0, 0.01) var sky_flash_peak: float = 1.0
## Seconds the on-kill sky flash snaps UP to the peak (StarSky.flash_kill — the Hotline-Miami whole-sky pop).
@export var sky_flash_up_time: float = 0.06
## Seconds the flash SUSTAINS the peak before fading. Without a hold the pop is only a RAMP through the colour and
## reads as a brightness blip, not as "the sky went red" — same reason the per-part hit flash sustains.
@export var sky_flash_hold_time: float = 0.3
## Seconds the on-kill sky flash fades back out. up + hold + down is the WHOLE beat the player sees, and the
## shipped 0.06 + 0.3 + 0.64 is deliberately ~1.0 s — retune all three together if you want a different length.
@export var sky_flash_down_time: float = 0.64
## Colour the sky washes to when the PLAYER TAKES DAMAGE — StarSky.flash_hurt writes it onto the horizon shader's
## `hurt_flash_color` uniform on every hit. Ships the SAME red as the screen-space hurt flash
## (PlayerFeedbackSettings.hurt_flash_color) so the two read as one cue rather than two different alarms.
## Darker than the kill flash's hot red on purpose — see sky_flash_color for how the two red cues stay apart.
@export var sky_hurt_color: Color = Color(0.85, 0.0, 0.0)
## How far the hurt wash pushes the sky TOWARD sky_hurt_color at its peak. Ships PARTIAL, unlike the kill flash's
## solid 1.0, and that asymmetry is the point: you take damage far more often than you kill, so a solid red sky
## would sit through a whole firefight, blind the player, and smear into the kill flash it must stay distinct from.
## Raise to 1.0 only if you want being shot to black out the skyline as hard as a kill does.
@export_range(0.0, 1.0, 0.01) var sky_hurt_peak: float = 0.55
## Seconds the hurt wash snaps UP to the peak. Fast — a damage cue that ramps in reads as ambience, not as a hit.
@export var sky_hurt_up_time: float = 0.04
## Seconds the hurt wash SUSTAINS the peak. Short: enough to register as red rather than as a brightness blip,
## without holding the sky red under sustained fire (each new hit restarts the beat, so a burst already holds it).
@export var sky_hurt_hold_time: float = 0.06
## Seconds the hurt wash fades back out. up + hold + down is the whole beat (ships ~0.45 s: 0.04 + 0.06 + 0.35),
## deliberately under half the kill flash's second. Retune all three together.
@export var sky_hurt_down_time: float = 0.35
## Dim, cool-blue fixed ambient StarSky pins over the level so the bright horizon sky never washes the scene white (warmer/brighter to taste).
@export var sky_ambient_fill: Color = Color(0.05, 0.07, 0.13)

@export_group("Hit flash (per-part)")
## Additive strength the per-part hit flash drives flash_strength to at its peak (Character.flash_red / the NPC located-hit flash).
@export var hit_flash_peak_strength: float = 10.0
## Seconds the hit flash snaps UP to the peak.
@export var hit_flash_up_time: float = 0.03
## Seconds the hit flash SUSTAINS the peak, so it reads as a strong hit and not a 1-frame blip.
@export var hit_flash_hold_time: float = 0.12
## Seconds the hit flash fades back out (slower, so it lingers).
@export var hit_flash_down_time: float = 0.3

@export_group("Damage Numbers")
## The floating world-space number a player hit pops off an enemy (DamageNumberPopup — the combat
## callers pass the post-mitigation HP loss, so it shows what the enemy actually lost). The popup's
## const bank stays as the shipped baseline + GUT anchors; every field below DEFAULTS to its const,
## so the feel is byte-identical until tuned here (test_damage_number_popup.gd pins the mirror). The
## show-at-all threshold (MIN_LOSS) and the draw order (RENDER_PRIORITY) deliberately STAY consts on
## the popup — gameplay policy and a render contract, not feel.
## Metres above the impact point the number spawns, so it clears the wound instead of starting inside it.
@export var damage_number_hit_offset_y: float = 0.25
## Fallback spawn height (metres above the victim's origin) when the hit has no finite impact point.
@export var damage_number_body_offset_y: float = 1.35
## Metres the number floats UP over its lifetime — the classic rising-damage read.
@export var damage_number_rise: float = 0.75
## Horizontal random drift (± metres on X and Z) so rapid hits don't overprint into one blob.
@export var damage_number_spread: float = 0.18
## Seconds the number lives — the whole rise + shrink + fade plays inside this window.
@export var damage_number_lifetime: float = 0.65
## Label3D font size of the number; with pixel_size below this sets its world footprint.
@export var damage_number_font_size: int = 48
## World metres per font pixel (Label3D.pixel_size) — the other half of the number's world footprint.
@export var damage_number_pixel_size: float = 0.004
## Outline thickness (font pixels) — the dark rim that keeps the number readable over any backdrop.
@export var damage_number_outline_size: int = 20
## Scale a CRIT number pops in at (>1 = crits land visibly bigger before settling toward end_scale).
@export var damage_number_start_scale: float = 1.12
## Scale every number shrinks to as it fades — the recede that sells "drifting away".
@export var damage_number_end_scale: float = 0.88
## Hot orange-red an ordinary hit's number wears.
@export var damage_number_body_color: Color = Color(1.0, 0.33, 0.2, 1.0)
## Bright yellow a CRIT's number wears instead — the payoff colour.
@export var damage_number_crit_color: Color = Color(1.0, 0.92, 0.22, 1.0)
## The number's outline tint (semi-opaque black rim).
@export var damage_number_outline_color: Color = Color(0.0, 0.0, 0.0, 0.78)

@export_group("Muzzle & Impact FX")
## World-space radius (metres) of the spray-can muzzle flash — kept tiny because it sits right at the camera (the impact-spark radius would read as screen-filling up close).
@export var muzzle_flash_radius: float = 0.06
## How far (metres) the bullet-impact spark / overkill burst is pulled back along the hit direction so it sits proud of the surface instead of inside it.
@export var hit_spark_backoff: float = 0.4
## Maps impact SPEED to the hit spark's grow-in scale (passed to the burst's speed_to_scale) — higher = a faster shot blooms a bigger spark.
@export var hit_spark_speed_to_scale: float = 32.0
## Radius (metres) of the overkill-penetration burst — bigger than the ordinary spark so a shot punching THROUGH an enemy into the next reads clearly.
@export var overkill_burst_radius: float = 0.9
## Opacity of ONE smoke puff (MuzzleSmoke), 0..1. The puffs are meant to read INDIVIDUALLY — a small cartoon
## cluster, not a haze — so this is high and the particle count is low, and the two must move together.
## ⭐Every failure mode here was photographed before these numbers were picked (the harness is
## scripts/tools/muzzle_smoke_qa_shots.gd): hundreds of near-transparent puffs fuse into a realistic
## connected haze, a few hundred at middling alpha saturate into a featureless solid-white ball, and a
## handful at low alpha vanish entirely. Multiplies the per-particle fade the colour ramp already does, so
## it is "how solid is one puff", never "when does it fade". Everything else about the look — the disc-with-
## a-rim falloff on resources/materials/muzzle_smoke.tres, the growth curve, the buoyancy and the curl —
## is authored in the Inspector on that material and scenes/effects/muzzle_smoke.tscn.
@export_range(0.0, 1.0, 0.01) var muzzle_smoke_alpha: float = 0.42
## How long (seconds) the stream takes to SWELL IN when it starts. Emission eases up from nothing across this
## window instead of snapping to full flow, so the smoke wells up out of the barrel rather than a whole cluster
## of puffs popping into existence in one frame. This is the other half of making the smoke its own beat: the
## delay separates it from the flash, this stops the separation reading as a hard pop. 0 restores the snap.
@export var muzzle_smoke_attack: float = 0.14
## How long (seconds) the stream takes to PETER OUT at the end of the hold. Emission eases to nothing across
## this window (via the emitter's amount_ratio) instead of being cut at full flow, which reads as the smoke
## being switched off mid-puff. Longer = a lazier, more gradual die-away. 0 restores the hard cut.
@export var muzzle_smoke_taper: float = 0.25
## The beat between the BANG and the smoke, in seconds. A round is long gone before a barrel smokes, so smoke
## that blooms on the same frame as the muzzle flash reads as part of the flash — the two events fuse and the
## shot loses its punch. This is what separates them. 0 restores the old same-frame behaviour; much above ~0.3
## and the smoke stops feeling caused by the shot at all. The hold below is NOT ticked during this window, so
## it always means "this long of actual smoke" however the delay is tuned.
@export var muzzle_smoke_delay: float = 0.05
## How long (seconds) the barrel keeps STREAMING smoke after a shot. Each shot re-arms this window rather
## than restarting the emitter, so a full-auto burst makes ONE continuous trail that keeps going this long
## after the last round. Longer = a heavier, more persistent trail; ~0.1 gives a quick single wisp per shot.
@export var muzzle_smoke_hold: float = 0.5

@export_group("View-Model Kick (per shot / per swing)")
## The whole view model's KICK when you attack — GunMesh.fire() tweens the rig out to these and back, and any
## mounted weapon mesh rides along. Z is Camera3D-local: +Z is BACK toward the player (recoil), -Z is FORWARD
## toward the crosshair. These four are a GUN's recoil and are the defaults every weapon gets.
## Local offset (metres) the rig kicks to on a shot. Positive Z = the gun drives back into your shoulder.
@export var view_model_kick_position: Vector3 = Vector3(0.0, 0.1, 0.4)
## Rotation offset (degrees) at the peak of the kick — negative X pitches the muzzle up.
@export var view_model_kick_rotation: Vector3 = Vector3(-5.0, 0.0, 0.0)
## Seconds to reach the kick (the snap).
@export var view_model_kick_in_time: float = 0.05
## Seconds to settle back to rest (the recovery).
@export var view_model_kick_out_time: float = 0.1
## The same four for a weapon whose WeaponData sets `view_model_punch` — a PUNCH, which must extend AWAY from
## you rather than recoil into you, or the rig slides backwards while the arm thrusts forward and the whole
## swing reads mushy. Note the NEGATIVE Z.
@export var punch_kick_position: Vector3 = Vector3(0.0, 0.01, -0.1)
## Rotation offset (degrees) at full extension — a slight downward pitch as the shoulder drops into the punch.
@export var punch_kick_rotation: Vector3 = Vector3(3.0, 0.0, 0.0)
## Seconds to full extension. Slightly slower than a gun's snap so the arm reads as thrown, not fired.
@export var punch_kick_in_time: float = 0.06
## Seconds to draw the fist back to guard.
@export var punch_kick_out_time: float = 0.2

@export_group("Gun Holster (view model)")
## Seconds to swing the view-model gun down (holster) / up (draw) — higher = a slower, more deliberate put-away/draw.
@export var gun_holster_animation_time: float = 0.35
## Lowered, off-screen rest OFFSET (local metres) the gun parks at while holstered — pushed down/back out of view.
@export var gun_holster_position_offset: Vector3 = Vector3(0.0, -1.4, 0.2)
## Rotation OFFSET (degrees) the gun tilts to while holstered — barrel pitched down as it's put away.
@export var gun_holster_rotation_offset: Vector3 = Vector3(-70.0, 0.0, 0.0)

@export_group("Gun Reload & Landing (view model)")
## The remaining GunMesh one-shot pose tweens (fire and holster already read this resource): the
## reload/swap "hands are busy" dip, the post-reload raise, and the touchdown dip. Same convention as
## the kick group — offsets are Camera3D-local metres/degrees added on top of the rest pose.
## Local offset (metres) the whole view model drops to while a reload/swap plays — down and back,
## out of the player's face (GunMesh.reload()).
@export var gun_reload_dip_position: Vector3 = Vector3(0.0, -0.9, 0.4)
## Rotation offset (degrees) during the reload dip — negative X pitches the barrel down as it drops.
@export var gun_reload_dip_rotation: Vector3 = Vector3(-25.0, 0.0, 0.0)
## Seconds to swing down into the reload dip.
@export var gun_reload_dip_time: float = 0.5
## Seconds the gun takes to raise back to ready after a reload/swap finishes. COUPLED to the laser
## sight: GunMesh derives its is_raised() gate window from THIS field (int(t * 1000), the same
## derivation unholster() uses), so the laser appears exactly when the gun settles — one knob moves
## both. GunMesh.GUN_RAISE_MS (= this × 1000) stays as the const baseline + test anchor; keep the
## default matching it (test_effects.gd asserts the pair).
@export var gun_raise_time: float = 0.5
## How far the gun dips DOWN (metres, negative) on a full-strength landing — scaled by the same
## impact value the camera dip uses, so heavier falls dip the gun further (GunMesh.land()).
@export var gun_land_dip: float = -0.08
## Barrel pitch (degrees, at full impact) as the gun "absorbs" the landing — also intensity-scaled.
@export var gun_land_pitch: float = 4.0
## Seconds to sink into the landing dip (the absorb).
@export var gun_land_in_time: float = 0.08
## Seconds to recover back to rest afterward — slower than the sink so the settle reads soft.
@export var gun_land_out_time: float = 0.18

@export_group("World ghost")
# Temporal persistence over the whole PICTURE (scripts/effects/world_ghost.gd) — the HUD's phosphor ghost
# extended, very faintly, to the world behind it. A never-cleared offscreen buffer keeps a running average
# of the finished frame and a full-rect shader adds the DIFFERENCE between that average and the live frame
# back over the picture, so the effect exists only where something moved: at rest the average has converged
# on the frame, the difference is zero, and the composite re-emits the picture unchanged. The view model is
# masked out per pixel, and menus / dialogue / cutscenes switch the whole pass off. The player scales it
# 0..1 via Options -> Accessibility -> "World Ghosting" (Settings.world_ghost_scale).
## How much of the lag is added back over the picture, 0..1 — the master amplitude, and the one knob that
## decides whether this reads as "a faint memory of the frame" or as motion blur. 0 stops the pass
## rendering entirely (OFF is free and the frame is bit-identical). Keep it LOW: this is a full-screen
## effect over a game that is already posterised and dithered, and past ~0.25 it stops being a ghost and
## starts being smear on every wall you walk past.
@export_range(0.0, 1.0, 0.01) var world_ghost_strength: float = 0.12
## Persistence time constant (seconds): the average closes 1/e of the gap to the live frame every tau, so
## the trail is the same LENGTH at 30 fps and at 144. Short on purpose — the world fills the screen, so a
## tail that would read as elegant on a 4 px HUD segment reads as drunk when it is the whole picture.
@export_range(0.0, 0.5, 0.005) var world_ghost_tau: float = 0.055
## Per-channel difference below which the trail is clipped to nothing. A never-cleared 8-bit buffer chasing
## a target stalls a few steps short of it (round-to-nearest), so the difference never quite reaches zero
## and a still frame would carry a permanent sub-percent haze. ~0.01 (about 2.5/255) is the smallest value
## that reliably clears that stall; raising it shortens the tail's faint end, lowering it lets the haze back.
@export_range(0.0, 0.2, 0.002) var world_ghost_dead_zone: float = 0.01
## Pixels of CHROMATIC SPLIT on the trail at full look rate: the accumulator's red and blue are sampled
## either side of green along the direction the view is moving, so a moving edge fringes the way an analog
## signal does instead of just blurring. This is what keeps the world's ghost in the same family as the
## HUD's coloured one without painting the world. 0 = a clean achromatic trail.
@export_range(0.0, 6.0, 0.1) var world_ghost_chroma_px: float = 0.8
## Px of that split per rad/s of camera look rate (x = yaw, y = pitch), before the cap above. Sized so an
## ordinary look reaches roughly half the cap and only a hard flick pins it.
@export var world_ghost_chroma_gain: Vector2 = Vector2(0.45, 0.36)
