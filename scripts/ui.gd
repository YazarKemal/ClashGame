extends CanvasLayer

## Top-layer UI: the Build button starts placement; while placing, the
## Confirm/Cancel buttons appear in the bottom-right corner.

const DEFENSE_TOWER_SCENE: PackedScene = preload("res://scenes/building.tscn")
const DEFENSE_TOWER_NAME := "Savunma Kulesi"
const DEFENSE_TOWER_SIZE := 2

@export var manager_path: NodePath

var manager: BuildingManager

@onready var build_button: Button = $BuildButton
@onready var confirm_button: Button = $PlacementButtons/ConfirmButton
@onready var cancel_button: Button = $PlacementButtons/CancelButton

func _ready() -> void:
	manager = get_node(manager_path)
	manager.placement_started.connect(func() -> void:
		confirm_button.show()
		cancel_button.show())
	manager.placement_ended.connect(func(_success: bool) -> void:
		confirm_button.hide()
		cancel_button.hide())
	build_button.pressed.connect(_on_build_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	confirm_button.hide()
	cancel_button.hide()

func _on_build_pressed() -> void:
	manager.start_placement(DEFENSE_TOWER_SCENE, DEFENSE_TOWER_NAME, DEFENSE_TOWER_SIZE)

func _on_confirm_pressed() -> void:
	manager.confirm_placement()

func _on_cancel_pressed() -> void:
	manager.cancel_placement()
