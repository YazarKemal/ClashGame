extends Node
class_name DefenseDirector

## AI-raid battle lifecycle. Owns state, enemy spawning, and win/loss decisions
## for a defense battle against the clone of the player's village. Deliberately
## free of UI, saving and economy logic: it only decides the outcome and emits
## a result dictionary that a later UI package can present.

signal state_changed(new_state: int)
signal battle_finished(result: Dictionary)

## Outcome + live states. BATTLE runs while enemies fight; WIN/LOSS are final.
enum State { PREPARING, BATTLE, WIN, LOSS }

## Wave table, one entry per wave. Wave 1 (the only one in this package) lists
## each troop group and how many spawn. Kept as an array of waves so later
## packages can append waves 2/3 without touching the spawn logic.
const WAVES := [
	[
		{ "type": Unit.Type.BARBARIAN, "count": 5 },
		{ "type": Unit.Type.ARCHER, "count": 3 },
		{ "type": Unit.Type.GIANT, "count": 1 },
	],
]

## Enemy deployment ring: just outside the village grid so attackers walk in.
const PAD := 56.0
## How far along each side the slot positions spread from the midpoint.
const SPREAD_RATIO := 0.7
## Sides cycled in order so consecutive units never stack on the same side.
const SIDES := ["top", "right", "bottom", "left"]

## Loss threshold: destroying this share of non-wall buildings loses.
const LOSS_PERCENT := 50.0

var manager: BuildingManager
var current_state := State.PREPARING
var battle_over := false

## Units still alive in the current battle, dropped via the Unit.died signal.
var active_enemies: Array = []

var _initial_buildings := 0
var _destroyed_non_wall := 0
var _town_hall_destroyed := false

## Prepares the battle against `mgr`'s already-cloned village and launches the
## single attack wave. Safe to call once per scene instance.
func initialize(mgr: BuildingManager) -> void:
	if current_state != State.PREPARING:
		return
	manager = mgr
	_initial_buildings = _count_scorable_buildings()
	_hook_building_destruction()
	_spawn_wave(WAVES[0])
	_set_state(State.BATTLE)

## True when the current battle has already reached a final outcome.
func has_finished() -> bool:
	return battle_over

## Destruction of non-wall buildings as a 0-100 fraction of the starting count.
func destruction_percent() -> float:
	if _initial_buildings <= 0:
		return 0.0
	return 100.0 * _destroyed_non_wall / _initial_buildings

## Places `wave`'s units just outside the village border and starts tracking
## them. Enemy units reuse the player Unit AI unchanged: they self-join the
## "units" group, which is exactly what player towers target.
func _spawn_wave(wave: Array) -> void:
	var index := 0
	for entry in wave:
		var group: Dictionary = entry
		var t: Unit.Type = group["type"]
		for i in group["count"]:
			var u: Unit = manager.UNIT_SCENE.instantiate()
			u.unit_type = t
			u.position = _spawn_pos_for(index)
			add_child(u)
			u.died.connect(_on_enemy_died.bind(u))
			active_enemies.append(u)
			index += 1

## World position for the index-th spawned unit, spread across all four sides
## (top/right/bottom/left) at staggered offsets so the wave does not arrive as
## one clump. Positions sit just outside the grid, so they never land on a
## building and always have a clear path in.
func _spawn_pos_for(index: int) -> Vector2:
	var half: float = GridConfig.GRID_SIZE * GridConfig.TILE_SIZE * 0.5
	var side: String = SIDES[index % SIDES.size()]
	var slot := index / SIDES.size()
	# slot 0,1,2 -> -spread, 0, +spread along the side's axis.
	var coord := lerpf(-half * SPREAD_RATIO, half * SPREAD_RATIO,
			float(slot % 3) / 2.0)
	match side:
		"top":
			return Vector2(coord, -half - PAD)
		"bottom":
			return Vector2(coord, half + PAD)
		"left":
			return Vector2(-half - PAD, coord)
		_:
			return Vector2(half + PAD, coord)

## Listens to each standing clone building so destruction is signal-driven
## (never polled). The building is bound so its type can be read here, and is
## still valid because the destroyed signal fires before queue_free.
func _hook_building_destruction() -> void:
	for b in manager.get_tree().get_nodes_in_group("buildings"):
		if b is Building and b.state == Building.State.PLACED:
			b.destroyed.connect(_on_clone_building_destroyed.bind(b))

## Counts the buildings destruction is measured against: every non-wall placed
## building. Walls are excluded because they are pathing blockers consumed by
## the attack and, like Clash-style rules, do not count toward destruction.
func _count_scorable_buildings() -> int:
	var n := 0
	for b in manager.get_tree().get_nodes_in_group("buildings"):
		if b is Building and b.state == Building.State.PLACED \
				and b.building_type != Building.Type.WALL:
			n += 1
	return n

func _on_clone_building_destroyed(_cells: Array, b: Building) -> void:
	if battle_over:
		return
	if b.building_type == Building.Type.WALL:
		return
	if b.building_type == Building.Type.TOWN_HALL:
		_town_hall_destroyed = true
		_finish(State.LOSS)
		return
	_destroyed_non_wall += 1
	if destruction_percent() >= LOSS_PERCENT:
		_finish(State.LOSS)

## Drops a dead unit from the tracked set. Winning only matters once every
## enemy is gone and the battle has not already been lost.
func _on_enemy_died(u: Unit) -> void:
	for i in range(active_enemies.size() - 1, -1, -1):
		if active_enemies[i] == u:
			active_enemies.remove_at(i)
	if battle_over:
		return
	if active_enemies.is_empty():
		_finish(State.WIN)

## Records a final outcome once. Stops further tracking and publishes the
## result data the UI package will consume.
func _finish(outcome: State) -> void:
	if battle_over:
		return
	battle_over = true
	_set_state(outcome)
	battle_finished.emit({
		"outcome": outcome,
		"destroyed_buildings": _destroyed_non_wall,
		"destruction_percent": int(round(destruction_percent())),
		"remaining_enemies": active_enemies.size(),
	})

func _set_state(s: State) -> void:
	current_state = s
	state_changed.emit(s)
