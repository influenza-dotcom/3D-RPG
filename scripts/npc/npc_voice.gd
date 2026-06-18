class_name NpcVoice
extends Node

## NPC bark / social-voice ORCHESTRATION, split off npc.gd (Wave 3 SRP, #6). Owns the per-NPC bark cooldowns
## and the trigger logic deciding WHEN an NPC speaks: detection call-outs, ally/assist reactions, the
## reload / combat-over / lost-interest shouts, the FNV hover greeting, and the death-witness social
## ("Murderer!" / "Good riddance.").
##
## The bark DATA + EMISSION stay on the NPC — the line constants, _pick_bark / _bark_pool, _bark_duration_ms,
## _emit_bark / _speak_bark, and the speech-bubble visuals — because they're pure / presentation and pinned by
## the test suite; this component reaches back into `host` for them. NPC keeps a 1-line facade per public
## trigger (greet / react_remark / thank_for_assist / _cry_wounded / _try_*_bark / _witness_death /
## _announce_death_to_witnesses) so its call-sites + the has_method tests are unchanged.
##
## `host` is typed Node (not NPC) to break the NpcVoice <-> NPC class-reference cycle (NPC creates this), so
## every host.X is a dynamic call resolved at runtime. Built in NPC._build_components, handed `host` + the
## profile's BarkSet, like the other NPC child components.

var host: Node = null  ## the NPC we speak for (Node-typed to avoid the class cycle)

## The resolved bark lines for THIS NPC: a profile's BarkSet (NpcData.bark_set) when set, else empty — each
## empty category falls back to the NPC's BARK_* line consts via host._bark_pool. Seeded by _build_components.
var _bark_set: BarkSet = BarkSet.new()
var _last_bark_msec: int = -100000   ## per-NPC bark cooldown (paces every bark path below)
var _last_greet_msec: int = -100000  ## separate cooldown for the look-at hover greeting (greet())
var _last_search_msec: int = -100000 ## SEPARATE cooldown for the active-search mutter (bark_searching), so the
									 ## per-frame hunt line never stamps the shared cooldown and starve the one-shot
									 ## "lost interest" give-up line that fires the moment the search expires

## Designer gates, seeded from the NpcData profile (damage_barks / death_barks) in NPC._build_components;
## default ON so an unprofiled NPC is unchanged. When off, the matching bark is muted at its trigger (the
## line pools are untouched — the NPC just stays quiet there).
var damage_barks_enabled: bool = true   ## the HURT cry when wounded (_cry_wounded)
var death_barks_enabled: bool = true    ## the death-witness reaction (_witness_death)
var search_barks_enabled: bool = true   ## the "where are you?" hunt mutter while searching (bark_searching)


## Detection bark: when this NPC spots a HOSTILE (player or enemy NPC) and is a speaking character, it calls
## out — floating text + spoken TTS. Gated near the player so the world text stays readable; a fleer stays
## silent (it's running). Per-NPC cooldown only; many NPCs can shout at once.
func _try_detection_bark() -> void:
	if host.is_fleeing() or host._dead or host.hp <= 0.0:
		return
	if not (is_instance_valid(host._target) and host.is_hostile_to(host._target)):
		return  # bark for ANY hostile it spotted — the player OR an enemy NPC
	var talkable = host._find_talkable()
	if talkable == null:
		return  # only a speaking character (a Talkable) barks
	var player = host._real_player()
	if player == null or host.global_position.distance_to(player.global_position) > host.BARK_DISTANCE:
		return  # keep it near the listener — the voice is 2D and the text would be unreadably far
	var now := Time.get_ticks_msec()
	if now - _last_bark_msec < host.BARK_COOLDOWN_MS:
		return
	_last_bark_msec = now
	host._emit_bark(host._pick_bark(host.BARK_LINES, _bark_set.spot), talkable.voice)


## Friendly/ally flavour reaction (reckless fire, aimed-at): float + speak a random line — only if this NPC is
## a non-hostile, out-of-combat speaker. Reuses the per-NPC bark cooldown so reactions never spam.
func react_remark(lines: Array[String]) -> void:
	if lines.is_empty() or host.is_hostile() or host.is_in_combat() or host._dead or host.hp <= 0.0:
		return
	var talkable = host._find_talkable()
	if talkable == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bark_msec < host.BARK_COOLDOWN_MS:
		return
	_last_bark_msec = now
	host._emit_bark(lines[randi() % lines.size()], talkable.voice)


## A wounded ALLY cries out ("I'm hurt..."). Unlike react_remark this does NOT gate on being out-of-combat (a
## hurt ally calls out mid-firefight) — just needs a Talkable + the per-NPC bark cooldown.
func _cry_wounded() -> void:
	if not damage_barks_enabled:
		return  # designer muted the hurt cry for this archetype (gate checked first, before any host read)
	if host._dead or host.hp <= 0.0:
		return
	var talkable = host._find_talkable()
	if talkable == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bark_msec < host.BARK_COOLDOWN_MS:
		return
	_last_bark_msec = now
	host._emit_bark(host._pick_bark(host.HURT_LINES, _bark_set.hurt), talkable.voice)


## Said by an NPC the player just helped (player damaged the enemy it was fighting, which then died):
## "Hey, thanks!". Non-hostile speakers only; reuses the bark cooldown + reaction delay.
func thank_for_assist() -> void:
	if host.is_hostile() or host._dead or host.hp <= 0.0:
		return
	var talkable = host._find_talkable()
	if talkable == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bark_msec < host.BARK_COOLDOWN_MS:
		return
	_last_bark_msec = now
	host._emit_bark(host._pick_bark(host.THANKS_LINES, _bark_set.thanks), talkable.voice)


## Reload call-out ("Reloading!") — fired when the AI ducks to reload. Mid-combat is fine: needs a Talkable,
## the player in earshot, and the bark cooldown.
func _try_reload_bark() -> void:
	if host._dead or host.hp <= 0.0:
		return
	var talkable = host._find_talkable()
	if talkable == null:
		return
	var player = host._real_player()
	if player == null or host.global_position.distance_to(player.global_position) > host.BARK_DISTANCE:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bark_msec < host.BARK_COOLDOWN_MS:
		return
	_last_bark_msec = now
	host._emit_bark(host._pick_bark(host.RELOAD_LINES, _bark_set.reload), talkable.voice)


## Combat-over call-out ("Lost 'em.") — fired once when a fighter returns to UNAWARE after having been ALERTED.
## Fleers don't taunt, so they're excluded.
func _try_combat_end_bark() -> void:
	if host._dead or host.hp <= 0.0 or host.is_fleeing():
		return
	var talkable = host._find_talkable()
	if talkable == null:
		return
	var player = host._real_player()
	if player == null or host.global_position.distance_to(player.global_position) > host.BARK_DISTANCE:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bark_msec < host.BARK_COOLDOWN_MS:
		return
	_last_bark_msec = now
	host._emit_bark(host._pick_bark(host.COMBAT_END_LINES, _bark_set.combat_end), talkable.voice)


## Lost-interest call-out ("Must be gone now.") — fired once when an NPC that only NOTICED a threat (never
## ALERTED) gives up searching. A calm remark, so unlike the combat-over taunt it ISN'T gated to fighters.
func _try_lost_interest_bark() -> void:
	if host._dead or host.hp <= 0.0:
		return
	var talkable = host._find_talkable()
	if talkable == null:
		return
	var player = host._real_player()
	if player == null or host.global_position.distance_to(player.global_position) > host.BARK_DISTANCE:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bark_msec < host.BARK_COOLDOWN_MS:
		return
	_last_bark_msec = now
	host._emit_bark(host._pick_bark(host.LOST_INTEREST_LINES, _bark_set.lost_interest), talkable.voice)


## Tell every nearby NPC that the player just killed our host, so each can react (see _witness_death). Called
## from NPC._on_died ONLY for a player-caused death, so enemy infighting / environmental deaths stay quiet.
func _announce_death_to_witnesses() -> void:
	for n in host.get_tree().get_nodes_in_group(&"npc"):
		var witness = n
		if witness == null or witness == host:
			continue
		if host.global_position.distance_to(witness.global_position) > host.DEATH_WITNESS_RADIUS:
			continue
		witness._witness_death(host)  # the witness NPC's facade -> its own NpcVoice


## React to having just seen the player kill `victim`: a co-aligned peer is outraged ("Murderer!"); an unallied
## bystander only remarks on a HOSTILE enemy's death — a friendly ally cheers it, everyone else questions it.
## react_remark self-filters (a hostile / in-combat / mute witness stays silent) + shares the bark cooldown.
func _witness_death(victim) -> void:
	if not death_barks_enabled:
		return  # designer muted death-witness reactions for this archetype (gate checked first, before any host read)
	if victim == null or victim == host or host._dead or host.hp <= 0.0:
		return
	if host._is_ally_of(victim):
		react_remark(host._bark_pool(host.DEATH_ALLY_LINES, _bark_set.death_ally))
		return
	if victim.is_hostile() and host.resolved_disposition() == Disposition.Kind.FRIENDLY:
		react_remark(host._bark_pool(host.DEATH_APPROVE_LINES, _bark_set.death_approve))
	else:
		react_remark(host._bark_pool(host.DEATH_QUESTION_LINES, _bark_set.death_question))


## FNV-style hover greeting: a short line spoken when the player's crosshair first lands on this (non-hostile,
## idle) NPC. Its OWN cooldown (not the bark cooldown) so glancing back and forth doesn't spam it.
func greet() -> void:
	if host.is_hostile() or host.is_in_combat() or host._dead or host.hp <= 0.0:
		return
	var now := Time.get_ticks_msec()
	if now - _last_greet_msec < host.GREET_COOLDOWN_MS:
		return
	var talkable = host._find_talkable()
	if talkable == null:
		return
	_last_greet_msec = now
	host._emit_bark(host._pick_bark(host.GREET_LINES, _bark_set.greet), talkable.voice)


## "Cut that out!" — the player hit this (still) non-hostile NPC WITHOUT aggroing it: an ally absorbing
## stray fire under its friendly_aggro_threshold. Fired from NPC._on_damaged_by's forgiven branch. Needs a
## Talkable + the per-NPC bark cooldown; NOT gated on combat (an ally fighting beside you still snaps at a
## stray shot) — the host is non-hostile by construction on this path.
func warn_attack() -> void:
	if host._dead or host.hp <= 0.0:
		return
	var talkable = host._find_talkable()
	if talkable == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bark_msec < host.BARK_COOLDOWN_MS:
		return
	_last_bark_msec = now
	host._emit_bark(host._pick_bark(host.WARN_ATTACK_LINES, _bark_set.warn_attack), talkable.voice)


## "Alright, that does it!" — the player's attack just AGGROED this NPC (the provoke moment: an ally's
## threshold crossed, or a neutral's first hit). Fires at most once per provoke cycle (the caller's
## non-hostile branch can't re-run while hostile), so it SKIPS the cooldown read and force-clears any
## on-screen bark (likely the warn above) so the payoff line always lands; it still stamps the cooldown.
## No hostility/combat gate — the host has JUST turned hostile, and that's the point.
func bark_aggro() -> void:
	if host._dead or host.hp <= 0.0:
		return
	var talkable = host._find_talkable()
	if talkable == null:
		return
	_last_bark_msec = Time.get_ticks_msec()
	host._clear_bark_bubble()  # replace a pending warn bubble instead of being suppressed by its overlap gate
	host._emit_bark(host._pick_bark(host.AGGRO_LINES, _bark_set.aggro), talkable.voice)


## Panic call-out ("Forget this!") — fired the MOMENT a fighter BREAKS and flees: a FIGHT NPC whose temperament
## flips it to FLEE under fire (the player shot it and it runs rather than fight back). A mid-combat call-out
## like the reload shout: needs a Talkable, the player in earshot, and the bark cooldown. Deliberately NOT gated
## on is_fleeing — this IS the flee moment (the other combat barks mute themselves for fleers; this replaces
## that silence with a one-shot panic line, since the flip fires once in _on_damaged_by).
func bark_flee() -> void:
	if host._dead or host.hp <= 0.0:
		return
	var talkable = host._find_talkable()
	if talkable == null:
		return
	var player = host._real_player()
	if player == null or host.global_position.distance_to(player.global_position) > host.BARK_DISTANCE:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bark_msec < host.BARK_COOLDOWN_MS:
		return
	_last_bark_msec = now
	host._emit_bark(host._pick_bark(host.FLEE_LINES, _bark_set.flee), talkable.voice)


## Spotted-a-body call-out ("Hey -- a body!") -- fired the moment an UNAWARE NPC notices a discoverable corpse
## (stealth body-discovery). Like the detection bark: needs a Talkable, the player in earshot, and the bark
## cooldown. NOT a combat line (the NPC is only INVESTIGATING the spot, not fighting), so it isn't fleeing-gated.
func bark_check_body() -> void:
	if host._dead or host.hp <= 0.0:
		return
	var talkable = host._find_talkable()
	if talkable == null:
		return
	var player = host._real_player()
	if player == null or host.global_position.distance_to(player.global_position) > host.BARK_DISTANCE:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bark_msec < host.BARK_COOLDOWN_MS:
		return
	_last_bark_msec = now
	host._emit_bark(host._pick_bark(host.CHECK_BODY_LINES, _bark_set.check_body), talkable.voice)


## Active-search call-out ("Where are you?") — muttered WHILE this NPC hunts a lost target / a noise (between the
## "!" and the give-up line). Gated by the designer's search_barks toggle, then like the body bark: needs a
## Talkable + the player in earshot + the bark cooldown (which paces it to an occasional mutter even though the
## search loop calls it every frame). Not a combat shout — the NPC is only INVESTIGATING, so it isn't fleeing-gated.
func bark_searching() -> void:
	if not search_barks_enabled:
		return  # designer muted the hunt mutter for this archetype (gate checked first, before any host read)
	if host._dead or host.hp <= 0.0:
		return
	var talkable = host._find_talkable()
	if talkable == null:
		return
	var player = host._real_player()
	if player == null or host.global_position.distance_to(player.global_position) > host.BARK_DISTANCE:
		return
	var now := Time.get_ticks_msec()
	if now - _last_search_msec < host.BARK_COOLDOWN_MS:
		return
	_last_search_msec = now  # own cooldown -> never consumes the shared one the give-up line needs
	host._emit_bark(host._pick_bark(host.SEARCH_LINES, _bark_set.search), talkable.voice)
