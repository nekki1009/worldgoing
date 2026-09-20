extends SceneTree
const OUT := "res://output/equipment_walk_fix_20260919"

func _initialize() -> void:
	var equal_count := 0
	var changed_fronts := 0
	for sex in ["male","female"]:
		var directory := DirAccess.open(OUT+"/hair_trial1/"+sex)
		assert(directory != null)
		for file in directory.get_files():
			if not file.begins_with("hair_") or not file.ends_with(".png"): continue
			var before := Image.load_from_file(OUT+"/before/"+sex+"/"+file)
			var after := Image.load_from_file(OUT+"/hair_trial1/"+sex+"/"+file)
			assert(before != null and after != null and before.get_size() == after.get_size())
			if "_off_" in file or "_none_" in file or "_helmet_cloth_" in file:
				assert(before.get_data() == after.get_data(), "Unchanged hair mode/cap: "+sex+"/"+file)
				equal_count += 1
			elif file.ends_with("_auto_0.png"):
				assert(before.get_data() != after.get_data(), "Western open fringe must visibly change: "+sex+"/"+file)
				changed_fronts += 1
	assert(equal_count == 126 and changed_fronts == 18)
	var report := {"unchanged_rgba":equal_count,"changed_fronts":changed_fronts,"status":"PASS"}
	FileAccess.open(OUT+"/hair_pixel_comparison.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WESTERN_HELMET_MASK_PIXELS_PASS ",equal_count," unchanged; ",changed_fronts," wider-fringe front views")
	quit()
