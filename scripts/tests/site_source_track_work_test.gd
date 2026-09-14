extends SceneTree
## Read-only native query-work inventory. Never changes production animation.
const Source = preload("res://scripts/terrain_lab/terrain_army_contact_source.gd")
const Motion = preload("res://scripts/tests/helpers/site_army_motion_bounds_inventory.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	assert(TerrainArmy.load_combat_bake())
	var source := Source.new()
	assert(source.initialize(root, TerrainArmy._combat_bake.manifest.appearance))
	var clips := {}
	for clip: StringName in [&"idle", &"walk_slash", &"walk", &"down", &"unconscious"]:
		var animation := source.editor.animation_player.get_animation(clip)
		var stats := {"tracks": animation.get_track_count(), "varying": {}, "constant": {}, "examples": [], "targets": {}}
		for track in animation.get_track_count():
			var kind := animation.track_get_type(track)
			if kind == Animation.TYPE_BLEND_SHAPE and animation.track_is_enabled(track):
				var path := animation.track_get_path(track)
				var target := str(path.get_concatenated_names()).get_file().split("_")[0]
				stats.targets[target] = int(stats.targets.get(target, 0)) + 1
			var varying := false
			var keys := animation.track_get_key_count(track)
			if keys > 0:
				var first: Variant = animation.track_get_key_value(track, 0)
				for key in range(1, keys):
					if var_to_bytes(animation.track_get_key_value(track, key)) != var_to_bytes(first):
						varying = true
						break
			var counts: Dictionary = stats.varying if varying else stats.constant
			counts[kind] = int(counts.get(kind, 0)) + 1
			if varying and stats.examples.size() < 12:
				stats.examples.append(str(animation.track_get_path(track)))
		clips[clip] = stats
	print("SOURCE_NATIVE_TRACK_WORK ", JSON.stringify(clips))
	var motion_reports := {}
	for clip: StringName in [&"idle", &"walk_slash"]:
		var report := Motion.inspect(source, clip)
		report.erase("local_rates")
		if report.get("supported", false):
			var checks := 0
			var violations := 0
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var previous := {}
				for index in 64:
					var time := 0.017 + float(index) * 0.00931
					if time >= float(report.length):
						break
					source.begin_contact_step()
					var sample: Dictionary = source.sample(clip, time, direction)
					assert(not sample.is_empty())
					if not previous.is_empty():
						var margin := float(report.pixels_per_second_candidate) * (0.00931 + float(report.approx_find_time_slack)) + 2.0
						var bounds: Rect2 = previous.hurt_bounds
						checks += 1
						violations += int(not bounds.grow(margin).encloses(sample.hurt_bounds))
					previous = sample
			report["consecutive_original_pose_checks"] = checks
			report["candidate_enclosure_violations"] = violations
		motion_reports[clip] = report
	print("SOURCE_NATIVE_MOTION_INVENTORY ", JSON.stringify(motion_reports))
	source.dispose()
	await process_frame
	print("SITE_SOURCE_TRACK_WORK_PASS")
	quit(0)
