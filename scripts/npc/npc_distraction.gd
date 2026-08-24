class_name NpcDistraction
extends Node

## The idle-brain DISTRACTION / UNAWARE reaction bodies, split off npc.gd: the no-target environmental sensing
## (react_unaware), the shared throttled noise/corpse scan (scan_distractions), the has-target-while-UNAWARE feeler
## (react_distraction, P0-4), the passive music reaction (react_music), and the corpse-discovery reaction
## (discover_corpse). npc.gd keeps a 1-line null-guarded facade per entry point (_react_unaware /
## _scan_distractions / _react_distraction / _react_music) so every _physics_process call site — and its ORDER —
## is unchanged: react_unaware runs BEFORE the no-target _executor.tick (the executor reads the Perception state
## it sets/decays), react_distraction / react_music run AFTER the tick (the face overrides the idle facing). See
## npc.gd's header @risk lines; the facades must never shift position in either branch.
##
## STATE SPLIT (the load-bearing part): only the scan throttles + the once-per-attend music-comment latch live
## HERE (_distraction_scan_t / _music_scan_t / _music_commented_radio — reset by our own reset_for_reuse in the
## pool cascade). Everything else these bodies touch is cross-consumed and stays HOST-owned, written through
## `host`: _alerted_allies (the GA-1 latch _settle_engagement_barks also clears), _was_distracted (the has-target
## branch clears it), _scripted_investigating (armed by NPC.investigate()), _attending_radio (the head-look's
## lowest-priority target), and _desired_velocity (the sole locomotion intent). Bare-NPC unit tests poke those
## host fields directly, so they must not migrate here.
##
## `host` is typed Node (not NPC) to break the NpcDistraction <-> NPC class cycle (NPC creates this), so every
## host.X is a dynamic call resolved at runtime — a rename of one of those npc.gd members fails at RUNTIME, not
## compile (see scripts/npc/README.md, this component's row). Built in NPC._build_components BY SCRIPT PATH
## (never the bare class_name — npc.gd is a @tool root, and naming a not-yet-reimported class_name can fail its
## parse in the live editor; the CrippleCallout / NpcHomeReturn idiom). The pure SCAN primitives these bodies
## consume stay on NpcSenses, reached via the host's _loudest_noise / _nearest_audible_radio /
## _nearest_visible_corpse facades.

## Music-quality tiering for the radio comment. preload (not the bare class_name) so the suite resolves it before
## the editor scans the script — mirrors the NPC.MQ const (which stays on the host for _music_lines / the tests).
const MQ = preload("res://scripts/components/music_quality.gd")

var host: Node = null  ## the NPC we sense for (Node-typed to avoid the class cycle; bound by NPC._build_components)

var _music_commented_radio: Node3D = null  ## the radio we last commented on, so the bark fires once per attend
var _music_scan_t: float = 0.0             ## throttle for the &"music" scan (paced like the distraction scan)
var _distraction_scan_t: float = 0.0  ## throttles the noise/corpse group scans — shared by react_unaware (no-target) AND react_distraction (has-target while UNAWARE), both via scan_distractions (GameSettings.npc_ai.distraction_scan_interval)

## NPC-pooling reuse reset (NpcPool): zero the scan throttles and drop the once-per-attend comment latch, or a
## reused body inherits a mid-window throttle AND — worse — a stale _music_commented_radio that silently swallows
## the same-radio music comment for its whole next life. Called from NPC.reset_for_reuse's child cascade; the
## host-owned latches these bodies write (_was_distracted / _scripted_investigating / _attending_radio /
## _alerted_allies) are reset by the host itself, beside its other per-life fields.
func reset_for_reuse() -> void:
	_music_commented_radio = null
	_music_scan_t = 0.0
	_distraction_scan_t = 0.0


## No-enemy environmental SENSING (the stealth distraction + body-discovery feeler): with NO acquired target,
## scan the &"noise" channel (if hearing_initiates) and bodies (if body_discovery) and, on a stimulus, point
## Perception at it (-> INVESTIGATING) + age/expire the give-up clock. It does NOT walk: the GOAP executor's
## Investigate action drives the move+search off the INVESTIGATING state this sets, so stealth investigation is a
## planner decision. When NO sensing applies (both features off, or we're
## dead / fleeing / a follower / have no Perception) it FORGETs any stale alert from a just-lost target, so the
## no-target executor picks the Hold idle floor rather than a targetless combat action. In-tree (group scans +
## LOS) -> playtest-verified; the pure gates (Corpse.noticeable, NoiseSource.audible) carry the unit tests.
func react_unaware(delta: float) -> void:
	host._alerted_allies = false  # GA-1: no acquired target here -> any engagement is over, so re-arm the ally broadcast
	var noise_on: bool = host._noise_initiates_on() and host._perception != null and host._perception.hearing
	var corpse_on: bool = host._body_discovery_on() and host._perception != null
	if host._perception == null or host._dead or host.hp <= 0.0 or host.is_fleeing() or host.is_following() or (not noise_on and not corpse_on):
		# No ambient sensing. A SCRIPTED investigate() (NPC.investigate()) winds down naturally over forget_time —
		# sense() with no target only decays the clock while the executor walks/searches the spot. Any OTHER
		# leftover (a stale ALERTED from a just-lost target) is a phantom: clear it instantly so the no-target
		# executor selects the Hold idle floor, not a targetless combat action.
		if host._perception != null:
			# Wind an alert DOWN naturally (ALERTED coasts the pursuit grace, then INVESTIGATING drains over forget_time)
			# instead of HARD-forgetting it, for two cases: a scripted investigation, AND a FLEEING NPC. A fleer that
			# hard-forgets the frame it loses its attacker (attacker out of sight_range, or simply behind the running NPC)
			# drops to UNAWARE, which makes its Survive/Flee goal infeasible — so it stops dead and strolls calmly back
			# past its would-be killer. Decaying keeps it scared while it runs, then calms over forget_time (raise the
			# NPC's forget_time to make fear last longer). A non-fleeing, non-scripted leftover still hard-forgets below.
			var decay_not_forget: bool = (host._scripted_investigating and host._perception.state == Perception.State.INVESTIGATING) \
					or (host.is_fleeing() and host._perception.state != Perception.State.UNAWARE)
			if decay_not_forget:
				host._perception.is_hostile = false
				host._perception.sense(delta)
				if host._perception.state != Perception.State.INVESTIGATING:
					host._scripted_investigating = false
			else:
				host._scripted_investigating = false
				host._perception.forget()
		return
	# Age the give-up clock EVERY frame: sense() with no target reports nothing from either sense, so it only
	# winds an in-progress investigation down toward UNAWARE (a brand-new or refreshed one stays put below); it
	# also decays a stale alert from a just-lost target the same way (so it can't linger as a phantom combat state).
	host._perception.is_hostile = false
	host._perception.sense(delta)
	# (Re)point the investigation at the strongest LIVE stimulus (throttled scan). Shared with the has-target
	# branch via react_distraction so a decoy/body registers while a hostile holds the player as a proximity
	# target but hasn't actually noticed them (UNAWARE) — see scan_distractions / react_distraction (P0-4).
	scan_distractions(delta, noise_on, corpse_on)
	# Investigating now -> the executor's GoapActionSearch walks + searches off last_known_position (same
	# move it always did); we only keep the give-up bookkeeping so we mutter "must've been nothing" on expiry.
	if host._perception.state == Perception.State.INVESTIGATING:
		host._was_distracted = true
		host._try_search_bark()  # mutter "where are you?" while hunting (the bark cooldown paces it)
	elif host._was_distracted:
		host._was_distracted = false
		host._try_lost_interest_bark()  # the investigation just expired with nothing found


## The throttled &"noise"/body-discovery scan: (re)point Perception at the strongest LIVE stimulus. Noise first (an
## ongoing sound outranks a static body); a heard source re-points each scan it persists (investigate_point refreshes
## the clock) so we track a moving decoy. Shared by react_unaware (no-target) and react_distraction (has-target,
## UNAWARE) so a thrown decoy / hidden body registers in BOTH branches. Assumes host._perception != null (both
## callers gate).
func scan_distractions(delta: float, noise_on: bool, corpse_on: bool) -> void:
	_distraction_scan_t -= delta
	if _distraction_scan_t <= 0.0:
		_distraction_scan_t = GameSettings.npc_ai.distraction_scan_interval
		if noise_on:
			var src: NoiseSource = host._loudest_noise()
			if src != null:
				# alerting "!" — the player wants to see the lure land; seed the search ring from how LOUD it was
				# (a crash searches a wider area than a faint step), scaled by SearchSettings.noise_radius_scale.
				# Hand WHO made the noise along (NoiseSource.emitter: the Player for its own steps/shots, an NPC for
				# its gunfire pulse, null for a decoy) so the "!" handler can tell "I heard YOU" (2D sting) from "I
				# heard a can rattle" (positional) — it must not read that off host._target, a mere proximity lock.
				# Sanitized: a one-shot source can outlive its emitter, and a typed Node param rejects a freed handle.
				var who: Node = src.emitter if is_instance_valid(src.emitter) else null
				host._perception.investigate_point(src.global_position, true, src.radius * GameSettings.search.noise_radius_scale, NAN, who)
		# Corpse discovery is PERSISTED (discover_corpse -> GameState.mark_corpse_discovered) — so gate it on a
		# GENUINELY idle NPC (UNAWARE), not merely "not INVESTIGATING": a stale DETECTING/ALERTED beat from a
		# just-lost target must NOT permanently mark a body discovered with zero real investigation. sense() (called
		# by both callers this frame) decays that stale state toward UNAWARE, so discovery is DEFERRED (not lost)
		# until the NPC truly stands down. Noise (above) also outranks a body: if it set INVESTIGATING this scan,
		# state != UNAWARE, so the body waits for the noise to wind down. (C7)
		if host._perception.state == Perception.State.UNAWARE and corpse_on:
			var corpse: Corpse = host._nearest_visible_corpse()
			if corpse != null:
				discover_corpse(corpse)


## Distraction sensing for the HAS-target branch. _acquire_target locks the nearest foe by pure PROXIMITY (no
## LOS/perception gate — NpcTargeting), so a hostile holds the player as _target the instant they enter sight_range
## even while perception-UNAWARE. Without this, thrown decoys and hidden bodies did NOTHING exactly when the player
## was in range (P0-4). Mirrors react_music: self-gates on state == UNAWARE, so a decoy only distracts a not-yet-
## noticing guard (escalating it to INVESTIGATING peels it toward the lure via GoapActionSearch); a foe it's already
## detecting/alerted-on always wins. sense() already ran this frame (has-target branch) — do NOT call it again here.
func react_distraction(delta: float) -> void:
	if host._perception == null or host._dead or host.hp <= 0.0 or host.is_fleeing() or host.is_following():
		return
	if host._perception.state != Perception.State.UNAWARE:
		return
	var noise_on: bool = host._noise_initiates_on() and host._perception.hearing
	var corpse_on: bool = host._body_discovery_on()
	if noise_on or corpse_on:
		scan_distractions(delta, noise_on, corpse_on)


## Passive MUSIC reaction: a calm, idle NPC — friendly OR hostile — that can HEAR a playing radio TURNS TO FACE it
## (a visible "look at the radio" beat) and comments ONCE on the song/playlist quality. Ships ON
## (GameSettings.npc_ai.music_reactions). Called (via the NPC._react_music facade) from BOTH the no-target idle path
## AND the has-target branch (a hostile NPC locks the player as a proximity target the moment it's in sight_range,
## so gating on "no target" would hide the reaction the instant the player walked up); it self-gates on
## host._perception.state == UNAWARE, so it only reacts while genuinely not-yet-noticing, and a foe or noise it's
## chasing always wins (it never abandons its post to walk over — the turn is a stationary body yaw, no locomotion).
## The radio SCAN is throttled like the distraction scan, but the FACE runs EVERY frame off the cached
## host._attending_radio (the head-look's lowest-priority target) so the turn eases smoothly; it yields to an active
## schedule/patrol route (a guard mid-patrol keeps walking, head-tracking only). The bark self-throttles. In-tree only.
## NAME NOTE: host.react_music(tier) is a DIFFERENT method — the NPC-side seam that resolves the tier's line pool
## into NpcVoice.music_comment; this per-frame body calls back into it on the one-shot comment below.
func react_music(delta: float) -> void:
	if not GameSettings.npc_ai.music_reactions or host._dead or host.hp <= 0.0 or host.is_following():
		host._attending_radio = null
		return
	# Only a relaxed NPC enjoys music -- detecting / investigating / alerted all outrank it.
	if host._perception != null and host._perception.state != Perception.State.UNAWARE:
		host._attending_radio = null
		return
	# (Re)scan for the nearest audible radio on the distraction-scan throttle; the FACE below + the one-shot comment
	# run off the cached _attending_radio, so a between-scan frame keeps facing (NO early-return before the turn).
	_music_scan_t -= delta
	if _music_scan_t <= 0.0:
		_music_scan_t = GameSettings.npc_ai.distraction_scan_interval
		var radio: Node3D = host._nearest_audible_radio()
		host._attending_radio = radio
		if radio == null:
			_music_commented_radio = null  # out of range / switched off -> a fresh comment when we next attend one
		elif radio != _music_commented_radio:
			_music_commented_radio = radio
			host.react_music(MQ.tier(str(radio.call(&"quality_text")),
				GameSettings.npc_ai.music_tier_meh, GameSettings.npc_ai.music_tier_good, GameSettings.npc_ai.music_tier_great))
	# Turn the BODY to face the radio we're enjoying and hold still to listen — the visible "look at the radio" the
	# head-look (cone-clamped, so a radio BEHIND us never gets tracked) can't deliver on its own. Runs AFTER the idle
	# executor (so it overrides the wander/post facing) but YIELDS to a directed schedule/patrol route, so attending a
	# radio never freezes a guard mid-patrol. Gated by music_turn_body so a designer can keep the reaction head-only.
	# INTENDED SIDE EFFECT (design-signed-off): Perception inherits the body transform, so its view cone is the body's
	# forward. A HOSTILE posted sentry that turns to face the radio therefore also swings its DETECTION cone off its
	# authored watch spot — a deliberate "distracted by music" stealth opening the player can create by switching on a
	# radio behind a guard. This is NOT a player-awareness telegraph (the turn keys on _attending_radio, a radio, never
	# on the host's _target / the player). The only opt-outs are global: music_turn_body off (all reactions head-only)
	# or music_reactions off (no reactions at all).
	if GameSettings.npc_ai.music_turn_body and is_instance_valid(host._attending_radio) and not host._on_directed_route():
		host._desired_velocity = Vector3.ZERO  # stop roaming — stand and enjoy the song
		host._face_point(host._attending_radio.global_position, delta)


## React to discovering a body: CLAIM it (so the neighbourhood doesn't pile onto one corpse), CALL OUT
## ("Hey — a body!"), and INVESTIGATE the spot QUIETLY. Reached from the no-target distraction pass
## (react_unaware). The bark fires FIRST and the investigate is non-alerting (investigate_point's
## `alerting=false`), so a corpse never mislabels as an enemy "!" sighting and the combat "Enemy spotted!"
## detection bark can't win the bark cooldown and swallow the body line.
func discover_corpse(c: Corpse) -> void:
	c.discovered = true
	GameState.mark_corpse_discovered(c.save_key())
	host._try_check_body_bark()
	# quiet (NOT a fire-ready ALERTED); a body carries no radius of its own, so seed the search from how far the
	# NPC can see (the range it spotted the body at), scaled by SearchSettings.corpse_radius_frac.
	host._perception.investigate_point(c.global_position, false, host._perception.sight_range * GameSettings.search.corpse_radius_frac)
