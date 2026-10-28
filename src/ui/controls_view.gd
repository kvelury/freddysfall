class_name ControlsView
extends VBoxContainer

## A list of controls: the keys as little key caps on the left, and what they
## do on the right. The Controls page and the power popups both use it. The
## Controls page lines the keys up in a column; a popup sets `centered`, so each
## line (keys and label together) sits in the middle.

const KEY_COLUMN := 120

## Centre each line instead of lining the keys up in a column.
var centered := false


func _init() -> void:
	add_theme_constant_override("separation", 2)


## Shows `rows` (from Controls) in place of whatever was showing.
func show_rows(rows: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for row: Dictionary in rows:
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
		var groups := Controls.key_groups(row)
		for g in groups.size():
			if g > 0:
				keys.add_child(_text("/"))
			for key: String in groups[g]:
				keys.add_child(KeyCap.new(key))
		line.add_child(_text(String(row["label"])))


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label
