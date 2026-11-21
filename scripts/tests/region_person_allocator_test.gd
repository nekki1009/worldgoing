extends SceneTree
## Pure identity/range contracts; no disk, SceneTree owners, or fake bind receipts.
var failures: Array[String] = []
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func source_record(id: int, alias: String, owner: String) -> Dictionary:
	var aliases: Dictionary = {}
	if not alias.is_empty(): aliases[alias] = id
	return {"projection": {"bodies": [{"id": id, "alias": alias}], "aliases": aliases, "next_person_id": id + 1}, "location": {"kind": "site", "id": owner}}

func _initialize() -> void:
	var empty: Dictionary = RegionSaveSlot.person_allocator_empty("world")
	var before: PackedByteArray = var_to_bytes(empty)
	var first: Dictionary = RegionSaveSlot.person_range(empty, 2)
	check(first.ok and first.ids == [1, 2] and first.allocator.next_person_id == 3, "initial contiguous range")
	check(var_to_bytes(empty) == before, "range never mutates input")
	var edge: Dictionary = empty.duplicate(true)
	edge.next_person_id = 999999999
	var endpoint: Dictionary = RegionSaveSlot.person_range(edge, 1)
	check(endpoint.ok and endpoint.ids == [999999999] and endpoint.allocator.next_person_id == 1000000001, "reserved endpoint normalized")
	var crossing: Dictionary = RegionSaveSlot.person_range(edge, 2)
	check(crossing.ok and crossing.ids == [1000000001, 1000000002], "reserved crossing skips whole range")
	var after: Dictionary = RegionSaveSlot.person_range(endpoint.allocator, 1)
	check(after.ok and after.ids == [1000000001], "allocation after reserved boundary remains valid")
	var zero: Dictionary = RegionSaveSlot.person_range(empty, 0)
	check(zero.ok and zero.ids.is_empty() and zero.allocator == empty, "zero allocation")
	var negative: Dictionary = RegionSaveSlot.person_range(empty, -1)
	check(not negative.ok and var_to_bytes(empty) == before, "negative allocation atomic refusal")
	var oversized: Dictionary = RegionSaveSlot.person_range(empty, 9223372036854775807)
	check(not oversized.ok and var_to_bytes(empty) == before, "oversized count refuses before arithmetic or iteration")
	edge.next_person_id = 2147483646
	var last: Dictionary = RegionSaveSlot.person_range(edge, 1)
	var exhausted: Dictionary = RegionSaveSlot.person_range(last.allocator, 1)
	check(last.ok and last.ids == [2147483646] and not exhausted.ok, "31-bit exhaustion")
	var alias: String = RegionTravel.stable_key({"type": "person", "namespace": "original:site-b", "lineage": 4})
	var a: Dictionary = source_record(1, "", "site-a")
	var b: Dictionary = source_record(2, alias, "site-b")
	var inputs: Array = [a, b]
	var source_before: PackedByteArray = var_to_bytes(inputs)
	var migrated: Dictionary = RegionSaveSlot.person_migration("world", inputs)
	check(migrated.ok and migrated.allocator.locations.size() == 2 and migrated.allocator.aliases[alias] == 2, "legacy disjoint local IDs preserve numbers and real typed aliases")
	check(var_to_bytes(inputs) == source_before, "migration does not rewrite legacy sources")
	var collision: Dictionary = RegionSaveSlot.person_migration("world", [a, source_record(1, alias, "site-b")])
	check(not collision.ok and collision.code == "PERSON_ID_COLLISION" and var_to_bytes(inputs) == source_before, "same number at two current owners refuses upgrade only")
	var remapped: Dictionary = RegionSaveSlot.person_migration("world", [source_record(3, alias, "site-c")], migrated.allocator)
	check(not remapped.ok and remapped.code == "PERSON_ID_REMAP_REQUIRED", "known person cannot change number while moving")
	var history: Dictionary = {"projection": {"bodies": [], "aliases": {}, "next_person_id": 100}, "location": {"kind": "party", "id": "old-party"}}
	history.projection.aliases[alias] = 99
	var historical: Dictionary = RegionSaveSlot.person_migration("world", [b, history], migrated.allocator)
	check(historical.ok and historical.allocator.aliases[alias] == 2 and historical.allocator.locations["2"].id == "site-b", "historical local number never replaces current body or alias")
	var pending: Dictionary = b.duplicate(true)
	pending.projection.pending_remap = true
	var refused: Dictionary = RegionSaveSlot.person_migration("world", [pending])
	check(not refused.ok and refused.code == "PERSON_MIGRATION_PENDING", "legacy pending renumbering refuses upgrade")
	var malformed: Dictionary = a.duplicate(true)
	malformed.projection.next_person_id = 1.5
	var invalid: Dictionary = RegionSaveSlot.person_migration("world", [malformed])
	check(not invalid.ok, "fractional counter refused without truncation")
	invalid = RegionSaveSlot.person_migration("world", [false])
	check(not invalid.ok, "malformed source fails explicitly")
	var slot: RegionSaveSlot = RegionSaveSlot.new()
	slot.pin = {"world_instance_id": "world"}
	slot._person_pending = migrated.allocator.duplicate(true)
	slot._person_generation = 0
	slot._person_scope = "scope-world"
	slot._person_nonce = "nonce-world"
	var known: Dictionary = slot.resolve_person_reference({"world_instance_id": "world", "person_id": 2})
	var unknown: Dictionary = slot.resolve_person_reference({"world_instance_id": "world", "person_id": 999})
	check(known.ok and known.status == "current" and known.typed_ref.lineage == 4, "canonical ref resolves original typed lineage")
	check(not unknown.ok and unknown.code == "UNKNOWN_PERSON_REF", "unknown canonical ref never succeeds")
	slot._person_pending.locations.erase("2")
	var historic_ref: Dictionary = slot.resolve_person_reference({"world_instance_id": "world", "person_id": 2})
	check(historic_ref.ok and historic_ref.status == "historical" and historic_ref.location.is_empty(), "historical alias explicitly has no body owner")
	var foreign: Dictionary = slot.resolve_person_reference({"world_instance_id": "another-world", "person_id": 2})
	check(not foreign.ok and foreign.code == "INVALID_PERSON_REF", "same number from another world is not this person")
	var checkpoint: Dictionary = slot.person_allocation_checkpoint()
	slot._person_allocation_owners.append("other-lab")
	var rolled: bool = slot.rollback_person_allocation(checkpoint, ["this-lab"])
	check(not rolled, "rollback cannot discard another Lab reservation")
	print("REGION_PERSON_ALLOCATOR_", "PASS" if failures.is_empty() else "FAILED", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
