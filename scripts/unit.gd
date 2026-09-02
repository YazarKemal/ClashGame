extends Node2D
class_name Unit

const SPEED := 60.0
const ATTACK_RANGE := 42.0
const DAMAGE := 20
const ATTACK_INTERVAL := 1.0
const MAX_HP := 100

var hp := MAX_HP
var _base_color := Color(0.9, 0.2, 0.2, 1.0)

var _attack_cd := 0.0

@onready var _body: Polygon2D = $Body
@onready var _hp_bar: ProgressBar = $HpBar

func _ready() -> void:
	add_to_group("units")
	_base_color = _body.color
	_body.polygon = _circle_points(10.0, 12)
	_hp_bar.position = Vector2(-12.0, -24.0)
	_hp_bar.size = Vector2(24.0, 5.0)
	_hp_bar.max_value = MAX_HP
	_hp_bar.value = hp

func _physics_process(delta: float) -> void:
	var target: Node2D = _select_target()
	if target == null:
		return
	var to_target: Vector2 = target.global_position - global_position
	if to_target.length() > ATTACK_RANGE:
		position += to_target.normalized() * SPEED * delta
	else:
		_attack_cd -= delta
		if _attack_cd <= 0.0:
			target.take_damage(DAMAGE)
			_attack_cd = ATTACK_INTERVAL

## Chooses what to attack: a Wall closer than the nearest building (so units
## stop and break walls first), otherwise the nearest building.
func _select_target() -> Node2D:
	var building: Node2D = _nearest_building()
	var wall: Node2D = _nearest_wall()
	if wall != null and building != null:
		if global_position.distance_squared_to(wall.global_position) \
				< global_position.distance_squared_to(building.global_position):
			return wall
	return building

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
