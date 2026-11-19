extends RefCounted
## R5 S1: designated heir data for one owner. Pure: no authority and no holder changes. The caller resolves
## authority (the head executor) and passes the live seat ids, members and an aliveness check.

const VERSION := 1

static func empty_record() -> Dictionary:
	return {"version": VERSION, "heirs": {}}

static func _whole(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) \
		and float(value) >= float(low) and float(value) <= float(high)

## Strict shape: exactly version and heirs; every heir keys a live head seat and names a current member.
static func valid_record(raw: Variant, seat_ids: Array, members: Dictionary) -> bool:
	if not raw is Dictionary or raw.size() != 2 or not raw.has("version") or not raw.has("heirs") or not raw.heirs is Dictionary:
		return false
	if not _whole(raw.version, VERSION, VERSION): return false
	for seat_id: Variant in raw.heirs:
		if not seat_id is String or not seat_ids.has(seat_id): return false
		var person: Variant = raw.heirs[seat_id]
		if not _whole(person, 1, 2147483646) or not members.has(int(person)): return false
	return true

## Designation rules: the seat must be a live head seat, the person a current member and alive, and not the seated head.
static func designate(record: Dictionary, seat_id: String, person_id: int, seat_ids: Array, members: Dictionary, head_holder: int, alive: Callable) -> Dictionary:
	if not valid_record(record, seat_ids, members): return {"ok": false, "code": "CORRUPT_STATE"}
	if not seat_ids.has(seat_id) or not members.has(person_id) or not alive.is_valid() or not bool(alive.call(person_id)):
		return {"ok": false, "code": "NO_TARGET"}
	if person_id == head_holder: return {"ok": false, "code": "DUPLICATE_HOLDER"}
	var candidate: Dictionary = record.duplicate(true)
	candidate.heirs[seat_id] = person_id
	if not valid_record(candidate, seat_ids, members): return {"ok": false, "code": "CORRUPT_STATE"}
	return {"ok": true, "code": "", "record": candidate}

## JSON numbers load as floats; restore exact integers after validation.
static func normalize_numbers(record: Dictionary) -> void:
	record["version"] = int(record.version)
	for seat_id: String in record.heirs:
		record.heirs[seat_id] = int(record.heirs[seat_id])
