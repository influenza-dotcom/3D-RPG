extends SceneTree
## QA probe: shoot the Options menu's Quit Game confirm overlay as it renders (WINDOWED — a UI look is a
## draw-time question; headless renders nothing). Boots the project's autoloads, forces the OptionsMenu
## root + %QuitConfirm visible without open() (no Player needed), settles, writes quit_confirm.png and
## prints the CardPanel's resolved `panel` stylebox + the dim colour.
##
##   & "C:\Users\dalla\bin\godot.cmd" --path . -s scripts/tools/probes/__quit_confirm_shot.gd -- --shots-dir=<dir>

var _dir := "."
var _frame := 0

func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 5:
		for a in OS.get_cmdline_user_args():
			if String(a).begins_with("--shots-dir="):
				_dir = String(a).trim_prefix("--shots-dir=")
		var om: Node = root.get_node("OptionsMenu")
		var r: Control = om.get_node("%Root")
		r.visible = true
		var qc: Control = om.get_node("%QuitConfirm")
		qc.visible = true
		var panel: PanelContainer = om.get_node("%QuitCard").get_parent()
		var sb: StyleBox = panel.get_theme_stylebox(&"panel")
		print("[qc] panel stylebox=%s override=%s" % [sb, panel.has_theme_stylebox_override(&"panel")])
		if sb is StyleBoxFlat:
			print("[qc] bg=%s border=%d draw_center=%s" % [sb.bg_color, sb.border_width_left, sb.draw_center])
		print("[qc] dim=%s vis=%s size=%s" % [om.get_node("%QuitDim").color, om.get_node("%QuitDim").is_visible_in_tree(), panel.size])
		print("[qc] card size=%s pos=%s panel pos=%s" % [om.get_node("%QuitCard").size, om.get_node("%QuitCard").global_position, panel.global_position])
	if _frame == 40:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(_dir.path_join("quit_confirm.png"))
		print("[qc] wrote quit_confirm.png")
		quit()
	return false
