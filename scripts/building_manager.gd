extends Node2D
class_name BuildingManager

## Tracks occupied grid cells and drives the building placement flow.

signal placement_started
signal placement_ended(success: bool)
signal building_selected(building: Building)
signal unit_spawned

const BUILDING_SCENE: PackedScene = preload("res://scenes/building.tscn")
const UNIT_SCENE: PackedScene = preload("res://scenes/unit.tscn")

var occupied: Dictionary = {}  # Vector2i -> true

const SELECT_TAP_DIST := 15.0

var placing := false
var spawn_mode := false
var selected_unit_type := Unit.Type.BARBARIAN

## When true, troops can only be deployed on the outer ring of grid cells
## (used in raid mode so attackers start at the village boundary).
var deploy_only_on_border := false
var _preview: Building = null
var _preview_cell := Vector2i.ZERO
var _selected: Building = null

# Tap detection: the press screen position, compared to the release position.
var _press_screen := Vector2.ZERO

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
	SaveManager.save_game(self)
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
			_spawn_unit_at()
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

## A release within SELECT_TAP_DIST of the press is a tap (select); anything
## larger was a pan, so it selects nothing. Tolerates tiny drag jitter.
func _handle_selection_tap(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			_press_screen = event.position
		elif event.position.distance_to(_press_screen) <= SELECT_TAP_DIST:
			print("Dokunulan Dünya Konumu: ", get_global_mouse_position())
			_select_at()

## Converts the global mouse/world position to a grid cell and selects the
## building that owns it (or clears the selection on empty ground).
func _select_at() -> void:
	var cell := GridConfig.world_to_cell(get_global_mouse_position())
	var found: Building = _building_at_cell(cell)
	if found != null:
		print("Bina Seçildi: ", found.building_name)
		_set_selected(found)
	else:
		_set_selected(null)

## Returns the placed building that owns the given grid cell, if any.
func _building_at_cell(cell: Vector2i) -> Building:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Building and b.state == Building.State.PLACED and cell in b.cells:
			return b
	return null

func _set_selected(b: Building) -> void:
	if _selected != null and is_instance_valid(_selected):
		if _selected.destroyed.is_connected(_on_selected_destroyed):
			_selected.destroyed.disconnect(_on_selected_destroyed)
		_selected.set_selected(false)
	_selected = b
	if b != null:
		if not b.destroyed.is_connected(_on_selected_destroyed):
			b.destroyed.connect(_on_selected_destroyed)
		b.set_selected(true)
	building_selected.emit(b)

## Auto-deselect when the currently selected building is destroyed by a unit.
func _on_selected_destroyed(_cells: Array) -> void:
	_set_selected(null)

## Deploys the currently selected troop at the tap point, consuming it from the
## trained army (nothing spawns when none of that troop type are ready).
func _spawn_unit_at() -> void:
	if deploy_only_on_border and not _is_border_cell(
			GridConfig.world_to_cell(get_global_mouse_position())):
		print("Asker sadece harita sınırlarına bırakılabilir.")
		return
	if not GameManager.consume_troop(selected_unit_type):
		print("Bu birimden hazır asker yok.")
		return
	var u: Unit = UNIT_SCENE.instantiate()
	u.unit_type = selected_unit_type
	u.position = get_global_mouse_position()
	add_child(u)
	unit_spawned.emit()

## True when the cell lies on the outer edge of the village grid.
func _is_border_cell(c: Vector2i) -> bool:
	return c.x == 0 or c.y == 0 \
			or c.x == GridConfig.GRID_SIZE - 1 or c.y == GridConfig.GRID_SIZE - 1

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
