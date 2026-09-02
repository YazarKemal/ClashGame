extends Node2D
class_name Building

enum State { PREVIEW, PLACED }
enum Type { TOWER, MINE, TOWN_HALL }

## Static definitions per building type: footprint, cost, currency and color.
const DATA := {
	Type.TOWER: {
		"name": "Savunma Kulesi",
		"size": 2,
		"cost": 100,
		"currency": "gold",
		"color": Color(0.4, 0.6, 1.0, 1.0),
		"gold_per_sec": 0,
	},
	Type.MINE: {
		"name": "Altın Madeni",
		"size": 2,
		"cost": 80,
		"currency": "elixir",
		"color": Color(1.0, 0.78, 0.2, 1.0),
		"gold_per_sec": 5,
	},
	Type.TOWN_HALL: {
		"name": "Belediye Binası",
		"size": 3,
		"cost": 250,
		"currency": "gold",
		"color": Color(0.42, 0.2, 0.62, 1.0),
		"gold_per_sec": 0,
	},
}

const VALID_COLOR := Color(0.3, 0.9, 0.3, 0.75)
const INVALID_COLOR := Color(0.9, 0.3, 0.3, 0.75)

@export var building_type := Type.TOWER

var state := State.PLACED
var cell := Vector2i.ZERO

## Derived from DATA in _ready().
var building_name := "Building"
var grid_size := 2
var cost := 0
var currency := "gold"
var gold_per_sec := 0
var _base_color := Color(0.55, 0.6, 0.7, 1.0)

var _timer: Timer = null

@onready var _body: Polygon2D = $Body
@onready var _label: Label = $Label

func _ready() -> void:
	_apply_def(DATA[building_type])
	_label.text = building_name
	_build_footprint()
	_apply_state()

func _apply_def(def: Dictionary) -> void:
	building_name = def["name"]
	grid_size = def["size"]
	cost = def["cost"]
	currency = def["currency"]
	gold_per_sec = def["gold_per_sec"]
	_base_color = def["color"]

## Gold spent if this building's currency is gold, else 0.
func gold_cost() -> int:
	return cost if currency == "gold" else 0

## Elixir spent if this building's currency is elixir, else 0.
func elixir_cost() -> int:
	return cost if currency == "elixir" else 0

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

## Locks the building onto cell (top-left), marks it built and, if it produces
## resources, starts its periodic production timer.
func place_at(c: Vector2i) -> void:
	cell = c
	state = State.PLACED
	position = _cell_center(c)
	_apply_state()
	if gold_per_sec > 0:
		_start_production()

func _start_production() -> void:
	if _timer != null:
		return
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.autostart = true
	add_child(_timer)
	_timer.timeout.connect(_produce)

func _produce() -> void:
	if gold_per_sec <= 0:
		return
	GameManager.add_resources(gold_per_sec, 0)

func _cell_center(c: Vector2i) -> Vector2:
	return GridConfig.cell_to_world(c.x, c.y) \
			+ Vector2(grid_size * GridConfig.TILE_SIZE, grid_size * GridConfig.TILE_SIZE) * 0.5
