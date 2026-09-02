extends Camera2D

## Mobile touch camera: single-finger pan, two-finger pinch-to-zoom.
## The village grid is a 40x40 iso area; the camera limits keep the view
## mostly inside the map bounds.

const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.5

# Village grid extent (matches the ground node's 40x40 area).
const GRID_SIZE := 40
const TILE_SIZE := 32.0
const GRID_RECT := Rect2(-(GRID_SIZE * TILE_SIZE) / 2.0,
		-(GRID_SIZE * TILE_SIZE) / 2.0,
		GRID_SIZE * TILE_SIZE,
		GRID_SIZE * TILE_SIZE)

var _panning := false
var _last_touch_pos := Vector2.ZERO
var _view_rect := Rect2()  # last known visible viewport rect (pixels)

func _ready() -> void:
	position = Vector2.ZERO
	limit_left = int(GRID_RECT.position.x - 128.0)
	limit_top = int(GRID_RECT.position.y - 128.0)
	limit_right = int(GRID_RECT.end.x + 128.0)
	limit_bottom = int(GRID_RECT.end.y + 128.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)
	elif event is InputEventMagnifyGesture:
		_handle_magnify(event)
	elif event is InputEventPanGesture:
		_handle_pan_gesture(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.index == 0:
		if event.pressed:
			_panning = true
			_last_touch_pos = event.position
		else:
			_panning = false

func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if _panning and event.index == 0:
		var delta := event.position - _last_touch_pos
		position -= delta / zoom.x
		_last_touch_pos = event.position
		_clamp_position()

func _handle_magnify(event: InputEventMagnifyGesture) -> void:
	_set_zoom(zoom.x * event.factor, event.position)

func _handle_pan_gesture(event: InputEventPanGesture) -> void:
	position -= event.delta * 40.0
	_clamp_position()

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_set_zoom(zoom.x * 1.1, get_global_mouse_position())
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_set_zoom(zoom.x / 1.1, get_global_mouse_position())
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_panning = true
			_last_touch_pos = event.position
		else:
			_panning = false

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _panning:
		var delta := event.position - _last_touch_pos
		position -= delta / zoom.x
		_last_touch_pos = event.position
		_clamp_position()

func _set_zoom(target_zoom: float, focus_screen_pos: Vector2) -> void:
	var new_zoom := clampf(target_zoom, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, zoom.x):
		return

	# Convert the focus screen point to world before and after the zoom
	# change so the world under the focus stays fixed.
	var viewport_center := get_viewport_rect().size * 0.5
	var focus_world_before := position + (focus_screen_pos - viewport_center) / zoom.x
	zoom = Vector2(new_zoom, new_zoom)
	var focus_world_after := position + (focus_screen_pos - viewport_center) / zoom.x
	position += focus_world_before - focus_world_after
	_clamp_position()

func _clamp_position() -> void:
	var half_view := _get_view_size() * 0.5
	position.x = clampf(position.x, limit_left + half_view.x, limit_right - half_view.x)
	position.y = clampf(position.y, limit_top + half_view.y, limit_bottom - half_view.y)

func _get_view_size() -> Vector2:
	if _view_rect.size != Vector2.ZERO:
		return _view_rect.size / zoom
	return get_viewport_rect().size / zoom

func _process(_delta: float) -> void:
	# Refresh the visible view size from the actual viewport each frame.
	_view_rect = get_viewport_rect()
	# Keep limits applied as the viewport resizes.
	_clamp_position()
