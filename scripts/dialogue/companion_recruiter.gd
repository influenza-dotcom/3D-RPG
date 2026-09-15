class_name CompanionRecruiter
extends RefCounted

## The recruit/dismiss contract resolution for the dialogue companion button — pure, stateless logic
## pulled out of DialogueManager so the coordinator only handles the button SPAWN + re-render. A speaker
## "opts in" by exposing the follow contract (can_recruit / start_following / stop_following / is_following,
## all has_method-guarded); anything that doesn't (a car, a terminal, a hostile NPC) yields no button and
## is wholly unaffected. The follow BEHAVIOUR lives on the NPC — these statics only read the contract and
## invoke it.
##
## ⭐THE `speaker` GUARDS BELOW CATCH null, NOT A FREED NODE — VALIDATE AT THE CALL SITE. `speaker` is a typed
## `Node` parameter, so GDScript type-checks the argument at the CALL BOUNDARY and raises "Invalid type in
## function '<name>' ... (previously freed) is not a subclass of the expected argument class" BEFORE the body
## runs; an in-body `is_instance_valid` can never suppress that (the same family as a lambda's freed capture,
## which is checked before the lambda body). It is not a cosmetic log, either: the rejection ABORTS THE
## CALLING FUNCTION at that line — only the caller's own caller resumes — so an unguarded call site stops
## part-way through whatever it was building. So a caller holding a possibly-freed speaker — DialogueManager
## keeps `_speaker` until _finish(), and a scene swap under a live conversation frees the node without
## clearing it — MUST check validity itself; _reveal_menu, _on_companion_pressed and _resume_from_menu all do.
## The `is_instance_valid` half is KEPT rather than trimmed as dead: that boundary rejection is an engine-side
## check we don't want these statics' safety to depend on, and it costs nothing here.

## Whether `speaker` is currently following (mid-follow companion). THE behaviour predicate for the
## recruit/dismiss button: DialogueManager binds this — never a comparison against the button's label text —
## as apply()'s `was_following`. A UI label is display-only and must never be a behaviour key (relabeling
## "Wait here", or localizing it, must not silently flip recruit into dismiss). has_method-guarded so a
## speaker without the follow contract simply reads as not-following.
static func following(speaker: Node) -> bool:
	if speaker == null or not is_instance_valid(speaker):
		return false
	return speaker.has_method(&"is_following") and speaker.is_following()

## The recruit/dismiss button's label for `speaker`, or "" for no button. Mirrors the monolith's priority:
## a companion mid-follow offers "Wait here" (dismiss wins, even if can_recruit() would also read true —
## you can't re-recruit something already at your side); else a recruitable speaker offers "Follow me";
## else "" so a non-recruitable speaker (inanimate, hostile, already-leader) shows nothing. All
## has_method-guarded so a partial implementation is safe. PURE DISPLAY: callers branch on following(),
## never on this text.
static func label_for(speaker: Node) -> String:
	if speaker == null or not is_instance_valid(speaker):
		return ""
	var is_follow := following(speaker)
	var recruitable: bool = speaker.has_method(&"can_recruit") and speaker.can_recruit()
	if not is_follow and not recruitable:
		return ""
	# The strings live on PlayerText with the other dialogue options (the tr()-sweep single-file guarantee);
	# this helper only PICKS between them.
	return PlayerText.DIALOGUE_OPTION_WAIT_HERE if is_follow else PlayerText.DIALOGUE_OPTION_FOLLOW

## Apply the recruit/dismiss action the button represents. Calls the matching contract method on the
## speaker — stop_following() when it was following, else start_following(player) with the player resolved
## from the "Player" group. All has_method-guarded so a partial implementation is safe. The caller
## re-renders the line afterwards so the button flips "Follow me" <-> "Wait here" live.
static func apply(speaker: Node, was_following: bool, tree: SceneTree) -> void:
	if speaker == null or not is_instance_valid(speaker):
		return
	if was_following:
		if speaker.has_method(&"stop_following"):
			speaker.stop_following()
	else:
		var player := tree.get_first_node_in_group(Groups.PLAYER) as Node3D
		if speaker.has_method(&"start_following"):
			speaker.start_following(player)
