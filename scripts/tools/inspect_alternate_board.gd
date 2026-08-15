extends SceneTree

const SOURCE := "res://art_source/paper_doll/reference_generated/worldgoing_alternate_parts_v1.png"

func _init() -> void:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if image == null or image.is_empty():
		push_error("alternate board could not be loaded")
		quit(1)
		return
	print("BOARD size=", image.get_size(), " format=", image.get_format())
	var used := image.get_used_rect()
	print("BOARD used=", used)
	for y: int in range(image.get_height()):
		var count: int = 0
		for x: int in range(image.get_width()):
			if _is_foreground(image.get_pixel(x, y)):
				count += 1
		if count > 0 and (y == 0 or _row_count(image, y - 1) == 0):
			print("RUN START y=", y, " count=", count)
		if count > 0 and (y == image.get_height() - 1 or _row_count(image, y + 1) == 0):
			print("RUN END y=", y, " count=", count)
	quit()

func _row_count(image: Image, y: int) -> int:
	var count: int = 0
	for x: int in range(image.get_width()):
		if _is_foreground(image.get_pixel(x, y)):
			count += 1
	return count

func _is_foreground(color: Color) -> bool:
	# ImageGen's magenta is intentionally flat; keep a generous tolerance for
	# antialiasing at sprite edges, but reject only the board background.
	return color.a > 0.05 and not (
		color.r > 0.75 and color.b > 0.65 and color.g < 0.30
	)
