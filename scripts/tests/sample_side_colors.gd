extends SceneTree

const ARTIFACT_DIR: String = "C:/Users/Nekki/.gemini/antigravity/brain/6751ce0d-7d56-4cae-8c5b-9f20717bdb83"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var img := Image.load_from_file(ARTIFACT_DIR + "/v2_male_leather_h1_side.png")
	var colors := {}
	for y in range(400, 520):
		for x in range(800, 950):
			var c := img.get_pixel(x, y)
			var hex := c.to_html(false)
			colors[hex] = colors.get(hex, 0) + 1
	var sorted_cols := colors.keys()
	sorted_cols.sort_custom(func(a, b): return colors[a] > colors[b])
	print("Top colors in head region:")
	for i in range(min(15, sorted_cols.size())):
		var cname: String = str(sorted_cols[i])
		print("  #", cname, ": ", colors[cname], " pixels")
	quit(0)
