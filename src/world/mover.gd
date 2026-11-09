class_name Mover
extends RefCounted

## One moving thing in a room, as pure data: where each of its bodies is at a
## physics tick, whether it is there at all, and whether touching it kills.
## The game and the reach solver both ask this, so they get the same answer for
## the same tick. A back-and-forth platform (`PlatformPath`) is one body; an
## emitter's platforms and a spinner's blocks are several.
##
## Subclasses override `body_count`, `rect_at`, `alive_at`, `is_hazard`,
## `period`, `swept_cells`, `band_cells` and `keep_out`. A mover whose bodies
## are not axis-aligned boxes (a spinner's turned bar) also overrides `smooth`,
## `spans_at`, `carry_at`, `push_at`, `rideable_at` and `stand_spots`.

const TICKS_PER_SECOND := 60

var id := ""


## How many bodies it has. A body keeps its index for good.
func body_count() -> int:
	return 1


## Body `body` at `tick`, in room pixels. A body that is not there has no
## meaningful rect; check `alive_at` first.
func rect_at(_tick: int, _body := 0) -> Rect2:
	return Rect2()


## Whether body `body` exists at `tick`. A body that is gone is not solid, not
## carried and not deadly.
func alive_at(_tick: int, _body := 0) -> bool:
	return true


## Whether body `body` at `tick + 1` is the same thing it was at `tick`, so it
## carries and pushes smoothly from one to the other. An emitted platform that
## breaks and is replaced in its slot is not: nothing rides across.
func continuous_at(_tick: int, _body := 0) -> bool:
	return true


## Whether touching body `body` kills (spikes), instead of holding the player up.
func is_hazard(_body := 0) -> bool:
	return false


## Ticks until it repeats exactly.
func period() -> int:
	return 1


## Every cell any of its bodies covers, in room cells.
func swept_cells() -> Rect2i:
	return Rect2i()


## The cells just above everywhere it goes that must stay open air, for a rider.
func band_cells() -> Rect2i:
	return Rect2i()


## The swept cells and the band above them, in room pixels: where nothing else
## may be, and where an Imprint may not go.
func keep_out() -> Rect2:
	return Grid.cell_rect(swept_cells().merge(band_cells()))


## Whether its bodies are turned shapes drawn as rows of pixels (`spans_at`),
## which a body walking on them climbs a few pixels at a time instead of
## stopping at each step. A box on rails is not.
func smooth() -> bool:
	return false


## The rects body `body` is made of at `tick`, in room pixels: its box, for a
## body that is one. A turned body is rows of whole pixels, 1 px tall, that
## are exactly what is drawn.
func spans_at(tick: int, body := 0) -> Array[Rect2]:
	return [rect_at(tick, body)]


## How far a body standing at `point` is carried from `tick` to `tick + 1` by
## body `body`: the body's own step, or for a turning one the point going round.
func carry_at(tick: int, body: int, _point: Vector2) -> Vector2:
	return rect_at(tick + 1, body).position - rect_at(tick, body).position


## How far a body whose box is centred on `centre` has to go to leave body
## `body` at `tick`, by the shortest way, or `Vector2.INF` if this mover has no
## exact shape (the caller then pushes it out of the body's box).
func push_at(_tick: int, _body: int, _centre: Vector2) -> Vector2:
	return Vector2.INF


## Whether a body can stand on body `body` at `tick`: false when the face it
## would stand on is too steep or faces down.
func rideable_at(_tick: int, _body: int) -> bool:
	return true


## Where a rider can stand on body `body` at `tick`, as (x of the body's centre,
## y of the top it stands on): the left and right ends, where it hangs on, and
## the middle of each cell.
func stand_spots(tick: int, body := 0) -> Array[Vector2]:
	var rect := rect_at(tick, body)
	var cell := float(Grid.CELL)
	var out: Array[Vector2] = [Vector2(rect.position.x - cell * 0.5 + 0.01, rect.position.y)]
	for x in range(roundi(rect.size.x / cell)):
		out.append(Vector2(rect.position.x + (float(x) + 0.5) * cell, rect.position.y))
	out.append(Vector2(rect.end.x + cell * 0.5 - 0.01, rect.position.y))
	return out


## Whether this mover turns or moves as one body with `other` (a spinner that
## shares a pivot, period and direction with it), so neither pushes a body that
## is standing on the other.
func rigid_with(_other: Mover) -> bool:
	return false
