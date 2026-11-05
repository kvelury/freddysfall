class_name ControlsView
extends VBoxContainer

## A list of controls: the keys as little key caps on the left, and what they
## do on the right. The Controls page and the power popups both use it. The
## Controls page lines the keys up in a column; a popup sets `centered`, so each
## line (keys and label together) sits in the middle.

const KEY_COLUMN := 120

## Centre each line instead of lining the keys up in a column.
var centered := false

var _rows: Array = []


func _init() -> void:
	add_theme_constant_override("separation", 2)


## Redraws when the player switches between keyboard and controller.
func _enter_tree() -> void:
	var bindings := get_node_or_null("/root/InputBindings")
	if bindings != null and not bindings.device_changed.is_connected(_redraw):
		bindings.device_changed.connect(_redraw)
		bindings.bindings_changed.connect(_redraw)


func _redraw() -> void:
	show_rows(_rows)


## Shows `rows` (from Controls) in place of whatever was showing, with the
## keys or the buttons of the device last used. A row the device has nothing
## for (the legacy mouse platform on a controller) is left out.
func show_rows(rows: Array) -> void:
	_rows = rows
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for row: Dictionary in rows:
		var groups := Controls.key_groups(row)
		if groups.is_empty():
			continue
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		if centered:
			line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		add_child(line)
		var keys := HBoxContainer.new()
		if not centered:
			keys.custom_minimum_size.x = KEY_COLUMN
			keys.alignment = BoxContainer.ALIGNMENT_END
		keys.add_theme_constant_override("separation", 2)
		line.add_child(keys)
		for g in groups.size():
			if g > 0:
				keys.add_child(_text("/"))
			for k in groups[g].size():
				if k > 0 and bool(row.get("combo", false)):
					keys.add_child(_text("+"))
				keys.add_child(KeyCap.new(groups[g][k]))
		line.add_child(_text(String(row["label"])))


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label
