extends Node2D

## Draws a dashed red frame along the outer edge of the village grid, marking
## the only zone where troops may be deployed during a raid.

const LINE_COLOR := Color(0.9, 0.25, 0.25, 0.55)
const LINE_WIDTH := 4.0
const DASH_LEN := 14.0

func _ready() -> void:
	z_index = 20
	queue_redraw()

func _draw() -> void:
	var tl: Vector2 = GridConfig.GRID_RECT.position
	var size := GridConfig.GRID_SIZE * GridConfig.TILE_SIZE
	var tr := tl + Vector2(size, 0.0)
	var br := tl + Vector2(size, size)
	var bl := tl + Vector2(0.0, size)
	draw_dashed_line(tl, tr, LINE_COLOR, LINE_WIDTH, DASH_LEN)
	draw_dashed_line(tr, br, LINE_COLOR, LINE_WIDTH, DASH_LEN)
	draw_dashed_line(br, bl, LINE_COLOR, LINE_WIDTH, DASH_LEN)
	draw_dashed_line(bl, tl, LINE_COLOR, LINE_WIDTH, DASH_LEN)
