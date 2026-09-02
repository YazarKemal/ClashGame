class_name SaveManager
## Persists the village layout and resources to a JSON file on disk. Exposed
## as static helpers so any node (BuildingManager, UI, Main) can trigger a
## save or load without needing an autoload instance.

const SAVE_PATH := "user://save_game.json"

## Building.Type <-> string names for JSON-friendly storage.
const TYPE_NAMES := {
	Building.Type.TOWER: "tower",
	Building.Type.MINE: "mine",
	Building.Type.TOWN_HALL: "town_hall",
	Building.Type.WALL: "wall",
	Building.Type.ELIXIR_COLLECTOR: "elixir_collector",
}

const TYPE_FROM_NAME := {
	"tower": Building.Type.TOWER,
	"mine": Building.Type.MINE,
	"town_hall": Building.Type.TOWN_HALL,
	"wall": Building.Type.WALL,
	"elixir_collector": Building.Type.ELIXIR_COLLECTOR,
}

## Writes the current resources and every placed building to the save file.
static func save_game(manager: BuildingManager) -> void:
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
static func load_game(manager: BuildingManager) -> bool:
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
	return true

## Destroys all buildings, clears the grid and resources, removes the save
## file, then reseeds a fresh village so the load path can be tested.
static func reset_village(manager: BuildingManager) -> void:
	for b in manager.get_tree().get_nodes_in_group("buildings"):
		if b is Building:
			b.free()
	manager.occupied.clear()
	manager._set_selected(null)
	GameManager.gold = 500
	GameManager.elixir = 500
	GameManager.resource_changed.emit(500, 500)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_init_default_village(manager)
	save_game(manager)

## Seeds a brand-new village: default resources plus one Town Hall in the
## center of the grid.
static func _init_default_village(manager: BuildingManager) -> void:
	GameManager.gold = 500
	GameManager.elixir = 500
	GameManager.resource_changed.emit(500, 500)
	var center := Vector2i((GridConfig.GRID_SIZE - 3) / 2, (GridConfig.GRID_SIZE - 3) / 2)
	_spawn_building(manager, Building.Type.TOWN_HALL, center, 1, 600)

## Instantiates a building at the saved cell, restores its level (recomputing
## the stats that upgrade() scales) and its current HP, then occupies the grid.
static func _spawn_building(manager: BuildingManager, type: Building.Type,
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
static func _cell_from_dict(d: Dictionary) -> Vector2i:
	return Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
