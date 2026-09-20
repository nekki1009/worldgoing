extends SceneTree
## The Chinese apron revision must not alter the other accepted target pixels.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var revision: String = args[0] if not args.is_empty() else "v4"
	assert(revision.is_valid_identifier() and revision.begins_with("v"))
	var checked := 0
	for sex in ["male","female"]:
		var root := "res://output/equipment_walk_fix_20260919/"
		var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root+"candidate_v3/"+sex+"/result.json"))
		var after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root+"candidate_"+revision+"/"+sex+"/result.json"))
		assert(before.images.size() == 348 and after.images.size() == 348)
		for old_path: String in before.images:
			if old_path.get_file().begins_with("chinese_armor_"): continue
			var new_path: String = root+"candidate_"+revision+"/"+sex+"/"+old_path.get_file()
			assert(new_path in after.images)
			var old := Image.load_from_file(old_path)
			var current := Image.load_from_file(new_path)
			assert(old.get_size() == current.get_size() and old.get_format() == current.get_format())
			assert(old.get_data() == current.get_data(),new_path)
			checked += 1
	assert(checked == 610)
	print("EQUIPMENT_WALK_REVISION_PIXELS_PASS ",revision," ",checked," unchanged native RGBA captures")
	quit(0)
