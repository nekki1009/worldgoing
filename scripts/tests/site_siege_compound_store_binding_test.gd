extends SceneTree

const INPUT = "res://scripts/tests/fixtures/cc095b_rejected_army.variant"
var failed: bool = false
var checks: int = 0

func _initialize() -> void:
	var decoded: Variant = str_to_var(FileAccess.get_file_as_string(INPUT))
	if not _check(decoded is Dictionary, "the original typed diagnostic parses without JSON coercion"): quit(1); return
	var fixture: Dictionary = decoded
	var data: TerrainData = TerrainData.new()
	data.allocate(fixture.map_size)
	data.height_levels.fill(2)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	var state: Dictionary = {"vehicles": fixture.vehicles, "item_records": fixture.item_records, "item_definitions": fixture.item_definitions, "corps": fixture.corps}
	data.site = state
	var team: Dictionary = fixture.team
	_check(team.units[1].has(&"duration") and typeof(team.units[1].duration) == TYPE_FLOAT, "retain StringName keys and float duration")
	_check(TerrainArmy.valid_saved_siege_compound(team, data, state.vehicles["1"]), "the real four-person2s compound proves its complete binding")
	_check(TerrainArmy.valid_combat_state(team, data, fixture.actor, state), "the original Army validator accepts the real snapshot with the bound duration")
	var crew: Dictionary = {3: true, 4: true, 5: true, 6: true}
	_check(SiteStore._valid_combat_movement_snapshot(data, team, {}, crew, state), "the four genuine independent crew tails retain one original compound batch")
	_check(not SiteStore._valid_combat_movement_snapshot(data, team, {}, crew), "ordinary validation without the original vehicle proof still rejects four tails")
	var registered: Dictionary = fixture.duplicate(true)
	registered.vehicles["1"].move.formation_id = 77
	var registered_state: Dictionary = {"vehicles": registered.vehicles, "item_records": registered.item_records, "item_definitions": registered.item_definitions, "corps": registered.corps}
	_check(TerrainArmy.valid_saved_siege_compound(registered.team, data, registered.vehicles["1"]), "runtime formation77 can belong to durable team1")
	_check(TerrainArmy.valid_combat_state(registered.team, data, registered.actor, registered_state), "Army retains independent runtime formation IDs")
	_check(SiteStore._valid_combat_movement_snapshot(data, registered.team, {}, crew, registered_state), "Store binds the actual batch rather than equating runtime and team IDs")
	for kind: String in ["duration", "coherent_duration", "crew", "vehicle", "team", "compound", "formation", "deployment_formation", "serial", "progress", "from", "to", "row_duration", "curve", "lease", "slot", "duplicate", "batch"]:
		var bad: Dictionary = fixture.duplicate(true)
		var vehicle: Dictionary = bad.vehicles["1"]
		match kind:
			"duration": vehicle.move.duration = 3.0
			"coherent_duration":
				vehicle.move.duration = 3.0
				for index: int in range(1, 5): bad.team.units[index].duration = 3.0
			"crew": vehicle.crew_slots["0"] = 99
			"vehicle": vehicle.move.vehicle_id = "2"
			"team": vehicle.team_id = 2
			"compound": vehicle.move.compound_id = "siege:2:13"
			"formation": vehicle.move.formation_id = 0
			"deployment_formation": bad.team.combat_deployment_plan = {"formation_id": 2, "member_slot_map": {}, "slot_lease_owner_map": {}}
			"serial": vehicle.move.formation_serial = 1
			"progress": bad.team.units[2].progress += 0.01
			"from": vehicle.move.participants[0].from += 1
			"to": vehicle.move.participants[0].to += 1
			"row_duration": bad.team.units[1].duration = TerrainArmy.MOVE_DURATION
			"curve": bad.team.units[1].move_curve = "legacy_smoothstep"
			"lease": bad.team.combat_deployment_plan = {"member_slot_map": {}, "slot_lease_owner_map": {"42,41": 3}}
			"slot": vehicle.move.participants[0].slot = "1"
			"duplicate": vehicle.move.participants[1].person_id = 3
			"batch": bad.team.combat_batch_move_members.erase(3)
		_check(not TerrainArmy.valid_saved_siege_compound(bad.team, data, vehicle), "reject forged compound binding: " + kind)
		var bad_state: Dictionary = {"vehicles": bad.vehicles, "item_records": bad.item_records, "item_definitions": bad.item_definitions, "corps": bad.corps}
		_check(not TerrainArmy.valid_combat_state(bad.team, data, bad.actor, bad_state), "full Army rejection stays active: " + kind)
		_check(not SiteStore._valid_combat_movement_snapshot(data, bad.team, {}, crew, bad_state), "batch binding also rejects corruption: " + kind)
	var ordinary: Dictionary = team.duplicate(true)
	for row: Dictionary in ordinary.units: row.duration = TerrainArmy.MOVE_DURATION
	_check(TerrainArmy.valid_combat_state(ordinary, data, fixture.actor), "ordinary row duration behavior is unchanged without a vehicle claim")
	ordinary.units[1].duration = 2.0
	_check(not TerrainArmy.valid_combat_state(ordinary, data, fixture.actor), "an ordinary row cannot borrow a free2s duration")
	print("CC095B_COMPOUND_BINDING ", "FAIL" if failed else "PASS", " checks=", checks)
	quit(1 if failed else 0)

func _check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failed = true
		push_error("CC095B_COMPOUND_BINDING: " + label)
	return condition
