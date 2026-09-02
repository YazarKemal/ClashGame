extends Node2D
class_name Building

signal destroyed(cells: Array)

enum State { PREVIEW, PLACED }
enum Type { TOWER, MINE, TOWN_HALL }

const ATTACK_RANGE := 200.0
const ATTACK_DAMAGE := 25
const ATTACK_INTERVAL := 1.0

## Static definitions per building type: footprint, cost, currency, color, HP.
const DATA := {
	Type.TOWER: {
		"name": "Savunma Kulesi",
		"size": 2,
		"cost": 100,
		"currency": "gold",
		"color": Color(0.4, 0.6, 1.0, 1.0),
		"gold_per_sec": 0,
		"max_hp": 300,
	},
	Type.MINE: {
		"name": "Altın Madeni",
		"size": 2,
		"cost": 80,
		"currency": "elixir",
		"color": Color(1.0, 0.78, 0.2, 1.0),
		"gold_per_sec": 5,
		"max_hp": 200,
	},
	Type.TOWN_HALL: {
		"name": "Belediye Binası",
		"size": 3,
		"cost": 250,
		"currency": "gold",
		"color": Color(0.42, 0.2, 0.62, 1.0),
		"gold_per_sec": 0,
		"max_hp": 600,
	},
}

const VALID_COLOR := Color(0.3, 0.9, 0.3, 0.75)
const INVALID_COLOR := Color(0.9, 0.3, 0.3, 0.75)

@export var building_type := Type.TOWER

var state := State.PLACED
var cell := Vector2i.ZERO
var cells: Array = []

## Derived from DATA in _ready().
var building_name := "Building"
var grid_size := 2
var cost := 0
var currency := "gold"
var gold_per_sec := 0
var max_hp := 100
var hp := max_hp
var _base_color := Color(0.55, 0.6, 0.7, 1.0)

var _timer: Timer = null
var _attack_timer: Timer = null

@onready var _body: Polygon2D = $Body
@onready var _label: Label = $Label
@onready var _hp_bar: ProgressBar = $HpBar

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
	max_hp = def["max_hp"]
	hp = max_hp
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
	_hp_bar.position = Vector2(-half, -half - 14.0)
	_hp_bar.size = Vector2(size, 8.0)
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp

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
	_hp_bar.hide()

## Locks the building onto cell (top-left), marks it built and starts any
## per-building behaviours (production, tower attacks).
func place_at(c: Vector2i) -> void:
	cell = c
	cells.clear()
	for dx in range(grid_size):
		for dy in range(grid_size):
			cells.append(c + Vector2i(dx, dy))
	state = State.PLACED
	position = _cell_center(c)
	_apply_state()
	_hp_bar.show()
	if gold_per_sec > 0:
		_start_production()
	if building_type == Type.TOWER:
		_start_attacks()

func take_damage(amount: int) -> void:
	if state != State.PLACED:
		return
	hp -= amount
	if _hp_bar != null:
		_hp_bar.value = max(hp, 0)
	if hp <= 0:
		_die()

func _die() -> void:
	remove_from_group("buildings")
	destroyed.emit(cells)
	queue_free()

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

func _start_attacks() -> void:
	if _attack_timer != null:
		return
	_attack_timer = Timer.new()
	_attack_timer.wait_time = ATTACK_INTERVAL
	_attack_timer.autostart = true
	add_child(_attack_timer)
	_attack_timer.timeout.connect(_attack)

func _attack() -> void:
	var target: Node2D = _nearest_unit_in_range()
	if target == null:
		return
	_fire_bullet(target)
	target.take_damage(ATTACK_DAMAGE)

func _nearest_unit_in_range() -> Node2D:
	var best: Node2D = null
	var best_d := ATTACK_RANGE * ATTACK_RANGE + 1.0
	for u in get_tree().get_nodes_in_group("units"):
		if u is Node2D:
			var d: float = global_position.distance_squared_to(u.global_position)
			if d <= ATTACK_RANGE * ATTACK_RANGE and d < best_d:
				best = u
				best_d = d
	return best

func _fire_bullet(target: Node2D) -> void:
	var bullet := Polygon2D.new()
	bullet.polygon = _circle_points(4.0, 8)
	bullet.color = Color(1.0, 0.95, 0.6, 1.0)
	add_child(bullet)
	var tw := create_tween()
	tw.tween_property(bullet, "position", to_local(target.global_position), 0.15)
	tw.parallel().tween_property(bullet, "modulate:a", 0.0, 0.15)
	tw.tween_callback(bullet.queue_free)

func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * i / segments
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts

func _cell_center(c: Vector2i) -> Vector2:
	return GridConfig.cell_to_world(c.x, c.y) \
			+ Vector2(grid_size * GridConfig.TILE_SIZE, grid_size * GridConfig.TILE_SIZE) * 0.5
