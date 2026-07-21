@tool
class_name ProvokeOnAttack
extends Node

## Drop-in: how this (non-hostile) NPC reacts when the PLAYER attacks it. A NEUTRAL flips hostile on the first
## hit; a FRIENDLY ally forgives incidental damage and only turns once cumulative player damage passes the
## NPC's friendly_aggro_threshold (a companion stops following at that point). Drop it under an NPC; the NPC
## calls react() from _on_damaged_by on every hit. It's AUTO-ADDED when you don't drop one in, so behaviour is
## unchanged — drop a configured instance, or set `enabled = false` so THIS NPC NEVER turns hostile from being
## hit (a scripted quest-giver / shopkeeper you can shoot at without aggroing). Only the PROVOKE decision lives
## here; the turn-toward-shooter, grudge, target-focus and self-heal/panic reactions stay on the NPC.

## Off = this NPC never turns hostile from a player attack (it absorbs hits, keeps its disposition). The other
## hit reactions (turn toward the shooter, self-heal, panic) still run — only the hostility flip is suppressed.
@export var enabled: bool = true

## Called by the host NPC from _on_damaged_by on every hit (HP already reduced). `attacker`/`amount` come from
## the damage hook. Mirrors the old inline branch verbatim: only a PLAYER hit on a still-non-hostile NPC does
## anything — a FRIENDLY accumulates toward host.friendly_aggro_threshold (warn under it, aggro + stop-following
## over it); a NEUTRAL provokes immediately. `host` is duck-typed so a bare-stub unit test can drive it.
func react(host: Variant, attacker: Node, amount: float) -> void:
	if not enabled or host == null:
		return
	if host.is_hostile() or attacker == null or not attacker.is_in_group(Groups.PLAYER):
		return  # only a PLAYER hit on a still-non-hostile NPC provokes (an enemy's stray friendly-fire doesn't)
	if host.resolved_disposition() == Disposition.Kind.FRIENDLY:
		# A FRIENDLY ally forgives incidental damage; it only turns once cumulative player damage passes the
		# threshold, at which point a companion stops following and it aggros.
		host._player_aggression += amount
		if host._player_aggression >= host.friendly_aggro_threshold:
			if host.is_following():
				host.stop_following()
			host.provoke(attacker)
			if host._voice != null:
				host._voice.bark_aggro()  # the forgiveness ran out: "Alright, that does it!"
		elif host._voice != null:
			host._voice.warn_attack()  # hit but still FORGIVEN (under the threshold): "Cut that out!"
	else:
		host.provoke(attacker)  # a NEUTRAL flips on the first hit — and says so
		if host._voice != null:
			host._voice.bark_aggro()

func _get_configuration_warnings() -> PackedStringArray:
	if get_parent() is NPC:
		return PackedStringArray()
	return PackedStringArray(["ProvokeOnAttack must be a child of an NPC (it reacts to that NPC taking damage)."])
