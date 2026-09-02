extends Node2D
class_name Building

signal destroyed(cells: Array)
signal hp_changed(current_hp: int, max_hp: int)
signal upgraded(level: int)

enum State { PREVIEW, PLACED }
enum Type { TOWER, MINE, TOWN_HALL, WALL }

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
	Type.WALL: {
		"name": "Duvar",
		"size": 1,
		"cost": 20,
		"currency": "gold",
		"color": Color(0.42, 0.42, 0.46, 1.0),
		"gold_per_sec": 0,
		"max_hp": 800,
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
var level := 1
var max_level := 3
var attack_damage := ATTACK_DAMAGE
var attack_range := ATTACK_RANGE
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

## True if this is a Wall (defensive blocker), which units must break first.
func is_wall() -> bool:
	return building_type == Type.WALL

## Cost to advance from the current level (in the building's own currency).
func upgrade_cost() -> int:
	return cost * level

## Gold spent if this building's upgrade costs gold, else 0.
func upgrade_gold_cost() -> int:
	return upgrade_cost() if currency == "gold" else 0

## Elixir spent if this building's upgrade costs elixir, else 0.
func upgrade_elixir_cost() -> int:
	return upgrade_cost() if currency == "elixir" else 0

## True if the world point lies within this building's footprint.
func contains_world_point(p: Vector2) -> bool:
	var half := grid_size * GridConfig.TILE_SIZE * 0.5
	return absf(p.x - position.x) <= half and absf(p.y - position.y) <= half

## Advances the level: pays the upgrade cost, raises max HP by 40% (healing to
## full), and boosts tower damage/range or mine production. Returns false if
## already maxed out or the player cannot afford it.
func upgrade() -> bool:
	if level >= max_level:
		return false
	if not GameManager.spend_resources(upgrade_gold_cost(), upgrade_elixir_cost()):
		return false
	level += 1
	max_hp = int(max_hp * 1.4)
	hp = max_hp
	if building_type == Type.TOWER:
		attack_damage = int(attack_damage * 1.4)
		attack_range = attack_range * 1.1
	elif building_type == Type.MINE:
		gold_per_sec = int(gold_per_sec * 1.4)
	_apply_hp_bar()
	_flash_upgrade()
	upgraded.emit(level)
	hp_changed.emit(hp, max_hp)
	return true

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
	_flash_hit()
	_apply_hp_bar()
	hp_changed.emit(maxi(hp, 0), max_hp)
	if hp <= 0:
		_die()

## Syncs the HP bar to the building's current and max HP.
func _apply_hp_bar() -> void:
	if _hp_bar == null:
		return
	_hp_bar.max_value = max_hp
	_hp_bar.value = max(hp, 0)

## Briefly flashes the body white so hits are visible.
func _flash_hit() -> void:
	if _body == null:
		return
	_body.color = Color.WHITE
	var tw := create_tween()
	tw.tween_property(_body, "color", _base_color, 0.1)

## Pulsing scale + alpha flash so a successful upgrade is clearly visible.
func _flash_upgrade() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "modulate:a", 0.5, 0.08)
	tw.tween_property(self, "modulate:a", 1.0, 0.08)

func _die() -> void:
	_spawn_death_particles()
	remove_from_group("buildings")
	destroyed.emit(cells)
	queue_free()

func _spawn_death_particles() -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = true
	p.amount = 24
	p.lifetime = 0.6
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 140.0
	p.gravity = Vector2(0, 200)
	p.color = _base_color
	p.position = position
	add_child(p)
	p.finished.connect(p.queue_free)

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
	target.take_damage(attack_damage)

func _nearest_unit_in_range() -> Node2D:
	var best: Node2D = null
	var best_d := attack_range * attack_range + 1.0
	for u in get_tree().get_nodes_in_group("units"):
		if u is Node2D:
			var d: float = global_position.distance_squared_to(u.global_position)
			if d <= attack_range * attack_range and d < best_d:
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
