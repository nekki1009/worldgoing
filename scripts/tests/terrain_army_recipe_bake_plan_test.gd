extends SceneTree
## Headless planning proof only; GPU pixels and original poses need a bake run.

const Plan = preload("res://scripts/tools/terrain_army_recipe_bake_plan.gd")
const Baker = preload("res://scripts/tools/bake_terrain_army_soldier.gd")

func _args(mask: int = 0, clips: String = "down,get_up", directions: String = "down", first: int = 0, count: int = 24) -> PackedStringArray:
	return PackedStringArray(["--recipe-mask=%d" % mask, "--recipe-output=res://output/terrain_army_missing_gear_20260913/test_unused",
		"--recipe-clips=" + clips, "--recipe-directions=" + directions, "--recipe-first=%d" % first, "--recipe-count=%d" % count])

func _initialize() -> void:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Baker.MANIFEST_PATH)).appearance
	var original := baseline.duplicate(true)
	var keys := {}
	for mask: int in range(32):
		var plan := Plan.build(_args(mask), Baker.CLIPS, Baker.DIRECTIONS, baseline)
		assert(plan.ok and plan.recipe_total == 536 and plan.selected_total == 24)
		assert(plan.selection_complete and not plan.recipe_complete)
		assert(not keys.has(plan.key))
		keys[plan.key] = true
		assert(plan.appearance.body == baseline.body and plan.appearance.parts.hair == baseline.parts.hair)
		for bit: int in Plan.SLOTS.size():
			var slot: String = Plan.SLOTS[bit]
			assert(plan.appearance.parts[slot] == (baseline.parts[slot] if (mask & (1 << bit)) != 0 else "none"))
		for clip: Dictionary in plan.clips:
			assert(not clip.has("weapon") and not clip.has("shield"))
		assert(plan.clips[0].id == "down" and plan.clips[1].id == "get_up")
	assert(baseline == original, "Planning never mutates the source appearance")
	assert(keys.has("standard_soldier_v2/m00") and keys.has("standard_soldier_v2/m31"))
	for iron in range(1, 8):
		var args := _args(31)
		args.append("--recipe-iron=%d" % iron)
		var plan := Plan.build(args, Baker.CLIPS, Baker.DIRECTIONS, baseline)
		assert(plan.ok and plan.recipe_total == 536 and plan.iron == iron)
		assert(plan.key == Plan.recipe_key(31, iron) and not keys.has(plan.key))
		assert(plan.appearance == Plan.appearance_for(31, baseline, iron))
		keys[plan.key] = true
		for bit in range(3):
			var slot: String = Plan.IRON_PARTS.keys()[bit]
			assert(plan.appearance.parts[slot] == (Plan.IRON_PARTS[slot] if iron & (1 << bit) else baseline.parts[slot]))
	for value: String in ["-1", "8", "steel", "1.5"]:
		var args := _args(31)
		args.append("--recipe-iron=" + value)
		assert(not Plan.build(args, Baker.CLIPS, Baker.DIRECTIONS, baseline).ok)
	for mask: int in [0, 31]:
		var next := 0
		while next < 536:
			var count := mini(128, 536 - next)
			var batch := Plan.build(_args(mask, "all", "all", next, count), Baker.CLIPS, Baker.DIRECTIONS, baseline)
			assert(batch.ok and batch.first == next and batch.count == count and batch.clips.size() == 18)
			assert(batch.selected_total == 536 and not batch.recipe_complete)
			var attacks: Array[String] = []
			for clip: Dictionary in batch.clips:
				if str(clip.id).begins_with("attack_") or clip.id == "walk_slash":
					attacks.append(str(clip.id))
			assert(attacks == (["attack_unarmed"] if mask == 0 else ["walk_slash"]))
			next += count
		assert(next == 536, "Explicit batches cover the selection without overlap or missing tail")
	for arguments: PackedStringArray in [
		_args(-1), _args(32), _args(0, "walk_slash", "down", 0, 12), _args(31, "attack_unarmed", "down", 0, 12),
		_args(0, "attack_spear", "down", 0, 12), _args(0, "down,down"), _args(0, "down", "front", 0, 12),
		_args(0, "all", "all", 0, 129), _args(0, "all", "all", 512, 25), _args(0, "down,get_up", "down", -1, 24),
		PackedStringArray(["--recipe-mask=0"]),
	]:
		assert(not Plan.build(arguments, Baker.CLIPS, Baker.DIRECTIONS, baseline).ok, str(arguments))
	var bad_path := _args()
	bad_path[1] = "--recipe-output=res://output/../../assets/characters"
	assert(not Plan.build(bad_path, Baker.CLIPS, Baker.DIRECTIONS, baseline).ok)
	var duplicate := _args()
	duplicate.append("--recipe-mask=1")
	assert(not Plan.build(duplicate, Baker.CLIPS, Baker.DIRECTIONS, baseline).ok)
	print("TERRAIN ARMY RECIPE PLAN PASS: 32 actual-slot masks, fixed body, 18 reachable clips / 536 frames, strict staging and bounded partition")
	quit(0)
