extends Node2D

## Defense (AI raid) scene controller — Package 1 foundation.
##
## Rebuilds a disposable clone of the SAVED player village, hands it to the
## DefenseDirector, and lets the AI attack it. The clone never touches the real
## village.
##
## Isolation guarantees:
## - Clone buildings are separate nodes in this throwaway scene; damage/destroy
##   here never affects the saved main village, which is only rebuilt from the
##   save file when returning to main.tscn.
## - GameManager.in_raid is set true so clone mines/collectors never produce.
## - No autosave timer exists and no save function is called here, so the clone
##   state is never persisted.

@onready var manager: BuildingManager = $BuildingManager
## Untyped so DefenseDirector's methods resolve without an editor rescan.
@onready var director = $DefenseDirector

var cloned_buildings := 0
## in_raid value on entry, so _exit_tree can restore it exactly (normally false,
## since defense is only entered from the real village).
var _prev_in_raid := false

func _ready() -> void:
	# Remember the real village's state before locking production for the clone.
	_prev_in_raid = GameManager.in_raid
	# Lock production so the clone's collectors/mines do not feed the real vault.
	GameManager.in_raid = true
	cloned_buildings = SaveManager.spawn_saved_buildings_into(manager)
	if cloned_buildings == 0:
		push_warning("Savunma köyü boş: kayıtlı bina bulunamadı.")
	# Clone is ready; hand the village to the director to start the AI attack.
	director.initialize(manager)

## Restores in_raid whenever this throwaway scene closes (returning to the
## village, or being freed unexpectedly), so a true value never leaks into the
## normal village's production. Autoloads may already be gone at engine quit, so
## guard against an invalid GameManager.
func _exit_tree() -> void:
	if is_instance_valid(GameManager):
		GameManager.in_raid = _prev_in_raid
