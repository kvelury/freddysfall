class_name UiTheme
extends RefCounted

## The monochrome look shared by the dev panel and the menus: black boxes with
## a one pixel white border and white text.


## A small monochrome theme keeps controls usable at the native pixel scale.
## The "MenuItem" variation of Button is a menu item: the focused or hovered
## one is inverted (white box, black text).
static func build() -> Theme:
	var out := Theme.new()
	out.default_font_size = 8
	var box := StyleBoxFlat.new()
	box.bg_color = Color.BLACK
	box.border_color = Color.WHITE
	box.set_border_width_all(1)
	box.content_margin_left = 3
	box.content_margin_right = 3
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	for type in ["PanelContainer", "TabContainer", "Button", "LineEdit", "ItemList"]:
		for style in ["panel", "normal", "hover", "pressed", "focus", "selected", "selected_focus", "tab_selected", "tab_unselected"]:
			out.set_stylebox(style, type, box)
		for color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_selected_color", "font_unselected_color", "font_outline_color"]:
			out.set_color(color, type, Color.WHITE)
	for style in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
		out.set_stylebox(style, "VScrollBar", box)
	for on in [false, true]:
		var pixels := Image.create(12, 6, false, Image.FORMAT_RGBA8)
		pixels.fill(Color.BLACK)
		for x in 12:
			pixels.set_pixel(x, 0, Color.WHITE)
			pixels.set_pixel(x, 5, Color.WHITE)
		for y in 6:
			pixels.set_pixel(0, y, Color.WHITE)
			pixels.set_pixel(11, y, Color.WHITE)
		pixels.fill_rect(Rect2i(7 if on else 2, 2, 3, 2), Color.WHITE)
		out.set_icon("checked" if on else "unchecked", "CheckButton", ImageTexture.create_from_image(pixels))
	var item := StyleBoxFlat.new()
	item.bg_color = Color.WHITE
	item.border_color = Color.WHITE
	item.set_border_width_all(1)
	item.content_margin_left = 3
	item.content_margin_right = 3
	item.content_margin_top = 2
	item.content_margin_bottom = 2
	out.set_type_variation("MenuItem", "Button")
	out.set_stylebox("normal", "MenuItem", box)
	for style in ["hover", "pressed", "focus"]:
		out.set_stylebox(style, "MenuItem", item)
	out.set_color("font_color", "MenuItem", Color.WHITE)
	for color in ["font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		out.set_color(color, "MenuItem", Color.BLACK)
	return out


## Big centred text with a black outline, for the game's title and title cards.
## It is 320 wide, the width of a screen in UI units.
static func title_label(text: String, size := 24) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 320
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label
