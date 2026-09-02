extends Node2D

## Raid (attack) scene controller. Builds a prepared enemy village on a fresh
## scene, lets the player deploy troops only at the grid border, accumulates
## loot as enemy buildings fall, and detects the end of the battle. The player
## village is never touched here: SaveManager only persists the main village.

const MAIN_SCENE := "res://scenes/main.tscn"

@onready var manager: BuildingManager = $BuildingManager
## Untyped so raid_ui.gd's script methods resolve at runtime.
@onready var ui = $RaidUI

var total_buildings := 0
var destroyed_count := 0
var gained_gold := 0
var gained_elixir := 0
var battle_over := false
var _current_level := 1
var _last_stars := 0
var _town_hall_destroyed := false
var _troops_deployed := false
var _check_timer: Timer = null

func _ready() -> void:
	GameManager.in_raid = true
	_current_level = GameManager.selected_level
	_build_enemy_village()
	manager.deploy_only_on_border = true
	manager.set_spawn_mode(true)
	manager.unit_spawned.connect(_on_unit_spawned)
	ui.setup(self, manager)
	var level: Dictionary = RaidManager.level_data(_current_level)
	ui.set_loot_pool(level["loot_gold"], level["loot_elixir"])
	_setup_check_timer()

func _on_unit_spawned() -> void:
	_troops_deployed = true

## Builds the selected level's enemy layout and assigns its loot pool to the
## buildings so destroyed buildings drop their share.
func _build_enemy_village() -> void:
	var level: Dictionary = RaidManager.level_data(_current_level)
	for spawn in level["spawns"]:
		var s: Dictionary = spawn
		_spawn(s["type"], s["cell"], s["loot_g"], s["loot_e"], int(s["level"]))

## Instantiates an enemy building at `cell`, fills the occupied grid and hooks
## its destruction so its loot is credited to the attacker.
func _spawn(btype: Building.Type, cell: Vector2i, loot_g: int, loot_e: int,
		blevel: int) -> void:
	if not manager.can_place_at(cell, Building.DATA[btype]["size"]):
		return
	var b: Building = manager.BUILDING_SCENE.instantiate()
	b.building_type = btype
	b.loot_gold = loot_g
	b.loot_elixir = loot_e
	manager.add_child(b)
	b.place_at(cell)
	_apply_level(b, btype, blevel)
	b.destroyed.connect(_on_enemy_destroyed.bind(loot_g, loot_e, btype))
	for c in b.cells:
		manager.occupied[c] = true
	total_buildings += 1

## Scales a freshly placed enemy building up to its template level, matching
## the player's own upgrade multipliers so higher levels are visibly tougher.
func _apply_level(b: Building, btype: Building.Type, blevel: int) -> void:
	for i in range(1, blevel):
		b.max_hp = int(b.max_hp * 1.4)
		if btype == Building.Type.TOWER:
			b.attack_damage = int(b.attack_damage * 1.4)
			b.attack_range = b.attack_range * 1.1
		elif btype == Building.Type.MINE:
			b.gold_per_sec = int(b.gold_per_sec * 1.4)
		elif btype == Building.Type.ELIXIR_COLLECTOR:
			b.elixir_per_sec = int(b.elixir_per_sec * 1.5)
	b.hp = b.max_hp
	b._apply_hp_bar()

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
	_last_stars = stars
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
	GameManager.record_level_result(_current_level, _last_stars)
	GameManager.add_resources(gained_gold, gained_elixir)
	SaveManager.save_resources_only()
	get_tree().change_scene_to_file(MAIN_SCENE)
