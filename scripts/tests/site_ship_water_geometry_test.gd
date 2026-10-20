extends "res://scripts/tests/site_ship_journey_edge_test.gd"
## OUTPUT-only fixed-source scope. Original Controller/Slot river journey.
## No soil source is invented; natural waterfront Runtime scope is separate.
const GEOMETRY_OUT := "res://output/site_ship_close_20261004/water_geometry_test"
const PF = preload("res://scripts/terrain_lab/person_fatigue.gd")
var geometry_complete: bool = false
var yard_id: String = ""
var bridge_id: String = ""
var house_id: String = ""
var spare_boat: String = ""
var land_team: TerrainArmy
var land_ids: Array[int] = []
var checked_inputs: Array[String] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not geometry_complete and Time.get_ticks_msec() > deadline: _must(false, "Water geometry internal deadline")
	return false

func _must(condition: bool, label: String) -> bool:
	if condition: return true
	if not geometry_complete:
		geometry_complete = true
		push_error("SITE_SHIP_WATER_GEOMETRY_FAIL: " + label)
		quit(1)
	return false

func _asset(name: String, bytes: PackedByteArray) -> Dictionary:
	var path: String = GEOMETRY_OUT.path_join(name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not _must(file != null, "Original fixed source write"): return {}
	file.store_buffer(bytes)
	file.close()
	return {"path":name, "sha256":FileAccess.get_sha256(path)}

func _edge_fixture() -> bool:
	# The parent opens OUT/manifest.json; all actual Site files and assets remain
	# isolated here. Only this candidate changes that original fixture entrypoint.
	if not _must(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GEOMETRY_OUT)) == OK, "Geometry output directory"): return false
	var accepted: TerrainData = _fixed_coast()
	if accepted == null: return false
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.bind_terrain(accepted)
	_freeze_processes()
	controller = lab.site_controller
	controller.save_root = GEOMETRY_OUT
	controller.save_path = GEOMETRY_OUT.path_join("before_fixed_world.json")
	world_id = "water_geometry_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(GEOMETRY_OUT.path_join("manifest.json"), world_id, "slot", FROM, true)
	if not _must(opened.ok, "Original fixed source world: " + str(opened)): return false
	_freeze_processes()
	team = lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = 4
	var shore: Array[Vector2i] = [Vector2i(11,21),Vector2i(12,21),Vector2i(13,21),Vector2i(14,21)]
	if not _must(team.deploy_at(lab.terrain, lab.character, lab.npc, shore) and team.enable_combat(false,0), "Four original journey people"): return false
	lab.terrain.site.army_next_team = team.team_id + 1
	lab.terrain.site.army_trial_active = true
	team_id = team.team_id
	for index: int in range(4):
		team.combat_units[index].logistics = true
		people.append(team.combat_identity(index))
	var pool: Dictionary = controller._enable_team_supply(team)
	if not _must(not pool.is_empty(), "Original supply"): return false
	pool.inventory.grain = 8 # One original initial stock, as in C's edge fixture.
	var deployed: Dictionary = controller.vehicles.deploy_ship(team, "river", Vector2i(10,19),Vector2i.LEFT,true)
	if not _must(deployed.ok, "Original real river: " + str(deployed)): return false
	boat_id = str(deployed.vehicle_id)
	var berths: Array[int] = [0,1,5,6]
	for index: int in range(4):
		if not _walk(index,Vector2i(10,20)): return false
		var boarded: Dictionary = controller.person_actions.begin_ship_board(people[index],boat_id,people[index],berths[index],true)
		if not _must(boarded.ok, "Real original board") or not _finish_job(people[index]): return false
	var loaded: Dictionary = controller.transfer_ship_supply(team,"shore:%d" % lab.terrain.index(Vector2i(10,20)),"vehicle:"+boat_id,{"grain":8},0.0,people[0],true)
	if not _must(loaded.ok, "Real original grain contact: " + str(loaded)): return false
	var helm: Dictionary = controller.person_actions.begin_ship_helm(people[0],boat_id,people[0],true)
	if not _must(helm.ok, "Original physical helm") or not _finish_job(people[0]): return false
	lab.terrain.site.controlled_person_id = people[0]
	return true

func _construct(kind: String, position: Vector2i, extent: Vector2i, options: Dictionary) -> String:
	var layout: Dictionary = Runtime.building_cells(lab.terrain,kind,position,extent,options)
	if not _must(layout.ok, "Legal original feature layout " + kind + ": " + str(layout)): return ""
	var built: Dictionary = Runtime.request_build(lab.terrain,kind,layout.cells,Callable(),options)
	if not _must(built.ok, "Original paid construction " + kind + ": " + str(built)): return ""
	var key: String = str(built.feature)
	var feature: Dictionary = lab.terrain.site.features[key]
	# Existing Runtime feature worker transaction, initial fixture setup only.
	# This is not an extra person/worker row or direct feature progress write.
	var task: Dictionary = {"target":"feature:"+key,"action":"construct","cell":int(feature.entrance),"mode":"work","status":"","progress":0.0}
	Runtime._feature_work(lab.terrain,key,float(feature.work),Callable(),Callable(),task,{},20,0)
	if not _must(feature.stage == "complete" and Runtime.validate_feature_layout(lab.terrain,feature).ok,"Original feature work complete and strict shape " + kind): return ""
	return key

func _geometry_setup() -> bool:
	lab.terrain.site.capacity = 100000
	for resource: String in ["wood","stone","fiber","iron","rope","clay","pottery","tools"]: lab.terrain.site.inventory[resource] = 5000
	# Fixed geography deliberately has no soil source. Do not invent foundation
	# for a house/shipyard: original ROAD/BRIDGE alone need no such source.
	for value: int in lab.terrain.foundation:
		if not _must(value == 0, "Fixed source soil must remain original UNKNOWN/zero"): return false
	bridge_id = _construct("bridge",Vector2i(40,68),Vector2i(1,3),{"layout_version":1,"quarter":0,"material":"wood","owner_faction":0})
	if bridge_id.is_empty(): return false
	land_team = lab.combat_armies[1]
	land_team.role = "logistics"
	land_team.faction_id = 0
	land_team.team_id = lab._next_army_identity()
	land_team.roster_size = 2
	var shore: Array[Vector2i] = [Vector2i(71,41),Vector2i(70,41)]
	if not _must(land_team.deploy_at(lab.terrain,lab.character,lab.npc,shore) and land_team.enable_combat(false,0),"Two original resident land workers"): return false
	for index: int in range(2):
		land_team.combat_units[index].logistics = false # Original resident workers, not dedicated hauling.
		land_ids.append(land_team.combat_identity(index))
	lab.terrain.site.army_next_team = land_team.team_id+1
	return _capture_journey()

func _navigation() -> PackedByteArray:
	var state: Array = []
	for index: int in range(lab.terrain.size.x*lab.terrain.size.y):
		if lab.terrain.surface_types[index] != TerrainData.Surface.WATER: continue
		var cell: Vector2i = lab.terrain.cell_from_index(index)
		var edges: Array[bool] = []
		for direction: Vector2i in TerrainData.DIRECTIONS: edges.append(lab.terrain.can_water_step(cell,cell+direction))
		state.append([index,lab.terrain.can_navigate_water(cell),edges])
	return var_to_bytes(state)

func _refuse(label: String, operation: Callable) -> bool:
	var before: PackedByteArray = var_to_bytes(lab.terrain.site)
	var navigation: PackedByteArray = _navigation()
	var result: Dictionary = operation.call()
	if not _must(not result.ok and result.code == "BUSY" and var_to_bytes(lab.terrain.site) == before and _navigation() == navigation,"Atomic original input rejected before materials/HP/refs/navigation mutation: " + label + ": " + str(result)): return false
	checked_inputs.append(label)
	return true

func _complete_original_pending(prepared: Dictionary, require_pending: bool = false) -> bool:
	if not prepared.ok and str(prepared.get("code","")) == "PENDING":
		var cells: Array[int] = [lab.terrain.index(Vector2i(75,40))]
		if not _refuse("pending_land_new",func() -> Dictionary: return Runtime.request_build(lab.terrain,"road",cells,Callable(),{"owner_faction":0})): return false
		if not _refuse("pending_zone",func() -> Dictionary: return Runtime.add_zone(lab.terrain,Rect2i(20,30,10,10),-1,"harvest")): return false
		# The original team.work duty decides who may request a work assignment.
		# Use that real decider so the pending gate, not the authority refusal, is what this check exercises.
		var work_decider: int = land_team.duty_decider("team.work")
		if not _must(work_decider > 0,"Original team.work duty has no decider while the resident is pending"): return false
		var before: PackedByteArray = var_to_bytes(lab.terrain.site)
		controller.enable_worker()
		controller.release_worker()
		var person: Dictionary = lab._combat_target(land_ids[1])
		var workers: Array[int] = [land_ids[1]]
		var assigned: Dictionary = controller.work_team.assign(land_team,workers,work_decider)
		if not _must(not assigned.ok and assigned.code == "BUSY" and not person.is_empty() and not controller._can_command_person(person) and controller._work_person_unavailable(land_ids[1]) and var_to_bytes(lab.terrain.site) == before,"Pending original Worker / resident WorkTeam inputs changed the source"): return false
		checked_inputs.append("pending_original_worker_and_land_workteam")
	return super._complete_original_pending(prepared,require_pending)

func _q_query() -> Callable:
	return func(identity: String) -> Dictionary:
		return Runtime.ok("Original Transport whole boat Q",{"load":controller.vehicles.ship_load(identity),"capacity":controller.vehicles.capacity_of(controller.vehicles.records()[identity])})

func _active_guards() -> bool:
	var data: TerrainData = lab.terrain
	var boat: Dictionary = controller.vehicles.records()[boat_id]
	var before: PackedByteArray = var_to_bytes(data.site)
	var ordered: Dictionary = controller.vehicles.ship_order(boat_id,"forward",TerrainArmy.INVALID_CELL,people[0],true)
	var spawned: Dictionary = controller.vehicles.deploy_ship(team,"ferry",Vector2i(50,19),Vector2i.UP,true)
	if not _must(not ordered.ok and ordered.code == "BUSY" and not spawned.ok and spawned.code == "BUSY" and var_to_bytes(data.site) == before,"Active original source ship / new deployment did not freeze"): return false
	checked_inputs.append("active_source_ship_new_deploy")
	var bridge_cells: Array[int] = [data.index(Vector2i(45,68)),data.index(Vector2i(45,69)),data.index(Vector2i(45,70))]
	if not _must(Runtime.bridge_layout(data,bridge_cells,0).ok,"Genuine fixed channel has both original land banks"): return false
	if not _refuse("active_bridge_new",func() -> Dictionary: return Runtime.request_build(data,"bridge",bridge_cells,Callable(),{"layout_version":1,"quarter":0,"material":"wood","owner_faction":0})): return false
	if not _refuse("active_bridge_cancel",func() -> Dictionary: return Runtime.cancel_feature(data,bridge_id,Callable(),0)): return false
	var edge_level: Array[int] = [data.index(Vector2i(35,20))]
	if not _refuse("active_adjacent_water_level",func() -> Dictionary: return Runtime.request_build(data,"level",edge_level,Callable(),{"owner_faction":0})): return false
	# The selected original hull must reject raw repair inputs before looking up
	# a facility. Empty feature_id expresses no selected facility, not a fake one.
	if not _refuse("active_selected_ship_repair",func() -> Dictionary: return Runtime.request_ship_repair(data,boat_id,"",team_id,false,_q_query())): return false
	if not _refuse("active_selected_ship_cancel_repair",func() -> Dictionary: return Runtime.cancel_ship_repair(data,boat_id,team_id)): return false
	return _must(boat.move.is_empty(),"Coarse source hull never acquired a Site movement")

func _land_and_biology() -> bool:
	var data: TerrainData = lab.terrain
	var navigation: PackedByteArray = _navigation()
	var built: Dictionary = Runtime.request_build(data,"road",[data.index(Vector2i(70,40))],Callable(),{"owner_faction":0})
	if not _must(built.ok,"Coarse journey wrongly froze ordinary land construction: " + str(built)): return false
	var key: String = str(built.feature)
	var people_to_work: Array[int] = [land_ids[1]]
	var worker: Dictionary = controller.person_actions._person(land_ids[1])
	if not _must(not worker.is_empty() and worker.owner == land_team and not bool(worker.body.get("logistics",false))
		and not controller._work_person_unavailable(land_ids[1]), "Original resident body/work guard still unavailable before normal land WORK"): return false
	var normal_decider: int = land_team.duty_decider("team.work")
	if not _must(normal_decider > 0,"Original team.work duty has no decider for normal land WORK"): return false
	var assigned: Dictionary = controller.work_team.assign(land_team,people_to_work,normal_decider)
	if not _must(assigned.ok,"Coarse source land resident cannot take original work: " + str(assigned)): return false
	var clock_before: float = RegionSaveSlot._site_seconds(data)
	var fatigue_before: float = PF.read(team.combat_units[0])
	var progress_before: float = float(data.site.features[key].progress)
	for step: int in range(80):
		if not _step(0.05): return false
		if float(data.site.features[key].progress) > progress_before: break
	if not _must(RegionSaveSlot._site_seconds(data) > clock_before and PF.read(team.combat_units[0]) > fatigue_before and float(data.site.features[key].progress) > progress_before and _navigation() == navigation and controller.ship_journey_active(),"Original coarse crew biology/GAME and resident land work did not advance with water geometry unchanged"): return false
	return _must(controller._capture_for_save().ok and Store._validate_state(data,data.site).ok,"Strict original Store rejects active source after lawful resident work")

func _run() -> void:
	if not _edge_fixture() or not _geometry_setup(): return
	var boat: Dictionary = controller.vehicles.records()[boat_id]
	var sailed: Dictionary = controller.vehicles.ship_order(boat_id,"sail",Vector2i(6,19),people[0],true)
	if not _must(sailed.ok,"Original legal source edge sailing"): return
	for step: int in range(40):
		if boat.move.is_empty() and boat.command.is_empty(): break
		controller.vehicles.update_ships(5.0)
	if not _must(boat.move.is_empty() and boat.command.is_empty() and lab.terrain.cell_from_index(int(boat.cell)) == Vector2i(6,19),"Original journey river truly reached its edge"): return
	if not _visited_pending(): return # Actual original cold debt + sole finish_tick; checks our extra pending inputs.
	if not _capture_journey(): return
	var boats: Array[String] = [boat_id]
	var departed: Dictionary = controller.begin_ship_journey(boats,TO,Vector2i(99,19),Vector2i.LEFT,people[0])
	if not _complete_original_pending(departed): return
	if not _active_guards() or not _land_and_biology(): return
	var report: FileAccess = FileAccess.open(GEOMETRY_OUT.path_join("report.json"),FileAccess.WRITE)
	if not _must(report != null,"Geometry report"): return
	report.store_string(JSON.stringify({"status":"SITE_SHIP_WATER_GEOMETRY_PASS","inputs":checked_inputs,"source_manifest_sha256":FileAccess.get_sha256(GEOMETRY_OUT.path_join("manifest.json")),"source_fingerprint":lab.terrain.fingerprint(),"scope":"Actual original fixed-source river/four original crew/true seam journey, PENDING public road/zone/Worker/WorkTeam freeze, source ship/deploy and genuine channel bridge/adjacent-water level/selected hull raw repair guards, original resident ROAD work and shared crew biology/GAME, unchanged water vertices/edges and strict fixed-source Store. Fixed soil stays zero/UNKNOWN. Waterfront facilities and fatal repair receipts are separately tested on untouched natural procedural terrain by site_ship_water_facility_guard_test; they are not asserted to exist in this fixed Site. No hot terrain/soil, duplicate owner, full gameplay/render/performance claim."},"\t"))
	report.close()
	geometry_complete = true
	lab.queue_free()
	print("SITE_SHIP_WATER_GEOMETRY_PASS")
	quit(0)

func _fixed_coast() -> TerrainData:
	if not _must(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GEOMETRY_OUT)) == OK, "Fixed coast evidence directory failed"): return null
	var summary := PackedByteArray()
	summary.resize(25)
	summary.fill(2)
	var summary_record := _asset("summary.u8", summary)
	summary_record.merge({"size": [5, 5], "site_origin": [-2, -2], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	# The source covers the origin and adjacent Sites, including THEIR geographic halos.
	# Water is an ocean mask with unknown seabed elevation; land is measured 0.
	var elevation := PackedByteArray()
	var levels := PackedByteArray()
	var water := PackedByteArray()
	elevation.resize(500 * 500 * 2)
	levels.resize(500 * 500)
	water.resize(500 * 500)
	for y in range(500):
		var north := -400 + (499 - y) * 2 + 1
		for x in range(500):
			var index := y * 500 + x
			var ocean := north >= 160 or (north >= 58 and north < 64)
			elevation.encode_s16(index * 2, -32767 if ocean else 0)
			water[index] = 2 if ocean else 0
	var height_record := _asset("coast.height.zlib", elevation.compress(FileAccess.COMPRESSION_DEFLATE))
	var level_record := _asset("coast.levels.zlib", levels.compress(FileAccess.COMPRESSION_DEFLATE))
	var water_record := _asset("coast.water.zlib", water.compress(FileAccess.COMPRESSION_DEFLATE))
	height_record.merge({"id": "straight_coast", "origin": [-400, -400], "size": [500, 500], "spacing_m": 2,
		"encoding": "int16_le_zlib", "row_order": "north_to_south", "nodata": -32767,
		"derived": {"encoding": "u8_zlib", "levels_path": level_record.path, "levels_sha256": level_record.sha256, "water_path": water_record.path, "water_sha256": water_record.sha256}})
	var manifest := {"format": 1, "synthetic_fixture": true, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": 1,
		"base_revision": "ship-water-geometry-fixed-coast-v2-halo", "crs": "EPSG:3826",
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary_record, "elevation_tiles": [height_record], "sources": [{"title": "Synthetic fixed straight coast with separate inland three-cell channel; geometry test only"}]}
	var file := FileAccess.open(GEOMETRY_OUT.path_join("manifest.json"), FileAccess.WRITE)
	if not _must(file != null, "Cannot write fixed-coast manifest"): return null
	file.store_string(JSON.stringify(manifest, "", true, true))
	file.close()
	atlas = Atlas.new()
	if not _must(atlas.load_manifest(GEOMETRY_OUT.path_join("manifest.json")).ok, "Original fixed-coast manifest rejected"): return null
	var built: Dictionary = atlas.make_terrain_data(0, 0)
	if not _must(built.ok and built.data.size == Vector2i(100, 100), "Original fixed-coast 100x100 adapter rejected"): return null
	var data: TerrainData = built.data
	Env.initialize(data, str(built.base.site_id))
	return data

