class_name WorldNode
extends Node2D

## A single clickable point on the macro world map: the player's home village,
## a faction city/castle, or a neutral resource camp. Pure presentation + data;
## all interaction logic (moving the army to it, camp income, starting raids)
## lives in world_map.gd. Nodes are rebuilt each time the map scene loads.

enum Type { HOME_VILLAGE, FACTION_CITY, RESOURCE_CAMP }
enum Faction { NEUTRAL, RED, BLUE }

const COLOR_HOME := Color(0.25, 0.85, 0.6, 1.0)
const COLOR_CAMP := Color(1.0, 0.82, 0.25, 1.0)
const COLOR_RED := Color(0.9, 0.24, 0.2, 1.0)
const COLOR_BLUE := Color(0.28, 0.55, 0.95, 1.0)
const COLOR_NEUTRAL := Color(0.62, 0.68, 0.72, 1.0)
const COLOR_DONE := Color(0.5, 0.52, 0.54, 0.9)  # claimed/visited camp

var node_id := ""
var type := Type.RESOURCE_CAMP
var faction := Faction.NEUTRAL
var tier: int = 1
var radius: float = 40.0
var title := ""

## While the army is parked at a RESOURCE_CAMP, this yields resources every
## CAMP_INTERVAL seconds (set per node by world_map).
var gold_reward: int = 0
var elixir_reward: int = 0
var camp_interval: float = 0.0

var _selected := false

@onready var _body: Polygon2D = $Body
@onready var _name_label: Label = $NameLabel

# Pulsing selection ring, lazily created on set_selected(true).
var _ring: Line2D = null
var _ring_tween: Tween = null

func _ready() -> void:
	_body.polygon = _shape_points(radius, 28)
	_body.color = _color()
	_name_label.text = title
	_name_label.position = Vector2(-70, -radius - 26)
	_name_label.size = Vector2(140, 22)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 13)

## Fills this node from a definition dictionary (see world_map.NODE_DEFS).
func setup(def: Dictionary) -> void:
	node_id = def["id"]
	type = def["type"]
	faction = def["faction"]
	tier = int(def.get("tier", 1))
	radius = float(def.get("radius", 40.0))
	title = def["title"]
	gold_reward = int(def.get("gold_reward", 0))
	elixir_reward = int(def.get("elixir_reward", 0))
	camp_interval = float(def.get("camp_interval", 0.0))
	position = def["pos"]
	add_to_group("world_nodes")

func _color() -> Color:
	if type == Type.HOME_VILLAGE:
		return COLOR_HOME
	if type == Type.RESOURCE_CAMP:
		return COLOR_CAMP
	if type == Type.FACTION_CITY:
		if faction == Faction.RED:
			return COLOR_RED
		if faction == Faction.BLUE:
			return COLOR_BLUE
	return COLOR_NEUTRAL

## Marks a claimed camp with a faded palette so the player can tell it is spent.
func set_claimed(claimed: bool) -> void:
	if claimed:
		_body.color = COLOR_DONE
		_name_label.modulate.a = 0.6
	else:
		_body.color = _color()
		_name_label.modulate.a = 1.0

## Shows/hides the pulsing white ring marking the army's current destination.
func set_selected(on: bool) -> void:
	_selected = on
	if on:
		_show_ring()
	else:
		_hide_ring()

func _show_ring() -> void:
	if _ring != null:
		return
	var r := radius + 8.0
	_ring = Line2D.new()
	_ring.closed = true
	_ring.width = 3.0
	_ring.default_color = Color(1, 1, 1, 1)
	_ring.antialiased = true
	_ring.z_index = 30
	_ring.points = PackedVector2Array([
		Vector2(-r, -r), Vector2(r, -r),
		Vector2(r, r), Vector2(-r, r),
	])
	add_child(_ring)
	_ring_tween = _ring.create_tween().set_loops()
	_ring_tween.tween_property(_ring, "modulate:a", 0.3, 0.6) \
		.set_trans(Tween.TRANS_SINE)
	_ring_tween.tween_property(_ring, "modulate:a", 1.0, 0.6) \
		.set_trans(Tween.TRANS_SINE)

func _hide_ring() -> void:
	if _ring_tween != null and _ring_tween.is_valid():
		_ring_tween.kill()
		_ring_tween = null
	if _ring != null:
		_ring.queue_free()
		_ring = null

func _shape_points(radius_: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * i / segments
		pts.append(Vector2(cos(a), sin(a)) * radius_)
	return pts
