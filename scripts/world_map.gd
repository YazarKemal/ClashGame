extends Node2D

## Macro world map. The player drags a single army icon around a symbolic
## over-world between faction cities and neutral resource camps (M&B Warband
## style). Scene switching is handled elsewhere; this scene only reads/writes
## shared state on GameManager and shows UI.
##
## Interaction model:
##   - Tap empty ground  -> army walks there (click-to-move).
##   - Tap a node        -> army walks to it; on arrival the node's action runs
##                          (resource camp drip starts / faction city panel opens).
##   - Drag              -> pans the camera. Pinch (or mouse wheel) zooms.
## Neutral resource camps give passive income every few seconds while the army
## stays parked on them (AoE style). Hostile faction cities start a raid that
## reuses raid.tscn and returns here when it ends.

const WORLD_NODE_SCENE: PackedScene = preload("res://scenes/world_node.tscn")
const MAIN_SCENE := "res://scenes/main.tscn"
const RAID_SCENE := "res://scenes/raid.tscn"

## Playable land (world coordinates); the camera is clamped inside it.
const WORLD_RECT := Rect2(-700.0, -380.0, 1400.0, 760.0)
const EDGE_MARGIN := 70.0

const ARMY_SPEED := 430.0
const ARRIVE_DIST := 20.0       # distance that counts as "reached"
const NODE_TAP_RADIUS := 16.0   # extra slack for tapping a node vs ground
const CAMP_TICK := 3.0          # seconds between resource-camp payments

const MIN_ZOOM := 0.55
const MAX_ZOOM := 2.2
const DRAG_THRESHOLD := 14.0    # screen px before a press becomes a pan

const ARMY_COLOR := Color(0.16, 0.9, 0.95, 1.0)

## Static layout of the world (prototype). Mutable state (army position) lives
## on GameManager so it survives the city->raid->world round trip.
const NODE_DEFS := [
	{ "id": "home", "type": WorldNode.Type.HOME_VILLAGE, "faction": WorldNode.Faction.NEUTRAL,
		"tier": 0, "pos": Vector2(-540, 280), "radius": 46.0, "title": "Kendi Köyün" },

	{ "id": "red1", "type": WorldNode.Type.FACTION_CITY, "faction": WorldNode.Faction.RED,
		"tier": 1, "pos": Vector2(-60, -300), "radius": 44.0, "title": "Demir Karakolu" },
	{ "id": "red2", "type": WorldNode.Type.FACTION_CITY, "faction": WorldNode.Faction.RED,
		"tier": 2, "pos": Vector2(330, -300), "radius": 50.0, "title": "Kan Kalesi" },

	{ "id": "blue1", "type": WorldNode.Type.FACTION_CITY, "faction": WorldNode.Faction.BLUE,
		"tier": 0, "pos": Vector2(610, -140), "radius": 46.0, "title": "Gök Kalesi" },
	{ "id": "blue2", "type": WorldNode.Type.FACTION_CITY, "faction": WorldNode.Faction.BLUE,
		"tier": 0, "pos": Vector2(600, 250), "radius": 40.0, "title": "Ay Kulesi" },

	{ "id": "camp_gold", "type": WorldNode.Type.RESOURCE_CAMP, "faction": WorldNode.Faction.NEUTRAL,
		"tier": 0, "pos": Vector2(-330, -40), "radius": 34.0, "title": "Altın Vadi",
		"gold_reward": 70, "elixir_reward": 0, "camp_interval": CAMP_TICK },
	{ "id": "camp_elixir", "type": WorldNode.Type.RESOURCE_CAMP, "faction": WorldNode.Faction.NEUTRAL,
		"tier": 0, "pos": Vector2(150, -40), "radius": 34.0, "title": "İksir Çayırı",
		"gold_reward": 0, "elixir_reward": 60, "camp_interval": CAMP_TICK },
	{ "id": "camp_border", "type": WorldNode.Type.RESOURCE_CAMP, "faction": WorldNode.Faction.NEUTRAL,
		"tier": 0, "pos": Vector2(-60, 120), "radius": 34.0, "title": "Sınır Kampı",
		"gold_reward": 40, "elixir_reward": 40, "camp_interval": CAMP_TICK },
]

@onready var camera: Camera2D = $Camera2D
@onready var gold_label: Label = $WorldUI/TopBar/Margin/HBox/GoldLabel
@onready var elixir_label: Label = $WorldUI/TopBar/Margin/HBox/ElixirLabel
@onready var node_panel: PanelContainer = $WorldUI/NodePanel
@onready var node_title_label: Label = $WorldUI/NodePanel/Margin/VBox/NodeTitleLabel
@onready var node_detail_label: Label = $WorldUI/NodePanel/Margin/VBox/NodeDetailLabel
@onready var attack_button: Button = $WorldUI/NodePanel/Margin/VBox/ActionRow/AttackButton
@onready var close_node_button: Button = $WorldUI/NodePanel/Margin/VBox/ActionRow/CloseNodeButton

var _nodes: Dictionary = {}            # node_id -> WorldNode
var _army_body: Polygon2D = null       # visual for the army icon
var _army_pos := Vector2.ZERO          # world position of the army

var _selected_node: WorldNode = null   # node with the selection ring
var _travel_target := Vector2.ZERO     # where the army is heading
var _arrival_node: WorldNode = null    # node to act on once reached
var _moving := false
var _active_camp: WorldNode = null     # camp currently paying income
var _camp_timer: Timer = null

# Camera / tap-vs-pan bookkeeping (single-finger and mouse share these flags).
var _touches := {}                     # touch index -> screen pos
var _tap_armed := false
var _tap_screen := Vector2.ZERO
var _pan_active := false
var _pinch_base_dist := 0.0
var _pinch_base_zoom := 1.0
var _zoom_tween: Tween = null   # smooth zoom/pan ease for the mouse wheel

func _ready() -> void:
	GameManager.in_raid = false
	_update_resources(GameManager.gold, GameManager.elixir)
	GameManager.resource_changed.connect(_update_resources)
	attack_button.pressed.connect(_on_attack_pressed)
	close_node_button.pressed.connect(_hide_node_panel)
	$WorldUI/ReturnButton.pressed.connect(_return_village)

	# Node visuals first, then the army so the army renders above them.
	_build_nodes()
	_build_army()

	# First time on the map: start the army at home.
	if GameManager.world_army_pos == Vector2.ZERO:
		GameManager.world_army_pos = _nodes["home"].position
	_army_pos = GameManager.world_army_pos
	_travel_target = _army_pos
	_place_army()

	camera.position = _army_pos
	camera.limit_left = int(WORLD_RECT.position.x - EDGE_MARGIN)
	camera.limit_top = int(WORLD_RECT.position.y - EDGE_MARGIN)
	camera.limit_right = int(WORLD_RECT.end.x + EDGE_MARGIN)
	camera.limit_bottom = int(WORLD_RECT.end.y + EDGE_MARGIN)
	_clamp_camera()

	_camp_timer = Timer.new()
	_camp_timer.wait_time = CAMP_TICK
	_camp_timer.autostart = true
	add_child(_camp_timer)
	_camp_timer.timeout.connect(_tick_camp_income)

	FxManager.popup_notice("Sefer Haritası — ordunu bir noktaya yönlendir.", 2.0)

## Soft green field for the playable land plus a boundary frame.
func _draw() -> void:
	draw_rect(WORLD_RECT, Color(0.18, 0.3, 0.16, 1.0), true)
	# Faint grid so distance/panning reads at a glance.
	for x in range(int(WORLD_RECT.position.x), int(WORLD_RECT.end.x) + 1, 100):
		draw_line(Vector2(x, WORLD_RECT.position.y),
				Vector2(x, WORLD_RECT.end.y), Color(0.9, 0.9, 0.9, 0.05), 1.0)
	for y in range(int(WORLD_RECT.position.y), int(WORLD_RECT.end.y) + 1, 100):
		draw_line(Vector2(WORLD_RECT.position.x, y),
				Vector2(WORLD_RECT.end.x, y), Color(0.9, 0.9, 0.9, 0.05), 1.0)
	draw_rect(WORLD_RECT, Color(0.85, 0.9, 0.85, 0.6), false, 4.0)

# --- Building the scene -------------------------------------------------------

func _build_nodes() -> void:
	for def in NODE_DEFS:
		var n: WorldNode = WORLD_NODE_SCENE.instantiate()
		n.setup(def)   # before add_child so _ready renders with the final values
		add_child(n)
		_nodes[n.node_id] = n

func _build_army() -> void:
	_army_body = Polygon2D.new()
	_army_body.polygon = _circle(16.0, 20)
	_army_body.color = ARMY_COLOR
	_army_body.z_index = 40
	add_child(_army_body)
	var outline := Line2D.new()
	outline.closed = true
	outline.width = 2.5
	outline.default_color = Color(0, 0, 0, 0.8)
	outline.points = _circle_points(16.0, 20)
	outline.z_index = 41
	_army_body.add_child(outline)   # parented so it travels with the army

func _place_army() -> void:
	_army_body.position = _army_pos

# --- Movement -----------------------------------------------------------------

func _process(delta: float) -> void:
	var to_target := _travel_target - _army_pos
	if to_target.length() > ARRIVE_DIST:
		_moving = true
		_army_pos += to_target.normalized() * ARMY_SPEED * delta
		GameManager.world_army_pos = _army_pos
		_place_army()
	else:
		_army_pos = _travel_target
		GameManager.world_army_pos = _army_pos
		_place_army()
		if _moving:
			_moving = false
			var node := _arrival_node
			_arrival_node = null
			if node != null:
				_on_arrive(node)

func _move_to(world: Vector2) -> void:
	_hide_node_panel()
	_travel_target = world
	_arrival_node = null
	_moving = true

func _send_to_node(node: WorldNode) -> void:
	_hide_node_panel()
	_select_node(node)
	_travel_target = node.position
	_arrival_node = node
	_moving = true

func _select_node(node: WorldNode) -> void:
	if _selected_node == node:
		return
	if _selected_node != null:
		_selected_node.set_selected(false)
	_selected_node = node
	if node != null:
		node.set_selected(true)

# --- Arrival & interactions ---------------------------------------------------

func _on_arrive(node: WorldNode) -> void:
	if node.type == WorldNode.Type.RESOURCE_CAMP:
		# Passive income is handled by _tick_camp_income while we stay here.
		FxManager.popup_notice("%s — kampa yerleşildi, pasif gelir başladı." % node.title, 1.6)
	elif node.type == WorldNode.Type.FACTION_CITY:
		if node.faction == WorldNode.Faction.RED:
			_open_city_panel(node)
		else:
			FxManager.popup_notice("%s — müttefik şehri. Buraya saldıramazsın." % node.title, 2.0)

func _tick_camp_income() -> void:
	var camp := _camp_under_army()
	if _active_camp != null and _active_camp != camp:
		_active_camp.set_claimed(false)
	_active_camp = camp
	if camp == null:
		return
	camp.set_claimed(true)
	if camp.gold_reward > 0 or camp.elixir_reward > 0:
		GameManager.add_resources(camp.gold_reward, camp.elixir_reward)
		FxManager.float_text(camp.position + Vector2(0, -camp.radius - 8),
				"+%d G  +%d İ" % [camp.gold_reward, camp.elixir_reward],
				Color(1.0, 0.85, 0.2, 1.0))

func _camp_under_army() -> WorldNode:
	var best: WorldNode = null
	var best_d: float = INF
	for n in get_tree().get_nodes_in_group("world_nodes"):
		if n is WorldNode:
			var wn: WorldNode = n
			if wn.type == WorldNode.Type.RESOURCE_CAMP:
				var d: float = _army_pos.distance_to(wn.position)
				if d <= wn.radius + 30.0 and d < best_d:
					best = wn
					best_d = d
	return best

func _open_city_panel(node: WorldNode) -> void:
	_select_node(node)
	node_title_label.text = "%s  (Sv. %d)" % [node.title, node.tier]
	node_detail_label.text = _node_detail(node)
	attack_button.visible = node.faction == WorldNode.Faction.RED
	node_panel.show()

func _node_detail(node: WorldNode) -> String:
	if node.faction == WorldNode.Faction.RED:
		return "Kızıl Kabile kalesi. Güçlü savunması var — ordunu hazırlamışsan saldır."
	if node.faction == WorldNode.Faction.BLUE:
		return "Mavi Krallık müttefik şehri. Şimdilik saldırı yok."
	return "Tarafsız bölge."

func _hide_node_panel() -> void:
	node_panel.hide()

## Starts a world-city raid: points raid.tscn at a non-campaign layout and tells
## it to return to this map when the battle ends.
func _on_attack_pressed() -> void:
	var city := _selected_node
	if city == null or city.faction != WorldNode.Faction.RED:
		_hide_node_panel()
		return
	# For the prototype, reuse a campaign level template as the city's defences.
	# (A dedicated per-city layout can replace this later.)
	var tier := clampi(city.tier, 1, RaidManager.level_count())
	GameManager.raid_is_campaign = false
	GameManager.raid_layout = RaidManager.level_data(tier)
	GameManager.raid_return_scene = "res://scenes/world_map.tscn"
	get_tree().change_scene_to_file(RAID_SCENE)

## Persists current resources then returns to the player's own village.
func _return_village() -> void:
	SaveManager.save_resources_only()
	GameManager.raid_is_campaign = true
	GameManager.raid_return_scene = MAIN_SCENE
	get_tree().change_scene_to_file(MAIN_SCENE)

func _update_resources(gold: int, elixir: int) -> void:
	gold_label.text = "Altın: %d" % gold
	elixir_label.text = "İksir: %d" % elixir

# --- Input: taps move the army, drags pan, pinch/wheel zoom -------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_touch_drag(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	# Reset the pinch baseline on every press/release so a fresh pinch recomputes
	# its starting finger distance instead of reusing a stale one.
	_pinch_base_dist = 0.0
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_arm_tap(event.position)
		else:
			_disarm_tap()  # a second finger means pinch, not a move
	else:
		_touches.erase(event.index)
		if _touches.size() == 0 and _tap_armed:
			_fire_tap(_tap_screen)
			_disarm_tap()
		if _touches.size() < 2:
			_pan_active = false

func _handle_touch_drag(event: InputEventScreenDrag) -> void:
	if event.index in _touches:
		_touches[event.index] = event.position
	if _touches.size() >= 2:
		_update_pinch()
		_pan_active = false
		return
	if _tap_armed and event.index == 0 \
			and event.position.distance_to(_tap_screen) > DRAG_THRESHOLD:
		_tap_armed = false
		_pan_active = true
	if _pan_active and event.index == 0:
		camera.position -= event.relative / camera.zoom.x
		_clamp_camera()

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var idx := event.button_index
	# Wheel zooms smoothly toward/away from the point under the cursor.
	if idx == MOUSE_BUTTON_WHEEL_UP:
		_zoom_around(event.position, 1.08)
		return
	if idx == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_around(event.position, 1.0 / 1.08)
		return
	if idx == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_arm_tap(event.position)
		else:
			if _tap_armed:
				_fire_tap(_tap_screen)
			_disarm_tap()
			_pan_active = false
		return
	# Middle/right drag = free pan (never moves the army).
	if idx == MOUSE_BUTTON_MIDDLE or idx == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_disarm_tap()
			_pan_active = true
		else:
			_pan_active = false

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	# _pan_active is already set by a middle/right press; a left press only turns
	# into a pan once the cursor drags past the threshold (otherwise it is a tap).
	if not _pan_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and _tap_armed \
			and event.position.distance_to(_tap_screen) > DRAG_THRESHOLD:
		_tap_armed = false
		_pan_active = true
	if _pan_active:
		camera.position -= event.relative / camera.zoom.x
		_clamp_camera()

func _arm_tap(screen: Vector2) -> void:
	_tap_armed = true
	_tap_screen = screen
	_pan_active = false

func _disarm_tap() -> void:
	_tap_armed = false

func _fire_tap(screen: Vector2) -> void:
	var world := _screen_to_world(screen)
	var node := _node_at(world)
	if node != null:
		_send_to_node(node)
	else:
		_select_node(null)
		_move_to(world)

func _node_at(world: Vector2) -> WorldNode:
	var best: WorldNode = null
	var best_d: float = INF
	for n in get_tree().get_nodes_in_group("world_nodes"):
		if n is WorldNode:
			var wn: WorldNode = n
			var d: float = wn.position.distance_to(world)
			var reach: float = wn.radius + NODE_TAP_RADIUS
			if d <= reach and d < best_d:
				best = wn
				best_d = d
	return best

# --- Camera helpers -----------------------------------------------------------

func _update_pinch() -> void:
	if _touches.size() < 2:
		return
	var pts: Array = _touches.values()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var d: float = a.distance_to(b)
	if _pinch_base_dist <= 0.0:
		_pinch_base_dist = d
		_pinch_base_zoom = camera.zoom.x
		return
	_set_zoom(_pinch_base_zoom * (d / _pinch_base_dist), (a + b) * 0.5)

func _set_zoom(target: float, focus_screen: Vector2) -> void:
	var new_zoom := clampf(target, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, camera.zoom.x):
		return
	var view := get_viewport().get_visible_rect().size
	var focus_before := camera.position + (focus_screen - view * 0.5) / camera.zoom.x
	camera.zoom = Vector2(new_zoom, new_zoom)
	var focus_after := camera.position + (focus_screen - view * 0.5) / camera.zoom.x
	camera.position += focus_before - focus_after
	_pinch_base_zoom = new_zoom
	_clamp_camera()

## Smoothly zooms around the given screen point: zoom and camera position both
## ease so the world point under the cursor stays anchored (used by the wheel).
func _zoom_around(screen: Vector2, factor: float) -> void:
	var view := get_viewport().get_visible_rect().size
	var new_zoom := clampf(camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, camera.zoom.x):
		return
	# World point currently under the cursor at the old zoom.
	var anchor := camera.position + (screen - view * 0.5) / camera.zoom.x
	# Camera position that keeps that world point under the cursor at new_zoom.
	var new_pos := _clamp_to_limits(
			anchor - (screen - view * 0.5) / new_zoom, new_zoom)
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_parallel(true)
	_zoom_tween.tween_property(camera, "zoom", Vector2(new_zoom, new_zoom), 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_property(camera, "position", new_pos, 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pinch_base_zoom = new_zoom

## Clamps a camera position so the view stays inside the world limits at `zoom`.
func _clamp_to_limits(p: Vector2, zoom: float) -> Vector2:
	var view := get_viewport().get_visible_rect().size
	var half := view * 0.5 / zoom
	return Vector2(
		clampf(p.x, camera.limit_left + half.x, camera.limit_right - half.x),
		clampf(p.y, camera.limit_top + half.y, camera.limit_bottom - half.y))

func _clamp_camera() -> void:
	var half := get_viewport().get_visible_rect().size * 0.5 / camera.zoom.x
	camera.position.x = clampf(camera.position.x,
			camera.limit_left + half.x, camera.limit_right - half.x)
	camera.position.y = clampf(camera.position.y,
			camera.limit_top + half.y, camera.limit_bottom - half.y)

func _screen_to_world(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen

func _circle(radius: float, segments: int) -> PackedVector2Array:
	return _circle_points(radius, segments)

func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * i / segments
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts
