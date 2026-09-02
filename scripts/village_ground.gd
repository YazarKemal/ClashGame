extends Node2D

## Draws a simple 40x40 village grid (square tile grid) centered on the
## origin, plus a border to mark the playable village boundary.

const GRID_SIZE := 40
const TILE_SIZE := 32.0

const EDGE_COLOR := Color(0.25, 0.5, 0.9, 1.0)
const TILE_LINE_COLOR := Color(0.9, 0.9, 0.9, 0.12)
const FILL_COLOR := Color(0.35, 0.55, 0.3, 0.35)

var grid_rect := Rect2(-(GRID_SIZE * TILE_SIZE) / 2.0,
		-(GRID_SIZE * TILE_SIZE) / 2.0,
		GRID_SIZE * TILE_SIZE,
		GRID_SIZE * TILE_SIZE)

func _draw() -> void:
	draw_rect(grid_rect, FILL_COLOR, true)

	# Interior tile lines.
	for i in range(GRID_SIZE + 1):
		var x := grid_rect.position.x + i * TILE_SIZE
		draw_line(Vector2(x, grid_rect.position.y),
				Vector2(x, grid_rect.end.y), TILE_LINE_COLOR, 1.0)
	for j in range(GRID_SIZE + 1):
		var y := grid_rect.position.y + j * TILE_SIZE
		draw_line(Vector2(grid_rect.position.x, y),
				Vector2(grid_rect.end.x, y), TILE_LINE_COLOR, 1.0)

	# Village boundary border.
	draw_rect(grid_rect, EDGE_COLOR, false, 3.0)
