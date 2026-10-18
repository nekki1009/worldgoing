extends "res://scripts/tests/site_building_ui_test.gd"
## P4 S5c consumer test: TerrainLab.prepare_initial_resident_roster on a real building fixture.
## Covers: the success path (one work army on rest cells, housing relations, civilians), refusal with
## nothing created (bed shortage, wrong faction), idempotency, and no run on a non-initial state.

const ResidentRoster = preload("res://scripts/terrain_lab/site_resident_roster.gd")

func _row(name: String, faction: Variant, house: String) -> Dictionary:
	return {"name": name, "faction_id": faction, "house": house}

# Diagnostic only: every item id claimed by a holder anywhere in the state (a dictionary with holder and item_ids).
func _located(value: Variant, found: Dictionary) -> void:
	if value is Dictionary:
		if value.has("holder") and value.has("item_ids") and value.get("item_ids") is Array:
			for identity: Variant in value.item_ids: found[str(identity)] = str(value.holder)
		for key: Variant in value: _located(value[key], found)
	elif value is Array:
		for item: Variant in value: _located(item, found)

func _item_gap(state: Dictionary) -> Dictionary:
	var located := {}
	_located(state, located)
	var gap: Array = []
	for identity: Variant in state.item_records:
		if not located.has(str(identity)): gap.append({"id": str(identity), "holder": str(state.item_records[identity].get("holder", ""))})
	return {"records": state.item_records.size(), "located": located.size(), "gap": gap}

## The authored construction (site_runtime.gd prepare_author_building, ~14700-14740): _preview_build, then
## _building_feature_candidate, stage "complete", next_feature, and the settlement record for a centre.
## No work and no clock advance, unlike _complete_key (site_building_ui_test.gd:48, which runs Runtime.advance).
func _authored_complete(data: TerrainData, kind: String, anchor: Vector2i, extent: Vector2i, options: Dictionary) -> String:
	var settings := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	settings.merge(options, true)
	var placement: Dictionary = Runtime.building_cells(data, kind, anchor, extent, settings)
	assert(placement.ok, str(placement))
	var cells: Array[int] = []
	cells.assign(placement.cells)
	var preview: Dictionary = Runtime._preview_build(data, kind, cells, Callable(), settings, "", false)
	assert(preview.ok and preview.clearing.is_empty(), str(preview))
	var key := str(int(data.site.next_feature))
	var feature: Dictionary = Runtime._building_feature_candidate(kind, cells, preview)
	feature.stage = "complete"
	feature.progress = float(feature.work)
	feature.status = "作者初始完工"
	data.site.features[key] = feature
	data.site.next_feature = int(data.site.next_feature) + 1
	if kind == "settlement_center":
		data.site["settlement"] = {"version": SiteSettlement.VERSION, "settlement_id": "settlement_%s_%s" % [str(data.site.id).left(64), key], "center_id": key, "level": 1, "name": "初始聚落", "owner_faction": 1, "offices": SiteOffices.default_offices("settlement"), "fall_record": SiteSettlement.empty_fall_record()}
	Env.rebuild_indexes(data)
	return key

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	var data := _building_fixture()
	var house := _authored_complete(data, "house", Vector2i(34, 34), Vector2i.ONE, {"variant": "standard"})
	_authored_complete(data, "settlement_center", Vector2i(20, 20), Vector2i(5, 5), {})
	var layout: Dictionary = Runtime.house_layout(data, house)
	assert(layout.ok and int(layout.capacity) == 2, str(layout))
	# The fields the NOT_INITIAL_SCENARIO guard reads (terrain_lab.gd prepare_initial_resident_roster): housing, family,
	# crowd, captivity, minute, paused, combat_left. Existing armies are not among them and are not refused.
	var fixture_armies: Array = []
	for army: Variant in data.site.get("armies", []):
		fixture_armies.append({"team_id": army.get("team_id"), "role": army.get("role"), "units": army.get("units", []).size()})
	if OS.get_cmdline_user_args().has("--p4s5c-diag"):
		print("P4S5C_DIAG fixture: armies=%s housing=%d family=%s crowd=%s captivity=%d minute=%s paused=%s combat_left=%s" % [str(fixture_armies), data.site.get("housing", {}).size(), str(data.site.has("family")), str(data.site.has("crowd")), data.site.get("captivity", {}).size(), str(data.site.get("minute")), str(data.site.get("paused")), str(data.site.get("combat_left"))])
	assert(int(data.site.get("minute", -1)) == 0 and not bool(data.site.get("paused", true)) and float(data.site.get("combat_left", -1.0)) == 0.0, "Guard clock fields (minute, paused, combat_left) are fresh")
	assert(data.site.get("housing", {}).is_empty() and not data.site.has("family") and not data.site.has("crowd") and data.site.get("captivity", {}).is_empty(), "Guard housing, family, crowd and captivity fields are fresh")
	var existing_ids := {}
	for army: Variant in data.site.get("armies", []):
		for existing_unit: Variant in army.get("units", []): existing_ids[int(existing_unit.person_id)] = true
	for actor_key: Variant in data.site.get("actors", {}):
		existing_ids[int(data.site.actors[actor_key].person_id)] = true
	data.site["residents"] = [_row("甲", 1, house), _row("乙", 1.0, house)]
	# In-tree lab, as in play (see S5c_G). The production capture gives seeded records their location.
	var lab := _building_lab(data)
	var captured: Dictionary = lab.site_controller._capture_for_save()
	assert(captured.ok, "Production capture before the consumer: " + str(captured))
	var fixture_items: Dictionary = Store._validate_items(data, data.site)
	assert(fixture_items.ok, "Captured fixture item state is valid before the consumer: " + str(fixture_items))
	var diag := OS.get_cmdline_user_args().has("--p4s5c-diag")
	if diag: print("P4S5C_DIAG before: " + str(_item_gap(data.site)))

	# Bed shortage: three rows for a two-bed house refuse the whole roster; the input state is unchanged.
	data.site["residents"] = [_row("甲", 1, house), _row("乙", 1, house), _row("丙", 1, house)]
	var before_short: Dictionary = data.site.duplicate(true)
	var short := lab.prepare_initial_resident_roster(data)
	assert(not short.ok and str(short.code) == "NO_BEDS", str(short))
	assert(data.site == before_short, "Bed-shortage refusal changes nothing")

	# Wrong faction refuses the whole roster too.
	data.site["residents"] = [_row("甲", 2, house)]
	var before_foreign: Dictionary = data.site.duplicate(true)
	var foreign := lab.prepare_initial_resident_roster(data)
	assert(not foreign.ok and str(foreign.code) == "RESIDENT_FACTION", str(foreign))
	assert(data.site == before_foreign, "Foreign refusal changes nothing")

	# Success: one work army of two civilians on the house rest cells; the existing armies and housing are kept.
	data.site["residents"] = [_row("甲", 1, house), _row("乙", 1.0, house)]
	var before_success: Dictionary = data.site.duplicate(true)
	var born := lab.prepare_initial_resident_roster(data)
	assert(born.ok and bool(born.changed) and int(born.count) == 2, str(born))
	assert(data.site == before_success, "The input state is never changed")
	var candidate: TerrainData = born.data
	if diag: print("P4S5C_DIAG after: " + str(_item_gap(candidate.site)))
	assert(candidate.site.item_records.size() == data.site.item_records.size(), "Residents create no equipment records at birth")
	var armies_before: int = before_success.get("armies", []).size()
	var housing_before: int = before_success.get("housing", {}).size()
	var armies: Array = candidate.site.armies
	assert(armies.size() == armies_before + 1, "Exactly one resident work army is added")
	for index: int in armies_before:
		assert(armies[index] == before_success.armies[index], "Existing army %d is kept unchanged" % index)
	var team: Dictionary = armies[armies.size() - 1]
	assert(str(team.get("role", "")) == "work", "Residents are a work army, not a combat army")
	assert(int(team.get("faction_id", -1)) == 1, "Army faction is the settlement owner")
	for index: int in armies_before:
		assert(int(armies[index].get("team_id", 0)) != int(team.get("team_id", -1)), "Resident team id is unique")
	var units: Array = team.get("units", [])
	assert(units.size() == 2, str(units.size()))
	assert(int(candidate.site.get("army_next_team", 1)) == int(team.get("team_id", 0)) + 1, "Team counter advanced")
	var slot_set := {}
	for slot: Variant in layout.slots: slot_set[int(slot)] = true
	var housing: Dictionary = candidate.site.get("housing", {})
	assert(housing.size() == housing_before + 2, str(housing))
	var cells := {}
	for unit: Dictionary in units:
		assert(str(unit.get("military_role", "")) == "civilian", "Residents are civilians")
		assert(not existing_ids.has(int(unit.person_id)), "Resident ids do not reuse an existing person id")
		var relation: Variant = housing.get(str(int(unit.person_id)), {})
		assert(relation is Dictionary and str(relation.get("house_id", "")) == house, "Each resident is housed in the assigned house")
		var cell: int = int(relation.get("cell", -1))
		assert(slot_set.has(cell) and not cells.has(cell), "Each resident has its own rest cell")
		cells[cell] = true

	# Unarmed: no resident holds an item or shows an equipment part without a record. The reconcile is the
	# game's own projection, SiteRuntime.equipment_appearance (site_store.gd _validate_army_assets calls it the same way).
	var equipment_slots: Array = Runtime.EQUIPMENT_SLOTS
	for unit: Dictionary in units:
		var holder: Dictionary = unit.get("item_state", {})
		var item_ids: Array = holder.get("item_ids", [0])
		var equipped: Dictionary = holder.get("equipped", {"x": 0})
		assert(item_ids.is_empty() and equipped.is_empty(), "Resident %d holds no items" % int(unit.person_id))
		var appearance: Dictionary = unit.get("appearance", {})
		var parts: Dictionary = appearance.get("parts", {})
		for slot: Variant in equipment_slots:
			assert(str(parts.get(str(slot), "")) == "none", "Resident %d shows no %s part" % [int(unit.person_id), str(slot)])
		assert(not appearance.has("equipment_dyes"), "Resident %d has no equipment dye" % int(unit.person_id))
		var reconciled: Dictionary = Runtime.equipment_appearance(candidate, holder, appearance)
		assert(not reconciled.is_empty() and reconciled == appearance, "Resident %d appearance equals the item reconcile" % int(unit.person_id))

	# Idempotent: the candidate already holds the resident army, so nothing new is created.
	var again := lab.prepare_initial_resident_roster(candidate)
	assert(again.ok and not bool(again.changed), str(again))
	assert(candidate.site.armies.size() == armies_before + 1, "Second run creates no second army")

	# Housing with no resident army refuses (the guard's housing field), and creates nothing.
	var later := TerrainData.new()
	later.site = {"residents": [_row("甲", 1, house)], "armies": [{"role": "combat", "units": []}], "housing": {"9": {"version": 1, "house_id": house, "cell": 0}}}
	var refused := lab.prepare_initial_resident_roster(later)
	assert(not refused.ok and str(refused.code) == "NOT_INITIAL_SCENARIO", str(refused))

	# No rows: nothing to do and nothing changed.
	var empty_data := TerrainData.new()
	empty_data.site = {"residents": []}
	var nothing := lab.prepare_initial_resident_roster(empty_data)
	assert(nothing.ok and not bool(nothing.changed), str(nothing))
	assert(ResidentRoster.valid_state(candidate.site), "Candidate roster stays valid")
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_RESIDENT_BIRTH_PASS: residents=%d existing_armies=%d" % [units.size(), armies_before])
	quit(0)
