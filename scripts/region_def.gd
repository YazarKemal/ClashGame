class_name RegionDef
extends RefCounted

## Static, designer-authored definition of a Region: a contiguous territory owned
## by a Kingdom (or neutral) that acts as a gameplay ruleset envelope. A Region
## carries its own type, owner, visual placement, neighbors and the ids of the
## Points of Interest inside it. Read-only at runtime — the *discovered* state of
## a region is per-player and lives on GameManager, never here.

enum Type { HOME, CONTESTED, WILDERNESS }

var id := ""
var display_name := ""
var region_type := Type.HOME
## Owning KingdomDef.id, or "" for neutral territory.
var owning_kingdom_id := ""
## World position of the region's centre and its half-extent (for the prototype
## world-map rendering only; the map may render regions however it likes).
var center := Vector2.ZERO
var half := Vector2(100.0, 80.0)
## ids of directly adjacent RegionDefs (future travel graph).
var neighbors: Array[String] = []
## Placeholder for the future region unlock requirement text ("TH seviyesi 2").
var unlock_note := ""
## ids of the POIDefs inside this region.
var poi_ids: Array[String] = []

func _init(p_id: String = "", p_name: String = "", p_type := Type.HOME,
		p_owner: String = "", p_center := Vector2.ZERO) -> void:
	id = p_id
	display_name = p_name
	region_type = p_type
	owning_kingdom_id = p_owner
	center = p_center
