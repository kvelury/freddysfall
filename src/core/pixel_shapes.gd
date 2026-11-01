class_name PixelShapes
extends RefCounted

## The shapes that used to be polygons, as the pixels they lit at 320 x 180.
## Each has the offset of its top-left pixel from its anchor (a cell's top-left
## for spikes, the centre for the diamonds). Made by `tools/pixel_check.sh
## --shapes` on the code that drew them as polygons.

const SHAPES := {
	"spikes_up": {
		"offset": Vector2i(0, 3),
		"rows": [
			"..#....#..",
			"..#....#..",
			"..#....#..",
			".###..###.",
			".###..###.",
			".###..###.",
			"##########",
		],
	},
	"spikes_down": {
		"offset": Vector2i(0, 0),
		"rows": [
			"##########",
			".###..###.",
			".###..###.",
			".###..###.",
			"..#....#..",
			"..#....#..",
			"..#....#..",
		],
	},
	"spikes_left": {
		"offset": Vector2i(3, 0),
		"rows": [
			"......#",
			"...####",
			"#######",
			"...####",
			"......#",
			"......#",
			"...####",
			"#######",
			"...####",
			"......#",
		],
	},
	"spikes_right": {
		"offset": Vector2i(0, 0),
		"rows": [
			"#......",
			"####...",
			"#######",
			"####...",
			"#......",
			"#......",
			"####...",
			"#######",
			"####...",
			"#......",
		],
	},
	"token": {
		"offset": Vector2i(-4, -4),
		"rows": [
			"...#...",
			"..###..",
			".#####.",
			"#######",
			"#######",
			".#####.",
			"..###..",
			"...#...",
		],
	},
	"flying_token": {
		"offset": Vector2i(-6, -6),
		"rows": [
			".....#.....",
			"....###....",
			"...#####...",
			"..#######..",
			".#########.",
			"###########",
			"###########",
			".#########.",
			"..#######..",
			"...#####...",
			"....###....",
			".....#.....",
		],
	},
	"slot": {
		"offset": Vector2i(-4, -4),
		"rows": [
			"...##...",
			"..#..#..",
			".#....#.",
			"#......#",
			"#......#",
			".#....#.",
			"..#..#..",
			"...##...",
		],
	},
	# The HUD's hearts (UI units, top-left at the anchor): a full one and the
	# same outline hollow.
	"hud_heart": {
		"offset": Vector2i(0, 0),
		"rows": [
			".##.##.",
			"#######",
			"#######",
			".#####.",
			"..###..",
			"...#...",
		],
	},
	"hud_heart_empty": {
		"offset": Vector2i(0, 0),
		"rows": [
			".##.##.",
			"#..#..#",
			"#.....#",
			".#...#.",
			"..#.#..",
			"...#...",
		],
	},
	# A held token in the HUD: a small solid 5x5 diamond, centred on the anchor.
	"hud_token": {
		"offset": Vector2i(-2, -2),
		"rows": [
			"..#..",
			".###.",
			"#####",
			".###.",
			"..#..",
		],
	},
}
