extends Node2D

## Scene root: loads any saved village on startup and keeps an auto-save
## running every 30 seconds.

@onready var manager: BuildingManager = $BuildingManager

var _autosave_timer: Timer

func _ready() -> void:
	GameManager.in_raid = false
	SaveManager.load_game(manager)
	# Show what the player earned while away ("" when there was nothing).
	if SaveManager.offline_summary != "":
		FxManager.popup_notice(SaveManager.offline_summary)
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = 30.0
	_autosave_timer.autostart = true
	add_child(_autosave_timer)
	_autosave_timer.timeout.connect(_autosave)

func _autosave() -> void:
	SaveManager.save_game(manager)
