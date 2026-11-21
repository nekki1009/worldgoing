extends "res://scripts/tests/site_boarding_contract_test.gd"
## B4S2 (plan line 86): a death in a link-gated channel records the real channel point and the peer hull.
## Ordinary cross keeps the source-hull clamp. Unit scope: ship_death_location and the runtime loot rule.

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	if not _must(DisplayServer.get_name() == "headless", "B4S2_CANONICAL_HEADLESS"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for owner: TerrainArmy in lab.combat_armies: owner.set_process(false)
	if not _fixture() or not _cases_b4s2(): return
	print("SITE_BOARDING_B4S2_PASS: " + get_script().resource_path)
	await _cleanup(0)

## A cross job held at its end point (elapsed == duration, huge speed), so _ship_job_point is the path end.
func _job_b4s2(aboard: int, point: Vector2, link: bool) -> Dictionary:
	return {"kind": "ship_cross", "link_crossing": link, "executor_id": aboard, "vehicle_id": boat_id,
		"secondary_vehicle_id": enemy_boat, "path": [point, point], "elapsed": 1.0, "duration": 1.0,
		"speed": 1000.0, "terrain": lab.terrain, "site_state": lab.terrain.site, "cancelled": false}

func _cases_b4s2() -> bool:
	var vehicles: Variant = lab.site_controller.vehicles
	var actions: Variant = lab.site_controller.person_actions
	var aboard: int = people[0]
	if not _must(str(vehicles.ship_person(aboard).row.get("embarked_vehicle_id", "")) == boat_id, "B4S2_PREMISE_EMBARKED"): return false
	var vehicle: Dictionary = vehicles.records()[boat_id]
	var anchor: Vector2 = Vector2(lab.terrain.cell_from_index(int(vehicle.cell)))
	var facing := Vector2(int(vehicle.facing[0]), int(vehicle.facing[1]))
	var lateral := Vector2(-facing.y, facing.x)
	var point: Vector2 = anchor + lateral * -1.5 + facing * 1.0   # 1.5 cells off the source deck, within reach of the pair
	var spec := Ship.definition(str(vehicle.ship_type))
	var local: Vector2 = Ship.local_from_world(Vector2i(anchor), Vector2i(facing), point)
	var clamped: Vector2 = local.clamp(Vector2.ONE * -0.25, Vector2(float(spec.width) - 0.75, float(spec.length) - 0.75))
	if not _must(local.x < -0.25 and not local.is_equal_approx(clamped), "B4S2_PREMISE_OUTSIDE_DECK local=%s clamped=%s" % [str(local), str(clamped)]): return false

	# Link-gated: the channel descriptor keeps the real point and names the peer hull.
	actions._jobs[str(aboard)] = _job_b4s2(aboard, point, true)
	var channel: Dictionary = vehicles.ship_death_location(aboard)
	var got: Array = channel.get("channel_point", [])
	if not _must(got.size() == 2 and is_equal_approx(float(got[0]), point.x) and is_equal_approx(float(got[1]), point.y) and str(channel.get("peer_vehicle_id", "")) == enemy_boat, "B4S2_CHANNEL_DESCRIPTOR expected=%s actual=%s" % [str(point), str(channel)]): return false
	if not _must(Runtime.valid_ship_loot_location(lab.terrain, channel), "B4S2_RUNTIME_ACCEPTS_CHANNEL actual=" + str(channel)): return false

	# Ordinary cross: unchanged, clamped to the source deck.
	actions._jobs[str(aboard)] = _job_b4s2(aboard, point, false)
	var ordinary: Dictionary = vehicles.ship_death_location(aboard)
	var got_local: Array = ordinary.get("local_position", [])
	if not _must(got_local.size() == 2 and is_equal_approx(float(got_local[0]), clamped.x) and is_equal_approx(float(got_local[1]), clamped.y), "B4S2_ORDINARY_STILL_CLAMPED expected=%s actual=%s" % [str(clamped), str(got_local)]): return false
	actions._jobs.erase(str(aboard))
	return true
