class_name WeaponStance
extends Node

## A combatant's GUN STANCE (Feature E) — the draw / holster / out-of-combat-reload bookkeeping that
## keeps the weapon up while fighting and stows (and tops up) it once combat ends, with a wary stand-down
## beat so the NPC doesn't KNOW the threat is gone the instant perception drops. Split off NPC so the root
## keeps only the firing CADENCE + the aim contract (and the canonical _weapon / _weapon_mesh handles);
## this child owns the stance state machine, reconciled once per frame from the host's _physics_process.
##
## Host-coupled: NPC builds it in _ready ONLY for a combatant (weapon_data set) and sets `host` right
## after .new(); it READS the host's combat sense (_perception / _target / threat_response) + drives the
## host's _weapon (holster / reload) and hides the host laser via host._hide_laser(). Off-tree (a unit-test
## NPC built via .new() with no add_child) this child never exists, so NPC's _current_move_speed facade
## null-guards it (returning the bare move_speed, exactly what the monolith returned with _weapon null) and
## the per-frame reconcile is gated on _weapon being non-null, which it also is only for a real combatant.

## The combatant this manages — set right after .new() in NPC._ready. The canonical weapon handles
## (_weapon / _weapon_mesh) live on the host; this child only holds the transient stance bookkeeping.
var host: NPC

## Set true once this NPC first enters combat (draws its gun). Gates the out-of-combat auto-reload so a
## starts_unloaded ambusher keeps its gun dry until it actually engages, rather than topping up while idle.
var _has_engaged: bool = false
## Combat stand-down countdown (Feature E): seconds left with the gun still OUT after disengaging. Set to
## GameSettings.npc_ai.holster_delay on every engaged frame; once disengaged it bleeds down, and only at <= 0
## does the NPC holster — so it keeps the weapon up, wary, for a beat instead of stowing it the instant
## combat ends.
var _holster_delay_timer: float = 0.0

## Bring the held gun into VIEW: unholster the Weapon (re-enables firing) and show the view-model. The low-level
## half of draw_weapon, WITHOUT marking _has_engaged -- so a pre-disposed-hostile NPC can stand with its gun OUT
## before ever entering combat, and a starts_unloaded one stays dry (no out-of-combat reload) until it actually does.
func _show_weapon() -> void:
	if host._weapon == null:
		return
	host._weapon.attack.set_holstered(false)
	if is_instance_valid(host._weapon_mesh):
		host._weapon_mesh.visible = true

## Draw the gun FOR COMBAT: show it AND mark that we've engaged, so the out-of-combat auto-reload may now top the
## clip up. Used on the engaged path; the always-ready pre-disposed-hostile stand uses _show_weapon (no _has_engaged).
func draw_weapon() -> void:
	_show_weapon()
	if host._weapon != null:
		_has_engaged = true

## Put the gun away: holster the Weapon (blocks firing) and hide the held view-model + the laser.
func holster_weapon() -> void:
	if host._weapon == null:
		return
	host._weapon.attack.set_holstered(true)
	if is_instance_valid(host._weapon_mesh):
		host._weapon_mesh.visible = false
	host._hide_laser()

## True while this combatant has a hostile target it has NOTICED (perception past UNAWARE) and means to
## fight — i.e. "in combat" for the purpose of having its gun OUT. Broader than NPC.is_in_combat() (which
## is ALERTED-only, for the talk gate): the gun comes up as the NPC first spots you (DETECTING), not only
## once it's locked on. A fleer never draws (it runs from threats), so it's excluded here.
func _is_engaged() -> bool:
	return host._perception != null and is_instance_valid(host._target) \
			and host._perception.state != Perception.State.UNAWARE \
			and host.threat_response == NPC.ThreatResponse.FIGHT

## Reconcile the gun stance with the combat state each frame (combatants only): draw while fighting;
## out of combat, reload a spent clip (drawing briefly if needed) then holster once it's full. A
## starts_unloaded NPC that has never engaged stays empty + holstered until it first fights.
func reconcile() -> void:
	if host._weapon == null:
		return
	# Can't fight with the gun — its weapon-item left the bag (looted / exchanged away — disarmed) or its ammo was pickpocketed, OR it's dry with no spare clips:
	# holster it + hide the held model rather than drawing it for a fight it can't join. The NPC then throws
	# fists instead (NPC._act_unarmed), so it visibly puts the gun away BEFORE squaring up bare-handed.
	if not host._can_fight_with_gun():
		if not host._weapon.attack.holstered:
			holster_weapon()
		return
	if _is_engaged():
		_holster_delay_timer = GameSettings.npc_ai.holster_delay  # re-engaged: re-arm the full stand-down beat before holstering
		if host._weapon.attack.holstered:
			draw_weapon()
		return
	# Disengaged: bleed the stand-down timer. The NPC keeps the gun OUT (and may reload, below) until it
	# elapses, THEN holsters — it shouldn't KNOW the threat is gone the instant perception drops (Feature E).
	_holster_delay_timer = maxf(0.0, _holster_delay_timer - host.get_physics_process_delta_time())
	var max_ammo: int = host._weapon.equipped_weapon.max_ammo if host._weapon.equipped_weapon else 0
	# A pre-disposed-hostile enemy NEVER stands down -- it keeps its gun OUT at all times (the player's cue that
	# it's a threat), unlike a neutral/friendly armed NPC which holsters once the stand-down beat elapses.
	var always_out: bool = host.is_predisposed_hostile()
	# Out-of-combat reload still runs DURING the stand-down — top the clip up between engagements.
	if _has_engaged and host._weapon.current_ammo < max_ammo and not host._weapon.is_busy():
		if host._weapon.attack.holstered:
			draw_weapon()  # must be out to reload
		host._weapon.reload()
	elif always_out:
		if host._weapon.attack.holstered:
			_show_weapon()  # hostile by design: stand ready with the gun up -- without claiming combat (keeps starts_unloaded dry)
	elif _holster_delay_timer <= 0.0 and not host._weapon.attack.holstered and not host._weapon.is_busy():
		holster_weapon()  # stand-down elapsed and nothing to reload — put it away

## Walk speed, slowed by a heavy DRAWN weapon (WeaponData.move_speed_multiplier). Holstered (out of
## combat) the NPC moves at full move_speed — the weight only bites while the gun is out, FNV-style.
func current_move_speed() -> float:
	if host._weapon != null and not host._weapon.attack.holstered and host._weapon.equipped_weapon:
		return host.move_speed * host._weapon.equipped_weapon.move_speed_multiplier
	return host.move_speed
