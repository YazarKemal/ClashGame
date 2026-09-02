extends Node2D
class_name Building

enum State { PREVIEW, PLACED }

const VALID_COLOR := Color(0.3, 0.9, 0.3, 0.75)
const INVALID_COLOR := Color(0.9, 0.3, 0.3, 0.75)

## Occupied footprint size in grid cells (N x N).
@export var grid_size := 2
## Display name shown on the building.
@export var building_name := "Building"

var state := State.PLACED
var cell := Vector2i.ZERO

var _base_color := Color(0.55, 0.6, 0.7, 1.0)

@onready var _body: Polygon2D = $Body
@onready var _label: Label = $Label

func _ready() -> void:
	_label.text = building_name
	_build_footprint()
	_apply_state()

## Builds the footprint polygon and label layout from grid_size.
func _build_footprint() -> void:
	var size := grid_size * GridConfig.TILE_SIZE
	var half := size * 0.5
	_body.polygon = PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	])
	_label.position = Vector2(-half, -half)
	_label.size = Vector2(size, size)

func _apply_state() -> void:
	_body.color = _base_color
	modulate.a = 1.0 if state == State.PLACED else 0.7

## Sets the preview footprint centered on cell (top-left) and tints it
## green when valid, red when not.
func set_preview(c: Vector2i, valid: bool) -> void:
	state = State.PREVIEW
	position = _cell_center(c)
	_body.color = VALID_COLOR if valid else INVALID_COLOR
	modulate.a = 0.7

## Locks the building onto cell (top-left) and marks it built.
func place_at(c: Vector2i) -> void:
	cell = c
	state = State.PLACED
	position = _cell_center(c)
	_apply_state()

func _cell_center(c: Vector2i) -> Vector2:
	return GridConfig.cell_to_world(c.x, c.y) \
			+ Vector2(grid_size * GridConfig.TILE_SIZE, grid_size * GridConfig.TILE_SIZE) * 0.5
