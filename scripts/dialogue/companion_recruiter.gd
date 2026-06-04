class_name CompanionRecruiter
extends RefCounted

## The recruit/dismiss contract resolution for the dialogue companion button — pure, stateless logic
## pulled out of DialogueManager so the coordinator only handles the button SPAWN + re-render. A speaker
## "opts in" by exposing the follow contract (can_recruit / start_following / stop_following / is_following,
## all has_method-guarded); anything that doesn't (a car, a terminal, a hostile NPC) yields no button and
## is wholly unaffected. The follow BEHAVIOUR lives on the NPC — these statics only read the contract and
## invoke it.

## The recruit/dismiss button's label for `speaker`, or "" for no button. Mirrors the monolith's priority:
## a companion mid-follow offers "Wait here" (dismiss wins, even if can_recruit() would also read true —
## you can't re-recruit something already at your side); else a recruitable speaker offers "Follow me";
## else "" so a non-recruitable speaker (inanimate, hostile, already-leader) shows nothing. All
## has_method-guarded so a partial implementation is safe.
static func label_for(speaker: Node) -> String:
	if speaker == null or not is_instance_valid(speaker):
		return ""
	var following: bool = speaker.has_method(&"is_following") and speaker.is_following()
	var recruitable: bool = speaker.has_method(&"can_recruit") and speaker.can_recruit()
	if not following and not recruitable:
		return ""
	return "Wait here" if following else "Follow me"

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
		var player := tree.get_first_node_in_group(&"Player") as Node3D
		if speaker.has_method(&"start_following"):
			speaker.start_following(player)
