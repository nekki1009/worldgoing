extends SceneTree
## Probe (2026-11-25): what a village nobody opens has in stock after `--days=N` game days (default 10): the stock in its
## saved file against the stock after its catch-up, for every settlement of a small scenario world. Bands lie low.
## Output: VILLAGE_STOCK lines and VILLAGE_STOCK_DONE.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Generator = preload("res://scripts/scenarios/demo_a_generator.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Aftermath = preload("res://scripts/terrain_lab/site_bandit_aftermath.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Formula = preload("res://scripts/region_lab/region_bandit_formula.gd")
const DAY := 86400.0

var lab: TerrainLab
var slot: RegionSaveSlot
var finished := false

func _initialize() -> void:
	create_timer(3400.0).timeout.connect(func() -> void: _end("deadline"))
	_run.call_deferred()

func _arg(name: String, fallback: float) -> float:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name): return float(arg.trim_prefix("--%s=" % name))
	return fallback

func _only() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): return arg.trim_prefix("--only=")
	return ""

func _copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for file: String in DirAccess.get_files_at(from): DirAccess.copy_absolute(from.path_join(file), to.path_join(file))
	for dir: String in DirAccess.get_directories_at(from):
		if dir in ["logs", "shader_cache", "vulkan"]: continue
		_copy_tree(from.path_join(dir), to.path_join(dir))

func _end(reason: String) -> void:
	if finished: return
	finished = true
	print("VILLAGE_STOCK END %s" % reason)
	print("VILLAGE_STOCK_DONE")
	TerrainArmy.release_contact_source()
	quit(0)

## Each farm: its status text, production minutes, whether its batch is paid, its recipe.
func _farms(site: Dictionary) -> Dictionary:
	var result := {}
	for key: Variant in site.get("features", {}):
		var feature: Dictionary = site.features[key]
		if str(feature.get("kind", "")) == "farm": result[str(key)] = [str(feature.get("status", "")), snappedf(float(feature.get("production", 0.0)), 0.1), bool(feature.get("batch_paid", false)), str(feature.get("recipe_id", ""))]
	return result

func _held(site: Dictionary) -> Dictionary:
	var owner := int(site.get("settlement", {}).get("owner_faction", -1))
	var alive := 0
	var carried := {}
	for army: Variant in site.get("armies", []):
		for unit: Variant in army.get("units", []):
			if float(unit.get("hp", 0.0)) > 0.0: alive += 1
			for item: Variant in unit.get("cargo", {}): carried[str(item)] = int(carried.get(str(item), 0)) + int(unit.cargo[item])
	var kinds := {}
	for feature: Variant in site.get("features", {}).values(): kinds[str(feature.get("kind", ""))] = int(kinds.get(str(feature.get("kind", "")), 0)) + 1
	return {"stock": Aftermath.stock_of(site, owner), "alive": alive, "carried": carried, "fields": site.get("zones", []).size(), "features": kinds, "produced": site.get("total_produced", 0), "supply": site.get("team_supply", {}).size(), "pantry": _pantry(site), "share": site.get("food_share", {}), "farms": _farms(site), "hungry": _hungry(site), "jobs": site.get("households", {}).values().map(func(h: Dictionary) -> String: return str(h.get("job", {}).get("feature", "")))}

func _pantry(site: Dictionary) -> float:
	var total := 0.0
	for entry: Dictionary in site.get("team_supply", {}).values():
		if int(entry.version) == 3:
			for location: Dictionary in entry.locations.values():
				total += float(location.open_rations)
				for item: String in SiteSustain.FOODS: total += float(location.inventory.get(item, 0))
		else:
			total += float(entry.sustain.get("open_rations", 0.0))
			for item: String in SiteSustain.FOODS: total += float(entry.inventory.get(item, 0))
	return total

func _hungry(site: Dictionary) -> float:
	var worst := 0.0
	for entry: Dictionary in site.get("team_supply", {}).values():
		for cohort: Dictionary in entry.sustain.cohorts: worst = maxf(worst, float(cohort.hunger))
	return worst

func _run() -> void:
	# The birth takes minutes: `--cache` opens the world an earlier `--keep` run left beside the project's temporary files.
	var cache := ProjectSettings.globalize_path("res://.godot-temp/village_world")
	var kept := "--cache" in OS.get_cmdline_user_args()
	if kept:
		_copy_tree(cache, ProjectSettings.globalize_path("user://"))
		if not RegionEntry.request_resume():
			_end("no kept world: %s" % RegionEntry.menu_message)
			return
	else:
		var folder := "user://village_stock_world"
		DirAccess.make_dir_recursive_absolute(folder.path_join("demo_a"))
		var natural := RegionData.new()
		natural.load_manifest(RegionData.DEFAULT_MANIFEST)
		var built: Dictionary = Generator.generate(natural, folder.path_join("demo_a"), "demo_a.json", 5, 1, 1, 20261122)
		print("VILLAGE_STOCK BUILT %d s after start" % [Time.get_ticks_msec() / 1000])
		if not built.get("ok", false) or not RegionEntry.request_new_world(built.start, {}, "村落存糧", "", str(built.path)):
			_end("no world %s %s" % [str(built.get("stage", built.get("code", ""))), RegionEntry.menu_message])
			return
	change_scene_to_file(SITE)
	var open_deadline := Time.get_ticks_msec() + 900000
	while Time.get_ticks_msec() < open_deadline:
		await process_frame
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if lab == null:
		_end("the world did not open")
		return
	for _warm: int in range(5): await process_frame
	slot = lab.site_controller.region_slot
	print("VILLAGE_STOCK OPEN %d s after start" % [Time.get_ticks_msec() / 1000])
	if "--keep" in OS.get_cmdline_user_args():
		_copy_tree(ProjectSettings.globalize_path("user://"), cache)
		print("VILLAGE_STOCK KEPT %s" % cache)
	for key: Variant in slot.control.faction_registry.entries:
		var band := int(slot.control.faction_registry.entries[key].faction_id)
		if not RegionFactionQuery.is_bandit(slot.control.faction_registry, band): continue
		lab.site_controller._commit_diplomacy(Bandit.set_heat(slot.control.faction_registry, band, 80, float(slot.control.logical_game_seconds)), "")
	var villages: Array[String] = []
	for site: Variant in slot._marker.sites:
		var parts: PackedStringArray = str(site).split(":")
		if "%s:%s" % [str(slot.pin.atlas_id), str(site)] == str(slot.control.active_site_id): continue
		var loaded: Dictionary = slot._load_checked(slot.folder.path_join(str(slot._marker.sites[site].path)), Vector2i(int(parts[0]), int(parts[1])))
		if not loaded.ok or not Settlement.record(loaded.data).has("owner_faction"): continue
		villages.append(str(site))
		print("VILLAGE_STOCK FILE %s %s" % [str(site), JSON.stringify(_held(loaded.data.site)).left(600)])
	# `--bind=1`: the settlement(s) are opened first and stay open, lived step by step.
	if _arg("bind", 0.0) > 0.0:
		var held := {}
		for village: String in villages:
			if not _only().is_empty() and village != _only(): continue
			var id := "%s:%s" % [str(slot.pin.atlas_id), village]
			lab.set_process(false) # the clock stands while it is opened
			var opened: Dictionary = {}
			for attempt: int in range(8000):
				opened = lab._region_gameplay_owner_lab(id, "cold_exact")
				if opened.get("ok", false) or str(opened.get("code", "")) != "PENDING": break
				await process_frame
			lab.set_process(true)
			print("VILLAGE_STOCK HELD %s %s" % [village, "open" if opened.get("ok", false) else str(opened.get("code", ""))])
			held[id] = 1000000 # and the idle release leaves it open
		slot.set_meta(&"bandit_musters", held)
	lab.simulation_speed = 16.0
	var hour := -1
	var began := float(slot.control.logical_game_seconds)
	var days := _arg("days", 10.0)
	var next_save := 1.0
	var raids := int(_arg("raids", 0.0)) # formula raids of 30 grain each on the first village, two days apart, from the second day on
	var raided := 0
	while float(slot.control.logical_game_seconds) - began < days * DAY:
		await process_frame
		if finished: return
		lab._process(1.0 / 30.0)
		lab.site_controller.person_actions.settle_after_contacts()
		if _arg("bind", 0.0) > 0.0 and int(float(slot.control.logical_game_seconds) / _arg("every", 3600.0)) != hour:
			hour = int(float(slot.control.logical_game_seconds) / _arg("every", 3600.0))
			for id: String in slot._region_original_labs:
				var there: TerrainLab = slot._region_original_labs[id]
				if there == null or there.terrain == null or not there.terrain.site.get("settlement", {}).has("meals"): continue
				if _arg("checkpoint", 0.0) > 0.0: # the capture an arriving party's event waits for
					var held_capture: Dictionary = there.site_controller.capture_region_checkpoint("region_checkpoint", true)
					print("VILLAGE_STOCK CHECKPOINT %d %s: %s, %d walks" % [hour, id, "ok" if held_capture.get("ok", false) else JSON.stringify(held_capture).left(300), there.site_controller.person_actions._jobs.size()])
				var working := 0
				for identity: Variant in there.site_controller.work_team.active_ids():
					if str(there.site_controller.work_team._person(int(identity)).get("row", {}).get("work_task", {}).get("action", "")) == "operate": working += 1
					var task: Dictionary = there.site_controller.work_team._person(int(identity)).get("row", {}).get("work_task", {})
					if not task.is_empty() and int(float(slot.control.logical_game_seconds) / 3600.0) % 4 == 0: print("VILLAGE_STOCK TASK %d %s: %s at %s" % [int(identity), id, JSON.stringify(task).left(400), str(there.crowd_site.combat_target(int(identity)).get("cell", ""))])
				var wt: Variant = there.site_controller.work_team
				var prep: Array = []
				if "--prepare" in OS.get_cmdline_user_args(): wt.prepare_work_requests(60.0, 0.0) # probe only: the selection of a one-minute step
				for entry: Dictionary in wt._prepared_work: prep.append([int(entry.identity), str(entry.get("blocked", "")), str(entry.get("plan_key", "")), bool(entry.get("zero_work", false)), float(entry.get("request", {}).get("remaining", -1.0)), float(entry.get("productivity", -1.0)), str(entry.get("action", "")), JSON.stringify(entry.get("request", {}).get("participants", [])).left(200)])
				print("VILLAGE_STOCK PREPARED %d %s: consumed %s seconds %.3f action %.3f point %s entries %s" % [hour, id, str(wt._work_consumed), float(wt._prepared_seconds), float(wt._prepared_action_seconds), str(there.crowd_site.work_fatigue_point_active()), JSON.stringify(prep).left(800)])
				if "--prepare" in OS.get_cmdline_user_args(): wt.discard_prepared_interval()
				for entry: Dictionary in there.terrain.site.get("team_supply", {}).values():
					for cohort: Dictionary in entry.sustain.cohorts:
						var rows: Array = []
						for identity: Variant in cohort.ids:
							var registered: Dictionary = SiteController.ResidentLife.Housing.relation(there, int(identity))
							var target: Dictionary = there.crowd_site.combat_target(int(identity))
							rows.append("%d%s%s" % [int(identity), "=" if not registered.is_empty() and there.terrain.index(target.get("cell", Vector2i.ZERO)) == int(registered.get("cell", -1)) else ("~" if not registered.is_empty() else "x"), "h" if there.crowd_site.is_at_home(int(identity)) else ""])
						for identity: Variant in cohort.ids:
							var away: Dictionary = SiteController.ResidentLife.Housing.relation(there, int(identity))
							if away.is_empty() or float(cohort.hunger) <= 0.0: continue
							var actions: Variant = there.site_controller.person_actions
							var body: Dictionary = actions._person(int(identity), false)
							var context: Dictionary = SiteController.ResidentLife.Housing.context(there, int(identity), str(away.house_id), -2, false, false)
							var unit := int(body.unit)
							var values: PackedFloat64Array = body.owner._soldier_values(unit)
							print("VILLAGE_STOCK STEP %d at (%.5f, %.5f) speed (%.4f, %.4f) controlled %s siege %s" % [int(identity), values[14], values[15], values[22], values[23], str(there.crowd_site.crowd.controlled_step_state(unit)), str(body.owner.native_siege_state(unit))])
							for other: Variant in there.crowd_site._index_by_id:
								var near: Dictionary = there.crowd_site.combat_target(int(other))
								if int(other) != int(identity) and Vector2(near.cell - body.cell).length() < 2.5: print("VILLAGE_STOCK NEAR %d: %d at %s" % [int(identity), int(other), str(near.cell)])
							print("VILLAGE_STOCK AWAY %d at %s home %s busy %s moving %s working %s job %s context %s %s schedule %s" % [int(identity), str(body.cell), str(there.terrain.cell_from_index(int(away.cell))), str(actions.is_busy(int(identity))), str(body.get("moving")), str(there.site_controller.work_team.is_assigned(int(identity))), JSON.stringify(actions._jobs.get(str(identity), {}).get("kind", "")) + str(actions._jobs.get(str(identity), {}).get("paused", "")), str(context.get("code", context.get("ok"))), str(context.get("message", "")).left(80), JSON.stringify(there.site_controller.last_resident_schedule)])
						print("VILLAGE_STOCK COHORT v%s hunger %.2f coverage %.2f: %s" % [str(entry.version), float(cohort.hunger), float(cohort.coverage), " ".join(rows)])
				print("VILLAGE_STOCK HOUR %d %s: %d at work, %s, %d pantry" % [hour, id, working, JSON.stringify(Aftermath.stock_of(there.terrain.site, int(there.terrain.site.settlement.owner_faction))), int(_pantry(there.terrain.site))])
		if not lab.site_controller._original_step_fault.is_empty():
			_end("fault %s" % str(lab.site_controller._original_step_fault).left(300))
			return
		if (float(slot.control.logical_game_seconds) - began) / DAY >= next_save:
			var saved: Dictionary = lab.site_controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "")
			if saved.get("ok", false):
				next_save += 1.0
				if raided < raids and int(next_save) % 2 == 1:
					var band := -1
					for key: Variant in slot.control.faction_registry.entries:
						if RegionFactionQuery.is_bandit(slot.control.faction_registry, int(slot.control.faction_registry.entries[key].faction_id)): band = int(slot.control.faction_registry.entries[key].faction_id)
					var target: String = _only() if not _only().is_empty() else villages[0]
					var now_stock: Dictionary = Formula.stock_left(slot, "%s:%s" % [str(slot.pin.atlas_id), target], Formula.stock_now(slot, Formula.summary(slot, target).summary))
					var taken := {"grain": mini(30, int(now_stock.get("grain", 0)))}
					var written: Dictionary = Bandit.raided(slot.control.faction_registry, band, "%s:%s" % [str(slot.pin.atlas_id), target], int(float(slot.control.logical_game_seconds) / DAY), taken, str(slot._marker.sites[target].path), float(slot.control.logical_game_seconds))
					var written_down: Dictionary = lab.site_controller._commit_diplomacy(written, "")
					print("VILLAGE_STOCK RAID %s day %d: %s of %s, saved %s" % [target, int(float(slot.control.logical_game_seconds) / DAY), JSON.stringify(taken), JSON.stringify(now_stock), str(written_down.get("ok", false))])
					raided += 1
	lab.set_process(false)
	print("VILLAGE_STOCK RAN %d s after start" % [Time.get_ticks_msec() / 1000])
	for village: String in villages:
		if not _only().is_empty() and village != _only(): continue
		var id := "%s:%s" % [str(slot.pin.atlas_id), village]
		var from := Time.get_ticks_msec()
		var expected: Dictionary = Formula.stock_left(slot, id, Formula.stock_now(slot, Formula.summary(slot, village).summary))
		print("VILLAGE_STOCK PROJECTED %s %s" % [village, JSON.stringify(expected)])
		var bound: Dictionary = {}
		var longest := 0
		for attempt: int in range(8000):
			var call_ms := Time.get_ticks_msec()
			bound = lab._region_gameplay_owner_lab(id, "cold_exact")
			longest = maxi(longest, Time.get_ticks_msec() - call_ms)
			if Time.get_ticks_msec() - call_ms > 800: print("VILLAGE_STOCK CALL %d ms, attempt %d, receipt %s" % [Time.get_ticks_msec() - call_ms, attempt, JSON.stringify(bound.get("cold_replay", {"code": bound.get("code", "ok")})).left(300)])
			if bound.get("ok", false) or not str(bound.get("code", "")) in ["PENDING", "BUSY"]: break
			if str(bound.code) == "BUSY":
				if attempt == 0: print("VILLAGE_STOCK BUSY with '%s' to %.1f, now %.1f" % [lab._cold_replay_id, lab._cold_replay_target, float(slot.control.logical_game_seconds)])
				lab._process(1.0 / 30.0)
			await process_frame
		if not bound.get("ok", false):
			print("VILLAGE_STOCK BIND %s refused %s" % [village, JSON.stringify(bound).left(1500)])
			continue
		var there: TerrainLab = slot._region_original_labs[id]
		there.crowd_site.sync_to_site()
		print("VILLAGE_STOCK AFTER %s %.2f days, bind %d ms (longest %d): %s" % [village, (float(slot.control.logical_game_seconds) - began) / DAY, Time.get_ticks_msec() - from, longest, JSON.stringify(_held(there.terrain.site)).left(600)])
	_end("complete")
