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

## Trained troops ready for deployment: Unit.Type (int) -> trained count.
var army_data: Dictionary = {}

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
