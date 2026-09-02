extends CanvasLayer

## In-raid HUD: loot pool/gained readouts, troop selector, an "end battle"
## button and the result window shown when the raid concludes.

## Untyped so raid.gd's script methods resolve at runtime.
var _raid = null
var _manager: BuildingManager = null

@onready var pool_label: Label = $TopBar/Margin/HBox/PoolLabel
@onready var gained_label: Label = $TopBar/Margin/HBox/GainedLabel
@onready var end_button: Button = $EndBattleButton
@onready var barbar_button: Button = $TroopBar/BarbarButton
@onready var archer_button: Button = $TroopBar/ArcherButton
@onready var giant_button: Button = $TroopBar/GiantButton
@onready var result_window: PanelContainer = $ResultWindow
@onready var title_label: Label = $ResultWindow/Margin/VBox/TitleLabel
@onready var destruction_label: Label = $ResultWindow/Margin/VBox/DestructionLabel
@onready var stars_label: Label = $ResultWindow/Margin/VBox/StarsLabel
@onready var loot_label: Label = $ResultWindow/Margin/VBox/LootLabel
@onready var return_button: Button = $ResultWindow/Margin/VBox/ReturnHomeButton

func setup(raid: Node, mgr: BuildingManager) -> void:
	_raid = raid
	_manager = mgr
	end_button.pressed.connect(_raid._end_battle)
	return_button.pressed.connect(_raid._return_home)
	barbar_button.pressed.connect(_select_barbarian)
	archer_button.pressed.connect(_select_archer)
	giant_button.pressed.connect(_select_giant)
	GameManager.army_changed.connect(_refresh_troop_bar)
	result_window.hide()
	_refresh_troop_bar()

func set_loot_pool(gold: int, elixir: int) -> void:
	pool_label.text = "Havuz: %d G / %d İ" % [gold, elixir]

func update_gained(gold: int, elixir: int) -> void:
	gained_label.text = "Kazanılan: %d G / %d İ" % [gold, elixir]

func show_result(pct: int, stars: int, gold: int, elixir: int) -> void:
	result_window.show()
	title_label.text = "Zafer!" if pct > 0 else "Yenilgi!"
	destruction_label.text = "Yıkım: %d%%" % pct
	stars_label.text = "Yıldız: %s" % ("★".repeat(stars) + "☆".repeat(maxi(3 - stars, 0)))
	loot_label.text = "Ganimet: %d G / %d İ" % [gold, elixir]

func _select_barbarian() -> void:
	_manager.selected_unit_type = Unit.Type.BARBARIAN
	_refresh_troop_bar()

func _select_archer() -> void:
	_manager.selected_unit_type = Unit.Type.ARCHER
	_refresh_troop_bar()

func _select_giant() -> void:
	_manager.selected_unit_type = Unit.Type.GIANT
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
				if _manager.selected_unit_type == t else Color(0.6, 0.6, 0.6, 1)
