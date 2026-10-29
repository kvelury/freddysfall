extends SceneTree

## Writes icon.svg, the project icon and so the web page's favicon: Freddy
## standing, facing right, with no marks, in his colours on the game's black,
## one cell of black round him. Drawn from `FreddySprites` so it is the same
## picture the game draws. Run: godot --headless --path . --script tools/make_icon.gd

const MARGIN := 1


func _init() -> void:
	var size := FreddySprites.SIZE + 2 * MARGIN
	var out := PackedStringArray()
	out.append('<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 %d %d" shape-rendering="crispEdges">' % [size, size])
	out.append('  <rect width="%d" height="%d" fill="#000000"/>' % [size, size])
	var drawn := FreddySprites.rects(PlayerAnimator.Pose.STAND, 0, 1, 0, false)
	for layer in drawn.layers:
		for box in layer.rects:
			out.append('  <rect x="%d" y="%d" width="%d" height="%d" fill="#%s"/>' % [box.position.x + MARGIN, box.position.y + MARGIN, box.size.x, box.size.y, layer.colour.to_html(false)])
	out.append("</svg>")
	var file := FileAccess.open("res://icon.svg", FileAccess.WRITE)
	file.store_string("\n".join(out) + "\n")
	file.close()
	print("icon.svg written")
	quit()
