extends Node2D

## Scene root: loads any saved village on startup and keeps an auto-save
## running every 30 seconds.

@onready var manager: BuildingManager = $BuildingManager

var _autosave_timer: Timer

func _ready() -> void:
	GameManager.in_raid = false
	# Coming back to the village (from the world map or a raid) always resets
	# raid routing to the campaign default.
	GameManager.raid_is_campaign = true
	GameManager.raid_return_scene = "res://scenes/main.tscn"
	SaveManager.load_game(manager)
	# First launch (or after a full village reset): no Kingdom chosen yet, so send
	# the player to pick one before they ever reach the village. That flow returns
	# here after persisting the choice. The swap is deferred so it does not run
	# while the scene tree is still finishing this _ready (avoids a busy-tree
	# remove_child error).
	if not GameManager.kingdom_selected():
		get_tree().call_deferred("change_scene_to_file",
				"res://scenes/kingdom_select.tscn")
		return
	# Show what the player earned while away ("" when there was nothing).
	if SaveManager.offline_summary != "":
		FxManager.popup_notice(SaveManager.offline_summary)
	# A Kingdom is chosen, so stamp last_saved_time to now immediately: this makes
	# a Kingdom picked moments ago persistent AND closes the offline double-claim
	# window (an autosave a second later must not treat this reload as absence).
	SaveManager.save_game(manager)
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = 30.0
	_autosave_timer.autostart = true
	add_child(_autosave_timer)
	_autosave_timer.timeout.connect(_autosave)

func _autosave() -> void:
	SaveManager.save_game(manager)
