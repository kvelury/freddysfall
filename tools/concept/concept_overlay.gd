class_name ConceptOverlay
extends Node2D

## CONCEPT ONLY. Draws Imprint slots around Freddy in world space.
## Each ghost is {"dir", "ring", "style"}; style is aim, aim_far, lit or selected.

const ARROW_RIGHT := ["..#..", "...#.", "#####", "...#.", "..#.."]
const ARROW_UPRIGHT := [".####", "...##", "..#.#", ".#..#", "#...."]

var room: Room
var player: Player
var tool: ImprintTool
var ghosts: Array = []
var labels := false


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	z_index = 5


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if room == null or player == null:
		return
	var width := GameState.abilities.imprint_width
	var local := player.global_position - room.position
	var body := Rect2(local - MovementSim.HALF, MovementSim.HALF * 2.0)
	var others: Array[Rect2] = []
	if tool != null:
		for p in tool.platforms:
			others.append(Rect2(p.rect.position - room.position, p.rect.size))
	for g in ghosts:
		var cell := ConceptSlots.cell_for(local, player.facing, g["dir"], g["ring"], width)
		var legal := ImprintRules.check(room.info, cell, width, body, others).is_empty() and others.is_empty()
		var origin := room.position + Vector2(cell) * float(Grid.CELL)
		var area := Rect2(origin, Vector2(width * Grid.CELL, Grid.CELL))
		var near: bool = g["ring"] == ConceptSlots.NEAR
		match String(g["style"]):
			"aim":
				_slot(area, legal, Color.WHITE, false)
			"aim_far":
				_slot(area, legal, Color(1, 1, 1, 0.45), false)
			"lit":
				_slot(area, legal, Color(1, 1, 1, 0.6 if near else 0.35), false)
			"selected":
				_slot(area, legal, Color.WHITE, true)
		if labels:
			var arrow: Vector2 = ConceptSlots.ARROWS[g["dir"]]
			arrow.x *= player.facing
			var a := Color.WHITE if near else Color(1, 1, 1, 0.55)
			_arrow(area.position + Vector2(2, 2), arrow, a)
			_letter("J" if near else "K", area.position + Vector2(12, 2), a)


func _slot(area: Rect2, legal: bool, color: Color, solid: bool) -> void:
	if not legal:
		_cross(area.position + Vector2(Grid.CELL, Grid.CELL) * 0.5, color)
		return
	if solid:
		draw_rect(area, Color(color, 0.3))
		draw_rect(area.grow(-0.5), color, false, 1.0)
		# Corner ticks just outside, so the choice reads at a glance.
		for c in [area.position, Vector2(area.end.x, area.position.y), Vector2(area.position.x, area.end.y), area.end]:
			var sx := -1.0 if c.x == area.position.x else 0.0
			var sy := -1.0 if c.y == area.position.y else 0.0
			draw_rect(Rect2(c.x + sx * 2.0 + (0.0 if sx < 0 else 1.0), c.y + sy, 1, 1), color)
			draw_rect(Rect2(c.x + sx, c.y + sy * 2.0 + (0.0 if sy < 0 else 1.0), 1, 1), color)
		return
	var x := 0
	while x < int(area.size.x):
		if x % 2 == 0:
			draw_rect(Rect2(area.position.x + x, area.position.y, 1.0, 1.0), color)
			draw_rect(Rect2(area.position.x + x, area.end.y - 1.0, 1.0, 1.0), color)
		x += 1
	var y := 0
	while y < int(area.size.y):
		if y % 2 == 0:
			draw_rect(Rect2(area.position.x, area.position.y + y, 1.0, 1.0), color)
			draw_rect(Rect2(area.end.x - 1.0, area.position.y + y, 1.0, 1.0), color)
		y += 1


func _cross(center: Vector2, color: Color) -> void:
	var c := center.floor()
	draw_rect(Rect2(c.x - 3.0, c.y - 3.0, 7.0, 7.0), Color(0, 0, 0, color.a))
	for i in 5:
		draw_rect(Rect2(c.x - 2.0 + i, c.y - 2.0 + i, 1.0, 1.0), color)
		draw_rect(Rect2(c.x - 2.0 + i, c.y + 2.0 - i, 1.0, 1.0), color)


## A 5x5 pixel arrow pointing along `dir` (each component -1, 0 or 1).
func _arrow(at: Vector2, dir: Vector2, color: Color) -> void:
	var diagonal := dir.x != 0 and dir.y != 0
	var pattern: Array = ARROW_UPRIGHT if diagonal else ARROW_RIGHT
	for py in 5:
		for px in 5:
			if pattern[py][px] != "#":
				continue
			var u := px
			var v := py
			if diagonal:
				# Drawn up-right; flip for the others.
				if dir.x < 0:
					u = 4 - px
				if dir.y > 0:
					v = 4 - py
			elif dir.x < 0:
				u = 4 - px
			elif dir.y != 0:
				# Rotate the right arrow to point up or down.
				u = py
				v = 4 - px if dir.y < 0 else px
			draw_rect(Rect2(at.x + u, at.y + v, 1, 1), color)


## Tiny 3x5 glyphs for the key letters.
const GLYPHS := {
	"J": ["..#", "..#", "..#", "#.#", ".#."],
	"K": ["#.#", "#.#", "##.", "#.#", "#.#"],
}


func _letter(letter: String, at: Vector2, color: Color) -> void:
	var g: Array = GLYPHS[letter]
	for py in 5:
		for px in 3:
			if g[py][px] == "#":
				draw_rect(Rect2(at.x + px, at.y + py, 1, 1), color)
