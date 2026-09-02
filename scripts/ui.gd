extends CanvasLayer

## Top-layer UI: the Build button opens the build menu; picking a building
## starts placement with the Confirm/Cancel buttons in the bottom-right corner.
## The top bar shows the current gold/elixir totals.

@export var manager_path: NodePath

var manager: BuildingManager

@onready var build_button: Button = $BuildButton
@onready var deploy_button: Button = $DeployButton
@onready var build_menu: PanelContainer = $BuildMenu
@onready var tower_button: Button = $BuildMenu/Margin/VBox/TowerButton
@onready var mine_button: Button = $BuildMenu/Margin/VBox/MineButton
@onready var town_hall_button: Button = $BuildMenu/Margin/VBox/TownHallButton
@onready var wall_button: Button = $BuildMenu/Margin/VBox/WallButton
@onready var close_menu_button: Button = $BuildMenu/Margin/VBox/CloseMenuButton
@onready var confirm_button: Button = $PlacementButtons/ConfirmButton
@onready var cancel_button: Button = $PlacementButtons/CancelButton
@onready var gold_label: Label = $TopBar/Margin/HBox/GoldLabel
@onready var elixir_label: Label = $TopBar/Margin/HBox/ElixirLabel
@onready var building_panel: PanelContainer = $BuildingPanel
@onready var panel_title: Label = $BuildingPanel/Margin/VBox/TitleLabel
@onready var panel_hp: Label = $BuildingPanel/Margin/VBox/HpLabel
@onready var upgrade_button: Button = $BuildingPanel/Margin/VBox/UpgradeButton
@onready var close_panel_button: Button = $BuildingPanel/Margin/VBox/ClosePanelButton

var _selected_building: Building = null

func _ready() -> void:
	manager = get_node(manager_path)
	manager.placement_started.connect(_on_placement_started)
	manager.placement_ended.connect(_on_placement_ended)

	build_button.pressed.connect(_on_build_pressed)
	deploy_button.pressed.connect(_on_deploy_pressed)
	tower_button.pressed.connect(_start_tower_placement)
	mine_button.pressed.connect(_start_mine_placement)
	town_hall_button.pressed.connect(_start_town_hall_placement)
	wall_button.pressed.connect(_start_wall_placement)
	close_menu_button.pressed.connect(_close_build_menu)
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	close_panel_button.pressed.connect(_on_close_panel)

	manager.building_selected.connect(_on_building_selected)

	confirm_button.hide()
	cancel_button.hide()
	build_menu.hide()
	building_panel.hide()

	GameManager.resource_changed.connect(_update_resources)
	_update_resources(GameManager.gold, GameManager.elixir)

func _update_resources(gold: int, elixir: int) -> void:
	gold_label.text = "Altın: %d" % gold
	elixir_label.text = "İksir: %d" % elixir
	# Keep the upgrade button's affordability in sync as gold/elixir change.
	_refresh_panel()

func _on_build_pressed() -> void:
	build_button.hide()
	build_menu.show()

func _on_deploy_pressed() -> void:
	if manager.spawn_mode:
		manager.set_spawn_mode(false)
		deploy_button.text = "Asker Bırak"
	else:
		manager.set_spawn_mode(true)
		deploy_button.text = "Kapat"

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

func _start_wall_placement() -> void:
	manager.start_placement(Building.Type.WALL)
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

func _on_building_selected(b: Building) -> void:
	_disconnect_selected()
	_selected_building = b
	if _selected_building == null:
		building_panel.hide()
		return
	_selected_building.hp_changed.connect(_on_building_hp_changed)
	_selected_building.upgraded.connect(_on_building_upgraded)
	building_panel.show()
	_refresh_panel()

func _disconnect_selected() -> void:
	if _selected_building == null:
		return
	if _selected_building.hp_changed.is_connected(_on_building_hp_changed):
		_selected_building.hp_changed.disconnect(_on_building_hp_changed)
	if _selected_building.upgraded.is_connected(_on_building_upgraded):
		_selected_building.upgraded.disconnect(_on_building_upgraded)

func _on_building_hp_changed(_current: int, _max_hp: int) -> void:
	_refresh_panel()

func _on_building_upgraded(_level: int) -> void:
	_refresh_panel()

func _refresh_panel() -> void:
	if _selected_building == null:
		return
	var b := _selected_building
	panel_title.text = "%s (Sv. %d)" % [b.building_name, b.level]
	panel_hp.text = "HP: %d/%d" % [b.hp, b.max_hp]
	if b.level >= b.max_level:
		upgrade_button.text = "Maksimum"
		upgrade_button.disabled = true
	else:
		var cur_word := "Altın" if b.currency == "gold" else "İksir"
		var cost := b.upgrade_gold_cost() + b.upgrade_elixir_cost()
		upgrade_button.text = "Yükselt (%d %s)" % [cost, cur_word]
		upgrade_button.disabled = not _can_afford(b)

func _can_afford(b: Building) -> bool:
	return GameManager.gold >= b.upgrade_gold_cost() \
			and GameManager.elixir >= b.upgrade_elixir_cost()

func _on_upgrade_pressed() -> void:
	if _selected_building == null:
		return
	if not _selected_building.upgrade():
		_refresh_panel()

func _on_close_panel() -> void:
	_disconnect_selected()
	_selected_building = null
	building_panel.hide()
