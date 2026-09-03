extends Node
## @system Save Model
## @seam capture() -> save_to_disk atomically write the versioned user://gamestate.cfg; load_from_disk restores it and sets loaded/profile_active, the flags gating Player._ready — a checkpoint, not a world snapshot.
## @risk Breaking _write_atomic's tmp->bak->rename rotation (e.g. dropping the Windows remove-before-rename guard) only loses the sole save on a real crash; the happy path keeps succeeding, so tests never surface it.
## @risk A field wired into only some of capture/save_to_disk/load_from_disk silently defaults on Continue; a STAT_NAMES rename with no SAVE_VERSION migration drops those points (cf. load_from_disk's legacy stat folds).
## @risk Dropping capture()'s Zorkmids.ITEM_ID skip lets a stray coin tile restore as cash the wallet never counted; applying respawn_position while ignoring respawn_level_matches teleports the player into the wrong level.
## @risk The dev sandbox (enable_sandbox / resolve_save_path) redirects the five canonical save paths at exactly six seams — a new read/write of SAVE_PATH / QUICKSAVE_PATH / slot_path that skips resolve_save_path silently sees or writes the REAL profile while a console `sandbox on` is in force.
## @test res://tests/test_game_save.gd
## @test res://tests/test_save_slots.gd
## @test res://tests/test_debug_sandbox.gd

## @system Save Model
## @seam The additive per-object ledger world_objects[level][key]=state (record_object_state/object_state/has_object_state) persists Door open/locked + consumed-pickup/destroyed-prop 'gone' bits per authored object.
## @risk A changed WorldSaveId key or a stricter load_from_disk Dictionary-shape filter silently drops ledger entries — pickups respawn (free money), doors revert, smashed props un-smash; load still returns true.
## @risk Reading a 'gone' bit with bare truthiness instead of GameState.as_bool falsely despawns a fresh pickup (or crashes via bool(<String>)) on a hand-edited String value.
## @risk A new persistable object type not wired through record_object_state + a save_id export silently never enters the ledger — its state just doesn't persist.
## @test res://tests/test_game_save.gd
## GameState — the live run's autosaved PROFILE + its RESPAWN point.
##
## Dark Souls style, ONE autosave (the run's checkpoint; a separate manual quicksave + 3 slots are the ML-1 layer below): the run persists to user://gamestate.cfg so quitting and
## relaunching resumes where you left off. The profile is the player's progression — money, the stat sheet, the
## unlocked mechanics, and the backpack (items + the drawn weapon, keyed by Item.id through ItemDb) — plus the
## respawn point (the last bonfire, or the initial spawn). It is captured + written
## at every milestone: a wallet change (kill bounty / trade / pickup), a level-up, an upgrade pickup, and a
## bonfire rest. On DEATH the world is NOT reloaded — you're brought back to LIFE at the respawn point (enemies
## stay as they are); the autosave is the only thing that survives quitting.
##
## Boot: this autoload's _ready loads the save (if any) into memory, so the start menu can offer "Continue" and
## the Player's _ready can apply the loaded build. "New Game" calls reset_for_new_game() to start clean.
##
## SAVE SCOPE — this is a PROFILE / checkpoint save with an ADDITIVE per-object ledger, NOT an exact world
## snapshot. It persists the player's progression (money, stats, unlocks, perks, backpack), the run's world FLAGS +
## QUEST state + faction standing + day/night clock, discovered Corpse markers, and the ACTIVE LEVEL identity
## (current_level_path, so a reload returns you to the level the saved respawn belongs to). It ALSO now persists a
## NAMED per-placed-object ledger (world_objects, keyed by level + WorldSaveId.key_for): a Door's open/locked
## state, and a consumed CanPickUp / MoneyPickUp / UpgradePickup / destroyed CanDestroy prop's "gone" bit — so an
## opened door stays open, a collected pickup stays collected (no respawn / infinite-money), and a smashed crate
## stays smashed on Continue. It STILL does NOT persist: looted / refilled containers, dead NPCs,
## dynamically-spawned entities (loot drops / encounter NPCs), or NPC positions — and it is NOT an exact snapshot
## (only touched, authored objects are in the ledger). LIVE WEAPON CLIP ammo is not persisted either: every gun
## loads a FULL magazine on Continue (the backpack's spare-CLIP reserve DOES persist) — a deliberate
## fresh-magazine-per-session choice. The ledger is additive: it never rebrands the profile save as an exact
## quicksave. See CLAUDE.md "Save semantics must be explicit".

const SAVE_PATH := "user://gamestate.cfg"
## Save schema version, stamped into [meta].version on every write (H1b). Bump ONLY for a BREAKING change to an
## existing key's MEANING; additive new sections stay back-compatible via their has_section checks. A pre-versioning
## save (no [meta]) reads 0. v2 (C43) was the FIRST version-gated read: the 2026-07-09 stat overhaul renamed the
## "persuasion" stat to "streetwise", so a <v2 save's persuasion points are folded into streetwise on load (the
## stat-load loop drops unknown keys, so without the migration those points would silently vanish). v3 is the SECOND:
## the "stealth" and "pickpocket" stats were consolidated into a single "larceny" stat, so a <v3 save's stealth AND
## pickpocket points both fold into larceny on load. Re-saving stamps the current version and each migration re-runs
## never. Future breaking migrations branch on save_version the same way (separate `if` branches, so a very old save
## runs every fold it needs in one load). v4 is the THIRD (Slice 3, stable NPC identity): [world].known_names entries
## changed MEANING from raw display-name strings to identity keys (NpcData.id, falling back to the authored display
## name). Its migration is LAZY, not a load-time fold — see the known_names load site for the mechanism and why.
## v5 is the FOURTH: the legacy NEGATIVE-WALLET fold (a pre-ATM save carried the implant bill as negative `money`)
## is now version-gated at <v5 like every other migration on this ladder. It used to run UNGATED, on the argument
## that it was idempotent by construction — but that argument rests on the wallet being cash-only, and
## DialogueChoice.give_money is documented as taking a NEGATIVE amount for a fee/cost, so a CURRENT run's wallet
## can legitimately land below zero. Ungated, the next load would silently convert that cash shortfall into
## interest-bearing bank debt. See the fold in load_from_disk.
const SAVE_VERSION := 5
## The CharacterStats, by name — the columns of the [stats] save section. Derived from CharacterStats.STAT_NAMES
## (the single source; cannot drift — a stat added there becomes a save column here for free). Missing keys default
## to 0, so older mid-development profile saves migrate softly. A compile-time const fold (no autoload/cycle issue).
const STAT_NAMES: Array[StringName] = CharacterStats.STAT_NAMES
## Exact-snapshot serializer for the manual save tier (preloaded, NOT class_name — no global-class-cache
## dependency, so headless GUT compiles GameState without a prior --import; the same idiom as QuestTrackerScript
## below, and as WorldSaveId in every component that keys the world_objects ledger).
const WorldSnapshot = preload("res://scripts/world/world_snapshot.gd")

## QUESTS LIVE ON THE `QuestTracker` AUTOLOAD (M1 split). The four quest SIGNALS moved with the state — connect to
## `QuestTracker.quest_started` / `objective_advanced` / `quest_completed` / `quest_failed`, not to GameState. The
## quest *function* API is still forwarded from here (see the "Quests" region near the bottom) so authored content
## and existing call sites keep working; new code should call QuestTracker directly.

## THE WORLD MAY RESET NOW — the player died and the death cinematic's screen has just gone FULLY BLACK, right as
## the "You were killed by X" card comes up (emitted from Player._on_death_screen_covered, a tween callback; NOT
## from die(), which is ~1.6 s earlier while the vignette is still closing and the world is plainly visible).
## Listeners are expected to REARRANGE THE WORLD, so the timing is the contract: fire anything visible here and it
## lands behind the black instead of on screen. Runs after the killer-aware Character._on_killed_by hook (which
## settles provoked grudges), so the two compose — the town calms down AND goes home.
##
## A CUE, not save state: nothing about it is captured or written. It lives on this autoload (rather than each
## listener hunting down the Player node) so a listener can connect once at _ready with no spawn-order handshake,
## and keep that connection across an NpcPool reuse. First consumer: the NpcHomeReturn leash
## (scripts/npc/npc_home_return.gd), which blinks every NPC back to its authored post — the default
## CHECKPOINT_RESPAWN death mode leaves the world untouched, so without it an encounter never resets.
@warning_ignore("unused_signal")  # emitted from Player.die() (player.gd), never from this autoload
signal player_died()

## True once a save has been loaded into the fields below (boot found a file, or Continue was chosen). The Player's
## _ready reads this: true -> apply the saved build (stats / money / unlocks / teleport); false -> a fresh game.
var loaded: bool = false
## True once a real run is authoritative IN MEMORY — set by a disk load OR by character creation (New Game). Unlike
## `loaded` it is NOT cleared by a scene reload, so a New-Game session survives a RELOAD_CHECKPOINT_FRESH death: the
## death path promotes `loaded = true` when this is set, so the fresh Player APPLIES the in-memory run (unlocks/xp/
## money/inventory) instead of reseeding a default build (P0-2). A dev boot straight into game.tscn leaves it false.
var profile_active: bool = false
## The [meta].version of the loaded save (0 = a pre-versioning save; SAVE_VERSION after a New Game). Recorded on load
## and now CONSUMED by the C43 <v2 persuasion→streetwise stat migration in load_from_disk (H1b's first version-gated
## read); future breaking migrations branch on it the same way.
var save_version: int = 0
## saved wallet (fractional zorkmids — see Zorkmids); fresh-game seed reads the economy tuning group
## (explicitly annotated, NOT ':='-inferred off the GameSettings chain). EconomySettings' default is 0.0 (the player starts broke).
var money: float = GameSettings.economy.player_starting_money
## Emitted whenever `account` actually CHANGES value (an equal write is swallowed by the setter, so a listener
## can't be spammed by a no-op assignment). THE seam for reacting to the ledger balance — the HUD's OWED row, the
## terminal screens, any future creditor: connect here rather than polling GameState.account every frame.
signal account_changed(value: float)

## Backing store for `account`. The property below is a get/set pair and an inline setter that assigned to its OWN
## name would re-enter itself forever, so the value has to live somewhere else. NEVER write `_account` directly —
## that skips the signal and every listener then paints a stale balance.
var _account: float = 0.0
## ⭐THE LEDGER ACCOUNT — ONE SIGNED number: POSITIVE is savings, NEGATIVE is what you owe. Debt and savings
## are therefore the same field with opposite signs, which is why "pay off your debt" and "deposit" are the
## SAME operation (Atm.deposit) and why you can never hold a death-safe hoard WHILE owing — every deposit is
## consumed by the debt until you are solvent.
##
## It lives ONLY here. It is never mirrored onto a Character, never read by capture(), and never touched by any
## death path (those move Character.money alone). Three consequences fall out for free:
##   * Player._ready has nothing to re-seed, so the reboot that killed an earlier transient debt field
##     (unlocks re-granted while the debt was refunded) is structurally impossible rather than merely guarded.
##   * Banked money is DEATH-SAFE with zero code — no death-path branch mentions it.
##   * You cannot die your way out of the Ledger: the debt is not in the wallet death empties.
## The New Game implant bill rides THIS field (start_menu._stamp_new_game_profile), not the wallet, so
## `money` stays cash-only and >= 0 for a created run.
##
## A get/set property over `_account` purely so every write fans out `account_changed`; the READ and WRITE surface
## is unchanged, so the existing `GameState.account = snappedf(GameState.account +/- n, Zorkmids.QUANTUM)` call
## sites (Atm.deposit/withdraw, LedgerAccrual, Player.charge, the New Game implant bill) keep working verbatim.
var account: float:
	get:
		return _account
	set(value):
		# EXACT compare, deliberately not is_equal_approx: every writer snaps to Zorkmids.QUANTUM first so an
		# unchanged write is bit-identical, while is_equal_approx's tolerance SCALES with magnitude (~10 zorkmids
		# at a 1e6 balance) — it would swallow a real interest posting on a large account and drop the write.
		if value == _account:
			return
		_account = value
		account_changed.emit(_account)
## The armed payment RAIL for purchases: "debit" (cash then savings, never crossing zero) or "credit" (the
## same draw order, but allowed below zero up to the live credit line). A String KEY, never an enum ordinal
## (a designer reordering an enum would silently re-map every existing save) and never a display string —
## PlayerText selects the caption from this key, the label-is-never-a-key rule.
var payment_method: String = "debit"
## ⭐YOUR RECORD WITH THE LEDGER — the earned half of the credit score, in
## [-economy.credit_standing_max, +credit_standing_max]. The four build lines rate who you ARE; this rates how
## you have BEHAVED, and it is the only way a mediocre build's rating climbs over a run. Fed by exactly three
## events: repaying debt at a terminal (Atm.deposit), sitting in arrears when interest posts (LedgerAccrual),
## and the Ledger's undisclosed conduct dividend (Character._award_kill — it likes headshots and declines to
## explain why). A fresh character has NO history, which is why credit_rating_for defaults it to 0 and New
## Game rates the build alone. Persisted; add through add_credit_standing so the clamp is never bypassed —
## and load_from_disk re-applies the SAME clamp, so a hand-edited save (or one written before a designer
## lowered credit_standing_max) can't carry a score past the live knob either.
var credit_standing: float = 0.0
## The character's chosen NAME (set once at character creation; "" for an unnamed or pre-naming save). Persisted in
## the [player] save section and applied to the live Player (Player.player_name) for display on the Stats screen.
## Never changes in-game, so capture() leaves it alone — it's authored at creation and simply carried on every save.
var player_name: String = ""
## The character's chosen APPEARANCE (head/body customizer), a lightweight save-friendly dict — NOT a live
## resource, so it round-trips cleanly through the ConfigFile save. Keys (all optional): "head"/"body" = String
## part ids into CharacterAppearanceCatalog, "skin"/"arm"/"leg" = Colour tints, "shirt" = a player-DRAWN torso
## texture stored as PNG BYTES (PackedByteArray; decoded by CharacterAppearanceCatalog.shirt_texture). EMPTY = never
## customised -> every consumer (the creation/Stats preview) falls back to the catalog's shipped default look.
## Authored at character creation and simply carried on every save (capture() leaves it, like player_name —
## appearance never changes in-game). A stored part id that's since been removed from the catalog resolves to the
## default on load.
var appearance: Dictionary = {}
var stat_values: Dictionary = {}           ## StringName stat -> int; empty = all baseline (a fresh sheet)
var unlocks: Array[StringName] = []         ## the saved unlocked-mechanic ids (granted AND active — a switched-off implant lives in disabled_unlocks instead)
## Installed-but-switched-OFF implant ids (the Implants-tab toggle). A SEPARATE additive key — never folded
## into `unlocks` (that key's meaning is "granted and active"; changing it would be a save-schema break).
## Captured from player.disabled_list(), restored via player.set_disabled_unlocks AFTER set_unlocks. An older
## save simply has no [player].disabled_unlocks key -> empty -> nothing disabled (clean back-compat, no v-bump).
var disabled_unlocks: Array[StringName] = []

## The saved BACKPACK. has_inventory marks that the save carried an [inventory] section at all — an older save
## (written before inventory persisted) doesn't, and the Player then seeds its authored starting loadout instead
## of restoring an empty bag. Stacks are {id: String, count: int} in stack order (Item.id is the stable key,
## resolved back through ItemDb.restore_item_from_save); a modified weapon stack can also carry `weapon_delta`.
## equipped_index is WHICH stack was the drawn weapon (-1 = fists).
var has_inventory: bool = false
var inventory_stacks: Array = []
var equipped_index: int = -1

## Saved FACTION STANDINGS — faction_id (String) -> standing (float). Captured from the Reputation autoload;
## the Player applies them back via Reputation.restore on a loaded game (a fresh game starts at zero). Empty
## until a run earns some, and an older save with no [reputation] section simply loads none.
var reputation: Dictionary = {}

## Saved DAY/NIGHT clock (WorldClock.time_of_day, 0..1) — captured from the WorldClock autoload and re-applied by
## the Player on load, so reloading doesn't snap the world back to noon (the default) and yank schedule-driven NPCs
## to their day routine. A save written before the clock persisted has no [clock] section and loads the noon default.
var time_of_day: float = 0.5

## Saved active STATUS EFFECTS on the player (CT-3): [{path: String, remaining: float}], so a buff/debuff survives a
## reload (anti quicksave-scum) with its countdown intact instead of vanishing. Effects are referenced by .tres path
## (a code-built effect with no resource_path can't round-trip and is skipped). Empty / missing section = none.
var status_effects: Array = []

## Saved ACTIVE LEVEL — the LevelData.resource_path GameRoot last loaded (set by GameRoot.load_level). On a loaded
## game GameRoot reloads THIS level instead of its exported default, so Continue / quickload / a load-death return
## you to the level you saved IN — not the editor's start level — before the saved respawn position is applied.
## Empty (or a code-built LevelData with no resource_path) -> GameRoot falls back to its exported `level`.
var current_level_path: String = ""

## One-shot: a genuine disk-load (load_from_disk) or New Game (reset_for_new_game) sets this so the Player pushes
## the saved/noon clock onto the free-running WorldClock autoload EXACTLY ONCE. A death-respawn reload leaves it
## false, so the live clock carries forward instead of rewinding to the last autosave's time.
var _clock_apply_pending: bool = false

## STORY FLAGS — designer / quest world-state: a String key -> Variant (bool/int/String) store. Set by
## triggers, dialogue, locks and quests; read by gated choices / merchants / doors. Persisted in [flags] and
## survives like the rest of the profile (written on every autosave). String-keyed internally (StringName args
## coerce at the set/get/has boundary) to dodge the GDScript String-vs-StringName Dictionary-hash trap and to
## round-trip cleanly through ConfigFile.
var flags: Dictionary = {}

## Lightweight per-marker corpse discovery ledger. This is deliberately narrower than full object persistence:
## it only stores the one-shot "an NPC has already reacted to this Corpse" marker, keyed by Corpse.save_key()
## (which now delegates to the shared WorldSaveId.key_for, so it keys identically to the world_objects ledger).
var discovered_corpses: Dictionary = {}

## The "Stranger until introduced" name ledger: characters the player has LEARNED, used as a set of String keys.
## v4 (Slice 3): the canonical key is the IDENTITY key (NPC.identity_key — NpcData.id, falling back to the authored
## display name, so for every id-less NPC the key is still the name string exactly as v3 wrote it). reveal_name also
## records the display-name string when it differs from the identity key — the DISPLAY-COMPAT bridge for the
## string-keyed public_name surfaces (see reveal_name). Until a character's key is in here, every player-facing
## surface shows PlayerText.STRANGER in its place (see public_name) — and the gate opens the moment the player
## TALKS to them: DialogueManager.start calls reveal_name on any real character speaker, so one conversation (of
## any length, from any line) is the whole introduction. DialogueLine.reveals_name still calls reveal_name but is
## redundant for a character. Persisted in [world].known_names and CLEARED on New Game (a fresh run re-meets everyone as a
## stranger). Two NPCs sharing one display_name AND no ids are still "the same person" once introduced (v3
## behaviour); give them distinct NpcData.ids to keep their identities separate.
var known_names: Dictionary = {}

## Dev/global master switch for the masking above. true (default) = the shipped "everyone is a Stranger until
## introduced" behaviour; flip to false at runtime (console / a debug tool) to show every real name outright — the
## pre-feature behaviour, useful when authoring. NOT a player-facing Settings row and deliberately NOT serialized:
## it resets to true each launch so a debug flip never bakes into a save.
var stranger_names_enabled: bool = true

## The additive per-object WORLD-STATE ledger (v1): { level_path -> { object_key -> state Dictionary } }. A door's
## {"open","locked"}, a consumed pickup / destroyed prop's {"gone": true}. Keyed by level + WorldSaveId.key_for so
## each authored object round-trips independently. This is STILL a profile save with a named-object ledger, NOT an
## exact world snapshot — untouched objects, dynamically-spawned entities, and NPC positions are not captured.
var world_objects: Dictionary = {}

## THE PLAYER'S OWN MAP PINS: { level_path -> Array[Dictionary] }, each entry a WaypointBook record
## ({pos, name, note, icon, tint}, plus an optional {tracked} — see scripts/world/waypoint_book.gd for the
## shape and its clamps). Placed by hand from the Map tab (click the plan) or in the world with the Mark
## Waypoint key, painted by scripts/ui/minimap.gd on BOTH its hosts and by the top-centre heading tape, and
## persisted in [waypoints].
##
## PER LEVEL, like world_objects beside it and for the same reason: a pin is a place, and the map only ever
## draws one level. Cleared on New Game — a fresh run has not been anywhere yet.
##
## ⭐AT MOST ONE PIN IN THIS WHOLE DICTIONARY carries "tracked" — the profile's single active navigation
## marker, which is why the flag is a fact about the LEDGER rather than about a record and why nothing
## outside set_tracked_waypoint / the load fold below may write it. The invariant spans every level on
## purpose: tracking a pin in the next district and walking there is the loop it exists to serve.
##
## ⭐THIS IS PLAYER-AUTHORED TEXT, so nothing here may be painted through a Control that translates its own
## text (auto_translate_mode must be DISABLED at those sites — the menu_style.gd translation-seam rule) and
## nothing may reach a BBCode-parsing label. Every entry that enters memory comes through WaypointBook's
## sanitize/clean fold, including the ones a player hand-edits into their save file.
var waypoints: Dictionary = {}

## Bumped on EVERY waypoint mutation, and read by the minimap's idle gate as a drawn-options stamp.
##
## ⭐IT EXISTS BECAUSE A CanvasItem REPAINTS ONLY ON queue_redraw(). The map widget deliberately withholds
## that from a player who is standing still, so a pin added, renamed, re-iconed or deleted while nothing else
## on the map is moving would simply never appear (or never leave). Comparing one int per frame is what turns
## this ledger into a live surface — the same trailing-edge shape as the drawn-options / drawn-skin stamps,
## and cheap enough for the per-frame gate because it allocates nothing.
##
## Deliberately NOT persisted: it is a within-session change detector, not a fact about the profile, and a
## saved value would only ever be wrong on the next boot (the widget seeds its own stamp to a value no
## revision can equal, so the first paint after a load is forced regardless).
var waypoints_rev: int = 0

## --- EXACT-snapshot save tier (WorldSnapshot; manual quicksave/slots ONLY) -----------------------------------
## The in-memory exact snapshot for the manual save tier. NON-NULL only after a manual quicksave/slot save built
## one (in _capture_and_write) or a load pulled one off disk; the lean autosave/Continue path leaves it NULL and
## save_to_disk therefore never writes a [world_snapshot] section into gamestate.cfg. NOT part of the profile —
## kept structurally separate so the two save products can never blur (CLAUDE.md "Save semantics must be explicit").
var world_snapshot: WorldSnapshot = null
## One-shot: a load that carried a [world_snapshot] sets this true; GameRoot's post-level-load hook consumes it
## exactly once to apply the snapshot (a twin of _clock_apply_pending / consume_clock_apply). False on a
## profile-only load, a death-respawn reload, or a fresh game — so those never apply a snapshot.
var _world_snapshot_pending: bool = false
## Latched between "a quickload / slot-load / death reload (load_autosave) has loaded a save into memory + requested a scene reload" and "the fresh scene's
## GameRoot has booted" (cleared in set_current_level). While set, autosave() refuses to run: a one-frame-deferred autosave
## flush queued in the SAME frame as the load (a kill bounty / a door fire) would otherwise run AFTER load_from_disk, on the
## still-in-tree OLD player, and overwrite the just-loaded profile (and null the pending world_snapshot) with the abandoned
## timeline's state — then persist that franken-profile over the sole checkpoint. See _load_and_reload / autosave.
var _reload_pending: bool = false

## Save paths whose profile came off a FALLBACK rung (.tmp / .bak) instead of the primary. An entry is added by
## load_from_disk and erased by the first swap onto that SAME path that actually lands (_swap_into_place — reached
## from _write_atomic, or from a sandbox commit's copy-back) and by enable_sandbox for the sandbox paths it just
## replaced. While a path is listed, its write must NOT rotate the file at `path` into ".bak": the file it would
## rotate is the primary the ladder just REJECTED, so the rotation would bury the last intact checkpoint under the
## corrupt one — a fallback-recovered run survived exactly one autosave before its only good copy was gone.
##
## ⭐KEYED BY PATH, NOT A SINGLE FLAG. Saves are multi-file: the autosave profile, the F5 quicksave and three
## named slots each round-trip through save_to_disk(path) / _write_atomic(path). One shared flag is spent by
## whichever file writes FIRST — so a boot that recovered gamestate.cfg from .bak, followed by a quicksave,
## clears the flag on quicksave.cfg and lets the very next autosave rotate the still-corrupt gamestate.cfg
## over the only good checkpoint. That is the exact data loss this guard exists to prevent, so the guard has
## to be per-file. Session state, never persisted — it describes THIS boot's loads, not the profile.
var _recovered_from_fallback: Dictionary = {}

## Public read of the quickload-in-flight latch, so a per-frame subscriber (LedgerAccrual's dawn posting) can
## refuse to move a balance that is about to be thrown away, without reaching into the underscore field.
func reload_pending() -> bool:
	return _reload_pending

## THE one mutator for the credit record — clamped to +/- economy.credit_standing_max so no event, however
## mis-authored, can run the score off its rails. Returns what actually moved (0.0 = already at the clamp), so
## a caller can skip a toast nobody needs to read. Deliberately does NOT autosave: every caller is already at
## a save milestone (a terminal transaction, an interest posting) or is a per-kill hook far too hot to persist.
func add_credit_standing(delta: float) -> float:
	if is_zero_approx(delta):
		return 0.0
	var cap: float = maxf(0.0, GameSettings.economy.credit_standing_max)
	var before := credit_standing
	credit_standing = clampf(credit_standing + delta, -cap, cap)
	return credit_standing - before

## Live per-level ledger of authored NPCs that have died this run: { level_path -> { snapshot_key: true } }.
## Fed by record_npc_death (each NPC's died signal), read by WorldSnapshot.capture (a dead NPC has freed itself,
## so it can't be seen in the tree at capture time), and reloaded from a snapshot on a snapshot load so post-load
## deaths keep accumulating. Not persisted by the profile — it only reaches disk folded into a WorldSnapshot.
var _dead_authored: Dictionary = {}

## QUESTS — the tracker dicts and the B-F40 load-warning array moved to the `QuestTracker` autoload (M1). They are
## still persisted by THIS file's cfg (save_into / load_from below), because quest progress is part of the run profile.
##
## Script (not class_name) so there is no global-class-cache dependency and no parse cycle — QuestTracker.gd reaches
## back for `GameState` as a runtime autoload lookup, never a preload, so the compile-time edge runs one way only.
const QuestTrackerScript := preload("res://managers/QuestTracker.gd")

## The tracker this GameState drives. Resolved lazily by `_qt()`; a test may also wire one explicitly.
var quest_tracker: Node = null

## ⭐ THE QuestTracker THIS GameState DRIVES — and the reason quest tests stayed isolated across the M1 split.
##
## Quest state used to live on this file, so a unit test could build a bare `GameState.new()` and get a private
## journal for free. Moving it to an autoload would have made every such test share ONE journal: `test_game_save`
## proved it immediately — a stale quest left in the singleton by an earlier test got written into the next test's
## save file, whose .tres had already been deleted, and the reload hit a real engine error.
##
## So the pairing is decided by WHO THIS IS, exactly:
##   • the autoload  -> the QuestTracker autoload (the real run's single journal)
##   • anything else -> its OWN private tracker, added as a CHILD so it is freed with us and never orphans
func _qt() -> Node:
	if quest_tracker == null:
		if self == GameState:
			quest_tracker = QuestTracker
		else:
			var qt: Node = QuestTrackerScript.new()
			qt.name = "PrivateQuestTracker"
			qt.game_state = self
			add_child(qt)  # works off-tree; ties its lifetime to ours so `gs.free()` takes it too
			quest_tracker = qt
	return quest_tracker
const HOLSTER_FORGIVENESS_TUTORIAL_SEEN_FLAG := &"tutorial_holster_forgiveness_seen"
var _holster_forgiveness_tutorial_reminder_pending: bool = false
## Saved PERK LEDGER — the resource_paths of unlocked perks. Their stat bonuses ride in [stats] and their granted
## abilities in [player].unlocks; this records WHICH perks so has_perk / prereqs / "already learned" survive a reload.
var perk_paths: Array = []
## Saved PERK-GRANT LEDGER — perk id (String) -> the ability id (String) THAT perk introduced (only perks whose
## grant_ability actually added a NEW ability node are recorded). Persisted so a respec after a reload strips only
## what the perk truly granted — without this, restore_paths would re-claim an ability the player also owned from
## another source (an UpgradePickup, a starting unlock) and a later respec would wrongly revoke it.
var perk_grants: Dictionary = {}
## XP progression (rank 29): cumulative xp + cached level (persisted in [player]) + unspent skill (perk) points
## (persisted in [perks], the perk-owning section). Restored onto Player.xp/level + the PerkManager on load.
var xp: float = 0.0
var level: int = 0
var skill_points: int = 0
var points_earned: int = 0  ## cumulative XP-granted perk picks (respec refunds back up to this)

var has_respawn: bool = false
var respawn_position: Vector3 = Vector3.ZERO
var respawn_yaw: float = 0.0  ## body yaw (radians) the player faces on respawn
## Boot-only gate (M3): false when this was a LOADED game whose saved level identity (current_level_path) could NOT be
## honored — its .tres was deleted/renamed or is scene-less, so GameRoot booted the EXPORTED level instead. The saved
## respawn belongs to that now-unloaded level, so the Player must NOT teleport to it (GameRoot instead places at the
## booted level's spawn + re-seeds a valid respawn). True in every normal case: a fresh game, an honored saved level,
## OR a legacy/old save with no recorded level identity (a blank path — we don't second-guess it). Set once in
## GameRoot._ready(), read once by Player._ready(); a runtime death-respawn is unaffected (its respawn is the live level's).
var respawn_level_matches: bool = true

func _ready() -> void:
	load_from_disk()  # boot: pull the autosave into memory so the menu can offer Continue + the Player can apply it

## True if an autosave file exists on disk — the start menu gates its "Continue" button on this.
func has_save_file() -> bool:
	# Resolved so a sandboxed session asks about the SANDBOX's autosave (the one its writes land in), not the real one.
	return FileAccess.file_exists(resolve_save_path(SAVE_PATH))

## Load the autosave at `path` into the fields above. Returns false — leaving `loaded` UNCHANGED — when NO rung of
## the recovery ladder below yields a usable profile: at boot that's the fresh-game false it started with, and on a
## failed MANUAL load (SaveLoadScreen / F9 on a file that vanished/corrupted since it was listed) the in-memory profile is untouched,
## so the flag that answers for it must not flip either — flipping it silently rebooted later Continues /
## death reloads as fresh runs. On success sets loaded = true so the Player applies the build.
## Every value reads through the type-guarded _cfg_* helpers below: this runs AT BOOT (the autoload's _ready),
## and a hand-edited/corrupt file can hold ANY Variant under a key — int() on an Array errors, `as Array` on a
## non-Array yields NULL (which would crash the restore loop), and a junk type hard-fails a typed assignment
## (respawn_position: Vector3). Junk degrades to the field's default instead of a boot crash.
func load_from_disk(path := SAVE_PATH) -> bool:
	# SANDBOX: resolved FIRST, before the ladder derives its .tmp/.bak siblings and before it keys
	# _recovered_from_fallback — so a sandboxed load walks the SANDBOX's rung set and a sandboxed and a real
	# profile never share a rung (or a fallback flag). Identity when the sandbox is off / for a non-canonical path.
	path = resolve_save_path(path)
	# THE ATOMIC-WRITE RECOVERY LADDER (H1) — the primary, then ".tmp" (the interrupted NEWEST write, left behind when
	# a crash struck the tiny rename window in save_to_disk), then ".bak" (the previous good checkpoint). Two things
	# decide whether a rung counts, and BOTH are load-bearing:
	#   * a FRESH ConfigFile per rung. ConfigFile.load() does NOT clear what the instance already holds, so one shared
	#     instance let a successful fallback MERGE on top of whatever a half-parsed primary had already absorbed — the
	#     .bak's money sitting beside the dead primary's inventory, a franken-profile that loads without one warning.
	#   * the rung must LOOK like one of our saves (_cfg_is_profile). ConfigFile.load returns OK for a ZERO-LENGTH file
	#     — zero sections, err == OK — so gating on the Error alone accepted a 0-byte primary as a pristine profile
	#     (loaded/profile_active true, every field silently at its default) and never even consulted the .tmp/.bak that
	#     still held the run.
	# So what this now guarantees: we take the NEWEST rung that BOTH parses AND carries a recognisable section, we
	# never blend two rungs, and we return false only when none of the three qualifies. A rung that parses into
	# nothing (truncated to a line boundary, zero-length, foreign file) is SKIPPED rather than accepted or merged.
	# A fresh game has none of the three, so it's simply unloaded.
	var cfg := ConfigFile.new()
	var primary_ok := cfg.load(path) == OK and _cfg_is_profile(cfg)
	# Two reasons to try a sibling: the primary is unusable (missing / 0-byte / shredded / not one of ours), OR it
	# parses as a real profile but carries no [eof] marker — a TAIL-TRUNCATED write. The second case used to be
	# accepted silently, which cost the run its perks and quests (those sections are written last) while money and
	# stats survived, so it looked like a glitch rather than a corrupt save.
	if not primary_ok or not _cfg_is_complete(cfg):
		var tmp_cfg := ConfigFile.new()
		var bak_cfg := ConfigFile.new()
		var tmp_ok := tmp_cfg.load(path + ".tmp") == OK and _cfg_is_profile(tmp_cfg)
		var bak_ok := bak_cfg.load(path + ".bak") == OK and _cfg_is_profile(bak_cfg)
		# RUNG ORDER, newest-first within each tier: prefer a sibling we can PROVE is whole, and only then fall back
		# to "is one of ours at all" — which is every save written before the [eof] marker existed. The two tiers must
		# stay separate: demanding the marker outright would refuse a legacy .bak and turn a recoverable corruption
		# into no save at all, while dropping the tier would go on silently accepting tail-truncated writes.
		if tmp_ok and _cfg_is_complete(tmp_cfg):
			cfg = tmp_cfg
			_recovered_from_fallback[path] = true  # the next write TO THIS PATH must not rotate the rejected primary over this .bak
			push_warning("GameState: primary save '%s' unusable — recovered the interrupted latest write from .tmp." % path)
		elif bak_ok and _cfg_is_complete(bak_cfg):
			cfg = bak_cfg
			_recovered_from_fallback[path] = true
			push_warning("GameState: primary save '%s' unusable — recovered from .bak (the last write may be lost)." % path)
		elif primary_ok:
			# The primary IS one of ours and no sibling is verifiably whole. A pre-marker save looks exactly like this,
			# and so does every hand-built fixture in the save tests, so keep the primary and read it — precisely how
			# this ladder behaved before the marker. Preferring an unproven sibling here would trade a good file for a
			# guess; the marker only ever ARBITRATES, it never condemns on its own.
			pass
		elif tmp_ok:
			cfg = tmp_cfg
			_recovered_from_fallback[path] = true
			push_warning("GameState: primary save '%s' unusable — recovered the interrupted latest write from .tmp." % path)
		elif bak_ok:
			cfg = bak_cfg
			_recovered_from_fallback[path] = true
			push_warning("GameState: primary save '%s' unusable — recovered from .bak (the last write may be lost)." % path)
		else:
			# No usable file: every in-memory field is untouched on this path, so `loaded` stays what it was
			# (false at boot; the session profile's true after a failed manual load — see the doc above).
			return false
	save_version = _cfg_int(cfg, "meta", "version", 0)  # H1b: 0 = a pre-versioning save; recorded for a future migration
	money = _cfg_float(cfg, "player", "money", GameSettings.economy.player_starting_money)  # missing/junk -> the fresh-game knob; older saves stored ints, _cfg_float casts them
	account = _cfg_float(cfg, "player", "account", 0.0)          # the Ledger account (signed: + savings, - debt); absent in pre-ATM saves -> 0
	payment_method = _cfg_str(cfg, "player", "payment_method", "debit")  # the armed rail KEY; absent -> the safe default
	# The earned record; absent -> a clean slate. Clamped to EXACTLY add_credit_standing's rails (its
	# maxf(0.0, …) cap floor included): this load is the one writer outside that mutator, and the file is the
	# one place a value past the LIVE cap can come from (a hand-edit, or a save written before a designer
	# lowered credit_standing_max).
	var standing_cap: float = maxf(0.0, GameSettings.economy.credit_standing_max)
	credit_standing = clampf(_cfg_float(cfg, "player", "credit_standing", 0.0), -standing_cap, standing_cap)
	# LEGACY FOLD, gated at <v5: saves written BEFORE the ATM carried the implant bill as a NEGATIVE WALLET. On one of
	# those the wallet is cash-only, so a negative one can only be pre-ATM debt — move it onto the account, where the
	# ATM can actually repay it. This used to run UNGATED, justified as idempotent by construction (after one save
	# `money` is >= 0, so it can never fire twice). That argument silently assumed a wallet that can never go below
	# zero, and DialogueChoice.give_money is documented as accepting a NEGATIVE amount for a fee/cost — so a CURRENT
	# run CAN reach this line with a genuine cash shortfall, and ungated we would have converted it into
	# interest-bearing bank debt behind the player's back. Now it is a proper version-gated migration: a separate `if`
	# like the stat folds above, so an ancient save still runs every fold it needs in one load, and re-saving stamps
	# v5 so it never re-runs.
	if save_version < 5 and money < 0.0:
		account = snappedf(account + money, Zorkmids.QUANTUM)
		money = 0.0
	player_name = _cfg_str(cfg, "player", "name", "")  # missing / junk-typed -> unnamed via the type guard (name is always written as a String, so this is lossless); a raw String(<Variant>) cast could raise "Invalid constructor" and abort the load
	# Appearance (head/body customizer): rebuild the dict from whatever's present, type-guarded. A missing section
	# (older save / never customised) leaves it EMPTY -> consumers use the catalog default. Junk-typed values drop.
	appearance.clear()
	if cfg.has_section("appearance"):
		for sk in ["head", "body"]:
			var sv = cfg.get_value("appearance", sk, "")
			if sv is String and not (sv as String).is_empty():
				appearance[sk] = sv
		for ck in ["skin", "arm", "leg"]:
			# has_section_key first: get_value with a null default treats it as NO default and error-logs on a
			# missing key (an older save without the key spams the boot log otherwise).
			if not cfg.has_section_key("appearance", ck):
				continue
			var cv = cfg.get_value("appearance", ck)
			if cv is Color:
				appearance[ck] = cv
		# The player-drawn t-shirt (the "Shirt" creation tab): a tiny PNG kept as bytes. Type-guarded like the rest;
		# a missing / junk / empty value just leaves the character on its base shirt (CharacterAppearanceCatalog).
		if cfg.has_section_key("appearance", "shirt"):
			var shirt = cfg.get_value("appearance", "shirt")
			if shirt is PackedByteArray and not (shirt as PackedByteArray).is_empty():
				appearance["shirt"] = shirt
	xp = _cfg_float(cfg, "player", "xp", 0.0)
	level = _cfg_int(cfg, "player", "level", 0)
	unlocks.clear()
	var raw_unlocks = cfg.get_value("player", "unlocks", [])
	if raw_unlocks is Array:
		for u in raw_unlocks:
			unlocks.append(StringName(str(u)))  # str() first — StringName(<non-string Variant>) errors
	disabled_unlocks.clear()
	var raw_disabled = cfg.get_value("player", "disabled_unlocks", [])  # absent on an older save -> [] -> nothing disabled
	if raw_disabled is Array:
		for u in raw_disabled:
			disabled_unlocks.append(StringName(str(u)))
	stat_values.clear()
	for n in STAT_NAMES:
		stat_values[n] = _cfg_int(cfg, "stats", String(n), 0)
	# C43: pre-2026-07-09 saves stored a "persuasion" stat later renamed to "streetwise"; the loop above ignores keys
	# not in STAT_NAMES and so silently drops the points. Fold the legacy value into streetwise for any save older
	# than v2 so the build survives the rename. A current save has no persuasion key (has_section_key false -> no-op);
	# a fresh game already stamps save_version = SAVE_VERSION (reset_for_new_game), so it never runs. Re-saving
	# stamps the current SAVE_VERSION and this branch never re-runs. save_version was read above (from [meta].version).
	if save_version < 2 and cfg.has_section("stats") and cfg.has_section_key("stats", "persuasion"):
		stat_values[&"streetwise"] = int(stat_values.get(&"streetwise", 0)) + _cfg_int(cfg, "stats", "persuasion", 0)
	# v3 (2026-07-16): the "stealth" and "pickpocket" stats were consolidated into ONE "larceny" stat. A <v3 save
	# stored points under both legacy keys; the stat-load loop above only reads STAT_NAMES (which now carries larceny,
	# not stealth/pickpocket), so both would silently vanish. Fold BOTH legacy values into larceny. A separate `if`
	# from the persuasion branch above so a v1 save runs BOTH folds in one load. A current save has neither legacy key
	# (no-op), and re-saving stamps v3 so this never re-runs. larceny didn't exist pre-v3, so it starts at 0 here.
	if save_version < 3 and cfg.has_section("stats"):
		var legacy_larceny := _cfg_int(cfg, "stats", "stealth", 0) + _cfg_int(cfg, "stats", "pickpocket", 0)
		if legacy_larceny != 0:
			stat_values[&"larceny"] = int(stat_values.get(&"larceny", 0)) + legacy_larceny
	reputation.clear()
	if cfg.has_section("reputation"):
		for fid in cfg.get_section_keys("reputation"):
			reputation[fid] = _cfg_float(cfg, "reputation", fid, 0.0)  # junk -> 0; faction id is the key
	flags.clear()
	if cfg.has_section("flags"):
		for f in cfg.get_section_keys("flags"):
			flags[f] = cfg.get_value("flags", f, null)  # String key; the value round-trips as its stored Variant
	discovered_corpses.clear()
	var raw_corpses = cfg.get_value("world", "discovered_corpses", [])
	if raw_corpses is Array:
		for key in raw_corpses:
			var k := str(key)
			if not k.is_empty():
				discovered_corpses[k] = true
	# v3 -> v4 (Slice 3, stable identity) is a LAZY migration, deliberately NOT a load-time fold: a <v4 save's
	# entries are raw display-name strings, and they load UNCHANGED because (a) for every id-less NPC the identity
	# key IS StringName(display_name) — the v3 key and the v4 key coincide — and (b) name_is_revealed accepts a
	# match on EITHER the identity key or the name string, so a legacy name entry keeps resolving. An eager
	# name->id rewrite is impossible to do authoritatively here: NpcData .tres files are only referenced from
	# scenes (no registry enumerates them; a res:// DirAccess scan is export-fragile), and most placed NPCs carry
	# an INLINE display_name with no NpcData at all. It would also be a no-op at v4-introduction time (no authored
	# ids existed before v4). A legacy entry that stops matching anything (the NPC's display_name was edited, or
	# its reveal now writes an id) degrades to "not yet introduced" — the graceful direction (a Stranger again,
	# never a wrongly-revealed name). reveal_name writes identity keys (+ the display bridge) from here on.
	known_names.clear()
	var raw_known = cfg.get_value("world", "known_names", [])
	if raw_known is Array:
		for nm in raw_known:
			var s := str(nm)
			if not s.is_empty():
				known_names[s] = true
	# World-object ledger: one nested Dictionary under [world_objects].data. Corrupt-safe — keep only
	# level_path -> { key -> state } entries whose shapes are Dictionaries; anything junk-typed degrades to empty.
	world_objects.clear()
	var raw_wo = cfg.get_value("world_objects", "data", {})
	if raw_wo is Dictionary:
		for lvl in raw_wo:
			var per = raw_wo[lvl]
			if per is Dictionary:
				var clean := {}
				for ok in per:
					if per[ok] is Dictionary:
						clean[str(ok)] = per[ok]
				if not clean.is_empty():
					world_objects[str(lvl)] = clean
	# The player's map pins: one nested Dictionary under [waypoints].data, level_path -> Array of records.
	# EVERY record goes through WaypointBook.sanitize, which drops the un-repairable ones (no position),
	# re-clamps the two text fields and truncates a level past the per-level cap — so a hand-edited save can
	# neither smuggle a control character onto the map nor grow the ledger without bound. A level whose whole
	# list sanitizes to empty is dropped rather than stored as an empty array.
	#
	# NO SAVE_VERSION MIGRATION, deliberately: this section is purely additive, and its absence (every save
	# written before the feature) is already the correct "no pins yet" state — and so is the absence of the
	# optional "tracked" key inside a record.
	#
	# The one rule sanitize CANNOT enforce is folded in here: at most one pin across the WHOLE ledger may be
	# tracked, and sanitize only ever sees one level's list. FIRST WINS (Dictionary iteration is insertion
	# order, so a hand-edited file that tracked three pins loads with the topmost one tracked rather than with
	# a nondeterministic winner or none at all) — a save cannot be allowed to seed two navigation markers,
	# because every consumer asks tracked_waypoint() for THE one and would silently see only the first anyway.
	waypoints.clear()
	var raw_wp = cfg.get_value("waypoints", "data", {})
	if raw_wp is Dictionary:
		var tracked_seen := false
		for lvl in raw_wp:
			var clean_wp := WAYPOINT_BOOK.sanitize(raw_wp[lvl])
			if not clean_wp.is_empty():
				tracked_seen = _fold_tracked(clean_wp, tracked_seen)
				waypoints[str(lvl)] = clean_wp
	# Exact-snapshot tier: a MANUAL quicksave/slot file carries a [world_snapshot] section; the lean autosave does
	# not. Its ABSENCE is the back-compat path (a profile-only load leaves world_snapshot null + nothing pending —
	# byte-identical to today). A version we don't understand is ignored (profile still loads). On a real snapshot
	# load we also reload the live death ledger from it so deaths AFTER the load keep accumulating onto the right set.
	world_snapshot = null
	_world_snapshot_pending = false
	_dead_authored.clear()
	if cfg.has_section_key("world_snapshot", "data"):
		var ws_ver := _cfg_int(cfg, "world_snapshot", "version", 0)
		var ws_raw = cfg.get_value("world_snapshot", "data", {})
		# Ranged, not exact-match: the snapshot shape only grows ADDITIVELY (v2 added "containers") and from_dict
		# shape-filters what a version lacks, so an older quicksave keeps its NPC/world state on update instead of
		# being dropped. WorldSnapshot.SNAPSHOT_MIN_COMPAT rises only on a genuinely breaking reshape. A NEWER
		# version than this build understands (a downgraded install) still degrades to profile-only below.
		if ws_ver >= WorldSnapshot.SNAPSHOT_MIN_COMPAT and ws_ver <= WorldSnapshot.SNAPSHOT_VERSION and ws_raw is Dictionary:
			world_snapshot = WorldSnapshot.new()
			world_snapshot.from_dict(ws_raw)
			_world_snapshot_pending = true
			_dead_authored = world_snapshot.dead_map()
		else:
			push_warning("GameState: [world_snapshot] version %d unsupported — loaded the profile only." % ws_ver)
	time_of_day = _cfg_float(cfg, "clock", "time_of_day", 0.5)  # missing section -> the noon default
	var raw_fx = cfg.get_value("status", "effects", [])  # [{path, remaining}]; junk-typed -> none (back-compat / corrupt-safe)
	status_effects = raw_fx if raw_fx is Array else []
	var raw_level = cfg.get_value("level", "path", "")  # active LevelData path; junk-typed / missing -> "" (GameRoot uses its export)
	current_level_path = raw_level if raw_level is String else ""
	# A load REPLACES the waypoint ledger wholesale, so its paint stamp must move even when the new content
	# happens to match the old — the widgets compare the revision, not the contents. Emitted HERE, after the
	# level path above is folded from the SAME file, so a waypoints_changed listener that re-validates a
	# selection reads the new ledger against the new level — never the new ledger keyed by the old path.
	_waypoints_loaded()
	has_respawn = _cfg_bool(cfg, "respawn", "has", false)
	respawn_position = _cfg_vec3(cfg, "respawn", "position", Vector3.ZERO)
	respawn_yaw = _cfg_float(cfg, "respawn", "yaw", 0.0)
	# Back-compat: a save written before inventory persisted has no [inventory] section — has_inventory stays
	# false and the Player seeds its authored loadout, exactly as those saves behaved when written.
	has_inventory = cfg.has_section("inventory")
	var raw_stacks = cfg.get_value("inventory", "stacks", []) if has_inventory else []
	inventory_stacks = raw_stacks if raw_stacks is Array else []
	equipped_index = _cfg_int(cfg, "inventory", "equipped", -1) if has_inventory else -1
	_load_perks_and_quests(cfg)
	loaded = true
	profile_active = true  # a disk-loaded run is authoritative in memory (P0-2)
	_clock_apply_pending = true  # a genuine disk-load: the Player applies the saved clock ONCE (not on a respawn reload)
	return true

## The sections a parsed file must show at least ONE of before load_from_disk's ladder will accept it as a save.
## [meta] and [player] are the two every real save_to_disk carries unconditionally (the schema stamp and the wallet),
## so they are the sentinels that matter in the field; the rest are listed because a legitimately sparse file — a
## pre-versioning save, a hand-authored migration fixture — can carry only one of them, and skipping such a file
## would be a worse bug than the one this guards. Nothing here is a gameplay number, so a const is the right home.
const PROFILE_SECTIONS := ["meta", "player", "stats", "flags", "world", "respawn", "inventory", "perks"]

## Does this parsed ConfigFile look like one of OUR saves at all? An empty (0-byte) or shredded file loads with
## err == OK and NO sections, which is indistinguishable from a pristine profile once you start reading keys —
## so the ladder asks this before it trusts a rung. See load_from_disk.
static func _cfg_is_profile(cfg: ConfigFile) -> bool:
	for section in PROFILE_SECTIONS:
		if cfg.has_section(section):
			return true
	return false

## Did this save finish writing? save_to_disk stamps [eof] as its LAST section, so the marker's presence proves the
## file reached its end — the one signal that separates a truncated write from a legitimately small profile (most
## sections are conditional, so "missing [perks]" means nothing on its own). Presence is the whole test: the marker
## is a length check, not an authenticity check, and it is deliberately NOT in PROFILE_SECTIONS so a file carrying
## only [eof] still fails _cfg_is_profile. Saves written before this existed have no marker — the ladder keeps them.
static func _cfg_is_complete(cfg: ConfigFile) -> bool:
	return cfg.has_section("eof")

## --- Type-guarded ConfigFile reads (see load_from_disk): junk-typed values fall back to the default
## instead of erroring in a conversion or a typed assignment. Numeric kinds convert freely between each
## other (an int 1 read as bool/float is fine); anything else is junk. _cfg_str is the same guard for a
## String value — String(<Variant>) can raise "Invalid constructor" on some junk-typed values (which would
## abort load_from_disk before `loaded = true`), so it returns the value only when it IS a String. ---
static func _cfg_int(cfg: ConfigFile, section: String, key: String, fallback: int) -> int:
	var v = cfg.get_value(section, key, fallback)
	return int(v) if (v is int or v is float or v is bool) else fallback

static func _cfg_float(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	var v = cfg.get_value(section, key, fallback)
	return float(v) if (v is int or v is float or v is bool) else fallback

static func _cfg_bool(cfg: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var v = cfg.get_value(section, key, fallback)
	return bool(v) if (v is bool or v is int or v is float) else fallback

static func _cfg_str(cfg: ConfigFile, section: String, key: String, fallback: String) -> String:
	var v = cfg.get_value(section, key, fallback)
	return v if v is String else fallback

static func _cfg_vec3(cfg: ConfigFile, section: String, key: String, fallback: Vector3) -> Vector3:
	var v = cfg.get_value(section, key, fallback)
	return v if v is Vector3 else fallback

## Write the in-memory profile to `path`. Unlocks are stored as plain Strings (clean round-trip), re-typed to
## StringName on load. The respawn fields are written straight from memory (kept current by set_respawn).
## Returns ConfigFile.save()'s Error so callers can tell a real write failure (disk full / permission / bad
## path) from a success instead of assuming it worked — a failed write also push_warnings (-> ErrorSink), so an
## autosave that silently can't persist still surfaces. void-discarding callers (autosave) keep working unchanged.
func save_to_disk(path := SAVE_PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)  # H1b: stamp the schema version FIRST so a future load can migrate
	cfg.set_value("player", "money", money)
	cfg.set_value("player", "account", account)                  # the signed Ledger account (+ savings / - debt)
	cfg.set_value("player", "payment_method", payment_method)    # the armed rail KEY
	cfg.set_value("player", "credit_standing", credit_standing)  # the earned half of the credit score
	cfg.set_value("player", "name", player_name)
	# Appearance (head/body customizer): stamp only the keys that are set, so an uncustomised profile writes no
	# [appearance] section at all (load treats a missing section as "use the catalog default", identical behaviour).
	if not appearance.is_empty():
		for ak in ["head", "body", "skin", "arm", "leg"]:
			if appearance.has(ak):
				cfg.set_value("appearance", ak, appearance[ak])
		# The drawn shirt is stored as PNG BYTES. Guarded so a stray live-texture value (the creator holds an
		# ImageTexture in-memory; character_creation._on_begin converts it to bytes before emitting) never reaches
		# the config, which can't serialise a Texture.
		var shirt = appearance.get("shirt")
		if shirt is PackedByteArray and not (shirt as PackedByteArray).is_empty():
			cfg.set_value("appearance", "shirt", shirt)
	cfg.set_value("player", "xp", xp)
	cfg.set_value("player", "level", level)
	var raw_unlocks: Array = []
	for u in unlocks:
		raw_unlocks.append(String(u))
	cfg.set_value("player", "unlocks", raw_unlocks)
	var raw_disabled: Array = []
	for u in disabled_unlocks:
		raw_disabled.append(String(u))
	cfg.set_value("player", "disabled_unlocks", raw_disabled)  # the switched-off implants, same String round-trip as unlocks
	for n in STAT_NAMES:
		cfg.set_value("stats", String(n), int(stat_values.get(n, 0)))
	for fid in reputation:
		cfg.set_value("reputation", String(fid), float(reputation[fid]))
	for f in flags:
		cfg.set_value("flags", String(f), flags[f])
	if not discovered_corpses.is_empty():
		var corpse_keys := discovered_corpses.keys()
		corpse_keys.sort()
		cfg.set_value("world", "discovered_corpses", corpse_keys)
	if not known_names.is_empty():
		var name_keys := known_names.keys()
		name_keys.sort()
		cfg.set_value("world", "known_names", name_keys)
	if not world_objects.is_empty():
		cfg.set_value("world_objects", "data", world_objects)  # nested Dictionary round-trips through ConfigFile
	# The player's map pins, same nested-Dictionary round trip. Skipped entirely when nobody has placed one, so
	# a profile that never used the feature carries no [waypoints] section at all — the load path treats a
	# missing section and an empty one identically. Written RAW (the records were already clamped by
	# WaypointBook.make on the way in), and re-sanitized on the way back out because the file is editable.
	if not waypoints.is_empty():
		cfg.set_value("waypoints", "data", waypoints)
	# Exact-snapshot tier: write [world_snapshot] ONLY when a manual save populated one (autosave nulls world_snapshot
	# first, so it can never leak into gamestate.cfg). Its own version stamp is decoupled from [meta].version. Empty
	# snapshots are skipped so the section never bloats a save. This is what keeps the profile and the snapshot separate.
	if world_snapshot != null and not world_snapshot.is_empty():
		cfg.set_value("world_snapshot", "version", WorldSnapshot.SNAPSHOT_VERSION)
		cfg.set_value("world_snapshot", "data", world_snapshot.to_dict())
	cfg.set_value("respawn", "has", has_respawn)
	cfg.set_value("respawn", "position", respawn_position)
	cfg.set_value("respawn", "yaw", respawn_yaw)
	cfg.set_value("clock", "time_of_day", time_of_day)
	# Only stamp [status] when there's something to carry — an empty section over the back-compat "no effects" path
	# is harmless but pointless; the load path treats missing as none either way.
	if not status_effects.is_empty():
		cfg.set_value("status", "effects", status_effects)
	if current_level_path != "":
		cfg.set_value("level", "path", current_level_path)  # GameRoot reloads THIS level on a loaded game (not its export)
	# Written only when a bag was actually captured — so a profile that never captured one (nothing has called
	# capture with a real player yet) doesn't stamp an empty [inventory] section over the seed-on-load path.
	if has_inventory:
		cfg.set_value("inventory", "stacks", inventory_stacks)
		cfg.set_value("inventory", "equipped", equipped_index)
	_save_perks_and_quests(cfg)
	# ⭐THE TRUNCATION DETECTOR — KEEP THIS THE LAST set_value IN THIS FUNCTION. ConfigFile.save emits sections in
	# INSERTION order, so this one lands at the very end of the file. Any write cut short (crash, power loss, full
	# disk) therefore loses it by construction, whatever it managed to emit first — which is the only way to tell a
	# truncated save from a legitimately small one, since most sections here are written CONDITIONALLY and a missing
	# [perks] or [inventory] is perfectly normal. load_from_disk prefers a rung that carries this over one that does
	# not; a save written before this existed carries none and is still accepted (see the ladder).
	cfg.set_value("eof", "complete", true)
	return _write_atomic(cfg, path)


## Atomic write (H1): ConfigFile.save truncates-then-writes IN PLACE, so a crash / power-loss mid-write corrupts the
## ONLY autosave (this is a one-slot, Dark-Souls design) — total run loss. Write to a sibling ".tmp", then atomically
## rename it OVER the target (rename is atomic within a volume), after rotating the previous good file to ".bak" (which
## load_from_disk falls back to). A crash now costs at most the last write. On Windows a rename onto an EXISTING file
## fails, so the destination is always removed/rotated away first (guarded by file_exists so a missing sibling can't
## emit a stray engine error). The absolute DirAccess statics need no opened directory, so there's no dir-open edge.
## ONE exception to the rotation, per save file, and only for the first write to that file after a
## fallback-recovered load of it: see `_recovered_from_fallback` — rotating there would bury the checkpoint we
## just recovered from. The rotate+rename tail lives in _swap_into_place (shared with commit_sandbox).
## THIS IS THE ONE FUNNEL every save takes: save_to_disk (-> autosave / _capture_and_write -> quicksave /
## save_to_slot) all end here — which is why the sandbox redirect and the disk-write telemetry both live here.
func _write_atomic(cfg: ConfigFile, path: String) -> Error:
	# SANDBOX: resolved BEFORE the .tmp/.bak siblings are derived, so a sandboxed write's WHOLE rung set (primary +
	# temp + backup) lives in the sandbox folder and the real profile's primary AND recovery siblings stay untouched.
	path = resolve_save_path(path)
	var tmp_path := path + ".tmp"
	var err := cfg.save(tmp_path)
	if err != OK:
		push_warning("GameState: save to %s FAILED (Error %d) — the profile did NOT persist." % [tmp_path, err])
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)  # don't strand a partial temp
		_note_save_result(path, err)
		return err
	err = _swap_into_place(tmp_path, path)
	_note_save_result(path, err)
	return err

## The rotate-and-rename TAIL of the atomic write, in ONE place so _write_atomic and commit_sandbox's copy-back can
## never drift on the rules: rotate the file at `path` to ".bak" (or DISCARD it when the fallback guard says the
## ladder rejected it — see _recovered_from_fallback), then rename `tmp_path` onto `path`. On Windows a rename onto
## an EXISTING file fails, so the destination is always removed/rotated away first (guarded by file_exists so a
## missing sibling can't emit a stray engine error). `tmp_path` must already hold the COMPLETE new bytes.
func _swap_into_place(tmp_path: String, path: String) -> Error:
	var bak_path := path + ".bak"
	if FileAccess.file_exists(path):
		if _recovered_from_fallback.get(path, false):
			# THE ONE WRITE THAT MUST NOT ROTATE: the profile in memory came off .tmp/.bak because the ladder REFUSED
			# the file sitting at `path`. Rotating that refused file onto .bak would overwrite the last intact
			# checkpoint with the very corruption we recovered from — the run would survive exactly one autosave.
			# Discard it instead (the rename below still needs the destination gone on Windows) and leave .bak alone.
			DirAccess.remove_absolute(path)
		else:
			if FileAccess.file_exists(bak_path):
				DirAccess.remove_absolute(bak_path)     # clear the old .bak first (Windows rename fails onto an existing dest)
			DirAccess.rename_absolute(path, bak_path)   # rotate the prior good save to .bak (recoverable prior checkpoint)
	var err := DirAccess.rename_absolute(tmp_path, path)  # atomically swap the new save into place
	if err != OK:
		push_warning("GameState: atomic swap into %s FAILED (Error %d) — the profile did NOT persist." % [path, err])
	else:
		_recovered_from_fallback.erase(path)  # one good write later THIS path's primary is trustworthy again — rotate normally from here
	return err

## Disk-write telemetry, stamped at the tail of EVERY _write_atomic (success and failure alike) — see the
## save_count / last_save_* fields. `saved` fires here too. Never autosaves and never touches the profile: this is
## a passive counter, and a listener that reacts by saving again would recurse straight back into _write_atomic.
func _note_save_result(path: String, err: Error) -> void:
	last_save_msec = Time.get_ticks_msec()
	last_save_path = path
	last_save_err = err
	if err == OK:
		save_count += 1
	else:
		save_fail_count += 1
	saved.emit(path, err)

## Read the live run off `player` into the in-memory profile (money, stats, the unlocked mechanics). The
## respawn fields aren't touched here — set_respawn keeps them current (a bonfire rest / the initial spawn).
func capture(player: Node) -> void:
	if player == null:
		return
	money = float(player.money)
	var sheet: CharacterStats = player.stats_or_default()
	stat_values.clear()
	for n in STAT_NAMES:
		stat_values[n] = sheet.get_stat(n)
	unlocks.clear()
	for u in player.unlocked_list():
		unlocks.append(StringName(u))
	# The switched-off implants ride a SEPARATE key: unlocked_list() deliberately omits them (it is the
	# ACTIVE projection), so without this line one autosave would permanently uninstall a toggled-off implant.
	# has_method-guarded like every duck-typed capture read: a stand-in player without the ability subsystem
	# (the in-tree StubPlayer the slot tests capture off) reads as "nothing switched off", never a crash.
	disabled_unlocks.clear()
	if player.has_method(&"disabled_list"):
		for u in player.disabled_list():
			disabled_unlocks.append(StringName(u))
	# Faction standings are GLOBAL (the Reputation autoload), not on the player — snapshot them here so the
	# autosave carries them. Stored String-keyed for a clean cfg round-trip; Reputation.restore re-types on load.
	var standings := Reputation.all_standings()
	reputation.clear()
	for fid in standings:
		reputation[String(fid)] = float(standings[fid])
	# The day/night clock is global too (the WorldClock autoload) — snapshot it so a reload resumes the time of day.
	time_of_day = WorldClock.time_of_day
	# The backpack — when the player carries one (a bare unit-test player has no inventory; the fields are
	# then left as-is). Each stack serializes as {id, count} in stack order, PLUS its grid placement {x, y, w, h}
	# when the bag's spatial cap is on (the player's Tetris grid) so the layout survives a reload; equipped_index
	# records which SERIALIZED stack holds the drawn weapon. An item with no Item.id can't round-trip — skipped
	# with a warning (register it in resources/items/ to make it persist).
	# Per-instance weapon state rides as an additive `weapon_delta` dict when a weapon's scalar exported fields
	# differ from the registered template. Old saves without the key still restore from the template.
	var inv = player.inventory
	if inv != null:
		has_inventory = true
		inventory_stacks.clear()
		equipped_index = -1
		for s in inv.placed_contents():
			var it: Item = s["item"]
			if it == null or it.id == &"":
				if it != null:
					push_warning("GameState: item '%s' has no id — not saved" % it.label())
				continue
			if it.id == Zorkmids.ITEM_ID:
				# BELT AND BRACES. The player's cash is the `money` float, already persisted as [player] `money`
				# above, and no live path puts a zorkmids stack in their bag (loot converts to money on take,
				# MoneyPickUp credits the wallet, the debug `give` refuses the id). If one ever slipped in, saving
				# it here would restore as cash the wallet never counted — so it is skipped, not persisted.
				continue
			if it == inv.equipped_item:
				equipped_index = inventory_stacks.size()
			var entry := {"id": String(it.id), "count": int(s["count"])}
			var weapon_delta := ItemDb.weapon_delta_for(it)
			if not weapon_delta.is_empty():
				entry["weapon_delta"] = weapon_delta
			# Placement only when the stack is actually on a grid (x >= 0) — an unbounded bag writes plain
			# {id, count}, which loads back as an auto-place (the back-compat shape).
			if int(s["x"]) >= 0:
				entry["x"] = int(s["x"])
				entry["y"] = int(s["y"])
				entry["w"] = int(s["w"])
				entry["h"] = int(s["h"])
			inventory_stacks.append(entry)
		# A prop pulled from the backpack to be HELD in hand (Hotbar hold -> Player.hold_item) was REMOVED from `inv`
		# above, so the loop didn't capture it. Fold it back into the snapshot as {id, count:1} (auto-placed on load)
		# so a save taken while it's in your hands never loses it — a reload isn't carrying anything, so the item just
		# lands back in the bag. Skipped for an id-less item (can't round-trip) or a coin tile (see above).
		var held_it: Item = player.held_inventory_item() if player.has_method(&"held_inventory_item") else null
		if held_it != null and held_it.id != &"" and held_it.id != Zorkmids.ITEM_ID:
			var held_entry := {"id": String(held_it.id), "count": 1}
			# Carry the per-instance weapon delta exactly as the stack loop above does. A WEAPON can be in-hand now
			# (the H verb takes the wielded knife/gun into your hands), and without this a looted weapon whose stats
			# differ from its registered template would reload as the plain template.
			var held_delta := ItemDb.weapon_delta_for(held_it)
			if not held_delta.is_empty():
				held_entry["weapon_delta"] = held_delta
			inventory_stacks.append(held_entry)
	# Active status effects (CT-3): serialize the player's StatusEffectManager (by .tres path + remaining time) so a
	# buff/debuff survives a reload. has_method-guarded for a bare test player; null manager (none applied) -> empty.
	var smgr = player.status_manager() if player.has_method(&"status_manager") else null
	status_effects = smgr.serialize() if smgr != null else []
	var pm := _perk_manager_of(player)
	perk_paths = pm.unlocked_paths() if pm != null else []
	# The perk-grant ledger (perk id -> ability id it introduced) — String-keyed for a clean cfg round-trip. Persisted
	# so a respec AFTER a reload revokes ONLY what each perk truly granted (not an ability owned from another source).
	perk_grants = {}
	if pm != null:
		var grants: Dictionary = pm.granted_abilities()
		for pid in grants:
			perk_grants[String(pid)] = String(grants[pid])
	var xp_v = player.get(&"xp")
	xp = float(xp_v) if xp_v != null else 0.0
	var level_v = player.get(&"level")
	level = int(level_v) if level_v != null else 0
	skill_points = pm.skill_points if pm != null else 0
	points_earned = pm.points_earned if pm != null else 0

## Capture `player` and write the save — the autosave seam every milestone calls. Off-tree (a bare player in a
## unit test) it does NOTHING: writing would clobber the user's real save during a test run. Real gameplay always
## autosaves from an in-tree player.
func autosave(player: Node) -> void:
	if player == null or not player.is_inside_tree():
		return
	# A quickload / slot-load / RELOAD_LAST_SAVE death reload is mid-flight (load_from_disk done, scene reload requested
	# but not yet booted): the OLD player
	# is still in-tree, so a same-frame deferred flush must NOT capture it over the freshly-loaded profile. Bail — the
	# fresh scene will autosave normally once GameRoot boots (which clears this latch via set_current_level).
	if _reload_pending:
		return
	world_snapshot = null  # the lean autosave/Continue profile NEVER carries an exact snapshot — clear any that a
	_world_snapshot_pending = false  # (and its consume flag) so a stale pending can't ride into the reloaded scene
						   # prior manual quicksave left in memory so save_to_disk can't write one into gamestate.cfg.
	capture(player)
	save_to_disk()

## The live HUMAN player — the non-NPC member of the Player group (companions ARE NPCs; mirrors NPC._real_player) —
## so world-state milestones can autosave without the caller threading a player ref. Null off-tree / pre-spawn.
func live_player() -> Node:
	if not is_inside_tree() or get_tree() == null:
		return null
	for p in get_tree().get_nodes_in_group(Groups.PLAYER):
		if not (p is NPC):
			return p
	return null

## Flush the run after a WORLD-STATE change (a flag flip / a quest transition). These are milestones the player
## expects to survive a quit, but the in-memory flag/quest dicts were only persisted before when a money/xp event
## happened to coincide (the most-felt "Continue lost my progress" bug). ONE-FRAME-DEFERRED + coalesced, mirroring
## Player._queue_autosave: a burst of objective ticks / a flag fan-out (an AoE multi-kill advancing a KILL
## objective, or a set_flag that fans out to several advance_objective + an expire-fail) collapses to a SINGLE
## end-of-frame write instead of N synchronous full-profile serialize+saves. No-op off-tree (tests) / pre-spawn
## via the autosave() guard, which the deferred flush re-checks (a player freed before the flush -> no write).
var _world_save_queued: bool = false

func autosave_world_state() -> void:
	if _world_save_queued:
		return
	_world_save_queued = true
	call_deferred(&"_flush_world_state_save")

func _flush_world_state_save() -> void:
	_world_save_queued = false
	var player := live_player()
	if player != null:
		autosave(player)

## Consume the one-shot clock-apply flag (set by a disk-load / New Game). The Player calls this in _ready: true ->
## push GameState.time_of_day onto the live WorldClock; false (a death-respawn reload) -> leave the live clock be.
func consume_clock_apply() -> bool:
	var pending := _clock_apply_pending
	_clock_apply_pending = false
	return pending

## Exact-snapshot tier: consume-once the "a loaded save carried a [world_snapshot]" flag. GameRoot calls this after
## the level subtree is ready; true -> apply GameState.world_snapshot to the reloaded world (a manual quickload),
## false -> no-op (Continue / autosave load / death-respawn reload / fresh game). Twin of consume_clock_apply.
func consume_world_snapshot() -> bool:
	var pending := _world_snapshot_pending
	_world_snapshot_pending = false
	return pending

## Exact-snapshot tier: record that an authored NPC (keyed by its POSITION-FREE NPC.snapshot_key) has died, into the
## live per-level ledger a later manual quicksave folds into its WorldSnapshot. Called from NPC's died signal. No
## disk write here — deaths reach disk only when the player takes a manual quicksave/slot save. Empty key ignored.
func record_npc_death(level_path: String, key: String) -> void:
	if key.is_empty():
		return
	if not (_dead_authored.get(level_path) is Dictionary):
		_dead_authored[level_path] = {}
	_dead_authored[level_path][key] = true

## Exact-snapshot tier: free every authored NPC in `tree` whose snapshot_key is in this level's death ledger — so an NPC
## the player killed EARLIER (this session via record_npc_death, OR restored dead from a quicksave via dead_map) STAYS
## dead when the level re-instantiates: a door A->B->A return, or the boot after a load. Called by GameRoot.load_level on
## EVERY load (deferred, after NPC _ready has settled so snapshot_key resolves in-tree). A silent queue_free — NOT a death
## (no FX / loot re-roll; corpse reconstruction is a later phase). Deferred queue_free is safe while iterating the group
## snapshot. Dynamic (spawner) NPCs never enter _dead_authored, so only authored bodies are suppressed. Empty ledger / no
## tree -> no-op, so a fresh game or a lean Continue (no snapshot -> empty ledger) suppresses nothing.
func suppress_dead_authored(tree: SceneTree, level_path: String) -> void:
	if tree == null:
		return
	var dead: Variant = _dead_authored.get(level_path)
	if not (dead is Dictionary) or (dead as Dictionary).is_empty():
		return
	for n in tree.get_nodes_in_group(Groups.NPC):
		if not is_instance_valid(n) or n.is_queued_for_deletion() or not n.has_method(&"snapshot_key"):
			continue
		if (dead as Dictionary).has(str(n.snapshot_key())):
			n.queue_free()

## Record the LevelData GameRoot just loaded (its resource_path) so the next save knows which level to reload.
## Called by GameRoot.load_level on every level load (boot + door swaps). Blank for a code-built LevelData.
func set_current_level(path: String) -> void:
	# The fresh scene's GameRoot has booted — a quickload/slot-load reload (if any) is complete, so lift the autosave
	# freeze. Harmless on every non-reload level load (the latch is already false).
	_reload_pending = false
	var moved := current_level_path != path
	current_level_path = path
	# WHICH PINS ARE ON THE MAP just changed, even though no pin did: the waypoint ledger is keyed by level,
	# and every paint site reads waypoints_for(current_level_path). Bumping the revision here is what gives
	# the minimap's idle gate a trailing edge for a LevelDoor swap — without it the previous district's pins
	# can sit on the new level's map until something unrelated asks for a repaint. Guarded on a real change so
	# a re-entrant set (a death reload re-stamping the same path) costs nothing.
	if moved:
		_waypoints_loaded()  # bump + notify, but never autosave — a level swap is not a checkpoint

# --- Manual save / quicksave / named slots (ML-1) -----------------------------------------------------------
## These layer over the path-parameterized save_to_disk(path) / load_from_disk(path). They are SEPARATE files from
## the Dark-Souls autosave (SAVE_PATH): quitting still resumes the autosave. Unlike the lean autosave, a quick/slot
## save is the EXACT-snapshot tier — it writes the profile+ledger PLUS a [world_snapshot] section (built in
## _capture_and_write) so a load restores the WORLD as it was, not just your progression. The two products stay
## distinct on purpose (autosave = lean profile, quick/slot = exact snapshot; see docs "Save semantics must be
## explicit"). RESTORED by a scene reload (load_from_disk sets loaded=true, then reload_current_scene rebuilds a
## fresh Player that re-applies the build; GameRoot then applies the snapshot) — we never mutate the live player,
## the same contract as boot / Continue. A quick/slot save also stamps the respawn point at the player's CURRENT
## position so a load returns you exactly where you saved (not the last bonfire).
## UI STATUS: the QUICKSAVE is written in-game by F5 (player.gd; F9 quickloads) and is a LOAD-only row on the
## SaveLoadScreen. The named SLOTS are player-reachable through that same SaveLoadScreen
## (scripts/ui/save_load_screen.gd — the Options menu's "Save / Load" button in-game, the start menu's
## "Load Game" for menu-mode loading); the read-only CYBER SUNDAY "Saves" dock shows the same files.
const QUICKSAVE_PATH := "user://quicksave.cfg"
const SLOT_COUNT := 3  ## how many manual save slots exist (1..SLOT_COUNT). Surfaced as the SaveLoadScreen's slot rows (see above).

## Disk path for manual slot `slot` (1-based); the index is clamped so a bad caller can't escape user://.
func slot_path(slot: int) -> String:
	return "user://save_slot_%d.cfg" % clampi(slot, 1, SLOT_COUNT)

## Does a quicksave / the given manual slot exist on disk? (Read by the SaveLoadScreen to gate its Load buttons
## and paint empty rows, by the start menu to decide whether "Load Game" appears, plus the editor Saves dock + tests.)
## Both resolve through the sandbox first, so a sandboxed session gates its Load rows on the files ITS saves wrote.
func has_quicksave() -> bool:
	return FileAccess.file_exists(resolve_save_path(QUICKSAVE_PATH))

func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(resolve_save_path(slot_path(slot)))

## Capture `player` and write a quicksave. Returns true on a successful write. Off-tree (a bare unit-test
## player) it does NOTHING — like autosave, so a test run never clobbers the user's real save files.
func quicksave(player: Node) -> bool:
	return _capture_and_write(player, QUICKSAVE_PATH)

## Capture `player` into manual slot `slot` (1-based). Same off-tree guard / return contract as quicksave.
func save_to_slot(player: Node, slot: int) -> bool:
	return _capture_and_write(player, slot_path(slot))

## Shared body: guard off-tree, stamp the respawn point at the player's current spot (so a load returns you
## there), capture the live run, write to `path`. Returns the write's success — true ONLY when the file actually
## persisted, so a caller's "Saved!" feedback can't fire over a failed disk write (disk full / permission).
func _capture_and_write(player: Node, path: String) -> bool:
	if player == null or not player.is_inside_tree():
		return false
	set_respawn(player.global_position, player.rotation.y)  # a quick/slot save IS your new checkpoint
	capture(player)
	# Exact-snapshot tier: the manual path (and ONLY this path — autosave never calls here) builds a WorldSnapshot of the
	# live world (current level's live NPCs + its dead ledger), THEN folds in every OTHER level's death ledger so a
	# cross-level kill survives a quickload (you door back into a cleared level and it stays cleared). save_to_disk writes
	# it as [world_snapshot]; a load reloads the full ledger via dead_map() and load_level suppresses the dead per level.
	world_snapshot = WorldSnapshot.new()
	if is_inside_tree() and get_tree() != null:
		world_snapshot.capture(get_tree(), current_level_path, _dead_authored.get(current_level_path, {}))
	world_snapshot.fold_dead_ledger(_dead_authored, current_level_path)  # other levels aren't in the tree — dead keys only
	return save_to_disk(path) == OK

## Load the quicksave and re-apply it by reloading the scene (the fresh Player rebuilds the saved build from
## loaded=true — we never mutate the live player). Engine.time_scale is reset first so a quickload fired during
## the death slow-mo / BulletTime doesn't carry the dilation across the reload. Returns false (no reload) when
## there's no quicksave / it's unreadable, or we're off-tree.
func quickload() -> bool:
	return _load_and_reload(QUICKSAVE_PATH)

func load_from_slot(slot: int) -> bool:
	return _load_and_reload(slot_path(slot))

## Death-respawn twin of quickload (the Player's DeathMode.RELOAD_LAST_SAVE branch): load the rolling AUTOSAVE
## (SAVE_PATH — the same file every coalesced world-state autosave writes) and re-apply it via the scene reload.
## The routing is the point, not convenience: _load_and_reload arms _reload_pending, so an autosave flush queued
## in the SAME frame the death resolved (a door, a pickup, a kill bounty) can't capture the abandoned timeline
## over the checkpoint it just loaded. A bare load_from_disk() + reload_current_scene() at the call site is how
## exactly that save-destroying race once existed. Returns false (NO reload happened) when there's no autosave /
## it's unreadable — the caller owns the degrade (the Player falls back to a plain reload of the in-memory run).
func load_autosave() -> bool:
	return _load_and_reload(SAVE_PATH)

func _load_and_reload(path: String) -> bool:
	# The existence gate resolves through the sandbox exactly as load_from_disk (handed the same RAW path below)
	# will, so the two agree: a sandboxed quickload can't be refused for a file only the REAL folder lacks, or
	# accepted for one only the real folder has.
	if not FileAccess.file_exists(resolve_save_path(path)):
		return false
	if not load_from_disk(path):  # sets loaded = true on success so the reloaded Player applies the build
		return false
	if is_inside_tree() and get_tree() != null:
		InputManager.close_all_modals()  # release any autoload screen bound to a soon-freed scene node before the reload (T1)
		Engine.time_scale = 1.0
		# Latch so a same-frame deferred autosave flush (queued BEFORE this load) can't overwrite the just-loaded profile
		# on the still-in-tree old player. Cleared when the fresh scene's GameRoot boots (set_current_level).
		_reload_pending = true
		get_tree().reload_current_scene()
	return true

# --- Dev SANDBOX (debug console `sandbox on|off|status|commit`) + disk-write telemetry (`saves`) ---------------
## THE PROBLEM THIS SOLVES: autosaves fire constantly and behind your back — every wallet change, inventory change,
## flag flip, object-state record and interest posting queues a real write of user://gamestate.cfg. So a console
## `give` / `money` / `advance` overwrites the player's REAL profile the moment it runs, and there was no dev-save
## sandbox. While the sandbox is ACTIVE, every canonical save path — the autosave, the F5 quicksave and the three
## named slots — RESOLVES into `_sandbox_dir` (resolve_save_path), at the six seams that touch those files by
## path: has_save_file / has_quicksave / has_slot (existence gates), load_from_disk + _load_and_reload (reads),
## and _write_atomic (THE write funnel). Cheats can then run for hours and the real profile is byte-identical
## until the dev explicitly `sandbox commit`s. A crash / relaunch simply boots the REAL profile (the sandbox flag
## is session state, never persisted) and the sandboxed hours sit in user://sandbox/ for a later commit or grab.
##
## SCOPE: this redirects GameState's own file access ONLY. Surfaces that read the save files by RAW path (the
## SaveLoadScreen's per-row `slot_metadata(path)` — which decides BOTH the caption AND whether the row shows a
## Load button — and the editor Saves dock) still describe the REAL files while the sandbox is on: a sandboxed
## quicksave nobody's real file backs paints Empty with no Load button, and a real-only slot offers a Load that
## then fails against the box. A known limitation of this slice (the fix is `slot_metadata(resolve_save_path(path))`
## at SaveLoadScreen._add_row), listed so nobody trusts a caption over `sandbox status`.
const SANDBOX_DIR := "user://sandbox"
## The active sandbox folder, or "" = off. Session state, deliberately NEVER written into a save: a sandbox flag
## that persisted would make the next boot's REAL load resolve into the sandbox — the exact leak this exists to
## prevent. Only enable_sandbox / disable_sandbox write it.
var _sandbox_dir: String = ""

## Disk-write telemetry — the autosave-storm bug class ("a cheat loops money and hammers the disk") needs to be
## VISIBLE, and these are how the console's `saves` row and the F3 overlay see it. Stamped by _note_save_result at
## the tail of every _write_atomic. `save_count` = successful swaps this session; `last_save_path` is the RESOLVED
## path actually written (the sandbox path while sandboxed), so the readout can never claim a real write that went
## into the box. Session counters, never persisted.
var save_count: int = 0
var save_fail_count: int = 0
var last_save_msec: int = -1     ## Time.get_ticks_msec() of the last attempt; -1 = no write yet this session
var last_save_path: String = ""
var last_save_err: int = OK
## Fired at the tail of EVERY _write_atomic, success AND failure — `path` is the resolved path, `err` the Error.
## A passive observation seam (an event ticker, the debug overlay); a listener must NEVER save from it (recursion).
signal saved(path: String, err: int)

func sandbox_active() -> bool:
	return not _sandbox_dir.is_empty()

## The active sandbox folder ("" when off). `sandbox status` prints it, so a dev can grab an old sandbox before
## `sandbox on` forks a fresh one over it (see enable_sandbox).
func sandbox_dir() -> String:
	return _sandbox_dir

## The five REAL canonical save paths the sandbox redirects — the autosave, the quicksave, and slots 1..SLOT_COUNT.
## Derived from the same constants/formatter the writers use, so a new slot count or a renamed file can't drift
## out of the allowlist. Order is stable (status lines / tests key on it).
func sandbox_files() -> PackedStringArray:
	var out := PackedStringArray([SAVE_PATH, QUICKSAVE_PATH])
	for slot in range(1, SLOT_COUNT + 1):
		out.append(slot_path(slot))
	return out

## THE redirect. An ALLOWLIST rewrite, exact-path: ONLY the five canonical paths (sandbox_files) map to
## `_sandbox_dir/<basename>` while the sandbox is active; ANY other path — a test's user://test_*.cfg scratch file,
## a dump path, an already-resolved sandbox path, even a file that merely SHARES a canonical basename in another
## folder (user://elsewhere/gamestate.cfg) — passes through UNCHANGED, and everything is identity while off. Exact
## paths rather than basenames because the redirect must be idempotent (a resolved path resolves to itself) and must
## never hijack a caller's explicit path: the sandbox exists to protect the five real files, nothing else.
func resolve_save_path(path: String) -> String:
	if _sandbox_dir.is_empty() or not sandbox_files().has(path):
		return path
	return _sandbox_path_for(path)

## Where a canonical real path lives inside the active sandbox: the same basename under `_sandbox_dir`.
func _sandbox_path_for(real_path: String) -> String:
	return _sandbox_dir.path_join(real_path.get_file())

## Turn the sandbox on: create `dir`, FORK the real profile into it, and arm the redirect. Returns the first Error
## met, or OK. Contract, in order:
##   * IDEMPOTENT: already active on this very `dir` -> OK and NO FILE is touched (a second `sandbox on` must not
##     clobber the sandboxed run with the real profile again; `off` then `on` is how you deliberately re-fork). The
##     only thing it may do is re-create the folder itself if it was swept mid-session (see the body).
##   * REFUSES the real folder itself ("" / user://): the redirect would map each file onto ITSELF and commit would
##     then copy a file over itself — a truncate-then-read of the only checkpoint. ERR_INVALID_PARAMETER.
##   * ALWAYS OVERWRITES: a fresh session forks from the CURRENT real profile — each of the five real files that
##     exists is copied over the sandbox's copy, and a sandbox file whose real counterpart does NOT exist is
##     removed, so after `on` the sandbox is an exact mirror of the real five (no ghost quicksave from a previous
##     session, no `has_quicksave()` that the real profile can't back). A stale sandbox from an earlier session
##     is therefore replaced, not merged: `sandbox status` shows the folder precisely so a dev can grab (copy out
##     or `commit`) an old sandbox FIRST. Simplest mental model wins over silent preservation.
##   * SKIPS .tmp/.bak: only the five primaries are copied, never the real files' recovery siblings, and any stale
##     .tmp/.bak rungs already in the sandbox are cleared — otherwise load_from_disk's ladder could resurrect a
##     PREVIOUS sandbox session's rung under a freshly forked primary.
##   * ARMS ON MKDIR SUCCESS even if a copy failed: the invariant worth keeping is "while active, the real profile
##     is never written" — a partial fork plus a reported Error beats a live redirect the caller assumes is off.
##     The in-memory profile is untouched (it IS the current run; the next autosave lands in the sandbox).
## Works on a bare instance (no tree access) — the debug tests build one.
func enable_sandbox(dir: String = SANDBOX_DIR) -> Error:
	if dir.is_empty():
		return ERR_INVALID_PARAMETER
	# Normalised ("user://sandbox/" and "user://sandbox" are ONE folder) so the idempotency check below can't be
	# defeated by a trailing slash and re-fork the real profile over a live sandbox. simplify_path keeps the scheme.
	dir = dir.simplify_path()
	if _sandbox_dir == dir:
		# No re-fork — but do re-create the FOLDER if a dev swept user://sandbox/ mid-session (`sandbox status` invites
		# a grab, and a grab is one keystroke from a delete): every sandboxed write would otherwise fail on the
		# missing directory (save_fail_count climbing, ConfigFile.save can't create parents) while `sandbox on`
		# keeps answering "already ON". Creating an empty folder touches no file, so the idempotency holds.
		return DirAccess.make_dir_recursive_absolute(dir)
	# The self-copy guard: compare the two folders as absolute filesystem paths, so "user://", "user://." and
	# "user:///" all read as the real folder. Lower-cased because the only filesystem this can bite on (Windows) is
	# case-insensitive; on a case-sensitive one a folder that differs from user:// by case alone isn't a real case.
	var real_dir := ProjectSettings.globalize_path("user://").simplify_path().rstrip("/").to_lower()
	var box_dir := ProjectSettings.globalize_path(dir).simplify_path().rstrip("/").to_lower()
	if box_dir == real_dir or box_dir.is_empty():
		return ERR_INVALID_PARAMETER
	var err := DirAccess.make_dir_recursive_absolute(dir)  # OK when it already exists (ERR_ALREADY_EXISTS is folded)
	if err != OK:
		return err
	_sandbox_dir = dir
	var first_err := OK
	for real_path in sandbox_files():
		var boxed := _sandbox_path_for(real_path)
		# Clear the previous session's rungs first (see SKIPS .tmp/.bak above); the primary is decided just below.
		for stale in [boxed + ".tmp", boxed + ".bak"]:
			if FileAccess.file_exists(stale):
				DirAccess.remove_absolute(stale)
		if FileAccess.file_exists(real_path):
			# copy_absolute is an ENGINE error (not just a returned Error) on a missing source — the file_exists gate
			# above is what keeps a fork from a partial real profile quiet. WRITE truncates, so it overwrites in place.
			var copy_err := DirAccess.copy_absolute(real_path, boxed)
			if copy_err != OK and first_err == OK:
				first_err = copy_err
		elif FileAccess.file_exists(boxed):
			DirAccess.remove_absolute(boxed)  # mirror the real set exactly: no real file -> no sandbox file
		# Whatever sat at the sandbox path before was just replaced or removed, so a fallback flag describing it
		# (a previous sandbox load that recovered from .bak) is stale: the next sandbox write must rotate normally.
		_recovered_from_fallback.erase(boxed)
	return first_err

## Turn the redirect off: clears `_sandbox_dir` ONLY. The sandbox files stay on disk (for a later `commit` or a
## grab), and the in-memory profile is left as-is — the CONSOLE COMMAND does the real-profile reload + scene
## reload (load_from_disk mid-play mutates only memory and would desync the live world; see _load_and_reload).
func disable_sandbox() -> void:
	_sandbox_dir = ""

## Copy every sandbox file that exists back OVER its real counterpart. Each copy is crash-safe: the sandbox bytes
## are copied to `real + ".tmp"` first and then swapped into place through _swap_into_place — the SAME rotate
## rules as a normal write, so the pre-commit real file rotates to `.bak` (a one-step undo for a regretted commit)
## unless that real path is still flagged fallback-recovered, in which case the rejected primary is discarded and
## the real .bak left alone, exactly as _write_atomic would. A landed swap clears the real path's fallback flag
## (the real primary is trustworthy again — it IS the sandbox's good file now). No sandbox counterpart -> the
## real file is left untouched (a commit never deletes). Not a "save": save_count / `saved` don't move — this is
## a copy, and the sandbox STAYS ACTIVE afterwards (keep playing in the box; commit again later). Returns the
## first Error, ERR_UNCONFIGURED when the sandbox is off.
func commit_sandbox() -> Error:
	if not sandbox_active():
		return ERR_UNCONFIGURED
	var first_err := OK
	for real_path in sandbox_files():
		var err := _commit_file(_sandbox_path_for(real_path), real_path)
		if err != OK and first_err == OK:
			first_err = err
	return first_err

## One file of a commit: `boxed` -> `real_path` via the crash-safe temp + swap. Split out (and path-explicit) so
## the debug tests can drive the copy-back on SCRATCH paths — commit_sandbox itself targets the five REAL files,
## which no test may write. OK (and nothing touched) when `boxed` doesn't exist.
func _commit_file(boxed: String, real_path: String) -> Error:
	if not FileAccess.file_exists(boxed):
		return OK
	var tmp_path := real_path + ".tmp"
	var err := DirAccess.copy_absolute(boxed, tmp_path)
	if err != OK:
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)  # don't strand a partial temp beside the real save
		return err
	return _swap_into_place(tmp_path, real_path)

## Terse developer lines for `sandbox status` — returned as data, never painted here (debug modules only return
## Strings). Active?, the folder, then one line per canonical file with its REAL and SANDBOX presence/size/mtime
## side by side, so "which is newer / which is a ghost" is answerable before a `commit` or a re-fork.
func sandbox_status_lines() -> PackedStringArray:
	var out := PackedStringArray()
	if sandbox_active():
		out.append("sandbox ON — every canonical save resolves into %s (the real profile is untouched until `sandbox commit`)" % _sandbox_dir)
	else:
		out.append("sandbox OFF — saves go to the real user:// files (default folder %s%s)" % [SANDBOX_DIR, "" if DirAccess.dir_exists_absolute(SANDBOX_DIR) else ", not created yet"])
	var box := _sandbox_dir if sandbox_active() else SANDBOX_DIR
	for real_path in sandbox_files():
		var boxed := box.path_join(real_path.get_file())
		out.append("  %-16s real: %-28s sandbox: %s" % [real_path.get_file(), _describe_file(real_path), _describe_file(boxed)])
	return out

## "missing", or "<bytes> B @ <local datetime>" for a file that exists. Guarded by file_exists first: the mtime
## read on a missing path is at best a verbose log line and on older builds an engine error.
func _describe_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "missing"
	var size := -1
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		size = int(f.get_length())
		f.close()
	# get_modified_time is UTC unix; shift by the system zone bias (minutes, positive east of UTC) for a local stamp.
	var bias_min: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var local_unix: int = int(FileAccess.get_modified_time(path)) + bias_min * 60
	return "%d B @ %s" % [size, Time.get_datetime_string_from_unix_time(local_unix, true)]

## Build a CharacterStats sheet from the saved stat values — handed to the Player BEFORE its super._ready so
## _apply_stats stamps max_hp / carry from the saved build. An unset stat defaults to baseline 0.
func make_stats() -> CharacterStats:
	var s := CharacterStats.new()
	for n in STAT_NAMES:
		s.set(n, int(stat_values.get(n, 0)))
	return s

## The PerkManager child of `player` (named "Perks"), or null if none has been created yet.
func _perk_manager_of(player: Node) -> PerkManager:
	for c in player.get_children():
		if c is PerkManager:
			return c
	return null

## Write the perk ledger + quest tracker to `cfg`, keyed by resource_path (a code-built quest/perk with no path
## can't round-trip and is skipped — the quest-side skip warns, see QuestTracker.save_into). Active quests carry
## their objective progress; completed carry just the path.
func _save_perks_and_quests(cfg: ConfigFile) -> void:
	if not perk_paths.is_empty():
		cfg.set_value("perks", "paths", perk_paths)
	if not perk_grants.is_empty():
		cfg.set_value("perks", "grants", perk_grants)  # perk id -> granted ability id (String-keyed) for respec revocation
	cfg.set_value("perks", "points", skill_points)  # always written so unspent points round-trip even with no perks yet
	cfg.set_value("perks", "earned", points_earned)  # cumulative — needed so a respec after a reload refunds correctly
	_qt().save_into(cfg)  # the quest half — [quests_active] / [quests_completed] / [quests_failed]

## Restore the perk ledger + quest tracker from `cfg` (resource-path keyed). A renamed/removed .tres path is
## skipped with a warning rather than crashing the boot load — degrade, never hard-fail.
func _load_perks_and_quests(cfg: ConfigFile) -> void:
	perk_paths.clear()
	var raw_perks = cfg.get_value("perks", "paths", [])
	if raw_perks is Array:
		for pp in raw_perks:
			perk_paths.append(str(pp))
	perk_grants.clear()
	var raw_grants = cfg.get_value("perks", "grants", {})  # an older save (before the grant ledger) has none -> empty
	if raw_grants is Dictionary:
		for pid in raw_grants:
			perk_grants[String(pid)] = String(raw_grants[pid])
	skill_points = _cfg_int(cfg, "perks", "points", 0)
	points_earned = _cfg_int(cfg, "perks", "earned", 0)
	_qt().load_from(cfg)  # the quest half — also repopulates the B-F40 load warnings the HUD toasts

## B-F40: hand the HUD the last load's quest-restore warnings. Forwards to QuestTracker, which owns them; kept here
## because ui.gd has always asked GameState for them in _ready. Consume-once, so a HUD rebuild on a level change
## doesn't re-toast old warnings. Returns [] after a clean load.
func take_load_warnings() -> Array:
	return _qt().take_load_warnings()

## The holster-forgiveness tutorial is shown once as a normal tutorial, but a death to the same provoked NPC queues
## a one-shot reminder for the next live Player (in-place respawn OR reload-style death).
func holster_forgiveness_tutorial_seen() -> bool:
	return get_flag_bool(HOLSTER_FORGIVENESS_TUTORIAL_SEEN_FLAG, false)

func mark_holster_forgiveness_tutorial_seen() -> void:
	set_flag(HOLSTER_FORGIVENESS_TUTORIAL_SEEN_FLAG, true)

func queue_holster_forgiveness_tutorial_reminder() -> void:
	_holster_forgiveness_tutorial_reminder_pending = true

func consume_holster_forgiveness_tutorial_reminder() -> bool:
	var pending := _holster_forgiveness_tutorial_reminder_pending
	_holster_forgiveness_tutorial_reminder_pending = false
	return pending

## Start a brand-new run: drop the loaded profile back to fresh-game defaults and forget the respawn point. The
## disk file is left until the first autosave overwrites it (so a New-Game-then-quit doesn't lose a prior save
## before any progress is actually made). The Player then ignores the profile (loaded = false) and seeds itself.
func reset_for_new_game() -> void:
	loaded = false
	profile_active = false  # cleared here; character creation re-sets it once the run is real (P0-2)
	save_version = SAVE_VERSION   # H1b: a fresh run is current-schema
	respawn_level_matches = true  # M3: a fresh run has no stale saved level identity to mismatch
	money = GameSettings.economy.player_starting_money  # cash on hand; stays >= 0 for a created run (the implant bill rides `account`)
	account = 0.0                # a fresh run owes nothing and has nothing banked; the implant bill debits this AFTER the reset
	payment_method = "debit"     # every run starts spending its own money
	credit_standing = 0.0        # a fresh character has no record: New Game rates the BUILD alone
	player_name = ""             # a fresh run is unnamed until character creation stamps a name
	appearance.clear()           # ...and un-customised until character creation stamps a look (empty -> catalog default)
	stat_values.clear()
	unlocks.clear()
	disabled_unlocks.clear()     # a fresh run has no switched-off implants (nothing installed at all)
	has_inventory = false
	inventory_stacks.clear()
	equipped_index = -1
	reputation.clear()
	time_of_day = 0.5            # a fresh run opens at noon
	status_effects.clear()      # ...with no carried buffs/debuffs
	current_level_path = ""     # ...and GameRoot starts from its exported level, not a saved one
	_clock_apply_pending = true # ...and the Player pushes that noon onto the live WorldClock (which free-ran on the menu)
	flags.clear()  # a fresh run forgets all story flags
	discovered_corpses.clear()
	known_names.clear()  # ...and re-meets every NPC as a Stranger until they re-introduce themselves
	world_objects.clear()  # a fresh run forgets every door/pickup/prop world-state marker
	waypoints.clear()      # ...and every map pin the previous run placed
	_waypoints_loaded()    # (no autosave — a reset must not write over the file it is replacing)
	world_snapshot = null          # ...and any in-memory exact snapshot (matters on a RELOAD_CHECKPOINT_FRESH death,
	_world_snapshot_pending = false #    which keeps in-memory GameState — a fresh run must never apply a stale snapshot)
	_dead_authored.clear()
	_qt().reset()  # the journal + any prior boot-load's quest-restore warnings
	_holster_forgiveness_tutorial_reminder_pending = false
	perk_paths.clear()
	perk_grants.clear()
	xp = 0.0
	level = 0
	skill_points = 0
	points_earned = 0
	Reputation.reset()  # wipe live faction standings too — a fresh run starts neutral with everyone
	clear()  # forget the respawn point

## Set the point a death brings the player back to (a bonfire, or the player's initial spawn).
func set_respawn(position: Vector3, yaw: float) -> void:
	respawn_position = position
	respawn_yaw = yaw
	has_respawn = true

## Forget the respawn point (a fresh game).
func clear() -> void:
	has_respawn = false
	respawn_position = Vector3.ZERO
	respawn_yaw = 0.0

# --- Story flags (designer / quest world-state; see `flags`) -------------------------------------------------
## Set a story flag. `value` defaults to true (the common "mark that this happened" case). String-keyed so a
## StringName arg and a String ConfigFile key never miss each other (the Dictionary StringName-vs-String trap).
func set_flag(flag: StringName, value: Variant = true) -> void:
	flags[String(flag)] = value
	if value:
		# Flags are the universal quest hook: a set flag can ADVANCE a FLAG objective and (WR-6) CLOSE a quest's
		# window via expire_on_flag -> auto-fail. QuestTracker owns both halves and their ordering.
		_qt().notify_flag_set(flag)
	autosave_world_state()  # world state changed — persist so a quit doesn't lose it (Dark-Souls-style)

## A flag's value, or `fallback` (default false) when it was never set — so an unset bool flag reads as false.
func get_flag(flag: StringName, fallback: Variant = false) -> Variant:
	return flags.get(String(flag), fallback)

## Coerce an arbitrary Variant to bool WITHOUT crashing. bool() in Godot 4 has no String (or Array/Object/…)
## constructor — bool(<String>) throws "Invalid call. Nonexistent 'bool' constructor" — so any bool read of a
## value that persisted data could type-pollute (a flag, a world_objects ledger entry) must funnel through here
## instead of a bare bool(). Numeric kinds convert freely (int 1 / float 0.0 -> bool); anything else -> fallback.
func as_bool(value: Variant, fallback: bool = false) -> bool:
	return bool(value) if (value is bool or value is int or value is float) else fallback

## get_flag coerced to bool. A flag round-trips as its stored Variant (get_flag), so a hand-edited / legacy
## gamestate.cfg can hold a String under a flag key; `bool(get_flag(...))` would then crash. Bool consumers of a
## flag call this instead.
func get_flag_bool(flag: StringName, fallback: bool = false) -> bool:
	return as_bool(get_flag(flag, fallback), fallback)

## Has this flag been set at all (to any value)?
func has_flag(flag: StringName) -> bool:
	return flags.has(String(flag))

# --- Lightweight world markers -------------------------------------------------------------------------------
## Has a Corpse marker already drawn an NPC reaction? Empty keys are never persisted or matched.
func is_corpse_discovered(key: String) -> bool:
	return not key.is_empty() and discovered_corpses.has(key)

## Record a Corpse marker's one-shot discovery and queue the same coalesced world-state autosave used by flags.
func mark_corpse_discovered(key: String) -> void:
	if key.is_empty() or discovered_corpses.has(key):
		return
	discovered_corpses[key] = true
	autosave_world_state()

# --- "Stranger until introduced" name ledger (see known_names / stranger_names_enabled) ----------------------
## Learn a character — from now on public_name returns `real_name` outright instead of "Stranger", everywhere and
## across a save. Called by DialogueManager the moment a conversation OPENS with a real character speaker (talking
## to someone is the introduction), and again by any line with reveals_name = true; both pass the speaker's
## `identity` key (Slice 3: NPC.identity_key — NpcData.id, else the authored display name). Omitted/blank identity
## (a legacy caller / id-less NPC) keys by the name string — exactly the v3 behaviour. When the identity key
## DIFFERS from the display name (an id-authored NPC), the name string is ALSO recorded: the DISPLAY-COMPAT
## bridge, because every public_name surface queries by display string only — writing the id alone would leave an
## introduced id-authored NPC reading "Stranger" forever. No-op on a blank name (blanks aren't identities) or
## fully-known keys; persists via the same coalesced world-state autosave flags/corpses use.
func reveal_name(real_name: String, identity: StringName = &"") -> void:
	var nm := real_name.strip_edges()
	if nm.is_empty():
		return
	var ik := String(identity).strip_edges()
	if ik.is_empty():
		ik = nm
	var changed := false
	if not known_names.has(ik):
		known_names[ik] = true
		changed = true
	if ik != nm and not known_names.has(nm):
		known_names[nm] = true  # the display-compat bridge entry (see the doc above)
		changed = true
	if changed:
		autosave_world_state()

## Has the player been introduced to this character (or is masking off)? Matches the ledger on EITHER the `identity`
## key (when the caller supplies one) OR the `real_name` string — the latter keeps every v3 save's legacy name
## entry and every string-only display surface resolving (Slice 3's lazy migration; see the known_names load site).
## Blank names are never "unknown" — an NPC with no authored name has nothing to hide, so it never reads as a Stranger.
func name_is_revealed(real_name: String, identity: StringName = &"") -> bool:
	var nm := real_name.strip_edges()
	if nm.is_empty() or not stranger_names_enabled or known_names.has(nm):
		return true
	var ik := String(identity).strip_edges()
	return not ik.is_empty() and known_names.has(ik)

## THE display-name seam: the name to SHOW the player for a character whose true name is `real_name` — the real
## name once introduced (or masking off, or the name blank), else the "Stranger" placeholder. DISPLAY ONLY; every
## player-facing NPC-name surface routes through this, but quest/kill/talk matching keeps the stable identity key
## (public masking must never leak into identity — a "kill <name>" objective matches identity_key, never this).
## Slice 3 deliberately does NOT change this seam: display flows keep reading public_name(<display string>)
## exactly as before — no player-visible behaviour changes; reveal_name's display-compat bridge keeps these
## string-only queries resolving even for an id-authored NPC.
func public_name(real_name: String) -> String:
	if name_is_revealed(real_name):
		return real_name
	return PlayerText.STRANGER

# --- Per-object world-state ledger (doors / consumed pickups / destroyed props) ------------------------------
## Record `state` for the object `key` under `level_path`, and queue the coalesced world-state autosave. Keyed by
## level so the ledger remembers every visited level; empty keys are ignored (a fallback-keyed object with no path).
func record_object_state(level_path: String, key: String, state: Dictionary) -> void:
	if key.is_empty():
		return
	if not (world_objects.get(level_path) is Dictionary):
		world_objects[level_path] = {}
	world_objects[level_path][key] = state
	autosave_world_state()

## The saved state Dictionary for `key` under `level_path`, or {} if none (never null — callers read `.get(...)`).
func object_state(level_path: String, key: String) -> Dictionary:
	var per = world_objects.get(level_path)
	if per is Dictionary and per.get(key) is Dictionary:
		return per[key]
	return {}

## Whether any state was saved for `key` under `level_path` (so a container can tell "restore" from "seed").
func has_object_state(level_path: String, key: String) -> bool:
	var per = world_objects.get(level_path)
	return per is Dictionary and per.has(key)

# --- The player's own map pins (waypoints + notes) -----------------------------------------------------------
## Emitted after ANY change to the waypoint ledger — an add, an edit, a delete, a level's list being cleared,
## and the fold that pulls a save off disk. Consumers that hold a SELECTION (the Map tab's selected index)
## re-validate on this rather than trusting an index across a mutation.
##
## The PAINT surfaces deliberately do NOT connect here. They compare `waypoints_rev` once per frame instead,
## because a signal-driven queue_redraw would have to be wired from a widget that legitimately exists as a
## bare off-tree .new() in ~39 test sites, and a duplicate connect / a disconnect on a freed listener is an
## engine error that fails a whole GUT suite. A stamp needs no wiring and cannot leak a connection.
signal waypoints_changed

## Rules + record shape for everything below. Preloaded BY PATH and left untyped: the file carries NO
## class_name (see its own @risk), so nothing here depends on the editor's global class cache being current.
const WAYPOINT_BOOK := preload("res://scripts/world/waypoint_book.gd")

## Every pin placed on `level_path`, oldest first, or [] when that level has none. Returns the LIVE array —
## callers read it (the paint sites do, every frame) and must not mutate it; every mutation below goes
## through this file so the revision stamp and the signal can never be skipped.
func waypoints_for(level_path: String) -> Array:
	var per: Variant = waypoints.get(level_path)
	return per if per is Array else []

## One pin, or {} for an out-of-range index. Never null, so a caller reads `.get("name", "")` on the result
## without a second guard — the object_state() convention next door.
func waypoint_at(level_path: String, index: int) -> Dictionary:
	var list := waypoints_for(level_path)
	if index < 0 or index >= list.size():
		return {}
	var d: Variant = list[index]
	return d if d is Dictionary else {}

## Place a pin. Returns its index, or -1 when the level is already at WaypointBook.MAX_PER_LEVEL — a REFUSAL
## the caller must answer with a denial cue rather than a success one, because a silently-dropped pin looks
## exactly like a broken map. Every field goes through WaypointBook.make, so a caller cannot store an
## over-long label, a control character, or an icon ordinal outside the vocabulary.
func add_waypoint(level_path: String, pos: Vector3, label: String, note: String,
		icon: int = 0, tint: int = 0) -> int:
	if level_path.is_empty():
		return -1  # no level = nowhere to file it; a boot with no level loaded must not accumulate orphans
	if not (waypoints.get(level_path) is Array):
		waypoints[level_path] = []
	var list: Array = waypoints[level_path]
	if list.size() >= WAYPOINT_BOOK.MAX_PER_LEVEL:
		return -1
	list.append(WAYPOINT_BOOK.make(pos, label, note, icon, tint))
	_waypoints_touched()
	return list.size() - 1

## Re-author an existing pin's label / note / icon / tint. Its POSITION is deliberately immutable: a pin is a
## place you marked, and letting an edit move it would make "rename" and "re-place" the same gesture with
## different undo consequences. To move one, delete it and mark again. Returns false for a bad index.
##
## ⭐IT REBUILDS THE RECORD through WaypointBook.make (which is 5-field on purpose), so the tracked flag would
## be silently dropped by a rename — the player's navigation marker vanishing off the compass because they
## fixed a typo. Carried across explicitly here; there is nowhere else to do it, since make() must not learn
## about a flag whose invariant only the ledger can police.
func update_waypoint(level_path: String, index: int, label: String, note: String,
		icon: int, tint: int) -> bool:
	var list := waypoints_for(level_path)
	if index < 0 or index >= list.size() or not (list[index] is Dictionary):
		return false
	var old := list[index] as Dictionary
	var pos: Variant = old.get("pos")
	if not (pos is Vector3):
		return false
	var rec := WAYPOINT_BOOK.make(pos as Vector3, label, note, icon, tint)
	if WAYPOINT_BOOK.is_tracked(old):
		rec["tracked"] = true
	list[index] = rec
	_waypoints_touched()
	return true

## Remove one pin. Returns false for a bad index so a caller can tell "deleted" from "there was nothing
## there" — the Map tab plays a denial cue on the latter rather than reporting a delete that never happened.
##
## Deleting THE tracked pin needs no special case and deliberately has none: the flag lives on the record, so
## it leaves with it and tracked_waypoint() answers {} on the very next ask. Anything that caches the tracked
## coordinates instead of asking is the bug this shape exists to prevent.
func remove_waypoint(level_path: String, index: int) -> bool:
	var list := waypoints_for(level_path)
	if index < 0 or index >= list.size():
		return false
	list.remove_at(index)
	if list.is_empty():
		waypoints.erase(level_path)  # keep the ledger (and the save section) free of empty per-level arrays
	_waypoints_touched()
	return true

## Drop every pin on one level, or — with no path — the whole ledger. Returns how many were removed, so a
## "clear all" affordance can report a number and stay silent when there was nothing to clear.
func clear_waypoints(level_path: String = "") -> int:
	var n := 0
	if level_path.is_empty():
		for lvl: Variant in waypoints.keys():
			n += waypoints_for(String(lvl)).size()
		waypoints.clear()
	else:
		n = waypoints_for(level_path).size()
		waypoints.erase(level_path)
	if n > 0:
		_waypoints_touched()
	return n

## Is this level at its pin cap? The Map tab and the in-world Mark key both ask BEFORE opening their entry
## box, so a player is refused up front instead of typing a name into a pin that cannot be stored.
func waypoints_full(level_path: String) -> bool:
	return waypoints_for(level_path).size() >= WAYPOINT_BOOK.MAX_PER_LEVEL

# --- THE TRACKED PIN: one active navigation marker per profile ------------------------------------------
## Which pin the player is navigating to, as {"level": String, "index": int} — or {} when none is, which is
## the resting state. A COORDINATE PAIR rather than the record, for two reasons: every consumer needs the
## LEVEL as well (the heading tape draws a pip only for the current level's tracked pin, the HUD box only
## rim-pins one it can actually reach), and handing back the record would hand out the ledger's own live
## Dictionary to a caller with no reason to hold it.
##
## Walks the ledger rather than caching an index, because a cached index is precisely what goes stale when a
## pin below it is deleted — the class of bug the Map tab's selection already has to re-validate against.
## The walk is bounded by MAX_PER_LEVEL x visited levels and allocates nothing per record; consumers that
## paint gate on waypoints_rev anyway, so in practice it is asked on change rather than per frame.
func tracked_waypoint() -> Dictionary:
	for lvl: Variant in waypoints:
		var level_path := String(lvl)
		var list := waypoints_for(level_path)
		for i in list.size():
			if WAYPOINT_BOOK.is_tracked(list[i]):
				return {"level": level_path, "index": i}
	return {}

## Track (or untrack) one pin — the classic "set active waypoint". Returns false ONLY for a bad index, the
## same refusal shape update_waypoint / remove_waypoint use; asking for the state a pin is already in
## succeeds and simply does no work (no stamp, no autosave), so a UI may call it idempotently.
##
## ⭐IT CLEARS EVERY OTHER TRACKED FLAG IN EVERY LEVEL FIRST, on the untrack path too. Tracking is a MOVE, not
## a set: the value of one marker is that the compass pip and the rim-pinned HUD glyph are unambiguous, and a
## second flag left anywhere in the ledger would quietly win on some surfaces and lose on others (every
## consumer asks tracked_waypoint(), which answers with the FIRST). Sweeping on both paths costs one bounded
## walk when the invariant holds and repairs it when a hand-edited save broke it.
##
## Routes through _waypoints_touched() like every other mutation: the paint stamp must move or the minimap's
## idle gate will never draw the ring onto a standing player's box, and waypoints_changed fires
## SYNCHRONOUSLY — a handler re-entering here reads a ledger whose flag has already finished moving.
func set_tracked_waypoint(level_path: String, index: int, on: bool) -> bool:
	var list := waypoints_for(level_path)
	if index < 0 or index >= list.size() or not (list[index] is Dictionary):
		return false  # validated BEFORE the sweep: a refusal must not have cleared the flag it failed to move
	var rec := list[index] as Dictionary
	var changed := _clear_tracked_except(level_path, index)
	# `rec` is the ledger's OWN Dictionary (Godot 4 Dictionaries are references), so these write straight into
	# the stored record — no read-modify-write back into the array.
	if on:
		if not WAYPOINT_BOOK.is_tracked(rec):
			rec["tracked"] = true
			changed = true
	elif rec.has("tracked"):
		rec.erase("tracked")  # erases a junk-typed flag too, so an untrack always leaves a clean record
		changed = true
	if changed:
		_waypoints_touched()
	return true

## Strip the tracked flag from every pin in every level EXCEPT the one named. Returns whether it cleared
## anything, so the caller can skip the write barrier — and the coalesced autosave behind it — on a no-op.
func _clear_tracked_except(keep_level: String, keep_index: int) -> bool:
	var cleared := false
	for lvl: Variant in waypoints:
		var level_path := String(lvl)
		var list := waypoints_for(level_path)
		for i in list.size():
			if level_path == keep_level and i == keep_index:
				continue
			var d: Variant = list[i]
			if d is Dictionary and (d as Dictionary).has("tracked"):
				(d as Dictionary).erase("tracked")
				cleared = true
	return cleared

## The LOAD half of the same invariant, called per level as load_from_disk folds each sanitized list in.
## `already` is whether an earlier level in the file claimed the flag; the return feeds the next level. FIRST
## WINS — a hand-edited save that tracked three pins loads with the topmost one tracked rather than with a
## nondeterministic winner. Separate from _clear_tracked_except on purpose: this walks a list that is NOT in
## the ledger yet, so it must never read `waypoints`.
func _fold_tracked(list: Array[Dictionary], already: bool) -> bool:
	var seen := already
	for rec: Dictionary in list:
		if not WAYPOINT_BOOK.is_tracked(rec):
			continue
		if seen:
			rec.erase("tracked")  # a second navigation marker: the first one keeps it, this one loads plain
		else:
			seen = true
	return seen

# --- The ledger's two write barriers --------------------------------------------------------------------
## The one write barrier: bump the paint stamp, tell the listeners, and queue the same coalesced world-state
## autosave the object ledger uses — a pin the player placed must survive a crash the way an opened door does.
func _waypoints_touched() -> void:
	waypoints_rev += 1
	waypoints_changed.emit()
	autosave_world_state()

## The same barrier for a ledger that arrived from DISK (a load, or a New Game reset) rather than from the
## player. Identical except that it must NOT queue an autosave: writing a save as a direct consequence of
## reading one is how a half-applied load overwrites the file it came from, and the reset path is explicitly
## the one place that has to leave the disk alone until a real checkpoint.
func _waypoints_loaded() -> void:
	waypoints_rev += 1
	waypoints_changed.emit()

# --- Quests (FORWARDERS — the tracker itself is the `QuestTracker` autoload) -----------------------------------
# The quest state, the four quest signals, reward granting and the cfg round-trip all live on QuestTracker now
# (M1 split). These one-line forwarders stay because ~70 call sites — authored dialogue choices, TriggerVolumes,
# QuestStarters, Readables, the journal — reach for GameState.<quest fn>, and because quest progress is still part
# of THIS file's save. Prefer calling QuestTracker directly in new code. NOTE: the SIGNALS did NOT stay behind —
# connect to QuestTracker.quest_started / objective_advanced / quest_completed / quest_failed.

func start_quest(quest: Quest) -> void:
	_qt().start_quest(quest)

func advance_objective(quest_id: StringName, objective_id: StringName, amount: int = 1) -> void:
	_qt().advance_objective(quest_id, objective_id, amount)

func complete_quest(quest_id: StringName) -> void:
	_qt().complete_quest(quest_id)

func fail_quest(quest_id: StringName) -> void:
	_qt().fail_quest(quest_id)

func is_quest_active(quest_id: StringName) -> bool:
	return _qt().is_quest_active(quest_id)

func is_quest_completed(quest_id: StringName) -> bool:
	return _qt().is_quest_completed(quest_id)

func is_quest_failed(quest_id: StringName) -> bool:
	return _qt().is_quest_failed(quest_id)

func active_quest_ids() -> Array:
	return _qt().active_quest_ids()

func active_quest(quest_id: StringName) -> Quest:
	return _qt().active_quest(quest_id)

func completed_quests() -> Array:
	return _qt().completed_quests()

func failed_quests() -> Array:
	return _qt().failed_quests()

func objective_progress(quest_id: StringName, objective_id: StringName) -> int:
	return _qt().objective_progress(quest_id, objective_id)

func is_objective_done(quest_id: StringName, objective_id: StringName) -> bool:
	return _qt().is_objective_done(quest_id, objective_id)

func notify_kill(target_id: StringName, legacy_name: StringName = &"") -> void:
	_qt().notify_kill(target_id, legacy_name)

func notify_pickup(item_id: StringName) -> void:
	_qt().notify_pickup(item_id)

func notify_talk(npc_id: StringName, legacy_name: StringName = &"") -> void:
	_qt().notify_talk(npc_id, legacy_name)

func notify_enter(area_name: StringName) -> void:
	_qt().notify_enter(area_name)

func notify_use(item_id: StringName) -> void:
	_qt().notify_use(item_id)
