class_name POIDef
extends RefCounted

## Static, designer-authored definition of a Point of Interest: a concrete,
## addressable place inside a Region that will eventually host an Activity. The
## POI itself is pure data + identity; whether the player has discovered it or
## already subdued/depleted it is per-player runtime state kept on GameManager.

enum Type { HOME, STRONGHOLD, SHRINE, GATHER }

var id := ""
var display_name := ""
var region_id := ""
var poi_type := Type.GATHER
## ActivityDef.id that this POI will host ("" when none, e.g. the home POI).
var activity_id := ""
## World position on the prototype world map.
var position := Vector2.ZERO
## Short human explanation used by the world map info panel.
var note := ""

func _init(p_id: String = "", p_name: String = "", p_region: String = "",
		p_type := Type.GATHER, p_activity: String = "",
		p_pos := Vector2.ZERO, p_note := "") -> void:
	id = p_id
	display_name = p_name
	region_id = p_region
	poi_type = p_type
	activity_id = p_activity
	position = p_pos
	note = p_note
