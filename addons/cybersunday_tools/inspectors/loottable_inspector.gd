@tool
extends EditorInspectorPlugin

## LootTable inspector add-on: injects a drop-summary card + a "Roll 1000×" Monte-Carlo at the top of a LootTable's
## inspector, so a designer sees what the table actually yields (and spots null items / chance 0 / max<min) without
## playtesting drops. tally()/summary_text() are pure + seeded -> unit-tested.


func _can_handle(object: Object) -> bool:
	return object is LootTable


func _parse_begin(object: Object) -> void:
	if object is LootTable:
		add_custom_control(_build_card(object as LootTable))


func _build_card(lt: LootTable) -> Control:
	var box := VBoxContainer.new()
	var head := Label.new()
	head.text = "LootTable — %d entr%s" % [lt.entries.size(), "y" if lt.entries.size() == 1 else "ies"]
	box.add_child(head)
	var i := 0
	for e in lt.entries:
		var line := Label.new()
		line.modulate = Color(1, 1, 1, 0.8)
		if e == null:
			line.text = "  [%d] (null entry — drops nothing)" % i
		elif e.item == null:
			line.text = "  [%d] (no item — drops nothing)" % i
		else:
			line.text = "  [%d] %s  ×%d–%d  @ %.0f%%" % [i, _item_label(e.item), e.min_count, e.max_count, e.chance * 100.0]
		box.add_child(line)
		i += 1
	var btn := Button.new()
	btn.text = "Roll 1000×"
	var result := Label.new()
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.pressed.connect(func() -> void: result.text = summary_text(lt, 1000, 12345))
	box.add_child(btn)
	box.add_child(result)
	return box


## Monte-Carlo tally of `n` independent rolls, seeded for determinism. Returns { item: {"hits", "total"} }.
static func tally(lt: LootTable, n: int, rng_seed: int) -> Dictionary:
	var out := {}
	if lt == null:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for _i in n:
		for d in lt.roll(rng):
			var it: Object = d["item"]
			if not out.has(it):
				out[it] = {"hits": 0, "total": 0}
			out[it]["hits"] += 1
			out[it]["total"] += int(d["count"])
	return out


static func summary_text(lt: LootTable, n: int, rng_seed: int) -> String:
	var t := tally(lt, n, rng_seed)
	if t.is_empty():
		return "%d rolls: nothing dropped (empty / null items / zero chance?)." % n
	var lines := PackedStringArray(["%d rolls:" % n])
	for it in t:
		var h: int = t[it]["hits"]
		var tot: int = t[it]["total"]
		lines.append("  %s — %.1f%% of rolls, avg %.2f / roll" % [_item_label(it), 100.0 * float(h) / float(n), float(tot) / float(n)])
	return "\n".join(lines)


static func _item_label(it: Object) -> String:
	if it == null:
		return "(null)"
	var dn: Variant = it.get("display_name")
	if dn is String and dn != "":
		return dn
	if it is Resource and (it as Resource).resource_path != "":
		return (it as Resource).resource_path.get_file()
	return str(it)
