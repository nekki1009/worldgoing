extends SiteResourceView

func _oval(canvas: Node2D, p: Vector2, radius: Vector2, color: Color) -> void:
	# Frozen original implementation; reference coverage is outside FPS timing.
	set_meta(&"reference_oval_calls", int(get_meta(&"reference_oval_calls", 0)) + 1)
	var points := PackedVector2Array()
	for n: int in range(20):
		var angle := float(n) * TAU / 20.0
		points.append(p + Vector2(cos(angle), sin(angle)) * radius)
	canvas.draw_colored_polygon(points, color)
