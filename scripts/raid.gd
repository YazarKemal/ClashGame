extends Node2D

## Raid (attack) scene controller. Builds a prepared enemy village on a fresh
## scene, lets the player deploy troops only at the grid border, accumulates
## loot as enemy buildings fall, and detects the end of the battle. The player
## village is never touched here: SaveManager only persists the main village.

const MAIN_SCENE := "res://scenes/main.tscn"

const TOTAL_POOL_GOLD := 500
const TOTAL_POOL_ELIXIR := 500

## Walls forming a loose ring around the enemy core.
const RING_WALLS := [
	Vector2i(14, 14), Vector2i(23, 14), Vector2i(14, 23), Vector2i(23, 23),
	Vector2i(14, 18), Vector2i(23, 18), Vector2i(18, 14), Vector2i(18, 23),
	Vector2i(14, 16), Vector2i(14, 20), Vector2i(23, 16), Vector2i(23, 20),
]

@onready var manager: BuildingManager = $BuildingManager
## Untyped so raid_ui.gd's script methods resolve at runtime.
@onready var ui = $RaidUI

var total_buildings := 0
var destroyed_count := 0
var gained_gold := 0
var gained_elixir := 0
var battle_over := false
var _town_hall_destroyed := false
var _troops_deployed := false
var _check_timer: Timer = null

func _ready() -> void:
	GameManager.in_raid = true
	_build_enemy_village()
	manager.deploy_only_on_border = true
	manager.set_spawn_mode(true)
	manager.unit_spawned.connect(_on_unit_spawned)
	ui.setup(self, manager)
	ui.set_loot_pool(TOTAL_POOL_GOLD, TOTAL_POOL_ELIXIR)
	_setup_check_timer()

func _on_unit_spawned() -> void:
	_troops_deployed = true

## Builds the fixed enemy layout and assigns the shared loot pool to its
## buildings so destroyed buildings drop their share.
func _build_enemy_village() -> void:
	# Mine: 250G. Elixir collector: 250E. Town Hall: the remainder (250G/250E).
	# Towers and walls hold no loot. Totals to 500G / 500E.
	_spawn(Building.Type.TOWN_HALL, Vector2i(18, 18), 250, 250)
	_spawn(Building.Type.TOWER, Vector2i(15, 18), 0, 0)
	_spawn(Building.Type.TOWER, Vector2i(21, 18), 0, 0)
	_spawn(Building.Type.MINE, Vector2i(18, 15), 250, 0)
	_spawn(Building.Type.ELIXIR_COLLECTOR, Vector2i(18, 21), 0, 250)
	for w in RING_WALLS:
		_spawn(Building.Type.WALL, w, 0, 0)

## Instantiates an enemy building at `cell`, fills the occupied grid and hooks
## its destruction so its loot is credited to the attacker.
func _spawn(btype: Building.Type, cell: Vector2i, loot_g: int, loot_e: int) -> void:
	if not manager.can_place_at(cell, Building.DATA[btype]["size"]):
		return
	var b: Building = manager.BUILDING_SCENE.instantiate()
	b.building_type = btype
	b.loot_gold = loot_g
	b.loot_elixir = loot_e
	manager.add_child(b)
	b.place_at(cell)
	b.destroyed.connect(_on_enemy_destroyed.bind(loot_g, loot_e, btype))
	for c in b.cells:
		manager.occupied[c] = true
	total_buildings += 1

func _on_enemy_destroyed(_cells: Array, loot_g: int, loot_e: int, btype: Building.Type) -> void:
	if battle_over:
		return
	destroyed_count += 1
	if btype == Building.Type.TOWN_HALL:
		_town_hall_destroyed = true
	gained_gold += loot_g
	gained_elixir += loot_e
	ui.update_gained(gained_gold, gained_elixir)

func _setup_check_timer() -> void:
	_check_timer = Timer.new()
	_check_timer.wait_time = 0.5
	_check_timer.autostart = true
	add_child(_check_timer)
	_check_timer.timeout.connect(_check_end)

## Ends the battle when every building is gone, or when the whole trained army
## has been spent and no units are left standing.
func _check_end() -> void:
	if battle_over:
		return
	if _count_buildings() == 0:
		_end_battle()
	elif _troops_deployed and GameManager.army_total() == 0 and _count_units() == 0:
		_end_battle()

func _count_buildings() -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Building:
			n += 1
	return n

func _count_units() -> int:
	var n := 0
	for u in get_tree().get_nodes_in_group("units"):
		if u is Node2D:
			n += 1
	return n

## Called by the top-right "Savaşı Bitir" button to end a raid early.
func _end_battle() -> void:
	if battle_over:
		return
	battle_over = true
	_check_timer.stop()
	manager.set_spawn_mode(false)
	var pct := 0
	if total_buildings > 0:
		pct = int(round(100.0 * destroyed_count / total_buildings))
	var stars := _compute_stars(pct, destroyed_count >= total_buildings)
	ui.show_result(pct, stars, gained_gold, gained_elixir)

## 1 star for 50%+ destruction, 1 for the Town Hall, 1 for a full clear (max 3).
func _compute_stars(pct: int, full_clear: bool) -> int:
	var stars := 0
	if pct >= 50:
		stars += 1
	if _town_hall_destroyed:
		stars += 1
	if full_clear:
		stars += 1
	return mini(stars, 3)

## Returns to the main village, crediting looted resources and persisting the
## updated vault without altering the saved main-village buildings.
func _return_home() -> void:
	GameManager.in_raid = false
	GameManager.add_resources(gained_gold, gained_elixir)
	SaveManager.save_resources_only()
	get_tree().change_scene_to_file(MAIN_SCENE)
