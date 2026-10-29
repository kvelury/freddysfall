class_name InventoryMarks
extends RefCounted

## The player's inventory, drawn on the body (`PlayerBody`): a small 2 x 1 line cut
## out for each token carried, and a line near the bottom once Imprint is found.
##
## The body is 10 x 10 pixels. Cut-outs are black, in pixel columns and rows
## counted from the top left of the body facing right, which is how
## `FreddySprites` draws Freddy. The first two tokens stack bottom to top on the
## side opposite facing, one pixel inside the body edge with one clear row
## between them; the third sits in the middle of the body, level with the gap
## between them, so no mark is up by the eyes. The Imprint line runs along the
## last row of the belly, from the middle to the front, one clear row under the
## third token. Which way the player faces is shown by the frog itself: its
## front is notched and its rear carries the stack.

const SIZE := 10
## The left pixel of each token's 2 x 1 line when facing right, in the order
## they are filled.
const SLOTS: Array[Vector2i] = [Vector2i(1, 6), Vector2i(1, 4), Vector2i(4, 5)]
const WIDTH := 2
const LINE_ROW := 7
const LINE_FROM := 4
const LINE_TO := 8


## The body pixels cut out for `tokens` carried, Imprint found or not, as drawn
## facing `face` (1 right, -1 left).
static func pixels(tokens: int, imprint: bool, face := 1) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in mini(tokens, SLOTS.size()):
		for dx in WIDTH:
			out.append(SLOTS[i] + Vector2i(dx, 0))
	if imprint:
		for x in range(LINE_FROM, LINE_TO + 1):
			out.append(Vector2i(x, LINE_ROW))
	if face < 0:
		for i in out.size():
			out[i] = Vector2i(SIZE - 1 - out[i].x, out[i].y)
	return out
