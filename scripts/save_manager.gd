extends Node
## Autoload singleton that persists the village layout and resources to a
## JSON file on disk. Any node can trigger a save or load by name
## (SaveManager), just like GameManager.

const SAVE_PATH := "user://save_game.json"

## Building.Type <-> string names for JSON-friendly storage.
const TYPE_NAMES := {
	Building.Type.TOWER: "tower",
	Building.Type.MINE: "mine",
	Building.Type.TOWN_HALL: "town_hall",
	Building.Type.WALL: "wall",
	Building.Type.ELIXIR_COLLECTOR: "elixir_collector",
	Building.Type.BARRACKS: "barracks",
	Building.Type.ARMY_CAMP: "army_camp",
}

const TYPE_FROM_NAME := {
	"tower": Building.Type.TOWER,
	"mine": Building.Type.MINE,
	"town_hall": Building.Type.TOWN_HALL,
	"wall": Building.Type.WALL,
	"elixir_collector": Building.Type.ELIXIR_COLLECTOR,
	"barracks": Building.Type.BARRACKS,
	"army_camp": Building.Type.ARMY_CAMP,
}

## Writes the current resources and every placed building to the save file.
func save_game(manager: BuildingManager) -> void:
	var buildings := []
	for b in manager.get_tree().get_nodes_in_group("buildings"):
		if b is Building and b.state == Building.State.PLACED:
			buildings.append({
				"type": TYPE_NAMES[b.building_type],
				"cell": {"x": b.cell.x, "y": b.cell.y},
				"level": b.level,
				"current_hp": maxi(b.hp, 0),
			})
	var data := {
		"resources": {"gold": GameManager.gold, "elixir": GameManager.elixir},
		"buildings": buildings,
		"army_data": GameManager.army_data,
		"level_stars": GameManager.best_stars,
		"last_saved_time": int(Time.get_unix_time_from_system()),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Kayıt başarısız: %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

## Restores resources and buildings from the save file. Returns true when a
## file was loaded; when none exists (or it is corrupt) it seeds a fresh
## village with a Town Hall in the center and returns false.
func load_game(manager: BuildingManager) -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		_init_default_village(manager)
		return false
	var raw := FileAccess.get_file_as_string(SAVE_PATH)
	var data: Variant = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Kayıt dosyası bozuk, sıfır köy kuruluyor.")
		_init_default_village(manager)
		return false

	var res: Dictionary = data.get("resources", {})
	GameManager.gold = int(res.get("gold", 500))
	GameManager.elixir = int(res.get("elixir", 500))
	GameManager.resource_changed.emit(GameManager.gold, GameManager.elixir)

	_restore_army(data.get("army_data", {}))
	GameManager.army_changed.emit()
	_restore_stars(data.get("level_stars", {}))

	_spawn_buildings_from_data(manager, data)
	return true

## Rebuilds a full clone of the SAVED village (types, grid cells and levels)
## into `manager`, with no side effects on the real GameManager resources, army
## or stars, and without triggering a save. Used by the defense scene to make a
## disposable copy of the player's village for AI raids. Returns the number of
## buildings cloned (0 when no save file exists or it is corrupt).
func spawn_saved_buildings_into(manager: BuildingManager) -> int:
	if not FileAccess.file_exists(SAVE_PATH):
		return 0
	var raw := FileAccess.get_file_as_string(SAVE_PATH)
	var data: Variant = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Kayıt dosyası bozuk, savunma köyü kurulamadı.")
		return 0
	return _spawn_buildings_from_data(manager, data)

## Spawns every building stored in `data` via _spawn_building and returns the
## count. Shared by load_game (village reload) and spawn_saved_buildings_into
## (defense clone) so both paths stay identical.
func _spawn_buildings_from_data(manager: BuildingManager, data: Dictionary) -> int:
	var count := 0
	for entry in data.get("buildings", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = entry
		var type: Building.Type = TYPE_FROM_NAME.get(
				e.get("type", "tower"), Building.Type.TOWER)
		var cell := _cell_from_dict(e.get("cell", {}))
		var level := int(e.get("level", 1))
		var hp := int(e.get("current_hp", 0))
		_spawn_building(manager, type, cell, level, hp)
		count += 1
	return count

## Restores the trained army from the save data. JSON turns integer troop-type
## keys into strings, so they are converted back to ints here.
func _restore_army(raw_army: Dictionary) -> void:
	GameManager.army_data = {}
	for k in raw_army:
		GameManager.army_data[int(k)] = int(raw_army[k])

## Restores the best-stars map, converting the string keys JSON produces back
## to integers.
func _restore_stars(raw_stars: Dictionary) -> void:
	GameManager.best_stars = {}
	for k in raw_stars:
		GameManager.best_stars[int(k)] = int(raw_stars[k])

## Rewrites only the resources in the existing save file, leaving the saved
## buildings untouched. Used when returning from a raid: the player's vault is
## updated (troop costs spent, loot gained) and persisted without letting the
## enemy village leak into the main village save.
func save_resources_only() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var raw := FileAccess.get_file_as_string(SAVE_PATH)
	var data: Variant = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		return
	data["resources"] = {"gold": GameManager.gold, "elixir": GameManager.elixir}
	data["army_data"] = GameManager.army_data
	data["level_stars"] = GameManager.best_stars
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

## Destroys all buildings, clears the grid and resources, removes the save
## file, then reseeds a fresh village so the load path can be tested.
func reset_village(manager: BuildingManager) -> void:
	for b in manager.get_tree().get_nodes_in_group("buildings"):
		if b is Building:
			b.free()
	manager.occupied.clear()
	manager._set_selected(null)
	GameManager.gold = 500
	GameManager.elixir = 500
	GameManager.resource_changed.emit(500, 500)
	GameManager.army_data = {}
	GameManager.army_changed.emit()
	GameManager.best_stars = {}
	GameManager.level_stars_changed.emit()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_init_default_village(manager)
	save_game(manager)

## Seeds a brand-new village: default resources plus one Town Hall in the
## center of the grid.
func _init_default_village(manager: BuildingManager) -> void:
	GameManager.gold = 500
	GameManager.elixir = 500
	GameManager.resource_changed.emit(500, 500)
	var center := Vector2i((GridConfig.GRID_SIZE - 3) / 2, (GridConfig.GRID_SIZE - 3) / 2)
	_spawn_building(manager, Building.Type.TOWN_HALL, center, 1, 600)

## Instantiates a building at the saved cell, restores its level (recomputing
## the stats that upgrade() scales) and its current HP, then occupies the grid.
func _spawn_building(manager: BuildingManager, type: Building.Type,
		cell: Vector2i, level: int, hp: int) -> void:
	var b: Building = manager.BUILDING_SCENE.instantiate()
	b.building_type = type
	manager.add_child(b)
	b.place_at(cell)

	b.level = maxi(level, 1)
	b._apply_def(Building.DATA[type])
	b.level = maxi(level, 1)
	for i in range(1, b.level):
		b.max_hp = int(b.max_hp * 1.4)
		if type == Building.Type.TOWER:
			b.attack_damage = int(b.attack_damage * 1.4)
			b.attack_range = b.attack_range * 1.1
		elif type == Building.Type.MINE:
			b.gold_per_sec = int(b.gold_per_sec * 1.4)
		elif type == Building.Type.ELIXIR_COLLECTOR:
			b.elixir_per_sec = int(b.elixir_per_sec * 1.5)
	b.hp = clamp(hp, 0, b.max_hp)
	b._apply_hp_bar()

	for c in b.cells:
		manager.occupied[c] = true

## Converts a {"x": int, "y": int} dictionary back into a grid cell.
func _cell_from_dict(d: Dictionary) -> Vector2i:
	return Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
