extends "res://scripts/tests/site_building_runtime_contract_test.gd"

func _run() -> void:
	create_timer(45.0).timeout.connect(func() -> void: quit(1))
	_check_siege_build_lifecycle()
	_check_siege_repair_and_release()
	_check_siege_wreck_clear()
	_check_siege_original_workers()
	TerrainArmy.release_contact_source()
	assert(completed == 4, "A siege runtime contract stopped before completion")
	print("SITE_SIEGE_RUNTIME_CONTRACT_PASS: original vehicle construction/material conservation, four-way footprints, damaged cancellation, fixed repair budget, unique ammo release, owner-independent empty-wreck clearing with adjacency/occupancy/busy guards, and two original workers with distinct saved work slots; no GPU or performance claim")
	quit(0)

func _new_ballista(data: TerrainData, facing: Vector2i = Vector2i.RIGHT) -> String:
	var before := JSON.stringify(data.site)
	assert(SiteRuntime.begin_siege_build(data, "ballista", Vector2i(20, 20), facing, 1, 1, Callable(), true).ok)
	assert(JSON.stringify(data.site) == before, "Preview changed original materials or IDs")
	var result := SiteRuntime.begin_siege_build(data, "ballista", Vector2i(20, 20), facing, 1, 1)
	assert(result.ok, str(result))
	return str(result.vehicle)

func _finish_siege(data: TerrainData, key: String) -> void:
	var slot: Dictionary = SiteRuntime.siege_work_slots(data, data.site.vehicles[key])[0]
	assert(SiteRuntime.advance_siege_work(data, key, "construct", 5400.0, data.cell_from_index(int(slot.cell)), 0, 1).ok)
	assert(data.site.vehicles[key].build.is_empty() and str(data.site.vehicles[key].phase) == "idle")

func _check_siege_build_lifecycle() -> void:
	for facing: Vector2i in TerrainData.DIRECTIONS:
		var data := _fixture()
		var wood := int(data.site.inventory.wood)
		var key := _new_ballista(data, facing)
		var vehicle: Dictionary = data.site.vehicles[key]
		assert(int(data.site.inventory.wood) == wood - 24)
		assert(SiteRuntime.siege_cells(data, vehicle).size() == 6 and SiteRuntime.siege_work_slots(data, vehicle).size() == 4)
		var before := JSON.stringify(data.site)
		assert(not SiteRuntime.begin_siege_build(data, "ballista", Vector2i(20, 20), facing, 1, 1).ok)
		assert(JSON.stringify(data.site) == before, "Overlapping construction spent materials")
		assert(SiteRuntime.cancel_siege_job(data, key, 1).ok)
		assert(int(data.site.inventory.wood) == wood and data.site.vehicles.is_empty())
	var data := _fixture()
	var key := _new_ballista(data)
	var vehicle: Dictionary = data.site.vehicles[key]
	var slot: Dictionary = SiteRuntime.siege_work_slots(data, vehicle)[0]
	assert(SiteRuntime.advance_siege_work(data, key, "construct", 2700.0, data.cell_from_index(int(slot.cell)), 0, 1).ok)
	data.site.capacity = int(SiteRuntime.carried_load(data.site, data.site.inventory, data.site.depot_items))
	var before := JSON.stringify(data.site)
	assert(not SiteRuntime.cancel_siege_job(data, key, 1).ok)
	assert(JSON.stringify(data.site) == before, "Full depot cancellation partially committed")
	data.site.capacity = 100000
	assert(SiteRuntime.damage_siege_vehicle(data, key, 1.0).ok)
	var wood := int(data.site.inventory.wood)
	assert(SiteRuntime.cancel_siege_job(data, key, 1).ok)
	assert(int(data.site.inventory.wood) == wood, "Damaged construction refunded materials")
	completed += 1

func _check_siege_repair_and_release() -> void:
	var data := _fixture()
	var key := _new_ballista(data)
	_finish_siege(data, key)
	var vehicle: Dictionary = data.site.vehicles[key]
	assert(SiteRuntime.damage_siege_vehicle(data, key, 70.0).ok)
	vehicle.command = {"type": "stop", "reason": "ordered"}
	assert(SiteRuntime.request_siege_repair(data, key, 1).ok)
	assert(vehicle.command.is_empty(), "Stopped crew release must allow repair")
	assert(is_equal_approx(float(vehicle.repair.total_work), 675.0))
	var slot: Dictionary = SiteRuntime.siege_work_slots(data, vehicle)[0]
	var cell := data.cell_from_index(int(slot.cell))
	assert(SiteRuntime.advance_siege_work(data, key, "repair", 337.5, cell, 0, 1).ok)
	assert(is_equal_approx(float(vehicle.hp), 105.0))
	assert(SiteRuntime.damage_siege_vehicle(data, key, 20.0).ok)
	assert(SiteRuntime.advance_siege_work(data, key, "repair", 337.5, cell, 0, 1).ok)
	assert(is_equal_approx(float(vehicle.hp), 120.0) and vehicle.repair.is_empty(), "Repair healed new damage for free")
	vehicle.cargo.siege_bolt = 1
	var version := int(vehicle.holder.version)
	var before := JSON.stringify(data.site)
	assert(not SiteRuntime.release_siege_bolt(data, key, version + 1).ok)
	assert(JSON.stringify(data.site) == before)
	var shot := SiteRuntime.release_siege_bolt(data, key, version)
	assert(shot.ok and int(shot.seq) == 1 and int(vehicle.next_attack_seq) == 2)
	assert(int(vehicle.cargo.get("siege_bolt", 0)) == 0 and int(vehicle.holder.version) == version + 1)
	assert(not SiteRuntime.release_siege_bolt(data, key, version).ok and int(vehicle.next_attack_seq) == 2)
	vehicle.cargo.siege_bolt = 1
	assert(SiteRuntime.damage_siege_vehicle(data, key, 999.0).ok)
	assert(str(vehicle.phase) == "wrecked" and int(vehicle.cargo.siege_bolt) == 1)
	assert(not SiteRuntime.remove_siege_vehicle(data, key, 1).ok, "Wreck removal lost original cargo")
	vehicle.cargo.clear()
	vehicle.command = {"type": "stop", "reason": "released"}
	assert(SiteRuntime.remove_siege_vehicle(data, key, 1).ok and data.site.vehicles.is_empty())
	completed += 1

func _check_siege_wreck_clear() -> void:
	var data := _fixture()
	var key := _new_ballista(data)
	_finish_siege(data, key)
	var vehicle: Dictionary = data.site.vehicles[key]
	assert(SiteRuntime.damage_siege_vehicle(data, key, 999.0).ok)
	vehicle.team_id = 99999 # Wreck clearing cannot depend on a surviving original team.
	var edge := Vector2i(19, 20)
	var wood := int(data.site.inventory.wood)
	vehicle.cargo.siege_bolt = 1
	var before := JSON.stringify(data.site)
	assert(not SiteRuntime.clear_siege_wreck(data, key, edge).ok)
	assert(JSON.stringify(data.site) == before, "Loaded wreck clearing changed original cargo")
	vehicle.cargo.clear()
	for blocked_cell: Vector2i in [Vector2i(20, 20), Vector2i(10, 10)]:
		before = JSON.stringify(data.site)
		assert(not SiteRuntime.clear_siege_wreck(data, key, blocked_cell).ok)
		assert(JSON.stringify(data.site) == before, "Invalid worker location partially cleared wreck")
	before = JSON.stringify(data.site)
	assert(not SiteRuntime.clear_siege_wreck(data, key, edge, func(cell: Vector2i) -> bool: return cell == Vector2i(22, 21)).ok)
	assert(JSON.stringify(data.site) == before, "Occupied footprint partially cleared wreck")
	vehicle.stop_pending = true
	assert(not SiteRuntime.clear_siege_wreck(data, key, edge).ok)
	vehicle.stop_pending = false
	vehicle.crew_slots = {"0": 70001}
	assert(not SiteRuntime.clear_siege_wreck(data, key, edge).ok)
	vehicle.crew_slots.clear()
	vehicle.action = {"stage": "recovering"}
	assert(not SiteRuntime.clear_siege_wreck(data, key, edge).ok)
	vehicle.action.clear()
	assert(SiteRuntime.clear_siege_wreck(data, key, edge).ok and data.site.vehicles.is_empty())
	assert(int(data.site.inventory.wood) == wood, "Empty wreck clearing refunded original construction cost")
	completed += 1

func _check_siege_original_workers() -> void:
	var data := _fixture()
	var key := _new_ballista(data)
	var vehicle: Dictionary = data.site.vehicles[key]
	var slots := SiteRuntime.siege_work_slots(data, vehicle)
	var fixture := CrewFixture.new()
	# The actual commander must stay inside the original formation's presence
	# radius; a distant setup correctly loses dispatch authority before work.
	fixture.setup(root, data, [Vector2i(16, 20), data.cell_from_index(int(slots[0].cell)), data.cell_from_index(int(slots[1].cell))])
	fixture.crew.vehicle_blocked = func(cell: Vector2i) -> bool: return SiteRuntime.siege_cells(data, vehicle).has(cell)
	var ids: Array[int] = [fixture.army.combat_identity(1), fixture.army.combat_identity(2)]
	var assigned := fixture.crew.assign(fixture.army, ids, fixture.army.combat_identity(0))
	assert(assigned.ok, str({"assignment": assigned, "commander": fixture.army.current_commander,
		"order": fixture.army.combat_order, "ids": ids, "cells": fixture.army.cells,
		"moving_to": fixture.army.moving_to, "stations": slots}))
	var result := fixture.crew.advance(60.0)
	var first: Dictionary = fixture.army.combat_units[1].work_task
	var second: Dictionary = fixture.army.combat_units[2].work_task
	assert(result.handled_seconds.size() == 2 and float(vehicle.build.progress) > 0.0 and float(vehicle.build.progress) <= 120.0,
		str({"result": result, "build": vehicle.build, "first": first, "second": second,
			"cells": fixture.army.cells, "moving_to": fixture.army.moving_to, "stations": slots,
			"fatigue": PersonFatigue.read(fixture.army.combat_units[1])}))
	assert(first.target == "vehicle:" + key and second.target == first.target)
	assert(SiteRuntime.work_claim_key(first) != SiteRuntime.work_claim_key(second))
	assert(SiteWorkTeam.valid_task(data, data.site, first) and SiteWorkTeam.valid_task(data, data.site, second))
	var bad := first.duplicate(true)
	bad.work_cell = data.index(Vector2i(2, 2))
	assert(not SiteWorkTeam.valid_task(data, data.site, bad))
	vehicle.build.progress = float(vehicle.build.total_work) - 1.0
	fixture.crew.advance(10.0)
	assert(vehicle.build.is_empty() and first.target == "" and second.target == "", "Completed work left stale saved worker references")
	fixture.close()
	completed += 1
