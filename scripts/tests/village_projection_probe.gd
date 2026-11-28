extends SceneTree
## Probe (2026-11-26): the projected stock, pantry and hunger days of the settlements in the kept world of village_stock_probe
## (`--keep`) over `--days=120`, by the daily rules a long absence is settled by (RegionBanditFormula.stock_now). Seconds.
const Formula = preload("res://scripts/region_lab/region_bandit_formula.gd")
const SiteFiles = preload("res://scripts/terrain_lab/site_store.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")

func _arg(name: String, fallback: float) -> float:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name): return float(arg.trim_prefix("--%s=" % name))
	return fallback

## `n` more fields of one working place, given to the households that have no place of their own.
func _add_fields(state: Dictionary, n: int) -> void:
	var like := ""
	for key: String in state.features:
		if str(state.features[key].get("kind", "")) == "farm": like = key
	var used := {}
	var spare: Array = []
	for house: String in state.households:
		var at := str(state.households[house].job.feature)
		if used.has(at): spare.append(house)
		used[at] = true
	for index: int in n:
		if index >= spare.size() or like.is_empty(): break
		var key := str(9000 + index)
		state.features[key] = state.features[like].duplicate(true)
		state.households[spare[index]].job.feature = key

func _initialize() -> void:
	var days := 120
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--days="): days = int(arg.trim_prefix("--days="))
	var root := ProjectSettings.globalize_path("res://.godot-temp/village_world/region_lab/worlds")
	var worlds := DirAccess.get_directories_at(root)
	var folder := root.path_join(worlds[worlds.size() - 1]).path_join("slots/main/generations")
	for file: String in DirAccess.get_files_at(folder):
		if not file.ends_with(".json"): continue
		var read: Dictionary = SiteFiles._read(folder.path_join(file))
		if not read.get("ok", false): continue
		var summary: Dictionary = Formula.summary_of(read.payload.state)
		if summary.living.is_empty(): continue
		var first := int(summary.living.first)
		var at0 := float(read.payload.state.get("minute", 0)) * 60.0
		for climate: bool in [false, true]:
			var own: Dictionary = Formula.summary_of(SiteFiles._read(folder.path_join(file)).payload.state)
			var line: PackedStringArray = []
			var town: bool = int(own.living.eaters) > 20
			own.living.state.inventory["grain"] = int(own.living.state.inventory.get("grain", 0)) + int(_arg("town-grain" if town else "village-grain", 0))
			_add_fields(own.living.state, int(_arg("town-fields" if town else "village-fields", 0)))
			var hungry := 0
			var worst := INF
			for day: int in range(1, days + 1):
				var slot := {"control": {"logical_game_seconds": at0 + float(day) * 86400.0, "faction_registry": {"climate": {"enabled": climate}}}}
				var stock: Dictionary = Formula.stock_now(slot, own)
				if float(own.run.pantry) < float(own.living.eaters): hungry += 1
				worst = minf(worst, float(own.run.pantry) + float(stock.get("grain", 0)))
				if day in [1, 3, 10, 20, 30, 60, 90, 120] or day % 30 == 0:
					line.append("%d:%s %d/%d/%d" % [day, str(Calendar.date((at0 + float(day) * 86400.0) / 60.0).season), int(stock.get("grain", 0)), int(stock.get("seeds", 0)), int(own.run.pantry)])
			print("VILLAGE_PROJECTION %s climate %s eaters %d start %s: day:season grain/seeds/pantry %s; days with under a day's food %d, least food %.0f" % [file.get_slice("_", 1) + ":" + file.get_slice("_", 2), str(climate), int(own.living.eaters), JSON.stringify(summary.stock), " | ".join(line), hungry, worst])
	print("VILLAGE_PROJECTION_DONE")
	quit(0)
