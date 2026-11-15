extends "res://scripts/tests/site_ecology_policy_border_test.gd"
## ECO16 real settlement office save/load and accepted capture timer.

const GOVERNANCE_SAVE := "res://.godot-temp/site_ecology_governance/"

var _governance_completed := false

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 90000
	_run.call_deferred()

func _process(delta: float) -> bool:
	if _governance_completed:
		return false
	return super._process(delta)

func _governance_source(data: TerrainData) -> String:
	for key: String in data.resource_base:
		var source := Env.resource(data, key)
		var cell := data.cell_from_index(int(source.cell))
		if int(source.kind) in Env.RESTORABLE_KINDS and Rect2i(13, 13, 20, 20).has_point(cell) and not Rect2i(19, 19, 7, 7).has_point(cell): return key
	assert(false, "Original controlled fixture needs one plant source inside jurisdiction")
	return ""

func _save_governance(lab: TerrainLab, suffix: String, key: String, base: TerrainData) -> Dictionary:
	assert(lab.site_controller._capture_for_save().ok)
	var data: TerrainData = lab.terrain
	var offices := JSON.stringify(data.site.settlement.offices, "", true, true)
	var change := JSON.stringify(data.site.changes[key], "", true, true)
	var resource_base_bytes := var_to_bytes(data.resource_base)
	var saved := Store.save(data, GOVERNANCE_SAVE + suffix + ".json")
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(GOVERNANCE_SAVE + suffix + ".json", _bridge_loader(base), 1, true)
	assert(loaded.ok, str(loaded))
	assert(JSON.stringify(loaded.data.site.settlement.offices, "", true, true) == offices)
	assert(JSON.stringify(loaded.data.site.changes[key], "", true, true) == change)
	assert(var_to_bytes(loaded.data.resource_base) == resource_base_bytes)
	var source := _border_state(data)
	assert(Store._validate_state(loaded.data, loaded.data.site.duplicate(true)).ok)
	assert(_border_state(data) == source, "Save and candidate validation cannot change source offices or policy")
	return loaded

func _run() -> void:
	var data := _building_fixture()
	data.site.id = RegionGrid.site_id(RegionGrid.ATLAS_ID, Vector2i.ZERO)
	data.parameters["composition"] = "fixed_geography"
	data.parameters["fixed_base"] = {"base_kind": "fixed_geography", "atlas_id": RegionGrid.ATLAS_ID,
		"site_id": str(data.site.id), "site": [0, 0], "grid_contract_version": 1,
		"base_revision": "ecology_governance_fixture_v1", "manifest_sha256": "e".repeat(64),
		"terrain_fingerprint": data.fingerprint(), "ramp_rule_revision": RegionTerrainAdapter.RAMP_RULE_REVISION}
	var base := _bridge_base(data)
	var lab := _building_lab(data)
	var player := lab.character.person_id
	var key := _governance_source(data)
	var layout := Runtime.building_cells(data, "settlement_center", Vector2i(20, 20), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	assert(layout.ok, str(layout))
	var cells: Array[int] = []
	cells.assign(layout.cells)
	assert(lab.character.place(Vector2i(26, 22), true))
	var founded := Settlement.found(lab, player, cells, {"layout_version": 1, "quarter": 0}, Callable(), "生態官職存讀驗收")
	assert(founded.ok, str(founded))
	_complete_key(data, str(founded.feature))
	assert(str(data.site.features[str(founded.feature)].stage) == "complete" and not data.site.features[str(founded.feature)].has("pending_build"), "The original completion helper must actually finish the founded center")
	assert(int(data.site.worker.cell) == data.index(Vector2i(10, 9)) and str(data.site.worker.mode) == "idle", "The original completion helper reaches its worker release exit")
	var legacy_offices := Settlement.offices(lab).duplicate(true)
	var legacy_seat := str(legacy_offices.duties["settlement.ecology"])
	legacy_offices.duties.erase("settlement.ecology")
	legacy_offices.positions = legacy_offices.positions.filter(func(row: Dictionary) -> bool: return str(row.id) != legacy_seat)
	assert(SiteOffices.validate(legacy_offices, "settlement", true))
	data.site.settlement.offices = legacy_offices
	var legacy_bytes := var_to_bytes(legacy_offices)
	var legacy_positions: Array = legacy_offices.positions.duplicate(true)
	var legacy_revision := int(legacy_offices.revision)
	assert(Settlement.ecology_authority(lab, key, player).ok)
	assert(var_to_bytes(data.site.settlement.offices) == legacy_bytes, "Read-only authority must not publish a missing legacy duty")
	var upgraded := Settlement.offices(lab)
	assert(upgraded.duties.has("settlement.ecology"))
	assert(int(SiteOffices.position(upgraded, str(upgraded.duties["settlement.ecology"])).holder) == -1)
	assert(int(upgraded.revision) == legacy_revision)
	for position: Dictionary in legacy_positions:
		assert(SiteOffices.position(upgraded, str(position.id)) == position, "Original catalog migration preserves every old position")
	var team: TerrainArmy = lab.army
	team.roster_size = 2
	team.faction_id = 1
	assert(team.deploy_at(data, null, null, [Vector2i(28, 30), Vector2i(29, 30)]) and team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	var holder := team.combat_identity(1)
	var offices := Settlement.offices(lab)
	var seat := str(offices.duties["settlement.ecology"])
	# 文武官 W2: a 文官 seat needs a 文吏 (a 武官 seat an officer); the fixture qualifies its holder first.
	team.set_civil_role(holder, "clerk")
	assert(Settlement.apply_office_plan(lab, player, int(offices.revision), [{"op": "appoint", "position_id": seat, "person_id": holder}]).ok)
	assert(Settlement.set_ecology_modes(lab, holder, [key], "protected").ok)
	var request := Settlement.ecology_authority(lab, key, holder)
	assert(request.ok)
	var loaded := _save_governance(lab, "appointed", key, base)
	lab.free()
	data = loaded.data
	lab = _building_lab(data)
	assert(lab.character.person_id == player)
	assert(Settlement.ecology_authority(lab, key, holder, int(request.revision)).ok)
	assert(not Settlement.ecology_authority(lab, key, player).ok)
	var before := _border_state(data)
	var revision := data.environment_revision
	assert(str(Env.ecology_info(data, key).mode) == "protected")
	assert(_border_state(data) == before and data.environment_revision == revision)
	assert(lab.character.place(Vector2i(10, 10), true) and lab.npc.place(Vector2i(10, 9), true))
	var attackers: TerrainArmy = lab.opposing_army
	attackers.team_id = 9
	attackers.faction_id = 2
	attackers.roster_size = 2
	assert(attackers.deploy_at(data, null, null, [Vector2i(20, 18), Vector2i(21, 18)]) and attackers.enable_combat(false))
	attackers.set_process(false)
	attackers.settle_combat_command()
	assert(Settlement.capture_zone(data).has(Vector2i(20, 18)))
	assert(Settlement.advance_capture(lab, 59.0).is_empty())
	var fallen := Settlement.advance_capture(lab, 1.5)
	assert(fallen.ok, str(fallen))
	assert(int(data.site.settlement.owner_faction) == 2)
	assert(int(data.site.settlement.offices.revision) > int(request.revision))
	assert(int(SiteOffices.position(data.site.settlement.offices, seat).holder) == -1)
	var leader := int(SiteOffices.head_position(data.site.settlement.offices).holder)
	assert(leader == attackers.combat_identity(0))
	before = _border_state(data)
	revision = data.environment_revision
	assert(Settlement.set_ecology_modes(lab, holder, [key], "general", int(request.revision)).code == "STALE_OFFICE")
	assert(not Settlement.set_ecology_modes(lab, player, [key], "general").ok, "A captured jurisdiction cannot fall through to the old controlled person")
	assert(_border_state(data) == before and data.environment_revision == revision)
	assert(Settlement.ecology_authority(lab, key, leader).ok, "The original fit provisional head acts for the vacant ecology seat")
	assert(Settlement.set_ecology_modes(lab, leader, [key], "general").ok)
	loaded = _save_governance(lab, "fallen", key, base)
	lab.free()
	lab = _building_lab(loaded.data)
	before = _border_state(loaded.data)
	revision = loaded.data.environment_revision
	assert(Settlement.ecology_authority(lab, key, leader).ok)
	assert(not Settlement.ecology_authority(lab, key, holder).ok)
	assert(_border_state(loaded.data) == before and loaded.data.environment_revision == revision)
	lab.free()
	TerrainArmy.release_contact_source()
	assert(Time.get_ticks_msec() <= deadline)
	_governance_completed = true
	print("SITE_ECOLOGY_GOVERNANCE_ROUNDTRIP_PASS legacy_vacant_catalog_query_read_only=true appointed_and_fallen_file_roundtrip=true original_capture_timer=true stale_revision_and_foreign_requests_unchanged=true current_provisional_head_acts=true; no GPU, performance or all16ECO claim")
	quit(0)
