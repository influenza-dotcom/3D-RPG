@tool
## @system Economy
## NOTE: each @seam/@risk below must stay on ONE line — ArchScan only reads lines that start with a @tag, so a
## wrapped continuation line is DROPPED and the statement renders truncated in docs/SYSTEM_MAP.md.
## @seam The ONLY writer of a weapon's fitted-part set: _refit() folds the six slot ids onto a fresh copy of the PRISTINE template (WeaponModKit.rebuild), migrates every WeaponData-keyed runtime cache through Weapon.migrate_weapon_state, then re-equips through CharacterInventory.equip_item — no other code path may replace an Item's WeaponData.
## @seam Every guard in fit_mod/buy_and_fit/remove_mod runs PRE-CHARGE (fitment, slot offered, slot free, registered template, stat gate, draw lock, bag space, affordability), so a refusal costs the player nothing and _fitted/_removed are only ever reached past a cleared till.
## @risk Drop the TEMPLATE GATE (item_by_id(gun.id) resolving to a real weapon): WeaponModKit.rebuild is handed a null template, the fold produces nothing, and the bench has already taken the money — the highest-blast-radius path in the whole system.
## @risk Call _refit's rebuild from gun.weapon instead of tmpl.weapon: MULTs compound onto their own output, removing a part no longer returns the authored numbers, and the drift is invisible until someone compares a stripped gun against its .tres.
## @risk Gate migrate_weapon_state on "is it drawn" or move it after equip_item: Ammo re-banks a stranger and _on_weapon_changed hands out a FREE FULL MAGAZINE on every fit — a repeatable infinite-reload exploit (see Ammo.rekey_weapon).
## @risk Rename fit_mod/buy_and_fit/remove_mod/fit_fee/remove_fee/buy_and_fit_cost/refusal_reason: WeaponBenchScreen duck-calls all of them and the 'Modify' dialogue option rides the dialogue_station_option/open_dialogue_station pair — both surfaces fail SILENTLY, and both are pinned by tests/test_dialogue_speaker_contracts.gd.
## @test res://tests/test_weapon_bench.gd
class_name WeaponBench
extends LookAtInteractable


## Drop-in GUNSMITH BENCH component. Weapon parts (Item .tres carrying a WeaponMod payload — see
## resources/items/mod_*.tres) do nothing while they sit in your pack: you bring them HERE and pay zorkmids to
## have one FITTED into one of a weapon's six FO4 slots, or pay a smaller fee to have one pulled back out —
## and you KEEP the part when you do. Exactly the ChipInstaller shape, with three differences that matter:
##   * the transaction is REVERSIBLE (a chip is consumed into the machine; a part comes back out),
##   * it changes a weapon's STAT BLOCK rather than granting a permanent player mechanic, and
##   * it is therefore the one station that has to hand the runtime a NEW WeaponData object safely (see _refit).
##
## Two ways to use it, exactly like Merchant / Healer / ChipInstaller:
##   1. STANDALONE (a workshop bench, a lone gunsmith with no Talkable): leave `standalone` on (default) — it
##      sits on the talk layer, so aiming at it and pressing Interact opens the bench screen directly.
##   2. ON A DIALOGUE NPC: set `standalone` = false so the ray IGNORES it (the NPC's Talkable drives the
##      conversation); the dialogue then offers a "Modify" option that opens THIS bench's screen.
##
## ECONOMY (all derived from the part Item's `value`, no hardcoded price consts — the ChipInstaller mold):
##   - FIT a part the player already carries -> value × fit_mult × mod.fit_labour_mult, floored at min_fee.
##   - BUY & FIT a part this bench stocks    -> value × buy_mult (the part) PLUS the fit fee, so finding a part
##     yourself is always cheaper than buying it here (rewards exploration).
##   - REMOVE a fitted part                  -> value × remove_mult × mod.fit_labour_mult, floored at min_fee,
##     and the part goes back into the pack. Cheap on purpose: experimenting with loadouts must not be punished.
##
## ⭐THE FITTED SET IS THE SAVE. WeaponData carries six @export_storage StringName slot ids, which ride the
## EXISTING weapon_delta seam (no new save key anywhere) and are re-derived from the catalog on load by
## ItemDb.rebuild_weapon_mods. That is why this component writes IDS and never writes stat numbers by hand:
## a designer's retune of mod_long_barrel.tres reaches guns already sitting in old save files.
##
## SETUP: drop it under the bench prop / gunsmith NPC (or assign highlight_target), size its CollisionShape3D
## to the body you aim at (or set auto_fit_collider), fill `stock_counts` with the parts it sells, pick which
## slots it works on with `slots_offered`, and tune the fees.
## DUCK-TYPED SURFACE: WeaponBenchScreen duck-calls fit_mod / buy_and_fit / remove_mod / fit_fee /
## buy_and_fit_cost / remove_fee / can_afford / quoted_total / moddable_weapons / fittable_parts / stock_parts /
## fitted_parts / refusal_reason; DialogueManager discovers the "Modify" option via the dialogue-station
## contract at the bottom of this file (dialogue_station_option / open_dialogue_station).

## The fold + the fitment gate + the slot map. Const-preloaded (no class_name) exactly as ItemDb preloads it,
## so the bench never re-implements a line of stat maths — see scripts/items/weapon_mod_kit.gd.
const WeaponModKit = preload("res://scripts/items/weapon_mod_kit.gd")

@export_group("Stock")
## The PARTS this bench sells (buy & fit in one stop) — one StockEntry per line (a part Item + how many).
## Leave empty for a FIT-ONLY bench (the player must find every part in the world first), which is the shape
## most benches should have: the loot fantasy is the point.
## StockEntry's `required_reputation` rides along unchanged, but a bench has no `faction_id` to measure
## standing against, so — matching Merchant._entry_unlocked's own "no faction -> don't withhold stock" branch —
## a rep-gated line simply stocks. Author the gate on a Merchant if you want it to bite.
@export var stock_counts: Array[StockEntry] = []
@export_group("Display")
## Shown on the look-at hover + the bench screen title. Blank -> just "Gunsmith".
@export var bench_name: String = ""
@export_group("Fitting")
## Which of WeaponData's six slots THIS bench will work on. The default (63) is all six. One authored line
## makes a sights-only optician or a receivers-and-barrels armourer — no new component, screen, or test needed.
## Gates the Fitted section, the offered parts, and fit_mod itself, so a bench can never take money for a slot
## it does not work on.
@export_flags("Receiver", "Barrel", "Magazine", "Sight", "Muzzle", "Stock") var slots_offered: int = 63
@export_group("Pricing")
## Labour to FIT a part the player already carries = part.value × this × the part's fit_labour_mult, floored at
## min_fee. < 1.0 = cheaper than the part's face value (you paid for the part by finding it; this is the work).
@export var fit_mult: float = 0.4
## Labour to pull a fitted part back OUT, same derivation. Cheaper than fitting, AND you keep the part — the
## whole reason a player is willing to try a loadout they might not like.
@export var remove_mult: float = 0.2
## Sale markup for a part this bench STOCKS = part.value × this. The buy-&-fit total is this PLUS the fit fee,
## so buying here always costs more than fitting a part you found (the ChipInstaller lesson).
@export var buy_mult: float = 1.25
## Minimum labour fee (zorkmids) for any fit or removal, so a cheap part still costs something to work on.
@export var min_fee: int = 10
## Whether this till extends CREDIT. It is passed straight through as Player.can_pay / charge's `allow_credit`
## argument (see can_afford), so OFF funds a job from pocket cash and banked savings ONLY, never past zero onto
## the credit line — LevelUp.accepts_credit's exact semantics under Merchant's name. ⭐It is NOT Merchant's
## cash-only switch: Merchant hand-rolls a wallet-only comparison, this one defers to the player's rails.
##
## ⭐SAFE at `true`, and it is a CHECKED CLAIM rather than an assumption: Merchant.buy_price / sell_price key
## ENTIRELY on Item.value, which a refit never touches — a fully modded sniper resells for exactly what a stock
## one does. So unlike LevelUp this bench needs neither `accepts_credit = false` nor a settled-account gate;
## nothing it sells converts back into spending power. ⭐If anyone ever prices vendor trades off
## WeaponData.power_score(), that buy-on-credit / sell-back laundering loop RE-OPENS — which is why
## tests/test_weapon_bench.gd pins test_sell_price_is_invariant_across_a_refit.
@export var accepts_ledger: bool = true
@export_group("Behavior")
## STANDALONE (default): sit on the talk layer so Interact opens the bench directly. Off -> DATA-ONLY: the ray
## won't detect us, and a dialogue NPC drives access via its "Modify" option.
@export var standalone: bool = true

## The parts this bench sells — a child CharacterInventory, seeded from stock_counts in _ready (like Merchant).
var stock: CharacterInventory


## Editor warning: a standalone bench on a dialogue NPC steals the interaction ray from the NPC's Talkable.
func _get_configuration_warnings() -> PackedStringArray:
	if standalone and _on_dialogue_host():
		return PackedStringArray([
			"`standalone` is on but this WeaponBench is a child of a dialogue NPC — its talk-layer hitbox steals the interaction ray from the NPC's Talkable. Set `standalone` = false and open the bench from the dialogue's \"Modify\" option.",
		])
	return PackedStringArray()

func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_fit_hitbox()  # preview the auto-fit hitbox in-editor (resizes an existing collider; safe)
		return  # @tool: only _get_configuration_warnings runs in-editor; the stock build + hitbox setup is runtime-only
	# Standalone = a look-at hitbox on the talk layer (ray detects it); data-only benches sense nothing.
	collision_layer = TalkHelpers.TALK_LAYER if standalone else 0
	collision_mask = 0
	stock = CharacterInventory.new()
	stock.name = &"Stock"
	add_child(stock)
	_seed_stock(stock)
	_build_outline()  # look-at outline over the host's meshes (LookAtInteractable helper)
	if auto_fit_collider:
		_fit_hitbox_to_host()
	if standalone:
		StationSpeaker.ensure(self)  # a self-serve bench answers with the shared panel chirp; a data-only bench rides a talking NPC, and people don't beep
	# The minimap pin — ungated, like Merchant's. A gunsmith riding a walking NPC is still "there is somewhere
	# to modify a gun over there"; ensure() derives PINNING from `standalone` itself, so a fixed bench points at
	# itself from the box rim while a walking smith stays clipped to the box (the radar rule).
	StationMarker.ensure(self, StationMarker.Kind.TECH)

## Seed `into` from the authored part stock. Parts are MISC items, so they stack by shared template and a line
## stocks `count` of the SHARED Item — matching ChipInstaller's chip branch (and unlike Merchant's weapon
## branch, which needs one unique duplicate per count). A stray non-part line is IGNORED, exactly as a non-chip
## line is in an installer: the authored stock list is a designer surface, not a place to fail loudly.
## Split out from _ready so tests can exercise the seeding on a bare inventory.
func _seed_stock(into: CharacterInventory) -> void:
	if into == null:
		return
	for entry in stock_counts:
		if entry == null or entry.item == null or entry.count <= 0:
			continue
		if not entry.item.is_weapon_mod():
			continue  # only weapon parts belong in a bench's stock
		into.add(entry.item, entry.count)

# ---------------------------------------------------------------------------
# Pricing
# ---------------------------------------------------------------------------

## Shared fee derivation for both labour verbs. Whole zorkmids (ChipInstaller parity — its fees are ints),
## rounded UP so the smith's labour never rounds away (Merchant's directional-round idiom at whole-coin
## granularity), floored at min_fee. Returns 0 for a null / non-part / worthless item so a permanently-disabled
## "0 zm" row can never render — the same contract ChipInstaller.install_fee carries, and the reason
## fittable_parts/stock_parts also drop value<=0 items rather than offering a free row that refuses.
func _labour(part: Item, mult: float) -> int:
	if part == null or not part.is_weapon_mod() or part.value <= 0.0:
		return 0
	return maxi(min_fee, int(ceilf(part.value * mult * maxf(0.0, part.weapon_mod.fit_labour_mult))))

## Zorkmids to FIT a part the player already carries.
func fit_fee(part: Item) -> int:
	return _labour(part, fit_mult)

## Zorkmids to pull a fitted part back out. The part itself returns to the pack — this is labour only.
func remove_fee(part: Item) -> int:
	return _labour(part, remove_mult)

## Zorkmids to BUY a stocked part AND fit it in one step — the marked-up part PLUS the fit fee, so it is always
## dearer than fitting a part you found yourself.
func buy_and_fit_cost(part: Item) -> int:
	if part == null or not part.is_weapon_mod() or part.value <= 0.0:
		return 0
	return int(ceilf(part.value * buy_mult)) + fit_fee(part)

## ⭐THIS BENCH'S ONE AFFORDABILITY PREDICATE — fit_mod / buy_and_fit / remove_mod gate on it and the screen
## dims on it, in the SAME order, so a row can never look dead while the till would serve it (or the reverse).
## Fed the RAW BASE: Player.can_pay folds the ledger service charge in itself, so feeding it quoted_total's
## output would fee the fee and falsely refuse. A free service always clears (the Character.charge convention).
## `accepts_ledger` rides through as can_pay's `allow_credit` — cash and savings are reachable either way; what
## the flag gates is whether the till will lend (see the export's note).
func can_afford(price: float, player: Player) -> bool:
	if player == null:
		return false
	if price <= 0.0:
		return true
	return player.can_pay(price, accepts_ledger)

## The matching till. FAIL-CLOSED like Character.charge: moves nothing and returns false when the funds don't
## cover the whole price. accepts_ledger off keeps the charge out of GameState.account entirely.
func take_payment(price: float, player: Player) -> bool:
	if not can_afford(price, player):
		return false
	return true if price <= 0.0 else player.charge(price, accepts_ledger)

## THE ALL-IN number a row paints — what actually leaves the player, service charge included. The dim gates on
## the RAW base (can_afford) while the label shows THIS, which is the split the whole payment seam exists for.
func quoted_total(price: float, player: Player) -> float:
	if player == null or price <= 0.0:
		return maxf(0.0, snappedf(price, Zorkmids.QUANTUM))
	return player.charge_total(price, accepts_ledger)

# ---------------------------------------------------------------------------
# What the screen can show right now (the cycler + the two sections)
# ---------------------------------------------------------------------------

## Is `slot` (a WeaponData.ModSlot ordinal) one this bench works on? The bitmask gate, in one place: the Fitted
## section, the offered parts and fit_mod all read it, so a sights-only bench cannot be talked into a barrel.
func _slot_offered(slot: int) -> bool:
	if slot < 0 or slot >= WeaponData.MOD_SLOT_PROPS.size():
		return false
	return (slots_offered & (1 << slot)) != 0

## Weapon Items in the player's pack this bench could actually work on — what the screen's gun CYCLER walks.
## NOT deduped: two pistols are two guns with two independent fitted sets, and collapsing them would hide one.
## Requires a REGISTERED template (ItemDb.item_by_id), because a weapon whose .tres has left resources/items/
## has no pristine base to fold from — offering it in the cycler would paint a gun every row refuses, with no
## refusal_reason key honest enough to explain why. fit_mod re-checks it anyway (a duck-call may skip this).
func moddable_weapons(player_node: Node) -> Array:
	var player := player_node as Player
	if player == null or player.inventory == null:
		return []
	var out: Array = []
	for e in player.inventory.contents():
		var it: Item = e.get("item")
		if it == null or not it.is_weapon() or it.weapon == null:
			continue
		var tmpl := ItemDb.item_by_id(it.id)
		if tmpl == null or not tmpl.is_weapon() or tmpl.weapon == null:
			continue
		out.append(it)
	return out

## Parts in the PLAYER's pack that fit `gun` and sit in a slot this bench works on — the "fit what you carry"
## section. Deduped by Item.id (carrying two identical barrels still shows one row; fitting consumes one).
## A part whose slot is already OCCUPIED is deliberately still listed: it dims and the Notice band says
## "remove the fitted part first", which is a far better answer than a row that silently is not there.
func fittable_parts(gun: Item, player_node: Node) -> Array:
	var player := player_node as Player
	if player == null or player.inventory == null:
		return []
	return _offered_parts(player.inventory.contents(), gun, {})

## Parts this bench STOCKS that fit `gun` — the "buy & fit" section. A part the player already carries is
## excluded: fitting the one in your pack is strictly cheaper, so offering the shelf copy beside it would only
## invite an overpayment (the ChipInstaller precedent, where the carried section always wins).
func stock_parts(gun: Item, player_node: Node) -> Array:
	var player := player_node as Player
	if player == null or stock == null:
		return []
	var carried := {}
	for it in fittable_parts(gun, player):
		carried[(it as Item).id] = true
	return _offered_parts(stock.contents(), gun, carried)

## Shared filter behind both part sections: from `entries` ({"item","count"} dicts) keep each weapon part that
## fits `gun`, sits in an offered slot, has a real price, and is not in `exclude` (a set of Item.ids) — deduped
## by id. Returns Array[Item]. Fitment itself lives on the PART (WeaponModKit.fits), never in a table here.
func _offered_parts(entries: Array, gun: Item, exclude: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	if gun == null or not gun.is_weapon() or gun.weapon == null:
		return out
	for e in entries:
		var item: Item = e.get("item")
		# value<=0 prices a 0 fee (see _labour) -> a permanently-disabled "0 zm" row; drop it here so
		# _labour's contract ("the bench screen won't offer those") holds for BOTH sections.
		if item == null or not item.is_weapon_mod() or item.value <= 0.0:
			continue
		if seen.has(item.id) or exclude.has(item.id):
			continue
		if not WeaponModKit.fits(item.weapon_mod, gun):
			continue
		if not _slot_offered(item.weapon_mod.slot):
			continue
		seen[item.id] = true
		out.append(item)
	return out

## What is on `gun` right now, as ONE ROW PER OFFERED SLOT — empty slots included, in enum order. Fixed arity
## is the point: the Fitted section then never collapses and never re-flows as parts come and go, so the card
## does not hop under the player's cursor mid-transaction (the shipped list-screen bug this shape avoids).
## Each entry: {"slot": int, "id": StringName (&"" when empty), "part": Item or null (the registered template)}.
## A fitted id that no longer resolves comes back with a null `part` — the screen renders the slot as empty and
## the next rebuild re-stamps it blank, which is the same self-healing WeaponModKit.rebuild does on load.
func fitted_parts(gun: Item) -> Array:
	var out: Array = []
	if gun == null or not gun.is_weapon() or gun.weapon == null:
		return out
	for slot in WeaponData.MOD_SLOT_PROPS.size():
		if not _slot_offered(slot):
			continue
		var id := gun.weapon.mod_id(slot)
		out.append({
			"slot": slot,
			"id": id,
			"part": ItemDb.item_by_id(id) if id != &"" else null,
		})
	return out

## WHY a row would refuse, as a KEY — never a display label (PlayerText.bench_notice selects the sentence).
## ⭐Keys, not labels: a display string is never a behaviour key, so the Notice band can be re-worded or
## translated without touching a single branch here.
##
## Two callers, two shapes, ONE function:
##   * `part == null` — the GUN-LEVEL question the always-present Notice band asks every rebuild. Only the
##     reasons that apply to the whole card can come back (&"no_weapons", &"draw_locked", else &"").
##   * `part != null` — one row's question, and `removing` says WHICH SECTION asked. ⭐The direction is PASSED,
##     never inferred from `mod_id(slot) == part.id`. That inference looks total and is not: a part STACKS, so a
##     second copy — a spare in the pack, or the bench's own shelf copy — has the same Item.id as the fitted one
##     and took the REMOVE branch, which answers "no reason to refuse". The screen then painted it as a live,
##     priced FIT row that _transact_fit rejects on the occupied-slot guard every single time, with a blank
##     Notice band and no way for the player to learn why. The caller always knows the direction; ask it.
##
## The FIT branch prices `fit_fee`. A BUY & FIT row is dearer, so the screen re-prices its own dim on
## can_afford(buy_and_fit_cost(...)) — the ONE place this function's answer is not the whole story, and it is
## the same predicate, on the same raw base, in the same order.
##
## Order here is a DISPLAY ranking (loudest cause first) rather than fit_mod's charge-safety order; both reach
## the same verdict, and only fit_mod's order decides what the player is charged.
func refusal_reason(gun: Item, part: Item, player_node: Node, removing: bool = false) -> StringName:
	var player := player_node as Player
	if player == null or player.inventory == null:
		return &""
	if gun == null or not gun.is_weapon() or gun.weapon == null:
		return &"no_weapons"
	# Blocks EVERY row at once, so it outranks anything a single part could say.
	if _is_drawn(gun, player) and _draw_locked(player):
		return &"draw_locked"
	if part == null or not part.is_weapon_mod():
		return &""
	var mod: WeaponMod = part.weapon_mod
	# The id check is still here, but only as a SANITY guard on the caller's claim: a REMOVE row can only ever
	# be asked about the part actually sitting in that slot. A `removing` claim that does not match is a
	# duck-caller bug, and the honest answer is the FIT branch's.
	if removing and gun.weapon.mod_id(mod.slot) == part.id:
		# REMOVE. The offered check first, for the same reason the FIT branch has one: fitted_parts never paints
		# a row for an unworked slot, but a duck-caller can still ask, and the honest answer is "not our trade".
		if not _slot_offered(mod.slot):
			return &"unfit"
		# Then bag space — it is the guard remove_mod checks BEFORE the charge, so the dim and the refusal name
		# the same cause (a full pack must never eat the fee AND the part).
		if not player.inventory.can_accept(part):
			return &"bag_full"
		if not can_afford(float(remove_fee(part)), player):
			return &"afford"
		return &""
	# FIT.
	if not WeaponModKit.fits(mod, gun) or not _slot_offered(mod.slot):
		return &"unfit"
	if gun.weapon.mod_id(mod.slot) != &"":
		return &"slot_taken"
	if mod.min_gunplay > 0 and player.stats_or_default().get_stat(&"gunplay") < mod.min_gunplay:
		return &"stat_gate"
	if not can_afford(float(fit_fee(part)), player):
		return &"afford"
	return &""

# ---------------------------------------------------------------------------
# Transactions — ⭐every guard PRE-CHARGE
# ---------------------------------------------------------------------------

## FIT a part the player is CARRYING: charge fit_fee, take the part out of the pack, fold it into the gun.
## True on success. Every refusal below happens before a single zorkmid moves.
func fit_mod(gun: Item, part: Item, player_node: Node) -> bool:
	var player := player_node as Player
	if player == null or player.inventory == null:
		return false
	if not player.inventory.has(part):
		return false
	return _transact_fit(gun, part, player, player.inventory, fit_fee(part))

## BUY a stocked part AND fit it in one step: charge buy_and_fit_cost, take it off the shelf, fold it in. The
## part NEVER enters the player's pack, so no bag-space guard is needed on this path (unlike remove_mod).
func buy_and_fit(gun: Item, part: Item, player_node: Node) -> bool:
	var player := player_node as Player
	if player == null or player.inventory == null or stock == null:
		return false
	if not stock.has(part):
		return false
	return _transact_fit(gun, part, player, stock, buy_and_fit_cost(part))

## The shared FIT body — everything both paths do once the part has been located in `source`. Split so the two
## public verbs differ in exactly two things (where the part comes from and what it costs) and cannot drift
## into two different guard orders, which is how one of them would eventually ship a charge-before-refuse bug.
func _transact_fit(gun: Item, part: Item, player: Player, source: CharacterInventory, cost: int) -> bool:
	if gun == null or not gun.is_weapon() or gun.weapon == null:
		return false
	if part == null or not part.is_weapon_mod():
		return false
	var mod: WeaponMod = part.weapon_mod
	if not WeaponModKit.fits(mod, gun):
		return false
	if not _slot_offered(mod.slot):
		return false
	if gun.weapon.mod_id(mod.slot) != &"":
		return false  # one part per slot: pull the occupant first, which keeps the refund story unambiguous
	# ⭐THE TEMPLATE GATE. A weapon whose .tres has left resources/items/ has no PRISTINE base to fold from, and
	# _refit would hand WeaponModKit.rebuild a null template. This is ChipInstaller's can_grant_mechanic guard
	# transplanted onto the highest-blast-radius path in the design: refuse with NO charge rather than take
	# money and produce nothing.
	if not _has_template(gun):
		push_warning("WeaponBench: weapon '%s' has no registered ItemDb template — fit refused, no charge." % gun.id)
		return false
	if mod.min_gunplay > 0 and player.stats_or_default().get_stat(&"gunplay") < mod.min_gunplay:
		return false
	# ⭐THE DRAW-LOCK GATE. Attack.set_holstered(false) is REFUSED while draw_locked, and the swap chain _refit
	# kicks off calls exactly that — so without this the model swaps behind a locked holster: the new gun is
	# visible in hand, unable to fire, and GunMesh's reload/land/finished-reloading handlers all bail while
	# holstered, stranding the pose too. Refuse until the player's hands are free.
	if _is_drawn(gun, player) and _draw_locked(player):
		return false
	# The RAW base into can_afford — can_pay folds the ledger service charge in itself (see can_afford).
	if cost <= 0 or not can_afford(float(cost), player):
		return false
	if not take_payment(float(cost), player):
		return false
	source.remove(part, 1)  # the part goes into the gun; `changed` fires and the screen rebuilds
	_refit(gun, mod.slot, part.id, player)
	_fitted(part, gun, player)
	return true

## REMOVE the part fitted in `slot` and give it back: charge remove_fee, return the SHARED template part to the
## pack, fold the gun back down. True on success. This is the ONE path that moves goods TO the player, so it is
## the one that needs a bag-space guard — and that guard runs before the charge.
func remove_mod(gun: Item, slot: int, player_node: Node) -> bool:
	var player := player_node as Player
	if player == null or player.inventory == null:
		return false
	if gun == null or not gun.is_weapon() or gun.weapon == null:
		return false
	if not _slot_offered(slot):
		return false
	var id := gun.weapon.mod_id(slot)
	if id == &"":
		return false  # nothing fitted there
	# A part is a stacking MISC item, so what goes back in the pack is the SHARED registered template — never a
	# duplicate (which would stop stacking) and never the folded WeaponMod payload (which is not an Item).
	var part := ItemDb.item_by_id(id)
	if part == null or not part.is_weapon_mod():
		push_warning("WeaponBench: fitted part '%s' is not a registered weapon part — removal refused, no charge." % id)
		return false
	if not _has_template(gun):
		push_warning("WeaponBench: weapon '%s' has no registered ItemDb template — removal refused, no charge." % gun.id)
		return false
	if _is_drawn(gun, player) and _draw_locked(player):
		return false  # same half-state as a fit — see _transact_fit's draw-lock note
	# ⭐BAG GATE BEFORE THE CHARGE (Merchant.buy's precedent): a full pack would otherwise eat the fee AND
	# destroy the part, because the fold clears the slot whether or not the add landed.
	if not player.inventory.can_accept(part):
		return false
	# A removal is allowed to be FREE (unlike a fit, which refuses a 0 fee so no permanently-dead "0 zm" row can
	# render): the part is the player's already, and refusing to hand it back over a rounding edge is absurd.
	var cost := remove_fee(part)
	if not can_afford(float(cost), player):
		return false
	if not take_payment(float(cost), player):
		return false
	player.inventory.add(part, 1)
	_refit(gun, slot, &"", player)
	_removed(part, gun, player)
	return true

## ⭐THE ONLY PLACE A WEAPON'S STAT BLOCK EVER CHANGES. Writes one slot id, re-folds the WHOLE set from the
## PRISTINE template, hands every WeaponData-keyed runtime cache over to the new object, and re-equips if the
## gun was drawn. `new_part_id` is &"" for a removal — fit and remove are the same call with a different value,
## which is why neither can forget a step the other one does.
##
## ⭐The fold ALWAYS starts from tmpl.weapon, never from gun.weapon. That is what makes it idempotent and
## lossless: removing a part returns the authored numbers exactly, with zero accumulated float drift, and a
## MULT can never compound onto its own output. It never WRITES to tmpl.weapon either — mutating the template
## would produce an EMPTY weapon_delta (the template IS the diff baseline, so nothing would persist) while
## silently buffing every instance of that gun in the world, NPC hands and shop shelves included.
##
## ⭐migrate_weapon_state runs BEFORE equip_item and is NOT gated on `drawn`. Pre-seeding (rather than
## post-correcting) is the only ordering correct on both paths, because Attack QUEUES the equip whenever a swap
## is already in flight — on that path inventory.equip never runs this frame and any post-equip clip write
## would land on the old gun. Ungated because start_background_reload fires precisely when you swap AWAY, so
## the canonical orphaned cache belongs to a HOLSTERED weapon.
##
## ⭐equip_item, never Inventory.equip / SwapWeapons.request_equip — only equip_item keeps the bag's
## equipped_item marker, the hotbar's gold highlight, the fists fallback and the save's equipped_index coherent
## with what is actually in the player's hands.
func _refit(gun: Item, slot: int, new_part_id: StringName, player: Player) -> void:
	var tmpl := ItemDb.item_by_id(gun.id)
	if tmpl == null or not tmpl.is_weapon() or tmpl.weapon == null:
		# Unreachable: every caller runs the pre-charge template gate first. Kept because reaching it after a
		# charge would be the one failure the gate exists to prevent, and a crash here would take the level with it.
		push_warning("WeaponBench: '%s' lost its ItemDb template mid-transaction — the gun is unchanged." % gun.id)
		return
	var ids := WeaponModKit.slot_map(gun.weapon)  # {slot int -> StringName}, all six, always
	ids[slot] = new_part_id
	var fresh := WeaponModKit.rebuild(tmpl.weapon, ids, ItemDb._resolve_weapon_mod)
	if fresh == null:
		push_warning("WeaponBench: the fold produced no stat block for '%s' — the gun is unchanged." % gun.id)
		return
	var old: WeaponData = gun.weapon
	var ws: Weapon = player.weapon_system
	# ⭐THE ONE DRAWN PREDICATE, and it is _is_drawn's ITEM-identity test — never `ws.equipped_weapon == old`.
	# That WeaponData comparison was wrong twice over (a shared template makes it a false POSITIVE for a
	# holstered twin; Attack's mid-swap queue makes it a false NEGATIVE for the 3rd fit in one window, which
	# stranded an orphaned block that then refilled itself to max — a free magazine). The full argument, with
	# both failure paths, is on _is_drawn.
	var drawn: bool = _is_drawn(gun, player)
	if ws != null:
		ws.migrate_weapon_state(old, fresh)
	gun.weapon = fresh  # the Item INSTANCE survives — only the pointer moves, so every reference to the gun holds
	if drawn:
		# Feeds the sanctioned swap chain, whose Attack identity gate (`if _weapon == current_weapon: return`)
		# PASSES precisely because the fold produced a new object — that is the entire reason it must — and whose
		# tail (GunMesh._on_swap_finished) is the only beat in the game that rebuilds the view model and re-aligns
		# the Muzzle marker. Which is why a view_model_override must ride a real swap, never a silent field write.
		player.inventory.equip_item(gun)
		# The whole equip chain above is SYNCHRONOUS, and it is the one thing that can create state under the
		# block we just retired: refitting mid-reload makes Attack hand the in-progress reload to the clip as a
		# background reload for the OUTGOING weapon. Sweep it onto `fresh` now, or its completion spends a spare
		# clip out of the backpack into a key nothing will ever read again.
		if ws != null:
			ws.migrate_pending_reload(old, fresh)

## Shared FIT tail — the ONE point both fit paths reach past the charge (the ChipInstaller._grant role).
## Persist (a changed gun is worth a checkpoint), tell the player, sound the commit cue.
## The REFUSAL half of the sound pair lives on WeaponBenchScreen, at the one place each bool comes back: the
## deliberate two-file split ChipInstaller/ChipInstallScreen already carries. Duplicating the commit at the
## screen would double it; duplicating the refusal here would mean a dozen `return false` sites to keep in sync.
func _fitted(part: Item, gun: Item, player: Player) -> void:
	GameState.autosave(player)
	if player.has_method(&"notify_toast"):
		player.notify_toast(PlayerText.mod_fitted(part.label(), gun.label()), Color(0.5, 0.85, 1.0))
	MenuStyle.play_commit()

## Shared REMOVE tail — same three beats, different sentence. Kept separate from _fitted rather than taking a
## bool, so the toast template is selected by the call site and neither verb can accidentally speak the other's.
func _removed(part: Item, gun: Item, player: Player) -> void:
	GameState.autosave(player)
	if player.has_method(&"notify_toast"):
		player.notify_toast(PlayerText.mod_removed(part.label(), gun.label()), Color(0.5, 0.85, 1.0))
	MenuStyle.play_commit()

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Does `gun` still have a PRISTINE registered template to fold from? The one predicate behind both the
## pre-charge template gate and moddable_weapons' cycler filter, so the list and the till agree by construction.
func _has_template(gun: Item) -> bool:
	if gun == null:
		return false
	var tmpl := ItemDb.item_by_id(gun.id)
	return tmpl != null and tmpl.is_weapon() and tmpl.weapon != null

## Is THIS gun the one currently in the player's hands? ⭐COMPARED BY **ITEM** IDENTITY (the bag's own
## `equipped_item` marker), NEVER by WeaponData identity. Both of the obvious WeaponData tests are wrong here,
## for two independent reasons, and each one shipped a real bug before this comment existed:
##  * ItemDb.make_weapon_item SHARES the template WeaponData across every unmodded copy of a gun (its own doc
##    says so — duplicate() does not deep-copy sub-resources). So `equipped_weapon == gun.weapon` is TRUE for
##    a holstered spare pistol while you are holding a different one, and a refit on the spare would force-swap
##    the gun out of the player's hands.
##  * `Weapon.equipped_weapon` is a getter onto Inventory.equipped_weapon, which Attack only advances at the
##    TAIL of its equip handler — the mid-swap branch (attack.gd:637) QUEUES and returns first. So the hub
##    value is STALE for every refit after the first inside one swap window, and that window is unbounded on
##    the shipped dialogue-hosted bench (the conversation pauses the tree, so the Swap timer never ticks while
##    the card is up).
## `equipped_item` has neither problem: it is per-Item, and CharacterInventory.equip_item writes it
## synchronously before anything can queue.
func _is_drawn(gun: Item, player: Player) -> bool:
	if gun == null or gun.weapon == null or player == null or player.inventory == null:
		return false
	return player.inventory.equipped_item == gun

## Are the player's hands locked (mid-draw, mid-swap, scripted)? Read through the weapon component rather than
## cached, because draw_locked flips inside the very swap chain a refit starts.
func _draw_locked(player: Player) -> bool:
	if player == null:
		return false
	var ws: Weapon = player.weapon_system
	return ws != null and ws.attack != null and ws.attack.draw_locked

# ---------------------------------------------------------------------------
# Behaviour (talk-handler surface — used only when standalone, a direct-interact bench)
# ---------------------------------------------------------------------------

## Interact pressed while aimed at us: open the bench screen on this bench.
func start_talk(player: Node) -> void:
	WeaponBenchScreen.open_bench(self, player)

## Always interactable — the smith is open for business even with an empty shelf (you can still fit parts you
## found, and pull parts back out).
func can_be_talked_to() -> bool:
	return true

## Hover readout: "Gunsmith: <name>" (or just "Gunsmith" when unnamed).
func look_name() -> String:
	return PlayerText.bench_prompt(bench_name)

# ---------------------------------------------------------------------------
# Dialogue-station contract (drives the "Modify" option when this rides a dialogue NPC)
# ---------------------------------------------------------------------------

## Sort key for the speaker's station options (Merchant 10 .. Atm 70; see merchant.gd for the full contract
## description). 55 sits between ChipInstaller 50 and ChessMatch 60 — chrome for your gear next to chrome for
## yourself. A const, never an @export: two authored instances must not be able to collide silently, and the
## order is a UI contract pinned by tests/test_dialogue_speaker_contracts.gd.
const DIALOGUE_ORDER := 55

## Dialogue-station contract, half 1 — DialogueManager discovers this + open_dialogue_station on the speaker's
## direct children (both methods required) and paints the "Modify" option. Unconditional, like the rest.
func dialogue_station_option() -> Dictionary:
	return {
		"label": PlayerText.DIALOGUE_OPTION_MODIFY,
		"order": DIALOGUE_ORDER,
		"reason": "modify",
		"closed": WeaponBenchScreen.closed,
	}

## Dialogue-station contract, half 2 — the press. DialogueManager suspends the conversation and calls this;
## closing the bench screen (every refuse path emits `closed`) resumes the dialogue.
func open_dialogue_station(player: Node) -> void:
	WeaponBenchScreen.open_bench(self, player)
