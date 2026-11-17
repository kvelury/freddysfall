class_name RoomView
extends RefCounted

## How much of the world the camera shows. Pure: no node, no input and no
## autoload. A room's "view" is how many screens (320 x 180 world px) the camera
## shows across and down: 1 (the default) or, for a room too big to play through
## one screen, more. Only views that keep every world pixel a whole number of
## screen pixels are allowed (`allowed`), so a zoomed room is still on the
## world-pixel grid. It is read from `data/world.json` (`"view": 2`), never from
## the room file, so it is not part of what the solver caches.
##
## Kept out of `Grid` on purpose: `grid.gd` is one of the solver's fingerprinted
## files, and editing it would re-solve every room.


## The views the viewport can show on whole pixels: the divisors of the render
## scale, from 1 up. At a render scale of 2 that is 1 and 2.
static func allowed() -> Array[int]:
	var out: Array[int] = []
	for view in range(1, Display.RENDER_SCALE + 1):
		if Display.RENDER_SCALE % view == 0:
			out.append(view)
	return out


static func is_allowed(view: int) -> bool:
	return allowed().has(view)


## The part of the world the camera shows, in world px.
static func size(view: float) -> Vector2:
	return Grid.SCREEN_SIZE * view


## The camera zoom that fits `view_size` world px to the viewport. 2 for one
## screen, 1 for two; a door glide passes sizes in between.
static func zoom_for(view_size: Vector2) -> Vector2:
	return Vector2(Display.VIEWPORT) / view_size


## Whether a room of `screens` screens can show `view` without the void around it.
static func fits(view: int, screens: Vector2i) -> bool:
	return screens.x >= view and screens.y >= view


## Where the camera sits to show `focus`, clamped inside a room. As
## `Grid.camera_focus`, but for a view of `view_size` world px instead of one
## screen: on an axis where the room is no bigger than the view the camera
## centres on the room, otherwise it follows the focus and stops at the room's
## edge. `look_y` (looking up or down) is added after the follow is clamped and
## is clamped again. The result is whole world pixels.
static func camera_focus(room_origin: Vector2, room_size: Vector2, view_size: Vector2, focus: Vector2, look_y := 0.0) -> Vector2:
	var half := view_size * 0.5
	var cam := focus
	if room_size.x <= view_size.x:
		cam.x = room_origin.x + room_size.x * 0.5
	else:
		cam.x = clampf(focus.x, room_origin.x + half.x, room_origin.x + room_size.x - half.x)
	if room_size.y <= view_size.y:
		cam.y = room_origin.y + room_size.y * 0.5
	else:
		cam.y = clampf(focus.y, room_origin.y + half.y, room_origin.y + room_size.y - half.y)
		cam.y = clampf(cam.y + look_y, room_origin.y + half.y, room_origin.y + room_size.y - half.y)
	return cam.round()


## How far looking up or down moves the view, as a multiple of the one-screen
## shift: a quarter of the view, not of a screen.
static func look_scale(view_size: Vector2) -> float:
	return view_size.y / Grid.SCREEN_SIZE.y
