extends GutTest

## M2: the NPC host-facade contract (see scripts/npc/README.md). Components attach to an NPC and read/write host
## members; the Node-typed ones do so DYNAMICALLY (no compile signal on a host rename), so these DRIVE each seam
## against a host and assert what the player would see:
##   - every component's `host` defaults null (bound by NPC._build_components at spawn, never at construction), and
##     the public write seams (_set_target, set_last_attacker) exist on NPC;
##   - NpcTargeting keeps a live, in-range attacker locked, and releases the lock THROUGH host.set_last_attacker
##     (then falls back to the nearest foe) once the attacker leaves range;
##   - the has-target distraction feeler (P0-4) pulls a still-UNAWARE guard to a decoy, but never re-points a guard
##     that is already investigating something; the facade is inert until the child exists;
##   - the bark facade round-trips into NpcVoice.emit and its HOST-owned one-bubble-at-a-time latch;
##   - WeaponStance only tops up a partial clip out of combat when a reload would actually load rounds (C5).
## NPCs are built off-tree via load(...).new() WITHOUT _ready (CLAUDE.md); the children _build_components would
## make are wired by hand (a real Perception + NpcDistraction, a senses double that reports the test's decoy).
## Only plain stand-ins (a targeting host, foes, NoiseSources, an NpcVoice for its reaction timer) enter the tree.
## Not covered here: NpcVoice._speak handing the HOST to SpeechTts as the bark source (needs a live Flite synth —
## Settings.tts_enabled + a native TextToSpeech3D — which a headless unit run must not start), and NPC.reset_for_reuse
## cascading into NpcDistraction.reset_for_reuse (its first line reads global_position, so it needs an in-tree NPC;
## the component's own reset is pinned in tests/test_npc_pool.gd).

const NPC_PATH := "res://scripts/npc/npc.gd"
const DISTRACTION_PATH := "res://scripts/npc/npc_distraction.gd"

const COMPONENTS := [
	"res://scripts/npc/npc_targeting.gd",
	"res://scripts/npc/npc_locomotion.gd",
	"res://scripts/npc/npc_voice.gd",
	"res://scripts/npc/npc_scavenge.gd",
	"res://scripts/npc/npc_combat.gd",
	"res://scripts/npc/npc_bark_ui.gd",
	"res://scripts/npc/companion_follow.gd",
	"res://scripts/npc/weapon_stance.gd",
	"res://scripts/npc/talk_approach.gd",
	"res://scripts/npc/npc_outline.gd",
	"res://scripts/npc/npc_laser.gd",
	"res://scripts/npc/npc_audio_cues.gd",
	"res://scripts/npc/npc_mortality.gd",
	"res://scripts/npc/npc_senses.gd",
	"res://scripts/npc/npc_home_return.gd",
	"res://scripts/npc/npc_distraction.gd",
]

var _saved_reaction_time: float = 0.0
var _saved_reaction_jitter: float = 0.0


func before_each() -> void:
	_saved_reaction_time = GameSettings.npc_ai.hearing_reaction_time
	_saved_reaction_jitter = GameSettings.npc_ai.hearing_reaction_jitter


func after_each() -> void:
	GameSettings.npc_ai.hearing_reaction_time = _saved_reaction_time
	GameSettings.npc_ai.hearing_reaction_jitter = _saved_reaction_jitter


# --- stand-ins -------------------------------------------------------------------------------------------------

## The NPC as NpcTargeting sees it (its `host` is Node-typed, every read dynamic). Records every value routed
## through the public set_last_attacker seam, in order.
class _TargetingHost extends Node3D:
	var sight_range: float = 10.0
	var _target: Node3D = null
	var _last_attacker = null
	var foes: Array = []
	var lock_writes: Array = []

	func _protectee() -> Node3D:
		return null

	func _treats_as_enemy(node) -> bool:
		return foes.has(node)

	func set_last_attacker(node: Node) -> void:
		lock_writes.append(node)
		_last_attacker = node

	func _set_target(node: Node3D) -> void:
		_target = node


## Senses that hear exactly the decoy the test hands them and see no bodies. The real scans are live group scans +
## LOS rays from the host's transform, which an off-tree NPC does not have.
class _DecoySenses extends NpcSenses:
	var decoy: NoiseSource = null

	func loudest_noise() -> NoiseSource:
		return decoy

	func nearest_visible_corpse() -> Corpse:
		return null


## A weapon hub that counts reload() requests and is never mid-reload. The real reload()/is_busy() run Attack's
## Timers, which only exist once weapon.tscn is instantiated in-tree.
class _CountingWeapon extends Weapon:
	var reloads: int = 0

	func reload() -> void:
		reloads += 1

	func is_busy() -> bool:
		return false


func _react_instantly() -> void:
	# A heard noise normally ARMS a reaction (hearing_reaction_time); zero it so the reaction lands on this scan and
	# the test can read where the guard is investigating. Restored in after_each.
	GameSettings.npc_ai.hearing_reaction_time = 0.0
	GameSettings.npc_ai.hearing_reaction_jitter = 0.0


func _decoy(at: Vector3) -> NoiseSource:
	var n := NoiseSource.new()
	n.radius = 8.0
	add_child_autofree(n)
	n.global_position = at
	return n


## An off-tree hostile guard (the NPC default disposition) wired the way _build_components would wire it.
func _guard(senses: NpcSenses):
	var npc = load(NPC_PATH).new()
	npc.hp = 100.0  # seeded from max_hp in Character._ready, which never runs here
	npc.hearing_initiates_opt_in = true  # listens to the noise channel whatever the global default is
	npc._perception = Perception.new()
	npc._senses = senses
	var d = load(DISTRACTION_PATH).new()
	d.host = npc
	npc._distraction = d
	return npc


func _free_guard(npc, distraction, senses: NpcSenses) -> void:
	npc._perception.free()
	distraction.free()
	senses.free()
	npc.free()


# --- surface pins ----------------------------------------------------------------------------------------------

func test_components_host_defaults_null() -> void:
	# host is bound by NPC._build_components at spawn — a bare .new() must leave it null (a non-null default would
	# double-bind / strand a stale host).
	for path in COMPONENTS:
		var c = load(path).new()
		assert_true("host" in c, "%s should expose a `host` field" % path)
		assert_null(c.get("host"), "%s.host must default null (bound by NPC._build_components, not at construction)" % path)
		c.free()


func test_npc_exposes_the_write_seams() -> void:
	var npc = load(NPC_PATH).new()
	assert_true(npc.has_method("_set_target"), "NPC._set_target binds the combat target (the NpcTargeting seam)")
	assert_true(npc.has_method("set_last_attacker"), "NPC.set_last_attacker is the M2 write seam for the _last_attacker lock")
	npc.free()


# --- NpcTargeting: the sticky attacker lock --------------------------------------------------------------------

func test_targeting_stays_locked_on_an_attacker_still_in_range() -> void:
	var host := _TargetingHost.new()
	add_child_autofree(host)
	var attacker := Node3D.new()
	add_child_autofree(attacker)
	attacker.global_position = Vector3(5, 0, 0)
	var nearer := Node3D.new()
	add_child_autofree(nearer)
	nearer.add_to_group(Groups.NPC)
	nearer.global_position = Vector3(2, 0, 0)
	host.foes = [attacker, nearer]
	host._last_attacker = attacker
	var tg := NpcTargeting.new()
	tg.host = host
	tg._acquire_target()
	assert_eq(host._target, attacker,
		"an NPC that was shot keeps fighting whoever shot it while they're in range, not whichever foe is nearest")
	assert_eq(host._last_attacker, attacker, "the attacker lock survives a re-acquire while the attacker is engageable")
	assert_eq(host.lock_writes.size(), 0, "nothing writes the lock while it is still valid")
	tg.free()


func test_targeting_releases_an_out_of_range_attacker_through_the_setter() -> void:
	var host := _TargetingHost.new()
	add_child_autofree(host)
	var attacker := Node3D.new()
	add_child_autofree(attacker)
	attacker.global_position = Vector3(30, 0, 0)  # fled well past sight_range (10)
	var nearer := Node3D.new()
	add_child_autofree(nearer)
	nearer.add_to_group(Groups.NPC)
	nearer.global_position = Vector3(2, 0, 0)
	host.foes = [attacker, nearer]
	host._last_attacker = attacker
	var tg := NpcTargeting.new()
	tg.host = host
	tg._acquire_target()
	assert_eq(host._target, nearer,
		"once the attacker fled out of sight_range the NPC re-targets the nearest foe instead of chasing a ghost")
	assert_eq(host._last_attacker, null, "the stale attacker lock is released, or it would pull the NPC back later")
	assert_eq(host.lock_writes, [null],
		"the release goes through host.set_last_attacker(null) exactly once (the M2 write seam), not a raw poke")
	tg.free()


# --- NpcDistraction behind NPC._react_distraction (P0-4) -------------------------------------------------------

func test_unaware_guard_is_pulled_to_a_decoy_through_the_facade() -> void:
	_react_instantly()
	var senses := _DecoySenses.new()
	senses.decoy = _decoy(Vector3(6, 0, 3))
	var npc = _guard(senses)
	var d = npc._distraction
	var p: Perception = npc._perception
	npc._react_distraction(0.1)
	assert_eq(p.state, Perception.State.INVESTIGATING,
		"a hostile holding the player as a proximity target but still UNAWARE must fall for a thrown decoy (P0-4)")
	assert_eq(p.last_known_position, senses.decoy.global_position, "the guard investigates where the decoy landed")
	_free_guard(npc, d, senses)


func test_investigating_guard_is_not_re_pointed_by_a_decoy() -> void:
	_react_instantly()
	var senses := _DecoySenses.new()
	senses.decoy = _decoy(Vector3(6, 0, 3))
	var npc = _guard(senses)
	var d = npc._distraction
	var p: Perception = npc._perception
	var trail := Vector3(-4, 0, 9)
	p.investigate_point(trail, false)  # already hunting the player's last known position
	npc._react_distraction(0.1)
	assert_eq(p.state, Perception.State.INVESTIGATING, "the guard keeps investigating")
	assert_eq(p.last_known_position, trail,
		"a guard already on the player's trail ignores the decoy — the lure only works on a guard that hasn't noticed anything")
	_free_guard(npc, d, senses)


func test_react_distraction_is_inert_until_the_distraction_child_exists() -> void:
	_react_instantly()
	var senses := _DecoySenses.new()
	senses.decoy = _decoy(Vector3(6, 0, 3))
	var npc = _guard(senses)
	var d = npc._distraction
	var p: Perception = npc._perception
	npc._distraction = null  # a bare NPC before _build_components
	npc._react_distraction(0.1)
	assert_eq(p.state, Perception.State.UNAWARE, "with no distraction child the facade does nothing (and does not crash)")
	assert_eq(p.last_known_position, Vector3.ZERO, "no investigation point is written without the child")
	npc._distraction = d  # control: the very same guard, once built, does react
	npc._react_distraction(0.1)
	assert_eq(p.state, Perception.State.INVESTIGATING, "control: the built guard reacts to the same decoy")
	_free_guard(npc, d, senses)


# --- NPC._emit_bark -> NpcVoice.emit ---------------------------------------------------------------------------

func test_bark_facade_round_trips_into_npc_voice_and_the_host_latch() -> void:
	var npc = load(NPC_PATH).new()
	var voice := NpcVoice.new()
	voice.host = npc
	add_child_autofree(voice)  # emit() awaits a SceneTree timer; the off-tree host makes it bail before any bubble / TTS
	npc._voice = voice
	var idle_latch: int = npc._bark_until_msec
	npc._emit_bark("", null)
	assert_eq(npc._bark_until_msec, idle_latch, "an unauthored (empty) line stays silent and blocks nothing")
	var asked_at := Time.get_ticks_msec()
	npc._emit_bark("Halt!", null)
	var armed: int = npc._bark_until_msec
	assert_gt(armed, asked_at,
		"a bark requested on the NPC reaches NpcVoice.emit, which blocks further barks on the HOST while its bubble shows")
	npc._emit_bark("Hands where I can see them, nice and slow, right now!", null)
	assert_eq(npc._bark_until_msec, armed,
		"a second bark in the same beat is dropped (one bubble at a time) instead of stacking or extending the first")
	await wait_seconds(0.15)  # let both reaction-delay coroutines unwind at emit()'s lifecycle guard
	npc._voice = null
	npc.free()


# --- WeaponStance.reconcile: out-of-combat reload (C5) ---------------------------------------------------------

## An armed townsperson (NEUTRAL, so it holsters between fights) that fought earlier, now out of combat with its gun
## still drawn and a PARTIAL clip, carrying `spare_clips` pistol clips.
func _stood_down_gunman(spare_clips: int) -> Dictionary:
	var gun := WeaponData.new()
	gun.max_ammo = 10
	gun.caliber = &"pistol"
	var npc = load(NPC_PATH).new()
	npc.disposition = Disposition.Kind.NEUTRAL
	npc.inventory = CharacterInventory.new()
	var gun_item := Item.new()
	gun_item.category = Item.Category.WEAPON
	gun_item.weapon = gun
	npc.inventory.equipped_item = gun_item
	if spare_clips > 0:
		npc.inventory.add(ItemDb.ammo_item_for(&"pistol"), spare_clips)
	var w := _CountingWeapon.new()
	w.inventory = Inventory.new()
	w.inventory.equipped_weapon = gun
	w.ammo = Ammo.new()
	w.ammo.character = npc
	w.ammo.current_weapon = gun
	w.ammo.current_ammo = 4
	w.attack = Attack.new()
	w.attack.holstered = false
	npc._weapon = w
	var stance := WeaponStance.new()
	stance.host = npc
	stance._has_engaged = true
	return {"npc": npc, "weapon": w, "stance": stance}


func _free_gunman(g: Dictionary) -> void:
	var w: _CountingWeapon = g["weapon"]
	var npc = g["npc"]
	g["stance"].free()
	w.attack.free()
	w.ammo.free()
	w.inventory.free()
	npc._weapon = null
	w.free()
	npc.inventory.free()
	npc.free()


func test_stance_holsters_instead_of_dry_reloading_with_no_spare_clips() -> void:
	var g := _stood_down_gunman(0)
	var w: _CountingWeapon = g["weapon"]
	g["stance"].reconcile()
	assert_eq(w.reloads, 0,
		"a partial clip with an EMPTY reserve must not call reload() — it would dry-click every frame (C5)")
	assert_true(w.attack.holstered, "with nothing to reload and the stand-down elapsed, the NPC puts the gun away")
	_free_gunman(g)


func test_stance_tops_up_a_partial_clip_when_spare_clips_exist() -> void:
	var g := _stood_down_gunman(2)
	var w: _CountingWeapon = g["weapon"]
	g["stance"].reconcile()
	assert_eq(w.reloads, 1, "control: with spare clips in the backpack the partial clip is topped up out of combat")
	assert_false(w.attack.holstered, "the gun stays out while it reloads")
	_free_gunman(g)
