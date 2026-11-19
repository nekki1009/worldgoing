extends "res://scripts/tests/site_barracks_dense_store_test.gd"
## Reuse the original seed/Army fixtures; run no inherited acceptance groups.
## All valid saves and deliberately corrupt evidence stay in this run's folder.
const TYPES_SAVE_ROOT := "res://output/site_barracks_two_types_20261003/store"
const INVALID_CAMP_TYPES := ["", "unknown", "Standard", 1, 1.25, true, null, [], {}]

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: quit(1))
	completed = 0
	rejected_files = 0
	assert(DirAccess.make_dir_recursive_absolute(TYPES_SAVE_ROOT) == OK)
	for version: int in [1, 2]:
		for quarter: int in range(4):
			_check_missing_type_store(version, quarter)
	for camp_type: String in ["standard", "chinese"]:
		_check_type_people_store(camp_type)
		_check_type_pending_store(camp_type)
	_check_non_barracks_type_store()
	TerrainArmy.release_contact_source()
	if completed != 13 or rejected_files != 68:
		push_error("Two-type Store acceptance incomplete: groups=%d/13 rejected=%d/68" % [completed, rejected_files])
		quit(1)
		return
	print("SITE_BARRACKS_TYPES_STORE_PASS: v1/v2 missing camp_type preserved in four directions and paid expansion resume; standard/chinese original Army, person IDs, roles, holders, items, supply and training references roundtrip; 68 checksum-valid corrupt files rejected without live-state/navigation/source-file changes; no native, visual or performance claim")
	quit(0)

func _type_roundtrip(data: TerrainData, path: String) -> TerrainData:
	assert(path.begins_with(TYPES_SAVE_ROOT + "/"))
	var before := JSON.stringify(data.site)
	var saved := SiteStore.save(data, path)
	assert(saved.ok, str(saved))
	var original := FileAccess.get_file_as_string(path)
	var loaded := SiteStore.load_site(path)
	assert(loaded.ok, str(loaded))
	assert(JSON.stringify(data.site) == before, "Saving/loading a candidate changed the live Site")
	assert(FileAccess.get_file_as_string(path) == original, "Loading rewrote its source file")
	var restored: TerrainData = loaded.data
	assert(not is_same(restored, data) and restored.fingerprint() == data.fingerprint())
	assert(restored.static_blocked == data.static_blocked and restored.feature_at == data.feature_at)
	return restored

func _type_payload(path: String) -> Dictionary:
	assert(path.begins_with(TYPES_SAVE_ROOT + "/"))
	var wrapper: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	return JSON.parse_string(wrapper.payload)

func _type_write_payload(path: String, payload: Dictionary) -> void:
	assert(path.begins_with(TYPES_SAVE_ROOT + "/"))
	var body := JSON.stringify(payload, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	file.close()

func _reject_type_payload(data: TerrainData, valid_path: String, payload: Dictionary, label: String) -> void:
	var bad_path := TYPES_SAVE_ROOT.path_join("invalid_%02d_%s.json" % [rejected_files, label])
	_type_write_payload(bad_path, payload)
	var valid_text := FileAccess.get_file_as_string(valid_path)
	var bad_text := FileAccess.get_file_as_string(bad_path)
	var before := JSON.stringify(data.site)
	var blocked := data.static_blocked.duplicate()
	var features := data.feature_at.duplicate()
	var fingerprint := data.fingerprint()
	var rejected := SiteStore.load_site(bad_path)
	assert(not rejected.ok and not rejected.has("data"), "Invalid candidate escaped temporary validation: %s %s" % [label, str(rejected)])
	assert(JSON.stringify(data.site) == before and data.static_blocked == blocked and data.feature_at == features and data.fingerprint() == fingerprint,
		"Rejected candidate changed the original Site/person/item/navigation owners: " + label)
	assert(FileAccess.get_file_as_string(valid_path) == valid_text and FileAccess.get_file_as_string(bad_path) == bad_text,
		"Rejected load changed a valid save or its corrupt evidence: " + label)
	rejected_files += 1

func _check_missing_type_store(version: int, quarter: int) -> void:
	var data := _military_store_fixture("missing-type-v%d-q%d" % [version, quarter])
	var options := {"barracks_layout_version": version, "quarter": quarter}
	var key := _build(data, "barracks", Vector2i(10, 10), Vector2i(10, 10), options)
	var feature: Dictionary = data.site.features[key]
	feature.erase("camp_type")
	if version == 1: feature.erase("barracks_layout_version")
	var original := _dense_geometry(data, key)
	assert(original.capacity == (72 if version == 1 else 60))
	assert(original.modules.size() == (3 if version == 1 else 7))
	assert(feature.cost == {"wood": 100, "stone": 100} and float(feature.work) == 200.0,
		"The new type field changed the original 10x10 v1/v2 construction terms")
	var terms := {"cost": feature.cost.duplicate(true), "work": feature.work, "inventory": data.site.inventory.duplicate(true)}
	var path := TYPES_SAVE_ROOT.path_join("missing_type_v%d_q%d.json" % [version, quarter])
	var restored := _type_roundtrip(data, path)
	var persisted: Dictionary = _type_payload(path).state.features[key]
	assert(not persisted.has("camp_type") and not restored.site.features[key].has("camp_type"), "Loading injected a type into a legacy feature")
	assert(restored.site.features[key].has("barracks_layout_version") == (version == 2))
	assert(_dense_geometry(restored, key) == original)
	assert(restored.site.features[key].cost == terms.cost and restored.site.features[key].work == terms.work and restored.site.inventory == terms.inventory)
	assert(SiteRuntime.barracks_type(restored.site.features[key]) == "standard")
	var expanded := _cells(restored, "barracks", Vector2i(10, 10), Vector2i(11, 10), options)
	assert(SiteRuntime.request_resize(restored, key, expanded, Callable(), 1).ok)
	assert(not restored.site.features[key].has("camp_type") and not restored.site.features[key].pending_build.has("camp_type"))
	var job: Dictionary = restored.site.features[key].pending_build
	SiteRuntime._feature_work(restored, key, float(job.work) * 0.25, Callable(), Callable(), _task(key, "construct", int(job.entrance)), {}, 20, 1)
	var pending: Dictionary = JSON.parse_string(JSON.stringify(job))
	var reloaded := _type_roundtrip(restored, path + ".pending")
	assert(JSON.parse_string(JSON.stringify(reloaded.site.features[key].pending_build)) == pending)
	var paid_inventory := JSON.stringify(reloaded.site.inventory)
	_finish_military(reloaded, key)
	assert(not reloaded.site.features[key].has("camp_type") and reloaded.site.features[key].has("barracks_layout_version") == (version == 2))
	assert(int(reloaded.site.features[key].get("barracks_layout_version", 1)) == version and reloaded.site.features[key].cells == expanded)
	assert(JSON.stringify(reloaded.site.inventory) == paid_inventory, "Legacy expansion charged its original materials twice")
	var final_data := _type_roundtrip(reloaded, path + ".resumed")
	assert(not final_data.site.features[key].has("camp_type") and _dense_geometry(final_data, key) == _dense_geometry(reloaded, key))
	completed += 1

func _type_people_state(state: Dictionary) -> Dictionary:
	var teams: Array = []
	for team: Dictionary in state.armies:
		var people: Array = []
		for row: Dictionary in team.units:
			people.append({"person_id": row.person_id, "military_role": row.military_role, "cell": row.cell, "slot": row.slot,
				"hp": row.hp, "ko": row.ko, "cargo": row.cargo, "item_state": row.item_state})
		teams.append({"team_id": team.team_id, "garrison_feature_id": team.garrison_feature_id, "training": team.training,
			"team_fatigue": team.get("team_fatigue", {}), "people": people})
	return JSON.parse_string(JSON.stringify({"teams": teams, "supply": state.team_supply, "items": state.item_records,
		"definitions": state.item_definitions, "next_item": state.next_item}))

func _check_type_people_store(camp_type: String) -> void:
	var data := _military_store_fixture("people-" + camp_type)
	var key := _build(data, "barracks", Vector2i(10, 10), Vector2i(10, 10), {"barracks_layout_version": 2, "camp_type": camp_type})
	var house := _build(data, "house", Vector2i(25, 10), Vector2i.ONE, {"variant": "small"})
	assert(data.site.features[key].camp_type is String and data.site.features[key].camp_type == camp_type)
	var positions: Array[Vector2i] = []
	for index: int in SiteRuntime.military_walkable_cells(data, data.site.features[key]):
		positions.append(data.cell_from_index(index))
		if positions.size() == 3: break
	var fixture := CrewFixture.new()
	fixture.army.exchange_enabled = true
	fixture.setup(root, data, positions)
	fixture.army.training = 37.0
	var members := {}
	var ids: Array[int] = []
	var life := {}
	var original_rows: Array[Dictionary] = []
	var original_holders: Array[Dictionary] = []
	for row: Dictionary in fixture.army.combat_units:
		var identity := int(row.person_id)
		row.item_state.clear() # Fixture initialization only, before any real item exists.
		assert(SiteRuntime.seed_person_equipment(data, row.item_state, identity, row.appearance).ok)
		assert(not row.item_state.item_ids.is_empty())
		row.cargo.wood = 1
		members[identity] = row
		ids.append(identity)
		life[str(identity)] = 0
		original_rows.append(row)
		original_holders.append(row.item_state)
	var sustain := SiteSustain.create()
	assert(SiteSustain.add_members(sustain, members, ids).ok)
	var training := camp_type == "standard"
	var supply := {"version": 2, "sustain": sustain, "inventory": {"grain": 3}, "training_order": training,
		"training_requester": ids[0] if training else -1, "training_feature_id": key if training else "", "revision": 0, "delivery": {}, "life_checkpoint": life}
	data.site.team_supply = {str(fixture.army.team_id): supply}
	data.site.actors = {}
	data.site.army_trial_active = true
	data.site.army_next_team = fixture.army.team_id + 1
	data.site.armies = [fixture.army.capture_combat_state()]
	var path := TYPES_SAVE_ROOT.path_join("people_%s.json" % camp_type)
	var original := _type_people_state(data.site)
	var restored := _type_roundtrip(data, path)
	assert(restored.site.features[key].camp_type == camp_type and _type_people_state(restored.site) == original)
	if training:
		var legacy := _type_payload(path)
		legacy.state.features[key].erase("camp_type")
		_type_write_payload(path + ".legacy_training", legacy)
		var loaded := SiteStore.load_site(path + ".legacy_training")
		assert(loaded.ok and not loaded.data.site.features[key].has("camp_type"), str(loaded))
		assert(_type_people_state(loaded.data.site) == original, "Missing type changed the original active training reference")
		for value: Variant in INVALID_CAMP_TYPES:
			var bad := _type_payload(path)
			bad.state.features[key].camp_type = value
			_reject_type_payload(data, path, bad, "parent_type")
		for fault: String in ["chinese", "missing", "wrong_kind", "unfinished", "faction", "stopped_reference", "not_supplied"]:
			var bad := _type_payload(path)
			var entry: Dictionary = bad.state.team_supply[str(fixture.army.team_id)]
			match fault:
				"chinese": bad.state.features[key].camp_type = "chinese"
				"missing": entry.training_feature_id = "99999"
				"wrong_kind": entry.training_feature_id = house
				"unfinished":
					bad.state.features[key].stage = "planned"
					bad.state.features[key].progress = 0.0
				"faction": bad.state.features[key].owner_faction = 2
				"stopped_reference":
					entry.training_order = false
					entry.training_requester = -1
				"not_supplied": entry.training_requester = 99999
			_reject_type_payload(data, path, bad, "training_" + fault)
	supply.training_order = false
	supply.training_requester = -1
	supply.training_feature_id = ""
	fixture.army.set_garrison(key)
	data.site.armies = [fixture.army.capture_combat_state()]
	original = _type_people_state(data.site)
	var garrison_path := path + ".garrison"
	restored = _type_roundtrip(data, garrison_path)
	assert(_type_people_state(restored.site) == original and restored.site.features[key].camp_type == camp_type)
	for index: int in range(ids.size()):
		assert(is_same(fixture.army.combat_units[index], original_rows[index]) and is_same(fixture.army.combat_units[index].item_state, original_holders[index]),
			"Saving/loading or registering replaced a live original row/holder")
		for item_id: String in restored.site.armies[0].units[index].item_state.item_ids:
			assert(restored.site.item_records[item_id].holder == "person:%d" % ids[index])
	for fault: String in ["missing_garrison", "wrong_garrison", "wrong_holder", "garrison_training"]:
		var bad := _type_payload(garrison_path)
		match fault:
			"missing_garrison": bad.state.armies[0].garrison_feature_id = "99999"
			"wrong_garrison": bad.state.armies[0].garrison_feature_id = house
			"wrong_holder":
				var item_id: String = bad.state.armies[0].units[0].item_state.item_ids[0]
				bad.state.item_records[item_id].holder = "person:%d" % ids[1]
			"garrison_training":
				var entry: Dictionary = bad.state.team_supply[str(fixture.army.team_id)]
				entry.training_order = true
				entry.training_requester = ids[0]
				entry.training_feature_id = key
		_reject_type_payload(data, garrison_path, bad, camp_type + "_" + fault)
	fixture.close()
	var resumed := CrewFixture.new()
	resumed.army.exchange_enabled = true
	resumed.setup(root, restored, positions, restored.site.armies[0])
	assert(resumed.army.garrison_feature_id == key and resumed.army.combat_units.size() == ids.size())
	assert(resumed.army.current_commander == -1 and resumed.army.formal_commander == -1)
	restored.site.armies = [resumed.army.capture_combat_state()]
	assert(_type_people_state(restored.site) == original, "Restoring the original Army changed its roster, holders, supplies or earned training")
	var final_data := _type_roundtrip(restored, path + ".army_restored")
	assert(_type_people_state(final_data.site) == original)
	resumed.close()
	completed += 1

func _check_type_pending_store(camp_type: String) -> void:
	var data := _military_store_fixture("pending-" + camp_type)
	var options := {"barracks_layout_version": 2, "camp_type": camp_type}
	var key := _build(data, "barracks", Vector2i(10, 10), Vector2i(10, 10), options)
	var cells := _cells(data, "barracks", Vector2i(10, 10), Vector2i(11, 10), options)
	assert(SiteRuntime.request_resize(data, key, cells, Callable(), 1).ok)
	var job: Dictionary = data.site.features[key].pending_build
	assert(not job.has("camp_type") and not job.has("barracks_layout_version"))
	SiteRuntime._feature_work(data, key, float(job.work) * 0.25, Callable(), Callable(), _task(key, "construct", int(job.entrance)), {}, 20, 1)
	var path := TYPES_SAVE_ROOT.path_join("pending_%s.json" % camp_type)
	var restored := _type_roundtrip(data, path)
	assert(restored.site.features[key].camp_type == camp_type and not restored.site.features[key].pending_build.has("camp_type"))
	assert(is_equal_approx(float(restored.site.features[key].pending_build.progress), float(job.progress)))
	for value: Variant in ["standard", "chinese"] + INVALID_CAMP_TYPES:
		var bad := _type_payload(path)
		bad.state.features[key].pending_build.camp_type = value
		_reject_type_payload(data, path, bad, "pending_type")
	var inventory := JSON.stringify(restored.site.inventory)
	_finish_military(restored, key)
	assert(restored.site.features[key].camp_type == camp_type and restored.site.features[key].cells == cells)
	assert(JSON.stringify(restored.site.inventory) == inventory, "Typed expansion charged the original paid materials twice")
	var final_data := _type_roundtrip(restored, path + ".resumed")
	assert(final_data.site.features[key].camp_type == camp_type and _dense_geometry(final_data, key) == _dense_geometry(restored, key))
	completed += 1

func _check_non_barracks_type_store() -> void:
	for kind: String in ["house", "training_ground"]:
		var data := _military_store_fixture("non-barracks-" + kind)
		var options := {"variant": "small"} if kind == "house" else {}
		var key := _build(data, kind, Vector2i(10, 10), Vector2i(10, 10), options)
		assert(not data.site.features[key].has("camp_type"))
		var path := TYPES_SAVE_ROOT.path_join("non_barracks_%s.json" % kind)
		var restored := _type_roundtrip(data, path)
		assert(not restored.site.features[key].has("camp_type"))
		for value: Variant in ["standard", "chinese"] + INVALID_CAMP_TYPES:
			var bad := _type_payload(path)
			bad.state.features[key].camp_type = value
			_reject_type_payload(data, path, bad, "non_barracks_type")
	completed += 1
