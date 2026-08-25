@abstract
class_name Character
extends CharacterBody3D

const ModelResourceUtil = preload("res://scripts/components/model_resource.gd")

## Shared base for all damageable, physics-driven actors — Player and NPC both
## extend this. Provides: HP + death, the per-instance damage-flash material overlay,
## the decaying "blast" impulse system (explosion_velocity) used for rocket jumps /
## launches / ram knockback, and the on-death gore/gib spawn. Subclasses override
## apply_velocity() for their own movement (Player: full controller; NPC: nav-driven
## + drift) but reuse the blast and gore machinery here.
##
## The combat OUTLINE lives on NPC (the non-player base), not here: only non-player
## actors wear it, and each configures its own colour/width. Character just builds the
## flash overlay and exposes _apply_overlay_to_meshes() (collecting meshes via
## TalkHelpers.collect_meshes) so a subclass (NPC) can chain its outline pass in front of
## the flash. The Player has no
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

# --- THE PAYMENT SEAM — the ONE chokepoint every priced transaction in the game goes through ---------------
# Four methods, one rule: `can_pay` is the sole affordability predicate and `charge` is the sole debit. Every
# station's gate AND every screen's affordability dimming read the SAME pair, so a row can never look dead
# while the till would have served it (or the reverse). Before this seam each site hand-rolled
# `player.money >= cost` + `add_money(-cost)`, which is why the free-service and negative-wallet cases kept
# drifting apart between the gate and the display.
#
# THE BASE RAIL IS A PLAIN WALLET. An NPC has no bank account and no credit line and never will — the account
# lives on the GameState autoload, not on any Character — so that isolation is STRUCTURAL, not a guard someone
# can forget. `Player` overrides these four with the cash -> savings -> credit logic.
#
# ⭐`allow_credit` IS THE TILL'S POLICY, NOT THE PLAYER'S RAIL. Every method here carries it so a counter that
# refuses to lend can say so ONCE and have the gate, the quote and the UI dim all obey the same answer — the
# whole reason the seam exists. False means "this till funds a sale from cash and banked savings only; it will
# not push the account past zero onto the credit line", and it is INDEPENDENT of which rail the player armed
# (GameState.payment_method): arming CREDIT at an ATM cannot make a cash-only counter lend. It defaults TRUE, so
# every existing caller and every duck-typed one-argument call is byte-identical.
#
# WHY A POLICY ARGUMENT RATHER THAN A SECOND PREDICATE: `can_pay` must stay the ONE affordability answer. A
# parallel `can_pay_no_credit` would be a second source of truth for the same question, and the two would drift
# exactly the way the hand-rolled `money >= cost` sites drifted before this seam existed.
#
# The base wallet has no credit line at all, so the flag is inert here — see Player for the rail that honours it.

## What this character could put toward a purchase right now — the raw pot, BEFORE any service charge.
## Display-only (a "you have N" readout); `can_pay` is the authority on whether a specific price is affordable.
func spendable(_allow_credit: bool = true) -> float:
	return maxf(0.0, money)

## The ALL-IN price of `cost` on this character's active rail: the base price plus whatever service charge the
## rail adds (none, for a plain wallet). THE one quoted number — every display site paints this and `charge`
## re-derives it from the same formula, so the label and the till can never disagree (the pickpocket rule:
## one formula feeds the shown odds AND the roll).
func charge_total(cost: float, _allow_credit: bool = true) -> float:
	return maxf(0.0, snappedf(cost, Zorkmids.QUANTUM))

## THE one affordability predicate. Every transaction gate and every UI dim reads exactly this.
func can_pay(cost: float, allow_credit: bool = true) -> bool:
	return charge_total(cost, allow_credit) <= spendable(allow_credit)

## THE TWO-PART PRICE QUOTE, for a point-of-sale display that wants to show the service charge SEPARATELY rather
## than only the all-in total: {base, cash, rail, fee, total, ok}. `base` is the sticker price, `cash`/`rail` how
## it would be funded, `fee` the service charge that funding adds, `total` what actually leaves the player, `ok`
## the same answer `can_pay` gives. Same shape on Player (which overrides it with the real split), so a screen can
## paint any character's quote without asking what kind it is.
##
## A plain wallet has no rail and therefore no fee, so the quote degrades to "the price is the price".
func quote(cost: float, allow_credit: bool = true) -> Dictionary:
	var base := maxf(0.0, snappedf(cost, Zorkmids.QUANTUM))
	return {"base": base, "cash": minf(base, maxf(0.0, money)), "rail": 0.0,
		"fee": 0.0, "total": base, "ok": can_pay(cost, allow_credit)}

## Pay `cost`. FAIL-CLOSED: returns false having moved NOTHING when the whole quoted total isn't covered — no
## partial draw, no goods, no debt. A cost of 0 or less always SUCCEEDS and charges nothing, so a free service
## still serves a character with an empty wallet or an open debt (the RespecStation / ChipInstaller convention,
## and the fix for the free-respec-refused-while-negative class of bug).
func charge(cost: float, allow_credit: bool = true) -> bool:
	var total := charge_total(cost, allow_credit)
	if total <= 0.0:
		return true
	if not can_pay(cost, allow_credit):
		return false
	add_money(-total)
	return true

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
## STRENGTH on the stat sheet adds to this at spawn (see _apply_stats). Per-character in the inspector.
@export var max_hp: float = 4.0
var hp: float
## This character's RPG stat sheet — set in the inspector by a designer (every Character, player AND NPC,
## has one). null = a neutral baseline sheet, so an unsheeted character is unchanged. Spawn effects
## (strength->max_hp + carry_capacity) stamp in _apply_stats during _ready; the live effects are
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
## The visual model root for this actor: every MeshInstance3D under its subtree gets the damage-flash overlay
## (and, for NPCs, the combat outline) applied in _ready. It only needs to be a NON-NULL node whose subtree holds
## the visible meshes — the NPC prefab wires it to the `BodyModelSwap` child (the live swapped body/head/limbs sit
## under it, since the vestigial `Man.glb` "Body" rig was removed). If `mesh` is null, `_flash_material` never
## builds and the whole flash + outline chain silently no-ops, so always keep it pointed at a surviving node.
@export var mesh: Node3D
## Optional model asset to use as this actor's mesh root. Drop a .glb/.gltf/.blend PackedScene or a .obj Mesh
## here and it is instanced into the character at runtime, then assigned to `mesh` automatically.
@export var mesh_asset: Resource
## Local offset for mesh_asset once it is instanced under the character.
@export var mesh_asset_position: Vector3 = Vector3.ZERO
## Local rotation, in degrees, for mesh_asset once it is instanced under the character.
@export var mesh_asset_rotation: Vector3 = Vector3.ZERO
## Local scale for mesh_asset once it is instanced under the character.
@export var mesh_asset_scale: Vector3 = Vector3.ONE
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
var _mesh_asset_instance: Node3D

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

## Dota-style passive item buffs: sums the `held_passive_effect` of every item carried in `inventory` into this
## Character's live buff pool (folded through status_stat_modifier / status_move_multiplier) and re-stamps any
## strength total into carry_capacity/max_hp. Built in _ready right after the backpack. See PassiveItemBuffs.
var _item_buffs: PassiveItemBuffs

## The stat sheet, never null — a bare/off-tree character lazily gets a fresh baseline sheet. Every stat
## consumer (Merchant, AimSway, Reputation, DialogueView, _apply_stats) reads through this, so a missing
## resource can't crash a price, a skill check, or spawn.
func stats_or_default() -> CharacterStats:
	if stats == null:
		stats = CharacterStats.new()
	return stats

## Spawn-time stat effects: STRENGTH adjusts BOTH max_hp (run BEFORE _ready seeds hp from max_hp) and
## carry_capacity (it absorbed the old Endurance stat). Strength's melee bonus + the other stats read the sheet
## LIVE at their own seams instead. Called as the FIRST line of _ready so every concrete actor (NPC stamps its
## profile first, then super() lands here) gets it.
func _apply_stats() -> void:
	var s := stats_or_default()
	max_hp = maxf(1.0, max_hp + s.max_hp_bonus())
	carry_capacity = maxf(0.0, carry_capacity + s.carry_bonus())

func _validate_property(property: Dictionary) -> void:
	if property.name == &"mesh_asset":
		property.hint = PROPERTY_HINT_RESOURCE_TYPE
		property.hint_string = ModelResourceUtil.HINT

func _ready() -> void:
	_apply_stats()  # ENDURANCE/STRENGTH stamp max_hp + carry_capacity BEFORE hp seeds from max_hp
	_build_mesh_asset()
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
	# Dota-style PASSIVE ITEM BUFFS: any carried Item with a `held_passive_effect` grants it WHILE HELD. Built
	# after the backpack so it can watch it, and connected in Character._ready (BEFORE the subclass seeds/restores
	# the bag) so the recompute fires as each stack lands — including a save's inventory restore. Character-level so
	# an NPC carrying a buff item benefits too. It contributes via the SAME duck-typed stat_modifier /
	# speed_multiplier surface the StatusEffectManager uses; status_stat_modifier / status_move_multiplier sum across both.
	_item_buffs = PassiveItemBuffs.new()
	_item_buffs._host = self
	_item_buffs.name = &"PassiveItemBuffs"
	add_child(_item_buffs)
	inventory.changed.connect(_item_buffs.on_inventory_changed)

## Turn an assigned model asset into a live Node3D mesh root. Godot imports glTF-style models as PackedScene
## resources, while .obj imports as a Mesh, so support both in one author-facing slot.
func _build_mesh_asset() -> void:
	if mesh_asset == null:
		return
	if is_instance_valid(_mesh_asset_instance):
		_mesh_asset_instance.queue_free()
	_mesh_asset_instance = null
	if not ModelResourceUtil.is_model(mesh_asset):
		push_warning("Character: mesh_asset '%s' must be a PackedScene or Mesh" % _mesh_asset_label())
		return
	var instanced_mesh: Node3D = ModelResourceUtil.instantiate(mesh_asset, "MeshAsset")
	if instanced_mesh == null:
		push_warning("Character: mesh_asset '%s' did not instantiate a Node3D root" % _mesh_asset_label())
		return
	_mesh_asset_instance = instanced_mesh
	if _mesh_asset_instance.name.is_empty():
		_mesh_asset_instance.name = "MeshAsset"
	add_child(_mesh_asset_instance)
	_mesh_asset_instance.position = mesh_asset_position
	_mesh_asset_instance.rotation_degrees = mesh_asset_rotation
	_mesh_asset_instance.scale = mesh_asset_scale
	mesh = _mesh_asset_instance

func _mesh_asset_label() -> String:
	return ModelResourceUtil.label(mesh_asset)

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
	var targets := TalkHelpers.collect_meshes(mesh, null, true)
	for m in targets:
		# Register this body with the ink-outline actor mask: hull-outlined actors are EXCLUDED from the
		# screen-space ink pass (the hull rim is their outline; ink on top doubles it — see InkOutline).
		# Riding THIS walk means every path that dresses the body (setup, provoke recolour, model rebuild)
		# re-stamps the bit for free, so a body swap can never strand its new parts inked.
		m.layers |= InkOutline.ACTOR_INK_MASK_LAYER
		# If the look-at talk highlight is active on this mesh, its real overlay is STASHED in meta (the
		# white highlight sits in the live slot). Update the stash so look-away restores the NEW overlay —
		# else a provoke / disposition recolour is lost when the highlight clears (a friendly turned
		# hostile would snap back to its old green rim on look-away instead of staying red).
		if m.has_meta(&"talk_prev_overlay"):
			m.set_meta(&"talk_prev_overlay", overlay)
		else:
			m.material_overlay = overlay


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

func take_damage(_amount: float, was_crit: bool = false, attacker: Node = null, hit_pos: Vector3 = Vector3.INF) -> void:
	# Guard: prevents multi-hit kills (e.g. shotgun's 9 pellets in one frame)
	# from triggering gore/die multiple times. queue_free is deferred so the
	# body still exists in the same frame and would otherwise receive every
	# subsequent pellet, each one firing 100 rain drops + 6 gibs + a death SFX.
	if _dead:
		return
	# ML-4 difficulty: scale damage the PLAYER takes (>1 = harder). PLAYER-ONLY (group-checked, not `is Player`,
	# to avoid a Character<->Player class cycle) — enemies aren't difficulty-scaled on the receiving end. Applied
	# BEFORE armour/DR: difficulty sizes the threat, armour is the player's own defence. 1.0 at Normal = no change.
	if _amount > 0.0 and is_in_group(Groups.PLAYER):
		_amount *= GameSettings.difficulty.damage_taken_mult
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
	# Enemy-health HUD hook, the mirror image of the aggro hook above: tell the ATTACKER whose HP it just
	# moved, so the player's top-centre health bar can show what it is fighting. Duck-typed + has_method-gated
	# exactly like on_dealt_hit's Character base is a no-op — only the Player implements on_damaged_target, so
	# an NPC attacker costs one has_method and nothing else, and an NPC-vs-NPC trade can never paint the
	# player's HUD. `attacker != self` spares our own splash / self-damage.
	#
	# THIS is the whole feature's seam, and it sits here on purpose: take_damage is the single funnel every
	# attributed damage path in the game already goes through — hitscan pellets and melee (DamageApplier from
	# damage_trace.gd), fired rounds (projectile.gd), explosions (explosion_area.gd), thrown props and thrown
	# weapons (Throwable.gd), the pinball ram (ram_reactor.gd) and a silent takedown. Wiring the HUD to
	# on_dealt_hit instead would have covered only the first three. Ambient damage (hazard zones, status DoT,
	# fall) deliberately passes attacker == null and so is deliberately not covered — there is nobody to
	# attribute it to. Runs BEFORE the lethal branch below, so the killing blow still pushes its final 0 HP.
	# `_amount > 0.0` skips heals (a negative amount) and fully-armour-soaked hits.
	# `hp + _amount` is the PRE-hit HP (hp was decremented six lines up): the bar needs it to draw the "chip"
	# shard for the damage THIS hit did, including the very first hit on a target — without it a blast that
	# damages ten bodies in one frame would leave the last one (a fresh target) showing no shard at all.
	if _amount > 0.0 and attacker != null and attacker != self and attacker.has_method(&"on_damaged_target"):
		attacker.call(&"on_damaged_target", self, hp, max_hp, hp + _amount)
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
		var killer := _resolve_killer(attacker)  # resolved ONCE, AFTER _award_kill, so both hooks below name the same killer
		_bequeath_wallet(killer)  # the PLAYER hands death_purse_loss_fraction of its wallet to the killer, or spills it on the ground when there isn't one (base no-op; see Player)
		_on_killed_by(killer)     # post-mortem reaction to WHO killed us (base no-op; the Player settles provoked grudges)
		# THE KILL CUE (the red whole-sky flash), and THIS is the one place it fires from.
		#
		# It sits at the same seam as the bounty deliberately: "who does this death pay?" and "whose sky pops?" are the
		# same question, so `killer` is the ALREADY-resolved answer from _resolve_killer above — which is what makes
		# EVERY kill flash, not just the ones with a hit site to hang a cue on. It carries, for free: a silent takedown
		# (SilentTakedown applies lethal damage through here), a status-effect / DoT tick that finishes someone off, a
		# thrown prop or thrown weapon, the pinball body-ram, and a FALL the player caused — the last three because
		# _resolve_killer falls back to `_credit_attacker` inside the kill-credit window when the killing blow itself
		# carries no attacker.
		#
		# Three guarantees come from the resolve + the _dead latch above, so this line needs no gates of its own:
		#   • ONCE per victim — `if _dead: return` at the top of take_damage means a shotgun's remaining pellets, a
		#     pierce through a corpse or a second grenade on a body cannot re-fire it. This latch is the authoritative
		#     "this hit was the kill" edge, which is why no caller has to compare a pre-hit HP for the flash.
		#   • NEVER a suicide — _resolve_killer returns null on `killer == self`, so your own blast/fall can't flash.
		#   • NEVER an NPC's kill — Character.on_scored_kill is a NO-OP; only the Player overrides it. So NPC-vs-NPC
		#     infighting (which still pays its bounty one line up) never touches the player's sky.
		# has_method-guarded because _resolve_killer only vouches for `reward_kill`; a future non-Character killer
		# (a turret, a trap) would pay a bounty without owning the cue.
		if killer != null and killer.has_method(&"on_scored_kill"):
			killer.call(&"on_scored_kill")
		_begin_death()
	else:
		# Non-lethal, real hit: punch in the low "underwater car door" thud. Only on the survive
		# branch so it doesn't double up under the death SFX/gore, and only for the player (gated
		# inside) so NPC hits stay silent here.
		_play_damage_thud()
		# We SURVIVED a hit, so any pin intent a thrown weapon just stamped is spent — the knife that stuck in
		# our shoulder does not get to staple a limb to the wall when we die of something else ten seconds later.
		_pin_hit = {}

## The on-death VISUAL + removal beat — the gore burst, then die(). Split out of take_damage into an
## overridable seam so a subclass can act BEFORE the body bursts: NPC overrides this to hold the actor
## frozen in place for a brief "juice" pop, then gore. Base Character (and the Player, which overrides only
## die() with its full death sequence) runs it inline, so their behaviour is unchanged. The bounty + wallet
## bequeath already ran in take_damage before this, so a deferred burst can't rob the killer of their credit.
func _begin_death() -> void:
	gore()
	die()

func die() -> void:
	died.emit()
	queue_free()

## Base-vitals half of the NPC-pooling reuse reset (NpcPool). Clears the death latch + HP + all-crit/credit
## bookkeeping + residual blast/velocity + limb damage + the whole-body hit-flash, and restores processing +
## visibility that the death-freeze beat may have disabled. NPC.reset_for_reuse() calls this via super() and then
## resets the AI/combat surface + delegates to each child component. Deliberately does NOT touch max_hp/carry
## (never re-run _apply_stats — it re-stamps strength ADDITIVELY, inflating max_hp every cycle) or the backpack
## contents (the NPC re-seeds those). `money` is owned/restored by the pool (it has the authored baseline).
func reset_for_reuse() -> void:
	_dead = false
	hp = max_hp
	_took_any_hit = false
	_all_crits = true
	_credit_attacker = null
	_credit_attacker_msec = 0
	explosion_velocity = Vector3.ZERO
	_blast_timer = 0.0
	velocity = Vector3.ZERO
	heal_limbs()  # clears _limb_condition / _crippled so a prior life's crippled limb doesn't ride in
	_pin_hit = {}  # a pooled body reused for a new NPC must not pin from the previous life's marker
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()  # a freeze-paused whole-body flash tween would resume on reuse
	_flash_tween = null
	if _flash_material:
		_flash_material.set_shader_parameter("flash_strength", 0.0)
	var mgr := status_manager()
	if mgr != null:
		mgr.clear_effects()  # drop any active bleed/slow/haste so buffs don't ride into the next life
	process_mode = Node.PROCESS_MODE_INHERIT  # the death-freeze beat may have DISABLED us
	visible = true

## True while this character is up and fightable: NOT the death-latch (_dead) AND still has HP. The canonical
## "is it worth engaging?" predicate — NPC targeting drops any node this returns false for (NpcTargeting._is_live),
## so enemies stop attacking the moment you ACTUALLY die instead of emptying clips into your corpse. It matters
## because the PLAYER stays in the tree through its death sequence + in-place checkpoint revive (this _dead latch
## stays set, hp 0) rather than freeing like an NPC does — without this an enemy would keep firing at the frozen
## body until the revive. Mirrors the `not _dead and hp > 0.0` liveness test the ally-alert / voice / senses gates
## already spell out inline.
func is_alive() -> bool:
	return not _dead and hp > 0.0

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
	var killer := _resolve_killer(attacker)
	if killer == null:
		return
	# Bounty sizes are DESIGNER knobs — tune them in resources/tuning/EconomySettings.tres, not here.
	var eco := GameSettings.economy
	var bounty := eco.all_headshots_kill_bounty if killed_by_only_crits() \
			else (eco.headshot_kill_bounty if killing_was_crit else eco.kill_bounty)
	if killer.is_in_group(Groups.PLAYER):
		bounty *= GameSettings.difficulty.money_mult  # ML-4: difficulty scales the PLAYER's earnings (1.0 at Normal)
		# ⭐THE LEDGER'S CONDUCT DIVIDEND. Your creditor watches, and its model likes precision — a headshot
		# nudges your credit standing, an all-headshot kill doubles it. Deliberately MARGINAL (a headshot is
		# worth ~1/400th of a spotless record at the shipped rate): this is flavour on top of the payment
		# history, never a substitute for it, and it must never become a way to grind a rating. PLAYER-ONLY —
		# an NPC has no file with the Ledger, and standing lives on GameState, not on any Character.
		if killing_was_crit or killed_by_only_crits():
			var per: float = maxf(0.0, GameSettings.economy.credit_standing_per_headshot)
			GameState.add_credit_standing(per * (2.0 if killed_by_only_crits() else 1.0))
	killer.reward_kill(bounty)
	_award_long_range_bonus(killer)  # EXTRA marksman pay when the kill was a distant one (see below)

## Pay an EXTRA "long-range kill" bounty when `killer` downed this character from a distance — the marksman
## reward. Distance is killer<->victim at the moment of death: exact for a hitscan (instant), a close
## approximation for a projectile (its shooter has barely moved during the round's flight). The payout scales
## with how far BEYOND the threshold the shot was and is capped, all via designer knobs in
## resources/tuning/EconomySettings.tres (EconomySettings.long_range_bonus_for owns the pure curve). Like the
## collateral / confetti trick-shots this pays ANY killer into its wallet (an NPC sniper banks it too, ready to
## loot) but only TOASTS the player. Melee / adjacent kills fall under the threshold and pay nothing, so the
## distance IS the gate — no weapon-type check is needed. `killer` is a Character (it exposes reward_kill), so
## it is always a Node3D; the guard just keeps a duck-typed test double from crashing on global_position.
func _award_long_range_bonus(killer: Node) -> void:
	# BOTH transforms must be real. The `is Node3D` half keeps a duck-typed test double out; the is_inside_tree()
	# half covers the case it missed — a REAL Node3D that never entered the tree (a bare Class.new() in a unit
	# test, where _ready never runs). Reading global_position off-tree raises `Condition "!is_inside_tree()" is
	# true`, and GUT 9.6 fails a test on any unexpected engine error even when every assert in it passes. A
	# distance is meaningless without a tree anyway, so an off-tree kill simply pays no marksman bonus — the same
	# no-op an off-tree instance gets everywhere else in this class.
	if not (killer is Node3D) or not (killer as Node3D).is_inside_tree() or not is_inside_tree():
		return
	var eco := GameSettings.economy
	var distance := (killer as Node3D).global_position.distance_to(global_position)
	var bonus := EconomySettings.long_range_bonus_for(distance, eco.long_range_min_distance, \
			eco.long_range_bounty, eco.long_range_bounty_per_m, eco.long_range_bounty_max)
	if bonus <= 0.0:
		return
	killer.reward_kill(bonus)
	# Same gold trick-shot toast as the collateral / confetti kills, with the shot distance for bragging rights.
	if killer.has_method(&"notify_toast"):
		killer.notify_toast(PlayerText.long_range_kill(int(round(distance)), bonus), Color(1.0, 0.86, 0.3))

## Resolve who gets credit for downing this character: the direct `attacker`, or — when that lethal hit was
## UNATTRIBUTED (a fall off a ledge, a stray blast) — the most recent real attacker within the kill-credit
## window (GameSettings.economy.kill_credit_window_ms), so a player-CAUSED fall/explosion still credits them
## but a lone stumble off a cliff credits no one. Returns null when nobody qualifies OR the only candidate is
## ourself (no self-bounty for our own blast/fall). Shared by _award_kill (the bounty) AND _bequeath_wallet
## (the player's death wallet transfer), so both name the SAME killer.
func _resolve_killer(attacker: Node) -> Node:
	var killer := attacker
	if (killer == null or not killer.has_method(&"reward_kill")) \
			and is_instance_valid(_credit_attacker) \
			and Time.get_ticks_msec() - _credit_attacker_msec <= GameSettings.economy.kill_credit_window_ms:
		killer = _credit_attacker
	if killer == null or killer == self or not killer.has_method(&"reward_kill"):
		return null
	return killer

## Hook: settle this character's wallet as it dies — hand it to `killer` (null when nobody qualifies).
## Base NO-OP — only the Player bequeaths its zorkmids: to the killer (recover them by hunting that killer down and
## looting their corpse) or, when nobody gets credit, onto the ground as a money bag where it died. An NPC needs
## none of this; its money just stays in its wallet and drops as loot the normal way (NpcMortality -> LootableCorpse).
## The Player overrides this (see Player._bequeath_wallet).
func _bequeath_wallet(_killer: Node) -> void:
	pass

## Hook: react to having just been killed by `killer` (the SAME node _bequeath_wallet was handed; null when
## nobody qualifies). Runs AFTER the bounty + wallet bequeath — so the holster-tutorial check inside
## Player._bequeath_wallet still reads the pre-settlement provoke state — and BEFORE _begin_death(), while the
## killer is guaranteed live. Base NO-OP: only the Player overrides it, to stand down every NPC that was hostile
## ONLY because it was provoked (see Player._on_killed_by / HostilityHelpers.settle_provoked_grudges). Called from
## BOTH lethal paths (take_damage here and Player._die_from_continuous_fall), exactly like _bequeath_wallet.
func _on_killed_by(_killer: Node) -> void:
	pass

func heal(_amount: float) -> void:
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

## Hook for when THIS character KILLED something — the kill flash (whole-sky red pour). Fired
## from ONE place: the lethal branch of take_damage above, on the `killer` _resolve_killer picked, so every
## attributed kill in the game reaches it (see the long note there for what that buys). Separate from
## on_dealt_hit because most kills have no hit-confirm to ride on — a takedown, a DoT tick and a caused fall all
## kill without any hitmarker moment.
##
## The base MUST stay a no-op: it is called duck-typed on whoever got the credit, so every NPC killer lands here,
## and an NPC-vs-NPC kill flashing the player's sky is exactly what that emptiness prevents. Only Player overrides.
func on_scored_kill() -> void:
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
## head / top cap is ~0.5..1.0 — hence the 0.4 default. Raise it to tighten the head zone, or
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

# --- Pin intent (thrown-weapon PIN kill) ---------------------------------------------------------------------
#
# A thrown weapon that opts in (Throwable.pins_body_part) stamps WHERE it struck and WHICH WAY it was travelling
# here, immediately before the lethal take_damage — the NPC.mark_silent_takedown idiom, and for the same reason:
# the death burst that needs this runs many frames and many signatures later (take_damage -> _begin_death -> a
# SceneTree timer for the death-freeze beat -> _complete_death -> gore() -> GoreSpawner), so the intent has to be
# STASHED rather than passed. GoreSpawner.spawn_gibs consumes it to staple one limb to the wall behind.
#
# PER-LIFE STATE. It is cleared in three places and needs all three: on the survive branch of take_damage (a
# non-lethal knife hit must not leave a marker that pins on some later, unrelated death), in reset_for_reuse
# (a POOLED body reused for a new NPC would otherwise pin from its previous life's marker — the exact trap
# NPC._silent_death documents), and by the consuming read itself.
var _pin_hit: Dictionary = {}

## Stash the pin intent for the hit that is about to land. `contact` is the strike's world-space contact point
## (the same one the damage classifies against), `travel_dir` the NORMALISED direction the weapon was moving,
## `blade` the Throwable itself, which ends up embedded in the surface, and `surface` the ALREADY-PROBED wall
## ({"point", "normal", "collider"} from Throwable._probe_pin_surface). Overwrites any earlier marker: the last
## thrown hit before death is the one that gets the trophy.
##
## The surface is passed IN rather than looked up later, and that is not an optimisation — it is the only place
## it CAN be found. The death burst that spends this marker runs off the death-freeze SceneTreeTimer, on the idle
## frame, where PhysicsDirectSpaceState3D queries come back empty however solid the wall is. See
## Throwable._probe_pin_surface for the full note; that bug shipped once and made the whole feature inert.
func mark_pin_hit(contact: Vector3, travel_dir: Vector3, blade: Node, surface: Dictionary) -> void:
	_pin_hit = {"contact": contact, "dir": travel_dir, "blade": blade, "surface": surface}

## CONSUME the pin intent — returns it and clears it, so a death can only ever spend it once (gore() is reachable
## twice in principle: the death-freeze timer and a direct call). Empty Dictionary when this death was not a pin
## kill, which is every death that is not a thrown-weapon kill. The caller MUST re-check `blade` with
## is_instance_valid: the marker holds a hard Node reference across the freeze beat, and the player can pick the
## knife back up (freeing the world prop) inside that window.
func take_pin_hit() -> Dictionary:
	var hit := _pin_hit
	_pin_hit = {}
	return hit

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

## Aggregate move-speed multiplier from every buff-source child — a StatusEffectManager (slow/haste effects) AND
## the PassiveItemBuffs pool (held-item speed buffs) — multiplied together, or 1.0 if none. Multiplied into
## locomotion alongside limb_move_multiplier / encumbrance_move_multiplier (both player + NPC). Duck-typed (no hard
## StatusEffectManager dependency on this core class) and re-scanned each call so a source added at runtime (the
## Player auto-creates a manager for consumable buffs) is picked up. PRODUCT across children: two independent
## multipliers compound, so the single-source case is unchanged.
func status_move_multiplier() -> float:
	var m := 1.0
	for c in get_children():
		if c.has_method(&"speed_multiplier") and c.has_method(&"apply_effect"):
			m *= c.speed_multiplier()
	return m

## Aggregate per-stat additive modifier SUMMED across every buff-source child — the StatusEffectManager (e.g. an
## adrenaline effect with {"agility": 2}) AND the PassiveItemBuffs pool (held-item stat buffs) — or 0.0 if none.
## Folded into the MULTIPLIER-stat derived effects at their live seams (move/jump/damage/sway/prices/reputation) via
## the derived methods' `bonus` arg, so a stat buff actually changes gameplay. Duck-typed + re-scanned each call,
## exactly like status_move_multiplier(); summing means a held buff and a consumable buff on the same stat stack.
## NOTE: strength's carry_capacity/max_hp are spawn-stamped and read once, not live, so a TIMED strength modifier
## doesn't move those — but it DOES fold into strength's melee_damage_mult (that IS a live seam). PassiveItemBuffs
## re-stamps a HELD strength total onto max_hp/carry_capacity directly and returns 0 for strength here, so a held
## strength buff stays a carry/HP item (no double-apply, no melee) while a timed one reaches melee.
func status_stat_modifier(stat: StringName) -> float:
	var total := 0.0
	for c in get_children():
		if c.has_method(&"stat_modifier") and c.has_method(&"apply_effect"):
			total += c.stat_modifier(stat)
	return total

## This character's StatusEffectManager child, or null if none exists yet (it's lazily created on first
## apply_status_effect). Read-only — for serialization (GameState.capture) + queries; use ensure_status_manager()
## to create-if-absent.
func status_manager() -> StatusEffectManager:
	for c in get_children():
		if c is StatusEffectManager:
			return c as StatusEffectManager
	return null

## The StatusEffectManager child, creating it if absent — the lazy-create shared by apply_status_effect + the
## save-restore glue. Needs to be in-tree (add_child).
func ensure_status_manager() -> StatusEffectManager:
	var mgr := status_manager()
	if mgr == null:
		mgr = StatusEffectManager.new()
		mgr.name = &"StatusEffects"
		add_child(mgr)
	return mgr

## Apply a StatusEffect to this character (CT-3), lazily creating the StatusEffectManager child on first use so a
## weapon's on-hit effect, a consumable, or an NPC ability all work without a pre-placed manager. Shared by the
## player + NPCs (promoted from Player._apply_status_effect). No-op for a null effect; needs to be in-tree (add_child).
func apply_status_effect(effect: StatusEffect) -> void:
	if effect == null:
		return
	ensure_status_manager().apply_effect(effect)

## PD-2: the summed combat bonus `key` from this character's unlocked perks (its PerkManager child), or 0 with
## no manager — the perk side of the damage scaling, read at the shot seam. Duck-typed so a perkless NPC is 0.
func perk_combat_bonus(key: StringName) -> float:
	for c in get_children():
		if c is PerkManager:
			return (c as PerkManager).combat_bonus(key)
	return 0.0

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

## Extra shot spread (radians) from the WIELDER's own marksmanship, added by attack.gd to every RANGED
## (non-melee) pellet. 0.0 here — the PLAYER's accuracy already runs through AimSway/bloom/hip_sway_mult, so a
## second cone would double-punish. NPC overrides this with its gunplay-scaled aim-error cone (npc.gd), which
## is what makes an enemy's stat sheet decide how well it shoots instead of every NPC being an aimbot.
func aim_error_spread() -> float:
	return 0.0

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
	if HostMethodHelper.try_call_bool(self, &"is_following"):
		return
	var dmg := FallDamage.hp_loss(fall_speed, fall_damage_min_speed, fall_damage_per_speed)
	if dmg > 0:
		take_damage(dmg)

func gravity(delta: float) -> void:
	if !is_on_floor():
		velocity += get_gravity() * delta

func _has_live_physics_space() -> bool:
	if not is_inside_tree():
		return false
	var world := get_world_3d()
	if world == null or not world.space.is_valid():
		return false
	return PhysicsServer3D.body_get_space(get_rid()).is_valid()

## Standard move step. Adds the blast impulse to velocity for THIS frame's move,
## slides, pushes any rigid bodies hit, then removes a fraction (1/blast_damp_divisor)
## of the blast so it bleeds off over subsequent frames instead of persisting.
## pre_move_velocity is captured BEFORE move_and_slide because the slide response
## zeroes velocity into surfaces, and _push_interactables needs the original speed.
func apply_velocity() -> void:
	# move_and_slide needs a live physics space; bail when we're not in one (e.g. a unit
	# test instantiates the actor outside a World3D yet still ticks _physics_process).
	if not _has_live_physics_space():
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
func apply_blast() -> void:
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
## Default resolved with runtime load(), NOT preload(): gore_gib.tscn's root runs Throwable.gd, which type-refs
## Character (`is Character`) -- a compile-time preload here would force that scene's scripts to analyze WHILE this
## class is still parsing, closing a cycle (character.gd -> gore_gib.tscn -> Throwable.gd -> Character) and throwing
## "Could not resolve member gib_scene: Cyclic reference". load() defers to instance-time, breaking the parse edge.
## DO NOT change this back to preload(). (Same reason npc.gd load()s weapon.tscn instead of preloading it.)
@export var gib_scene: PackedScene = load("uid://bgore1gib0scn")
## Optional on-death corpse / loot drop spawned at the death spot, carrying a COPY of this actor's
## backpack + wallet (GoreSpawner._attach_loot) and lingering until looted. Two drop-ins fit this slot:
## a rigged-skeleton Ragdoll (scenes/props/skeleton.tscn — flops + flies the way the kill knocked us,
## see scripts/components/ragdoll.gd) or a LootBag (scenes/props/loot_bag.tscn — a physics Throwable bag
## that falls + rests on the floor and can be looted or thrown, see scripts/components/loot_bag.gd). The
## Ragdoll consumes the `launch` + `loot` hooks set here; the LootBag ignores them (physics + a
## LootableCorpse child do its work). Null = no corpse; the NPC leaves a free-standing LootableCorpse via _drop_loot.
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

## The SceneTree group EVERY world node this actor's death burst spawns joins — the gibs (meat chunks AND body
## parts), the floor blood splat, the ragdoll/loot corpse, and, propagated down the chain by bloody_mess.gd ->
## BloodDropEmitter -> BloodDrop, the secondary splatter those gibs bleed when they later pop. `&""` (the base)
## tags NOTHING, which is what an NPC wants: its gore is world dressing and has to stay lying where it fell.
## The PLAYER overrides it with Groups.PLAYER_GORE so its own burst can be undone wholesale by the in-place
## checkpoint revive — see clear_death_gore() and Player._respawn_at_checkpoint.
##
## Why an overridable seam instead of an `is Player` test inside GoreSpawner: gore_spawner.gd sits on Character's
## parse path, so a `Player` TYPE reference from there closes a parse cycle (the same reason gib_scene load()s
## instead of preload()ing). A group NAME crosses that boundary with no type dependency at all.
func death_gore_group() -> StringName:
	return &""

## Undo this actor's death burst: free every world node tagged with death_gore_group(). Returns how many were
## freed — always 0 for an actor that tags nothing (every NPC), which is what makes this safe to call blind.
## Thin facade over the GoreSpawner child; null off-tree (_ready skipped) — then this no-ops like the rest.
func clear_death_gore() -> int:
	if _gore_spawner == null:
		return 0
	return _gore_spawner.clear_tagged_gore()

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
