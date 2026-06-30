extends GutTest

## Tests for Claimable. The eligibility predicate (Claimable.eligible) is pure logic — literal booleans (mirrors
## test_pettable). claim_name() resolution + claim() need an in-tree PARENT (they read/write get_parent()), so those
## parent a Claimable under a tiny stub host via add_child_autofree with auto_fit_collider off — still no Player/NPC
## _ready (per CLAUDE.md). The in-tree raycast + name dialog remain manual-playtest only.

const Claimable := preload("res://scripts/components/claimable.gd")
const PropFollow := preload("res://scripts/components/prop_follow.gd")


## A host that exposes the Throwable's verb-less resolver AND a settable display_name (so we can verify renaming),
## plus the persistent-outline hooks (so we can verify the blue claimed rim is applied / lifted) — the duck-typed
## surface Claimable calls on a Throwable.
class _DogHost extends Node:
	var display_name := ""
	var outline_color = null      ## last colour passed to set_persistent_outline (null = never set / cleared)
	var outline_cleared := false  ## set true by clear_persistent_outline
	func resolved_display_name() -> String:
		return display_name if not display_name.is_empty() else "Dog"
	func set_persistent_outline(color: Color) -> void:
		outline_color = color
		outline_cleared = false
	func clear_persistent_outline() -> void:
		outline_cleared = true


func test_disabled_never_eligible() -> void:
	assert_false(Claimable.eligible(false, false),
		"A disabled Claimable can never be claimed")


func test_enabled_unclaimed_is_eligible() -> void:
	assert_true(Claimable.eligible(true, false),
		"Enabled + not yet claimed = claimable")


func test_already_claimed_gate() -> void:
	assert_false(Claimable.eligible(true, true),
		"Claiming is one-shot — an already-claimed object can't be claimed again")


func test_defaults_ask_for_name_on() -> void:
	# Off-tree field reads — Claimable.new() with no add_child runs no _ready.
	var c = Claimable.new()
	assert_true(c.ask_for_name,
		"claiming opens the name box by default (the requested behaviour)")
	assert_eq(c.prompt_verb, "Befriend",
		"the default prompt verb is 'Befriend' (friendlier than 'Claim' for adopting a stray)")
	c.free()


func _make_claimable():
	var c = Claimable.new()
	c.auto_fit_collider = false  # we only exercise name/claim logic — no runtime hitbox needed
	return c


func test_claim_name_prefers_host_resolved_name() -> void:
	var host := _DogHost.new()
	host.name = "Throwable"
	add_child_autofree(host)
	var c = _make_claimable()
	host.add_child(c)
	assert_eq(c.claim_name(), "Dog",
		"claim_name uses the host's resolved_display_name, NOT the node name 'Throwable'")


func test_claim_renames_host_and_locks() -> void:
	var host := _DogHost.new()
	host.name = "Throwable"
	add_child_autofree(host)
	var c = _make_claimable()
	host.add_child(c)
	watch_signals(c)
	c.claim(null, "Rex")
	assert_eq(host.display_name, "Rex",
		"claiming pushes the chosen name onto the host's display_name (so the readout reads 'Rex')")
	assert_false(c.can_claim(),
		"after a claim the object is locked — it can't be claimed again")
	assert_signal_emitted(c, "claimed",
		"claiming fires the claimed() signal so designers can hook a reaction")


func test_claim_adds_enabled_prop_follow() -> void:
	var host := _DogHost.new()
	add_child_autofree(host)
	var c = _make_claimable()
	host.add_child(c)
	c.claim(null, "Rex")
	var follow: PropFollow = null
	for child in host.get_children():
		if child is PropFollow:
			follow = child
			break
	assert_not_null(follow,
		"claiming adds a PropFollow to the host so the object now follows the player")
	if follow != null:
		assert_true(follow.enabled,
			"the added PropFollow is switched ON by the claim (an unclaimed prop ships it off)")


func test_claim_enables_existing_prop_follow() -> void:
	# A designer can pre-place a tuned-but-disabled PropFollow; claiming should ENABLE it, not add a second.
	var host := _DogHost.new()
	add_child_autofree(host)
	var pre := PropFollow.new()
	pre.enabled = false
	host.add_child(pre)
	var c = _make_claimable()
	host.add_child(c)
	c.claim(null, "Rex")
	assert_true(pre.enabled,
		"claiming enables a pre-placed PropFollow (honouring its Inspector tuning)")
	var count := 0
	for child in host.get_children():
		if child is PropFollow:
			count += 1
	assert_eq(count, 1,
		"claiming reuses the existing PropFollow rather than adding a duplicate")


func test_empty_name_falls_back_to_default() -> void:
	var host := _DogHost.new()
	add_child_autofree(host)
	var c = _make_claimable()
	c.default_name = "Stray"
	host.add_child(c)
	c.claim(null, "")
	assert_eq(host.display_name, "Stray",
		"a blank typed name falls back to the Claimable's default_name")


func test_claim_applies_blue_outline() -> void:
	var host := _DogHost.new()
	add_child_autofree(host)
	var c = _make_claimable()
	host.add_child(c)
	c.claim(null, "Rex")
	assert_eq(host.outline_color, c.claimed_outline_color,
		"claiming pins the claimed rim colour (default blue) on the host via set_persistent_outline")


func test_unclaimable_when_unclaimed() -> void:
	var c = _make_claimable()
	assert_false(c.can_unclaim(),
		"an object that hasn't been claimed can't be unclaimed")
	c.free()


func test_unclaim_reverts_everything() -> void:
	var host := _DogHost.new()
	add_child_autofree(host)
	var c = _make_claimable()
	host.add_child(c)
	c.claim(null, "Rex")
	assert_true(c.can_unclaim(), "a claimed object with allow_unclaim on can be released")
	watch_signals(c)
	c.unclaim(null)
	assert_true(c.can_claim(),
		"after a release the object is claimable again")
	assert_false(c.can_unclaim(),
		"after a release it's no longer claimed, so it can't be released again")
	assert_true(host.outline_cleared,
		"releasing lifts the blue claimed rim (clear_persistent_outline)")
	assert_eq(host.display_name, "",
		"releasing reverts the host's name to its original (un-names the dog)")
	assert_eq(c.claim_name(), "Dog",
		"after release the prompt name falls back to the original resolved name, not the given 'Rex'")
	assert_signal_emitted(c, "unclaimed",
		"releasing fires the unclaimed() signal")
	# The follow added by the claim is DISABLED (not removed), so a re-claim re-enables the same one.
	for child in host.get_children():
		if child is PropFollow:
			assert_false((child as PropFollow).enabled,
				"releasing disables the PropFollow so the object stops following")


func test_unclaim_restores_prior_name() -> void:
	# A prop that already had a name BEFORE being befriended gets THAT name back on release (not blanked).
	var host := _DogHost.new()
	host.display_name = "Mutt"
	add_child_autofree(host)
	var c = _make_claimable()
	host.add_child(c)
	c.claim(null, "Rex")
	assert_eq(host.display_name, "Rex", "befriending renames the host to the chosen name")
	c.unclaim(null)
	assert_eq(host.display_name, "Mutt",
		"releasing restores the host's ORIGINAL name, not a blank")


func test_unclaim_blocked_when_not_allowed() -> void:
	var host := _DogHost.new()
	add_child_autofree(host)
	var c = _make_claimable()
	c.allow_unclaim = false
	host.add_child(c)
	c.claim(null, "Rex")
	assert_false(c.can_unclaim(),
		"with allow_unclaim off, a claimed object is permanent — it can't be released")
