extends "res://scripts/tests/site_siege_landing_contract_test.gd"
## Real ArmyCrowd/GD owner adapter; canonical headless helper launches this once.
const NativeSite = preload("res://scripts/terrain_lab/crowd_site.gd")

class NativeFixture extends Node2D:
	var terrain: TerrainData
	var crowd_site: Variant
	var combat_armies: Array[TerrainArmy] = []
	var combat_actors: Array[TerrainTestCharacter] = []
	var site_controller: Variant
	var crew := SiteWorkTeam.new()
	var threatened := false
	func controlled_person_id() -> int: return -1
	func _combat_target(identity: int) -> Dictionary: return crowd_site.siege_original_person(identity)
	func _fatigue_threat(_cell: Vector2i, _faction: int, _owner: Variant, _unit: int, _candidates: Dictionary) -> bool: return threatened
	func reserves_cell(cell: Vector2i) -> bool: return crowd_site.reserves_cell(cell)
	func close() -> void:
		crew.lab = null
		site_controller.vehicles.lab = null
		site_controller.vehicles.controller = null
		site_controller.free()
		site_controller = null
		crowd_site.free()
		queue_free()

func _require(condition: bool, message: String) -> bool:
	if condition: return true
	push_error(message)
	quit(1)
	return false

func _run() -> void:
	create_timer(55.0).timeout.connect(func() -> void: quit(90))
	if not _require(ClassDB.class_exists("ArmyCrowd"), "Native DLL is required; no GD fallback proof"): return
	var definition := _ladder_fixture()
	var data: TerrainData = definition.data
	var feature: Dictionary = definition.feature
	var lab := NativeFixture.new()
	lab.terrain = data
	root.add_child(lab)
	lab.site_controller = SiteController.new()
	lab.site_controller.lab = lab
	lab.site_controller.work_team = lab.crew
	lab.site_controller.person_actions.init(lab)
	lab.site_controller.vehicles.init(lab.site_controller)
	lab.crowd_site = NativeSite.new()
	lab.add_child(lab.crowd_site)
	var site: Variant = lab.crowd_site
	site.lab = lab
	site.crowd = ClassDB.instantiate("ArmyCrowd")
	site.crowd.setup(4, 987)
	if not _require(site.sync_terrain() and site.siege_native_supported() and site.crowd.has_method("charge_siege_work"), "Frozen native controlled-step/work-fatigue APIs missing"): return
	# An earlier global native index prevents accidental GD-array indexing.
	var dummy: int = site.crowd.add_formation(0, 4.5, 4.5, 0.0, 1, 1.0, 0, 0.0)
	if not _require(site.crowd.add_soldiers(dummy, PackedInt64Array([99]), PackedInt32Array([0]), PackedByteArray([1]), PackedInt32Array([0])) >= 0, "Native offset fixture failed"): return
	var group: int = site.crowd.add_formation(1, 23.5, 25.5, 0.0, 3, 1.0, 0, 0.0)
	var identities: Array[int] = [101, 102, 103]
	var first: int = site.crowd.add_soldiers(group, PackedInt64Array(identities), PackedInt32Array([0, 0, 0]), PackedByteArray([1, 1, 1]), PackedInt32Array([0, 0, 0]))
	if not _require(first == 1, "Native ladder members must retain their real global index offset"): return
	var slots := SiteRuntime.siege_ladder_work_slots(data, feature)
	var a := data.cell_from_index(int(slots[0].cell))
	var b := data.cell_from_index(int(slots[1].cell))
	var initial: Array[Vector2i] = [a + Vector2i(-1, 1), a + Vector2i(-1, 0), b]
	var starts := PackedFloat32Array()
	for cell: Vector2i in initial: starts.append_array(PackedFloat32Array([float(cell.x) + 0.5, float(cell.y) + 0.5]))
	if not _require(site.crowd.set_start_positions(first, starts), "Original pre-finalize start-position import failed"): return
	site.crowd.finalize()
	site.crowd.set_ai(false)
	site._records[99] = {"person_id": 99, "appearance": HumanCharacter3DEditor.default_appearance(), "item_state": SiteRuntime.new_item_state("person:99"), "cargo": {}}
	var rows: Array = []
	for identity: int in identities:
		var row := {"person_id": identity, "appearance": HumanCharacter3DEditor.default_appearance(), "item_state": SiteRuntime.new_item_state("person:" + str(identity)), "cargo": {}, "work_task": {}, "work_resting": false, "fatigue": 999.0}
		site._records[identity] = row
		rows.append(row)
	site.teams.append({"slot": 0, "team_id": 1, "formation": group, "faction": 1, "troop": 0, "person_ids": identities, "solo": false})
	site.rosters.append({"team_id": 1, "faction_id": 1, "crowd_formation": group, "units": rows})
	site._bind_people()
	site.active = true
	if not _bulk_crew_hold_contract(site.crowd, data): return
	var owner: Variant = site.person_owner(101)
	# Finalize imported the exact original starts, rebuilt native cell/hash and
	# settled commander presence. No zero-time step or post-finalize teleport.
	var triplets: PackedInt64Array = site.crowd.siege_ground_cells()
	for local in range(identities.size()):
		var index: int = owner.index_for_identity(identities[local])
		var pose: PackedInt64Array = site.crowd.siege_person_state(index)
		if not _require(site.siege_original_person(identities[local]).cell == initial[local] and int(pose[1]) == 0 and int(pose[2]) < 0 and int(pose[4]) < 0, "Initial native original source/goal differs from imported fixture"): return
	var geometry := SiteRuntime.feature_geometry(data, feature)
	var lower: Vector2i = geometry.stair_lower.cell
	var upper: Vector2i = geometry.stair_upper.cell
	var broad: PackedByteArray = site.crowd.get_occupancy_mask(PackedInt64Array())
	var exact: PackedByteArray = site.crowd.siege_occupancy_mask(PackedInt64Array())
	if not _require(broad[data.index(lower)] != 0 and exact[data.index(lower)] == 0 and exact[data.index(upper)] == 0, "Fixture must expose broad-radius spill while both real ladder surfaces are empty"): return
	print("SIEGE_WORK_OCCUPANCY_INPUTS ", JSON.stringify({"native_index_person_cell": Array(triplets), "a": [a.x, a.y], "b": [b.x, b.y], "surface": [[lower.x, lower.y], [upper.x, upper.y]], "broad_lower": broad[data.index(lower)], "exact_lower": exact[data.index(lower)]}))
	# A genuine original body on the changing surface must still reject. Only
	# this pre-work negative fixture moves the separate original dummy and back.
	var original_dummy: Dictionary = site.soldier_state(0)
	var site_before := JSON.stringify(data.site)
	if not _require(site.set_soldier_fields(0, {"px": float(lower.x) + 0.5, "py": float(lower.y) + 0.5}), "Original dummy occupancy fixture failed"): return
	site._siege_cell_masks.clear() # Discard only the derived query cache after explicit initial fixture mutation.
	var blocked := SiteRuntime.request_siege_ladder_action(data, definition.key, "deploy", [102, 103], 1, lab.site_controller._siege_people_occupied, true)
	if not _require(not blocked.ok and blocked.code == "OCCUPIED" and JSON.stringify(data.site) == site_before, "Exact original source body was ignored or rejection mutated ladder state"): return
	if not _require(site.set_soldier_fields(0, {"px": float(original_dummy.px), "py": float(original_dummy.py)}), "Original dummy source restoration failed"): return
	site._siege_cell_masks.clear()
	site._occupancy_cache.clear()
	lab.crew.init(lab)
	var requester: int = owner.combat_identity(owner.current_commander)
	var requested := lab.crew.request_ladder_action(definition.key, [102, 103], requester, "deploy")
	if not _require(requested.ok, "Original native commander dispatch failed: " + str(requested)): return
	var original_row: Dictionary = site._records[102]
	if not _require(is_same(lab.crew._person(102).row, original_row), "Work adapter copied the original native metadata row"): return
	lab.crew.advance(0.01)
	if not _require(bool(site.siege_original_person(102).moving), "Native worker did not commit a real approach step"): return
	var waiting: PackedInt64Array = site.crowd.siege_person_state(owner.index_for_identity(103))
	if not _require(int(waiting[1]) == 5 and int(waiting[2]) < 0 and not bool(site.siege_original_person(103).moving), "Worker initially at its station was not held by the original native mode"): return
	var projected: Dictionary = site.sync_siege_inputs()
	if not _require(projected.ok and site.crowd.siege_person_state(owner.index_for_identity(103)) == waiting,
		"Actual CrowdSite bulk projection revoked the original WorkTeam station hold: " + str(projected)): return
	lab.crew.advance_ladder_actions(12.0, 720.0)
	if not _require(float(feature.ladder.progress) == 0.0, "Not-yet-arrived native worker advanced the shared ladder action"): return
	for tick in range(90): site.crowd.step_clock(1.0 / 30.0, 0.0, 0.0)
	if not _require(site.siege_original_person(102).cell == a and not bool(site.siege_original_person(102).moving), "Native original approach failed to arrive"): return
	if not _require(site.siege_original_person(103).cell == b and not bool(site.siege_original_person(103).moving), "Original HOLD cohesion moved the worker away from its held station"): return
	lab.crew.advance(0.001)
	var before: float = owner.combat_hot_get(owner.index_for_identity(102), &"fatigue")
	print("SIEGE_WORK_BEFORE ", JSON.stringify(_work_diagnostic(lab, feature)))
	var handled: Dictionary = lab.crew.advance_ladder_actions(1.0, 60.0)
	print("SIEGE_WORK_AFTER ", JSON.stringify({"handled": handled, "workers": _work_diagnostic(lab, feature), "cold_fatigue": original_row.fatigue, "native_before": before, "native_after": owner.combat_hot_get(owner.index_for_identity(102), &"fatigue"), "progress": feature.ladder.progress}))
	if not _require(float(feature.ladder.progress) == 1.0 and owner.combat_hot_get(owner.index_for_identity(102), &"fatigue") > before and original_row.fatigue == 999.0, "Shared native pool was not charged or a stale cold fatigue row was changed"): return
	lab.threatened = true
	lab.crew.advance_ladder_actions(11.0, 660.0)
	if not _require(float(feature.ladder.progress) == 1.0, "Threatened native work advanced"): return
	lab.threatened = false
	if not _require(lab.crew.cancel(102).ok and original_row.work_task.is_empty() and str(feature.ladder.pending).is_empty(), "Native cancel did not clear both original handles safely"): return
	for identity: int in [102, 103]:
		var released: PackedInt64Array = site.crowd.siege_person_state(owner.index_for_identity(identity))
		if not _require(int(released[1]) == 0 and int(released[2]) < 0 and site._records[identity].work_task.is_empty(), "Cancelling either ladder worker did not release both original native station holds"): return
	# Existing same-cell steps must also recenter a worker after a genuine
	# original HOLD movement, without a coordinate write or a fatigue bypass.
	# Keep the other worker at its own original station so its released HOLD
	# slot cannot move into this return destination during the positive case.
	if not _require(site.siege_approach_step(102, a), "Original peer station hold failed"): return
	var commander_cell: Vector2i = site.siege_original_person(101).cell
	if not _require(site.siege_approach_step(101, commander_cell), "Original commander cell hold failed"): return
	for tick in range(90):
		site.crowd.step_clock(1.0 / 30.0, 0.0, 0.0)
		if bool(site.siege_original_person(103).moving): break
	var drifting: Dictionary = site.siege_original_person(103)
	if not _require(drifting.cell == b and bool(drifting.moving), "Original HOLD must expose a real within-cell approach recovery fixture"): return
	if not _require(site.siege_approach_step(103, b), "Existing native same-cell step refused a real within-cell return"): return
	var returning: PackedInt64Array = site.crowd.siege_person_state(owner.index_for_identity(103))
	if not _require(int(returning[1]) == 5 and int(returning[2]) == data.index(b) and bool(site.siege_original_person(103).moving), "Within-cell native return was faked as instant arrival"): return
	for tick in range(90): site.crowd.step_clock(1.0 / 30.0, 0.0, 0.0)
	var returned: Dictionary = site.soldier_state(owner.index_for_identity(103))
	var return_neighbours: Array = []
	for identity: int in [101, 102, 103]:
		var neighbour: Dictionary = site.siege_original_person(identity)
		return_neighbours.append({"identity": identity, "hot": site.soldier_state(int(neighbour.unit)), "original": neighbour})
	print("SIEGE_WORK_SAME_CELL_NEIGHBOURS ", JSON.stringify(return_neighbours))
	print("SIEGE_WORK_SAME_CELL_RETURN ", JSON.stringify({"expected": [float(b.x) + 0.5, float(b.y) + 0.5], "drifting": drifting, "admitted": Array(returning), "returned": returned, "actual_original": site.siege_original_person(103), "step": Array(site.crowd.siege_person_state(owner.index_for_identity(103)))}))
	if not _require(not bool(site.siege_original_person(103).moving) and absf(float(returned.px) - (float(b.x) + 0.5)) < 0.00001 and absf(float(returned.py) - (float(b.y) + 0.5)) < 0.00001, "Native same-cell return did not settle at its original station centre"): return
	owner.siege_cancel_step(owner.index_for_identity(103))
	lab.close()
	await process_frame
	print("SITE_SIEGE_NATIVE_WORKTEAM_PASS: real ArmyCrowd owner rows, global index offset, commander dispatch, committed native approach, all-workers arrival barrier, native shared fatigue without cold writes, threat pause and two-person cancel; no GPU/UI/full save claim")
	quit(0)

func _work_diagnostic(lab: Node, feature: Dictionary) -> Dictionary:
	var site: Variant = lab.crowd_site
	var workers: Array = []
	for identity: int in [102, 103]:
		var person: Dictionary = site.siege_original_person(identity)
		var owner: Variant = person.owner
		var index := int(person.unit)
		workers.append({"identity": identity, "index": index, "cell": str(person.cell), "moving": person.moving,
			"hot": site.soldier_state(index), "native_step": Array(site.crowd.siege_person_state(index)),
			"contact_pose": Array(site.crowd.contact_pose_state(index)), "pose": owner.combat_hot_get(index, &"pose"),
			"attack": owner.combat_hot_get(index, &"attack"), "can_act": owner.combat_can_act(index), "order": owner.combat_order,
			"assigned": lab.crew.is_assigned(identity), "resting": person.row.get("work_resting"), "task": person.row.get("work_task"),
			"native_zero_charge_admitted": bool(site.crowd.charge_siege_work(index, 0.0)), "fatigue": owner.combat_hot_get(index, &"fatigue"),
			"unavailable": bool(lab.crew.unavailable.call(identity)) if lab.crew.unavailable.is_valid() else false})
	return {"ladder": feature.ladder, "workers": workers, "formation": site.formation_state(1), "threatened": lab.threatened}

func _bulk_crew_snapshot(native: Variant) -> Dictionary:
	var marks: Array[PackedInt64Array] = []
	var people: Array[PackedFloat64Array] = []
	for index in range(int(native.soldier_count())):
		marks.append(native.siege_person_state(index))
		people.append(native.get_soldier_state(index))
	# No stats() call: it changes serialized reporting counters.
	return {"hash": str(native.state_hash()), "blob": native.save_state(), "ids": native.person_ids(),
		"marks": marks, "people": people, "ground": native.siege_ground_cells(),
		"physical": native.siege_occupancy_mask(PackedInt64Array()), "terrain": native.terrain_state()}

func _bulk_crew_hold_contract(source: Variant, data: TerrainData) -> bool:
	# Isolated original ArmyCrowd instance, cloned before any live WorkTeam job.
	# Every tested transition enters the real published GDExtension ABI.
	var baseline := _bulk_crew_snapshot(source)
	var native: Variant = ClassDB.instantiate("ArmyCrowd")
	if not _require(not baseline.blob.is_empty() and native.load_state(baseline.blob)
		and _bulk_crew_snapshot(native) == baseline, "Bulk crew ABI fixture clones the exact existing native world"): return false
	var cells: PackedInt64Array = native.siege_ground_cells()
	var worker_cell := int(cells[3 * 3 + 2])
	var housing_cell := int(cells[1 * 3 + 2])
	var crew_cell := int(cells[0 * 3 + 2])
	if not _require(native.order_siege_step(3, worker_cell) and native.order_housing_step(1, housing_cell),
		"Actual noncrew WorkTeam and Housing same-cell holds enter their original modes"): return false
	var held := _bulk_crew_snapshot(native)
	if not _require(int(held.marks[3][0]) == 0 and int(held.marks[3][1]) == 5 and int(held.marks[3][2]) < 0
		and int(held.marks[1][1]) == 3 and int(held.marks[1][2]) < 0 and not held.blob.is_empty(),
		"Held transient jobs remain noncrew and are saveable as held (G10, Nekki 2026-10-30 A)"): return false
	for repeat in range(2):
		var accepted: bool = native.set_siege_crew_members(PackedInt32Array())
		var observed := _bulk_crew_snapshot(native)
		print("SIEGE_BULK_CREW_NOOP ", JSON.stringify({"repeat": repeat, "accepted": accepted,
			"before_hash": held.hash, "after_hash": observed.hash, "before_marks": held.marks, "after_marks": observed.marks}))
		if not _require(accepted and observed == held,
			"Bulk empty/no-op crew projection must preserve all existing noncrew WorkTeam/Housing holds"): return false
	if not _require(native.set_siege_crew_members(PackedInt32Array([0])), "Add an unrelated actual crew member through bulk ABI"): return false
	var added := _bulk_crew_snapshot(native)
	if not _require(added.marks[3] == held.marks[3] and added.marks[1] == held.marks[1]
		and added.people == held.people and added.ground == held.ground and added.blob.is_empty() == held.blob.is_empty(),
		"Unrelated crew addition leaves original jobs, people and positions unchanged"): return false
	if not _require(native.set_siege_crew_members(PackedInt32Array([0])) and _bulk_crew_snapshot(native) == added
		and native.set_siege_crew_members(PackedInt32Array()) and _bulk_crew_snapshot(native) == held,
		"Same membership and unrelated departure preserve exact held native state"): return false
	var invalid: Array[PackedInt32Array] = [PackedInt32Array([0, 0]), PackedInt32Array([-1]),
		PackedInt32Array([0, 4]), PackedInt32Array([0, 1, 2, 3, 4]), PackedInt32Array([0, 1])]
	for indices: PackedInt32Array in invalid:
		if not _require(not native.set_siege_crew_members(indices) and _bulk_crew_snapshot(native) == held,
			"Duplicate/range/count/ineligible mixed bulk inputs reject atomically: " + str(indices)): return false
	if not _require(native.set_siege_crew_members(PackedInt32Array([0])) and native.order_siege_step(0, crew_cell),
		"A genuine existing crew member has a real settled mode-5 hold"): return false
	var departing: PackedInt64Array = native.siege_person_state(0)
	if not _require(int(departing[0]) == 1 and int(departing[1]) == 5 and int(departing[2]) < 0
		and native.set_siege_crew_members(PackedInt32Array()) and _bulk_crew_snapshot(native) == held,
		"Only an actual crew-to-noncrew departure clears its own settled mode-5 hold"): return false
	if not _require(native.cancel_siege_step(3) and native.cancel_housing_step(1)
		and _bulk_crew_snapshot(native) == baseline, "Original job cancellation restores the original saveable state"): return false
	var restored: Variant = ClassDB.instantiate("ArmyCrowd")
	if not _require(restored.load_state(native.save_state()) and _bulk_crew_snapshot(restored) == baseline,
		"After original cancellation, unchanged save/load preserves all original bytes, IDs and gameplay hash"): return false
	# A real pending approach must still make leaving crew an atomic refusal.
	var next := data.index(data.cell_from_index(crew_cell) + Vector2i.RIGHT)
	if not _require(native.set_siege_crew_members(PackedInt32Array([0])) and native.order_siege_step(0, next),
		"Existing public native step starts a genuine adjacent crew approach"): return false
	var approaching := _bulk_crew_snapshot(native)
	if not _require(int(approaching.marks[0][2]) == next and approaching.blob.is_empty()
		and not native.set_siege_crew_members(PackedInt32Array([2])) and _bulk_crew_snapshot(native) == approaching
		and not native.set_siege_crew_members(PackedInt32Array()) and _bulk_crew_snapshot(native) == approaching,
		"Pending actual crew approach prevents partial replacement or departure"): return false
	# Start a second isolated scenario from the same original saved world.
	if not _require(native.load_state(baseline.blob) and _bulk_crew_snapshot(native) == baseline
		and native.set_siege_crew_members(PackedInt32Array([0])), "Original load resets only the isolated group guard fixture"): return false
	var body := PackedInt32Array([next])
	var token: int = native.begin_siege_compound(PackedInt64Array([0, int(baseline.ids[0]), crew_cell, crew_cell]), body, body, body, 1.0)
	if not _require(token > 0, "Public ABI starts an actual stationary original compound outside the member cell"): return false
	var grouped := _bulk_crew_snapshot(native)
	if not _require(int(grouped.marks[0][3]) == token and grouped.blob.is_empty()
		and native.set_siege_crew_members(PackedInt32Array([0])) and _bulk_crew_snapshot(native) == grouped
		and not native.set_siege_crew_members(PackedInt32Array()) and _bulk_crew_snapshot(native) == grouped,
		"Existing group membership allows an exact no-op and rejects premature crew departure atomically"): return false
	if not _require(_bulk_crew_snapshot(source) == baseline, "All isolated public-ABI checks preserve the original live world"): return false
	print("SIEGE_BULK_CREW_HOLD_PASS: empty/repeated/changed membership, noncrew work and housing holds, invalid input atomicity, real leaving crew cleanup, active approach/group refusal, original post-cancel save/load")
	return true
