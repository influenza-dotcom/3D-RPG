@tool
class_name CrippleCallout
extends Node

## Drop-in: announces a crippled limb. When THIS actor has a limb crippled it (1) toasts the player who did it,
## by name + part — "Crippled Kyle's arm" — and (2) cries out its authored `self_bark_template` (empty by
## default = silent; a lethal hit never calls out — a dying actor doesn't cry). Drop it under an NPC; the NPC
## calls react() from its _on_limb_crippled hook.
## AUTO-ADDED by NPC._build_components when you don't drop one in, so behaviour is unchanged — drop a CONFIGURED
## instance to retint the toast, or set `enabled = false` to silence the callouts (a mute enemy).
##
## Portable (Type-1 drop-in): every host access is DUCK-TYPED (host._real_player()/display_name/_dead/hp/
## _find_talkable()/_emit_bark()), so it works on any actor exposing that surface — it references NO NPC type.
## The one hard type is Character.BodyPart (the limb-index enum it maps to a word), a base enum every Character
## shares; it is fully qualified (Character.BodyPart.HEAD) because this extends Node, not Character, so it does
## not inherit the bare enum. (Precedent: npc_outline.gd / test_character.gd reference it the same way.)

## Off = no cripple callouts at all (neither the attacker toast nor the self-bark).
@export var enabled: bool = true
## Colour of the "Crippled X's leg" toast shown to the player who crippled this actor. Per-instance tunable
## (CLAUDE.md: never bake a designer-facing colour as a const). Default = the amber the inline code shipped.
@export var toast_color: Color = Color(1.0, 0.82, 0.3)
## What the actor CRIES OUT when a limb is crippled — authored speech, so it ships EMPTY (= silent).
## `%s` is replaced with the part word ("head"/"arm"/"leg"), e.g. author "My %s!" for the classic callout.
@export var self_bark_template: String = ""

## Called by the host from its _on_limb_crippled virtual (a dispatch-by-name Character hook that stays a thin
## shell on the root, because the Character base still needs to own the cripple SFX + head-stagger). `host` is
## duck-typed so a bare-instance unit test can drive it with a stub. `part` is a Character.BodyPart int; `attacker`
## is who dealt the crippling hit (may be null / a non-player).
func react(host: Variant, part: int, attacker: Node = null) -> void:
	if not enabled or host == null:
		return
	var part_name: String = _cripple_part_name(part)
	if part_name.is_empty():
		return  # TORSO (or any unmapped part) gets no callout
	# (1) Attacker toast — only when the HUMAN PLAYER crippled us. Companions share the &"Player" group but lack
	# notify_toast, so the has_method gate excludes them — this is equivalent to the inline `not (attacker is NPC)`
	# check the root used, but WITHOUT hard-coupling this drop-in to the NPC class. Fires even on a lethal hit.
	if attacker != null and attacker.is_in_group(Groups.PLAYER) and attacker.has_method(&"notify_toast"):
		var p: Node = host._real_player()
		if p != null and p.has_method(&"notify_toast"):
			var who: String = GameState.public_name(host.display_name)  # "Crippled Stranger's leg" until introduced
			if who.is_empty():
				who = "Enemy"
			p.notify_toast("Crippled %s's %s" % [who, part_name], toast_color)
	# (2) Self-bark — authored speech only (empty template = silent), and a dying actor doesn't cry out.
	if self_bark_template.is_empty() or host._dead or host.hp <= 0.0:
		return
	var talkable: Variant = host._find_talkable()
	if talkable == null:
		return
	host._emit_bark(self_bark_template % part_name if "%s" in self_bark_template else self_bark_template, talkable.voice)

## BodyPart int -> the word used in both callouts. Pure (reads no host state), so a unit test pins the mapping
## directly. Character.BodyPart.* is fully qualified because a Node-extending component doesn't inherit the enum.
static func _cripple_part_name(part: int) -> String:
	match part:
		Character.BodyPart.HEAD:
			return "head"
		Character.BodyPart.ARMS:
			return "arm"
		Character.BodyPart.LEGS:
			return "leg"
	return ""

## Editor hint (duck-typed to stay portable): this drop-in needs a host that emits barks. Warn on a parent that
## can't, rather than pinning it to the NPC class (which would make an otherwise-portable drop-in NPC-only).
func _get_configuration_warnings() -> PackedStringArray:
	var parent := get_parent()
	if parent != null and parent.has_method(&"_emit_bark"):
		return PackedStringArray()
	return PackedStringArray(["CrippleCallout expects a host that announces limb cripples (e.g. an NPC): its parent needs an _emit_bark() method."])
