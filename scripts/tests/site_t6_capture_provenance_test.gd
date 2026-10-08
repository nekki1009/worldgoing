extends "res://scripts/tests/site_siege_takeover_ai_contract_test.gd"
## Genuine original PA takeover/Army/Runtime engine ownership. This tests
## capture/schema/remap foundations only; analysis/phase/receipt and full
## save/load/native/UI close still require root's expanded original owners.
const CaptureStore = preload("res://scripts/terrain_lab/site_store.gd")
const Travel = preload("res://scripts/region_lab/region_travel.gd")

func _hostile_source() -> Dictionary:
	var context := _ballista_fixture(0)
	# Remove the original OWN engine by its real guard; create/pay an engine
	# under an actual distinct hostile Army instead of relabeling our build.
	context.vehicle.cargo.clear()
	assert(SiteRuntime.remove_siege_vehicle(context.data, context.key, 1).ok)
	var hostile := TerrainArmy.new()
	hostile.team_id = 2
	hostile.faction_id = 2
	hostile.roster_size = 3
	assert(hostile.deploy_at(context.data, null, null, [Vector2i(45, 40), Vector2i(46, 40), Vector2i(47, 40)]))
	assert(hostile.enable_combat(false))
	hostile.set_process(false)
	hostile.settle_combat_command()
	context.lab.combat_armies.append(hostile)
	hostile.vehicle_transport = context.controller.vehicles
	var built := SiteRuntime.begin_siege_build(context.data, "ballista", Vector2i(20, 20), Vector2i.RIGHT, hostile.team_id, hostile.combat_identity(0))
	assert(built.ok, str(built))
	var key := str(built.vehicle)
	var slot: Dictionary = SiteRuntime.siege_work_slots(context.data, context.data.site.vehicles[key])[0]
	# Same original Runtime construction fixture as the existing siege tests;
	# ordinary source-engine setup makes no individual research work receipt.
	assert(SiteRuntime.advance_siege_work(context.data, key, "construct", 5400.0, context.data.cell_from_index(int(slot.cell)), 0, hostile.team_id).ok)
	context.key = key
	context.vehicle = context.data.site.vehicles[key]
	context["hostile"] = hostile
	context["executor"] = context.fixture.army.combat_identity(1)
	context.data.set_meta(&"site_garrison_lab", weakref(context.lab))
	return context

func _close_hostile(context: Dictionary) -> void:
	context.lab.combat_armies.erase(context.hostile)
	context.hostile.vehicle_transport = null
	context.hostile.free()
	_close_ballista(context)

func _shape_valid(context: Dictionary, vehicle: Dictionary) -> bool:
	var result := CaptureStore._validate_siege_vehicle(context.data, context.data.site, context.key, vehicle, {}, {1: 3, 2: 3}, {}, {}, {}, false)
	return bool(result.ok)

func _check_original_hostile_receipt() -> void:
	var context := _hostile_source()
	var vehicle: Dictionary = context.vehicle
	assert(int(vehicle.team_id) == 2 and vehicle.technology_capture.is_empty())
	var original := vehicle.duplicate(true)
	var holder: Dictionary = vehicle.holder
	var cargo: Dictionary = vehicle.cargo
	assert(_begin_takeover(context).ok)
	assert(_settle_takeover(context, 9.99).is_empty())
	assert(vehicle.technology_capture.is_empty() and int(vehicle.team_id) == 2)
	var results := _settle_takeover(context, 0.01)
	assert(results.size() == 1 and results[0].ok and int(vehicle.team_id) == 1, str(results))
	var capture: Dictionary = vehicle.technology_capture
	assert(SiteRuntime.technology_capture_valid(capture, false) and int(vehicle.vehicle_version) == 3)
	assert(int(capture.source_team_id) == 2 and int(capture.source_faction) == 2 and int(capture.recipient_team_id) == 1 and int(capture.recipient_faction) == 1)
	assert(capture.vehicle == {"site_id": str(context.data.site.id), "vehicle_id": context.key})
	assert(capture.capture_id == JSON.stringify([str(context.data.site.id), context.key, int(holder.version)]))
	assert(is_same(vehicle.holder, holder) and is_same(vehicle.cargo, cargo))
	for field: String in ["id", "kind", "definition_version", "cell", "facing", "hp", "ever_hp_damaged", "cargo", "next_attack_seq", "rng_state"]:
		assert(vehicle[field] == original[field], field)
	assert(_shape_valid(context, vehicle))
	assert(context.controller.person_actions.settle_after_contacts().is_empty() and vehicle.technology_capture == capture)
	# JSON round trip exercises the actual original source shape validator,
	# not a complete Site save/load acceptance claim.
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(vehicle))
	assert(_shape_valid(context, decoded) and SiteRuntime.technology_capture_valid(decoded.technology_capture, false))
	for fault: String in ["missing", "same_faction", "tuple", "extra", "version"]:
		var bad: Dictionary = vehicle.duplicate(true)
		match fault:
			"missing": bad.erase("technology_capture")
			"same_faction": bad.technology_capture.source_faction = bad.technology_capture.recipient_faction
			"tuple": bad.technology_capture.capture_id = JSON.stringify([str(context.data.site.id), "different-engine", int(holder.version)])
			"extra": bad.technology_capture.fake_source = true
			"version": bad.vehicle_version = 4
		assert(not _shape_valid(context, bad), fault)
	# True historical field through the original Region remapper: local live ID
	# changes, provenance and nine-field analysis history retain their originals.
	var person_receipt := {"tech_id": "F11", "rules_version": 1, "original_work": 34200.0, "credited_work": 17100.0,
		"vehicle_id": JSON.stringify([str(capture.vehicle.site_id), str(capture.vehicle.vehicle_id)]), "capture_id": str(capture.capture_id),
		"family_id": "0123456789abcdef0123456789abcdef", "purpose": "F11:first", "project_id": 1}
	# This is a REMAP NEGATIVE input, not granted knowledge/analysis authority.
	var remapped: Dictionary = Travel._remap_current({"vehicle_id": context.key, "technology_capture": capture, "analysis": [person_receipt]}, {"vehicle": {context.key: "999"}})
	assert(remapped.vehicle_id == "999" and remapped.technology_capture == capture and remapped.analysis == [person_receipt])
	_close_hostile(context)

func _check_no_capture_inference() -> void:
	var neutral := _takeover_fixture()
	assert(_begin_takeover(neutral).ok)
	var results := _settle_takeover(neutral, 10.0)
	assert(results.size() == 1 and results[0].ok and neutral.vehicle.technology_capture.is_empty(), "Neutral original engine is usable without invented enemy history")
	_close_ballista(neutral)
	var direct := _hostile_source()
	var expected: Dictionary = direct.controller.person_actions._siege_takeover_snapshot(direct.vehicle)
	assert(SiteRuntime.takeover_siege(direct.data, direct.key, expected, 1).ok)
	assert(direct.vehicle.technology_capture.is_empty(), "A direct Runtime call lacks a completed original takeover job")
	_close_hostile(direct)
	var stale := _hostile_source()
	assert(_begin_takeover(stale).ok)
	assert(_settle_takeover(stale, 5.0).is_empty())
	stale.fixture.army.combat_units[1].hit_revision = int(stale.fixture.army.combat_units[1].get("hit_revision", 0)) + 1
	results = _settle_takeover(stale, 5.0)
	assert(results.size() == 1 and not results[0].ok and int(stale.vehicle.team_id) == 2 and stale.vehicle.technology_capture.is_empty())
	_close_hostile(stale)
	var legacy := _hostile_source()
	var raw: Dictionary = legacy.vehicle.duplicate(true)
	raw.vehicle_version = 2
	raw.erase("technology_capture")
	assert(_shape_valid(legacy, raw), "Exact legitimate v2 shape still loads")
	raw.technology_capture = {}
	assert(not _shape_valid(legacy, raw), "v2 must not carry a source field")
	_close_hostile(legacy)

func _run() -> void:
	create_timer(90.0).timeout.connect(func() -> void: quit(1))
	_check_original_hostile_receipt()
	_check_no_capture_inference()
	TerrainArmy.release_contact_source()
	print("SITE_T6_CAPTURE_PROVENANCE_PASS original paid hostile engine/actual two Army owners/real ten-action-second capture, source schema JSON and corrupt-field refusal, no neutral/direct/stale inference, old v2 boundary, immutable Region history; ANALYSIS/phase/receipt/full save/native/UI close separate")
	quit(0)
