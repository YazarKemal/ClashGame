extends Camera2D

## Mobile touch camera: single-finger pan and two-finger pinch-to-zoom.
##
## - Pan and pinch are disabled while placement or spawn mode is active
##   (queried from the BuildingManager), so map gestures never fight the
##   building preview or unit deployment.
## - Touches over UI controls never reach this script because those controls
##   use mouse_filter STOP, which consumes the input first.
## - The camera position is clamped so the village grid stays mostly in view.

const MIN_ZOOM := 0.6
const MAX_ZOOM := 2.0

# Village grid extent (matches the ground node's 40x40 area).
const GRID_SIZE := 40
const TILE_SIZE := 32.0
const GRID_RECT := Rect2(-(GRID_SIZE * TILE_SIZE) / 2.0,
		-(GRID_SIZE * TILE_SIZE) / 2.0,
		GRID_SIZE * TILE_SIZE,
		GRID_SIZE * TILE_SIZE)
const EDGE_MARGIN := 128.0

@export var manager_path: NodePath

var _manager: BuildingManager

# Multi-touch bookkeeping for pinch-to-zoom.
var _touches := {}  # int touch index -> Vector2 position
var _pinch_base_dist := 0.0
var _pinch_base_zoom := 0.0

# Whether the current single-finger gesture may pan; false when the press
# began over a building or a UI control.
var _pan_allowed := true

# Screen-shake bookkeeping. Shake is applied to `offset` so it never fights the
# pan/zoom-controlled `position`.
var _shake_strength := 0.0
var _shake_duration := 0.0
var _shake_time := 0.0

func _ready() -> void:
	add_to_group("camera")
	position = Vector2.ZERO
	zoom = Vector2.ONE
	limit_left = int(GRID_RECT.position.x - EDGE_MARGIN)
	limit_top = int(GRID_RECT.position.y - EDGE_MARGIN)
	limit_right = int(GRID_RECT.end.x + EDGE_MARGIN)
	limit_bottom = int(GRID_RECT.end.y + EDGE_MARGIN)
	if manager_path != NodePath():
		_manager = get_node(manager_path)

## True while a placement or spawn interaction is in progress; pan/pinch are
## suspended so they don't compete with preview or unit drops.
func _mode_locked() -> bool:
	if _manager == null:
		return false
	return _manager.placing or _manager.spawn_mode

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	# Always keep the touch map accurate, even while locked, so the state is
	# clean when a mode ends.
	if event.pressed:
		_touches[event.index] = event.position
		# A press over a building or UI must not start a camera pan, so taps
		# reach selection instead.
		if event.index == 0:
			_pan_allowed = not _touch_is_on_building(event.position)
	else:
		_touches.erase(event.index)
	_pinch_base_dist = 0.0
	_pinch_base_zoom = zoom.x

func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index in _touches:
		_touches[event.index] = event.position
	if _mode_locked():
		return
	# Two fingers down -> pinch-to-zoom; otherwise single-finger pan.
	if _touches.size() >= 2:
		_update_pinch()
	elif event.index == 0 and _pan_allowed:
		position -= event.relative / zoom.x
		_clamp_position()

## True if the pressed screen point lands on a placed building's cell.
func _touch_is_on_building(screen_pos: Vector2) -> bool:
	if _manager == null:
		return false
	var world := get_canvas_transform().affine_inverse() * screen_pos
	var cell := GridConfig.world_to_cell(world)
	return _manager.occupied.has(cell)

func _update_pinch() -> void:
	if _touches.size() < 2:
		return
	var pts: Array = _touches.values()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var d: float = a.distance_to(b)
	if _pinch_base_dist <= 0.0:
		_pinch_base_dist = d
		_pinch_base_zoom = zoom.x
		return
	# Zoom keeps the midpoint between the two fingers fixed on screen.
	var target_zoom := clampf(_pinch_base_zoom * (d / _pinch_base_dist), MIN_ZOOM, MAX_ZOOM)
	if not is_equal_approx(target_zoom, zoom.x):
		_set_zoom(target_zoom, (a + b) * 0.5)

func _set_zoom(target_zoom: float, focus_screen_pos: Vector2) -> void:
	var new_zoom := clampf(target_zoom, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, zoom.x):
		return
	# Convert the focus screen point into world space before and after the
	# zoom so the world under the focus stays fixed.
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
	return get_viewport_rect().size / zoom

## Starts a decaying screen shake for `duration` seconds. Re-triggering with a
## stronger strength raises the current amplitude (trauma-style), so collapsing
## several big buildings at once reads as one heavy rumble.
func shake(strength: float, duration: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_duration = maxf(_shake_duration, duration)
	_shake_time = 0.0

func _process(delta: float) -> void:
	# Keep limits applied as the viewport resizes or zoom changes.
	_clamp_position()
	_update_shake(delta)

## Applies a random offset that decays over the shake duration, then resets it.
func _update_shake(delta: float) -> void:
	if _shake_duration <= 0.0:
		return
	_shake_time += delta
	var t := _shake_time / _shake_duration
	if t >= 1.0:
		_shake_duration = 0.0
		offset = Vector2.ZERO
		return
	# Quadratic falloff keeps the start punchy and the tail gentle.
	var intensity := _shake_strength * (1.0 - t) * (1.0 - t)
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * intensity
