extends Node

## Autoload singleton (WorldData) that owns the STATIC, designer-authored world:
## Kingdoms, Regions, Points of Interest and Activities. Everything here is
## read-only at runtime and never mixed with per-player state (which lives on
## GameManager) or the save file.
##
## D1 ships a small demo world: two playable Kingdoms (east/west), each with a
## HOME region and a CONTESTED border region, plus a neutral WILDERNESS between
## them. Regions are authored along a single east-west axis so the map reads as a
## world with locked/unexplored territory, not as a flat list of raid buttons.

const NEUTRAL_COLOR := Color(0.52, 0.58, 0.52, 1.0)

var _kingdoms: Array[KingdomDef] = []
var _regions: Array[RegionDef] = []
var _pois: Array[POIDef] = []
var _activities: Array[ActivityDef] = []

var _kingdom_by_id := {}
var _region_by_id := {}
var _poi_by_id := {}
var _activity_by_id := {}

func _ready() -> void:
	_build_activities()
	_build_kingdoms()
	_build_regions()
	_build_pois()
	_index()

# --- Authoring (designer-facing) ----------------------------------------------

func _build_activities() -> void:
	_activities = [
		ActivityDef.new("stronghold_raid", ActivityDef.Kind.STRONGHOLD_RAID,
			"Kale Baskını", "res://scenes/raid.tscn",
			"Gelecek paket: sınırlı ganimet + dünya sonucu (kaleyi bastırır)."),
		ActivityDef.new("shrine_minigame", ActivityDef.Kind.SHRINE_MINIGAME,
			"Mabet Sınavı", "",
			"Gelecek paket: minigame -> ün/bölgesel kalıcı etki."),
		ActivityDef.new("gather", ActivityDef.Kind.GATHER,
			"Kaynak Keşfi", "",
			"Gelecek paket: depolama-üstlü, tükenebilir kaynak toplama."),
	]

func _build_kingdoms() -> void:
	_kingdoms = [
		KingdomDef.new("kingdom_red", "Kızıl Ateş", Color(0.85, 0.24, 0.2),
			"crest_fire", "region_red_home"),
		KingdomDef.new("kingdom_blue", "Mavi Deniz", Color(0.25, 0.52, 0.9),
			"crest_wave", "region_blue_home"),
	]

func _build_regions() -> void:
	_regions = [
		RegionDef.new("region_red_home", "Kızıl Ana Bölge",
			RegionDef.Type.HOME, "kingdom_red", Vector2(-540, 0)),
		RegionDef.new("region_red_border", "Kızıl Sınır",
			RegionDef.Type.CONTESTED, "kingdom_red", Vector2(-320, 0)),
		RegionDef.new("region_wilderness", "Serbest Topraklar",
			RegionDef.Type.WILDERNESS, "", Vector2(0, 0)),
		RegionDef.new("region_blue_border", "Mavi Sınır",
			RegionDef.Type.CONTESTED, "kingdom_blue", Vector2(320, 0)),
		RegionDef.new("region_blue_home", "Mavi Ana Bölge",
			RegionDef.Type.HOME, "kingdom_blue", Vector2(540, 0)),
	]
	# Authoring notes (region_type is set above; only author extra fields here).
	var red_home: RegionDef = _regions[0]
	red_home.half = Vector2(130, 90)
	red_home.neighbors = ["region_red_border"]
	var red_border: RegionDef = _regions[1]
	red_border.half = Vector2(120, 110)
	red_border.neighbors = ["region_red_home", "region_wilderness"]
	red_border.unlock_note = ""
	var wilderness: RegionDef = _regions[2]
	wilderness.half = Vector2(120, 110)
	wilderness.neighbors = ["region_red_border", "region_blue_border"]
	var blue_border: RegionDef = _regions[3]
	blue_border.half = Vector2(120, 110)
	blue_border.neighbors = ["region_wilderness", "region_blue_home"]
	var blue_home: RegionDef = _regions[4]
	blue_home.half = Vector2(130, 90)
	blue_home.neighbors = ["region_blue_border"]

func _build_pois() -> void:
	_pois = [
		# Red home.
		POIDef.new("poi_red_home", "Ana Köy", "region_red_home",
			POIDef.Type.HOME, "", Vector2(-540, 0),
			"Krallığının köyü. Dönüş noktan."),
		# Red contested border.
		POIDef.new("poi_red_stronghold", "Sınır Kalesi", "region_red_border",
			POIDef.Type.STRONGHOLD, "stronghold_raid", Vector2(-370, -70),
			"Baskına uğramış bir haydut kalesi. (Aktivite gelecek pakette)"),
		POIDef.new("poi_red_shrine", "Sınır Mabedi", "region_red_border",
			POIDef.Type.SHRINE, "shrine_minigame", Vector2(-270, 5),
			"Kadim bir mabet. (Aktivite gelecek pakette)"),
		POIDef.new("poi_red_gather", "Bozkır Maden Yatağı", "region_red_border",
			POIDef.Type.GATHER, "gather", Vector2(-370, 70),
			"Kaynak bakımından zengin bir yatak. (Aktivite gelecek pakette)"),
		# Wilderness (neutral).
		POIDef.new("poi_wild_shrine", "Kayıp Orman Mabedi", "region_wilderness",
			POIDef.Type.SHRINE, "shrine_minigame", Vector2(0, 0),
			"Serbest topraklarda gizli bir mabet."),
		# Blue contested border (mirror).
		POIDef.new("poi_blue_stronghold", "Doğu Kalesi", "region_blue_border",
			POIDef.Type.STRONGHOLD, "stronghold_raid", Vector2(270, -70),
			"Baskına uğramış bir haydut kalesi."),
		POIDef.new("poi_blue_shrine", "Doğu Mabedi", "region_blue_border",
			POIDef.Type.SHRINE, "shrine_minigame", Vector2(370, 5),
			"Kadim bir mabet."),
		POIDef.new("poi_blue_gather", "Doğu Maden Yatağı", "region_blue_border",
			POIDef.Type.GATHER, "gather", Vector2(270, 70),
			"Kaynak bakımından zengin bir yatak."),
		# Blue home.
		POIDef.new("poi_blue_home", "Ana Köy", "region_blue_home",
			POIDef.Type.HOME, "", Vector2(540, 0),
			"Krallığının köyü. Dönüş noktan."),
	]

# --- Indexing -----------------------------------------------------------------

func _index() -> void:
	_kingdom_by_id.clear()
	_region_by_id.clear()
	_poi_by_id.clear()
	_activity_by_id.clear()
	for k in _kingdoms:
		_kingdom_by_id[k.id] = k
	for r in _regions:
		_region_by_id[r.id] = r
	for p in _pois:
		_poi_by_id[p.id] = p
	for a in _activities:
		_activity_by_id[a.id] = a
	# Link every POI back into its owning region's poi_ids, so the Region -> POI
	# relationship is bidirectional (keeps the authored lists consistent).
	for p in _pois:
		var region := _region_by_id.get(p.region_id) as RegionDef
		if region != null and not p.id in region.poi_ids:
			region.poi_ids.append(p.id)

# --- Lookups ------------------------------------------------------------------

func kingdom_defs() -> Array:
	return _kingdoms

func kingdom(id: String) -> KingdomDef:
	return _kingdom_by_id.get(id) as KingdomDef

func region_defs() -> Array:
	return _regions

func poi_defs() -> Array:
	return _pois

func activity_defs() -> Array:
	return _activities

func region(id: String) -> RegionDef:
	return _region_by_id.get(id) as RegionDef

func poi(id: String) -> POIDef:
	return _poi_by_id.get(id) as POIDef

func activity(id: String) -> ActivityDef:
	return _activity_by_id.get(id) as ActivityDef

## The regions belonging to a Kingdom (used both by world rendering and by
## kingdom-discovery seeding on GameManager).
func regions_by_kingdom(kid: String) -> Array:
	var out: Array = []
	for r in _regions:
		if r.owning_kingdom_id == kid:
			out.append(r)
	return out

func pois_of_region(region_id: String) -> Array:
	var out: Array = []
	for p in _pois:
		if p.region_id == region_id:
			out.append(p)
	return out

## The player's starting region after picking a Kingdom (its home region).
func starting_region_for(kid: String) -> RegionDef:
	var k := kingdom(kid)
	if k == null:
		return null
	return region(k.starting_region_id)

# --- Human labels -------------------------------------------------------------

func region_type_name(t: int) -> String:
	match t:
		RegionDef.Type.HOME:
			return "Ana Bölge"
		RegionDef.Type.CONTESTED:
			return "Sınır Bölgesi"
		RegionDef.Type.WILDERNESS:
			return "Serbest Topraklar"
	return "Bölge"

func poi_type_name(t: int) -> String:
	match t:
		POIDef.Type.HOME:
			return "Köy"
		POIDef.Type.STRONGHOLD:
			return "Kale"
		POIDef.Type.SHRINE:
			return "Mabet"
		POIDef.Type.GATHER:
			return "Kaynak"
	return "Nokta"

## Colour of the owner of a region (neutral lands use a muted green).
func owner_color_for_region(r: RegionDef) -> Color:
	if r.owning_kingdom_id == "":
		return NEUTRAL_COLOR
	var k := kingdom(r.owning_kingdom_id)
	return k.color if k != null else NEUTRAL_COLOR

func owner_name_for_region(r: RegionDef) -> String:
	if r.owning_kingdom_id == "":
		return "Tarafsız"
	var k := kingdom(r.owning_kingdom_id)
	return k.display_name if k != null else "Bilinmiyor"

## Colour used to tint a POI marker by its type on the world map.
func color_for_poi(t: int) -> Color:
	match t:
		POIDef.Type.HOME:
			return Color(0.3, 0.85, 0.5, 1.0)
		POIDef.Type.STRONGHOLD:
			return Color(0.85, 0.3, 0.25, 1.0)
		POIDef.Type.SHRINE:
			return Color(0.95, 0.8, 0.2, 1.0)
		POIDef.Type.GATHER:
			return Color(0.95, 0.55, 0.2, 1.0)
	return Color(0.7, 0.7, 0.7, 1.0)

func activity_kind_name(kind: int) -> String:
	match kind:
		ActivityDef.Kind.STRONGHOLD_RAID:
			return "Kale Baskını"
		ActivityDef.Kind.SHRINE_MINIGAME:
			return "Mabet Sınavı"
		ActivityDef.Kind.GATHER:
			return "Kaynak Keşfi"
		ActivityDef.Kind.NONE:
			return "—"
	return "—"
