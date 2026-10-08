extends "res://scripts/tests/site_ship_repair_test.gd"
## Receipt-only original Runtime contract. Initial hull fixture is explicit;
## this is not boarding, navigation or full Site roundtrip acceptance.

func _check_atomic(value: bool, name: String) -> bool:
	if value: return true
	push_error("SITE_SHIP_REPAIR_ATOMIC_FAIL: " + name)
	run_completed = true
	quit(1)
	return false

func _run() -> void:
	if not _fatal_receipt(): return
	if not _facility_receipts(): return
	TerrainArmy.release_contact_source()
	run_completed = true
	print("SITE_SHIP_REPAIR_ATOMIC_PASS")
	quit(0)

func _atomic_start(data: TerrainData, identity: String, feature_id: String) -> bool:
	var result: Dictionary = Runtime.request_ship_repair(data, identity, feature_id, 1, false, _q(data))
	return _check_atomic(result.ok, "ORIGINAL_START " + identity + ": " + str(result))

func _atomic_work(data: TerrainData, identity: String, ratio: float) -> bool:
	var vehicle: Dictionary = data.site.vehicles[identity]
	var stations: Array[Dictionary] = Runtime.ship_repair_work_slots(data, vehicle)
	if not _check_atomic(not stations.is_empty(), "ORIGINAL_STATION " + identity): return false
	var station: Dictionary = stations[0]
	var result: Dictionary = Runtime.advance_ship_repair_work(data, identity,
		float(vehicle.naval.repair.total_work) * ratio, data.cell_from_index(int(station.cell)), int(station.slot), 1)
	return _check_atomic(result.ok, "ORIGINAL_WORK " + identity + ": " + str(result))

func _remaining(vehicle: Dictionary, cost: Dictionary, ratio: float, name: String) -> bool:
	for resource: String in cost:
		if not _check_atomic(int(vehicle.cargo.get(resource, 0)) == int(cost[resource]) - ceili(float(cost[resource]) * ratio), name + " " + resource): return false
	return true

func _fatal_receipt() -> bool:
	var fixture: Dictionary = _repair_fixture()
	var data: TerrainData = fixture.data
	var vehicle: Dictionary = fixture.vehicle
	var cargo_alias: Dictionary = vehicle.cargo
	var holder_alias: Dictionary = vehicle.holder
	if not _atomic_start(data, "1", str(fixture.feature_id)): return false
	var cost: Dictionary = vehicle.naval.repair.paid_cost.duplicate()
	if not _atomic_work(data, "1", 0.001): return false
	var depot: Dictionary = data.site.inventory.duplicate()
	var version: int = int(vehicle.holder.version)
	var result: Dictionary = Runtime.damage_ship_vehicle(data, "1", 100000.0)
	if not _check_atomic(result.ok and float(vehicle.naval.hp) == 0.0 and str(vehicle.naval.state) == "sinking", "FATAL_ORIGINAL_HP " + str(result)): return false
	if not _check_atomic(vehicle.naval.repair.is_empty() and int(vehicle.holder.version) == version + 1, "FATAL_SYNCHRONOUS_RECEIPT"): return false
	if not _remaining(vehicle, cost, 0.001, "FATAL_CEIL_ONCE"): return false
	if not _check_atomic(data.site.inventory == depot and is_same(cargo_alias, vehicle.cargo) and is_same(holder_alias, vehicle.holder), "FATAL_ORIGINAL_CARGO_HOLDER_NO_REFUND"): return false
	# The actual strict Store naval branch must accept immediately after damage,
	# before Transport wreck tick. This test does not claim a full Site roundtrip.
	result = Store._validate_ship_naval(data, data.site, vehicle)
	if not _check_atomic(result.ok, "IMMEDIATE_STRICT_STORE_NAVAL " + str(result)): return false
	var before: PackedByteArray = var_to_bytes(data.site)
	result = Runtime.settle_ship_repair_damage(data, "1")
	if not _check_atomic(result.ok and before == var_to_bytes(data.site), "LATER_WRECK_NO_DOUBLE_CHARGE"): return false
	print("FATAL_REPAIR_ATOMIC_PASS")
	return true

func _facility_receipts() -> bool:
	var fixture: Dictionary = _repair_fixture()
	var data: TerrainData = fixture.data
	var feature_id: String = str(fixture.feature_id)
	# Explicit second original hull fixture: disjoint authorized water footprint,
	# opposite side contact with the same original completed shipyard.
	var second: Dictionary = Ships.make_record("2", 1, "ferry", data.index(Vector2i(28, 33)), Vector2i.RIGHT)
	second.naval.hp = Ships.hull_hp("ferry") * 0.5
	data.site.vehicles["2"] = second
	data.site.next_vehicle = 3
	var first: Dictionary = fixture.vehicle
	var occupied: Array[Vector2i] = Ships.footprint("ferry", data.cell_from_index(int(first.cell)), Vector2i.LEFT)
	for cell: Vector2i in Ships.footprint("ferry", Vector2i(28, 33), Vector2i.RIGHT):
		if not _check_atomic(not occupied.has(cell) and data.can_navigate_water(cell), "SECOND_HULL_DISJOINT_KNOWN_WATER"): return false
	if not _atomic_start(data, "1", feature_id) or not _atomic_start(data, "2", feature_id): return false
	var first_cost: Dictionary = first.naval.repair.paid_cost.duplicate()
	var second_cost: Dictionary = second.naval.repair.paid_cost.duplicate()
	if not _atomic_work(data, "1", 0.25) or not _atomic_work(data, "2", 0.35): return false
	# Corrupt receipt fixture proves the all-receipt preflight, then restore the
	# exact original value and commit real damage once; no failed retry is hidden.
	var applied: float = float(second.naval.repair.applied)
	second.naval.repair.applied = applied + 1.0
	var before: PackedByteArray = var_to_bytes(data.site)
	var result: Dictionary = Runtime.damage_structure_part(data, feature_id, "body", 100000.0)
	if not _check_atomic(not result.ok and var_to_bytes(data.site) == before, "ALL_RECEIPTS_PREFLIGHT_NO_PARTIAL_COMMIT"): return false
	second.naval.repair.applied = applied
	var depot: Dictionary = data.site.inventory.duplicate()
	var first_hp: float = float(first.naval.hp)
	var second_hp: float = float(second.naval.hp)
	result = Runtime.damage_structure_part(data, feature_id, "body", 100000.0)
	if not _check_atomic(result.ok and not Runtime.feature_usable(data.site.features[feature_id]), "FACILITY_ORIGINAL_DESTRUCTION " + str(result)): return false
	if not _check_atomic(first.naval.repair.is_empty() and second.naval.repair.is_empty(), "FACILITY_ALL_RECEIPTS_RELEASED"): return false
	if not _remaining(first, first_cost, 0.25, "FACILITY_FIRST_REMAINDER") or not _remaining(second, second_cost, 0.35, "FACILITY_SECOND_REMAINDER"): return false
	if not _check_atomic(data.site.inventory == depot and float(first.naval.hp) == first_hp and float(second.naval.hp) == second_hp, "FACILITY_NO_REFUND_NO_EXTRA_HP"): return false
	if not _check_atomic(Runtime.validate_ship_repair(data, first).ok and Runtime.validate_ship_repair(data, second).ok, "FACILITY_STRICT_RECEIPT_FREE"): return false
	before = var_to_bytes(data.site)
	result = Runtime.request_ship_repair(data, "1", feature_id, 1, false, _q(data))
	if not _check_atomic(not result.ok and var_to_bytes(data.site) == before, "DESTROYED_FACILITY_REJECTS_NEW_RECEIPT"): return false
	print("FACILITY_REPAIR_ATOMIC_PASS")
	return true
