extends Node2D

## Defense (AI raid) scene controller — the disposable battle scene.
##
## Rebuilds a disposable clone of the SAVED player village, hands it to the
## DefenseDirector (gameplay owner), and connects a DefenseUI (presentation).
## Leaving this scene is the only way back to the village; the clone is never
## saved, so the real village is never modified.
##
## Isolation guarantees:
## - Clone buildings are separate nodes in this throwaway scene; damage/destroy
##   here never affects the saved main village, which is only rebuilt from the
##   save file when returning to main.tscn.
## - GameManager.in_raid is set true so clone mines/collectors never produce.
## - No autosave timer exists and no save function is called here, so the clone
##   state is never persisted.

const VILLAGE_SCENE := "res://scenes/main.tscn"

@onready var manager: BuildingManager = $BuildingManager
## Untyped so DefenseDirector's methods resolve without an editor rescan.
@onready var director = $DefenseDirector
## Untyped so DefenseUI's setup/director-calls resolve at runtime.
@onready var ui = $DefenseUI

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
	# Wire the UI BEFORE initialize so it catches the director's synchronous
	# battle_started/state emissions and is ready to mirror live state.
	ui.setup(self, director)
	# Clone is ready; hand the village to the director to start the AI attack.
	director.initialize(manager)

## Leaves the disposable battle scene back to the real village. No save, no
## damage persistence, no reward — _exit_tree restores in_raid automatically.
func return_to_village() -> void:
	get_tree().change_scene_to_file(VILLAGE_SCENE)

## Android system back quits this scene safely whenever the Defense scene is
## active. Because this handler lives only on the Defense root, it never
## interferes with World Map or normal Raid back behavior.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		return_to_village()
		get_viewport().set_input_as_handled()

## Restores in_raid whenever this throwaway scene closes (returning to the
## village, or being freed unexpectedly), so a true value never leaks into the
## normal village's production. Autoloads may already be gone at engine quit, so
## guard against an invalid GameManager.
func _exit_tree() -> void:
	if is_instance_valid(GameManager):
		GameManager.in_raid = _prev_in_raid
