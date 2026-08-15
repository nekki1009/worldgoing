extends SceneTree

const VARIANT_DIR: String = "res://assets/map/site/variants"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var generated: int = 0
	generated += _rotate_variant(
		"res://assets/map/site/variants/cliff_path_horizontal_v1.png",
		"res://assets/map/site/variants/cliff_path_vertical_v1.png"
	)
	generated += _rotate_variant(
		"res://assets/map/site/roads/path_straight_v3.png",
		"res://assets/map/site/variants/path_straight_horizontal_v1.png"
	)
	generated += _copy_variant(
		"res://assets/map/site/roads/path_straight_v3.png",
		"res://assets/map/site/variants/path_straight_vertical_v1.png"
	)
	generated += _rotate_variant(
		"res://assets/map/site/rivers/river_straight_v2.png",
		"res://assets/map/site/variants/river_straight_horizontal_v1.png"
	)
	generated += _copy_variant(
		"res://assets/map/site/rivers/river_straight_v2.png",
		"res://assets/map/site/variants/river_straight_vertical_v1.png"
	)
	generated += _rotate_variant(
		"res://assets/map/site/scenes/river_bridge_v1.png",
		"res://assets/map/site/scenes/river_bridge_vertical_v1.png"
	)
	print("SITE CONNECTION VARIANTS: generated=%d" % generated)
	quit(0 if generated == 6 else 2)

func _copy_variant(source_path: String, target_path: String) -> int:
	var source: Image = Image.load_from_file(source_path)
	if source == null or source.is_empty():
		push_error("Could not load variant source: %s" % source_path)
		return 0
	var error: Error = source.save_png(target_path)
	if error != OK:
		push_error("Could not write variant: %s (%s)" % [target_path, error])
		return 0
	return 1

func _rotate_variant(source_path: String, target_path: String) -> int:
	var source: Image = Image.load_from_file(source_path)
	if source == null or source.is_empty():
		push_error("Could not load variant source: %s" % source_path)
		return 0
	source.rotate_90(ClockDirection.CLOCKWISE)
	var error: Error = source.save_png(target_path)
	if error != OK:
		push_error("Could not write rotated variant: %s (%s)" % [target_path, error])
		return 0
	return 1
