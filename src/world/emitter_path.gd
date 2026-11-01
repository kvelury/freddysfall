class_name EmitterPath
extends PlatformPath

## A machine that spits out platforms. It is drawn like a moving platform: a row
## of its glyph where each platform appears (against a solid wall, the machine),
## with its track running straight on to where the platforms break. A new one
## appears every `every` seconds, slides along the track at `speed`, and breaks
## the moment it reaches the end of the track, where the next cell has to be
## spikes or solid. It never goes back. Each platform is one body, and a body is
## there only for its trip, so a rider falls when theirs breaks.
##
## Bodies are fixed slots: slot `k` is there at tick `t` when `t - k * every` is
## inside its trip, counted modulo `period()`. Everything is whole ticks, so the
## game and the solver agree.

## Ticks between one platform and the next.
var every_ticks := 1
## How many platforms can be out at once, which is how many bodies it has.
var slots := 1
## Ticks a platform lasts: its whole trip, from appearing to breaking.
var life_ticks := 1


func _init(platform_id: String, drawn: Rect2i, toward: Vector2i, length: int, px_per_second: float, every_seconds: float) -> void:
	super(platform_id, drawn, toward, length, px_per_second, 0.0)
	every_ticks = maxi(1, roundi(every_seconds * float(TICKS_PER_SECOND)))
	life_ticks = travel_ticks
	slots = maxi(1, ceili(float(life_ticks) / float(every_ticks)))


func body_count() -> int:
	return slots


## A platform there, back to the start, once the last has gone.
func period() -> int:
	return slots * every_ticks


## How many ticks into its trip slot `body` is at `tick`, or -1 when it is not out.
func age_at(tick: int, body: int) -> int:
	var age := posmod(tick - body * every_ticks, period())
	return age if age < life_ticks else -1


func alive_at(tick: int, body := 0) -> bool:
	return age_at(tick, body) >= 0


func continuous_at(tick: int, body := 0) -> bool:
	var age := age_at(tick, body)
	return age >= 0 and age_at(tick + 1, body) == age + 1


func rect_at(tick: int, body := 0) -> Rect2:
	var rect := Grid.cell_rect(start_cells)
	var age := maxi(0, age_at(tick, body))
	rect.position += Vector2(direction) * distance() * float(age) / float(travel_ticks)
	return rect


## The tick a platform in slot `body` is first out at or after `tick`.
func next_spawn(tick: int, body: int) -> int:
	var age := posmod(tick - body * every_ticks, period())
	return tick if age == 0 else tick + period() - age
