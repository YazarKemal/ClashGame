class_name GridConfig
## Shared village grid constants and world<->cell helpers.

const GRID_SIZE := 40
const TILE_SIZE := 32.0

# World-space rect of the whole grid, centered on the origin.
const GRID_RECT := Rect2(-(GRID_SIZE * TILE_SIZE) / 2.0,
		-(GRID_SIZE * TILE_SIZE) / 2.0,
		GRID_SIZE * TILE_SIZE,
		GRID_SIZE * TILE_SIZE)

## World position of a cell's top-left corner.
static func cell_to_world(gx: int, gy: int) -> Vector2:
	return Vector2(GRID_RECT.position.x + gx * TILE_SIZE,
			GRID_RECT.position.y + gy * TILE_SIZE)

## Grid cell containing a world point.
static func world_to_cell(world: Vector2) -> Vector2i:
	var gx := int(floor((world.x - GRID_RECT.position.x) / TILE_SIZE))
	var gy := int(floor((world.y - GRID_RECT.position.y) / TILE_SIZE))
	return Vector2i(gx, gy)
