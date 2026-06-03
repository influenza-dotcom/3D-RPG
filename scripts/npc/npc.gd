@abstract
class_name NPC
extends Character

## Shared base for all NON-PLAYER actors (Enemy today; future friendly/neutral NPCs
## tomorrow). Sits between Character and Enemy so non-combat NPCs can extend NPC without
## inheriting enemy-only behaviour, while everything keeps inheriting Character's HP /
## damage / gore / blast machinery and `Enemy is Character` stays transitively true.
##
## Owns the combat OUTLINE (Phase 2): the outline is a non-player cue, so it lives here,
## not on Character. Each NPC subclass / instance configures its own outline via the
## exports below, so a future friendly NPC need not wear the enemy's black rim. The
## outline ShaderMaterial is built through TalkHelpers.make_outline_material() — the one
## shared outline-material builder, also used by the look-at talk highlight — then chained
## IN FRONT of Character's damage-flash overlay (outline.next_pass = flash) so a single
## material_overlay produces both the inflated-hull outline and the hit-flash.
##
## The Player is deliberately NOT an NPC: it stays `extends Character` and has no outline.

## Master switch for this actor's combat outline. Off => flash-only overlay (no rim).
@export var has_outline: bool = true
## Outline rim colour. Enemies default to black; a friendly NPC can override per instance.
@export var outline_color: Color = Color.BLACK
## Outline thickness fed to the shader's `outline_width` uniform (shader scales it x4 in clip
## space). 0.085 reproduces the intended enemy rim. Was silently ignored pre-Phase-2 because the
## old code set a non-existent `outline_thickness` uniform; the shader only exposes `outline_width`.
@export var outline_width: float = 0.085

@export_group("Hostility")
## The faction this NPC belongs to. NULL => UNALIGNED: the NPC uses its standalone `disposition`
## below instead of faction + player-reputation. Set this to a Faction .tres (e.g. raiders,
## townsfolk) to make the NPC's attitude track the player's reputation with that faction.
@export var faction: Faction = null
## Standalone attitude, used ONLY when `faction` is null (unaligned). Defaults to HOSTILE so a
## plain Enemy with no faction set behaves exactly like today's enemy (aggressive on sight).
@export var disposition: Disposition.Kind = Disposition.Kind.HOSTILE
## When true, this NPC has been provoked (e.g. the player attacked it) and is hostile regardless
## of faction/disposition until something clears it. Runtime only — never authored in the editor.
var _provoked: bool = false

func _ready() -> void:
	super()  # Character._ready(): set hp + build the flash overlay on the mesh tree.
	add_to_group(&"npc")  # so hostile NPCs can find us as a target (RangedEnemy's scan enumerates this)
	_setup_outline()

## Chain the configured outline pass in front of the flash material and re-apply the combined
## overlay to the mesh tree. No-op if outlines are disabled or the flash overlay wasn't built
## (no `mesh`). Built once; toggling appearance later would re-run _apply_overlay_to_meshes.
func _setup_outline() -> void:
	if not has_outline or _flash_material == null:
		return
	var outline := TalkHelpers.make_outline_material(outline_color, outline_width)
	outline.next_pass = _flash_material
	_apply_overlay_to_meshes(outline)

## Resolve this NPC's CURRENT attitude toward the player, in priority order:
##   1. provoked  -> HOSTILE (a hit always aggros, overriding everything)
##   2. factioned -> Reputation's disposition for that faction (faction baseline + player rep)
##   3. unaligned -> the standalone `disposition` export
func resolved_disposition() -> Disposition.Kind:
	if _provoked:
		return Disposition.Kind.HOSTILE
	if faction != null:
		return Reputation.disposition_for(faction)
	return disposition

## True when this NPC currently treats the player as an enemy. The combat AI (RangedEnemy /
## Perception) gates ALL hostile behaviour — detect, aim, fire — on this. A non-hostile NPC keeps
## gravity / idle but never engages the player until provoked.
func is_hostile() -> bool:
	return resolved_disposition() == Disposition.Kind.HOSTILE

## True when this NPC currently treats `other` as an enemy. Two cases:
##   - other is the PLAYER ("Player" group): defer to today's is_hostile() (provoke + faction-rep
##     + standalone disposition). Player targeting is unchanged.
##   - other is another NPC: BOTH must be factioned and this faction's relation to the other's
##     faction must be < 0 (FNV-style "<0 = enemies"). Unaligned NPCs never fight other NPCs;
##     a provoked NPC still only sours toward the PLAYER (provoke drops player-rep), not peers.
## Self / null / non-NPC-non-player nodes are never hostile.
func is_hostile_to(other: Node) -> bool:
	if other == null or other == self or not is_instance_valid(other):
		return false
	if other.is_in_group(&"Player"):
		return is_hostile()
	var other_npc := other as NPC
	if other_npc == null or faction == null or other_npc.faction == null:
		return false
	return faction.relation_to(other_npc.faction.id) < 0.0

## Aggro this NPC: become hostile NOW, and — if factioned — drop the player's reputation with that
## faction so the whole faction sours (FNV-style). Idempotent; safe to call every hit. `attacker`
## is accepted so subclasses (RangedEnemy) can also turn toward the source.
func provoke(_attacker: Node = null) -> void:
	if not _provoked:
		_provoked = true
		if faction != null:
			Reputation.add_reputation(faction, -Reputation.PROVOKE_REP_PENALTY)

## Aggro-on-attack: when the PLAYER damages us while we are NOT already hostile, provoke. Wired by
## Character.take_damage. We only react to the player (the attacker is in the "Player" group), so an
## enemy hitting us with friendly fire / a stray explosion doesn't flip a neutral NPC against the
## player. Overrides Character._on_damaged_by.
func _on_damaged_by(attacker: Node, _was_crit: bool = false) -> void:
	if is_hostile():
		return
	if attacker != null and attacker.is_in_group(&"Player"):
		provoke(attacker)
