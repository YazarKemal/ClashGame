extends Node

## Global resource economy: gold and elixir. Registered as an autoload so any
## node can reference it by name (GameManager).

signal resource_changed(gold: int, elixir: int)

var gold := 500
var elixir := 500

## True while the player is raiding an enemy village. Disables enemy resource
## production so raid buildings never credit the player's real vault.
var in_raid := false

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
