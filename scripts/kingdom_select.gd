extends CanvasLayer

## First-launch Kingdom selection. Shown by main.gd only while the player has no
## Kingdom id; picking one persists it (via main.gd, which saves right after it
## re-enters the village) and is never shown again unless the save is reset.
## Identity is IDENTITY + STARTING REGION only — no Kingdom grants stat bonuses.

const VILLAGE_SCENE := "res://scenes/main.tscn"
const ACCENT_BG := Color(0.12, 0.14, 0.18, 1.0)
const ACCENT_BG_HOVER := Color(0.18, 0.21, 0.27, 1.0)

func _ready() -> void:
	# Safety net: if a Kingdom is somehow already chosen, never trap the player.
	if GameManager.kingdom_selected():
		get_tree().change_scene_to_file(VILLAGE_SCENE)
		return
	_build_ui()

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.08, 0.97)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.16, 0.99)
	sb.set_content_margin_all(28)
	sb.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	var title := Label.new()
	title.text = "KRALLIĞINI SEÇ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 6)
	v.add_child(title)

	var sub := Label.new()
	sub.text = "Bir krallığa bağlan. Seçimin kimliğini, başlangıç bölgeni\nve haritada dost/düşman taraflarını belirler."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 14)
	sub.modulate = Color(1, 1, 1, 0.85)
	v.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	v.add_child(spacer)

	for k in WorldData.kingdom_defs():
		v.add_child(_make_kingdom_card(k))

	var note := Label.new()
	note.text = "Seçim sonrası köyüne götürülürsün. (İleride köyü sıfırlayarak yeniden seçebilirsin.)"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 11)
	note.modulate = Color(1, 1, 1, 0.6)
	v.add_child(note)

func _make_kingdom_card(k) -> Button:
	var start_region := ""
	var sr = WorldData.starting_region_for(k.id)
	if sr != null:
		start_region = sr.display_name

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(430, 92)
	btn.text = "◉ %s\n   Başlangıç Bölgesi: %s" % [k.display_name, start_region]
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(_pick.bind(k.id))
	btn.add_theme_stylebox_override("normal", _card_box(k.color, ACCENT_BG))
	btn.add_theme_stylebox_override("hover", _card_box(k.color, ACCENT_BG_HOVER))
	btn.add_theme_stylebox_override("pressed", _card_box(k.color, ACCENT_BG_HOVER))
	return btn

## A dark button box with a thick Kingdom-coloured left accent bar.
func _card_box(accent: Color, bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = accent
	sb.border_width_left = 16
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	sb.set_content_margin(SIDE_LEFT, 18)
	sb.set_corner_radius_all(8)
	return sb

func _pick(kid: String) -> void:
	if not GameManager.choose_kingdom(kid):
		return
	# Persistence happens in main.gd, which saves immediately after the village
	# (re)loads now that a Kingdom is selected. Return straight to the village.
	get_tree().change_scene_to_file(VILLAGE_SCENE)
