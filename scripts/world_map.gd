extends Node2D

## Macro world map (WORLD -> REGION -> POI). Reads the static, designer-authored
## world from the WorldData autoload and renders it as a pannable/zoomable map:
## Regions are soft rectangles coloured by their owner; Points of Interest are
## coloured markers inside a region. Per-player discovery state lives on
## GameManager. D2 makes Stronghold POIs (in CONTESTED regions) the first playable
## activity: SALDIR launches a raid (reusing raid.tscn) and, on a win, the keep is
## marked subdued and its region reads as secured. Other POI activities remain
## previews only.
##
## Interaction model (Desktop + Mobile):
##   - Tap a region  -> reveals it (discovery) and shows its info panel.
##   - Tap a POI     -> shows its info panel (type / owner / state / action).
##   - Tap empty     -> clears the selection.
##   - Drag          -> pans. Pinch (or wheel) zooms.
##
## This scene reuses the previous map's camera/pan/zoom code verbatim; only the
## object layer was swapped from a roaming army over freeform nodes to a typed,
## data-driven region/POI structure.

const MAIN_SCENE := "res://scenes/main.tscn"
const WORLD_SCENE := "res://scenes/world_map.tscn"
const RAID_SCENE := "res://scenes/raid.tscn"

## Playable land (world coordinates); the camera is clamped inside it.
const WORLD_RECT := Rect2(-700.0, -380.0, 1400.0, 760.0)
const EDGE_MARGIN := 70.0

const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.2
const DRAG_THRESHOLD := 14.0   # screen px before a press becomes a pan

const POI_RADIUS := 15.0       # marker radius for a non-home POI
const HOME_POI_RADIUS := 22.0  # marker radius for a HOME village POI
const POI_TAP_SLACK := 9.0     # extra slack for tapping a POI marker

const COLOR_DISCOVERED_BG := Color(0.05, 0.06, 0.09, 0.5)
const COLOR_LOCKED := Color(0.10, 0.11, 0.13, 0.92)
const COLOR_LOCKED_OUTLINE := Color(0.34, 0.37, 0.40, 0.9)
const COLOR_SELECT := Color(1, 1, 1, 0.95)

## A campaign level reused as a Stronghold keep's garrison (pre-authored, tested).
const STRONGHOLD_LEVEL := 2

## D2 consequence colours: a conquered keep / secured region reads player-green;
## the next attackable keep is framed by a gold objective ring.
const COLOR_SUBDUED := Color(0.3, 0.85, 0.5, 1.0)
const COLOR_OBJECTIVE := Color(1.0, 0.92, 0.45, 1.0)

@onready var camera: Camera2D = $Camera2D
@onready var gold_label: Label = $WorldUI/TopBar/Margin/HBox/GoldLabel
@onready var elixir_label: Label = $WorldUI/TopBar/Margin/HBox/ElixirLabel
@onready var hint_label: Label = $WorldUI/HintLabel
@onready var node_panel: PanelContainer = $WorldUI/NodePanel
@onready var node_title_label: Label = $WorldUI/NodePanel/Margin/VBox/NodeTitleLabel
@onready var node_detail_label: Label = $WorldUI/NodePanel/Margin/VBox/NodeDetailLabel
@onready var attack_button: Button = $WorldUI/NodePanel/Margin/VBox/ActionRow/AttackButton
@onready var close_node_button: Button = $WorldUI/NodePanel/Margin/VBox/ActionRow/CloseNodeButton

var _selected_poi: POIDef = null        # POI shown in the panel (over region)
var _selected_region: RegionDef = null  # region shown in the panel (no POI)

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
	# The attack action row only appears for Stronghold POIs (set per panel).
	attack_button.visible = false
	attack_button.pressed.connect(_launch_stronghold_raid)
	close_node_button.pressed.connect(_hide_node_panel)
	$WorldUI/ReturnButton.pressed.connect(_return_village)
	_refresh_hint()

	camera.limit_left = int(WORLD_RECT.position.x - EDGE_MARGIN)
	camera.limit_top = int(WORLD_RECT.position.y - EDGE_MARGIN)
	camera.limit_right = int(WORLD_RECT.end.x + EDGE_MARGIN)
	camera.limit_bottom = int(WORLD_RECT.end.y + EDGE_MARGIN)

	# Open the map centred on the player's home region (its Kingdom start).
	var home = WorldData.starting_region_for(GameManager.kingdom_id)
	camera.position = home.center if home != null else Vector2.ZERO
	_clamp_camera()

	queue_redraw()

func _kingdom_id() -> String:
	return GameManager.kingdom_id

func _region_discovered(r: RegionDef) -> bool:
	return GameManager.region_discovered(r.id)

func _region_visible(r: RegionDef) -> bool:
	# Own Kingdom's regions are known from the start; foreign/neutral land only
	# becomes visible once the player has tapped (discovered) it.
	return _region_discovered(r)

func _poi_visible(p: POIDef) -> bool:
	var r := WorldData.region(p.region_id)
	return r != null and _region_visible(r)

# --- Drawing -------------------------------------------------------------------

func _draw() -> void:
	draw_rect(WORLD_RECT, Color(0.15, 0.24, 0.15, 1.0), true)
	# Faint grid so distance/panning reads at a glance.
	for x in range(int(WORLD_RECT.position.x), int(WORLD_RECT.end.x) + 1, 100):
		draw_line(Vector2(x, WORLD_RECT.position.y),
				Vector2(x, WORLD_RECT.end.y), Color(0.9, 0.9, 0.9, 0.05), 1.0)
	for y in range(int(WORLD_RECT.position.y), int(WORLD_RECT.end.y) + 1, 100):
		draw_line(Vector2(WORLD_RECT.position.x, y),
				Vector2(WORLD_RECT.end.x, y), Color(0.9, 0.9, 0.9, 0.05), 1.0)

	var own := _kingdom_id()
	for r in WorldData.region_defs():
		_draw_region(r, own)

	for p in WorldData.poi_defs():
		if _poi_visible(p):
			_draw_poi(p)

	# Objective pulse: frames the next attackable stronghold so the first conquest
	# is discoverable even before the player learns to look for keeps.
	var objective := _objective_stronghold()
	if objective != null:
		_draw_circle_ring(objective.position, HOME_POI_RADIUS + 6.0, COLOR_OBJECTIVE)

	# Selection highlight drawn on top.
	if _selected_poi != null:
		_draw_circle_ring(_selected_poi.position, HOME_POI_RADIUS + 6.0)
	elif _selected_region != null:
		_draw_region_ring(_selected_region)

func _draw_region(r: RegionDef, own: String) -> void:
	var visible := _region_visible(r)
	var rect := _region_rect(r)
	if visible:
		var c: Color = WorldData.owner_color_for_region(r)
		var bg := Color(c.r, c.g, c.b, 0.32)
		draw_rect(rect, bg, true)
		draw_rect(rect, c, false, 3.0)
		var txt := Color(c.r, c.g, c.b, 1.0).lightened(0.35)
		_draw_center_text(rect.get_center(), r.display_name, 16, txt)
	else:
		draw_rect(rect, COLOR_LOCKED, true)
		draw_rect(rect, COLOR_LOCKED_OUTLINE, false, 2.0)
		_draw_center_text(rect.get_center() + Vector2(0, -6),
				"Keşfedilmedi", 13, Color(0.75, 0.78, 0.8, 0.9))
		_draw_center_text(rect.get_center() + Vector2(0, 14),
				"(dokunup keşfet)", 11, Color(0.6, 0.63, 0.66, 0.8))
	# Owner ribbon above visible regions.
	if visible and r.owning_kingdom_id != "":
		var who := WorldData.owner_name_for_region(r)
		_draw_center_text(rect.position + Vector2(0, -16), who, 12,
				Color(1, 1, 1, 0.55))
	# A CONTESTED region whose strongholds are all subdued reads as secured.
	if visible and _region_secured(r):
		_draw_center_text(rect.get_center() + Vector2(0, 26),
				"GÜVENCE ALTINA ALINDI", 11, COLOR_SUBDUED)

func _draw_poi(p: POIDef) -> void:
	var r := WorldData.region(p.region_id)
	var base: Color = WorldData.color_for_poi(p.poi_type)
	if p.poi_type == POIDef.Type.HOME and _kingdom_id() != "" \
			and r != null and r.owning_kingdom_id != _kingdom_id():
		# Another Kingdom's home is a foreign capital — tint by its owner.
		base = WorldData.owner_color_for_region(r)
	var radius := HOME_POI_RADIUS if p.poi_type == POIDef.Type.HOME else POI_RADIUS
	# A subdued STRONGHOLD is the player's conquered keep: paint it player-green so
	# it reads as secured, not as an ordinary spent POI. Other subdued/depleted
	# POIs keep the muted grey.
	var conquered_keep := p.poi_type == POIDef.Type.STRONGHOLD \
			and GameManager.poi_subdued(p.id)
	var col := base
	if conquered_keep:
		col = COLOR_SUBDUED
	elif GameManager.poi_subdued(p.id) or GameManager.poi_depleted(p.id):
		col = Color(0.45, 0.47, 0.5, 0.8)
	draw_circle(p.position, radius, Color(0, 0, 0, 0.35))
	draw_circle(p.position, radius - 2.0, col)
	# A small glyph so the marker type reads even without art. A conquered keep
	# swaps its S for a check to confirm the state change at a glance.
	var glyph := "✓" if conquered_keep else _poi_glyph(p.poi_type)
	if glyph != "":
		_draw_center_text(p.position, glyph, 12, Color(0.08, 0.08, 0.1, 0.9))
	# Home is the single most important marker; label it always.
	if p.poi_type == POIDef.Type.HOME:
		_draw_center_text(p.position + Vector2(0, radius + 12.0),
				p.display_name, 13, Color(1, 1, 1, 0.95))

func _poi_glyph(t: int) -> String:
	match t:
		POIDef.Type.HOME:
			return "K"
		POIDef.Type.STRONGHOLD:
			return "S"
		POIDef.Type.SHRINE:
			return "M"
		POIDef.Type.GATHER:
			return "R"
	return ""

func _region_rect(r: RegionDef) -> Rect2:
	return Rect2(r.center - r.half, r.half * 2.0)

func _draw_region_ring(r: RegionDef) -> void:
	var rect := _region_rect(r)
	draw_rect(Rect2(rect.position - Vector2.ONE * 5.0, rect.size + Vector2.ONE * 10.0),
			COLOR_SELECT, false, 3.0)

func _draw_circle_ring(center: Vector2, radius: float,
		col: Color = COLOR_SELECT) -> void:
	var pts := PackedVector2Array()
	var segments := 40
	for i in segments:
		var a := TAU * i / segments
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	# draw_polyline gives an open ring around a filled marker.
	var opened := PackedVector2Array()
	for i in segments - 1:
		opened.append(pts[i])
	draw_polyline(opened, col, 3.0, true)

## Draws `text` centred on `center` (both axes). Uses the fallback theme font so
## no font resource is required.
func _draw_center_text(center: Vector2, text: String, size: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var h := font.get_height(size)
	draw_string(font, center + Vector2(-w * 0.5, -h * 0.5), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

# --- Selection -----------------------------------------------------------------

func _fire_tap(screen: Vector2) -> void:
	var world := _screen_to_world(screen)
	var poi := _poi_at(world)
	if poi != null:
		_select_poi(poi)
		return
	var region := _region_at(world)
	if region != null:
		_select_region(region)
		return
	_hide_node_panel()
	_selected_poi = null
	_selected_region = null
	queue_redraw()

func _select_poi(p: POIDef) -> void:
	# Opening a POI also (re)confirms its region discovery.
	var r := WorldData.region(p.region_id)
	if r != null:
		GameManager.discover_region(r.id)
	GameManager.discover_poi(p.id)
	_selected_poi = p
	_selected_region = null
	_show_poi_panel(p)
	queue_redraw()

func _select_region(r: RegionDef) -> void:
	var just_discovered := not GameManager.region_discovered(r.id)
	GameManager.discover_region(r.id)
	# Revealing a region reveals the POIs within it too.
	for p in WorldData.pois_of_region(r.id):
		GameManager.discover_poi(p.id)
	_selected_region = r
	_selected_poi = null
	_show_region_panel(r, just_discovered)
	queue_redraw()

func _poi_at(world: Vector2) -> POIDef:
	var best: POIDef = null
	var best_d: float = INF
	for p in WorldData.poi_defs():
		if not _poi_visible(p):
			continue
		var radius := HOME_POI_RADIUS if p.poi_type == POIDef.Type.HOME else POI_RADIUS
		var d: float = world.distance_to(p.position)
		if d <= radius + POI_TAP_SLACK and d < best_d:
			best = p
			best_d = d
	return best

func _region_at(world: Vector2) -> RegionDef:
	for r in WorldData.region_defs():
		if _region_rect(r).has_point(world):
			return r
	return null

# --- Info panel ----------------------------------------------------------------

func _show_poi_panel(p: POIDef) -> void:
	node_title_label.text = p.display_name
	if _is_stronghold(p):
		# Strongholds get a raiding status line + SALDIR / ELE GEÇİRİLDİ action.
		node_detail_label.text = _stronghold_detail(p)
		_set_stronghold_action(p)
	else:
		var r := WorldData.region(p.region_id)
		var owner := ""
		if r != null:
			owner = " · %s" % WorldData.owner_name_for_region(r)
		node_detail_label.text = _poi_detail(p, r, owner)
		attack_button.visible = false
	node_panel.show()

func _poi_detail(p: POIDef, r: RegionDef, owner: String) -> String:
	var lines: Array[String] = []
	lines.append("Tür: %s%s" % [WorldData.poi_type_name(p.poi_type), owner])
	if r != null and r.display_name != "":
		lines.append("Bölge: %s" % r.display_name)
	# State (only meaningful for conquerable/exhaustible POIs).
	var state: Array[String] = []
	if GameManager.poi_subdued(p.id):
		state.append("bastırılmış")
	if GameManager.poi_depleted(p.id):
		state.append("tükenmiş")
	if state.size() > 0:
		lines.append("Durum: %s" % ", ".join(state))
	# Activity preview (activities are not runnable in D1).
	var act := WorldData.activity(p.activity_id) if p.activity_id != "" else null
	if act != null:
		lines.append("Aktivite: %s (gelecek pakette oynanabilir)" % act.display_name)
	if p.note != "":
		lines.append(p.note)
	return "\n".join(lines)

# --- Stronghold raiding (D2) ---------------------------------------------------

func _is_stronghold(p: POIDef) -> bool:
	return p != null and p.poi_type == POIDef.Type.STRONGHOLD

## A stronghold is attackable when it is a bandit keep in a CONTESTED border
## region that has not yet been subdued. The keep's region ownership does not gate
## attacks (contested keeps are hostile until conquered); region ownership itself
## is left unchanged by a conquest, per the D2 scope.
func _is_attackable_stronghold(p: POIDef) -> bool:
	if not _is_stronghold(p):
		return false
	var r := WorldData.region(p.region_id)
	if r == null or r.region_type != RegionDef.Type.CONTESTED:
		return false
	return not GameManager.poi_subdued(p.id)

func _stronghold_detail(p: POIDef) -> String:
	var r := WorldData.region(p.region_id)
	var lines: Array[String] = []
	lines.append("Tür: %s" % WorldData.poi_type_name(p.poi_type))
	if r != null:
		lines.append("Bölge: %s (%s)" % [r.display_name,
				WorldData.region_type_name(r.region_type)])
	var subdued := GameManager.poi_subdued(p.id)
	lines.append("Durum: %s" % ("ELE GEÇİRİLDİ" if subdued else "FETHEDİLMEDİ"))
	if subdued:
		lines.append("Garnizon dağıtıldı — bu kale artık güvenli.")
	else:
		lines.append("Haydut garnizonu hâlâ burada. Fethetmek için saldır ve "
				+ "belediye binasını yok et.")
	return "\n".join(lines)

func _set_stronghold_action(p: POIDef) -> void:
	if GameManager.poi_subdued(p.id):
		attack_button.text = "✓ ELE GEÇİRİLDİ"
		attack_button.disabled = true
	else:
		attack_button.text = "SALDIR"
		attack_button.disabled = false
	attack_button.visible = true

## Launches a Stronghold raid by reusing raid.tscn with transient raid routing on
## GameManager (never persisted). On return, raid.gd subdue the POI on a win.
func _launch_stronghold_raid() -> void:
	var p := _selected_poi
	if p == null or not _is_attackable_stronghold(p):
		return
	GameManager.raid_is_campaign = false
	GameManager.raid_is_stronghold = true
	GameManager.stronghold_poi_id = p.id
	# A campaign level (pre-authored, already-tested) stands in as this keep's
	# garrison; the post-battle return routes straight back to the world map.
	GameManager.raid_layout = RaidManager.level_data(STRONGHOLD_LEVEL)
	GameManager.raid_return_scene = WORLD_SCENE
	get_tree().change_scene_to_file(RAID_SCENE)

## A CONTESTED region is "secured" once every stronghold it holds has been subdued
## (all its bandit keeps cleared). Home/neutral regions are never marked secured.
func _region_secured(r: RegionDef) -> bool:
	if r == null or r.region_type != RegionDef.Type.CONTESTED:
		return false
	var has_keep := false
	for p in WorldData.pois_of_region(r.id):
		if p.poi_type == POIDef.Type.STRONGHOLD:
			has_keep = true
			if not GameManager.poi_subdued(p.id):
				return false
	return has_keep

## The player's current conquest target: the first un-subdued stronghold in their
## own Kingdom's CONTESTED border, or else any other un-subdued contested keep.
func _objective_stronghold() -> POIDef:
	var own := _kingdom_id()
	var fallback: POIDef = null
	for p in WorldData.poi_defs():
		if not _poi_visible(p) or not _is_attackable_stronghold(p):
			continue
		var r := WorldData.region(p.region_id)
		if r != null and r.owning_kingdom_id == own:
			return p
		if fallback == null:
			fallback = p
	return fallback

func _refresh_hint() -> void:
	var obj := _objective_stronghold()
	if obj != null:
		hint_label.text = ("Hedef: %s — kaleye dokun ve SALDIR.  "
				% obj.display_name
				+ "(Sürükle = kaydır · tekerlek / iki parmak = yakınlaştır)")
	else:
		hint_label.text = ("Keşfedilen kaleler fethedildi — sınırın güvenceye "
				+ "alındı. Yeni bölgeler için dünyada kaydır, sonra KÖYE DÖN.")

func _show_region_panel(r: RegionDef, just_discovered: bool) -> void:
	node_title_label.text = r.display_name
	var lines: Array[String] = []
	lines.append("Tür: %s" % WorldData.region_type_name(r.region_type))
	lines.append("Sahip: %s" % WorldData.owner_name_for_region(r))
	if just_discovered:
		lines.append("Bu bölgeyi keşfettin!")
	var count := WorldData.pois_of_region(r.id).size()
	if count > 0:
		lines.append("İçindeki noktalar: %d" % count)
	if _region_secured(r):
		lines.append("Güvence altına alındı: tüm kaleler fethedildi.")
	node_detail_label.text = "\n".join(lines)
	attack_button.visible = false
	node_panel.show()

func _hide_node_panel() -> void:
	node_panel.hide()

## Persists current resources + discovery, then returns to the player's village.
func _return_village() -> void:
	SaveManager.save_resources_only()
	GameManager.raid_is_campaign = true
	GameManager.raid_return_scene = MAIN_SCENE
	get_tree().change_scene_to_file(MAIN_SCENE)

func _update_resources(gold: int, elixir: int) -> void:
	gold_label.text = "Altın: %d" % gold
	elixir_label.text = "İksir: %d" % elixir

# --- Input: taps select, drags pan, pinch/wheel zoom --------------------------

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
			_disarm_tap()  # a second finger means pinch, not a select
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
	# Middle/right drag = free pan (never selects).
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
