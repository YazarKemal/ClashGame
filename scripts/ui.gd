extends CanvasLayer

## Top-layer UI: the Build button opens the build menu; picking a building
## starts placement with the Confirm/Cancel buttons in the bottom-right corner.
## The top bar shows the current gold/elixir totals.

@export var manager_path: NodePath

var manager: BuildingManager

@onready var build_button: Button = $BuildButton
@onready var deploy_button: Button = $DeployButton
@onready var reset_button: Button = $ResetButton
@onready var expedition_button: Button = $ExpeditionButton
@onready var attack_button: Button = $AttackButton
@onready var build_menu: PanelContainer = $BuildMenu
@onready var tower_button: Button = $BuildMenu/Margin/VBox/TowerButton
@onready var mine_button: Button = $BuildMenu/Margin/VBox/MineButton
@onready var town_hall_button: Button = $BuildMenu/Margin/VBox/TownHallButton
@onready var wall_button: Button = $BuildMenu/Margin/VBox/WallButton
@onready var elixir_collector_button: Button = $BuildMenu/Margin/VBox/ElixirCollectorButton
@onready var barracks_button: Button = $BuildMenu/Margin/VBox/BarracksButton
@onready var army_camp_button: Button = $BuildMenu/Margin/VBox/ArmyCampButton
@onready var close_menu_button: Button = $BuildMenu/Margin/VBox/CloseMenuButton
@onready var confirm_button: Button = $PlacementButtons/ConfirmButton
@onready var cancel_button: Button = $PlacementButtons/CancelButton
@onready var gold_label: Label = $TopBar/Margin/HBox/GoldLabel
@onready var elixir_label: Label = $TopBar/Margin/HBox/ElixirLabel
@onready var building_panel: PanelContainer = $BuildingPanel
@onready var panel_title: Label = $BuildingPanel/Margin/VBox/TitleLabel
@onready var panel_hp: Label = $BuildingPanel/Margin/VBox/HpLabel
@onready var train_button: Button = $BuildingPanel/Margin/VBox/TrainButton
@onready var upgrade_button: Button = $BuildingPanel/Margin/VBox/UpgradeButton
@onready var close_panel_button: Button = $BuildingPanel/Margin/VBox/ClosePanelButton
@onready var troop_bar: HBoxContainer = $TroopBar
@onready var barbar_button: Button = $TroopBar/BarbarButton
@onready var archer_button: Button = $TroopBar/ArcherButton
@onready var giant_button: Button = $TroopBar/GiantButton
@onready var train_window: PanelContainer = $TrainWindow
@onready var army_label: Label = $TrainWindow/Margin/VBox/ArmyLabel
@onready var barbar_train_button: Button = $TrainWindow/Margin/VBox/BarbarTrainButton
@onready var archer_train_button: Button = $TrainWindow/Margin/VBox/ArcherTrainButton
@onready var giant_train_button: Button = $TrainWindow/Margin/VBox/GiantTrainButton
@onready var close_train_button: Button = $TrainWindow/Margin/VBox/CloseTrainButton
@onready var campaign_panel: PanelContainer = $CampaignPanel
@onready var level1_button: Button = $CampaignPanel/Margin/VBox/Level1Button
@onready var level2_button: Button = $CampaignPanel/Margin/VBox/Level2Button
@onready var level3_button: Button = $CampaignPanel/Margin/VBox/Level3Button
@onready var saldir_button: Button = $CampaignPanel/Margin/VBox/HBox/SaldirButton
@onready var geri_button: Button = $CampaignPanel/Margin/VBox/HBox/GeriButton

var _selected_building: Building = null
var _selected_level := 1

func _ready() -> void:
	manager = get_node(manager_path)
	manager.placement_started.connect(_on_placement_started)
	manager.placement_ended.connect(_on_placement_ended)

	build_button.pressed.connect(_on_build_pressed)
	deploy_button.pressed.connect(_on_deploy_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	expedition_button.pressed.connect(_on_expedition_pressed)
	attack_button.pressed.connect(_on_attack_pressed)
	tower_button.pressed.connect(_start_tower_placement)
	mine_button.pressed.connect(_start_mine_placement)
	town_hall_button.pressed.connect(_start_town_hall_placement)
	wall_button.pressed.connect(_start_wall_placement)
	elixir_collector_button.pressed.connect(_start_elixir_collector_placement)
	barracks_button.pressed.connect(_start_barracks_placement)
	army_camp_button.pressed.connect(_start_army_camp_placement)
	close_menu_button.pressed.connect(_close_build_menu)
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	close_panel_button.pressed.connect(_on_close_panel)
	train_button.pressed.connect(_on_train_pressed)
	barbar_train_button.pressed.connect(_on_train_barbar_pressed)
	archer_train_button.pressed.connect(_on_train_archer_pressed)
	giant_train_button.pressed.connect(_on_train_giant_pressed)
	close_train_button.pressed.connect(_on_close_train_pressed)
	barbar_button.pressed.connect(_on_barbar_pressed)
	archer_button.pressed.connect(_on_archer_pressed)
	giant_button.pressed.connect(_on_giant_pressed)
	level1_button.pressed.connect(_select_level.bind(1))
	level2_button.pressed.connect(_select_level.bind(2))
	level3_button.pressed.connect(_select_level.bind(3))
	saldir_button.pressed.connect(_on_saldir_pressed)
	geri_button.pressed.connect(_on_campaign_geri_pressed)

	manager.building_selected.connect(_on_building_selected)

	confirm_button.hide()
	cancel_button.hide()
	build_menu.hide()
	building_panel.hide()
	train_window.hide()
	troop_bar.hide()
	campaign_panel.hide()

	GameManager.resource_changed.connect(_update_resources)
	GameManager.army_changed.connect(_refresh_troop_bar)
	GameManager.level_stars_changed.connect(_refresh_campaign)
	_update_resources(GameManager.gold, GameManager.elixir)
	_refresh_troop_bar()

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
		troop_bar.hide()
	else:
		manager.set_spawn_mode(true)
		deploy_button.text = "Kapat"
		troop_bar.show()
		_refresh_troop_bar()

func _on_reset_pressed() -> void:
	SaveManager.reset_village(manager)

## Saves the village (so the offline timer resets), resets raid routing to the
## campaign default, then opens the macro world map.
func _on_expedition_pressed() -> void:
	SaveManager.save_game(manager)
	GameManager.raid_is_campaign = true
	GameManager.raid_return_scene = "res://scenes/main.tscn"
	get_tree().change_scene_to_file("res://scenes/world_map.tscn")

## Opens the campaign selection panel instead of jumping straight into a raid.
func _on_attack_pressed() -> void:
	build_button.hide()
	build_menu.hide()
	campaign_panel.show()
	_refresh_campaign()

## Selects a playable campaign level (locked levels ignore the tap).
func _select_level(level: int) -> void:
	if not GameManager.level_unlocked(level):
		return
	_selected_level = level
	_refresh_campaign()

## Rebuilds the level list: name + best-star row, locked when the previous
## level has no star, and a highlight on the selected entry.
func _refresh_campaign() -> void:
	var names: Array = RaidManager.level_names()
	for i in range(3):
		var level := i + 1
		var btn: Button = [level1_button, level2_button, level3_button][i]
		if GameManager.level_unlocked(level):
			var stars := GameManager.best_stars_for(level)
			btn.text = "Seviye %d: %s  %s" % [level, names[i],
					"★".repeat(stars) + "☆".repeat(maxi(3 - stars, 0))]
			btn.disabled = false
		else:
			btn.text = "Seviye %d: %s  🔒" % [level, names[i]]
			btn.disabled = true
		btn.modulate = Color(1, 1, 1, 1) if level == _selected_level \
				else Color(0.75, 0.75, 0.75, 1)

## Saves the village and launches the selected level's raid.
func _on_saldir_pressed() -> void:
	if not GameManager.level_unlocked(_selected_level):
		return
	GameManager.selected_level = _selected_level
	SaveManager.save_game(manager)
	get_tree().change_scene_to_file("res://scenes/raid.tscn")

## Closes the campaign panel and returns to the village controls.
func _on_campaign_geri_pressed() -> void:
	campaign_panel.hide()
	build_button.show()

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

func _start_elixir_collector_placement() -> void:
	manager.start_placement(Building.Type.ELIXIR_COLLECTOR)
	build_menu.hide()
	build_button.show()

func _start_barracks_placement() -> void:
	manager.start_placement(Building.Type.BARRACKS)
	build_menu.hide()
	build_button.show()

func _start_army_camp_placement() -> void:
	manager.start_placement(Building.Type.ARMY_CAMP)
	build_menu.hide()
	build_button.show()

func _on_placement_started() -> void:
	confirm_button.show()
	cancel_button.show()
	troop_bar.hide()
	train_window.hide()
	campaign_panel.hide()

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
		train_window.hide()
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
	train_button.visible = b.building_type == Building.Type.BARRACKS
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
	if _selected_building.upgrade():
		SaveManager.save_game(manager)
	else:
		_refresh_panel()

func _on_close_panel() -> void:
	_disconnect_selected()
	_selected_building = null
	building_panel.hide()
	train_window.hide()

func _on_barbar_pressed() -> void:
	_select_troop(Unit.Type.BARBARIAN)

func _on_archer_pressed() -> void:
	_select_troop(Unit.Type.ARCHER)

func _on_giant_pressed() -> void:
	_select_troop(Unit.Type.GIANT)

func _select_troop(t: Unit.Type) -> void:
	manager.selected_unit_type = t
	_refresh_troop_bar()

## Shows each troop's ready count and grays out buttons with none available.
func _refresh_troop_bar() -> void:
	_set_troop_button(barbar_button, Unit.Type.BARBARIAN, "Barbar")
	_set_troop_button(archer_button, Unit.Type.ARCHER, "Okçu")
	_set_troop_button(giant_button, Unit.Type.GIANT, "Dev")

func _set_troop_button(btn: Button, t: Unit.Type, troop_name: String) -> void:
	var count := GameManager.army_count(t)
	btn.text = "%s (x%d)" % [troop_name, count]
	btn.disabled = count <= 0
	if count <= 0:
		btn.modulate = Color(0.4, 0.4, 0.4, 1)
	else:
		btn.modulate = Color(1, 1, 1, 1) \
				if manager.selected_unit_type == t else Color(0.6, 0.6, 0.6, 1)

func _on_train_pressed() -> void:
	building_panel.hide()
	train_window.show()
	_refresh_train_window()

func _on_close_train_pressed() -> void:
	train_window.hide()
	if _selected_building != null:
		building_panel.show()

func _on_train_barbar_pressed() -> void:
	GameManager.train_troop(Unit.Type.BARBARIAN)
	_refresh_train_window()

func _on_train_archer_pressed() -> void:
	GameManager.train_troop(Unit.Type.ARCHER)
	_refresh_train_window()

func _on_train_giant_pressed() -> void:
	GameManager.train_troop(Unit.Type.GIANT)
	_refresh_train_window()

func _refresh_train_window() -> void:
	army_label.text = "Ordu: %d / %d" % [GameManager.army_total(), GameManager.army_capacity()]
