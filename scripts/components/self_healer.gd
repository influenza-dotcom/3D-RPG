@tool
class_name SelfHealer
extends Node

## Drop-in: this NPC reaches for a carried HEALING consumable when its HP drops past a threshold — the same
## health packs the player loots off its corpse, spent in the fight instead. Drop it under an NPC (the Enemy
## root); the NPC calls react() on every hit it takes. It's AUTO-ADDED (seeded from GameSettings.npc_ai.medkit_*)
## when you don't drop one in, so existing NPCs are unchanged — drop a CONFIGURED instance to override per-NPC
## (heal sooner/later, faster/slower), or set `enabled = false` so THIS NPC never self-heals.

## Off = this NPC never uses a medkit (it just takes the hits).
@export var enabled: bool = true
## Heal once HP is at/below this fraction of max HP. Higher = heals sooner (more cautious).
@export var heal_at_hp_frac: float = 0.5
## Minimum milliseconds between heals, so one bad moment doesn't burn the whole backpack at once.
@export var cooldown_ms: int = 4000

var _last_heal_msec: int = -1_000_000_000  ## "no heal yet" — far enough back that the FIRST heal is allowed for ANY configured cooldown_ms

## NPC-pooling reuse reset (NpcPool): rewind the heal cooldown to the "no heal yet" sentinel so a reused body that
## used a medkit shortly before dying isn't denied its first heal early in the new life. Called by NPC.reset_for_reuse.
func reset_for_reuse() -> void:
	_last_heal_msec = -1_000_000_000

## Called by the host NPC from _on_damaged_by on every hit it takes (HP already reduced). Spends one carried
## healing consumable when enabled, at/below the threshold, off cooldown, and one is in the bag. `host` is
## passed (duck-typed) so a bare-instance unit test can drive it with a stub — no NPC _ready needed.
func react(host: Variant) -> void:
	if not enabled or host == null:
		return
	if host.hp <= 0.0 or host.inventory == null:  # dead / civilian with no bag -> nothing to do
		return
	if host.hp > host.max_hp * heal_at_hp_frac:
		return
	var now := Time.get_ticks_msec()
	if now - _last_heal_msec < cooldown_ms:
		return
	var kit: Item = host.inventory.find_healing_consumable()
	if kit == null:
		return
	_last_heal_msec = now
	host.heal(kit.heal_amount)
	host.inventory.remove(kit, 1)

func _get_configuration_warnings() -> PackedStringArray:
	if get_parent() is NPC:
		return PackedStringArray()
	return PackedStringArray(["SelfHealer must be a child of an NPC (it reacts to that NPC taking damage)."])
