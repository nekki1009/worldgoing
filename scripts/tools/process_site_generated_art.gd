extends SceneTree

const SOURCE_DIR: String = "res://assets/map/site/generated"

const JOBS: Array[Dictionary] = [
	{"source": "grass_patch_source.png", "output": "grass_patch.png", "size": Vector2i(64, 48)},
	{"source": "fruit_tree_source.png", "output": "fruit_tree.png", "size": Vector2i(96, 96)},
	{"source": "forest_cluster_source.png", "output": "forest_cluster.png", "size": Vector2i(112, 96)},
	{"source": "stone_ore_source.png", "output": "stone_ore.png", "size": Vector2i(72, 64)},
	{"source": "iron_ore_source.png", "output": "iron_ore.png", "size": Vector2i(72, 64)},
	{"source": "silver_ore_source.png", "output": "silver_ore.png", "size": Vector2i(72, 64)},
	{"source": "gold_ore_source.png", "output": "gold_ore.png", "size": Vector2i(72, 64)},
	{"source": "wood_bridge_source.png", "output": "wood_bridge.png", "size": Vector2i(160, 56)},
	{"source": "wood_stair_source.png", "output": "wood_stair.png", "size": Vector2i(48, 80)},
	{"source": "wood_wall_source.png", "output": "wood_wall.png", "size": Vector2i(128, 56)},
	{"source": "stone_wall_source.png", "output": "stone_wall.png", "size": Vector2i(128, 56)},
	{"source": "wood_house_source.png", "output": "wood_house.png", "size": Vector2i(224, 176)},
]

func _init() -> void:
	var failures: int = 0
	for job: Dictionary in JOBS:
		if not _process_job(job):
			failures += 1
	print("Processed Site generated art: %d/%d" % [JOBS.size() - failures, JOBS.size()])
	quit(0 if failures == 0 else 1)

func _process_job(job: Dictionary) -> bool:
	var input_path: String = "%s/%s" % [SOURCE_DIR, str(job["source"])]
	var output_path: String = "%s/%s" % [SOURCE_DIR, str(job["output"])]
	var image: Image = Image.load_from_file(input_path)
	if image == null or image.is_empty():
		push_error("Could not load %s" % input_path)
		return false
	image.convert(Image.FORMAT_RGBA8)
	var border_color: Color = image.get_pixel(0, 0)
	var minimum: Vector2i = Vector2i(image.get_width(), image.get_height())
	var maximum: Vector2i = Vector2i(-1, -1)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color: Color = image.get_pixel(x, y)
			var distance: float = _rgb_distance(color, border_color)
			if distance < 0.08 or (color.r > 0.76 and color.b > 0.56 and color.g < 0.28):
				image.set_pixel(x, y, Color(color.r, color.g, color.b, 0.0))
				continue
			if distance < 0.22:
				var alpha: float = smoothstep(0.08, 0.22, distance)
				image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
			if image.get_pixel(x, y).a > 0.18:
				minimum.x = mini(minimum.x, x)
				minimum.y = mini(minimum.y, y)
				maximum.x = maxi(maximum.x, x)
				maximum.y = maxi(maximum.y, y)
	if maximum.x < minimum.x or maximum.y < minimum.y:
		push_error("No subject remained in %s" % input_path)
		return false
	var margin: int = maxi(2, roundi(float(maxi(maximum.x - minimum.x, maximum.y - minimum.y)) * 0.03))
	var crop_rect: Rect2i = Rect2i(
		maxi(0, minimum.x - margin),
		maxi(0, minimum.y - margin),
		mini(image.get_width() - maxi(0, minimum.x - margin), maximum.x - minimum.x + 1 + margin * 2),
		mini(image.get_height() - maxi(0, minimum.y - margin), maximum.y - minimum.y + 1 + margin * 2)
	)
	var cropped: Image = image.get_region(crop_rect)
	var target: Vector2i = job["size"] as Vector2i
	cropped.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
	var error: Error = cropped.save_png(output_path)
	if error != OK:
		push_error("Could not save %s" % output_path)
		return false
	print("SITE ART: %s" % ProjectSettings.globalize_path(output_path))
	return true

func _rgb_distance(left: Color, right: Color) -> float:
	var dr: float = left.r - right.r
	var dg: float = left.g - right.g
	var db: float = left.b - right.b
	return sqrt(dr * dr + dg * dg + db * db)
