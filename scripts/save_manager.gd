extends Node
## Autoload singleton that persists the village layout and resources to a
## JSON file on disk. Any node can trigger a save or load by name
## (SaveManager), just like GameManager.

const SAVE_PATH := "user://save_game.json"

## Offline production never accumulates past this many seconds, so an absent
## player can't come back to an exploded economy after a multi-week absence.
const MAX_OFFLINE_SECONDS := 8 * 3600  # 8 hours

## Absences shorter than this are treated as "still here" (e.g. returning from
## a raid, which rewrites last_saved_time to ~now) and earn no offline income,
## so a sub-minute gap never spawns a pointless popup.
const MIN_OFFLINE_SECONDS := 60

## Human-readable offline report for the last load ("" when nothing earned).
## Read by main.gd after load_game() so the village scene can show a popup.
var offline_summary := ""

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
	offline_summary = ""
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

	# Credit mines/collectors for the time the player was away. Buildings are
	# restored above, so their level-scaled per-second rates are available here.
	var last_saved := int(data.get("last_saved_time", 0))
	var elapsed := _offline_elapsed_seconds(last_saved)
	if elapsed >= MIN_OFFLINE_SECONDS:
		_apply_offline_income(manager, elapsed)
	return true

## Whole seconds between `last_saved` (a Unix timestamp) and now; 0 when the
## timestamp is missing/invalid so a fresh village never earns offline income.
func _offline_elapsed_seconds(last_saved: int) -> int:
	if last_saved <= 0:
		return 0
	return int(Time.get_unix_time_from_system()) - last_saved

## Sums the level-scaled production of every active Mine/Elixir Collector over
## the time away (capped at MAX_OFFLINE_SECONDS), credits it to the vault and
## builds a human-readable summary shown when the village loads.
func _apply_offline_income(manager: BuildingManager, elapsed: int) -> void:
	var seconds := mini(elapsed, MAX_OFFLINE_SECONDS)
	if seconds <= 0:
		return
	# Aggregated per-second rates across every producing building.
	var gold_rate := 0
	var elixir_rate := 0
	for b in manager.get_tree().get_nodes_in_group("buildings"):
		if b is Building:
			gold_rate += b.gold_per_sec
			elixir_rate += b.elixir_per_sec
	var gold := gold_rate * seconds
	var elixir := elixir_rate * seconds
	if gold <= 0 and elixir <= 0:
		return
	GameManager.gold += gold
	GameManager.elixir += elix
	GameManager.resource_changed.emit(GameManager.gold, GameManager.elixir)

	var lines: Array[String] = []
	if gold > 0:
		lines.append("Altın Madeni: +%s Altın" % _fmt_number(gold))
	if elixir > 0:
		lines.append("İksir Toplayıcı: +%s İksir" % _fmt_number(elixir))
	var note := "" if elapsed <= MAX_OFFLINE_SECONDS \
			else " (8 sa. üst sınır)"
	offline_summary = "Köyünden ayrı kaldın: %s%s\n%s" % [
			_fmt_duration(seconds), note, "\n".join(lines)]

## Formats seconds as "X sa Y dk" (or minutes/seconds when short).
func _fmt_duration(total_seconds: int) -> String:
	var h := total_seconds / 3600
	var m := (total_seconds % 3600) / 60
	if h > 0:
		return "%d sa %d dk" % [h, m]
	if m > 0:
		return "%d dk" % m
	return "%d sn" % total_seconds

## Formats a positive integer with a "." thousands separator (Turkish style).
func _fmt_number(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		if i > 0 and (s.length() - i) % 3 == 0:
			out = "." + out
	return out

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
	# The player is present now, so the next village load must not treat the
	# time spent in a raid as offline absence and credit extra production.
	data["last_saved_time"] = int(Time.get_unix_time_from_system())
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

## Destroys all buildings, clears the grid and resources, removes the save
## file, then reseeds a fresh village so the load path can be tested.
func reset_village(manager: BuildingManager) -> void:
	offline_summary = ""
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
	offline_summary = ""
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
