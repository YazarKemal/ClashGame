extends Node

## Central "juice" helper: floating combat/loot text, one-shot particle bursts
## and camera shake. Registered as an autoload (FxManager) so any building or
## unit can trigger an effect by name. Effects are parented to the current 2D
## scene so they inherit the world camera transform and land at world positions.

const TEXT_LIFETIME := 0.9
const RISE_DIST := 46.0

## Spawns a coloured label at a world position that floats up, fades out and
## frees itself. Used for damage numbers and loot pickups.
func float_text(pos: Vector2, text: String, color: Color) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 60
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	scene.add_child(label)
	label.reset_size()
	# Centre the text horizontally and sit its bottom on the target point.
	label.position = pos - Vector2(label.size.x * 0.5, label.size.y)
	var tw := label.create_tween()
	tw.tween_property(label, "position:y", label.position.y - RISE_DIST, TEXT_LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "modulate:a", 0.0, TEXT_LIFETIME) \
		.set_delay(0.25)
	tw.tween_callback(label.queue_free)

## Fires a short-lived particle burst (dust, debris, muzzle flash) at a world
## position. The particle is independent of its origin node, so it survives the
## destruction of the building/unit that triggered it.
func burst(pos: Vector2, color: Color, amount: int = 20,
		lifetime: float = 0.4, max_velocity: float = 150.0) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = true
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = max_velocity * 0.35
	p.initial_velocity_max = max_velocity
	p.gravity = Vector2(0, 320)
	p.color = color
	p.position = pos
	p.z_index = 40
	scene.add_child(p)
	p.finished.connect(p.queue_free)

## Triggers a short screen shake on every camera in the "camera" group.
func shake_cam(strength: float, duration: float) -> void:
	for c in get_tree().get_nodes_in_group("camera"):
		if c.has_method("shake"):
			c.shake(strength, duration)
