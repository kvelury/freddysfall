class_name Mover
extends RefCounted

## One moving thing in a room, as pure data: where each of its bodies is at a
## physics tick, whether it is there at all, and whether touching it kills.
## The game and the reach solver both ask this, so they get the same answer for
## the same tick. A back-and-forth platform (`PlatformPath`) is one body; an
## emitter's platforms and a spinner's blocks are several.
##
## Subclasses override `body_count`, `rect_at`, `alive_at`, `is_hazard`,
## `period`, `swept_cells`, `band_cells` and `keep_out`.

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
