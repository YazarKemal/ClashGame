extends Node2D
class_name Unit

const SPEED := 60.0
const ATTACK_RANGE := 42.0
const DAMAGE := 20
const ATTACK_INTERVAL := 1.0
const MAX_HP := 100

var hp := MAX_HP

var _attack_cd := 0.0

@onready var _body: Polygon2D = $Body
@onready var _hp_bar: ProgressBar = $HpBar

func _ready() -> void:
	add_to_group("units")
	_body.polygon = _circle_points(10.0, 12)
	_hp_bar.position = Vector2(-12.0, -24.0)
	_hp_bar.size = Vector2(24.0, 5.0)
	_hp_bar.max_value = MAX_HP
	_hp_bar.value = hp

func _physics_process(delta: float) -> void:
	var target: Node2D = _nearest_building()
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

func take_damage(amount: int) -> void:
	hp -= amount
	if _hp_bar != null:
		_hp_bar.value = max(hp, 0)
	if hp <= 0:
		queue_free()

func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * i / segments
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts
