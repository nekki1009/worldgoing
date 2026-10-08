extends "res://scripts/tests/site_ship_repair_test.gd"
## Original Runtime public guard contract on untouched generated soil/water.
## This fixture supplies only original metadata Callable query results. It has
## no journey token/clock/person/ship owner and claims no fixed-Site migration.
const FACILITY_OUT := "res://output/site_ship_close_20261004/water_facility_guard_test"
var query_state: Dictionary = {"active":false,"pending":false,"selected":""}
var facility_inputs: Array[String] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()

func _must_facility(condition: bool, label: String) -> bool:
	if condition and Time.get_ticks_msec() <= deadline: return true
	push_error("SITE_SHIP_WATER_FACILITY_GUARD_FAIL: " + label)
	run_completed = true
	quit(1)
	return false

func _navigation_facility(data: TerrainData) -> PackedByteArray:
	var state: Array = []
	for index: int in range(data.size.x*data.size.y):
		if data.surface_types[index] != TerrainData.Surface.WATER: continue
		var cell: Vector2i = data.cell_from_index(index)
		var edges: Array[bool] = []
		for direction: Vector2i in TerrainData.DIRECTIONS: edges.append(data.can_water_step(cell,cell+direction))
		state.append([index,data.can_navigate_water(cell),edges])
	return var_to_bytes(state)

func _bind_query_contract(data: TerrainData) -> void:
	data.set_meta(&"region_operation_pending",func() -> bool: return bool(query_state.pending))
	data.set_meta(&"ship_journey_active",func() -> bool: return bool(query_state.active))
	data.set_meta(&"ship_vehicle_in_journey",func(identity: String) -> bool: return not str(query_state.selected).is_empty() and identity == str(query_state.selected))

func _refuse_facility(data: TerrainData, label: String, operation: Callable) -> bool:
	var before: PackedByteArray = var_to_bytes(data.site)
	var navigation: PackedByteArray = _navigation_facility(data)
	var result: Dictionary = operation.call()
	if not _must_facility(not result.ok and result.code == "BUSY" and var_to_bytes(data.site) == before and _navigation_facility(data) == navigation,"Atomic original input before materials/HP/receipt/refs/navigation mutation: " + label + ": " + str(result)): return false
	facility_inputs.append(label)
	return true

func _natural_house(data: TerrainData) -> String:
	for y: int in range(4,data.size.y-4):
		for x: int in range(4,data.size.x-4):
			var options: Dictionary = {"owner_faction":0,"quarter":0}
			var layout: Dictionary = Runtime.building_cells(data,"house",Vector2i(x,y),Vector2i(3,3),options)
			if not layout.ok: continue
			var cells: Array[int] = []; cells.assign(layout.cells)
			var preview: Dictionary = Runtime.preview_build(data,"house",cells,Callable(),options)
			if not preview.ok or not preview.clearing.is_empty(): continue
			var built: Dictionary = Runtime.request_build(data,"house",cells,Callable(),options)
			if not _must_facility(built.ok,"Original generated land admits original paid house"): return ""
			var identity: String = str(built.feature)
			var feature: Dictionary = data.site.features[identity]
			var task: Dictionary = {"target":"feature:"+identity,"action":"construct","cell":int(feature.entrance),"mode":"work","status":"","progress":0.0}
			Runtime._feature_work(data,identity,float(feature.work),Callable(),Callable(),task,{},20,0)
			if not _must_facility(feature.stage == "complete" and Runtime.validate_feature_layout(data,feature).ok,"Original generated house completes through Runtime work"): return ""
			return identity
	_must_facility(false,"No untouched generated foundation admits legal original house")
	return ""

func _natural_dock_probe(data: TerrainData, yard: Dictionary) -> Dictionary:
	# Independent original generation of exactly the same source. The existing
	# yard/hull are absent here, so they cannot cause an unrelated OCCUPIED exit.
	var probe: TerrainData = TerrainGenerator.generate(data.preset,data.seed_value,data.parameters)
	Env.initialize(probe,"water_facility_new_probe")
	probe.site.inventory = data.site.inventory.duplicate()
	probe.site.capacity = 100000
	var facing: Vector2i = Runtime.waterfront_facing(yard)
	var shore: Vector2i = data.cell_from_index(int(yard.launch_cell))-facing
	var options: Dictionary = {"owner_faction":0,"quarter":int(yard.quarter),"waterfront_version":1,"launch_cell":int(yard.launch_cell)}
	for offset: Vector2i in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]:
		var layout: Dictionary = Runtime.building_cells(probe,"dock",shore-offset,Vector2i(2,2),options)
		if not layout.ok: continue
		var cells: Array[int] = []; cells.assign(layout.cells)
		var preview: Dictionary = Runtime.preview_build(probe,"dock",cells,Callable(),options)
		if preview.ok and preview.clearing.is_empty(): return {"data":probe,"cells":cells,"options":options}
	_must_facility(false,"Original natural shore needs a legal dock probe before the active guard")
	return {}

func _facility_contract() -> bool:
	# The existing repair fixture searches unmodified TerrainGenerator sources
	# and pays/builds its shipyard through original Runtime. Never call the old
	# controlled _ship_fixture with a rewritten plot for this scope.
	var fixture: Dictionary = _natural_repair_fixture()
	if not _must_facility(not fixture.is_empty(),"Original natural facility fixture"): return false
	var data: TerrainData = fixture.data
	var vehicle: Dictionary = fixture.vehicle
	var yard_id: String = str(fixture.feature_id)
	var yard: Dictionary = data.site.features[yard_id]
	for resource: String in ["wood","stone","fiber","iron","rope","clay","pottery","tools"]: data.site.inventory[resource] = 10000 # One explicit initial resource stock.
	var house_id: String = _natural_house(data)
	if house_id.is_empty(): return false
	var dock: Dictionary = _natural_dock_probe(data,yard)
	if dock.is_empty(): return false
	if not _must_facility(int(yard.get("civil_version",0)) == 1 and int(yard.get("building_grade",0)) == 1 and float(yard.parts.body.hp) == Runtime.civil_max_hp(yard),"NEW real shipyard retains original civil version/grade/body HP"): return false
	_bind_query_contract(data)
	_bind_query_contract(dock.data)
	query_state.pending = true
	if not _refuse_facility(data,"pending_land_upgrade",func() -> Dictionary: return Runtime.request_upgrade(data,house_id,0)): return false
	query_state.pending = false
	query_state.active = true
	var dock_cells: Array[int] = []; dock_cells.assign(dock.cells)
	if not _refuse_facility(dock.data,"active_waterfront_new",func() -> Dictionary: return Runtime.request_build(dock.data,"dock",dock_cells,Callable(),dock.options)): return false
	if not _refuse_facility(data,"active_waterfront_cancel",func() -> Dictionary: return Runtime.cancel_feature(data,yard_id,Callable(),0)): return false
	if not _refuse_facility(data,"active_waterfront_upgrade",func() -> Dictionary: return Runtime.request_upgrade(data,yard_id,0)): return false
	if not _refuse_facility(data,"active_new_launch",func() -> Dictionary: return Runtime.begin_ship_build(data,yard_id,"ferry",1,0)): return false
	query_state.selected = "1"
	if not _refuse_facility(data,"active_selected_ship_repair",func() -> Dictionary: return Runtime.request_ship_repair(data,"1",yard_id,1,false,_q(data))): return false
	if not _refuse_facility(data,"active_selected_ship_cancel_repair",func() -> Dictionary: return Runtime.cancel_ship_repair(data,"1",1)): return false
	query_state.selected = ""
	var repair: Dictionary = Runtime.request_ship_repair(data,"1",yard_id,1,false,_q(data))
	if not _must_facility(repair.ok,"Original stationary nonselected hull repair remains permitted: " + str(repair)): return false
	var stations: Array[Dictionary] = Runtime.ship_repair_work_slots(data,vehicle)
	if not _must_facility(not stations.is_empty(),"Original genuine generated facility repair station"): return false
	var worked: Dictionary = Runtime.advance_ship_repair_work(data,"1",0.001,data.cell_from_index(int(stations[0].cell)),int(stations[0].slot),1)
	if not _must_facility(worked.ok,"Original paid receipt accrued actual Runtime work"): return false
	if not _refuse_facility(data,"active_fatal_facility_preserves_receipt_hp_cargo",func() -> Dictionary: return Runtime.damage_structure_part(data,yard_id,"body",100000.0)): return false
	var navigation_before: PackedByteArray = _navigation_facility(data)
	if not _must_facility(Runtime.damage_structure_part(data,yard_id,"body",1.0).ok and _navigation_facility(data) == navigation_before,"Original nonfatal facility HP changes without geometry change"): return false
	if not _refuse_facility(data,"active_nonfatal_facility_new_repair",func() -> Dictionary: return Runtime.request_repair(data,yard_id,"body",0)): return false
	if not _must_facility(not vehicle.naval.repair.is_empty() and Runtime.validate_ship_repair(data,vehicle).ok,"Frozen fatal facility retains strict original repair receipt"): return false
	if not _must_facility(Runtime.cancel_ship_repair(data,"1",1).ok and vehicle.naval.repair.is_empty(),"Original nonselected receipt cancellation retains unused cargo"): return false
	return _must_facility(var_to_bytes([data.height_levels,data.flags,data.surface_types,data.ramp_edges,data.foundation,data.water_kind,data.water_body]) == fixture.ground,"Natural feature guard never rewrites original ground/soil/water")

func _run() -> void:
	if not _facility_contract(): return
	if not _must_facility(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FACILITY_OUT)) == OK,"Facility report directory"): return
	var file: FileAccess = FileAccess.open(FACILITY_OUT.path_join("report.json"),FileAccess.WRITE)
	if not _must_facility(file != null,"Facility report write"): return
	file.store_string(JSON.stringify({"status":"SITE_SHIP_WATER_FACILITY_GUARD_PASS","inputs":facility_inputs,"scope":"Original Runtime public guard contract with original metadata Callable inputs on unchanged natural TerrainGenerator foundation/water and actual original paid civil facilities/ship receipt. Initial hull is original fixture state; no real journey token, person migration, Site gameplay worker route or full Store roundtrip is claimed here. Fixed-source real journey/work/bio/Store is separately covered by site_ship_water_geometry_test; natural full Store and original worker repair are separately covered by site_ship_repair_test."},"\t"))
	file.close()
	TerrainArmy.release_contact_source()
	run_completed = true
	print("SITE_SHIP_WATER_FACILITY_GUARD_PASS")
	quit(0)
