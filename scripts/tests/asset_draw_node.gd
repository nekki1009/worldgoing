extends Node2D

var texture: Texture2D

func _draw() -> void:
	if texture != null:
		draw_texture_rect(texture, Rect2(Vector2.ZERO, Vector2(100.0, 100.0)), false)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
