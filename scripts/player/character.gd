@abstract
class_name Character
extends CharacterBody3D

## Shared base for all damageable, physics-driven actors — Player and NPC both
## extend this. Provides: HP + death, the per-instance damage-flash material overlay,
## the decaying "blast" impulse system (explosion_velocity) used for rocket jumps /
## launches / ram knockback, and the on-death gore/gib spawn. Subclasses override
## apply_velocity() for their own movement (Player: full controller; NPC: nav-driven
## + drift) but reuse the blast and gore machinery here.
##
## The combat OUTLINE lives on NPC (the non-player base), not here: only non-player
## actors wear it, and each configures its own colour/width. Character just builds the
## flash overlay and exposes _apply_overlay_to_meshes()/_collect_mesh_instances() so a
## subclass (NPC) can chain its outline pass in front of the flash. The Player has no
## outline (flash only).

## Emitted on every damage application (after hp changes). Health UI listens.
signal damaged(current_hp: float, max_hp: float)
## Fired whenever `money` changes via add_money: (new total, signed delta). The player's HUD listens; on an
## NPC nothing usually does — its wallet just accumulates until looted. Route every wallet change through
## add_money so this always fires.
signal money_changed(total: float, delta: float)

@export_group("Economy")
## This character's zorkmids — EVERY character carries a wallet now, and amounts are FRACTIONAL (half a
## zorkmid = 0.5; see Zorkmids). The player spends/earns through the whole economy; an NPC's wallet
## (designer-set here, plus any kill bounties it EARNS — see _award_kill) rides into its lootable corpse,
## so killing a rich enemy pays. Set per NPC in the inspector.
@export var money: float = 0.0

## Change this character's zorkmids by `delta` (negative to spend; fractions fine — 0.5 is half a zorkmid).
## The ONE seam every wallet change routes through — kill bounties, merchant buy/sell, money pickups, wallet
## looting — so listeners (the player's HUD readout + autosave) always fire, and the total stays QUANTIZED
## to Zorkmids.QUANTUM so float drift can never creep into the economy. A zero delta is a no-op.
func add_money(delta: float) -> void:
	if is_zero_approx(delta):
		return
	money = snappedf(money + delta, Zorkmids.QUANTUM)
	money_changed.emit(money, delta)

## Kill-bounty hook, duck-typed by _award_kill: this character downed an enemy — pay the 1 / 2 / 4 zorkmid
## bounty (and the collateral extras) into its wallet. EVERY character earns now, not just the player: an
## NPC's winnings sit in its wallet until the player loots its corpse.
func reward_kill(amount: float) -> void:
	add_money(amount)
## Emitted once when this character dies (from take_damage). NPC wires this to its
## death SFX + freeze-frame + the cha-ching kill reward.
signal died()

@export_group("Physics & Blast")
## Divisor applied to explosion_velocity AFTER move_and_slide each frame — the
## per-frame "give-back" that bleeds a blast impulse down over time. Larger = blast
## decays faster. Must stay > 1 or the blast would never settle.
@export var blast_damp_divisor: float = 1.12

@export_group("Health & Stats")
## Starting/maximum health (HP). hp is seeded from this in _ready and damage can't heal past it.
## ENDURANCE on the stat sheet adds to this at spawn (see _apply_stats). Per-character in the inspector.
@export var max_hp: float = 4.0
var hp: float
## This character's RPG stat sheet — set in the inspector by a designer (every Character, player AND NPC,
## has one). null = a neutral baseline sheet, so an unsheeted character is unchanged. Spawn effects
## (endurance->max_hp, strength->carry_capacity) stamp in _apply_stats during _ready; the live effects are
## read at their own seams (Merchant prices, AimSway steadiness, Reputation scaling, dialogue skill checks).
@export var stats: CharacterStats = null
@export_group("Fall Damage")
## Downward speed (m/s) a landing must exceed before it does fall damage.
@export var fall_damage_min_speed: float = 16.0
## HP lost per m/s of downward speed above the safe speed.
@export var fall_damage_per_speed: float = 0.5
@export_group("Encumbrance")
## Fraction of carry_capacity you haul for FREE — below this load ratio there's no penalty at all (¼ by default).
@export var encumbrance_free_fraction: float = 0.25
## Load ratio at/above which the penalties hit their MAX. From free_fraction the penalty ramps up LINEARLY to here.
@export var encumbrance_full_fraction: float = 1.0
## Move-speed multiplier at FULL load (lerped from 1.0 at free_fraction). Lower = a heavier slog.
@export var min_load_speed_mult: float = 0.4
## Jump-height multiplier at full load — heavier = lower hops.
@export var min_load_jump_mult: float = 0.5
## External-launch multiplier (grapple fling / explosion knockback) at full load — heavier = flung less.
@export var min_load_launch_mult: float = 0.4
## Max carry weight before this actor reads as ENCUMBERED (the UI flag). The gradual penalties above ramp in
## BEFORE this; this is just the "overloaded" line + the reference for the load ratio. Tunable per character.
@export var carry_capacity: float = 20.0
@export_group("Appearance")
## The visual model root for this actor. Every MeshInstance3D under it gets the damage-flash overlay (and
## NPC's combat outline) applied in _ready, and the gore/decal raycasts hang off it. Wire to the body mesh.
@export var mesh: Node3D
const BLOOD_SPLAT_DECAL = preload("uid://dg5ui5is8sakg")
const CHARACTER_DUST = preload("uid://um6f8g8g6l7v")
const FLASH_OVERLAY_SHADER = preload("res://resources/shaders/flash_overlay.gdshader")
# Hit-flash feel numbers live on GameSettings.effects (Hit flash group) -- shared by Player + NPC, designer-tunable.

@export_group("Audio")
## Low, heavy one-shot layered under the audio-desaturation duck when the PLAYER takes a real,
## non-lethal hit — the "car door slammed underwater" thud that gives a body to the flinch. Played
## 2D (non-positional) via AudioManager since it's a first-person felt-impact, not a world sound.
## Gated strictly to the Player group so NPC hits never trigger it. PLACEHOLDER: defaults to the
## project's wooden-thud — swap in a bespoke underwater-car-door asset here when one is authored.
@export var damage_thud: AudioStream = preload("uid://c23166qlxcvbi")

## Decaying impulse layered on top of normal movement velocity. Systems ADD to it
## (rocket self-knockback, melee dash, slide-jump, pinball ram bounce, enemy
## knockback); apply_blast() + apply_velocity() consume and decay it. Lets external
## forces fling the actor without permanently overwriting controller velocity.
var explosion_velocity: Vector3

## Grace countdown that keeps a blast "alive" briefly even while grounded, so a
## ground-level blast (e.g. the ram bounce) isn't instantly zeroed by the floor
## check in apply_blast(). Re-armed whenever explosion_velocity is sizable.
var _blast_timer: float = 0.0
## Latched on the killing hit so take_damage()/gore can't fire twice when multiple
## hits land in one frame (e.g. a shotgun's pellets).
var _dead: bool = false
## All-crit kill tracking — stays true only if every point of damage this actor took was a
## crit (headshot). killed_by_only_crits() reads these on death to fire the applause reward.
var _took_any_hit: bool = false
var _all_crits: bool = true
## The most recent attacker that landed an attributed hit, and when (ms). Separate from NPC._last_attacker
## (sticky targeting) so the two lifecycles don't interfere — this one is read only by _award_kill.
var _credit_attacker: Node = null
var _credit_attacker_msec: int = 0
var _flash_material: ShaderMaterial
var _flash_tween: Tween

## Outward-spawning responsibilities split off this coordinator into code-built Node3D children
## (see _ready). Each holds a back-ref to this host and reads our @exports/consts off it, so the
## editor/.tscn keep configuring them on the root. Null until _ready runs — every facade that
## delegates to one of these null-guards first, so an off-tree instance (Class.new() in a unit
## test, where _ready never fires) keeps the monolith's no-op behaviour.
var _gore_spawner: GoreSpawner
var _dust_spawner: DustSpawner
var _damage_thud_node: DamageThud

## The character's backpack — generic item storage (weapons now; consumables/ammo later). Built in
## _ready so Player and NPC both carry one. DISTINCT from the equipped-weapon hub `Inventory`
## (weapon_system.inventory): this is `character.inventory`. Null off-tree (_ready skipped) — every
## caller that touches it null-guards, matching the other code-built children.
var inventory: CharacterInventory

## The stat sheet, never null — a bare/off-tree character lazily gets a fresh baseline sheet. Every stat
## consumer (Merchant, AimSway, Reputation, DialogueView, _apply_stats) reads through this, so a missing
## resource can't crash a price, a skill check, or spawn.
func stats_or_default() -> CharacterStats:
	if stats == null:
		stats = CharacterStats.new()
	return stats

## Spawn-time stat effects: ENDURANCE adjusts max_hp (run BEFORE _ready seeds hp from max_hp) and STRENGTH
## adjusts carry_capacity. The live effects read the sheet at their own seams instead. Called as the FIRST
## line of _ready so every concrete actor (NPC stamps its profile first, then super() lands here) gets it.
func _apply_stats() -> void:
	var s := stats_or_default()
	max_hp = maxf(1.0, max_hp + s.max_hp_bonus())
	carry_capacity = maxf(0.0, carry_capacity + s.carry_bonus())

func _ready():
	_apply_stats()  # ENDURANCE/STRENGTH stamp max_hp + carry_capacity BEFORE hp seeds from max_hp
	hp = max_hp
	_setup_overlay_chain()
	# Build the outward-spawning helpers AFTER the overlay chain so the order of side effects in
	# _ready is unchanged. Each gets its host ref BEFORE add_child so it's wired the instant it
	# enters the tree. NPC/Player both call super() first, so these run for every concrete actor.
	_gore_spawner = GoreSpawner.new()
	_gore_spawner._host = self
	add_child(_gore_spawner)
	_dust_spawner = DustSpawner.new()
	_dust_spawner._host = self
	add_child(_dust_spawner)
	_damage_thud_node = DamageThud.new()
	_damage_thud_node._host = self
	add_child(_damage_thud_node)
	# The backpack every actor carries. Built last so it's ready for the subclass seed (player/NPC fill
	# it after super()). Equip seam: equipping a weapon-item makes the container ask us to draw it via
	# equip_weapon_requested -> the overridable _on_equip_weapon_requested hook below (player routes it
	# through SwapWeapons, NPC straight to its weapon hub).
	inventory = CharacterInventory.new()
	inventory.name = &"CharacterInventory"
	add_child(inventory)
	inventory.equip_weapon_requested.connect(_on_equip_weapon_requested)

## Build the per-instance damage-flash material and apply it as the material_overlay on every
## MeshInstance3D under `mesh`. Godot pattern: material_overlay renders on top of each surface's
## own material without modifying it. Built once in _ready; flash_red() and the death tint then
## drive only the flash uniform. Subclasses that want an extra pass IN FRONT of the flash (NPC's
## combat outline) override _ready, call this, then chain their pass via _flash_material as the
## outline's next_pass and re-apply with _apply_overlay_to_meshes().
func _setup_overlay_chain() -> void:
	if not mesh:
		return
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = FLASH_OVERLAY_SHADER
	_flash_material.set_shader_parameter("flash_strength", 0.0)
	_apply_overlay_to_meshes(_flash_material)

## Set `overlay` as material_overlay on every MeshInstance3D under `mesh`. Shared so a subclass
## (NPC) can re-apply once it has chained its outline pass onto the flash material.
func _apply_overlay_to_meshes(overlay: Material) -> void:
	if not mesh:
		return
	var targets: Array[MeshInstance3D] = []
	_collect_mesh_instances(mesh, targets)
	for m in targets:
		# If the look-at talk highlight is active on this mesh, its real overlay is STASHED in meta (the
		# white highlight sits in the live slot). Update the stash so look-away restores the NEW overlay —
		# else a provoke / disposition recolour is lost when the highlight clears (a friendly turned
		# hostile would snap back to its old green rim on look-away instead of staying red).
		if m.has_meta(&"talk_prev_overlay"):
			m.set_meta(&"talk_prev_overlay", overlay)
		else:
			m.material_overlay = overlay

func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out)

## Flash to acknowledge a hit. Base flashes the WHOLE body (the one shared overlay). NPC overrides it to
## flash only the SPECIFIC swapped part the shot landed on (head / torso / arm / leg), falling back to the
## whole-body flash for an unlocated hit (fall / explosion) or a body with no swapped parts. hit_pos is the
## world-space contact point (Vector3.INF when the damage carries no location).
func _flash_damage(_hit_pos: Vector3) -> void:
	flash_red()

func flash_red() -> void:
	if not _flash_material:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = _build_flash_tween(_flash_material)

## Drive one flash material's strength up to the peak then back to 0 — the red hit pulse. Factored out so a
## subclass can pulse a PER-PART flash material (NPC's located-hit flash) on its own tween, independent of the
## whole-body _flash_tween. Returns the running tween so the caller can store/kill it.
func _build_flash_tween(mat: ShaderMaterial) -> Tween:
	var fx := GameSettings.effects
	var t := create_tween()
	t.tween_property(mat, "shader_parameter/flash_strength", fx.hit_flash_peak_strength, fx.hit_flash_up_time)
	t.tween_interval(fx.hit_flash_hold_time)  # SUSTAIN the peak so the hit flash reads as a strong pop, not a 1-frame blip
	t.tween_property(mat, "shader_parameter/flash_strength", 0.0, fx.hit_flash_down_time)
	return t

func take_damage(_amount: float, was_crit: bool = false, attacker: Node = null, hit_pos: Vector3 = Vector3.INF):
	# Guard: prevents multi-hit kills (e.g. shotgun's 9 pellets in one frame)
	# from triggering gore/die multiple times. queue_free is deferred so the
	# body still exists in the same frame and would otherwise receive every
	# subsequent pellet, each one firing 100 rain drops + 6 gibs + a death SFX.
	if _dead:
		return
	# CT-2 mitigation: flat armour soaks off the top, then damage_reduction scales the rest. Defaults 0/0 = no
	# change. Only a positive incoming hit is mitigated (a 0 / heal passes through); floored at 0 (armour can't heal).
	if _amount > 0.0:
		_amount = maxf(0.0, (_amount - armor_flat) * (1.0 - damage_reduction))
	# All-crit kill bookkeeping: any non-crit damage (body shot, fall, explosion) disqualifies it.
	_took_any_hit = true
	if not was_crit:
		_all_crits = false
	_flash_damage(hit_pos)
	hp -= _amount
	damaged.emit(hp, max_hp)
	# Aggro hook: who dealt this hit (null for fall/explosion/unknown). Base no-op; NPC overrides
	# it to provoke when a non-hostile NPC is shot by the player. Runs even on the lethal hit —
	# harmless (provoke on a corpse is a no-op via the _dead latch above on the next hit).
	_on_damaged_by(attacker, was_crit, _amount)
	# Remember who last hit us (and when), so a player-caused-but-unattributed follow-up kill — a fall off a
	# ledge we were knocked from, a delayed blast — can still credit them the bounty (see _award_kill).
	if attacker != null:
		_credit_attacker = attacker
		_credit_attacker_msec = Time.get_ticks_msec()
	# Locational/limb condition + crippling — only for hits that carry a hit point (not fall/explosion).
	if hit_pos.is_finite():
		_apply_limb_damage(hit_pos, _amount, attacker)
	if hp <= 0:
		_dead = true
		_award_kill(attacker, was_crit)  # pay the killer a zorkmid bounty (player only; see _award_kill)
		gore()
		die()
	else:
		# Non-lethal, real hit: punch in the low "underwater car door" thud. Only on the survive
		# branch so it doesn't double up under the death SFX/gore, and only for the player (gated
		# inside) so NPC hits stay silent here.
		_play_damage_thud()

func die():
	died.emit()
	queue_free()

## Play the low, heavy damage thud. Thin facade over the DamageThud child (which holds the cooldown
## throttle, gates on the Player group, and routes 2D through AudioManager). Null off-tree (_ready
## skipped) — then this no-ops, exactly as the monolith did when called before it had a stream/clock.
func _play_damage_thud() -> void:
	if _damage_thud_node == null:
		return
	_damage_thud_node.play()

## True if this actor took at least one hit and EVERY point of damage was a crit (headshot) — no
## body shots, fall, or explosion damage mixed in. The enemy's Death node checks this to applaud.
func killed_by_only_crits() -> bool:
	return _took_any_hit and _all_crits

## Pay the killer a zorkmid bounty when this character is downed: 4 for an all-headshot kill, 2 when the
## KILLING blow was a headshot, else 1. Duck-typed via reward_kill, which EVERY Character now exposes — the
## player banks it, an NPC's winnings ride in its wallet until looted (NPC-vs-NPC fights move money around
## the world). The self-bounty guard below still blocks paying yourself for your own blast/fall.
func _award_kill(attacker: Node, killing_was_crit: bool) -> void:
	var killer := attacker
	# Unattributed lethal hit (a fall off a ledge, a stray blast): credit the most recent real attacker if it
	# was within the kill-credit window (GameSettings.economy.kill_credit_window_ms) — so a player-CAUSED fall /
	# explosion pays, but an enemy that wanders off a cliff on its own doesn't (no recent attacker, or it
	# wasn't the player).
	if (killer == null or not killer.has_method(&"reward_kill")) \
			and is_instance_valid(_credit_attacker) \
			and Time.get_ticks_msec() - _credit_attacker_msec <= GameSettings.economy.kill_credit_window_ms:
		killer = _credit_attacker
	if killer == null or killer == self or not killer.has_method(&"reward_kill"):
		return  # no self-bounty (a player caught in its own blast/fall doesn't pay itself)
	# Bounty sizes are DESIGNER knobs — tune them in resources/tuning/EconomySettings.tres, not here.
	var eco := GameSettings.economy
	var bounty := eco.all_headshots_kill_bounty if killed_by_only_crits() \
			else (eco.headshot_kill_bounty if killing_was_crit else eco.kill_bounty)
	killer.reward_kill(bounty)

func heal(_amount: float):
	hp = min(hp + _amount, max_hp)
	damaged.emit(hp, max_hp)

## Hook for a directional damage indicator on the wielder that was hit, aimed at the source.
## Base is a no-op (enemies don't show one); the Player overrides it to ping its aim radial toward
## `source` (the shooter). `source` is optional so unattributed hits (explosions) can still call it.
func indicate_damage_from(_world_pos: Vector3, _source: Object = null) -> void:
	pass

## Hook: THIS character just took a hit from `attacker` (null if the source is unknown — fall
## damage, an explosion, a corpse-less projectile). Base is a no-op; NPC overrides it to flip a
## non-hostile NPC hostile when the PLAYER is the attacker (aggro-on-attack). Separate from the
## `damaged` signal so we don't change that signal's arity (the health UI + enemy scene rely on it).
func _on_damaged_by(_attacker: Node, _was_crit: bool = false, _amount: float = 0.0) -> void:
	pass

## Hook for when THIS character lands a hit on something, so a hitmarker can flash. Base is a
## no-op (enemies don't show one); the Player overrides it.
func on_dealt_hit(_headshot: bool = false, _hp_frac: float = 1.0) -> void:
	pass

@export_group("Mitigation")
## Flat damage soaked off the TOP of every incoming hit (a second defense axis besides HP) — armour. Applied
## before damage_reduction in take_damage. 0 = no armour (the default, so nothing changes).
@export var armor_flat: float = 0.0
## Fraction (0..0.95) of the post-armour damage shrugged off — percentage damage reduction. Capped below 1.0 so
## a character is never fully invulnerable. 0 = no reduction (the default).
@export_range(0.0, 0.95) var damage_reduction: float = 0.0
## WEAKPOINT multipliers, keyed by BodyPart (TORSO/HEAD/ARMS/LEGS) -> damage multiplier for a hit in that zone.
## Empty = 1.0 everywhere (inert default). e.g. { BodyPart.TORSO: 3.0 } = a soft core that takes triple. The
## PLAYER leaves this empty (its head-one-shot immunity stays), so weakpoints are an ENEMY-authoring tool.
@export var zone_damage_mult: Dictionary = {}

@export_group("Limb & Locational Damage")
## A hit at or above this height — measured in the character's LOCAL frame, so it stays correct
## as the body yaws — counts as a headshot. Tune per enemy to sit at the base of the skull
## The enemy's collision capsule is 2 m tall CENTRED on the origin (local y -1..+1), so its
## head / top cap is ~0.5..1.0 — hence the 0.5 default. Raise it to tighten the head zone, or
## tune per enemy if a body's origin/height differs.
@export var head_local_y: float = 0.4
## Locational/limb zones (LOCAL frame): below leg_local_y = legs; between it and head_local_y = torso,
## unless |local x| exceeds arm_local_x (a side hit = arms); head is >= head_local_y.
@export var leg_local_y: float = -0.35
## Lateral half-width (LOCAL metres) splitting arms out of the torso band: a torso-height hit with
## |local x| at or beyond this counts as an arm. Larger = wider torso, smaller arm zones.
@export var arm_local_x: float = 0.18
## Each limb's condition pool as a fraction of max_hp — crippled once that much LOCATED damage hits it.
@export var limb_condition_frac: float = 0.6
## Movement multiplier while a leg is crippled (Fallout-style limp).
@export var crippled_leg_speed_mult: float = 0.5
## Extra pellet spread (radians) on THIS actor's shots while an arm is crippled.
@export var crippled_arm_spread: float = 0.06
## Sound played (positional) when ANY limb is crippled — a sharp crack. Placeholder = crate break; swap.
@export var cripple_sound: AudioStream
## Playback volume (decibels) for cripple_sound; 0 = unchanged, negative = quieter.
@export var cripple_sound_volume_db: float = 0.0

enum BodyPart { TORSO, HEAD, ARMS, LEGS }
var _limb_condition: Dictionary = {}   ## BodyPart -> remaining condition (lazy-seeded from the pool)
var _crippled: Dictionary = {}         ## BodyPart -> bool

## True if a world-space hit point lands in this character's head zone. Attackers multiply their
## damage by the weapon's headshot_multiplier when this returns true.
func is_headshot(world_pos: Vector3) -> bool:
	return to_local(world_pos).y >= head_local_y

## Classify a world-space hit into a body part in the actor's LOCAL frame (stays correct as the body
## yaws). Height splits head/torso/legs; lateral offset splits arms out of the torso band.
func body_part_at(world_pos: Vector3) -> int:
	var lp := to_local(world_pos)
	if lp.y >= head_local_y:
		return BodyPart.HEAD
	if lp.y < leg_local_y:
		return BodyPart.LEGS
	if absf(lp.x) >= arm_local_x:
		return BodyPart.ARMS
	return BodyPart.TORSO

## CT-2 weakpoint: the damage multiplier for a world-space hit, from zone_damage_mult keyed by BodyPart. Empty
## map (the default, incl. the player) -> 1.0 everywhere, and the empty short-circuit means the transform
## classifier (body_part_at -> to_local) is never touched in the common case (off-tree-safe). Un-located hits
## (fall/explosion, non-finite pos) are 1.0.
func zone_damage_mult_at(world_pos: Vector3) -> float:
	if zone_damage_mult.is_empty() or not world_pos.is_finite():
		return 1.0
	return float(zone_damage_mult.get(body_part_at(world_pos), 1.0))

## A located hit chips the struck limb's condition; emptying it cripples the limb (legs limp, arms widen
## your shots, head staggers). Torso never cripples. Skipped for un-located damage (fall/explosion).
func _apply_limb_damage(world_pos: Vector3, amount: float, attacker: Node = null) -> void:
	var part := body_part_at(world_pos)
	if part == BodyPart.TORSO or bool(_crippled.get(part, false)):
		return
	var pool: float = _limb_condition.get(part, max_hp * limb_condition_frac)
	pool -= amount
	_limb_condition[part] = pool
	if pool <= 0.0:
		_crippled[part] = true
		_on_limb_crippled(part, attacker)

func is_limb_crippled(part: int) -> bool:
	return bool(_crippled.get(part, false))

## True if ANY limb is crippled OR any limb's condition pool is below full — i.e. there is limb damage a
## Healer would mend. The pools are lazy-seeded, so an undamaged limb has no entry (treated as full).
func has_limb_damage() -> bool:
	for crippled in _crippled.values():
		if crippled:
			return true
	var full := max_hp * limb_condition_frac
	for cond in _limb_condition.values():
		if cond < full:
			return true
	return false

## Clear ALL limb damage — un-cripple every limb and reset its condition pool (re-seeds full on the next
## located hit). Used by the Healer's pay-to-heal; HP itself is restored separately via heal().
func heal_limbs() -> void:
	_limb_condition.clear()
	_crippled.clear()

## Move-speed multiplier from limb state (crippled legs limp). Multiply locomotion speed by this.
func limb_move_multiplier() -> float:
	return crippled_leg_speed_mult if is_limb_crippled(BodyPart.LEGS) else 1.0

## Current backpack carry weight (0 if there's no backpack — an off-tree unit actor).
func current_carry_weight() -> float:
	return inventory.total_weight() if inventory != null else 0.0

## True when the backpack is over carry_capacity — the actor reads as ENCUMBERED (the UI flag). The gradual
## speed / jump / launch penalties ramp in BEFORE this point; see heaviness().
func is_encumbered() -> bool:
	return inventory != null and inventory.total_weight() > carry_capacity

## Load ratio: carried weight / carry_capacity (0 = empty, 1 = at max). 0 when this actor has no capacity.
func encumbrance_load_ratio() -> float:
	if carry_capacity <= 0.0:
		return 0.0
	return current_carry_weight() / carry_capacity

## HEAVINESS, 0 (light) .. 1 (fully loaded): ramps LINEARLY from 0 at encumbrance_free_fraction of capacity
## to 1 at encumbrance_full_fraction. Below the free fraction you carry weightlessly. Higher carry_capacity
## (strength) makes the SAME weight a smaller ratio, so the strong stay lighter. Every penalty scales off this.
func heaviness() -> float:
	var span: float = maxf(encumbrance_full_fraction - encumbrance_free_fraction, 0.0001)
	return clampf((encumbrance_load_ratio() - encumbrance_free_fraction) / span, 0.0, 1.0)

## Move-speed multiplier from load (1.0 light -> min_load_speed_mult fully loaded). Multiply locomotion speed
## by this, alongside limb_move_multiplier(); player + NPC locomotion both apply it.
func encumbrance_move_multiplier() -> float:
	return lerpf(1.0, min_load_speed_mult, heaviness())

## Aggregate move-speed multiplier from a StatusEffectManager child (slow/haste effects), or 1.0 if none —
## multiplied into locomotion alongside limb_move_multiplier / encumbrance_move_multiplier (both player + NPC).
## Duck-typed (no hard StatusEffectManager dependency on this core class) and re-scanned each call so a manager
## added at runtime (the Player auto-creates one for consumable buffs) is picked up.
func status_move_multiplier() -> float:
	for c in get_children():
		if c.has_method(&"speed_multiplier") and c.has_method(&"apply_effect"):
			return c.speed_multiplier()
	return 1.0

## Jump-height multiplier from load (1.0 light -> min_load_jump_mult fully loaded). Scales jump velocity.
func encumbrance_jump_multiplier() -> float:
	return lerpf(1.0, min_load_jump_mult, heaviness())

## External-launch multiplier from load (1.0 light -> min_load_launch_mult fully loaded). Scales the kick a
## grapple fling / explosion gives you — a heavy character is harder to throw around.
func encumbrance_launch_multiplier() -> float:
	return lerpf(1.0, min_load_launch_mult, heaviness())

## Extra shot spread (radians) from limb state (a crippled arm shakes your aim). Added to pellet spread.
func limb_spread_penalty() -> float:
	return crippled_arm_spread if is_limb_crippled(BodyPart.ARMS) else 0.0

## Hook: a limb was just crippled by `attacker` (null if unattributed). Base plays the cripple SFX
## (player + NPC) and routes head crippling to the overridable stagger hook. NPC extends this to cry out
## "My [part]!" + (when the player did it) toast the player; the Player toasts its own head cripple.
func _on_limb_crippled(part: int, attacker: Node = null) -> void:
	# Skip the cripple SFX on the LETHAL blow: _apply_limb_damage runs one frame before the hp<=0/die()
	# branch, so a killing hit that also empties a limb would otherwise stack the cripple sound on top of
	# the death gore/SFX. hp is already decremented here, so hp<=0 (or the _dead latch from a prior pellet)
	# means this hit kills — let the death cinematic own the audio.
	if cripple_sound != null and is_inside_tree() and hp > 0 and not _dead:
		AudioManager.play_sfx(global_position, cripple_sound, cripple_sound_volume_db)
	if part == BodyPart.HEAD:
		_on_head_crippled(attacker)

## Overridable: head crippled by `attacker`. Base no-op; the Player pulses the hurt feedback for a
## concussion read + toasts it.
func _on_head_crippled(_attacker: Node = null) -> void:
	pass

## Hook: the backpack just asked to draw `weapon` (a weapon-item was equipped from it). Base no-op; the
## Player routes it through SwapWeapons (keeps the swap timer/anim), the NPC hands it straight to its
## weapon hub. Connected to inventory.equip_weapon_requested in _ready.
func _on_equip_weapon_requested(_weapon: WeaponData) -> void:
	pass

## True if this character hasn't noticed the attacker yet, so the hit earns the sneak-attack
## bonus. Base is false (the player is never an ambush target); enemies override it via Perception.
func is_off_guard() -> bool:
	return false

## Fall damage: a landing whose downward speed tops fall_damage_min_speed costs HP, scaling
## with the excess. Shared by the player (its landing block) and enemies (Enemy.apply_velocity).
func _apply_fall_damage(fall_speed: float) -> void:
	# Allies (companions following the player) are immune to fall damage — they keep up via teleport and
	# shouldn't be punished by dying to terrain. has_method-guarded so only NPCs answer is_following().
	if has_method(&"is_following") and call(&"is_following"):
		return
	var dmg := FallDamage.hp_loss(fall_speed, fall_damage_min_speed, fall_damage_per_speed)
	if dmg > 0:
		take_damage(dmg)

func gravity(delta: float):
	if !is_on_floor():
		velocity += get_gravity() * delta

## Standard move step. Adds the blast impulse to velocity for THIS frame's move,
## slides, pushes any rigid bodies hit, then removes a fraction (1/blast_damp_divisor)
## of the blast so it bleeds off over subsequent frames instead of persisting.
## pre_move_velocity is captured BEFORE move_and_slide because the slide response
## zeroes velocity into surfaces, and _push_interactables needs the original speed.
func apply_velocity():
	# move_and_slide needs a live physics space; bail when we're not in one (e.g. a unit
	# test instantiates the actor outside a World3D yet still ticks _physics_process).
	var world := get_world_3d()
	if world == null or not world.space.is_valid():
		return
	velocity += explosion_velocity
	var pre_move_velocity := velocity
	move_and_slide()
	_push_interactables(pre_move_velocity)
	velocity -= explosion_velocity / blast_damp_divisor

# --- Weapon-host aim contract ---
# A hosted Weapon component reads these to know where its hitscan/projectiles originate,
# which way they travel, and the basis its pellet spread rotates around — instead of
# reaching for a Camera3D. So the same Weapon works whether a Player (camera aim) or an
# Enemy (AI aim) wields it. Defaults fire straight forward from this body; subclasses
# override (Player uses its camera).
func get_aim_origin() -> Vector3:
	return global_position

func get_aim_direction() -> Vector3:
	return -global_basis.z

func get_aim_basis() -> Basis:
	return global_transform.basis

# Fire-feedback hook: a hosted Weapon calls this once per shot so the wielder can react
# (screen shake, etc.). Default no-op — an enemy needs none. Player overrides.
func on_weapon_fired(_weapon: WeaponData) -> void:
	pass

# Post-shot outcome hook: a hosted Weapon calls this once AFTER a shot's trace fully resolves, with
# whether the shot connected with an NPC. Lets the wielder react to the OUTCOME — the player uses it to
# suppress its reckless-fire bystander remark when the shot actually hit someone. Default no-op. Player
# overrides.
func on_shot_resolved(_weapon: WeaponData, _hit_npc: bool) -> void:
	pass

# The full-screen hit-flash node briefly shown on an instant-hit shot, or null if the
# wielder has none (only the player has a camera to flash). Player overrides.
func get_hit_flash() -> Node3D:
	return null

# Launch/dash feedback hook (a scoped-attack launch, e.g. the melee air-dash): the wielder
# reacts with its own whoosh — FOV punch, shake. Default no-op. Player overrides.
func on_weapon_launched(_weapon: WeaponData) -> void:
	pass

func _push_interactables(pre_move_velocity: Vector3) -> void:
	# CharacterBody3D doesn't push RigidBody3D on its own. After move_and_slide,
	# apply an impulse to any non-frozen rigid body we collided with, scaled by
	# how fast we were moving into it. Uses the PRE-move velocity because the
	# collision response already zeroed `velocity` into the body by now.
	var force: float = GameSettings.physics_damage.character_push_force
	if force <= 0.0:
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var collider := c.get_collider()
		if collider is RigidBody3D:
			var rb := collider as RigidBody3D
			if rb.freeze:
				continue
			var push_dir := -c.get_normal()
			var into_speed := pre_move_velocity.dot(push_dir)
			if into_speed <= 0.0:
				continue
			var contact_offset := c.get_position() - rb.global_position
			rb.apply_impulse(push_dir * into_speed * force, contact_offset)

## Per-frame blast bookkeeping, called before apply_velocity(). A sizable blast
## (re)arms the grace timer so a fresh impulse survives at least blast_grace_timer
## seconds even on the floor. Once grounded AND grace has elapsed, the blast is
## hard-zeroed (so you don't keep sliding after landing). While airborne or within
## grace it eases toward zero frame-rate-independently, snapping to zero below a min
## magnitude to avoid an endless tiny residual.
func apply_blast():
	if explosion_velocity.length() > GameSettings.physics_damage.blast_min_magnitude:
		_blast_timer = GameSettings.physics_damage.blast_grace_timer

	if is_on_floor() and _blast_timer <= 0.0:
		explosion_velocity = Vector3.ZERO
		return

	var dt := get_physics_process_delta_time()
	_blast_timer -= dt
	var blast_t := 1.0 - pow(1.0 - GameSettings.physics_damage.blast_decay_rate, dt * GameSettings.player_movement.smoothing_reference_fps)
	explosion_velocity = explosion_velocity.lerp(Vector3.ZERO, blast_t)
	if explosion_velocity.length() < GameSettings.physics_damage.blast_min_magnitude:
		explosion_velocity = Vector3.ZERO

## Base actor step — Enemy uses this; Player overrides _physics_process entirely.
## Order is load-bearing: gravity first so the frame's downward accel is in velocity,
## apply_blast() next to arm/decay the impulse, apply_velocity() last to add the
## blast and move. Do not reorder.
func _physics_process(delta: float) -> void:
	gravity(delta)
	apply_blast()
	apply_velocity()

## Spawn the floor blood-splat decal beneath this actor (on death). Thin facade over the GoreSpawner
## child, which holds the down-raycast + surface-aligned decal placement. Null off-tree (_ready
## skipped) — then this no-ops, exactly as the monolith's is_inside_tree() guard did off-tree.
func spawn_blood_decal() -> void:
	if _gore_spawner == null:
		return
	_gore_spawner.spawn_blood_decal()

@export_group("Gore & Death")
## Blood-particle emitter node fired on death (its .particles() spews the death gore rain). Wire to the
## body's bloody-mess node; null = no blood burst on death (decal + gibs + ragdoll still fire).
@export var bloody_mess: Node3D

# Gore-gib system: when a character dies, spawn a handful of interactable
# rigid bodies that fly outward. The gib's visuals, mesh, sounds, mass,
# data resource (incl. destroy particle), and outline are all editable in
# res://scenes/effects/gore_gib.tscn. Per-spawn we only randomize position,
# velocity, rotation, and a fragility roll; the spawn counts/velocities/
# lifetime knobs live in resources/tuning/EffectsSettings.tres (gib_*).
## PackedScene spawned in bulk on death as the flying gore gibs (see the gore-gib note above). Null = no gibs.
@export var gib_scene: PackedScene = preload("uid://bgore1gib0scn")
## Optional rigged-skeleton corpse spawned on death; it ragdolls + flies the way the kill knocked
## us. Assign skeleton_ragdoll.tscn here (see scripts/effects/ragdoll.gd). Null = no corpse.
@export var ragdoll_scene: PackedScene

## Fire the full on-death gore burst — floor decal, blood-particle burst, nearby-player ping, gibs,
## then the ragdoll corpse. Thin facade over the GoreSpawner child (which preserves that exact order
## and reads our transform/velocity/bloody_mess/scenes off this host). Null off-tree (_ready skipped)
## — then this no-ops, matching a bare instance that never spawns gore. take_damage() calls this only
## on the lethal branch, which the unit tests deliberately never reach.
func gore() -> void:
	if _gore_spawner == null:
		return
	_gore_spawner.run()

## Spawn the outward-flying gib rigid bodies. Thin facade over the GoreSpawner child. Null off-tree
## (_ready skipped) — then this no-ops, exactly as the monolith returned early on a null gib_scene.
func spawn_gibs() -> void:
	if _gore_spawner == null:
		return
	_gore_spawner.spawn_gibs()

## Ping nearby players that this actor died so their on-camera blood splatter + death shake fire.
## Thin facade over the GoreSpawner child. Kept on the root because test_smoke probes it via
## has_method on a freshly added Character. Null off-tree (_ready skipped) — then this no-ops.
func _notify_nearby_players_of_death() -> void:
	if _gore_spawner == null:
		return
	_gore_spawner._notify_nearby_players_of_death()

## Kick up a ground dust puff (jump/land/slide). Thin facade over the DustSpawner child, which
## holds the down-raycast + particle setup. Null off-tree (_ready skipped) — then this no-ops,
## exactly as the monolith's is_inside_tree() guard did when called on a bare instance.
func spawn_dust(intensity: float = 1.0) -> void:
	if _dust_spawner == null:
		return
	_dust_spawner.spawn(intensity)
