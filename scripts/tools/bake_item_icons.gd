extends SceneTree

## CLI inventory-icon baker — the same pipeline as CYBER SUNDAY → Icons, runnable without clicking the editor:
##
##   godot --path <absolute project path> -s scripts/tools/bake_item_icons.gd
##
## WINDOWED on purpose: the bake needs a real renderer, so do NOT pass --headless (it exits with an error there).
## A window flashes for a couple of seconds while EVERY Item under res://resources/items/ renders to an
## autocropped res://resources/icons/<id>.png — its authored model (weapon view_model / world_model / world_prop
## scene) when it has one, else a procedural primitive stand-in (icon_models.gd) — then it quits. Freshly written
## PNGs still need the EDITOR to import them before the game can load them — focusing the open editor triggers
## that scan automatically.
##
## -s runs before autoloads, so everything is load()ed lazily in _run — no top-level preloads (see the
## godot-headless memory: -s compiles the script before autoloads exist).

func _initialize() -> void:
	_run()  # fire-and-forget coroutine: _initialize itself can't await, the tree keeps ticking while _run does


func _run() -> void:
	await process_frame  # _initialize fires before the root window reports in-tree; children added now would fail
						 # bake()'s host.is_inside_tree() guard (verified live) — one frame settles it
	if DisplayServer.get_name() == "headless":
		push_error("bake_item_icons: needs a renderer — run WITHOUT --headless.")
		quit(1)
		return
	var Baker = load("res://addons/cybersunday_tools/dock_icons/icon_baker.gd")
	var Render = load("res://addons/cybersunday_tools/dock_icons/icon_render.gd")
	var baker = Baker.new()
	var host := Node.new()
	root.add_child(host)  # the baker parents its capture SubViewport here (must be in-tree)

	var items_dir := "res://resources/items/"
	var baked: Array = []
	var failed: Array = []
	var d := DirAccess.open(items_dir)
	if d == null:
		push_error("bake_item_icons: can't open " + items_dir)
		quit(1)
		return
	for f in d.get_files():
		var fn := f.trim_suffix(".remap")
		if fn.get_extension() != "tres":
			continue
		var item = load(items_dir + fn)
		if not (item is Item):
			continue
		var px: Vector2i = Render.pixel_size(item.grid_width, item.grid_height, Baker.CELL)
		var img = await baker.bake_item(item, px, host)  # authored model, else a primitive stand-in — every item bakes
		if img == null:
			failed.append(String(item.id))
			continue
		if Baker.save_png(img, "res://resources/icons/" + String(item.id) + ".png") == OK:
			baked.append(String(item.id))
		else:
			failed.append(String(item.id))
	print("bake_item_icons: baked %d -> res://resources/icons/  [%s]" % [baked.size(), ", ".join(baked)])
	if not failed.is_empty():
		print("bake_item_icons: FAILED %d: %s" % [failed.size(), ", ".join(failed)])
	quit(0 if failed.is_empty() else 1)
