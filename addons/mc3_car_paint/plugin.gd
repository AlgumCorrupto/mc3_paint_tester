@tool
extends EditorPlugin
## MC3CarPaint and MC3CarPaintPanel are registered through class_name, so nothing has to be
## registered here. This plugin only adds a convenience entry to Project > Tools.

const MENU_NAME := "MC3 Car Paint: add paint node to selected node(s)"


func _enter_tree() -> void:
	add_tool_menu_item(MENU_NAME, _add_to_selection)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_NAME)


func _add_to_selection() -> void:
	var root := EditorInterface.get_edited_scene_root()
	var selected := EditorInterface.get_selection().get_selected_nodes()
	if root == null or selected.is_empty():
		push_warning("MC3 Car Paint: select the root node of a car first.")
		return
	for n in selected:
		if n is Node3D:
			var paint := MC3CarPaint.new()
			paint.name = "MC3CarPaint"
			n.add_child(paint)
			paint.owner = root
