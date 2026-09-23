extends GutTest

## FALL WARNING — the screen draining to grayscale while you fall (Cyberpunk 2077's fall read).
##
## WHAT IT IS. While the player is airborne and descending, post_process.gdshader's `fall_grey` uniform mixes
## the finished frame toward luminance. The strength is not a stylistic curve: it is the FRACTION OF YOUR
## REMAINING HP the landing would cost, scored by the same fall_damage_min_speed / fall_damage_per_speed that
## Landing.on_land hands to _apply_fall_damage. So 1.0 — a completely grey frame — means "the ground kills you",
## at the HP you have this instant, and the same drop reads greyer when you are already hurt.
##
## WHAT THESE TESTS COVER, and why in these three shapes:
##   1. THE CURVE. Pure statics on FallDamage (the Landing.impact_for / Player.health_regen_rate_for idiom), so
##      the whole mapping is assertable with no Player, no tree and no GPU. This is the part that must not drift
##      from the damage formula, and it is the part that actually can be checked.
##   2. THE DRIVER. An off-tree Player (load().new(), never instantiated, never added to the tree — the
##      test_landing / test_fists_view_model idiom) driven a frame at a time, because the three behaviours worth
##      pinning are stateful: the instant rise, the eased release, and the snap to EXACTLY zero.
##   3. THE SEAMS. What the player PUSHES is driven for real: an off-tree Player handed a ShaderMaterial of the
##      real post_process.gdshader (ShaderMaterial records every set_shader_parameter even on the dummy
##      rasterizer), through a fall, a landing, a conversation and a respawn reset. What the SHADER does with it
##      stays a source pin, because headless NEVER compiles a .gdshader and set_shader_parameter to a uniform that
##      does not exist is SILENTLY DISCARDED. Those pins read the shader with every comment stripped, so a
##      commented-out line cannot keep them green.
##
## Deliberately NOT covered: what it LOOKS like. That is a windowed playtest — jump off something high.

const SHADER_PATH := "res://resources/shaders/post_process.gdshader"
const PLAYER_PATH := "res://scripts/player/player.gd"

## The shipped player's fall-damage profile (character.gd's @export defaults — Player.tscn overrides neither), so
## the numbers below read as the real game rather than as arbitrary fixtures.
const MIN_SPEED := 16.0
const PER_SPEED := 0.5
const FULL_HP := 4.0
## ...which puts the lethal landing at 16 + 4/0.5 = 24 m/s.
const LETHAL_SPEED := 24.0
## The uniform name is the contract between player.gd and the shader; both sides are checked against it below.
const FALL_UNIFORM := "fall_grey"
const DT := 1.0 / 60.0

var _saved_time_scale: float = 1.0
var _saved_dialogue: DialogueResource = null
var _saved_suspended: bool = false
var _saved_grey_max: float = 1.0
var _saved_release_rate: float = 0.0
var _saved_void_lead: float = 0.0


func before_each() -> void:
	_saved_time_scale = Engine.time_scale
	_saved_dialogue = DialogueManager._active
	_saved_suspended = DialogueManager._suspended
	_saved_grey_max = GameSettings.player_feedback.fall_grey_max
	_saved_release_rate = GameSettings.player_feedback.fall_grey_release_rate
	_saved_void_lead = GameSettings.player_feedback.fall_grey_void_lead


func after_each() -> void:
	# _reset_screen_post_process writes Engine.time_scale; the dialogue gate and the feedback knobs are
	# process-global too. Restored here so a failed assert can never leak them into a later file.
	Engine.time_scale = _saved_time_scale
	DialogueManager._active = _saved_dialogue
	DialogueManager._suspended = _saved_suspended
	GameSettings.player_feedback.fall_grey_max = _saved_grey_max
	GameSettings.player_feedback.fall_grey_release_rate = _saved_release_rate
	GameSettings.player_feedback.fall_grey_void_lead = _saved_void_lead
	_saved_dialogue = null


func _read(path: String) -> String:
	var s := FileAccess.get_file_as_string(path)
	assert_false(s.is_empty(), "%s must be readable" % path)
	return s


func _player():
	return load(PLAYER_PATH).new()


## An off-tree Player carrying the shipped fall profile, at full health, mid-fall at `fall_speed` m/s downward.
func _falling_player(fall_speed: float, hp: float = FULL_HP):
	var p = _player()
	p.max_hp = FULL_HP
	p.hp = hp
	p.fall_damage_min_speed = MIN_SPEED
	p.fall_damage_per_speed = PER_SPEED
	p.velocity = Vector3(0.0, -fall_speed, 0.0)
	return p


## Hand an off-tree Player the post-process overlay its @onready would have resolved: a ColorRect carrying a
## ShaderMaterial of the REAL post_process.gdshader. Returns the material so the pushed uniforms can be read back.
func _give_post_rect(p) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	var rect := ColorRect.new()
	rect.material = mat
	autofree(rect)
	p._post_rect = rect
	return mat


## The value the player last pushed into `uniform` on `mat`, or -1.0 when nothing was ever pushed under that name.
func _pushed(mat: ShaderMaterial, uniform: String = FALL_UNIFORM) -> float:
	var v: Variant = mat.get_shader_parameter(uniform)
	return float(v) if (v is float or v is int) else -1.0


## post_process.gdshader with every `//` and `/* */` comment removed, so a pin can only be satisfied by live code.
func _shader_code() -> String:
	var block := RegEx.new()
	block.compile("(?s)/\\*.*?\\*/")
	var line := RegEx.new()
	line.compile("//[^\\n]*")
	return line.sub(block.sub(_read(SHADER_PATH), "", true), "", true)


func _squash(s: String) -> String:
	var ws := RegEx.new()
	ws.compile("\\s+")
	return ws.sub(s, " ", true).strip_edges()


## The whitespace-squashed body of the live `if (<uniform> > 0...) { ... }` pass in `code`, or "" when there is none.
func _gated_pass(code: String, uniform: String) -> String:
	var gate := RegEx.new()
	gate.compile("if\\s*\\(\\s*" + uniform + "\\s*>\\s*0(\\.0)?\\s*\\)\\s*\\{")
	var m := gate.search(code)
	if m == null:
		return ""
	var depth := 1
	for i in range(m.get_end(), code.length()):
		if code[i] == "{":
			depth += 1
		elif code[i] == "}":
			depth -= 1
			if depth == 0:
				return _squash(code.substr(m.get_end(), i - m.get_end()))
	return ""


# =============================================================================================================
# 1. The curve — the promise that the screen cannot lie about what the ground is going to do
# =============================================================================================================

## The lethal speed is the damage formula solved for death, and it must read `hp` rather than `max_hp`. That is
## the entire reason the effect means anything: a drop that is a scratch at full health IS a lethal fall at one
## point of health, and the frame has to go fully grey earlier to say so.
func test_the_lethal_speed_moves_with_the_health_you_have_left() -> void:
	assert_almost_eq(FallDamage.lethal_speed(MIN_SPEED, PER_SPEED, FULL_HP), LETHAL_SPEED, 0.001,
		"at 4 HP and 0.5 HP per m/s over 16, the landing that costs exactly 4 HP is at 24 m/s")
	assert_almost_eq(FallDamage.lethal_speed(MIN_SPEED, PER_SPEED, 1.0), 18.0, 0.001,
		"at 1 HP the SAME actor dies at 18 m/s — the threshold must track current HP, not max, or the full-grey frame stops meaning 'this kills you'")
	assert_lt(FallDamage.lethal_speed(MIN_SPEED, PER_SPEED, 1.0), FallDamage.lethal_speed(MIN_SPEED, PER_SPEED, FULL_HP),
		"a hurt player must reach the lethal threshold at a LOWER speed than a healthy one")

## No survivable landing exists when fall damage is switched off (per_speed 0) or the actor is already down. INF
## is the honest answer and it is what lethal_fraction reads as "there is nothing here to warn about".
func test_no_speed_is_lethal_when_fall_damage_cannot_apply() -> void:
	assert_eq(FallDamage.lethal_speed(MIN_SPEED, 0.0, FULL_HP), INF,
		"per_speed 0 means no landing can ever cost HP — no speed is lethal, so the answer is INF and not a finite number the drain would then ramp toward")
	assert_eq(FallDamage.lethal_speed(MIN_SPEED, PER_SPEED, 0.0), INF,
		"an actor already at 0 HP is not something to warn about — the death cinematic owns that frame")

## The drain is the fall scored as a fraction of the HP you have. These four points ARE the feature.
func test_the_drain_is_the_fraction_of_your_health_the_landing_costs() -> void:
	assert_eq(FallDamage.lethal_fraction(MIN_SPEED, MIN_SPEED, PER_SPEED, FULL_HP), 0.0,
		"a landing at exactly the safe speed costs nothing, so the frame stays in FULL colour — a warning that fires on a harmless drop is a warning nobody reads")
	assert_almost_eq(FallDamage.lethal_fraction(20.0, MIN_SPEED, PER_SPEED, FULL_HP), 0.5, 0.001,
		"20 m/s costs 2 of 4 HP — half your health, so half the colour")
	assert_eq(FallDamage.lethal_fraction(LETHAL_SPEED, MIN_SPEED, PER_SPEED, FULL_HP), 1.0,
		"the lethal speed must land on EXACTLY 1.0 — the shader mixes to true grayscale there, and 'completely grey' is the one thing this cue promises")
	assert_eq(FallDamage.lethal_fraction(200.0, MIN_SPEED, PER_SPEED, FULL_HP), 1.0,
		"past lethal it clamps — falling twice as fast as death is still just death")

## Below the safe speed the numerator goes negative. It must clamp to 0 and never invert into a negative mix
## (which the shader would read as an over-SATURATION — colour pushed the wrong way on a harmless hop).
func test_a_harmless_fall_never_tints_and_never_goes_negative() -> void:
	for v in [0.0, 1.0, 4.5, 15.9]:
		assert_eq(FallDamage.lethal_fraction(v, MIN_SPEED, PER_SPEED, FULL_HP), 0.0,
			"%s m/s is under the %s m/s damage threshold — it must read 0, not a negative mix the shader would apply backwards" % [v, MIN_SPEED])

## The same fall reads GREYER the more hurt you are. Stated as an ordering rather than as fixed numbers, because
## that ordering is the design claim; the exact values are pinned above.
func test_the_same_fall_greys_out_more_the_more_hurt_you_are() -> void:
	var healthy := FallDamage.lethal_fraction(20.0, MIN_SPEED, PER_SPEED, FULL_HP)
	var grazed := FallDamage.lethal_fraction(20.0, MIN_SPEED, PER_SPEED, 3.0)
	var hurt := FallDamage.lethal_fraction(20.0, MIN_SPEED, PER_SPEED, 2.0)
	assert_lt(healthy, grazed, "20 m/s must read worse at 3 HP than at 4")
	assert_lt(grazed, hurt, "...and worse again at 2 HP")
	assert_eq(hurt, 1.0,
		"at 2 HP a 20 m/s landing costs exactly 2 HP — that IS a lethal fall, so the same drop that read half-grey at full health must now be COMPLETELY grey")

## Un-truncated on purpose, unlike hp_loss()'s int(). With 4 HP a truncated ramp would step in four visible
## bands over the whole fall; the drain has to be continuous or it reads as the screen glitching.
func test_the_drain_is_continuous_where_the_damage_number_is_truncated() -> void:
	assert_eq(FallDamage.hp_loss(17.0, MIN_SPEED, PER_SPEED), 0,
		"17 m/s costs half a point, which truncates to 0 actual damage — hp_loss is the COST and stays whole")
	assert_gt(FallDamage.lethal_fraction(17.0, MIN_SPEED, PER_SPEED, FULL_HP), 0.0,
		"...but the warning must already be draining at 17 m/s: it is a continuous read of danger, not a readout of whole HP, and quantising it would step the fade in visible bands")
	var last := -1.0
	for i in range(0, 41):
		var v := MIN_SPEED + float(i) * 0.2
		var f := FallDamage.lethal_fraction(v, MIN_SPEED, PER_SPEED, FULL_HP)
		assert_gte(f, last, "the drain must never run BACKWARDS as the fall gets faster (at %s m/s)" % v)
		last = f

## The void channel — the continuous-fall death timer, which is a different way to die and needs its own ramp.
func test_the_void_channel_ramps_over_the_last_seconds_before_the_fall_timer_kills_you() -> void:
	assert_eq(FallDamage.void_fraction(0.0, 4.0, 2.0), 0.0,
		"the instant you leave the ground nothing has happened yet — a hop must not tint the screen")
	assert_eq(FallDamage.void_fraction(2.0, 4.0, 2.0), 0.0,
		"at the START of the 2 s lead-in (2 s into a 4 s timer) the drain is still exactly 0")
	assert_almost_eq(FallDamage.void_fraction(3.0, 4.0, 2.0), 0.5, 0.001,
		"halfway through the lead-in, half the colour is gone")
	assert_eq(FallDamage.void_fraction(4.0, 4.0, 2.0), 1.0,
		"on the frame the timer kills you the frame must already be COMPLETELY grey — arriving after the death would be a warning about nothing")
	assert_eq(FallDamage.void_fraction(9.9, 4.0, 2.0), 1.0, "past the limit it clamps")

## The two off switches, and the one clamp that keeps a nonsense lead sane.
func test_the_void_channel_switches_off_cleanly() -> void:
	assert_eq(FallDamage.void_fraction(3.0, 4.0, 0.0), 0.0,
		"lead 0 is the designer's off switch for this channel — it must be a hard 0, not a divide by zero")
	assert_eq(FallDamage.void_fraction(3.0, 0.0, 2.0), 0.0,
		"limit 0 means the continuous-fall death is disabled entirely (the `god` debug command does exactly this), so there is nothing to count down to")
	assert_eq(FallDamage.void_fraction(0.0, 4.0, 99.0), 0.0,
		"a lead longer than the whole timer clamps to the timer — it means 'drain across the entire fall', which starts at 0")
	assert_almost_eq(FallDamage.void_fraction(2.0, 4.0, 99.0), 0.5, 0.001,
		"...and with the lead clamped to the 4 s limit, 2 s in is halfway")


# =============================================================================================================
# 2. The driver — the stateful half: instant rise, eased release, hard zero
# =============================================================================================================

## The two channels resolved off real host state, and the gate that keeps a rising or grounded player in colour.
func test_the_driver_reads_the_fall_off_the_host() -> void:
	var p = _falling_player(20.0)
	assert_almost_eq(p._fall_grey_target(), 0.5, 0.001,
		"falling at 20 m/s with 4 HP must target half grey — the driver has to resolve the same fraction the static does")
	p.velocity = Vector3(0.0, LETHAL_SPEED * -1.0, 0.0)
	assert_eq(p._fall_grey_target(), 1.0, "at the lethal speed the target is a completely grey frame")
	# Going UP is not falling, however fast. A rocket-jump must not grey the screen on the way up; it greys on
	# the way back DOWN, which is when there is something to warn about.
	p.velocity = Vector3(0.0, 40.0, 0.0)
	assert_eq(p._fall_grey_target(), 0.0,
		"rocketing UPWARD at 40 m/s is not a fall — the whole cue is about the ground below you")
	p.velocity = Vector3(0.0, 0.0, 0.0)
	assert_eq(p._fall_grey_target(), 0.0, "hanging still is not a fall either")
	p.free()

## Fall immunity makes the landing genuinely free, so the impact channel must go completely silent — warning
## about a landing that costs nothing would train the player to ignore the one that doesn't.
##
## But the continuous-fall death is NOT covered by that implant, so the void channel must keep firing. Without
## it, an immune player pitched off the edge of the world falls in full colour and dies with no tell at all.
## This is the single most important interaction in the feature and the reason the two channels are separate.
func test_fall_immunity_silences_the_impact_channel_but_not_the_void() -> void:
	var p = _falling_player(LETHAL_SPEED * 2.0)
	assert_eq(p._fall_grey_target(), 1.0, "baseline: without the implant this fall is lethal and reads fully grey")
	p.unlock_mechanic(&"fall_immunity")
	assert_true(p.has_mechanic(&"fall_immunity"), "precondition: the FallImmunity implant installed and active on the player")
	assert_eq(p._fall_grey_target(), 0.0,
		"with the fall-immunity implant active the landing costs nothing, so the impact channel must not tint the screen at all")
	# Control: the silence belongs to the ACTIVE implant, not to having once installed it.
	p.set_mechanic_active(&"fall_immunity", false)
	assert_eq(p._fall_grey_target(), 1.0,
		"switching the implant OFF in the Implants tab makes the landing lethal again, so the full-grey warning must come straight back")
	p.set_mechanic_active(&"fall_immunity", true)
	# ...and now the void timer starts running out underneath that silence.
	var limit: float = GameSettings.player_movement.max_continuous_fall_time
	var lead: float = GameSettings.player_feedback.fall_grey_void_lead
	p._continuous_fall_time = limit
	assert_eq(p._fall_grey_target(), 1.0,
		"the continuous-fall death ignores fall immunity, so an immune player must STILL be shown a completely grey frame as that timer runs out — otherwise the one death they can still die has no warning")
	p._continuous_fall_time = limit - lead * 0.5
	assert_almost_eq(p._fall_grey_target(), 0.5, 0.001, "...ramping, not popping")
	p.free()

## The rise is INSTANT and only the release is eased. A cue you read in the last half-second of a fall cannot
## afford to lag behind the danger it is describing.
func test_the_drain_arrives_instantly_and_only_the_release_is_eased() -> void:
	var p = _falling_player(LETHAL_SPEED)
	p._update_fall_grey(1.0 / 60.0)
	assert_eq(p._fall_grey, 1.0,
		"ONE frame at the lethal speed must already be fully grey — easing the rise would put the warning behind the fall")
	# Land. The colour must come back, but not on the landing frame: the tail draining out under the impact is
	# what stops it reading as a separate effect switching off.
	p.velocity = Vector3.ZERO
	p._update_fall_grey(1.0 / 60.0)
	assert_lt(p._fall_grey, 1.0, "the release has begun on the first grounded frame")
	assert_gt(p._fall_grey, 0.5, "...but it has NOT snapped back — one frame of release is a fraction of the drain, not all of it")
	p.free()

## And it must reach EXACTLY zero. An exponential ease approaches its target without arriving, and a permanent
## 0.001 of desaturation would keep the shader's `fall_grey > 0.0` branch alive on every frame of the game for a
## drain nobody can see — so the driver snaps through the last of it. This is what makes "free when you are not
## falling" true rather than nearly true.
func test_the_release_lands_on_exactly_zero_and_not_on_an_epsilon() -> void:
	var p = _falling_player(LETHAL_SPEED)
	p._update_fall_grey(1.0 / 60.0)
	p.velocity = Vector3.ZERO
	for _i in range(180):  # three seconds at 60 Hz — comfortably past the snap
		p._update_fall_grey(1.0 / 60.0)
	assert_eq(p._fall_grey, 0.0,
		"after the release the value must be EXACTLY 0.0, not an epsilon — otherwise post_process.gdshader runs the desaturation branch forever for a drain of one part in a thousand")
	p.free()

## Dying hands the screen to the death cinematic (`death_bw`), which drains and then blacks out the whole frame.
## The fall warning must stand down rather than fight it for the same pixels.
func test_a_dying_player_stops_driving_the_warning() -> void:
	var p = _falling_player(LETHAL_SPEED)
	assert_eq(p._fall_grey_target(), 1.0, "baseline: a live player mid-lethal-fall reads fully grey")
	p.hp = 0.0
	assert_eq(p._fall_grey_target(), 0.0, "at 0 HP there is no landing left to warn about")
	p.hp = FULL_HP
	p._dying = true
	assert_eq(p._fall_grey_target(), 0.0,
		"once the death cinematic has started it owns the frame — the warning must not keep writing over death_bw")
	p.free()

## The designer's off switch has to be a real off switch: 0 peak means the frame is bit-identical to a build
## without the feature, not "almost none".
func test_the_peak_knob_switches_the_whole_feature_off() -> void:
	var fb = GameSettings.player_feedback  # untyped autoload -> Variant; the knob writes below are dynamic
	var saved: float = fb.fall_grey_max
	var p = _falling_player(LETHAL_SPEED)
	fb.fall_grey_max = 0.0
	var off: float = p._fall_grey_target()
	fb.fall_grey_max = 0.5
	var half: float = p._fall_grey_target()
	fb.fall_grey_max = saved  # restore BEFORE asserting — GameSettings resources are shared across the whole suite
	assert_eq(off, 0.0, "fall_grey_max 0 must leave the frame untouched, exactly as if the feature were not compiled in")
	assert_almost_eq(half, 0.5, 0.001, "and it must SCALE the peak: a lethal fall at half strength is half grey")
	p.free()

## The shipped default has to be the full drain, because the mechanic's whole claim is that a lethal fall turns
## the screen COMPLETELY grey. Anything less and the top of the range stops being a distinguishable state.
func test_a_lethal_fall_ships_at_completely_grey() -> void:
	assert_eq(GameSettings.player_feedback.fall_grey_max, 1.0,
		"fall_grey_max must SHIP at 1.0 — a lethal fall going only partly grey leaves the player no way to tell 'this will nearly kill me' from 'this will kill me', which is the one distinction the cue exists to draw")
	assert_gt(GameSettings.player_feedback.fall_grey_release_rate, 0.0,
		"the release must be eased by default — snapping the colour back on the landing frame reads as a bug rather than as the end of the fall")
	assert_gt(GameSettings.player_feedback.fall_grey_void_lead, 0.0,
		"the void channel must ship ON: it is the only warning a fall-immune player gets, and the only one for a fall the impact formula does not score")


# =============================================================================================================
# 3. The seams — the push driven for real; the shader side pinned on comment-stripped source
# =============================================================================================================

## The value player.gd moves has to land on a uniform post_process.gdshader actually declares. set_shader_parameter
## on a name that does not exist is silently discarded, so a rename on EITHER side turns the whole feature into a
## dead write with no error anywhere — this drives the push and checks the name against the live declaration.
func test_the_player_pushes_the_drain_into_a_uniform_the_shader_declares() -> void:
	var decl := RegEx.new()
	decl.compile("uniform\\s+float\\s+" + FALL_UNIFORM
		+ "\\s*:\\s*hint_range\\(\\s*([-\\d.]+)\\s*,\\s*([-\\d.]+)\\s*\\)\\s*=\\s*([-\\d.]+)\\s*;")
	var m := decl.search(_shader_code())
	assert_true(m != null,
		"post_process.gdshader must declare a LIVE (uncommented) `uniform float fall_grey : hint_range(..) = ..;` — player.gd pushes that name every physics frame, and a push to a missing uniform is dropped in silence")
	if m != null:
		assert_eq(float(m.get_string(3)), 0.0,
			"...defaulting to 0, so an UN-DRIVEN material (computerroom.tscn's CRT wall, this shader on a bare quad in the editor) is untouched by a feature only the player drives")
		assert_eq([float(m.get_string(1)), float(m.get_string(2))], [0.0, 1.0],
			"...ranged 0..1, the exact span the driver writes (0 = full colour, 1 = the lethal fall's completely grey frame)")
	var p = _falling_player(20.0)
	var mat := _give_post_rect(p)
	p._update_fall_grey(DT)
	assert_almost_eq(_pushed(mat), 0.5, 0.001,
		"a 20 m/s fall at 4 HP must land 0.5 on the shader's `fall_grey` uniform — the value moving with nothing reading it is the classic half-wiring")
	p.velocity = Vector3.ZERO
	p._update_fall_grey(DT)
	var eased: float = p._fall_grey
	assert_lt(eased, 0.5, "precondition: the release has begun on the first grounded frame")
	assert_eq(_pushed(mat), eased,
		"the push must follow the release down every frame, not only write on the way up — otherwise the landing freezes the screen at the mid-fall grey")
	p.free()

## KEPT AS A SHADER PIN (headless never compiles a .gdshader). The mix has to reach TRUE grayscale, and it has to be
## a desaturation ONLY. `hurt`, `low_hp` and the death cinematic all already darken and close a vignette; this one
## must not, or the three cues stop being distinguishable from each other at the moment they matter most.
func test_the_shader_pass_is_a_pure_drain_to_exact_grayscale() -> void:
	var code := _shader_code()
	var fall := _gated_pass(code, FALL_UNIFORM)
	assert_ne(fall, "",
		"the fall pass must sit behind a live `if (fall_grey > 0.0) {` gate — the driver snaps to exactly 0 when you are not falling, so this branch is what makes a grounded frame genuinely free")
	var lum := RegEx.new()
	lum.compile("float (\\w+) = dot\\(final_color, (vec3\\([^)]*\\))\\);")
	var fall_lum := lum.search(fall)
	assert_true(fall_lum != null, "the fall pass must read the frame's luminance (`float <lum> = dot(final_color, vec3(..));`) before mixing toward it")
	if fall_lum == null:
		return
	var mix_at := fall.find("final_color = mix(final_color, vec3(%s), clamp(fall_grey, 0.0, 1.0));" % fall_lum.get_string(1))
	assert_gt(mix_at, fall_lum.get_end() - 1,
		"the fall pass must be a plain luminance mix at the FULL clamp, AFTER the luma it mixes toward — at 1.0 that is EXACT grayscale, which is what 'completely grey means this kills you' requires; a partial mix (low_hp's * 0.8), a tint or a multiply breaks the top of the range")
	assert_eq(fall.count(";"), 2,
		"the fall pass must be exactly the luma read and the mix — a third statement (a vignette, a darken, a tint) makes it read like hurt / low_hp: " + fall)
	var death_lum := lum.search(_gated_pass(code, "death_bw"))
	assert_true(death_lum != null, "the death cinematic's grayscale pass must still read luminance the same way")
	if death_lum != null:
		assert_eq(fall_lum.get_string(2), death_lum.get_string(2),
			"the fall drain must use the SAME luma weights as the death cinematic, so a frame greyed by a fall and the death_bw frame that takes it over are the same grey")

## KEPT AS A SHADER PIN. Placement in the chain: with the sustained world grades (after low_hp, before
## daltonization and grain), NOT with the death cinematic at the end — a warning is part of the picture, an override
## is not. Ordered by the passes' live CODE, so moving a pass while leaving its comment behind is caught.
func test_the_fall_pass_sits_with_the_world_grades_not_with_the_death_override() -> void:
	var code := _shader_code()
	var at := {}
	for uniform in ["low_hp", FALL_UNIFORM, "colorblind_mode", "death_bw"]:
		var gate := RegEx.new()
		gate.compile("if\\s*\\(\\s*" + uniform + "\\s*>\\s*0(\\.0)?\\s*\\)")
		var hits := gate.search_all(code)
		assert_eq(hits.size(), 1, "post_process.gdshader must run exactly one live `if (%s > 0..)` pass" % uniform)
		at[uniform] = hits[0].get_start() if hits.size() > 0 else -1
	var grain := RegEx.new()
	grain.compile("final_color\\s*\\+=\\s*noise\\s*\\*\\s*grain_amount")
	var grain_m := grain.search(code)
	assert_true(grain_m != null, "the film grain must still be layered onto final_color")
	var grain_at := grain_m.get_start() if grain_m != null else -1
	assert_gt(at[FALL_UNIFORM], at["low_hp"],
		"the fall drain must run AFTER the low-HP drain, so a wounded player's fall greys out an already-drained frame instead of the two passes fighting over the same pixels")
	assert_lt(at[FALL_UNIFORM], at["colorblind_mode"],
		"...and BEFORE daltonization, like low_hp: this is a world colour grade, so the accessibility passes get the last word")
	assert_lt(at[FALL_UNIFORM], grain_at, "...and before the grain, which still lays over the greyed frame")
	assert_lt(at[FALL_UNIFORM], at["death_bw"],
		"...and well before the death cinematic, which is the pass that IS allowed to override everything — that ordering is what makes a fall death continuous, the frame already fully grey when death_bw takes it over")

## A conversation opened mid-fall freezes the player (velocity zeroed) in the one _physics_process branch that
## returns before the main driver. That branch must still drive the warning, or the whole chat is held in grayscale.
func test_a_conversation_opened_mid_fall_drains_the_grey_instead_of_holding_it() -> void:
	var p = _falling_player(LETHAL_SPEED)
	var mat := _give_post_rect(p)
	p._update_fall_grey(DT)
	assert_eq(p._fall_grey, 1.0, "precondition: fully grey mid-lethal-fall when the conversation opens")
	DialogueManager._active = DialogueResource.new()
	DialogueManager._suspended = false
	var in_dialogue := DialogueManager.is_active()
	p._physics_process(DT)
	var first_frame: float = p._fall_grey
	var frozen: Vector3 = p.velocity
	for _i in range(179):
		p._physics_process(DT)
	var settled: float = p._fall_grey
	DialogueManager._active = _saved_dialogue  # restore BEFORE asserting — the dialogue gate is process-global
	DialogueManager._suspended = _saved_suspended
	assert_true(in_dialogue, "precondition: the staged conversation reads as active")
	assert_eq(frozen, Vector3.ZERO, "precondition: the dialogue branch froze the fall")
	assert_lt(first_frame, 1.0, "the grey must start easing out on the first frozen frame — a frozen player is not falling")
	assert_eq(settled, 0.0,
		"three seconds into the conversation the grey must be gone EXACTLY — otherwise the whole chat is held in grayscale")
	assert_eq(_pushed(mat), 0.0, "...and the shader must have been told, not just the accumulator")
	p.free()

## KEPT AS A SOURCE PIN: the live branch of Player._physics_process runs coyote_time, gravity and input over
## components only _ready builds, so it cannot be driven off-tree (CLAUDE.md). It is the only thing that moves the
## value during play. Scoped to that function body, comments stripped, and required at the function's TOP level with
## no top-level `return` ahead of it — a call nested in a branch or parked after an early return fails.
func test_the_live_physics_step_drives_the_warning() -> void:
	var lines := _read(PLAYER_PATH).split("\n")
	var start := lines.find("func _physics_process(delta: float) -> void:")
	assert_gt(start, -1, "player.gd must still define `func _physics_process(delta: float) -> void:`")
	if start < 0:
		return
	var strip := RegEx.new()
	strip.compile("\\s*#.*$")
	var call_line := -1
	var early_return := -1
	for i in range(start + 1, lines.size()):
		var raw: String = lines[i]
		if raw != "" and not raw.begins_with("\t") and not raw.begins_with("#"):
			break  # the next top-level declaration ends the function body
		var code := strip.sub(raw, "")
		if code == "\treturn" and early_return < 0 and call_line < 0:
			early_return = i
		if code == "\t_update_fall_grey(delta)" and call_line < 0:
			call_line = i
	assert_gt(call_line, -1,
		"Player._physics_process must call _update_fall_grey(delta) at its top level — it is the only thing that moves the value, and die()'s set_physics_process(false) is exactly why it must be driven from there rather than by a self-ticking node")
	assert_eq(early_return, -1, "...with no top-level `return` ahead of that call, or the warning never runs")

## The respawn reset. A fall DEATH deliberately freezes the warning at full grey (die() stops the physics step and
## the death cinematic takes the frame over), so nothing writes it back down — the fresh life would fade up into a
## grey world. _reset_screen_post_process is driven here from exactly that frozen state.
func test_the_respawn_clears_the_frozen_grey() -> void:
	var p = _falling_player(LETHAL_SPEED)
	var mat := _give_post_rect(p)
	p._update_fall_grey(DT)
	assert_eq(_pushed(mat), 1.0, "precondition: a lethal fall froze the uniform at full grey")
	p._reset_screen_post_process()
	assert_eq(_pushed(mat), 0.0,
		"_reset_screen_post_process must clear the uniform — a fall death leaves it pinned at 1.0 with the physics step off, so a CHECKPOINT_RESPAWN would fade back up into a completely grey world")
	assert_eq(p._fall_grey, 0.0,
		"...and the accumulator with it, or the first live frame's release would ease down from the dead life's value")
	p.velocity = Vector3.ZERO
	p._update_fall_grey(DT)
	assert_eq(_pushed(mat), 0.0, "the fresh life's first grounded frame must be in full colour, not a fading-out grey")
	p.free()
	# The accumulator is cleared even when there is no overlay to write to (the reset's early-out comes after it).
	var bare = _falling_player(LETHAL_SPEED)
	bare._update_fall_grey(DT)
	bare._reset_screen_post_process()
	assert_eq(bare._fall_grey, 0.0, "with no post-process overlay wired the accumulator must still be cleared on respawn")
	bare.free()

## The knobs are the designer's inspector surface and each is RANGED from 0, so the inspector cannot author a
## negative drain (which the shader would apply backwards) or a peak past 1. The driver must also hold that line
## for a value that arrives out of range anyway (a hand-edited .tres, a debug command).
func test_the_designer_knobs_are_ranged_and_the_driver_clamps_them_anyway() -> void:
	var fb = GameSettings.player_feedback  # untyped autoload -> Variant; the knob writes below are dynamic
	var props := {}
	for prop in fb.get_property_list():
		props[prop["name"]] = prop
	for knob in ["fall_grey_max", "fall_grey_release_rate", "fall_grey_void_lead"]:
		assert_true(props.has(knob), "PlayerFeedbackSettings must still carry `%s`" % knob)
		if not props.has(knob):
			continue
		var info: Dictionary = props[knob]
		assert_true((int(info["usage"]) & PROPERTY_USAGE_EDITOR) != 0,
			"`%s` must be @exported — the fall warning's tuning belongs on the inspector page with the rest of the hit/death feel" % knob)
		assert_eq(int(info["hint"]), PROPERTY_HINT_RANGE, "`%s` must be an @export_range, not a free-form float" % knob)
		assert_eq(float(String(info["hint_string"]).split(",")[0]), 0.0,
			"`%s` must be ranged from 0.0 — a negative is a drain the shader would apply backwards" % knob)
	if props.has("fall_grey_max"):
		assert_eq(float(String(props["fall_grey_max"]["hint_string"]).split(",")[1]), 1.0,
			"fall_grey_max tops out at 1.0 — past that is no longer a grayscale mix")
	var p = _falling_player(LETHAL_SPEED)
	fb.fall_grey_max = 2.0
	var over: float = p._fall_grey_target()
	fb.fall_grey_max = -1.0
	var under: float = p._fall_grey_target()
	fb.fall_grey_max = _saved_grey_max
	fb.fall_grey_release_rate = -5.0
	p._update_fall_grey(DT)
	p.velocity = Vector3.ZERO
	p._update_fall_grey(DT)
	var negative_rate_release: float = p._fall_grey
	fb.fall_grey_release_rate = _saved_release_rate  # restore BEFORE asserting — shared across the suite
	assert_eq(over, 1.0, "a peak authored past 1 must still cap the lethal fall at exactly full grey")
	assert_eq(under, 0.0, "a negative peak must read as the feature OFF, never as colour pushed out of the frame")
	assert_eq(negative_rate_release, 0.0,
		"a negative release rate must cut straight back to colour on the landing frame, never run the ease backwards")
	p.free()
