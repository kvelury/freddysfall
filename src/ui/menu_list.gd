class_name MenuList
extends VBoxContainer

## A vertical list of menu items. The mouse hovers to select and clicks to
## pick; the arrow keys and W / S move the selection and wrap round; Enter or
## Space picks. The selected item is drawn inverted by UiTheme's "MenuItem".
## Only a list that is showing reacts to the keys.

const ITEM_WIDTH := 96


func _init() -> void:
	add_theme_constant_override("separation", 2)


## Adds an item that calls `on_pick` when picked.
func add_item(text: String, on_pick: Callable) -> Button:
	var item := Button.new()
	item.text = text
	item.theme_type_variation = "MenuItem"
	item.custom_minimum_size.x = ITEM_WIDTH
	item.alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.mouse_entered.connect(item.grab_focus)
	item.pressed.connect(on_pick)
	add_child(item)
	return item


func clear() -> void:
	for item in get_children():
		remove_child(item)
		item.queue_free()


func item_texts() -> Array[String]:
	var out: Array[String] = []
	for item: Button in get_children():
		out.append(item.text)
	return out


func focus_item(index: int) -> void:
	if get_child_count() > 0:
		(get_child(clampi(index, 0, get_child_count() - 1)) as Button).grab_focus()


func focus_first() -> void:
	focus_item(0)


## The index of the selected item, or -1.
func selected() -> int:
	for i in get_child_count():
		if (get_child(i) as Button).has_focus():
			return i
	return -1


func move(step: int) -> void:
	var count := get_child_count()
	if count == 0:
		return
	var at := selected()
	focus_item(posmod(at + step, count) if at >= 0 else 0)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_pressed() or event is InputEventMouse:
		return
	if event.is_action_pressed("ui_up") or event.is_action_pressed("jump"):
		move(-1)
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_down"):
		move(1)
	else:
		return
	get_viewport().set_input_as_handled()
