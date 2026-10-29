class_name InventoryMarks
extends RefCounted

## The player's inventory, drawn on the body (`PlayerBody`): a small 2 x 1 line cut
## out for each token carried, and a line near the bottom once Imprint is found.
##
## This is the rule; where the cuts go is data on each picture
## (`FreddySprites.Frame.tokens` and `line`), in box pixels facing right, so a
## picture of a different shape places its own marks. `FreddySprites` cuts them
## in black from the body and then mirrors the finished picture, so nothing here
## knows which way the player faces. Which way that is shows in the frog itself:
## its front is notched and its rear carries the stack.

## How wide each token's line is.
const WIDTH := 2
## The pocket cap, `GameState.TOKEN_CAP`.
const MAX_TOKENS := GameState.TOKEN_CAP


## The pixels cut from `frame` for `tokens` carried and Imprint found, facing right.
static func pixels(frame: FreddySprites.Frame, tokens: int, imprint: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in mini(mini(tokens, MAX_TOKENS), frame.tokens.size()):
		for dx in WIDTH:
			out.append(frame.tokens[i] + Vector2i(dx, 0))
	if imprint:
		out.append_array(frame.line)
	return out
