extends SceneTree

## Deterministically normalizes an ImageGen hair-sheet draft into the
## production paper-doll contract.  ImageGen supplies the silhouette; this
## tool owns the non-negotiable 512x192 / 8x3 / transparent-background rules.

const OUTPUT_SIZE := Vector2i(512, 192)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_path := ""
	var destination_path := ""
	# The verify helper passes script arguments directly after the script path,
	# so they are visible in the full command-line list (not only after `--`).
	for argument: String in OS.get_cmdline_args():
		if argument.begins_with("--source="):
			source_path = argument.trim_prefix("--source=")
		elif argument.begins_with("--destination="):
			destination_path = argument.trim_prefix("--destination=")
	if source_path.is_empty() or destination_path.is_empty():
		push_error("Usage: --source=<png> --destination=<png>")
		quit(2)
		return

	var image := Image.load_from_file(source_path)
	if image == null or image.is_empty():
		push_error("Could not load ImageGen source: %s" % source_path)
		quit(2)
		return
	image.convert(Image.FORMAT_RGBA8)
	var source_size := image.get_size()
	if source_size.x < OUTPUT_SIZE.x or source_size.y < OUTPUT_SIZE.y:
		push_error("ImageGen source is too small: %s" % source_size)
		quit(2)
		return

	# ImageGen was asked for a flat #ff00ff key.  Remove both the solid key and
	# pink antialias fringe before the exact 4x nearest-neighbour reduction.
	for y: int in range(source_size.y):
		for x: int in range(source_size.x):
			var pixel := image.get_pixel(x, y)
			var red := pixel.r * 255.0
			var green := pixel.g * 255.0
			var blue := pixel.b * 255.0
			var magenta_dominance: float = min(red, blue) - green
			if red > 180.0 and blue > 180.0 and green < 130.0:
				image.set_pixel(x, y, Color.TRANSPARENT)
			elif magenta_dominance > 60.0 and green < 170.0:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))

	image.resize(OUTPUT_SIZE.x, OUTPUT_SIZE.y, Image.INTERPOLATE_NEAREST)
	if image.get_size() != OUTPUT_SIZE:
		push_error("Normalized sheet has the wrong size: %s" % image.get_size())
		quit(2)
		return
	if image.get_pixel(0, 0).a > 0.0 or image.get_pixel(511, 191).a > 0.0:
		push_error("Normalized sheet still has an opaque corner")
		quit(2)
		return

	var destination_dir := destination_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(destination_dir)
	var error := image.save_png(destination_path)
	if error != OK:
		push_error("Could not save normalized sheet: %s" % destination_path)
		quit(2)
		return
	print("NORMALIZE_HAIR_PASS source=%s destination=%s size=%s" % [source_path, destination_path, image.get_size()])
	quit()
