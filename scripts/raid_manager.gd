extends Node

## Autoload singleton that owns the PvE campaign level definitions. Each level
## lists the enemy village layout (building type, cell, level and per-building
## loot) plus the loot pool shown in the HUD. Any node can read a level by name
## (RaidManager), like GameManager. Levels are registered as an autoload so the
## engine resolves RaidManager references without a global-class rescan.

var _levels: Dictionary = {}

func _ready() -> void:
	_levels = _build_levels()

## How many campaign levels exist.
func level_count() -> int:
	return _levels.size()

## Human-readable names of all levels, in order.
func level_names() -> Array:
	var names: Array = []
	for i in range(1, _levels.size() + 1):
		names.append(_levels[i]["name"])
	return names

## The full definition for a level, falling back to level 1 when unknown.
func level_data(level: int) -> Dictionary:
	return _levels.get(level, _levels[1])

## Returns the wall cells making up a hollow rectangle border, used to build
## the full and double wall rings on higher levels.
func _ring(min_x: int, max_x: int, min_y: int, max_y: int) -> Array:
	var cells: Array = []
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			if x == min_x or x == max_x or y == min_y or y == max_y:
				cells.append(Vector2i(x, y))
	return cells

## A wall spawn entry (level 1, no loot).
func _wall(w: Vector2i) -> Dictionary:
	return { "type": Building.Type.WALL, "cell": w, "level": 1, "loot_g": 0, "loot_e": 0 }

func _build_levels() -> Dictionary:
	return {
		1: _make_level_1(),
		2: _make_level_2(),
		3: _make_level_3(),
	}

## Level 1 - Goblin Çadırı: 1 Town Hall, 1 Tower, a few walls, 300G / 300E.
func _make_level_1() -> Dictionary:
	var spawns: Array = [
		{ "type": Building.Type.TOWN_HALL, "cell": Vector2i(18, 18), "level": 1, "loot_g": 300, "loot_e": 300 },
		{ "type": Building.Type.TOWER, "cell": Vector2i(13, 18), "level": 1, "loot_g": 0, "loot_e": 0 },
	]
	for w in [Vector2i(16, 13), Vector2i(17, 13), Vector2i(20, 13), Vector2i(21, 13),
			Vector2i(13, 13), Vector2i(13, 14)]:
		spawns.append(_wall(w))
	return { "name": "Goblin Çadırı", "loot_gold": 300, "loot_elixir": 300, "spawns": spawns }

## Level 2 - Karakol: 1 Town Hall, 2 Towers, a mine and an elixir collector,
## a full wall ring, 800G / 800E. Mine 300G, collector 300E, Town Hall 500G/500E.
func _make_level_2() -> Dictionary:
	var spawns: Array = [
		{ "type": Building.Type.TOWN_HALL, "cell": Vector2i(18, 18), "level": 1, "loot_g": 500, "loot_e": 500 },
		{ "type": Building.Type.TOWER, "cell": Vector2i(13, 18), "level": 1, "loot_g": 0, "loot_e": 0 },
		{ "type": Building.Type.TOWER, "cell": Vector2i(23, 18), "level": 1, "loot_g": 0, "loot_e": 0 },
		{ "type": Building.Type.MINE, "cell": Vector2i(18, 13), "level": 1, "loot_g": 300, "loot_e": 0 },
		{ "type": Building.Type.ELIXIR_COLLECTOR, "cell": Vector2i(18, 23), "level": 1, "loot_g": 0, "loot_e": 300 },
	]
	for w in _ring(12, 25, 12, 25):
		spawns.append(_wall(w))
	return { "name": "Karakol", "loot_gold": 800, "loot_elixir": 800, "spawns": spawns }

## Level 3 - Goblin Kalesi: 1 Town Hall (Lv 2), 3 Towers (Lv 2), a double wall
## ring, 1500G / 1500E all held by the Town Hall.
func _make_level_3() -> Dictionary:
	var spawns: Array = [
		{ "type": Building.Type.TOWN_HALL, "cell": Vector2i(18, 18), "level": 2, "loot_g": 1500, "loot_e": 1500 },
		{ "type": Building.Type.TOWER, "cell": Vector2i(13, 18), "level": 2, "loot_g": 0, "loot_e": 0 },
		{ "type": Building.Type.TOWER, "cell": Vector2i(23, 18), "level": 2, "loot_g": 0, "loot_e": 0 },
		{ "type": Building.Type.TOWER, "cell": Vector2i(18, 13), "level": 2, "loot_g": 0, "loot_e": 0 },
	]
	for w in _ring(11, 26, 11, 26):
		spawns.append(_wall(w))
	for w in _ring(15, 22, 15, 22):
		spawns.append(_wall(w))
	return { "name": "Goblin Kalesi", "loot_gold": 1500, "loot_elixir": 1500, "spawns": spawns }
