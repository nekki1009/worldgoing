extends RefCounted
## Stateless capability checks. Only the original Slot owns staged snapshots.
const Registry = preload("res://scripts/region_lab/region_organization_registry.gd")
const FIELDS = ["nonce", "slot_instance_id", "lab_instance_id", "data_instance_id", "folder", "generation", "pin"]

static func authenticate(ticket: Variant, expected: Dictionary) -> Dictionary:
	if expected.is_empty(): return {"ok": false, "code": "ORGANIZATION_STAGE_CLOSED"}
	if not ticket is Dictionary or ticket.size() != FIELDS.size() or expected.size() != FIELDS.size(): return {"ok": false, "code": "ORGANIZATION_STAGE_TOKEN"}
	for field: String in FIELDS:
		if not ticket.has(field) or not expected.has(field): return {"ok": false, "code": "ORGANIZATION_STAGE_TOKEN"}
	if not ticket.nonce is String or ticket.nonce.is_empty() or not ticket.folder is String or ticket.folder.is_empty() or not ticket.pin is Dictionary or not RegionSaveSlot._same_pin(ticket.pin, ticket.pin): return {"ok": false, "code": "ORGANIZATION_STAGE_TOKEN"}
	for field: String in ["slot_instance_id", "lab_instance_id", "data_instance_id"]:
		if not ticket[field] is int or int(ticket[field]) == 0: return {"ok": false, "code": "ORGANIZATION_STAGE_TOKEN"}
	if not ticket.generation is int or int(ticket.generation) < 1: return {"ok": false, "code": "ORGANIZATION_STAGE_TOKEN"}
	return {"ok": true} if Registry.same(ticket, expected) else {"ok": false, "code": "ORGANIZATION_STAGE_TOKEN"}

static func guard(ticket: Variant, expected: Dictionary, current: Dictionary) -> Dictionary:
	var admitted: Dictionary = authenticate(ticket, expected)
	if not admitted.ok: return admitted
	if current.size() != FIELDS.size() - 1: return {"ok": false, "code": "ORGANIZATION_STAGE_STALE"}
	for field: String in FIELDS:
		if field == "nonce": continue
		if not current.has(field) or not Registry.same(expected[field], current[field]): return {"ok": false, "code": "ORGANIZATION_STAGE_STALE"}
	return {"ok": true}
