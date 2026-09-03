class_name KingdomDef
extends RefCounted

## Static, designer-authored definition of a playable Kingdom. Read-only at
## runtime; players reference a Kingdom by id (GameManager.kingdom_id), never by
## carrying its data around. Identity is IDENTITY + STARTING REGION, deliberately
## with no stat bonuses — a Kingdom is who you are and where you begin, not a
## multiplier.

var id := ""
var display_name := ""
var color := Color.WHITE
var crest_id := ""            # placeholder reference for future visual identity
var starting_region_id := ""

func _init(p_id: String = "", p_name: String = "", p_color := Color.WHITE,
		p_crest: String = "", p_start_region: String = "") -> void:
	id = p_id
	display_name = p_name
	color = p_color
	crest_id = p_crest
	starting_region_id = p_start_region
