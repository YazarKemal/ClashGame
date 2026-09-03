class_name ActivityDef
extends RefCounted

## Static, designer-authored definition of an Activity that a Point of Interest
## can host. For D1 the Activity is represented in data and surfaced in the UI
## only — it is NOT executed. target_scene and reward_note are placeholders for
## the future packages that actually run raids / mini-games / gathers.

enum Kind { NONE, STRONGHOLD_RAID, SHRINE_MINIGAME, GATHER }

var id := ""
var kind := Kind.NONE
var display_name := ""
## Future scene path that will run this activity (placeholder).
var target_scene := ""
## Placeholder note for the future reward / world-consequence design.
var reward_note := ""

func _init(p_id: String = "", p_kind := Kind.NONE, p_name: String = "",
		p_target := "", p_reward: String = "") -> void:
	id = p_id
	kind = p_kind
	display_name = p_name
	target_scene = p_target
	reward_note = p_reward
