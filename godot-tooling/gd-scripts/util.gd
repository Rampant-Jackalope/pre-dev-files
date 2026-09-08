class_name Util
extends Node

static func show_temp_richlabel(
		parent: Node,
		text: String,
		duration: float = 1.5,
		fade_duration: float = 0.5,
		callback: Callable = Callable()
) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = text
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var viewport_size := parent.get_viewport().get_visible_rect().size
	label.size = Vector2(200, 40)
	label.position = Vector2(viewport_size.x / 2.0 - label.size.x / 2.0, viewport_size.y - 50)

	parent.add_child(label)

	var tween := label.create_tween()
	tween.tween_interval(duration)
	tween.tween_property(label, "modulate:a", 0.0, fade_duration)

	if callback.is_valid():
		tween.tween_callback(callback)

	tween.tween_callback(label.queue_free)

	return label
