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

# Screen-px a left-mouse drag must exceed before it pans (kept short of the
# building tap-selection distance so a click still selects).
const DRAG_THRESHOLD := 12.0

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

# Mouse panning bookkeeping. Mouse buttons are handled here explicitly (the
# scene's building code only reads touch events), mirroring the wheel-zoom and
# middle/right-drag pan behaviour added to the world map.
var _zoom_tween: Tween = null
var _mouse_drag_button := -1        # mouse button currently held for a drag
var _mouse_drag_origin := Vector2.ZERO

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
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

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
## PC mouse buttons: wheel zooms smoothly; middle/right drags pan freely; left
## drag pans empty ground (never when the press started on a building, so the
## click reaches building selection).
func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var idx := event.button_index
	if idx == MOUSE_BUTTON_WHEEL_UP:
		_zoom_around(event.position, 1.08)
		return
	if idx == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_around(event.position, 1.0 / 1.08)
		return
	if _mode_locked():
		return
	if idx == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_drag_button = idx
			_mouse_drag_origin = event.position
			_pan_allowed = not _touch_is_on_building(event.position)
		else:
			_mouse_drag_button = -1
		return
	if idx == MOUSE_BUTTON_MIDDLE or idx == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_mouse_drag_button = idx
			_pan_allowed = true
		else:
			_mouse_drag_button = -1

## Applies a held-drag pan for the active mouse button.
func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _mouse_drag_button < 0:
		return
	if _mouse_drag_button == MOUSE_BUTTON_LEFT and not _pan_allowed:
		return  # press began on a building -> let click select instead
	if _mouse_drag_button == MOUSE_BUTTON_LEFT \
			and event.position.distance_to(_mouse_drag_origin) <= DRAG_THRESHOLD:
		return  # still a potential tap
	position -= event.relative / zoom.x
	_clamp_position()

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

## Smooth mouse-wheel zoom: zoom and position both ease so the world point under
## the cursor stays anchored (the pinch path uses the instant _set_zoom above).
func _zoom_around(screen: Vector2, factor: float) -> void:
	var view := get_viewport_rect().size
	var center := view * 0.5
	var new_zoom := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, zoom.x):
		return
	var anchor := position + (screen - center) / zoom.x
	var new_pos := _clamp_for_zoom(anchor - (screen - center) / new_zoom, new_zoom)
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_parallel(true)
	_zoom_tween.tween_property(self, "zoom", Vector2(new_zoom, new_zoom), 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_property(self, "position", new_pos, 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## Clamps a camera position so the view stays within limits at `zoom_val`.
func _clamp_for_zoom(p: Vector2, zoom_val: float) -> Vector2:
	var half := get_viewport_rect().size * 0.5 / zoom_val
	return Vector2(
		clampf(p.x, limit_left + half.x, limit_right - half.x),
		clampf(p.y, limit_top + half.y, limit_bottom - half.y))

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
