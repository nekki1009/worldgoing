extends SceneTree
const Stage = preload("res://scripts/region_lab/region_organization_stage.gd")
var failures: Array[String] = []
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	# Pure metadata only; these values never stand in for actual Lab receipts.
	var pin: Dictionary = {"format": 1, "world_instance_id": "world", "slot_id": "main", "atlas_id": RegionSaveSlot.Grid.ATLAS_ID, "base_revision": "base", "manifest_sha256": "a".repeat(64), "ramp_rule_revision": "ramp", "grid_contract_version": 1}
	var ticket: Dictionary = {"nonce": "one-capability", "slot_instance_id": 1, "lab_instance_id": 2, "data_instance_id": 3, "folder": "slot/a", "generation": 4, "pin": pin}
	var current: Dictionary = ticket.duplicate(true)
	current.erase("nonce")
	var before: PackedByteArray = var_to_bytes([ticket, current])
	var admitted: Dictionary = Stage.guard(ticket.duplicate(true), ticket, current)
	check(admitted.ok, "Exact capability and scope metadata pass pure admission")
	var signed_ids: Dictionary = ticket.duplicate(true)
	signed_ids.slot_instance_id = -101
	signed_ids.data_instance_id = -103
	var signed_current: Dictionary = signed_ids.duplicate(true)
	signed_current.erase("nonce")
	var signed_result: Dictionary = Stage.guard(signed_ids, signed_ids, signed_current)
	check(signed_result.ok, "Nonzero signed original instance IDs remain exact identities")
	var zero_id: Dictionary = signed_ids.duplicate(true)
	zero_id.data_instance_id = 0
	var zero_result: Dictionary = Stage.authenticate(zero_id, zero_id)
	check(not zero_result.ok, "Zero is never an admitted original instance ID")
	var malformed: Dictionary = Stage.authenticate("not-a-ticket", ticket)
	check(not malformed.ok and malformed.code == "ORGANIZATION_STAGE_TOKEN", "Malformed capability fails without property access")
	var closed: Dictionary = Stage.authenticate(ticket, {})
	check(not closed.ok and closed.code == "ORGANIZATION_STAGE_CLOSED", "Missing stage has an explicit closed state")
	for field: String in ["nonce", "slot_instance_id", "lab_instance_id", "data_instance_id", "folder", "generation", "pin"]:
		var changed: Dictionary = ticket.duplicate(true)
		if field == "pin": changed.pin.base_revision = "foreign-base"
		elif changed[field] is int: changed[field] = int(changed[field]) + 1
		else: changed[field] = str(changed[field]) + "-different"
		var rejected: Dictionary = Stage.authenticate(changed, ticket)
		check(not rejected.ok, "Changed capability field refuses: " + field)
	var extra: Dictionary = ticket.duplicate(true)
	extra["activation_ready"] = true
	var extra_result: Dictionary = Stage.authenticate(extra, ticket)
	check(not extra_result.ok, "Caller-supplied readiness cannot extend the capability")
	for field: String in current:
		var changed: Dictionary = current.duplicate(true)
		if field == "pin": changed.pin.world_instance_id = "another-world"
		elif changed[field] is int: changed[field] = int(changed[field]) + 1
		else: changed[field] = str(changed[field]) + "-different"
		var stale: Dictionary = Stage.guard(ticket, ticket, changed)
		check(not stale.ok and stale.code == "ORGANIZATION_STAGE_STALE", "Original scope change refuses: " + field)
		var cleanup: Dictionary = Stage.authenticate(ticket, ticket)
		check(cleanup.ok, "Exact capability still authenticates cleanup after stale scope: " + field)
	var fractional: Dictionary = ticket.duplicate(true)
	fractional.generation = 4.0
	var numeric: Dictionary = Stage.authenticate(fractional, ticket)
	check(not numeric.ok, "Capability keeps integer metadata types")
	check(var_to_bytes([ticket, current]) == before, "All checks preserve input and expected capability bytes")
	print("REGION_ORGANIZATION_STAGE_", "PASS" if failures.is_empty() else "FAILED", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
