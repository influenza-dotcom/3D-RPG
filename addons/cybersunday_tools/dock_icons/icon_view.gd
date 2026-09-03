@tool
extends VBoxContainer

## CYBER SUNDAY -> Icons (Create group): bake clean, consistent inventory pictures for EVERY item. An item with a
## model (a weapon's view_model, a world_model, or a world_prop scene) renders that; an item with none renders a
## procedural primitive stand-in (icon_models.gd -- cartridges for ammo, a medkit, keyword trinkets) so no tile is
## ever a letter glyph. Each bake is a transparent, AUTOCROPPED PNG sized to the item's GRID FOOTPRINT (grid_w x
## grid_h cells), written to res://resources/icons/<item.id>.png; the grid tile loads it by id automatically
## (grid_tile.gd). The same bake also runs from the CLI (its own folder walk, not this tab's):
## godot --path <project> -s scripts/tools/bake_item_icons.gd (windowed -- it needs a renderer).
##
## CONVENTION over Item.icon ON PURPOSE: writing a PNG + letting the grid load it by id at RUNTIME avoids the
## edit-time "load a just-written, not-yet-imported PNG" race AND never mutates your item .tres files (so a re-bake
## can't clobber a concurrently-edited resource). It ONLY writes PNGs into resources/icons/. Re-runnable any time.
## EDITOR-ONLY: the render needs a real renderer, so this refuses (with a status line, never an error) headless.
##
## Layout contract (every tab in the panel): the one action button is OUTSIDE the ScrollContainer, the ONE status
## Label sits under it, and the report box -- the only thing that grows -- lives INSIDE the scroll with fit_content
## on, so a long id list grows the SCROLL, never the panel. The scroll carries a small height floor because a
## TabContainer's minimum is the CURRENT tab's minimum, and the editor's bottom splitter keeps the height it grew
## to: one tall tab would ratchet the whole bottom panel taller for every tab after it.
##
## Bake states: the bake is ASYNC (icon_baker awaits four draw frames per item), so a second press mid-bake used to
## start a SECOND interleaved bake against the same capture host -- two SubViewports racing for the same PNG names.
## Now `_baking` latches and the button greys BEFORE any early return, the status counts "Baking 12 / 49 -- <item>..."
## ahead of every await, and EVERY exit path (refusal, empty folder, finished) goes through _end_bake() so the button
## always comes back. New vs replaced is decided per file with FileAccess.file_exists BEFORE the save, so the final
## report can say what the bake actually did to the folder.
##
## Item list: the shared core/item_scan.gd (ItemDb is a NON-@tool autoload = empty inside the editor), whose
## scan_report also names the files that did NOT load as an Item -- those are reported as "couldn't load" rather
## than silently thinning the list (the mid-reimport / broken-script case).

const ItemMeshView := preload("res://scripts/ui/item_mesh_view.gd")
const Baker := preload("res://addons/cybersunday_tools/dock_icons/icon_baker.gd")
const Render := preload("res://addons/cybersunday_tools/dock_icons/icon_render.gd")
const ItemScan := preload("res://addons/cybersunday_tools/core/item_scan.gd")

## Where the PNGs land; the item folder itself is ItemScan.ITEMS_DIR (the one shared scan owns that path).
const ICONS_DIR := "res://resources/icons/"
## The same two folders as a designer reads them (the res:// form rides the tooltips, never the prose).
const ITEMS_FOLDER := "resources/items/"
const ICONS_FOLDER := "resources/icons/"

## Status / tooltip sentences, shared between the button's tooltip and the status fallback so they never drift.
const MSG_IDLE := "Press Bake All Icons -- every item gets an inventory picture in resources/icons/."
const MSG_BUSY := "Baking now -- wait for it to finish."
## Written to the status before the folder walk so the designer sees the tab is busy, not frozen.
const MSG_SCANNING := "Scanning items..."
const BAKE_TIP := "Render an inventory picture for every item into resources/icons/ (uses the item's 3D model, or a simple stand-in shape). Safe to re-run; never changes item files."
const OUT_IDLE := "[i]Each item gets one transparent picture, sized to the grid cells it takes up, saved as <item id>.png in resources/icons/. The inventory grid finds them by id on its own. Writes pictures only -- your item files are never changed.[/i]"

## Status tints -- a theme override on the Label, never bbcode. Warn for a refusal / failure, ok for a finished bake.
const TINT_WARN := Color(1.0, 0.82, 0.3)
const TINT_OK := Color(0.6, 1.0, 0.6)

var _bake_btn: Button = null
var _status: Label = null
var _out: RichTextLabel = null
var _baker := Baker.new()

## True from the press until _end_bake(): the button is greyed too, but a press queued behind the first frame can
## still land, and this latch is what keeps that from starting a second interleaved bake.
var _baking := false


func _init() -> void:
	name = "Icons"
	add_theme_constant_override("separation", 4)

	# Head row (outside the scroll): the one command. No heading -- the tab title already says it.
	var row := HBoxContainer.new()
	_bake_btn = Button.new()
	_bake_btn.text = "Bake All Icons"
	_bake_btn.tooltip_text = BAKE_TIP
	_bake_btn.pressed.connect(_on_bake_all)
	row.add_child(_bake_btn)
	add_child(row)

	# The ONE status Label: progress ("Baking 12 / 49 -- ...") and the one-line verdict, two lines max with the full
	# text mirrored into its tooltip on every write.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	add_child(_status)
	_set_status(MSG_IDLE)

	# Everything that grows scrolls: the report box is fit_content so its height follows the text and the scroll
	# (not the tab) absorbs it. Horizontal scroll is off so a long id list wraps instead of widening the panel.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 90)
	add_child(scroll)
	_out = RichTextLabel.new()
	_out.bbcode_enabled = true
	_out.fit_content = true
	_out.selection_enabled = true
	_out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_out)
	_set_out(OUT_IDLE)


## The one write command. Latches + greys FIRST, then refuses or runs, and every path ends in _end_bake().
func _on_bake_all() -> void:
	if _baking:
		return  # a press that slipped in behind the grey-out: the running bake owns the folder
	_baking = true
	_bake_btn.disabled = true
	_bake_btn.tooltip_text = MSG_BUSY
	if DisplayServer.get_name() == "headless":
		_set_status("Couldn't bake icons: no renderer here -- open this tab inside the editor.", TINT_WARN)
		_end_bake()
		return
	if not is_inside_tree():
		# The baker parents its capture viewport under this tab, so it must be on screen (icon_baker returns null
		# for every item otherwise -- which would read as "49 skipped" instead of the real reason).
		_set_status("Couldn't bake icons: the Icons tab isn't on screen yet -- open it, then bake.", TINT_WARN)
		_end_bake()
		return

	# The folder walk LOADS every item file, so it can hang a beat on a big project. Say so and give the editor
	# one frame to paint the greyed button and this line before the walk starts; every exit below still ends in
	# _end_bake(), so the button always comes back.
	_set_status(MSG_SCANNING)
	await get_tree().process_frame
	var rep := ItemScan.scan_report(ItemScan.ITEMS_DIR)
	var items: Array[Item] = rep["items"]
	var unreadable: PackedStringArray = rep["skipped"]
	if items.is_empty():
		var why := "no items found in %s" % ITEMS_FOLDER
		if not unreadable.is_empty():
			why = "%d item files couldn't be loaded (reimport in progress?)" % unreadable.size()
		_set_status("Couldn't bake icons: %s." % why, TINT_WARN)
		var unreadable_bb := _unreadable_bb(unreadable)
		_set_out(OUT_IDLE if unreadable_bb == "" else unreadable_bb)
		_end_bake()
		return

	# Per item: a progress line BEFORE the await (the designer sees which item is rendering, and a hang names its
	# culprit), then new-vs-replaced is decided by the file's existence BEFORE the save.
	var total := items.size()
	var new_ids := PackedStringArray()
	var replaced_ids := PackedStringArray()
	var failed := PackedStringArray()  # "<label> (<reason>)" per item that rendered nothing or didn't save
	for i in total:
		var item: Item = items[i]
		var id := String(item.id)
		var label := _item_label(item)
		_set_status("Baking %d / %d -- %s..." % [i + 1, total, label])
		var px := Render.pixel_size(item.grid_width, item.grid_height, Baker.CELL)
		var img = await _baker.bake_item(item, px, self)  # async: authored model, else a primitive stand-in
		if img == null:
			failed.append("%s (nothing rendered -- a broken or empty model)" % label)
			continue
		var path := ICONS_DIR + id + ".png"
		var existed := FileAccess.file_exists(path)
		var err := Baker.save_png(img, path)
		if err != OK:
			failed.append("%s (couldn't save the picture: %s)" % [label, error_string(err)])
			continue
		if existed:
			replaced_ids.append(id)
		else:
			new_ids.append(id)
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()  # import the new PNGs so the grid can load them

	var baked := new_ids.size() + replaced_ids.size()
	var all_ids := PackedStringArray()
	all_ids.append_array(new_ids)
	all_ids.append_array(replaced_ids)
	var summary := "Baked %d icons: %d new, %d replaced -> %s (%s)" % [baked, new_ids.size(), replaced_ids.size(), ICONS_FOLDER, ", ".join(all_ids)]
	var bb := ""
	if baked > 0:
		bb = "[color=lime]%s[/color]" % summary
	else:
		bb = "[color=#ffd24d]Baked 0 icons -- none of the %d items rendered.[/color]" % total
	if not failed.is_empty():
		bb += "\n[color=#ffd24d]%d skipped:[/color] %s" % [failed.size(), ", ".join(failed)]
	var unreadable_bb := _unreadable_bb(unreadable)
	if unreadable_bb != "":
		bb += "\n" + unreadable_bb
	# GOTCHA: a game already running picked up its import table at launch and won't see PNGs imported after -- so a
	# fresh bake looks like "nothing changed" until you relaunch. Spell that out; it's the #1 confusion with this tab.
	bb += "\n[color=#9fd0ff]Already running the game? Stop it and press F5 again to see the new pictures[/color] -- a running game keeps the picture list it started with."
	_set_out(bb)

	if baked > 0:
		var tail := ""
		if not failed.is_empty() or not unreadable.is_empty():
			tail = "; %d skipped (see below)" % (failed.size() + unreadable.size())
		_set_status("Baked %d icons -- %d new, %d replaced -> %s%s." % [baked, new_ids.size(), replaced_ids.size(), ICONS_FOLDER, tail], TINT_OK)
	else:
		_set_status("Couldn't bake icons: none of the %d items rendered -- see below." % total, TINT_WARN)
	_end_bake()


## The exit for EVERY path out of _on_bake_all: releases the latch and hands the button back with its real tooltip.
func _end_bake() -> void:
	_baking = false
	if _bake_btn != null:
		_bake_btn.disabled = false
		_bake_btn.tooltip_text = BAKE_TIP


## What a designer calls the item: its display name, else its id (the PNG's file name), else its file name.
static func _item_label(item: Item) -> String:
	if item == null:
		return "(missing item)"
	if item.display_name != "":
		return item.display_name
	if String(item.id) != "":
		return String(item.id)
	return item.resource_path.get_file()


## The "couldn't load" line for files under resources/items/ that did not load as an Item -- named by file name
## (the folder is the one folder), or "" when every file loaded so the report stays quiet.
static func _unreadable_bb(unreadable: PackedStringArray) -> String:
	if unreadable.is_empty():
		return ""
	var names := PackedStringArray()
	for p in unreadable:
		names.append(String(p).get_file())
	return "[color=#ffd24d]%d item files couldn't be loaded[/color] (reimport in progress? -- or a broken script): %s" % [names.size(), ", ".join(names)]


func _set_out(bb: String) -> void:
	if _out != null:
		_out.text = bb


func _set_status(msg: String, tint: Color = Color()) -> void:
	if _status == null:
		return
	_status.text = msg
	_status.tooltip_text = msg
	if tint.a > 0.0:
		_status.add_theme_color_override("font_color", tint)
	else:
		_status.remove_theme_color_override("font_color")
