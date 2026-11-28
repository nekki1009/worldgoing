extends SceneTree
## Probe (2026-11-27, 開局速度 B): how RegionData.prebuild_fixed_bases scales, in one process (the machine's speed
## mode can change between runs): groups of 18 different plain Taiwan Sites built one by one, then on 2, 4 and 6 worker
## threads, then one by one again. Output: PREBUILD_SCALING lines and PREBUILD_SCALING_DONE.
const GROUP := 18

func _initialize() -> void:
	_run.call_deferred()

func _ms(from: int) -> float:
	return float(Time.get_ticks_usec() - from) / 1000.0

func _run() -> void:
	var source := RegionData.new()
	if not source.load_manifest(RegionData.DEFAULT_MANIFEST).get("ok", false):
		print("PREBUILD_SCALING load failed")
		quit(1)
		return
	var sites: Array[Vector2i] = []
	for y: int in range(13205, 13295, 3):
		for x: int in range(1105, 1195, 3):
			var summary: Dictionary = source.get_site_summary(x, y)
			if bool(summary.get("ok", false)) and summary.get("status") != "outside_content" and int(summary.get("class_id", 0)) != 0:
				sites.append(Vector2i(x, y))
	print("PREBUILD_SCALING %d land Sites in the window, processors %d" % [sites.size(), OS.get_processor_count()])
	source.make_terrain_data(sites[0].x, sites[0].y) # the tile, resource tile and first masks load outside the timing
	var cursor := 1
	for workers: int in [1, 2, 4, 6, 1]:
		if cursor + GROUP > sites.size(): break
		var group: Array = sites.slice(cursor, cursor + GROUP)
		cursor += GROUP
		var t := Time.get_ticks_usec()
		var result: Dictionary
		if workers == 1:
			for site: Vector2i in group: result = source.make_terrain_data(site.x, site.y)
		else:
			result = source.prebuild_fixed_bases(group, workers)
		var total := _ms(t)
		print("PREBUILD_SCALING workers %d: %d builds %.0f ms, %.0f ms a build, ok %s" % [workers, group.size(), total, total / group.size(), str(result.get("ok", false))])
	print("PREBUILD_SCALING_DONE")
	quit(0)
