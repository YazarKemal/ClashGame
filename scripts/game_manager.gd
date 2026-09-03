extends Node

## Global resource economy: gold and elixir. Registered as an autoload so any
## node can reference it by name (GameManager).

signal resource_changed(gold: int, elixir: int)
signal army_changed

var gold := 500
var elixir := 500

## True while the player is raiding an enemy village. Disables enemy resource
## production so raid buildings never credit the player's real vault.
var in_raid := false

## --- Macro world map state (shared between the village and world scenes) ---

## Army icon position on the world map. Persists across scene switches so a
## world-city raid returns the player to the same spot. Zero means "not set yet".
var world_army_pos := Vector2.ZERO

## --- Raid routing: campaign village attack vs a world-map city attack ---
## Both flows reuse raid.tscn; these fields tell it which one is running and
## where to send the player when the battle ends.

## True = campaign PvE level (records stars, returns to the village).
## False = a world-map faction city attack (no star recording, returns to the
## map). Must be reset to true whenever entering a campaign raid.
var raid_is_campaign := true

## Enemy layout (spawns + loot pool) used for non-campaign city attacks.
var raid_layout: Dictionary = {}

## Scene to return to when a non-campaign raid ends.
var raid_return_scene := "res://scenes/main.tscn"

## --- Transient stronghold-raid context (D2) -----------------------------------
## While a Stronghold POI raid runs these say it is a stronghold raid and which
## POI to subdue on a win. They are UNSAVED (never serialized) and are cleared by
## finish_stronghold_raid once the battle resolves, so the world consequence is
## applied exactly once and can never be duplicated by a reload or autosave.

## True while the running raid is a Stronghold POI raid (not a campaign level).
var raid_is_stronghold := false
## The Stronghold POI id this raid targets ("" when not a stronghold raid).
var stronghold_poi_id := ""

## Trained troops ready for deployment: Unit.Type (int) -> trained count.
var army_data: Dictionary = {}

## Campaign level currently being raided. Set by the campaign UI before the
## raid scene loads; read by raid.gd to build the matching enemy village.
var selected_level := 1

## Best stars earned per campaign level: level (int) -> 0..3.
var best_stars: Dictionary = {}

signal level_stars_changed

## --- Kingdom & world discovery (D1 foundation) -------------------------------
## These fields are the per-player portion of the world: which Kingdom was chosen
## and which Regions/POIs the player has discovered. Static definitions for the
## world itself live on the WorldData autoload; this state is never mixed with
## them. kingdom_id == "" means no Kingdom chosen yet (first launch / after a
## full reset).

## Chosen KingdomDef.id, or "" before first-launch selection.
var kingdom_id := ""
## RegionDef.id -> true, once the player has seen that region.
var discovered_regions := {}
## POIDef.id -> true, once the player has seen that POI.
var discovered_pois := {}
## POIDef.id -> { "subdued": bool, "depleted": bool } runtime world state.
## Stored per POI (only for POIs that can be subdued/depleted).
var poi_state := {}

## True once a Kingdom has been chosen (selection persists in the save).
func kingdom_selected() -> bool:
	return kingdom_id != ""

## Picks a Kingdom for this player: validates the id against WorldData and seeds
## discovery of that Kingdom's own regions + POIs. Returns false if unknown.
func choose_kingdom(kid: String) -> bool:
	var k := WorldData.kingdom(kid)
	if k == null:
		return false
	kingdom_id = kid
	_seed_kingdom_discovery(kid)
	return true

## Discards all world choice + discovery state (used by a full village reset so
## the player is offered Kingdom selection again on the next load).
func clear_world_state() -> void:
	kingdom_id = ""
	discovered_regions = {}
	discovered_pois = {}
	poi_state = {}

func _seed_kingdom_discovery(kid: String) -> void:
	for r in WorldData.regions_by_kingdom(kid):
		discover_region(r.id)
		for p in WorldData.pois_of_region(r.id):
			discover_poi(p.id)

func region_discovered(id: String) -> bool:
	return discovered_regions.has(id)

func discover_region(id: String) -> void:
	if WorldData.region(id) != null:
		discovered_regions[id] = true

func poi_discovered(id: String) -> bool:
	return discovered_pois.has(id)

func discover_poi(id: String) -> void:
	if WorldData.poi(id) != null:
		discovered_pois[id] = true

## Runtime state helpers for a POI (returns sane defaults when never recorded).
func poi_subdued(id: String) -> bool:
	var st: Dictionary = poi_state.get(id, {})
	return bool(st.get("subdued", false))

func poi_depleted(id: String) -> bool:
	var st: Dictionary = poi_state.get(id, {})
	return bool(st.get("depleted", false))

func set_poi_subdued(id: String, value: bool) -> void:
	var st: Dictionary = poi_state.get(id, {})
	st["subdued"] = value
	poi_state[id] = st

func set_poi_depleted(id: String, value: bool) -> void:
	var st: Dictionary = poi_state.get(id, {})
	st["depleted"] = value
	poi_state[id] = st

## Resolves a finished Stronghold raid: on a win the targeted POI is marked
## subdued (this is the world consequence), then the transient raid context is
## cleared so the effect is applied exactly once. Lives here (the activity/world
## layer), not in raid.gd, per the D2 design. Safe to call from any raid flow;
## it is a no-op when no stronghold raid context is present.
func finish_stronghold_raid(won: bool) -> void:
	if won and stronghold_poi_id != "":
		set_poi_subdued(stronghold_poi_id, true)
	raid_is_stronghold = false
	stronghold_poi_id = ""

## Best stars earned for a level (0 when never attempted).
func best_stars_for(level: int) -> int:
	return int(best_stars.get(level, 0))

## Keeps the highest star count achieved for a level and emits on improvement.
func record_level_result(level: int, stars: int) -> void:
	if stars > best_stars_for(level):
		best_stars[level] = stars
		level_stars_changed.emit()

## A level is playable when it is the first level or the previous level earned
## at least one star.
func level_unlocked(level: int) -> bool:
	return level <= 1 or best_stars_for(level - 1) >= 1

## Adds resources and emits the change.
func add_resources(amount_gold: int, amount_elixir: int) -> void:
	gold += amount_gold
	elixir += amount_elixir
	resource_changed.emit(gold, elixir)

## Spends the given amounts only if the player can afford both. Returns false
## (and changes nothing) when insufficient.
func spend_resources(amount_gold: int, amount_elixir: int) -> bool:
	if gold < amount_gold or elixir < amount_elixir:
		return false
	gold -= amount_gold
	elixir -= amount_elixir
	resource_changed.emit(gold, elixir)
	return true

## Trained count for a troop type.
func army_count(t: Unit.Type) -> int:
	return int(army_data.get(int(t), 0))

## Total trained troops (in slots).
func army_total() -> int:
	var n := 0
	for k in army_data:
		n += int(army_data[k])
	return n

## Max army size, derived from the number of army camps in the current village.
func army_capacity() -> int:
	var camps := 0
	if get_tree() == null:
		return 0
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Building and b.building_type == Building.Type.ARMY_CAMP:
			camps += 1
	return camps * 30

## Trains one troop: charges its elixir cost and adds it to the ready army,
## unless the army is already at camp capacity. Returns false when blocked.
func train_troop(t: Unit.Type) -> bool:
	var slots := Unit.slots_for(t)
	if army_total() + slots > army_capacity():
		return false
	if not spend_resources(0, Unit.cost_for(t)):
		return false
	army_data[int(t)] = army_count(t) + 1
	army_changed.emit()
	return true

## Removes one ready troop of the given type for deployment. Returns false when
## none are available.
func consume_troop(t: Unit.Type) -> bool:
	if army_count(t) <= 0:
		return false
	army_data[int(t)] = army_count(t) - 1
	army_changed.emit()
	return true
