extends CanvasLayer

## Top-layer UI: the Build button opens the build menu; picking a building
## starts placement with the Confirm/Cancel buttons in the bottom-right corner.
## The top bar shows the current gold/elixir totals.

@export var manager_path: NodePath

var manager: BuildingManager

@onready var build_button: Button = $BuildButton
@onready var build_menu: PanelContainer = $BuildMenu
@onready var tower_button: Button = $BuildMenu/Margin/VBox/TowerButton
@onready var mine_button: Button = $BuildMenu/Margin/VBox/MineButton
@onready var town_hall_button: Button = $BuildMenu/Margin/VBox/TownHallButton
@onready var close_menu_button: Button = $BuildMenu/Margin/VBox/CloseMenuButton
@onready var confirm_button: Button = $PlacementButtons/ConfirmButton
@onready var cancel_button: Button = $PlacementButtons/CancelButton
@onready var gold_label: Label = $TopBar/Margin/HBox/GoldLabel
@onready var elixir_label: Label = $TopBar/Margin/HBox/ElixirLabel

func _ready() -> void:
	manager = get_node(manager_path)
	manager.placement_started.connect(_on_placement_started)
	manager.placement_ended.connect(_on_placement_ended)

	build_button.pressed.connect(_on_build_pressed)
	tower_button.pressed.connect(_start_tower_placement)
	mine_button.pressed.connect(_start_mine_placement)
	town_hall_button.pressed.connect(_start_town_hall_placement)
	close_menu_button.pressed.connect(_close_build_menu)
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)

	confirm_button.hide()
	cancel_button.hide()
	build_menu.hide()

	GameManager.resource_changed.connect(_update_resources)
	_update_resources(GameManager.gold, GameManager.elixir)

func _update_resources(gold: int, elixir: int) -> void:
	gold_label.text = "Altın: %d" % gold
	elixir_label.text = "İksir: %d" % elixir

func _on_build_pressed() -> void:
	build_button.hide()
	build_menu.show()

func _close_build_menu() -> void:
	build_menu.hide()
	build_button.show()

func _start_tower_placement() -> void:
	manager.start_placement(Building.Type.TOWER)
	build_menu.hide()
	build_button.show()

func _start_mine_placement() -> void:
	manager.start_placement(Building.Type.MINE)
	build_menu.hide()
	build_button.show()

func _start_town_hall_placement() -> void:
	manager.start_placement(Building.Type.TOWN_HALL)
	build_menu.hide()
	build_button.show()

func _on_placement_started() -> void:
	confirm_button.show()
	cancel_button.show()

func _on_placement_ended(_success: bool) -> void:
	confirm_button.hide()
	cancel_button.hide()
	build_menu.hide()
	build_button.show()

func _on_confirm_pressed() -> void:
	manager.confirm_placement()

func _on_cancel_pressed() -> void:
	manager.cancel_placement()
