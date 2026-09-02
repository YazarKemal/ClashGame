extends Node2D
class_name BuildingManager

## Tracks occupied grid cells and drives the building placement flow.

signal placement_started
signal placement_ended(success: bool)

const BUILDING_SCENE: PackedScene = preload("res://scenes/building.tscn")
const UNIT_SCENE: PackedScene = preload("res://scenes/unit.tscn")

var occupied: Dictionary = {}  # Vector2i -> true

var placing := false
var spawn_mode := false
var _preview: Building = null
var _preview_cell := Vector2i.ZERO

func is_cell_free(c: Vector2i) -> bool:
	return not occupied.has(c)

## True if an NxN footprint with top-left `cell` fits on the map and all of
## its cells are free.
func can_place_at(cell_top_left: Vector2i, grid_size: int) -> bool:
	for dx in range(grid_size):
		for dy in range(grid_size):
			var c := cell_top_left + Vector2i(dx, dy)
			if c.x < 0 or c.y < 0 \
					or c.x >= GridConfig.GRID_SIZE or c.y >= GridConfig.GRID_SIZE:
				return false
			if occupied.has(c):
				return false
	return true

func start_placement(building_type: Building.Type) -> void:
	if placing:
		cancel_placement()
	spawn_mode = false
	var b: Building = BUILDING_SCENE.instantiate()
	b.building_type = building_type
	b.destroyed.connect(_on_building_destroyed)
	add_child(b)
	_preview = b
	_preview_cell = GridConfig.world_to_cell(get_global_mouse_position())
	placing = true
	_apply_preview_validity()
	placement_started.emit()

func set_spawn_mode(on: bool) -> void:
	spawn_mode = on

func confirm_placement() -> bool:
	if not placing or _preview == null:
		return false
	if not can_place_at(_preview_cell, _preview.grid_size):
		return false
	# Never confirm unless the player can afford the building's cost.
	if not GameManager.spend_resources(_preview.gold_cost(), _preview.elixir_cost()):
		return false
	_place_preview()
	placing = false
	_preview = null
	placement_ended.emit(true)
	return true

func cancel_placement() -> void:
	if not placing:
		return
	_preview.queue_free()
	_preview = null
	placing = false
	placement_ended.emit(false)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if spawn_mode and not placing:
		if event is InputEventScreenTouch and event.pressed:
			_spawn_unit_at(event.position)
		return
	if not placing or _preview == null:
		return
	# Only move the preview from real map touches/drags, never from UI presses.
	if event is InputEventScreenDrag:
		_move_preview_to(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		_move_preview_to(event.position)

func _spawn_unit_at(screen_pos: Vector2) -> void:
	var world := get_global_transform_with_canvas().affine_inverse() * screen_pos
	var u: Node2D = UNIT_SCENE.instantiate()
	u.position = world
	add_child(u)

func _on_building_destroyed(cells: Array) -> void:
	for c in cells:
		occupied.erase(c)

func _move_preview_to(screen_pos: Vector2) -> void:
	# Convert the viewport/screen point into world space (accounts for the
	# camera pan/zoom) before snapping to a grid cell.
	var world := get_global_transform_with_canvas().affine_inverse() * screen_pos
	var cell := GridConfig.world_to_cell(world)
	if cell != _preview_cell:
		_preview_cell = cell
		_apply_preview_validity()

func _apply_preview_validity() -> void:
	if _preview == null:
		return
	_preview.set_preview(_preview_cell, can_place_at(_preview_cell, _preview.grid_size))

func _place_preview() -> void:
	var b := _preview
	b.place_at(_preview_cell)
	for c in b.cells:
		occupied[c] = true
