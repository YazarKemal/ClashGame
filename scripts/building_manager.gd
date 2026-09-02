extends Node2D
class_name BuildingManager

## Tracks occupied grid cells and drives the building placement flow.

signal placement_started
signal placement_ended(success: bool)
signal building_selected(building: Building)

const BUILDING_SCENE: PackedScene = preload("res://scenes/building.tscn")
const UNIT_SCENE: PackedScene = preload("res://scenes/unit.tscn")

var occupied: Dictionary = {}  # Vector2i -> true

const SELECT_TAP_DIST := 24.0

var placing := false
var spawn_mode := false
var _preview: Building = null
var _preview_cell := Vector2i.ZERO
var _selected: Building = null

# Tap detection: a press+release that barely moves is a tap, not a pan.
var _press_screen := Vector2.ZERO
var _pressing := false

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
	if placing and _preview != null:
		# Only move the preview from real map touches/drags, never from UI presses.
		if event is InputEventScreenDrag:
			_move_preview_to(event.position)
		elif event is InputEventScreenTouch and event.pressed:
			_move_preview_to(event.position)
		return
	# Idle: a tap selects a building, a tap on empty ground deselects.
	_handle_selection_tap(event)

## Distinguishes a quick tap (select) from a drag (pan) on the empty map.
func _handle_selection_tap(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			_press_screen = event.position
			_pressing = true
		else:
			if _pressing and event.position.distance_to(_press_screen) <= SELECT_TAP_DIST:
				_select_at(event.position)
			_pressing = false
	elif event is InputEventScreenDrag and event.index == 0:
		# A drag means the gesture was a pan, so it can't also be a tap.
		_pressing = false

func _select_at(screen_pos: Vector2) -> void:
	var world := get_global_transform_with_canvas().affine_inverse() * screen_pos
	var found: Building = _building_at_world(world)
	_set_selected(found)

func _building_at_world(world: Vector2) -> Building:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Building and b.state == Building.State.PLACED and b.contains_world_point(world):
			return b
	return null

func _set_selected(b: Building) -> void:
	if _selected != null and is_instance_valid(_selected) \
			and _selected.destroyed.is_connected(_on_selected_destroyed):
		_selected.destroyed.disconnect(_on_selected_destroyed)
	_selected = b
	if b != null:
		b.destroyed.connect(_on_selected_destroyed)
	building_selected.emit(b)

## Auto-deselect when the currently selected building is destroyed by a unit.
func _on_selected_destroyed(_cells: Array) -> void:
	_set_selected(null)

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
