extends CanvasLayer

## Defense battle UI — presentation only. Builds a mobile-friendly top HUD
## (village title + live enemy/destruction/town-hall readouts), a short-lived
## battle-state flash, and a centered result overlay with tween animations.
##
## Everything displayed comes from DefenseDirector signals. This script never
## kills enemies, judges win/loss, computes destruction, touches buildings,
## resources, SaveManager or GameManager.in_raid. It only displays state and
## asks defense.gd (the scene owner) to return to the village.

var _defense = null    # untyped: defense.gd methods resolve at runtime
var _director = null   # untyped: DefenseDirector signals resolve at runtime

var _total_enemies := 9
var _townhall_alive := true
# Previous HUD values, so micro-pulses fire only on a real change.
var _last_destruct := 0
var _last_enemy := 9

# Top HUD
var _enemy_label: Label
var _destruct_label: Label
var _townhall_label: Label
# Battle-state flash (centered, fades away)
var _state_label: Label
var _state_tween: Tween = null
# Result overlay
var _overlay: ColorRect
var _panel: PanelContainer
var _title_label: Label
var _stats_label: Label
var _return_button: Button

func setup(defense: Node, director: Node) -> void:
	_defense = defense
	_director = director
	_build_ui()
	# Connect by signal name so no typed member resolution is needed.
	_director.connect("enemy_count_changed", _on_enemy_count)
	_director.connect("destruction_changed", _on_destruction)
	_director.connect("town_hall_status_changed", _on_townhall)
	_director.connect("battle_started", _on_battle_started)
	_director.connect("battle_finished", _on_battle_finished)

# --- Signal handlers ---------------------------------------------------------

func _on_enemy_count(current: int, total: int) -> void:
	_total_enemies = total
	_enemy_label.text = "DÜŞMAN: %d/%d" % [current, total]
	if current < _last_enemy:
		_pulse_label(_enemy_label, 1.08)
	_last_enemy = current

func _on_destruction(percent: int) -> void:
	_destruct_label.text = "YIKIM: %d%%" % percent
	if percent > _last_destruct:
		_pulse_label(_destruct_label, 1.06)
	_last_destruct = percent

func _on_townhall(alive: bool) -> void:
	_townhall_alive = alive
	_townhall_label.text = "BELEDİYE: %s" % ("✓" if alive else "✕")

func _on_battle_started() -> void:
	_play_flash("SALDIRI!")

func _on_battle_finished(result: Dictionary) -> void:
	var won: bool = int(result["outcome"]) == DefenseDirector.State.WIN
	_show_result(won, result)

# --- Presentation ------------------------------------------------------------

## Briefly shows a centered banner, then fades it away so the battlefield stays
## the visual priority.
func _play_flash(text: String) -> void:
	if _state_tween:
		_state_tween.kill()
	_state_label.text = text
	_state_label.modulate.a = 0.0
	if not _state_label.visible:
		_state_label.visible = true
	_state_tween = create_tween()
	_state_tween.tween_property(_state_label, "modulate:a", 1.0, 0.25)
	_state_tween.tween_interval(0.9)
	_state_tween.tween_property(_state_label, "modulate:a", 0.0, 0.5)

func _show_result(won: bool, result: Dictionary) -> void:
	_title_label.text = "ZAFER!" if won else "YENİLGİ"
	_title_label.add_theme_color_override("font_color",
			Color(0.35, 0.9, 0.35) if won else Color(0.95, 0.4, 0.4))
	var lines: Array[String] = [
		"YIKIM: %d%%" % int(result["destruction_percent"]),
		"DÜŞMANLAR: %d/%d" % [int(result["remaining_enemies"]), _total_enemies],
		"BELEDİYE: %s" % ("✓" if _townhall_alive else "✕"),
	]
	_stats_label.text = "\n".join(lines)

	_overlay.visible = true
	_overlay.color.a = 0.0
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.92, 0.92)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_overlay, "color:a", 0.62, 0.25)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.3)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_return_pressed() -> void:
	_defense.return_to_village()

## A brief, subtle scale pulse on a HUD label so a counter change is confirmed
## without shaking the screen. Scales about the label's centre.
func _pulse_label(l: Label, to: float) -> void:
	if l == null:
		return
	l.pivot_offset = l.size * 0.5
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2(to, to), 0.08) \
			.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(l, "scale", Vector2.ONE, 0.1) \
			.set_trans(Tween.TRANS_QUAD)

# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	_add_top_hud()
	_add_state_flash()
	_add_result_overlay()

func _mk_label(parent: Node, text: String, font_size: int = 18) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l

func _add_top_hud() -> void:
	var bar := PanelContainer.new()
	bar.name = "TopHUD"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.7)
	sb.corner_radius_top_left = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_right = 10
	bar.add_theme_stylebox_override("panel", sb)
	# Top-wide, fixed comfortable height; width auto-fills the screen.
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_top = 8.0
	bar.offset_left = 8.0
	bar.offset_right = -8.0
	bar.offset_bottom = 104.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 8)
	bar.add_child(margin)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(box)

	var title := Label.new()
	title.text = "KÖY SAVUNMASI"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(title)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(right)
	_enemy_label = _mk_label(right, "DÜŞMAN: 9/9", 18)
	_destruct_label = _mk_label(right, "YIKIM: 0%", 18)
	_townhall_label = _mk_label(right, "BELEDİYE: ✓", 18)

func _add_state_flash() -> void:
	var cc := CenterContainer.new()
	cc.name = "StateCenter"
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	_state_label = Label.new()
	_state_label.text = "HAZIRLANIYOR..."
	_state_label.add_theme_font_size_override("font_size", 48)
	_state_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	_state_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_state_label.add_theme_constant_override("outline_size", 8)
	_state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(_state_label)

func _add_result_overlay() -> void:
	_overlay = ColorRect.new()
	_overlay.name = "ResultOverlay"
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.visible = false
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	var cc := CenterContainer.new()
	cc.name = "ResultCenter"
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(cc)

	_panel = PanelContainer.new()
	_panel.name = "ResultPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.12, 0.16, 0.97)
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	sb.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(320, 0)
	_panel.pivot_offset = _panel.size * 0.5
	_panel.resized.connect(_update_panel_pivot)
	cc.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 40)
	vbox.add_child(_title_label)

	_stats_label = Label.new()
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_stats_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(spacer)

	_return_button = Button.new()
	_return_button.text = "KÖYE DÖN"
	_return_button.custom_minimum_size = Vector2(220, 58)
	_return_button.add_theme_font_size_override("font_size", 22)
	_return_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_return_button.pressed.connect(_on_return_pressed)
	vbox.add_child(_return_button)

func _update_panel_pivot() -> void:
	_panel.pivot_offset = _panel.size * 0.5
