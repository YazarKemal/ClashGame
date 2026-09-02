extends Node2D
class_name Unit

## Tactical troop types and their combat profile. Cost is paid in elixir on
## deploy; damage/range are scaled per type from DATA.
enum Type { BARBARIAN, ARCHER, GIANT }

const DATA := {
	Type.BARBARIAN: {
		"name": "Barbar", "max_hp": 100, "speed": 90.0, "range": 25.0,
		"damage": 20, "cost": 15, "radius": 10.0,
		"color": Color(0.9, 0.2, 0.2, 1.0),
	},
	Type.ARCHER: {
		"name": "Okçu", "max_hp": 50, "speed": 80.0, "range": 120.0,
		"damage": 15, "cost": 25, "radius": 7.0,
		"color": Color(0.2, 0.8, 0.4, 1.0),
	},
	Type.GIANT: {
		"name": "Dev", "max_hp": 450, "speed": 45.0, "range": 30.0,
		"damage": 35, "cost": 80, "radius": 16.0,
		"color": Color(0.95, 0.55, 0.15, 1.0),
	},
}

const ATTACK_INTERVAL := 1.0

@export var unit_type := Type.BARBARIAN

var hp := 100
var max_hp := 100
var speed := 90.0
var attack_range := 25.0
var damage := 20
var _radius := 10.0
var _base_color := Color(0.9, 0.2, 0.2, 1.0)

var _attack_cd := 0.0

@onready var _body: Polygon2D = $Body
@onready var _hp_bar: ProgressBar = $HpBar

## Elixir cost to deploy this troop type.
static func cost_for(t: Type) -> int:
	return DATA[t]["cost"]

func _ready() -> void:
	add_to_group("units")
	_apply_def(DATA[unit_type])
	_body.color = _base_color
	_body.polygon = _circle_points(_radius, 12)
	_hp_bar.position = Vector2(-12.0, -24.0)
	_hp_bar.size = Vector2(24.0, 5.0)
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp

func _apply_def(def: Dictionary) -> void:
	max_hp = def["max_hp"]
	speed = def["speed"]
	attack_range = def["range"]
	damage = def["damage"]
	_radius = def["radius"]
	_base_color = def["color"]
	hp = max_hp

func _physics_process(delta: float) -> void:
	var target: Node2D = _select_target()
	if target == null:
		return
	var to_target: Vector2 = target.global_position - global_position
	if to_target.length() > attack_range:
		position += to_target.normalized() * speed * delta
	else:
		_attack_cd -= delta
		if _attack_cd <= 0.0:
			_attack_target(target)
			_attack_cd = ATTACK_INTERVAL

func _attack_target(target: Node2D) -> void:
	if unit_type == Type.ARCHER:
		_fire_arrow(target)
	else:
		target.take_damage(_effective_damage(target))

## Base damage, doubled against walls for the Giant.
func _effective_damage(target: Node2D) -> int:
	if unit_type != Type.GIANT:
		return damage
	var b := target as Building
	if b != null and b.is_wall():
		return damage * 2
	return damage

## Archer fires a visible arrow from range, dealing damage on release.
func _fire_arrow(target: Node2D) -> void:
	var arrow := Polygon2D.new()
	arrow.polygon = _circle_points(3.0, 6)
	arrow.color = Color(0.9, 0.85, 0.5, 1.0)
	add_child(arrow)
	var tw := create_tween()
	tw.tween_property(arrow, "position", to_local(target.global_position), 0.2)
	tw.parallel().tween_property(arrow, "modulate:a", 0.0, 0.2)
	tw.tween_callback(arrow.queue_free)
	target.take_damage(damage)

## Units break walls in their path first; the Giant then prioritizes defense
## towers over every other building.
func _select_target() -> Node2D:
	var preferred: Node2D = _preferred_building()
	var wall: Node2D = _nearest_wall()
	if preferred == null:
		return wall
	if wall != null and global_position.distance_squared_to(wall.global_position) \
			< global_position.distance_squared_to(preferred.global_position):
		return wall
	return preferred

func _preferred_building() -> Node2D:
	if unit_type == Type.GIANT:
		var tower: Node2D = _nearest_tower()
		if tower != null:
			return tower
	return _nearest_building()

## Nearest defense tower; the Giant's priority target.
func _nearest_tower() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Building and b.building_type == Building.Type.TOWER:
			var d: float = global_position.distance_squared_to(b.global_position)
			if d < best_d:
				best = b
				best_d = d
	return best

func _nearest_building() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Node2D:
			var d: float = global_position.distance_squared_to(b.global_position)
			if d < best_d:
				best = b
				best_d = d
	return best

## Nearest Wall among all buildings; used so units break walls in their path.
func _nearest_wall() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Node2D and b.is_wall():
			var d: float = global_position.distance_squared_to(b.global_position)
			if d < best_d:
				best = b
				best_d = d
	return best

func take_damage(amount: int) -> void:
	hp -= amount
	_flash_hit()
	if _hp_bar != null:
		_hp_bar.value = max(hp, 0)
	if hp <= 0:
		_spawn_death_particles()
		queue_free()

## Briefly flashes the body white so hits are visible.
func _flash_hit() -> void:
	if _body == null:
		return
	_body.color = Color.WHITE
	var tw := create_tween()
	tw.tween_property(_body, "color", _base_color, 0.1)

func _spawn_death_particles() -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = true
	p.amount = 16
	p.lifetime = 0.5
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 120.0
	p.gravity = Vector2(0, 150)
	p.color = _base_color
	p.position = position
	add_child(p)
	p.finished.connect(p.queue_free)

func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * i / segments
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts
