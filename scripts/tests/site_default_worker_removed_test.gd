extends SceneTree
## Main-scene regression: removing the old camp actor must not remove Army work.

const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const OUT := "res://output/remove_default_worker_20260919/test"
var deadline := 0
var lab: TerrainLab

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 90000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("SITE DEFAULT WORKER REMOVED deadline")
		quit(1)
	return false

func _assert_absent() -> void:
	var ui: SiteController = lab.site_controller
	assert(lab.npc == null and lab.find_child("CommandTestNPC", true, false) == null)
	assert(lab.find_child("EnableWorker", true, false) == null and lab.find_child("StopWorker", true, false) == null)
	assert(lab.combat_actors.size() == 1 and lab.combat_actors[0] == lab.character)
	assert(lab._combat_target(2).is_empty() and ui.person_actions._person(2).is_empty())
	assert(not ui._all_supply_members().has(2) and ui.captivity_supply._home(2).is_empty())
	assert(not lab.terrain.site.get("worker_enabled", false))
	assert(not lab.terrain.site.get("person_supply", {}).has("2"))
	for node: Node in lab.find_children("*", "", true, false):
		assert(not node is TerrainTestNPC, "No default worker node or fallback marker may remain")
	for occupants: Array in lab._ranged_occupants().values():
		for person: Dictionary in occupants:
			assert(int(person.id) != 2, "Removed worker cannot block fire or receive combat damage")
	ui.selected = lab.character.terrain_cell
	assert(ui._selected_people().has(lab.character.person_id))
	assert(not ui._selected_people().has(2))
	ui.update_ui()

func _round_trip(name: String) -> void:
	lab.site_controller._capture_positions()
	assert(lab.terrain.site.actors.keys() == ["player"])
	var result := Store.save(lab.terrain, OUT + "/" + name + ".json")
	assert(result.ok, str(result))
	var loaded := Store.load_site(OUT + "/" + name + ".json")
	assert(loaded.ok, str(loaded))
	assert(loaded.data.site.actors.keys() == ["player"])
	lab.bind_terrain(loaded.data)
	lab.site_controller._auto_save_blocked = true
	_assert_absent()

func _reachable_timber() -> String:
	var ui: SiteController = lab.site_controller
	var data := lab.terrain
	var origin := lab.army.cells[1]
	var keys := data.resource_base.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return data.cell_from_index(int(data.resource_base[a].cell)).distance_squared_to(origin) < data.cell_from_index(int(data.resource_base[b].cell)).distance_squared_to(origin))
	var threats := {}
	var blocked := func(cell: Vector2i) -> bool:
		return ui.work_team._occupied(cell, lab.army, 1) or lab._fatigue_threat(cell, lab.army.faction_id, lab.army, 1, threats)
	var depot := data.cell_from_index(int(data.site.depot_cell))
	var unloading: Array[Vector2i] = [depot]
	for direction: Vector2i in TerrainData.DIRECTIONS:
		unloading.append(depot + direction)
	for key: String in keys:
		var source := SiteEnvironment.resource(data, key)
		if int(source.kind) != SiteEnvironment.Kind.TIMBER or int(source.remaining) < 4:
			continue
		var target := SiteRuntime._reachable_work(data, origin, SiteEnvironment.work_cells(data, key), blocked)
		if target == TerrainArmy.INVALID_CELL or data.path_between(origin, target, blocked).size() > 24:
			continue
		if SiteRuntime._reachable_work(data, target, unloading, blocked) != TerrainArmy.INVALID_CELL:
			return key
	return ""

func _legacy_round_trip(vacant: Vector2i) -> void:
	# Explicit archived actor fixture; never add a worker node to the main scene.
	var loaded := Store.load_site(OUT + "/fresh.json")
	assert(loaded.ok, str(loaded))
	var data: TerrainData = loaded.data
	var old_worker := TerrainTestNPC.new()
	old_worker.person_id = 2
	old_worker.faction_id = lab.character.faction_id
	old_worker.visual_state.body_index = 1
	old_worker.data = data
	assert(old_worker.place(vacant, true))
	var appearance := HumanCharacter3DEditor.default_appearance(1)
	appearance.parts.cape = "none"
	old_worker._saved_appearance = appearance.duplicate(true)
	assert(SiteRuntime.seed_person_equipment(data, old_worker.item_state, 2, appearance).ok)
	data.site.actors.npc = old_worker.capture_state()
	data.site.worker.cell = data.index(vacant)
	data.site.worker.cargo = {"wood": 2, "arrow": 3}
	data.site.worker_enabled = true
	var personal := Sustain.create(SiteRuntime.now(data) * 60.0)
	assert(Sustain.add_members(personal, {2: data.site.actors.npc}, [2]).ok)
	personal.open_rations = 0.5
	data.site.person_supply = {"2": personal}
	var item_ids: Array = old_worker.item_state.item_ids.duplicate()
	assert(not item_ids.is_empty())
	old_worker.free()
	var old_path := OUT + "/legacy_worker.json"
	var saved := Store.save(data, old_path)
	assert(saved.ok, str(saved))
	var original_file := FileAccess.get_file_as_bytes(old_path)
	var migrated := Store.load_site(old_path)
	assert(migrated.ok, str(migrated))
	assert(migrated.data.site.actors.has("npc"), "Generic archive reads preserve explicit actor snapshots")
	var retired := Store.retire_default_worker(migrated.data)
	assert(retired.ok, str(retired))
	var once := var_to_bytes(migrated.data.site)
	assert(Store.retire_default_worker(migrated.data).ok)
	assert(var_to_bytes(migrated.data.site) == once, "Binding the migrated map again cannot duplicate loot")
	assert(FileAccess.get_file_as_bytes(old_path) == original_file, "Migration never rewrites the archived original")
	assert(migrated.data.site.actors.keys() == ["player"] and not migrated.data.site.person_supply.has("2"))
	assert(migrated.data.site.worker.cargo.is_empty())
	var found := false
	for bag: Dictionary in migrated.data.site.ground_loot.values():
		if int(bag.original_owner) != 2:
			continue
		assert(not found and int(bag.cell) == data.index(vacant))
		assert(bag.cargo == {"wood": 2, "arrow": 3} and is_equal_approx(float(bag.open_rations), 0.5))
		assert(bag.item_ids.size() == item_ids.size())
		for identity: String in item_ids:
			assert(bag.item_ids.has(identity))
			assert(migrated.data.site.item_records[identity].holder == bag.holder)
			assert(int(migrated.data.site.item_records[identity].original_owner) == 2)
		found = true
	assert(found, "Every old physical item, cargo unit and opened ration survives at the old ground cell")
	lab.bind_terrain(migrated.data)
	lab.site_controller._auto_save_blocked = true
	_assert_absent()
	_round_trip("legacy_migrated")
	# A registered relative is an established person, not disposable startup data.
	data.site.family = {"version": 1, "complete": true, "members": [{"site_id": str(data.site.id),
		"person_id": 2, "path": old_path, "label": "Archived relative", "age_years": 25}]}
	var family_path := OUT + "/legacy_family.json"
	assert(Store.save(data, family_path).ok)
	var family_file := FileAccess.get_file_as_bytes(family_path)
	var family_loaded := Store.load_site(family_path)
	assert(family_loaded.ok, str(family_loaded))
	var unchanged := var_to_bytes(family_loaded.data.site)
	assert(Store.retire_default_worker(family_loaded.data).code == "BUSY")
	assert(var_to_bytes(family_loaded.data.site) == unchanged)
	assert(FileAccess.get_file_as_bytes(family_path) == family_file)
	# Even a failure after legacy equipment seeding restores the whole candidate.
	var exhausted := Store.load_site(old_path)
	assert(exhausted.ok, str(exhausted))
	for identity: String in item_ids:
		exhausted.data.site.item_records.erase(identity)
	exhausted.data.site.actors.npc.erase("item_state")
	exhausted.data.site.next_loot = 2147483647
	assert(Store._validate_state(exhausted.data, exhausted.data.site).ok)
	var before_failure := var_to_bytes(exhausted.data.site)
	assert(not Store.retire_default_worker(exhausted.data).ok)
	assert(var_to_bytes(exhausted.data.site) == before_failure, "Failed item migration must roll back seeded equipment and all ownership")

func _real_legacy_round_trip() -> void:
	var path := "res://output/remove_default_worker_20260919/legacy_current.before.json"
	var original := FileAccess.get_file_as_bytes(path)
	var loaded := Store.load_site(path)
	# Known pre-existing rejection: original player #1 wears item #4, a cape,
	# without an office. The unchanged Store cape guard rejects it before binding.
	# This archive proves failure preservation, not successful worker retirement.
	assert(not loaded.ok and str(loaded.code) == "CAPE_ROLE_RESTRICTED", str(loaded))
	assert(FileAccess.get_file_as_bytes(path) == original)
	assert(float(lab.terrain.site.combat_left) <= 0.0)
	var current: TerrainData = lab.terrain
	lab.site_controller._auto_save_blocked = false
	lab.site_controller._load_path(path)
	assert(lab.terrain == current, "Rejected archive must not replace the current TerrainData")
	assert(lab.site_controller._auto_save_blocked, "Rejected archive must block automatic overwrite")
	assert(str(loaded.message) in lab.site_controller.message.text)
	assert("自動保存已暫停，原檔保留" in lab.site_controller.message.text)
	assert("已載入地圖" not in lab.site_controller.message.text)
	assert(FileAccess.get_file_as_bytes(path) == original)
	print("KNOWN PRE-EXISTING ARCHIVE REJECTION PRESERVED: CAPE_ROLE_RESTRICTED; player #1 has no cape-granting office; current scene and original file unchanged")

func _run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	var scene: String = ProjectSettings.get_setting("application/run/main_scene")
	assert(scene == "res://scenes/terrain_lab/TerrainLab.tscn")
	lab = (load(scene) as PackedScene).instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies:
		team.set_process(false)
	_assert_absent()
	# The former spawn is an ordinary ground cell, selectable and traversable.
	var vacant := lab._find_npc_spawn_cell()
	assert(lab.terrain.is_walkable(vacant) and vacant != lab.character.terrain_cell)
	assert(not lab.site_controller._actor_blocked(vacant, lab.character))
	assert(not lab.site_controller.reserves_cell(vacant))
	lab.site_controller.selected = vacant
	assert(lab.site_controller._selected_people().is_empty())
	lab._process(1.0)
	_round_trip("fresh")
	_legacy_round_trip(vacant)
	_real_legacy_round_trip()
	if "--startup-only" in OS.get_cmdline_user_args():
		print("SITE DEFAULT WORKER REMOVED CORE PASS: formal startup; no node/UI/person/occupancy/feeding; fresh and valid legacy save/load; item preservation; refused legacy archive remains unchanged. Army-work regression not run.")
		lab.queue_free()
		await process_frame
		quit(0)
		return
	var deployed := lab.start_melee_trial({"friendly_count": 2, "enemy_count": 1,
		"friendly_role": "work", "enemy_role": "logistics", "friendly_attack": false,
		"enemy_attack": false, "friendly_female_percent": 50, "enemy_female_percent": 0})
	assert(deployed.ok, str(deployed))
	var worker_id := lab.army.combat_identity(1)
	assert(lab.site_controller.work_team.active_ids() == [worker_id])
	assert(lab.army.role == "work" and lab.opposing_army.role == "logistics")
	_assert_absent()
	# Exercise the original supply owner with only the original deployed people.
	var entry: Dictionary = lab.site_controller._enable_team_supply(lab.army)
	assert(not entry.is_empty() and Sustain._ids(entry.sustain).size() == 2)
	assert(2 not in Sustain._ids(entry.sustain))
	var source_key := _reachable_timber()
	assert(not source_key.is_empty(), "The unchanged main map must offer reachable work and return access")
	var source := SiteEnvironment.resource(lab.terrain, source_key)
	var source_cell := lab.terrain.cell_from_index(int(source.cell))
	assert(SiteRuntime.add_zone(lab.terrain, Rect2i(source_cell, Vector2i.ONE), SiteEnvironment.Kind.TIMBER).ok)
	var initial_stock := int(lab.terrain.site.inventory.get("wood", 0))
	var saw_cargo := false
	lab.change_simulation_speed(2)
	for step in range(2400):
		lab._process(0.05)
		saw_cargo = saw_cargo or int(lab.army.combat_units[1].cargo.get("wood", 0)) > 0
		if saw_cargo and int(lab.terrain.site.inventory.get("wood", 0)) > initial_stock:
			break
		if step % 100 == 0:
			await process_frame
	assert(saw_cargo and int(lab.terrain.site.inventory.get("wood", 0)) == initial_stock + 4,
		"The real Army worker must harvest and physically return its batch after default-worker removal")
	assert(lab.terrain.site.worker.cargo.is_empty() and str(lab.terrain.site.worker.target).is_empty())
	_round_trip("working_team")
	assert(lab.site_controller.work_team.active_ids() == [worker_id])
	assert(lab.army.role == "work" and lab.opposing_army.role == "logistics")
	assert(int(lab.terrain.site.inventory.get("wood", 0)) == initial_stock + 4)
	print("SITE DEFAULT WORKER REMOVED PASS: formal main scene; no worker node/identity/selection/occupancy/combat/feeding; legacy goods/opened-food preserved, family guard atomic; original work team harvest and deposit; fresh/migrated/working-team save/load")
	lab.queue_free()
	await process_frame
	quit(0)
