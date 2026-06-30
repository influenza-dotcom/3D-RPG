extends GutTest

## Thrown-decoy noise config (stealth Slice 4 -- "lob a rock to lure a guard"). The actual spawn
## (Throwable._emit_decoy_noise: one-shot, thrown-only, one-per-throw) is in-tree/physics and playtest-verified;
## the pure CONFIG resolution -- per-prop ThrowableData overrides vs the GameSettings.distraction defaults --
## and the on-by-default decoy flag + the inherit overrides are unit-tested here. (NoiseSource's own audible/decay/lifetime are covered
## in test_noise_source.gd.)


func test_throwable_data_decoy_defaults() -> void:
	var d := ThrowableData.new()
	assert_true(d.noise_on_land, "noise_on_land defaults ON -> any thrown prop is a decoy unless explicitly turned off")
	assert_lt(d.noise_radius, 0.0, "noise_radius defaults negative = inherit the global default")
	assert_lt(d.noise_decay, 0.0, "noise_decay defaults negative = inherit")
	assert_lt(d.noise_lifetime, 0.0, "noise_lifetime defaults negative = inherit")
	d = null

func test_distraction_settings_defaults() -> void:
	var s := DistractionSettings.new()
	assert_gt(s.decoy_radius, 0.0, "a decoy must carry SOME distance or it lures nobody")
	assert_gte(s.decoy_decay, 0.0, "decay is non-negative (0 = constant radius)")
	assert_gt(s.decoy_lifetime, 0.0, "lifetime must be > 0 so a thrown decoy self-frees and never leaks a NoiseSource")
	s = null

func test_resolved_decoy_inherits_defaults_when_unset() -> void:
	var d := ThrowableData.new()  # all overrides negative -> inherit
	var s := DistractionSettings.new()
	s.decoy_radius = 9.0
	s.decoy_decay = 1.5
	s.decoy_lifetime = 3.0
	var cfg := d.resolved_decoy(s)
	assert_almost_eq(float(cfg[&"radius"]), 9.0, 0.0001, "an unset (negative) radius inherits the global default")
	assert_almost_eq(float(cfg[&"decay"]), 1.5, 0.0001, "an unset decay inherits")
	assert_almost_eq(float(cfg[&"lifetime"]), 3.0, 0.0001, "an unset lifetime inherits")
	d = null
	s = null

func test_resolved_decoy_override_wins_and_zero_is_explicit() -> void:
	var d := ThrowableData.new()
	d.noise_radius = 20.0   # a loud prop
	d.noise_decay = 0.0     # 0 is a VALID override (constant radius) -- only a NEGATIVE value inherits
	# noise_lifetime left at the default -1.0 -> inherit
	var s := DistractionSettings.new()
	s.decoy_radius = 9.0
	s.decoy_decay = 5.0
	s.decoy_lifetime = 3.0
	var cfg := d.resolved_decoy(s)
	assert_almost_eq(float(cfg[&"radius"]), 20.0, 0.0001, "a per-prop radius override (>= 0) wins over the default")
	assert_almost_eq(float(cfg[&"decay"]), 0.0, 0.0001, "decay 0 is an explicit override (constant), NOT inherit")
	assert_almost_eq(float(cfg[&"lifetime"]), 3.0, 0.0001, "the unset (negative) lifetime still inherits")
	d = null
	s = null

func test_resolved_decoy_zero_lifetime_inherits_so_a_decoy_is_never_persistent() -> void:
	# lifetime is special: 0 is NOT a valid override (a 0-lifetime NoiseSource would be PERSISTENT and leak /
	# trap NPCs), so 0 OR negative both inherit the global default. radius/decay still treat 0 as a real override.
	var d := ThrowableData.new()
	d.noise_lifetime = 0.0   # would-be-persistent -> must inherit instead
	d.noise_radius = 0.0     # radius 0 IS a valid (silent) override, to prove the rules differ per field
	var s := DistractionSettings.new()
	s.decoy_radius = 9.0
	s.decoy_lifetime = 5.0
	var cfg := d.resolved_decoy(s)
	assert_almost_eq(float(cfg[&"lifetime"]), 5.0, 0.0001, "a 0 lifetime override inherits the default — a decoy is always one-shot")
	assert_almost_eq(float(cfg[&"radius"]), 0.0, 0.0001, "radius 0 is still a valid explicit override (unlike lifetime)")
	d = null
	s = null
