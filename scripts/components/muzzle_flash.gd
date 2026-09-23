class_name MuzzleFlash
extends Node3D

## Blinks the muzzle-flash mesh + point light for a fixed duration on each shot.
## Connected to Attack.flash_muzzle (emitted alongside the gunshot). Per-weapon
## opt-out via WeaponData.has_muzzle_flash (e.g. melee has none). The mesh is an
## ExplosionMesh (pulsing glow); light_flash briefly lights the surroundings.
##
## RAPID FIRE HOLDS, IT DOESN'T STROBE. An automatic weapon that cycles faster than the blink can clear
## (the SMG: 8 rounds/s against a 0.1 s blink) used to go dark for a frame or two between every round —
## an 8 Hz on/off of a bright disc dead centre while aiming, on top of the recoil kick driving that disc
## into the lens (see EffectsSettings.view_model_kick_ads_mult). Such a weapon now keeps the flash lit from
## round to round (hold_seconds) so a burst reads as one sustained muzzle glow — the ExplosionMesh's own
## slow pulse still gives it life — and a generation counter makes sure only the LAST round's timer hides it.

## The pulsing-glow flash mesh (an ExplosionMesh) flicked visible for the flash duration on each shot.
@export var mesh_instance_3d: ExplosionMesh
## The point light blinked on with the mesh so the flash briefly lights nearby surfaces.
@export var light_flash: OmniLight3D
# Set by GunMesh.setup() (invoked by Player._enter_tree) so we can honor the equipped weapon's flash toggle.
## The weapon hub, so the flash can be skipped when the equipped weapon's has_muzzle_flash is off (e.g. melee).
@export var inventory: Inventory

## An automatic weapon whose cadence is under blink x this HOLDS its flash across rounds instead of blinking.
## 1.5 catches the SMG (0.125 s cadence vs the 0.1 s blink) and leaves the pistol (0.44 s) a per-shot blink.
const RAPID_FIRE_HOLD_RATIO := 1.5

var _flash_gen: int = 0  ## bumped per shot; a timer's hide only lands if no newer shot re-lit the flash since

func _do_muzzle_flash() -> void:
	var weapon: WeaponData = inventory.equipped_weapon if inventory else null
	if weapon and not weapon.has_muzzle_flash:
		return
	# A shot can fire the same frame the weapon node is being swapped/freed — guard the pre-await writes too,
	# not just the post-await ones, so we never poke a freed mesh / light.
	if not is_instance_valid(mesh_instance_3d) or not is_instance_valid(light_flash):
		return
	_flash_gen += 1
	var gen := _flash_gen
	mesh_instance_3d.visible = true
	light_flash.visible = true
	var hold := MuzzleFlash.hold_seconds(GameSettings.weapon_general.muzzle_flash_duration,
			weapon != null and weapon.auto_fire, weapon.attack_speed if weapon else INF, get_process_delta_time())
	await get_tree().create_timer(hold).timeout
	# A newer round re-lit the flash while this one's timer ran: its timer owns the hide now. Without this
	# the older timer would black out the newer round's flash mid-burst — the strobe by another route.
	if gen != _flash_gen:
		return
	# The flash timer can outlive these nodes (e.g. the weapon was swapped / freed mid-blink) — bail
	# before touching them so we don't poke a freed mesh / light, like the post-await guards in attack.gd.
	if not is_instance_valid(mesh_instance_3d) or not is_instance_valid(light_flash):
		return
	mesh_instance_3d.visible = false
	light_flash.visible = false


## Seconds ONE round keeps the flash lit. Normally `blink` (the muzzle_flash_duration knob). An automatic
## weapon that cycles faster than the blink can clear (`cadence` < blink x RAPID_FIRE_HOLD_RATIO) instead
## holds for its cadence plus one `frame` of slack, so the next round re-lights the flash BEFORE this one's
## timer would have hidden it and a held trigger reads as a sustained glow, never an N-Hz strobe. Never
## shorter than the blink. `cadence` is the weapon's AUTHORED attack_speed: the wielder's agility only ever
## shortens the live cadence, so the authored number is the longest gap a hold has to bridge. Pure and
## static for the contract test.
static func hold_seconds(blink: float, auto_fire: bool, cadence: float, frame: float) -> float:
	if auto_fire and cadence < blink * RAPID_FIRE_HOLD_RATIO:
		return maxf(blink, cadence + frame)
	return blink
